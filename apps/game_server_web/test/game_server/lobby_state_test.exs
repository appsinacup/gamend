defmodule GameServer.LobbyStateTest do
  use GameServer.DataCase

  alias GameServer.AccountsFixtures
  alias GameServer.Lobbies
  alias GameServer.Lobbies.States

  # Vetoes any move into "playing" and reports what it saw, so both the veto
  # path and the after-hook's arguments are covered.
  defmodule StateHook do
    def before_lobby_state_change(_lobby, from, to) do
      send(Application.get_env(:game_server, :hooks_test_pid), {:before_state, from, to})
      if to == "playing", do: {:error, :not_ready}, else: :ok
    end

    def after_lobby_state_changed(_lobby, from, to) do
      send(Application.get_env(:game_server, :hooks_test_pid), {:after_state, from, to})
      :ok
    end
  end

  defp with_state_hook(fun) do
    orig = Application.get_env(:game_server_core, :hooks_module)
    Application.put_env(:game_server_core, :hooks_module, StateHook)
    Application.put_env(:game_server, :hooks_test_pid, self())

    try do
      fun.()
    after
      if orig,
        do: Application.put_env(:game_server_core, :hooks_module, orig),
        else: Application.delete_env(:game_server_core, :hooks_module)
    end
  end

  defp lobby_fixture(attrs \\ %{}) do
    {:ok, lobby} =
      Lobbies.create_lobby(Map.merge(%{title: "L#{System.unique_integer([:positive])}"}, attrs))

    lobby
  end

  describe "states vocabulary" do
    test "core documents a default vocabulary and assigns the initial state" do
      assert States.initial() == "created"

      # Documentation, not an enum: the game enforces its own vocabulary in
      # before_lobby_state_change.
      assert Map.keys(States.core()) |> Enum.sort() ==
               ["created", "ended", "playing", "starting"]
    end
  end

  describe "create_lobby/1" do
    test "starts in the initial state with a timestamp" do
      lobby = lobby_fixture()

      assert lobby.state == "created"
      assert lobby.state_changed_at
    end
  end

  describe "transition_state/3" do
    test "moves the lobby and stamps state_changed_at" do
      lobby = lobby_fixture()

      assert {:ok, playing} = Lobbies.transition_state(lobby, "playing")
      assert playing.state == "playing"
      assert DateTime.compare(playing.state_changed_at, lobby.state_changed_at) != :lt
    end

    test "the vocabulary is the game's — any sane word is accepted" do
      lobby = lobby_fixture()

      # No declaration registry: a game that wants a closed vocabulary rejects
      # unknown words in before_lobby_state_change.
      assert {:ok, %{state: "drafting"}} = Lobbies.transition_state(lobby, "drafting")
    end

    test "rejects an empty or oversized state string" do
      lobby = lobby_fixture()

      assert {:error, :invalid_state} = Lobbies.transition_state(lobby, "")

      assert {:error, :invalid_state} =
               Lobbies.transition_state(lobby, String.duplicate("x", 65))

      assert Lobbies.get_lobby(lobby.id).state == "created"
    end

    test "is idempotent — a same-state write is a no-op" do
      lobby = lobby_fixture()
      {:ok, playing} = Lobbies.transition_state(lobby, "playing")

      assert {:ok, again} = Lobbies.transition_state(playing, "playing")
      assert again.state_changed_at == playing.state_changed_at
    end

    test "any state may follow any other — core enforces no ordering" do
      lobby = lobby_fixture()

      {:ok, lobby} = Lobbies.transition_state(lobby, "ended")
      # Core does not model a machine; a round-based game may reopen a lobby.
      assert {:ok, lobby} = Lobbies.transition_state(lobby, "created")
      assert lobby.state == "created"
    end

    test "state is not reachable through a generic lobby update" do
      lobby = lobby_fixture()

      {:ok, updated} = Lobbies.update_lobby(lobby, %{"state" => "playing", "title" => "renamed"})

      assert updated.title == "renamed"
      assert updated.state == "created"
    end
  end

  describe "transition_state_by_host/3" do
    test "the host of a host-managed lobby may move it" do
      host = AccountsFixtures.user_fixture()
      lobby = lobby_fixture(%{host_id: host.id})

      assert {:ok, moved} = Lobbies.transition_state_by_host(host, lobby, "playing")
      assert moved.state == "playing"
    end

    test "a non-host may not" do
      host = AccountsFixtures.user_fixture()
      other = AccountsFixtures.user_fixture()
      lobby = lobby_fixture(%{host_id: host.id})

      assert {:error, :not_host} = Lobbies.transition_state_by_host(other, lobby, "playing")
      assert Lobbies.get_lobby(lobby.id).state == "created"
    end

    test "nobody may move a hostless lobby — matchmaking matches belong to the server" do
      user = AccountsFixtures.user_fixture()
      lobby = lobby_fixture(%{hostless: true})

      assert {:error, :not_host} = Lobbies.transition_state_by_host(user, lobby, "ended")
      assert Lobbies.get_lobby(lobby.id).state == "created"

      # The server itself still can, via the unscoped call.
      assert {:ok, ended} = Lobbies.transition_state(lobby, "ended")
      assert ended.state == "ended"
    end
  end

  describe "hooks" do
    test "before_lobby_state_change can veto the move" do
      lobby = lobby_fixture()

      with_state_hook(fn ->
        assert {:error, {:hook_rejected, :not_ready}} =
                 Lobbies.transition_state(lobby, "playing")

        assert_received {:before_state, "created", "playing"}
      end)

      assert Lobbies.get_lobby(lobby.id).state == "created"
    end

    test "after_lobby_state_changed observes an allowed move" do
      lobby = lobby_fixture()

      with_state_hook(fn ->
        assert {:ok, _} = Lobbies.transition_state(lobby, "ended")
        assert_received {:before_state, "created", "ended"}
        assert_receive {:after_state, "created", "ended"}, 1_000
      end)
    end

    test "skip_hooks bypasses the veto (admin/server path)" do
      lobby = lobby_fixture()

      with_state_hook(fn ->
        assert {:ok, moved} = Lobbies.transition_state(lobby, "playing", skip_hooks: true)
        assert moved.state == "playing"
      end)
    end
  end

  describe "listing" do
    test "filters by state" do
      a = lobby_fixture()
      b = lobby_fixture()
      {:ok, _} = Lobbies.transition_state(b, "playing")

      keys = Lobbies.list_lobbies(%{state: "playing"}) |> Enum.map(& &1.id)

      assert b.id in keys
      refute a.id in keys
    end
  end
end
