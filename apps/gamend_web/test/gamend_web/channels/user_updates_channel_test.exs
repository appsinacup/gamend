defmodule GamendWeb.UserChannelTest do
  use ExUnit.Case
  import Phoenix.ChannelTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias GamendWeb.Auth.Guardian

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)
    :ok
  end

  @endpoint GamendWeb.Endpoint

  # A write's broadcasts reach the channel before the write returns, so once
  # the channel has answered a call every push they cause has been sent.
  defp settle(socket), do: :sys.get_state(socket.channel_pid)

  test "user channel receives updated event when leaving clears lobby_id" do
    user = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, _socket} = subscribe_and_join(socket, "user:#{user.id}", %{})

    assert_push "updated", initial_payload
    assert initial_payload.id == user.id
    assert initial_payload.lobby_id == ""

    {:ok, lobby} =
      Gamend.Lobbies.create_lobby(%{title: "user-updates-leave-room", hostless: true})

    assert {:ok, joined_user} = Gamend.Lobbies.join_lobby(user, lobby.id)

    assert_push "updated", joined_payload
    assert joined_payload.id == user.id
    assert joined_payload.lobby_id == lobby.id

    assert {:ok, _} = Gamend.Lobbies.leave_lobby(joined_user)

    assert_push "updated", left_payload
    assert left_payload.id == user.id
    assert left_payload.lobby_id == ""
  end

  test "join allowed for owner and receives broadcasts" do
    user = AccountsFixtures.user_fixture()
    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    # verify connect assigned a current_scope (user auto-loaded)
    assert Map.has_key?(socket.assigns, :current_scope)
    assert socket.assigns.current_scope.user_id == user.id
    {:ok, _, _socket} = subscribe_and_join(socket, "user:#{user.id}", %{})
    assert_push "updated", _initial_payload

    payload =
      user.id
      |> Gamend.Accounts.get_user!()
      |> Map.put(:metadata, %{"display_name" => "Updated"})
      |> Gamend.Accounts.serialize_user_payload()

    GamendWeb.endpoint().broadcast("user:#{user.id}", "updated", payload)

    # The test process receives the push
    assert_push "updated", pushed_payload
    assert pushed_payload.id == user.id
    assert pushed_payload.metadata == %{"display_name" => "Updated"}
  end

  test "user channel sends the full metadata on update" do
    user = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, user} =
      Gamend.Accounts.update_user(user, %{
        metadata: %{
          "word_match" => %{
            to_string(user.id) => %{"points" => 10, "streak" => 2}
          },
          "invalid_until" => 500
        }
      })

    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, _socket} = subscribe_and_join(socket, "user:#{user.id}", %{})

    assert_push "updated", %{metadata: initial_metadata}
    assert initial_metadata["invalid_until"] == 500

    {:ok, _updated_user} =
      Gamend.Accounts.update_user(user, %{
        metadata: %{
          "word_match" => %{
            to_string(user.id) => %{"points" => 12, "streak" => 3}
          }
        }
      })

    # Full payload: the new metadata whole, with the dropped invalid_until absent.
    assert_push "updated", payload

    assert payload.metadata == %{
             "word_match" => %{
               to_string(user.id) => %{"points" => 12, "streak" => 3}
             }
           }
  end

  test "user channel receives friend events for create & accept flows" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    {:ok, token_b, _} = Guardian.encode_and_sign(b)

    {:ok, socket_a} = connect(GamendWeb.UserSocket, %{"token" => token_a})
    {:ok, socket_b} = connect(GamendWeb.UserSocket, %{"token" => token_b})

    {:ok, _, _socket_a} = subscribe_and_join(socket_a, "user:#{a.id}", %{})
    {:ok, _, _socket_b} = subscribe_and_join(socket_b, "user:#{b.id}", %{})

    # create request a -> b
    assert {:ok, f} = Gamend.Friends.create_request(a.id, b.id)

    expected = %{
      id: f.id,
      requester_id: f.requester_id,
      target_id: f.target_id,
      status: f.status
    }

    # both requester and target should receive channel pushes for outgoing/incoming
    assert_push "outgoing_request", ^expected
    assert_push "incoming_request", ^expected

    # accept as b
    assert {:ok, accepted} = Gamend.Friends.accept_friend_request(f.id, b)

    expected_acc = %{
      id: accepted.id,
      requester_id: accepted.requester_id,
      target_id: accepted.target_id,
      status: accepted.status
    }

    # both users get friend_accepted
    assert_push "friend_accepted", ^expected_acc
    assert_push "friend_accepted", ^expected_acc
  end

  test "user channel receives friend events for reject and cancel flows" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    {:ok, token_b, _} = Guardian.encode_and_sign(b)

    {:ok, socket_a} = connect(GamendWeb.UserSocket, %{"token" => token_a})
    {:ok, socket_b} = connect(GamendWeb.UserSocket, %{"token" => token_b})

    {:ok, _, _socket_a} = subscribe_and_join(socket_a, "user:#{a.id}", %{})
    {:ok, _, _socket_b} = subscribe_and_join(socket_b, "user:#{b.id}", %{})

    # create request a -> b
    assert {:ok, f} = Gamend.Friends.create_request(a.id, b.id)

    # reject as b
    assert {:ok, rejected} = Gamend.Friends.reject_friend_request(f.id, b)

    expected_rej = %{
      id: rejected.id,
      requester_id: rejected.requester_id,
      target_id: rejected.target_id,
      status: rejected.status
    }

    assert_push "friend_rejected", ^expected_rej
    assert_push "friend_rejected", ^expected_rej

    # create a new request then cancel as requester
    {:ok, f2} = Gamend.Friends.create_request(a.id, b.id)
    assert {:ok, :cancelled} = Gamend.Friends.cancel_request(f2.id, a)

    expected_cancel = %{
      id: f2.id,
      requester_id: f2.requester_id,
      target_id: f2.target_id,
      status: f2.status
    }

    assert_push "request_cancelled", ^expected_cancel
    assert_push "request_cancelled", ^expected_cancel
  end

  test "user channel receives friend_blocked, unblocked and removed events" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    {:ok, token_b, _} = Guardian.encode_and_sign(b)

    {:ok, socket_a} = connect(GamendWeb.UserSocket, %{"token" => token_a})
    {:ok, socket_b} = connect(GamendWeb.UserSocket, %{"token" => token_b})

    {:ok, _, _socket_a} = subscribe_and_join(socket_a, "user:#{a.id}", %{})
    {:ok, _, _socket_b} = subscribe_and_join(socket_b, "user:#{b.id}", %{})

    # a -> b then block as b
    {:ok, f} = Gamend.Friends.create_request(a.id, b.id)
    assert {:ok, blocked} = Gamend.Friends.block_friend_request(f.id, b)

    expected_block = %{
      id: blocked.id,
      requester_id: blocked.requester_id,
      target_id: blocked.target_id,
      status: blocked.status
    }

    assert_push "friend_blocked", ^expected_block
    assert_push "friend_blocked", ^expected_block

    # unblock as b
    assert {:ok, :unblocked} = Gamend.Friends.unblock_friendship(blocked.id, b)
    # The original blocked record is deleted during unblock, but unblock_friendship broadcasts
    # a friend_unblocked event with the friendship that was removed
    assert_push "friend_unblocked", ^expected_block
    assert_push "friend_unblocked", ^expected_block

    # create accepted friend and then remove
    {:ok, f2} = Gamend.Friends.create_request(a.id, b.id)
    {:ok, accepted} = Gamend.Friends.accept_friend_request(f2.id, b)

    assert {:ok, _} = Gamend.Friends.remove_friend(a.id, b.id)

    expected_removed = %{
      id: accepted.id,
      requester_id: accepted.requester_id,
      target_id: accepted.target_id,
      status: accepted.status
    }

    assert_push "friend_removed", ^expected_removed
    assert_push "friend_removed", ^expected_removed
  end

  test "join rejected for another user" do
    user = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    {:ok, token2, _} = Guardian.encode_and_sign(other)

    {:ok, socket2} = connect(GamendWeb.UserSocket, %{"token" => token2})

    # the channel logs a warning when an unauthorized join is attempted; capture
    # that log in the test so it doesn't show up as noisy output
    ExUnit.CaptureLog.capture_log(fn ->
      assert {:error, _} = subscribe_and_join(socket2, "user:#{user.id}", %{})
    end)
  end

  test "user channel receives updated event when linking a provider" do
    # Create a user with a password and google_id (so we can link another provider)
    user = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, token, _} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, _socket} = subscribe_and_join(socket, "user:#{user.id}", %{})

    # Link discord provider to the user
    {:ok, updated_user} =
      Gamend.Accounts.link_account(
        user,
        %{discord_id: "123456789"},
        :discord_id,
        &User.discord_oauth_changeset/2
      )

    # Should receive updated event
    assert_push "updated", payload
    assert payload.id == updated_user.id
  end

  test "user channel receives updated event when unlinking a provider" do
    # Create a user then add multiple providers so we can unlink one
    user = AccountsFixtures.user_fixture()

    # Use link_account to add providers
    {:ok, user} =
      Gamend.Accounts.link_account(
        user,
        %{google_id: "google123"},
        :google_id,
        &User.google_oauth_changeset/2
      )

    {:ok, user} =
      Gamend.Accounts.link_account(
        user,
        %{discord_id: "discord456"},
        :discord_id,
        &User.discord_oauth_changeset/2
      )

    {:ok, token, _} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, _socket} = subscribe_and_join(socket, "user:#{user.id}", %{})

    # Unlink discord provider
    {:ok, updated_user} = Gamend.Accounts.unlink_provider(user, :discord)

    # Should receive updated event
    assert_push "updated", payload
    assert payload.id == updated_user.id
  end

  test "user channel sets is_online on join and broadcasts friend_updated to friends" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    # Make a and b friends
    {:ok, f} = Gamend.Friends.create_request(a.id, b.id)
    {:ok, _} = Gamend.Friends.accept_friend_request(f.id, b)

    # User b joins their channel first (to listen for friend_updated from a)
    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    {:ok, socket_b} = connect(GamendWeb.UserSocket, %{"token" => token_b})
    {:ok, _, _socket_b} = subscribe_and_join(socket_b, "user:#{b.id}", %{})

    assert_push "updated", _b_initial
    assert_push "friend_updated", b_initial_friends
    assert b_initial_friends.friends[to_string(a.id)].is_online == false

    # User a joins — triggers set_user_online + friend_updated broadcast
    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    {:ok, socket_a} = connect(GamendWeb.UserSocket, %{"token" => token_a})
    {:ok, _, _socket_a} = subscribe_and_join(socket_a, "user:#{a.id}", %{})

    # a should receive their own "updated" with is_online: true
    assert_push "updated", a_payload
    assert a_payload.id == a.id
    assert a_payload.is_online == true

    assert_push "friend_updated", friend_payload
    assert friend_payload.friends[to_string(a.id)].is_online == true

    # Verify DB state
    refreshed_a = Gamend.Accounts.get_user!(a.id)
    assert refreshed_a.is_online == true
    assert refreshed_a.last_seen_at != nil
  end

  test "user channel broadcasts offline friend_updated to friends on disconnect" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, f} = Gamend.Friends.create_request(a.id, b.id)
    {:ok, _} = Gamend.Friends.accept_friend_request(f.id, b)

    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    {:ok, socket_b} = connect(GamendWeb.UserSocket, %{"token" => token_b})
    {:ok, _, _socket_b} = subscribe_and_join(socket_b, "user:#{b.id}", %{})

    assert_push "updated", _b_initial
    assert_push "friend_updated", b_initial_friends
    assert b_initial_friends.friends[to_string(a.id)].is_online == false

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    {:ok, socket_a} = connect(GamendWeb.UserSocket, %{"token" => token_a})
    {:ok, _, socket_a} = subscribe_and_join(socket_a, "user:#{a.id}", %{})

    assert_push "updated", %{id: a_id, is_online: true}
    assert a_id == a.id

    friend_key = to_string(a.id)

    assert_receive %Phoenix.Socket.Message{
                     event: "friend_updated",
                     payload: %{friends: %{^friend_key => online_payload}}
                   },
                   1000

    assert online_payload.is_online == true
    # A presence-only broadcast still carries the whole friend object — the
    # client can store it directly without losing name/metadata.
    assert online_payload.user_id == a.id
    assert Map.has_key?(online_payload, :display_name)
    assert Map.has_key?(online_payload, :metadata)

    Process.unlink(socket_a.channel_pid)
    :ok = close(socket_a)

    assert_receive %Phoenix.Socket.Message{
                     event: "friend_updated",
                     payload: %{friends: %{^friend_key => offline_payload}}
                   },
                   1000

    assert offline_payload.is_online == false
  end

  test "user channel sends accepted friends in initial friend_updated on join" do
    user = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    friend = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    pending = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, friend} =
      Gamend.Accounts.update_user(friend, %{
        metadata: %{"map_country_id" => "ro", "map_city_id" => "sighetu-marmatiei"}
      })

    {:ok, accepted} = Gamend.Friends.create_request(user.id, friend.id)
    {:ok, _} = Gamend.Friends.accept_friend_request(accepted.id, friend)
    {:ok, _pending} = Gamend.Friends.create_request(user.id, pending.id)

    {:ok, token, _} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, _socket} = subscribe_and_join(socket, "user:#{user.id}", %{})

    assert_push "updated", _initial
    assert_push "friend_updated", payload

    assert [friend_key] = Map.keys(payload.friends)
    assert friend_key == to_string(friend.id)
    friend_payload = payload.friends[friend_key]
    assert friend_payload.user_id == friend.id
    assert friend_payload.friendship_id == accepted.id

    assert friend_payload.metadata == %{
             "map_country_id" => "ro",
             "map_city_id" => "sighetu-marmatiei"
           }

    refute Map.has_key?(payload.friends, to_string(pending.id))
  end

  test "user channel broadcasts friend_updated to accepted friends" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, f} = Gamend.Friends.create_request(a.id, b.id)
    {:ok, _} = Gamend.Friends.accept_friend_request(f.id, b)

    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    {:ok, socket_b} = connect(GamendWeb.UserSocket, %{"token" => token_b})
    {:ok, _, _socket_b} = subscribe_and_join(socket_b, "user:#{b.id}", %{})

    assert_push "updated", _b_initial
    assert_push "friend_updated", _b_initial_friends

    {:ok, _updated_a} =
      Gamend.Accounts.update_user(a, %{
        metadata: %{"map_country_id" => "ro", "map_city_id" => "sighetu-marmatiei"}
      })

    assert_push "friend_updated", payload, 1000
    friend_payload = payload.friends[to_string(a.id)]

    assert friend_payload.metadata == %{
             "map_country_id" => "ro",
             "map_city_id" => "sighetu-marmatiei"
           }
  end

  test "friend_updated is not pushed to the updated user's own channel" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, f} = Gamend.Friends.create_request(a.id, b.id)
    {:ok, _} = Gamend.Friends.accept_friend_request(f.id, b)

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    {:ok, socket_a} = connect(GamendWeb.UserSocket, %{"token" => token_a})
    {:ok, _, socket_a} = subscribe_and_join(socket_a, "user:#{a.id}", %{})

    assert_push "updated", _a_initial
    assert_push "friend_updated", _a_initial_friends

    {:ok, _updated_a} =
      Gamend.Accounts.update_user(a, %{
        metadata: %{"map_country_id" => "ro"}
      })

    assert_push "updated", self_payload
    assert self_payload.id == a.id
    settle(socket_a)
    refute_push "friend_updated", _, 0
  end

  test "friend_updated is not pushed for pending friend requests" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, _f} = Gamend.Friends.create_request(a.id, b.id)

    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    {:ok, socket_b} = connect(GamendWeb.UserSocket, %{"token" => token_b})
    {:ok, _, socket_b} = subscribe_and_join(socket_b, "user:#{b.id}", %{})

    assert_push "updated", _b_initial
    assert_push "friend_updated", %{friends: friends}
    assert friends == %{}

    {:ok, _updated_a} =
      Gamend.Accounts.update_user(a, %{
        metadata: %{"map_country_id" => "ro"}
      })

    settle(socket_b)
    refute_push "friend_updated", _, 0
  end

  test "friend_updated is not pushed for blocked friend requests" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, f} = Gamend.Friends.create_request(a.id, b.id)
    {:ok, _blocked} = Gamend.Friends.block_friend_request(f.id, b)

    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    {:ok, socket_b} = connect(GamendWeb.UserSocket, %{"token" => token_b})
    {:ok, _, socket_b} = subscribe_and_join(socket_b, "user:#{b.id}", %{})

    assert_push "updated", _b_initial
    assert_push "friend_updated", %{friends: friends}
    assert friends == %{}

    {:ok, _updated_a} =
      Gamend.Accounts.update_user(a, %{
        metadata: %{"map_country_id" => "ro"}
      })

    settle(socket_b)
    refute_push "friend_updated", _, 0
  end

  test "friend_updated is not pushed after friendship removal" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, f} = Gamend.Friends.create_request(a.id, b.id)
    {:ok, _} = Gamend.Friends.accept_friend_request(f.id, b)
    {:ok, _} = Gamend.Friends.remove_friend(a.id, b.id)

    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    {:ok, socket_b} = connect(GamendWeb.UserSocket, %{"token" => token_b})
    {:ok, _, socket_b} = subscribe_and_join(socket_b, "user:#{b.id}", %{})

    assert_push "updated", _b_initial
    assert_push "friend_updated", %{friends: friends}
    assert friends == %{}

    {:ok, _updated_a} =
      Gamend.Accounts.update_user(a, %{
        metadata: %{"map_country_id" => "ro"}
      })

    settle(socket_b)
    refute_push "friend_updated", _, 0
  end

  test "deleting a user who is online sends offline friend_updated to friends" do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    # Make a and b friends
    {:ok, f} = Gamend.Friends.create_request(a.id, b.id)
    {:ok, _} = Gamend.Friends.accept_friend_request(f.id, b)

    # Mark a as online
    {:ok, _} = Gamend.Accounts.set_user_online(a.id)

    # b joins their channel to listen for friend_updated
    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    {:ok, socket_b} = connect(GamendWeb.UserSocket, %{"token" => token_b})
    {:ok, _, _socket_b} = subscribe_and_join(socket_b, "user:#{b.id}", %{})

    assert_push "updated", _b_initial
    assert_push "friend_updated", b_initial_friends
    assert b_initial_friends.friends[to_string(a.id)].is_online == true

    # Delete user a
    {:ok, _} = Gamend.Accounts.delete_user(a)

    assert_push "friend_updated", payload, 1000
    assert payload.friends[to_string(a.id)].is_online == false
  end
end
