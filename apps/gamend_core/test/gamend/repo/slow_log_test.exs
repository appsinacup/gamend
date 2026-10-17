defmodule Gamend.Repo.SlowLogTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Gamend.Repo.SlowLog

  @event [:gamend, :repo, :query]
  @config %{
    query: System.convert_time_unit(100, :millisecond, :native),
    transaction: System.convert_time_unit(50, :millisecond, :native)
  }

  defp ms(ms), do: System.convert_time_unit(ms, :millisecond, :native)

  defp query(sql, run, queue \\ 0),
    do:
      SlowLog.handle_event(
        @event,
        %{query_time: ms(run), queue_time: ms(queue)},
        %{query: sql, source: "kv_entries", stacktrace: nil},
        @config
      )

  test "a query over the line is named, with its table and where it came from" do
    log = capture_log(fn -> query(~s(SELECT k0."key" FROM "kv_entries"), 250) end)

    assert log =~ "slow query: 250ms"
    assert log =~ ~s(kv_entries: SELECT k0."key")
    assert log =~ "SlowLogTest"
  end

  test "waiting for a connection counts too; a quick query says nothing" do
    assert capture_log(fn -> query("SELECT 1", 1, 300) end) =~ "waited 300ms"
    assert capture_log(fn -> query("SELECT 1", 20) end) == ""
  end

  test "a transaction held past the line is named when it ends" do
    log =
      capture_log(fn ->
        SlowLog.handle_event(@event, %{query_time: 0}, %{query: "begin"}, @config)
        Process.sleep(80)
        SlowLog.handle_event(@event, %{query_time: 0}, %{query: "commit"}, @config)
      end)

    assert log =~ "slow transaction: held its connection"
    assert log =~ "(COMMIT)"
  end

  test "a short transaction, or a commit with no begin seen, says nothing" do
    log =
      capture_log(fn ->
        SlowLog.handle_event(@event, %{query_time: 0}, %{query: "begin"}, @config)
        SlowLog.handle_event(@event, %{query_time: 0}, %{query: "rollback"}, @config)
        SlowLog.handle_event(@event, %{query_time: 0}, %{query: "commit"}, @config)
      end)

    assert log == ""
  end

  test "0 turns a line off" do
    off = %{query: nil, transaction: nil}

    assert capture_log(fn ->
             SlowLog.handle_event(@event, %{query_time: ms(5_000)}, %{query: "SELECT 1"}, off)
           end) == ""
  end
end
