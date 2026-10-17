defmodule GamendWeb.SignalingRelayTest do
  @moduledoc """
  What the signaling channel relays between two peers: an offer, an answer
  and an ICE candidate reach the one named (with who sent them), a
  broadcast offer reaches everyone else, the room's users are listed, a
  target not in the room or a payload too big or not a string is refused, a
  star room lets a user talk to the host only, a closed room stops every
  channel, and a room with no WebRTC, or a stranger to a closed lobby, is
  refused at join.
  """
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.Signaling
  alias GamendWeb.Auth.Guardian

  @endpoint GamendWeb.Endpoint

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)
    host = AccountsFixtures.user_fixture()
    peer = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{"title" => "Relay", "host_id" => host.id})
    {:ok, _} = Lobbies.join_lobby(peer, lobby.id)
    %{lobby: lobby, host: host, peer: peer}
  end

  defp room(lobby, opts) do
    {:ok, lobby} =
      Signaling.configure(lobby, Keyword.merge([enabled: true, reconnect_timeout: 0], opts))

    lobby
  end

  defp enter(user, lobby_id) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    subscribe_and_join(socket, "signaling:#{lobby_id}", %{})
  end

  defp both(lobby, host, peer) do
    {:ok, %{role: _}, host_socket} = enter(host, lobby.id)
    {:ok, _reply, peer_socket} = enter(peer, lobby.id)
    # Let presence settle so each sees the other.
    Process.sleep(200)
    {host_socket, peer_socket}
  end

  describe "a mesh room" do
    setup %{lobby: lobby} do
      %{lobby: room(lobby, topology: :mesh)}
    end

    test "an offer, its answer and a candidate reach the one named", %{
      lobby: lobby,
      host: host,
      peer: peer
    } do
      {host_socket, peer_socket} = both(lobby, host, peer)
      host_id = host.id
      peer_id = peer.id

      ref = push(host_socket, "offer", %{"target" => peer.id, "sdp" => "v=0 offer"})
      assert_reply ref, :ok, %{}
      assert_push "offer", %{sdp: "v=0 offer", from_user_id: ^host_id}

      ref = push(peer_socket, "answer", %{"target" => host.id, "sdp" => "v=0 answer"})
      assert_reply ref, :ok, %{}
      assert_push "answer", %{sdp: "v=0 answer", from_user_id: ^peer_id}

      ref = push(peer_socket, "ice", %{"target" => host.id, "candidate" => "candidate:1"})
      assert_reply ref, :ok, %{}
      assert_push "ice", %{candidate: "candidate:1", from_user_id: ^peer_id}
    end

    test "a broadcast offer reaches everyone else; the users are listed", %{
      lobby: lobby,
      host: host,
      peer: peer
    } do
      {host_socket, _peer_socket} = both(lobby, host, peer)
      host_id = host.id

      ref = push(host_socket, "broadcast_offer", %{"sdp" => "v=0 all"})
      assert_reply ref, :ok, %{}
      assert_push "offer", %{sdp: "v=0 all", from_user_id: ^host_id}

      ref = push(host_socket, "list_users", %{})
      assert_reply ref, :ok, %{users: users}
      assert users |> Map.new() |> Map.keys() |> Enum.sort() == Enum.sort([host.id, peer.id])
    end

    test "a target not in the room, or a bad payload, is refused", %{
      lobby: lobby,
      host: host,
      peer: peer
    } do
      {host_socket, _peer_socket} = both(lobby, host, peer)
      nobody = Ecto.UUID.generate()

      for event <- ~w(offer answer) do
        ref = push(host_socket, event, %{"target" => nobody, "sdp" => "v=0"})
        assert_reply ref, :error, %{error: "user_not_found"}
      end

      ref = push(host_socket, "ice", %{"target" => nobody, "candidate" => "c"})
      assert_reply ref, :error, %{error: "user_not_found"}

      big = String.duplicate("a", 16_385)
      ref = push(host_socket, "offer", %{"target" => peer.id, "sdp" => big})
      assert_reply ref, :error, %{error: "payload_too_large"}

      ref = push(host_socket, "answer", %{"target" => peer.id, "sdp" => %{"not" => "text"}})
      assert_reply ref, :error, %{error: "invalid_payload"}
    end

    test "an event the channel does not know is answered, not crashed on", %{
      lobby: lobby,
      host: host
    } do
      {:ok, _reply, socket} = enter(host, lobby.id)
      ref = push(socket, "teleport", %{})
      assert_reply ref, :error, _
      assert Process.alive?(socket.channel_pid)
    end

    test "a closed room stops every channel in it", %{lobby: lobby, host: host, peer: peer} do
      {host_socket, peer_socket} = both(lobby, host, peer)
      Process.unlink(host_socket.channel_pid)
      Process.unlink(peer_socket.channel_pid)
      host_ref = Process.monitor(host_socket.channel_pid)
      peer_ref = Process.monitor(peer_socket.channel_pid)

      assert Signaling.close(lobby.id) == :ok
      assert_push "room_closed", %{room_id: room_id}
      assert room_id == lobby.id
      assert_receive {:DOWN, ^host_ref, :process, _, :normal}
      assert_receive {:DOWN, ^peer_ref, :process, _, :normal}
    end

    test "a stray message is ignored", %{lobby: lobby, host: host} do
      {:ok, _reply, socket} = enter(host, lobby.id)
      send(socket.channel_pid, :nothing_to_see)
      send(socket.channel_pid, {:channel_updates_flush, []})
      ref = push(socket, "list_users", %{})
      assert_reply ref, :ok, %{users: _}
    end
  end

  describe "a star room" do
    setup %{lobby: lobby, host: host} do
      %{lobby: room(lobby, topology: :star, host_id: host.id)}
    end

    test "the host joins as host; a user may not broadcast", %{
      lobby: lobby,
      host: host,
      peer: peer
    } do
      assert {:ok, %{role: :host}, _} = enter(host, lobby.id)
      assert {:ok, %{role: :user}, peer_socket} = enter(peer, lobby.id)
      Process.sleep(200)

      ref = push(peer_socket, "broadcast_offer", %{"sdp" => "v=0"})
      assert_reply ref, :error, %{error: "not_allowed"}

      ref = push(peer_socket, "offer", %{"target" => host.id, "sdp" => "v=0"})
      assert_reply ref, :ok, %{}
    end

    test "a user may not talk to another user", %{lobby: lobby, host: host, peer: peer} do
      third = AccountsFixtures.user_fixture()
      {:ok, _} = Lobbies.join_lobby(third, lobby.id)
      {:ok, _, _} = enter(host, lobby.id)
      {:ok, _, peer_socket} = enter(peer, lobby.id)
      {:ok, _, _} = enter(third, lobby.id)
      Process.sleep(200)

      for event <- ~w(offer answer) do
        ref = push(peer_socket, event, %{"target" => third.id, "sdp" => "v=0"})
        assert_reply ref, :error, %{error: "not_allowed"}
      end

      ref = push(peer_socket, "ice", %{"target" => third.id, "candidate" => "c"})
      assert_reply ref, :error, %{error: "not_allowed"}
    end
  end

  test "a lobby with no WebRTC has no room to join", %{lobby: lobby, host: host} do
    assert {:error, %{reason: "room_not_found"}} = enter(host, lobby.id)
    assert {:error, %{reason: "room_not_found"}} = enter(host, Ecto.UUID.generate())
  end

  test "a stranger may not late-join a locked lobby", %{lobby: lobby} do
    lobby = room(lobby, topology: :mesh, late_join: true)
    {:ok, _} = Lobbies.update_lobby(lobby, %{is_locked: true})
    assert {:error, %{reason: "not_allowed"}} = enter(AccountsFixtures.user_fixture(), lobby.id)
  end
end
