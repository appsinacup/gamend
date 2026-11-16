defmodule Gamend.FriendsTest do
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Friends

  describe "friendship flows" do
    setup do
      a = AccountsFixtures.user_fixture()
      b = AccountsFixtures.user_fixture()

      %{a: a, b: b}
    end

    test "send request, accept, list friends", %{a: a, b: b} do
      assert {:ok, f} = Friends.create_request(a.id, b.id)
      assert f.status == "pending"

      # accept as b
      assert {:ok, accepted} = Friends.accept_friend_request(f.id, b)
      assert accepted.status == "accepted"

      friends_a = Friends.list_friends_for_user(a.id)
      friends_b = Friends.list_friends_for_user(b.id)

      assert Enum.any?(friends_a, &(&1.id == b.id))
      assert Enum.any?(friends_b, &(&1.id == a.id))
      # count helper should reflect 1 friend for each
      assert Friends.count_friends_for_user(a.id) == 1
      assert Friends.count_friends_for_user(b.id) == 1
    end

    test "cannot friend yourself", %{a: a} do
      assert {:error, :cannot_friend_self} = Friends.create_request(a.id, a.id)
    end

    test "duplicate request succeeds idempotently", %{a: a, b: b} do
      assert {:ok, f1} = Friends.create_request(a.id, b.id)
      assert {:ok, f2} = Friends.create_request(a.id, b.id)
      assert f1.id == f2.id
    end

    test "reverse request auto-accepts if reverse pending", %{a: a, b: b} do
      # a -> b pending
      {:ok, _f} = Friends.create_request(a.id, b.id)

      # b -> a should accept the existing pending request
      {:ok, accepted} = Friends.create_request(b.id, a.id)
      assert accepted.status == "accepted"
      assert Enum.any?(Friends.list_friends_for_user(a.id), &(&1.id == b.id))
    end

    test "reject and cancel flows", %{a: a, b: b} do
      {:ok, f} = Friends.create_request(a.id, b.id)

      # reject by target
      {:ok, _} = Friends.reject_friend_request(f.id, b)

      # now no friends
      refute Enum.any?(Friends.list_friends_for_user(a.id), &(&1.id == b.id))

      # new request then canceled
      {:ok, f2} = Friends.create_request(a.id, b.id)
      assert {:ok, :cancelled} = Friends.cancel_request(f2.id, a)
    end

    test "remove accepted friendship", %{a: a, b: b} do
      {:ok, f} = Friends.create_request(a.id, b.id)
      {:ok, _} = Friends.accept_friend_request(f.id, b)

      # remove friend by user a
      assert {:ok, _} = Friends.remove_friend(a.id, b.id)
      refute Enum.any?(Friends.list_friends_for_user(a.id), &(&1.id == b.id))
    end
  end

  describe "blocking flows and pubsub" do
    setup do
      a = AccountsFixtures.user_fixture()
      b = AccountsFixtures.user_fixture()

      %{a: a, b: b}
    end

    test "target can block incoming request, it's listed and broadcasts to topics", %{a: a, b: b} do
      {:ok, f} = Friends.create_request(a.id, b.id)

      # subscribe to per-user and global topics
      Phoenix.PubSub.subscribe(Gamend.PubSub, "friends:user:#{a.id}")
      Phoenix.PubSub.subscribe(Gamend.PubSub, "friends:user:#{b.id}")
      Phoenix.PubSub.subscribe(Gamend.PubSub, "friends")

      assert {:ok, blocked} = Friends.block_friend_request(f.id, b)
      assert blocked.status == "blocked"

      # list blocked for b should include the blocked friendship
      blocked_list = Friends.list_blocked_for_user(b.id)
      assert Enum.any?(blocked_list, &(&1.id == blocked.id))

      # should receive broadcasts on the subscribed topics
      blocked_id = blocked.id
      assert_receive {:friend_blocked, %Friends.Friendship{id: ^blocked_id}}
      assert_receive {:friend_blocked, %Friends.Friendship{id: ^blocked_id}}
      assert_receive {:friend_blocked, %Friends.Friendship{id: ^blocked_id}}
    end

    test "cannot send request when blocked", %{a: a, b: b} do
      {:ok, f} = Friends.create_request(a.id, b.id)
      {:ok, _blocked} = Friends.block_friend_request(f.id, b)

      # now a should not be able to send new request to b
      assert {:error, :blocked} = Friends.create_request(a.id, b.id)
    end

    test "target can unblock and broadcasts friend_unblocked and removes row", %{a: a, b: b} do
      {:ok, f} = Friends.create_request(a.id, b.id)
      {:ok, blocked} = Friends.block_friend_request(f.id, b)

      # subscribe
      Phoenix.PubSub.subscribe(Gamend.PubSub, "friends:user:#{a.id}")
      Phoenix.PubSub.subscribe(Gamend.PubSub, "friends:user:#{b.id}")
      Phoenix.PubSub.subscribe(Gamend.PubSub, "friends")

      # only the block target (b) may unblock
      assert {:error, :not_authorized} = Friends.unblock_friendship(blocked.id, a)

      # unblock as b
      assert {:ok, :unblocked} = Friends.unblock_friendship(blocked.id, b)

      # friendship should be removed from DB
      assert Repo.get(Friends.Friendship, blocked.id) == nil

      # should receive friend_unblocked broadcasts
      bid = blocked.id
      assert_receive {:friend_unblocked, %Friends.Friendship{id: ^bid}}
      assert_receive {:friend_unblocked, %Friends.Friendship{id: ^bid}}
      assert_receive {:friend_unblocked, %Friends.Friendship{id: ^bid}}
    end
  end

  describe "blacklisting arbitrary users" do
    setup do
      a = AccountsFixtures.user_fixture()
      b = AccountsFixtures.user_fixture()

      %{a: a, b: b}
    end

    test "block with no prior friendship", %{a: a, b: b} do
      assert {:ok, f} = Friends.block_user(a, b.id)
      assert f.status == "blocked"

      assert Friends.blocked?(a.id, b.id)
      assert Friends.blocked?(b.id, a.id)

      # the blocker is the target, so the block shows on a's list
      assert [%{requester_id: requester_id}] = Friends.list_blocked_for_user(a.id)
      assert requester_id == b.id
      assert Friends.list_blocked_for_user(b.id) == []
    end

    test "cannot block yourself", %{a: a} do
      assert {:error, :cannot_block_self} = Friends.block_user(a, a.id)
    end

    test "blocking supersedes an existing friendship in either direction", %{a: a, b: b} do
      {:ok, f} = Friends.create_request(a.id, b.id)
      {:ok, _} = Friends.accept_friend_request(f.id, b)
      assert Friends.friends?(a.id, b.id)

      # a blocks b, though the existing row runs a -> b
      assert {:ok, _} = Friends.block_user(a, b.id)

      refute Friends.friends?(a.id, b.id)
      assert Friends.blocked?(a.id, b.id)

      # exactly one row survives for the pair
      assert Repo.aggregate(Friends.Friendship, :count) == 1
    end

    test "blocking twice is idempotent", %{a: a, b: b} do
      assert {:ok, f1} = Friends.block_user(a, b.id)
      assert {:ok, f2} = Friends.block_user(a, b.id)

      assert f1.id == f2.id
      assert Repo.aggregate(Friends.Friendship, :count) == 1
    end

    test "unblock removes the block", %{a: a, b: b} do
      {:ok, _} = Friends.block_user(a, b.id)

      # only the blocker can lift it
      assert {:error, :not_found} = Friends.unblock_user(b, a.id)

      assert {:ok, :unblocked} = Friends.unblock_user(a, b.id)
      refute Friends.blocked?(a.id, b.id)
    end

    test "unblock without a block is not_found", %{a: a, b: b} do
      assert {:error, :not_found} = Friends.unblock_user(a, b.id)
    end

    test "any_blocked?/2 checks both directions", %{a: a, b: b} do
      c = AccountsFixtures.user_fixture()

      {:ok, _} = Friends.block_user(a, b.id)

      # a blocked b, so it holds looking from either side
      assert Friends.any_blocked?(b.id, [c.id, a.id])
      assert Friends.any_blocked?(a.id, [c.id, b.id])

      refute Friends.any_blocked?(c.id, [a.id, b.id])
      refute Friends.any_blocked?(a.id, [])
      refute Friends.any_blocked?(a.id, [a.id])
    end

    test "blocked_pairs/1 returns order-independent keys", %{a: a, b: b} do
      c = AccountsFixtures.user_fixture()
      {:ok, _} = Friends.block_user(a, b.id)

      pairs = Friends.blocked_pairs([a.id, b.id, c.id])

      assert MapSet.member?(pairs, Friends.pair_key(a.id, b.id))
      assert MapSet.member?(pairs, Friends.pair_key(b.id, a.id))
      refute MapSet.member?(pairs, Friends.pair_key(a.id, c.id))

      # a pair is only reported when both users are in the queried set
      assert Friends.blocked_pairs([a.id, c.id]) |> MapSet.size() == 0
    end
  end
end
