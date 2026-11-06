defmodule Gamend.LobbyStateRaceTest do
  @moduledoc """
  Two transitions of one lobby, the second landing while the first is still
  in `before_lobby_state_change`. The hook approved a move out of the state
  it read; once another transition has moved the lobby, that approval is for
  a state the lobby has left, and the write must not land over it.

  The hook here makes the other transition itself, so the interleaving is the
  same on every run and on both adapters.
  """
  use Gamend.DataCase, async: false

  alias Gamend.Lobbies

  defmodule MovingHook do
    use Gamend.TestSupport.NoopHooks

    # Approving "playing", the server closes the lobby first.
    @impl true
    def before_lobby_state_change(lobby, _from, "playing") do
      {:ok, _closed} = Lobbies.transition_state(lobby, "closed", skip_hooks: true)
      {:ok, lobby}
    end

    def before_lobby_state_change(lobby, _from, _to), do: {:ok, lobby}
  end

  setup do
    previous = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, MovingHook)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, :hooks_module, previous),
        else: Application.delete_env(:gamend_core, :hooks_module)
    end)

    :ok
  end

  test "a transition approved from a state the lobby has left does not land" do
    {:ok, lobby} = Lobbies.create_lobby(%{title: "race-#{System.unique_integer([:positive])}"})

    assert {:error, :state_changed} = Lobbies.transition_state(lobby, "playing")
    assert Lobbies.get_lobby(lobby.id).state == "closed"
  end
end
