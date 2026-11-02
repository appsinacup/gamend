defmodule GamendWeb.SignalingChannelTest do
  @moduledoc """
  Presence translation on the signaling channel.

  Presence diffs are broadcast on the channel's own topic, so they reach
  `handle_out/3` (via `intercept`), not `handle_info/2`. Getting that wrong is
  invisible from the server side — the channel keeps working, it just stops
  translating, or translates twice — so these assert on what peers receive.
  """
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.Signaling
  alias GamendWeb.Auth.Guardian

  @endpoint GamendWeb.Endpoint

  # A presence diff crosses the tracker, a task and the channel, so how long it
  # takes depends on how busy the machine is. Waited for, never slept through.
  @push_timeout 5_000

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)

    host = AccountsFixtures.user_fixture()
    peer = AccountsFixtures.user_fixture()

    {:ok, lobby} = Lobbies.create_lobby(%{"title" => "Signaling", "host_id" => host.id})

    {:ok, lobby} =
      Signaling.configure(lobby, enabled: true, topology: :mesh, reconnect_timeout: 0)

    %{lobby: lobby, host: host, peer: peer}
  end

  defp join_signaling(user, lobby_id) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    subscribe_and_join(socket, "signaling:#{lobby_id}", %{})
  end

  # Tracking runs after the join returns. A second peer joining before the first
  # is tracked would see no one to be seeded with.
  defp await_tracked(lobby_id, user_id, attempts \\ 500) do
    cond do
      Signaling.peer_role(lobby_id, user_id) -> :ok
      attempts == 0 -> flunk("#{user_id} was never tracked")
      true -> Process.sleep(10) && await_tracked(lobby_id, user_id, attempts - 1)
    end
  end

  # Every socket in this test shares the test process mailbox, so the pushes are
  # counted rather than matched in order.
  defp pushed_ids(event) do
    {:messages, messages} = :erlang.process_info(self(), :messages)

    for %Phoenix.Socket.Message{event: ^event, payload: payload} <- messages,
        do: payload.user_id
  end

  test "a peer is announced exactly once to everyone already in the room", %{
    lobby: lobby,
    host: host,
    peer: peer
  } do
    {:ok, _reply, _socket} = join_signaling(host, lobby.id)
    await_tracked(lobby.id, host.id)
    assert pushed_ids("user_joined") == []

    {:ok, _reply, _socket} = join_signaling(peer, lobby.id)

    # The presence diff the host sees, and the seed the newcomer gets for whoever
    # was already there.
    assert_push "user_joined", %{user_id: user_id}, @push_timeout
    assert_push "user_joined", %{user_id: other_id}, @push_timeout
    assert Enum.sort([user_id, other_id]) == Enum.sort([host.id, peer.id])

    # A second of either would mean the channel is subscribed to its own topic
    # twice.
    refute_push "user_joined", %{}, 300
  end

  test "a leave is announced exactly once", %{lobby: lobby, host: host, peer: peer} do
    peer_id = peer.id

    {:ok, _reply, _socket} = join_signaling(host, lobby.id)
    await_tracked(lobby.id, host.id)

    {:ok, _reply, peer_socket} = join_signaling(peer, lobby.id)
    assert_push "user_joined", %{user_id: ^peer_id}, @push_timeout

    # subscribe_and_join links the channel to the test process, and leaving
    # stops it with {:shutdown, :left}.
    Process.unlink(peer_socket.channel_pid)
    leave(peer_socket)

    assert_push "user_left", %{user_id: ^peer_id}, @push_timeout
    refute_push "user_left", %{}, 300
  end

  test "ICE relayed over signaling is limited by its own settings", %{lobby: lobby, host: host} do
    limiter = Application.get_env(:gamend_web, GamendWeb.Plugs.RateLimiter, [])

    Application.put_env(
      :gamend_web,
      GamendWeb.Plugs.RateLimiter,
      Keyword.merge(limiter, enabled: true, signaling_ice_limit: 1)
    )

    on_exit(fn -> Application.put_env(:gamend_web, GamendWeb.Plugs.RateLimiter, limiter) end)

    {:ok, _reply, socket} = join_signaling(host, lobby.id)

    ice = %{
      "target" => Ecto.UUID.generate(),
      "candidate" => "candidate:1 1 udp 1 1.2.3.4 5 typ host"
    }

    ref = push(socket, "ice", ice)
    refute_reply ref, :error, %{error: "ice_rate_limited"}

    ref = push(socket, "ice", ice)
    assert_reply ref, :error, %{error: "ice_rate_limited"}
  end
end
