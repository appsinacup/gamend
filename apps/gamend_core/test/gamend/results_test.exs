defmodule Gamend.ResultsTest do
  # `max_result_events` is global Application config.
  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Results
  alias Gamend.Results.Event
  alias Gamend.SettingsHelpers

  setup do
    user = AccountsFixtures.user_fixture()
    {:ok, result} = Results.start(user.id, "match")
    %{result: result}
  end

  test "records events while open, and a play ends once", %{result: result} do
    assert {:ok, %Event{key: "goal", value: 1.0}} = Results.record(result, "goal", 1)
    assert {:ok, %{status: "ended"}} = Results.finish(result)
    assert {:error, :already_ended} = Results.finish(result)
    assert {:error, :not_found} = Results.finish(Ecto.UUID.generate())
  end

  test "an event recorded through a copy read before the end is refused", %{result: result} do
    # `result` still says open: the end is read under the result's lock, not
    # from the copy. It used to be written after the play had ended.
    {:ok, _ended} = Results.finish(result)

    assert {:error, :ended} = Results.record(result, "late", 1)
    assert {:error, :ended} = Results.record(result.id, "late", 1)
    assert Results.count_events(result.id) == 0
  end

  test "stops at max_result_events", %{result: result} do
    SettingsHelpers.put(:gamend_core, Gamend.Limits, :max_result_events, 2)
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, Gamend.Limits, :max_result_events) end)

    assert {:ok, _} = Results.record(result, "a")
    assert {:ok, _} = Results.record(result, "b")
    assert {:error, :too_many_events} = Results.record(result, "c")
  end
end
