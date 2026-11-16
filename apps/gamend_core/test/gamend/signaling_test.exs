defmodule Gamend.SignalingTest do
  @moduledoc """
  Signaling with no room process.

  The property that matters is that nothing is stored: config comes off the
  lobby and membership comes off `Gamend.Presence`, so any node can serve
  any room. The old version kept rooms in a node-local GenServer, where a room
  created on one node did not exist on another.
  """
  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.Presence
  alias Gamend.Signaling

  setup do
    host = AccountsFixtures.unconfirmed_user_fixture()
    peer = AccountsFixtures.unconfirmed_user_fixture()

    {:ok, lobby} = Lobbies.create_lobby(%{"title" => "Signaling", "host_id" => host.id})
    {:ok, lobby} = Signaling.configure(lobby, enabled: true, topology: :star)

    %{lobby: lobby, host: host, peer: peer}
  end

  # Presence normally tracks a channel process; a plain process stands in.
  defp connect(lobby, user_id, role) do
    test = self()

    pid =
      spawn(fn ->
        {:ok, _} =
          Presence.track(self(), Signaling.topic(lobby.id), user_id, %{role: role})

        send(test, :tracked)
        Process.sleep(:infinity)
      end)

    assert_receive :tracked, 2_000
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    pid
  end

  # The tracker drops a dead process's entries when it handles the exit.
  defp eventually(fun, tries \\ 200) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(5) && eventually(fun, tries - 1)
    end
  end

  describe "config/1" do
    test "derives from the lobby's own columns", %{lobby: lobby, host: host} do
      assert {:ok, cfg} = Signaling.config(lobby.id)
      assert cfg.topology == :star
      assert cfg.host_user_id == host.id
      assert cfg.late_join == true
      assert cfg.reconnect_timeout == 30_000
    end

    test "a lobby without webrtc has no room" do
      owner = AccountsFixtures.unconfirmed_user_fixture()
      {:ok, plain} = Lobbies.create_lobby(%{"title" => "Plain", "host_id" => owner.id})

      assert {:error, :room_not_found} = Signaling.config(plain.id)
      refute Signaling.enabled?(plain.id)
    end

    test "a deleted lobby has no room", %{lobby: lobby} do
      {:ok, _} = Lobbies.delete_lobby(lobby)

      assert {:error, :room_not_found} = Signaling.config(lobby.id)
    end

    # The bug that shipped: `|| true` read an explicit false as "unset".
    test "late_join false is honoured" do
      owner = AccountsFixtures.unconfirmed_user_fixture()

      {:ok, closed} = Lobbies.create_lobby(%{"title" => "Closed", "host_id" => owner.id})

      {:ok, closed} =
        Signaling.configure(closed, enabled: true, topology: :mesh, late_join: false)

      assert {:ok, %{late_join: false}} = Signaling.config(closed.id)
    end

    test "a pinned host_id overrides the lobby host", %{lobby: lobby, peer: peer} do
      {:ok, lobby} = Signaling.configure(lobby, topology: :star, host_id: peer.id)

      assert {:ok, %{host_user_id: host_user_id}} = Signaling.config(lobby.id)
      assert host_user_id == peer.id
      assert {:ok, :host} = Signaling.authorize(lobby.id, peer.id)
    end

    test "clearing host_id falls back to the lobby host", %{lobby: lobby, host: host, peer: peer} do
      {:ok, lobby} = Signaling.configure(lobby, host_id: peer.id)
      {:ok, lobby} = Signaling.configure(lobby, host_id: nil)

      assert {:ok, %{host_user_id: host_user_id}} = Signaling.config(lobby.id)
      assert host_user_id == host.id
    end

    # SQLite reports no constraint name, so a foreign_key_constraint would raise
    # instead of erroring. The id is checked before the write for that reason.
    test "an unknown host_id is refused, not raised", %{lobby: lobby} do
      assert {:error, :host_not_found} = Signaling.configure(lobby, host_id: "host_user_id")
      assert {:error, :host_not_found} = Signaling.configure(lobby, host_id: Ecto.UUID.generate())

      assert Lobbies.get_lobby(lobby.id).webrtc_host_id == nil
    end
  end

  describe "authorize/2" do
    test "the lobby host is the star host", %{lobby: lobby, host: host} do
      assert {:ok, :host} = Signaling.authorize(lobby.id, host.id)
    end

    test "a non-member may join when late_join is on", %{lobby: lobby, peer: peer} do
      assert {:ok, :user} = Signaling.authorize(lobby.id, peer.id)
    end

    test "a non-member is refused when late_join is off", %{peer: peer} do
      host = AccountsFixtures.unconfirmed_user_fixture()

      {:ok, closed} = Lobbies.create_lobby(%{"title" => "Closed", "host_id" => host.id})

      {:ok, closed} =
        Signaling.configure(closed, enabled: true, topology: :mesh, late_join: false)

      assert {:error, :not_allowed} = Signaling.authorize(closed.id, peer.id)
      # The lobby's own host is a member, so it is still allowed.
      assert {:ok, _} = Signaling.authorize(closed.id, host.id)
    end

    # Signaling config is server-owned now, so a client cannot reach any of it.
    # The star host is the lobby host, and nothing in metadata changes that.
    test "metadata cannot grant a signaling role", %{peer: peer} do
      owner = AccountsFixtures.unconfirmed_user_fixture()
      impostor = AccountsFixtures.unconfirmed_user_fixture()

      {:ok, lobby} = Lobbies.create_lobby(%{"title" => "Planted", "host_id" => owner.id})
      {:ok, lobby} = Signaling.configure(lobby, enabled: true, topology: :star)

      {:ok, _} =
        Lobbies.update_lobby(lobby, %{
          metadata: %{"webrtc" => %{"host_user_id" => impostor.id, "topology" => "mesh"}}
        })

      assert {:ok, cfg} = Signaling.config(lobby.id)
      assert cfg.host_user_id == owner.id
      assert cfg.topology == :star

      assert {:ok, :host} = Signaling.authorize(lobby.id, owner.id)
      assert {:ok, :user} = Signaling.authorize(lobby.id, impostor.id)
      assert {:ok, :user} = Signaling.authorize(lobby.id, peer.id)
    end

    test "no room means no authorization", %{peer: peer} do
      assert {:error, :room_not_found} = Signaling.authorize(Ecto.UUID.generate(), peer.id)
    end
  end

  describe "peers/1" do
    test "reports whoever is tracked, and forgets them when they die", %{
      lobby: lobby,
      host: host,
      peer: peer
    } do
      assert Signaling.peers(lobby.id) == %{}

      connect(lobby, host.id, :host)
      pid = connect(lobby, peer.id, :user)

      peers = Signaling.peers(lobby.id)
      assert peers[host.id] == :host
      assert peers[peer.id] == :user

      Process.exit(pid, :kill)
      eventually(fn -> not Map.has_key?(Signaling.peers(lobby.id), peer.id) end)
    end
  end

  describe "live config changes" do
    # Config is read per call, so a host change takes effect at once — the role
    # must not be the one frozen into the presence meta at join time.
    test "a host change moves the :host role without a reconnect", %{
      lobby: lobby,
      host: host,
      peer: peer
    } do
      connect(lobby, host.id, :host)
      connect(lobby, peer.id, :user)

      assert Signaling.peers(lobby.id)[host.id] == :host
      assert Signaling.peers(lobby.id)[peer.id] == :user

      {:ok, _} = Lobbies.update_lobby(Lobbies.get_lobby(lobby.id), %{host_id: peer.id})

      assert Signaling.peers(lobby.id)[peer.id] == :host
      assert Signaling.peers(lobby.id)[host.id] == :user
      assert {:ok, :host} = Signaling.authorize(lobby.id, peer.id)
    end

    test "disabling webrtc stops relaying", %{lobby: lobby, host: host, peer: peer} do
      connect(lobby, host.id, :host)
      connect(lobby, peer.id, :user)

      assert :ok = Signaling.relay(lobby.id, host.id, peer.id, :offer, %{})

      {:ok, _} = Signaling.configure(lobby.id, enabled: false)

      assert {:error, :room_not_found} = Signaling.relay(lobby.id, host.id, peer.id, :offer, %{})
      assert {:error, :room_not_found} = Signaling.authorize(lobby.id, peer.id)
    end

    test "tightening late_join only affects new joins", %{lobby: lobby, peer: peer} do
      connect(lobby, peer.id, :user)

      {:ok, _} = Signaling.configure(lobby.id, late_join: false)

      # Already connected, so still a peer; but a fresh join is now refused.
      assert Map.has_key?(Signaling.peers(lobby.id), peer.id)
      assert {:error, :not_allowed} = Signaling.authorize(lobby.id, peer.id)
    end
  end

  describe "relay/5" do
    setup %{lobby: lobby, host: host, peer: peer} do
      connect(lobby, host.id, :host)
      connect(lobby, peer.id, :user)
      :ok
    end

    test "delivers to the target's inbox", %{lobby: lobby, host: host, peer: peer} do
      Phoenix.PubSub.subscribe(Gamend.PubSub, Signaling.inbox(lobby.id, peer.id))

      assert :ok = Signaling.relay(lobby.id, host.id, peer.id, :offer, %{sdp: "x"})

      assert_receive {:signaling_relay, :offer, from, %{sdp: "x"}}, 2_000
      assert from == host.id
    end

    test "an unknown target is a user_not_found", %{lobby: lobby, host: host} do
      assert {:error, :user_not_found} =
               Signaling.relay(lobby.id, host.id, Ecto.UUID.generate(), :offer, %{})
    end

    # Star topology: every exchange must involve the host.
    test "two non-hosts cannot talk in a star room", %{lobby: lobby, peer: peer} do
      other = AccountsFixtures.unconfirmed_user_fixture()
      connect(lobby, other.id, :user)

      assert {:error, :not_allowed} = Signaling.relay(lobby.id, peer.id, other.id, :offer, %{})
    end

    test "two non-hosts can talk in a mesh room" do
      owner = AccountsFixtures.unconfirmed_user_fixture()

      {:ok, mesh} = Lobbies.create_lobby(%{"title" => "Mesh", "host_id" => owner.id})
      {:ok, mesh} = Signaling.configure(mesh, enabled: true, topology: :mesh)

      a = AccountsFixtures.unconfirmed_user_fixture()
      b = AccountsFixtures.unconfirmed_user_fixture()
      connect(mesh, a.id, :user)
      connect(mesh, b.id, :user)

      Phoenix.PubSub.subscribe(Gamend.PubSub, Signaling.inbox(mesh.id, b.id))

      assert :ok = Signaling.relay(mesh.id, a.id, b.id, :ice, %{candidate: "c"})
      assert_receive {:signaling_relay, :ice, _from, %{candidate: "c"}}, 2_000
    end
  end

  describe "broadcast/4" do
    test "only the host may broadcast in a star room", %{lobby: lobby, host: host, peer: peer} do
      connect(lobby, host.id, :host)
      connect(lobby, peer.id, :user)

      Phoenix.PubSub.subscribe(Gamend.PubSub, Signaling.inbox(lobby.id, peer.id))

      assert :ok = Signaling.broadcast(lobby.id, host.id, :offer, %{sdp: "s"})
      assert_receive {:signaling_relay, :offer, _from, %{sdp: "s"}}, 2_000

      assert {:error, :not_allowed} = Signaling.broadcast(lobby.id, peer.id, :offer, %{})
    end
  end

  describe "close/1" do
    test "tells every peer the room is over", %{lobby: lobby, host: host, peer: peer} do
      connect(lobby, host.id, :host)
      connect(lobby, peer.id, :user)

      Phoenix.PubSub.subscribe(Gamend.PubSub, Signaling.inbox(lobby.id, peer.id))

      assert :ok = Signaling.close(lobby.id)
      assert_receive {:signaling_relay, :room_closed, nil, _}, 2_000
    end
  end
end
