defmodule Gamend.Analytics.BufferTest do
  # The buffer with a window on: writes wait in ETS until a flush, then land
  # as counters and rows. Not async: the window is application config.
  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Analytics
  alias Gamend.Analytics.Buffer
  alias Gamend.Analytics.Event
  alias Gamend.Repo
  alias Gamend.SettingsHelpers

  @today ~D[2026-08-16]
  defp at(day), do: DateTime.new!(day, ~T[12:00:00], "Etc/UTC")

  setup do
    # The process lives in the web app's tree (`GamendWeb.HostSupervision`);
    # the core suite runs without it.
    _ = Process.whereis(Buffer) || start_supervised!(Buffer)
    SettingsHelpers.put(:gamend_core, Buffer, :flush_ms, 60_000)
    Buffer.clear()

    on_exit(fn ->
      SettingsHelpers.put(:gamend_core, Buffer, :flush_ms, 0)
      Buffer.clear()
    end)

    :ok
  end

  test "gathers counters and events until a flush lands them in the caller's process" do
    assert Buffer.buffered?()
    user = AccountsFixtures.user_fixture()

    :ok =
      Analytics.track("web.game.started", %{game: "hangman"}, user_id: user.id, at: at(@today))

    :ok = Analytics.count("level.finished", 2, at(@today))

    assert Repo.all(Event) == []
    assert Analytics.counts("*", 7, @today) == %{}

    assert {3, 1} = Analytics.flush()

    assert [%Event{name: "web.game.started"}] = Repo.all(Event)

    assert Analytics.count_totals("*", 7, @today) == [
             {"level.finished", 2},
             {"web.game.started", 1},
             {"web.game.started.game:hangman", 1}
           ]

    # Nothing left behind, nothing written twice.
    assert {0, 0} = Analytics.flush()
    assert Analytics.count_totals("level.finished", 7, @today) == [{"level.finished", 2}]
  end

  test "an increment between the read and the write is kept for the next flush" do
    :ok = Analytics.count("x.y", 1, at(@today))
    assert {1, 0} = Analytics.flush()
    :ok = Analytics.count("x.y", 2, at(@today))
    :ok = Analytics.count("x.y", 1, at(Date.add(@today, -1)))
    assert {2, 0} = Analytics.flush()

    assert Analytics.counts("x.y", 7, @today) == %{
             "x.y" => %{@today => 3, Date.add(@today, -1) => 1}
           }
  end

  test "with the window off, writes go through at once" do
    SettingsHelpers.put(:gamend_core, Buffer, :flush_ms, 0)
    refute Buffer.buffered?()
    user = AccountsFixtures.user_fixture()

    :ok = Analytics.track("web.page", %{section: "home"}, user_id: user.id, at: at(@today))
    assert [%Event{name: "web.page"}] = Repo.all(Event)
    assert {0, 0} = Analytics.flush()
  end
end
