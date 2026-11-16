defmodule Gamend.SpectatorTrackerTest do
  @moduledoc """
  Spectator counts on Presence.

  The point of the move is that counts are cluster-wide and that a spectator
  who disappears stops being counted without anyone cleaning up — the ETS
  version needed an explicit `untrack_all/1` on lobby delete and still
  undercounted across nodes.
  """
  use Gamend.DataCase, async: false

  alias Gamend.Lobbies.SpectatorTracker

  defp watch(lobby_id, user_id) do
    test = self()

    pid =
      spawn(fn ->
        :ok = SpectatorTracker.track(lobby_id, user_id)
        send(test, :watching)
        Process.sleep(:infinity)
      end)

    assert_receive :watching, 2_000
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

  test "counts spectators per lobby" do
    a = Ecto.UUID.generate()
    b = Ecto.UUID.generate()

    assert SpectatorTracker.count(a) == 0

    watch(a, Ecto.UUID.generate())
    watch(a, Ecto.UUID.generate())
    watch(b, Ecto.UUID.generate())

    assert SpectatorTracker.count(a) == 2
    assert SpectatorTracker.count(b) == 1
    assert SpectatorTracker.counts([a, b]) == %{a => 2, b => 1}
  end

  test "lists the spectating user ids" do
    lobby = Ecto.UUID.generate()
    user = Ecto.UUID.generate()

    watch(lobby, user)

    assert SpectatorTracker.list(lobby) == [user]
  end

  test "a spectator whose process dies stops counting" do
    lobby = Ecto.UUID.generate()
    pid = watch(lobby, Ecto.UUID.generate())

    assert SpectatorTracker.count(lobby) == 1

    Process.exit(pid, :kill)
    eventually(fn -> SpectatorTracker.count(lobby) == 0 end)
  end

  test "untrack removes only the caller's entry" do
    lobby = Ecto.UUID.generate()
    stays = Ecto.UUID.generate()
    leaves = Ecto.UUID.generate()

    watch(lobby, stays)
    test = self()

    pid =
      spawn(fn ->
        :ok = SpectatorTracker.track(lobby, leaves)
        send(test, :tracked)

        receive do
          :go -> :ok
        end

        :ok = SpectatorTracker.untrack(lobby, leaves)
        send(test, :untracked)
        Process.sleep(:infinity)
      end)

    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

    assert_receive :tracked, 2_000
    assert SpectatorTracker.count(lobby) == 2

    send(pid, :go)
    # `untrack/2` is a call to the tracker: done when it returns.
    assert_receive :untracked, 2_000
    assert SpectatorTracker.list(lobby) == [stays]
  end
end
