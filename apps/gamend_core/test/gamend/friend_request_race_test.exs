defmodule Gamend.FriendRequestRaceTest do
  @moduledoc """
  A friend request answered twice at once: accepted and rejected, accepted
  and blocked, accepted and cancelled, accepted twice; and one player
  accepting more requests at once than their friend cap allows.

  Every answer read the request through the cache and wrote its status by id
  with no condition, so the last write won: an accept wrote "accepted" over a
  block, an accept and a reject both told the requester, and an accept after
  a cancel updated a deleted row and raised. The cap was counted per pair, so
  accepts by one player to several others each counted the others as not
  there yet.

  Postgres shows these reliably; see `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Friends
  alias Gamend.Friends.Friendship
  alias Gamend.Notifications.Notification

  @pairs 12

  setup do
    pairs = unboxed(fn -> for _ <- 1..@pairs, do: requested_pair() end)
    track(Enum.flat_map(pairs, fn %{requester: r, target: t} -> [r.id, t.id] end))
    %{pairs: pairs}
  end

  test "an accept and a reject: one answer stands, and the requester hears only that one",
       %{pairs: pairs} do
    results =
      pairs
      |> Enum.flat_map(fn %{request: f, target: target} ->
        [
          fn -> Friends.accept_friend_request(f.id, target) end,
          fn -> Friends.reject_friend_request(f.id, target) end
        ]
      end)
      |> race()
      |> Enum.chunk_every(2)

    for {%{request: f, requester: requester}, [accepted, rejected] = both} <-
          Enum.zip(pairs, results) do
      refute Enum.any?(both, &match?({:raised, _}, &1)), "raised: #{inspect(both)}"
      assert Enum.count(both, &match?({:ok, _}, &1)) == 1, "both answers won: #{inspect(both)}"

      told = notification_types(requester.id) -- ["friend_request"]

      case {accepted, rejected} do
        {{:ok, _}, {:error, :not_pending}} ->
          assert status(f.id) == "accepted"
          assert told == ["friend_accepted"]

        {{:error, :not_pending}, {:ok, _}} ->
          assert status(f.id) == "rejected"
          assert told == ["friend_rejected"]

        other ->
          flunk("unexpected outcome: #{inspect(other)}")
      end
    end
  end

  test "a block and an accept: an accept never writes over the block", %{pairs: pairs} do
    results =
      pairs
      |> Enum.with_index()
      |> Enum.flat_map(fn {%{request: f, requester: requester, target: target}, i} ->
        # Half block the request from its target's other tab, half block the
        # target from the requester's side (which deletes the request).
        block =
          if rem(i, 2) == 0,
            do: fn -> Friends.block_friend_request(f.id, target) end,
            else: fn -> Friends.block_user(requester, target.id) end

        [block, fn -> Friends.accept_friend_request(f.id, target) end]
      end)
      |> race()
      |> Enum.chunk_every(2)

    for {%{requester: requester, target: target}, [blocked, accepted] = both} <-
          Enum.zip(pairs, results) do
      refute Enum.any?(both, &match?({:raised, _}, &1)), "raised: #{inspect(both)}"

      case blocked do
        # A block that answered ok is what stands, whichever way the accept went.
        {:ok, _} ->
          assert pair_status?(requester.id, target.id, "blocked")
          refute pair_status?(requester.id, target.id, "accepted"), "the block was written over"

        # Only a block of the request itself can lose: the accept was first.
        {:error, :not_pending} ->
          assert {:ok, _} = accepted
          assert pair_status?(requester.id, target.id, "accepted")
      end
    end
  end

  test "a cancel and an accept: one wins, and nothing raises", %{pairs: pairs} do
    results =
      pairs
      |> Enum.flat_map(fn %{request: f, requester: requester, target: target} ->
        [
          fn -> Friends.cancel_request(f.id, requester) end,
          fn -> Friends.accept_friend_request(f.id, target) end
        ]
      end)
      |> race()
      |> Enum.chunk_every(2)

    for {%{request: f}, [cancelled, accepted] = both} <- Enum.zip(pairs, results) do
      refute Enum.any?(both, &match?({:raised, _}, &1)), "raised: #{inspect(both)}"

      case {cancelled, accepted} do
        {{:ok, :cancelled}, {:error, :not_found}} -> assert status(f.id) == nil
        {{:error, :not_pending}, {:ok, _}} -> assert status(f.id) == "accepted"
        other -> flunk("unexpected outcome: #{inspect(other)}")
      end
    end
  end

  test "two accepts of one request: one is the friendship, the other is told so",
       %{pairs: pairs} do
    results =
      pairs
      |> Enum.flat_map(fn %{request: f, target: target} ->
        [
          fn -> Friends.accept_friend_request(f.id, target) end,
          fn -> Friends.accept_friend_request(f.id, target) end
        ]
      end)
      |> race()
      |> Enum.chunk_every(2)

    for {%{request: f}, both} <- Enum.zip(pairs, results) do
      refute Enum.any?(both, &match?({:raised, _}, &1)), "raised: #{inspect(both)}"
      assert Enum.count(both, &match?({:ok, _}, &1)) == 1, "both accepts won: #{inspect(both)}"
      assert Enum.count(both, &match?({:error, :already_friends}, &1)) == 1
      assert status(f.id) == "accepted"
    end
  end

  describe "the friend cap" do
    setup do
      previous = Application.get_env(:gamend_core, Gamend.Limits, [])
      Gamend.SettingsHelpers.put(:gamend_core, Gamend.Limits, :max_friends_per_user, 2)
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.Limits, previous) end)
    end

    test "a player accepting many requests at once ends at the cap" do
      player = unboxed(fn -> AccountsFixtures.user_fixture() end)
      others = unboxed(fn -> for _ <- 1..6, do: AccountsFixtures.user_fixture() end)
      track([player.id | Enum.map(others, & &1.id)])

      requests =
        unboxed(fn ->
          for other <- others do
            {:ok, f} = Friends.create_request(other, player.id)
            f
          end
        end)

      results =
        race(
          Enum.map(requests, fn f -> fn -> Friends.accept_friend_request(f.id, player) end end)
        )

      refute Enum.any?(results, &match?({:raised, _}, &1)), "raised: #{inspect(results)}"
      assert Enum.count(results, &match?({:ok, _}, &1)) == 2
      assert Enum.count(results, &match?({:error, :too_many_friends}, &1)) == 4
      assert unboxed(fn -> Friends.count_friends_for_user(player.id) end) == 2
    end
  end

  defp requested_pair do
    requester = AccountsFixtures.user_fixture()
    target = AccountsFixtures.user_fixture()
    {:ok, request} = Friends.create_request(requester, target.id)
    %{requester: requester, target: target, request: request}
  end

  # Users go last: their friendships and notifications go with them.
  defp track(user_ids) do
    cleanup(fn -> Repo.delete_all(from u in User, where: u.id in ^user_ids) end)
  end

  defp status(friendship_id) do
    unboxed(fn ->
      Repo.one(from f in Friendship, where: f.id == ^friendship_id, select: f.status)
    end)
  end

  defp pair_status?(a, b, status) do
    unboxed(fn ->
      Repo.exists?(
        from f in Friendship,
          where:
            f.status == ^status and
              ((f.requester_id == ^a and f.target_id == ^b) or
                 (f.requester_id == ^b and f.target_id == ^a))
      )
    end)
  end

  defp notification_types(recipient_id) do
    unboxed(fn ->
      from(n in Notification, where: n.recipient_id == ^recipient_id, select: n.metadata)
      |> Repo.all()
      |> Enum.map(& &1["type"])
      |> Enum.sort()
    end)
  end
end
