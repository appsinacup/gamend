defmodule GamendWeb.LobbyChannelTest do
  use ExUnit.Case
  import Phoenix.ChannelTest

  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias GamendWeb.Auth.Guardian

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)
    :ok
  end

  @endpoint GamendWeb.Endpoint

  test "members can join lobby topic and receive broadcasts" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    other = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "channel-room", host_id: host.id})

    # other joins as member
    assert {:ok, _} = Lobbies.join_lobby(other, lobby)

    {:ok, token_host, _} = Guardian.encode_and_sign(host)
    {:ok, token_other, _} = Guardian.encode_and_sign(other)

    {:ok, socket_host} = connect(GamendWeb.UserSocket, %{"token" => token_host})
    {:ok, socket_other} = connect(GamendWeb.UserSocket, %{"token" => token_other})

    {:ok, _, _socket} = subscribe_and_join(socket_host, "lobby:#{lobby.id}", %{})
    {:ok, _, _socket} = subscribe_and_join(socket_other, "lobby:#{lobby.id}", %{})

    payload = %{event: "hello", message: "hi"}

    GamendWeb.endpoint().broadcast("lobby:#{lobby.id}", "event", payload)

    assert_push "event", ^payload
  end

  test "non-members can join a public lobby as spectators" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    spectator = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "spectate-room", host_id: host.id})

    {:ok, token_spectator, _} = Guardian.encode_and_sign(spectator)
    {:ok, socket_spectator} = connect(GamendWeb.UserSocket, %{"token" => token_spectator})

    {:ok, _, socket} = subscribe_and_join(socket_spectator, "lobby:#{lobby.id}", %{})
    assert socket.assigns.spectator == true
  end

  test "a spectator is sent no member's metadata" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    spectator = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    {:ok, _} = Gamend.Accounts.update_user_metadata(host.id, &Map.put(&1, "ship", "brig"))

    {:ok, lobby} = Lobbies.create_lobby(%{title: "spectate-metadata", host_id: host.id})

    {:ok, token, _} = Guardian.encode_and_sign(spectator)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, _socket} = subscribe_and_join(socket, "lobby:#{lobby.id}", %{})

    assert_push "updated", %{spectator: true, members: [%{id: host_id, metadata: metadata}]}
    assert host_id == host.id
    assert metadata == %{}
  end

  test "non-members cannot join a hidden lobby" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    stranger = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "hidden-room", host_id: host.id})
    {:ok, lobby} = Lobbies.update_lobby(lobby, %{is_hidden: true})

    {:ok, token_stranger, _} = Guardian.encode_and_sign(stranger)
    {:ok, socket_stranger} = connect(GamendWeb.UserSocket, %{"token" => token_stranger})

    assert {:error, %{reason: "not_spectatable"}} =
             subscribe_and_join(socket_stranger, "lobby:#{lobby.id}", %{})
  end

  test "non-members cannot join a locked lobby" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    stranger = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "locked-room", host_id: host.id})
    {:ok, lobby} = Lobbies.update_lobby(lobby, %{is_locked: true})

    {:ok, token_stranger, _} = Guardian.encode_and_sign(stranger)
    {:ok, socket_stranger} = connect(GamendWeb.UserSocket, %{"token" => token_stranger})

    assert {:error, %{reason: "not_spectatable"}} =
             subscribe_and_join(socket_stranger, "lobby:#{lobby.id}", %{})
  end

  test "user in a different lobby cannot spectate another lobby" do
    host1 = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    host2 = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    member = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby1} = Lobbies.create_lobby(%{title: "lobby-1", host_id: host1.id})
    {:ok, lobby2} = Lobbies.create_lobby(%{title: "lobby-2", host_id: host2.id})

    # member joins lobby1
    {:ok, _} = Lobbies.join_lobby(member, lobby1)

    {:ok, token_member, _} = Guardian.encode_and_sign(member)
    {:ok, socket_member} = connect(GamendWeb.UserSocket, %{"token" => token_member})

    # member tries to spectate lobby2 — should be rejected
    assert {:error, %{reason: "must_spectate_own_lobby"}} =
             subscribe_and_join(socket_member, "lobby:#{lobby2.id}", %{})
  end

  test "channel receives user_kicked event when member is kicked" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    member = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "kick-channel-room", host_id: host.id})
    assert {:ok, _} = Lobbies.join_lobby(member, lobby)

    {:ok, token_host, _} = Guardian.encode_and_sign(host)
    {:ok, socket_host} = connect(GamendWeb.UserSocket, %{"token" => token_host})
    {:ok, _, _socket} = subscribe_and_join(socket_host, "lobby:#{lobby.id}", %{})

    # Kick the member - this should broadcast user_kicked event
    {:ok, _} = Lobbies.kick_user(host, lobby, member)

    assert_push "user_kicked", %{user_id: kicked_id, display_name: kicked_name}
    assert kicked_id == member.id
    assert is_binary(kicked_name)
  end

  test "channel receives updated event when lobby is updated" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "update-channel-room", host_id: host.id})

    {:ok, token_host, _} = Guardian.encode_and_sign(host)
    {:ok, socket_host} = connect(GamendWeb.UserSocket, %{"token" => token_host})
    {:ok, _, _socket} = subscribe_and_join(socket_host, "lobby:#{lobby.id}", %{})

    # drain the initial after_join payload
    assert_push "updated", %{title: "update-channel-room"}, 500

    # Update the lobby
    {:ok, _} = Lobbies.update_lobby_by_host(host, lobby, %{"title" => "New Title"})

    # allow a slightly longer window for the broadcast -> push to arrive in tests
    assert_push "updated", payload, 500
    assert payload.id == lobby.id
    assert payload.title == "New Title"
  end

  test "channel sends the full lobby state on update" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby} =
      Lobbies.create_lobby(%{
        title: "update-channel-room",
        host_id: host.id,
        metadata: %{
          "game_state" => "playing",
          "boat_adventure" => %{"hp" => 10, "stopped_until" => 500}
        }
      })

    {:ok, token_host, _} = Guardian.encode_and_sign(host)
    {:ok, socket_host} = connect(GamendWeb.UserSocket, %{"token" => token_host})
    {:ok, _, _socket} = subscribe_and_join(socket_host, "lobby:#{lobby.id}", %{})

    assert_push "updated", %{metadata: initial_metadata}, 500
    assert initial_metadata["boat_adventure"]["hp"] == 10

    {:ok, _updated} =
      Lobbies.update_lobby_by_host(host, lobby, %{
        "metadata" => %{
          "game_state" => "playing",
          "boat_adventure" => %{"hp" => 8}
        }
      })

    # Full payload: the new metadata is present whole, and the removed
    # stopped_until key is simply absent rather than flagged.
    assert_push "updated", payload, 500
    assert payload.metadata == %{"game_state" => "playing", "boat_adventure" => %{"hp" => 8}}
  end

  test "channel emits a single updated event per lobby update" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "single-update-room", host_id: host.id})

    {:ok, token_host, _} = Guardian.encode_and_sign(host)
    {:ok, socket_host} = connect(GamendWeb.UserSocket, %{"token" => token_host})
    {:ok, _, _socket} = subscribe_and_join(socket_host, "lobby:#{lobby.id}", %{})

    # consume the initial after_join payload
    assert_push "updated", %{title: "single-update-room"}, 500

    {:ok, _} = Lobbies.update_lobby_by_host(host, lobby, %{"title" => "Single Update"})

    # One push carrying the new state, and no duplicate for the unchanged rest.
    assert_push "updated", %{title: "Single Update"}, 500
    refute_push "updated", _payload, 200
  end

  test "channel receives user_online when a lobby member comes online" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    member = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "presence-room", host_id: host.id})
    {:ok, _} = Lobbies.join_lobby(member, lobby)

    {:ok, token_host, _} = Guardian.encode_and_sign(host)
    {:ok, socket_host} = connect(GamendWeb.UserSocket, %{"token" => token_host})
    {:ok, _, _socket} = subscribe_and_join(socket_host, "lobby:#{lobby.id}", %{})

    # drain the initial after_join payload
    assert_push "updated", _initial, 500

    # Simulate member coming online
    Lobbies.broadcast_member_presence(lobby.id, {:member_online, member.id})

    assert_push "user_online", payload, 500
    assert payload.user_id == member.id
    assert Map.has_key?(payload, :display_name)
    assert Map.has_key?(payload, :metadata)
  end

  test "channel receives user_offline when a lobby member goes offline" do
    host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    member = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "offline-room", host_id: host.id})
    {:ok, _} = Lobbies.join_lobby(member, lobby)

    {:ok, token_host, _} = Guardian.encode_and_sign(host)
    {:ok, socket_host} = connect(GamendWeb.UserSocket, %{"token" => token_host})
    {:ok, _, _socket} = subscribe_and_join(socket_host, "lobby:#{lobby.id}", %{})

    # drain the initial after_join payload
    assert_push "updated", _initial, 500

    # Simulate member going offline
    Lobbies.broadcast_member_presence(lobby.id, {:member_offline, member.id})

    assert_push "user_offline", payload, 500
    assert payload.user_id == member.id
    assert Map.has_key?(payload, :display_name)
  end
end
