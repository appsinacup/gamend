defmodule Gamend.TestSupport.Race do
  @moduledoc """
  Releases racers at the same instant, each on its own database connection,
  so a test can show whether a rule holds when requests land together.

  For tests only. It lives in `lib/` rather than core's `test/support` so a
  host app can use it from its own case template: a dependency's test
  support is not compiled into a host. Core's suite uses it through
  `Gamend.RaceCase`; a host's case calls `race/1,2` and `unboxed/1` and
  deletes what it made in `on_exit/1`.

  The sandbox runs a whole test on one connection, so calls made at once from
  several processes still reach the database one statement at a time, and a
  check-then-write bug passes on every adapter. Here each racer runs outside
  the sandbox (`Ecto.Adapters.SQL.Sandbox.unboxed_run/2`), in its own
  transactions, and what it writes is committed. The races overlap only on
  Postgres. SQLite runs one write transaction at a time, so there the racers
  run one after another: released together they only queued for the pool's
  one connection, and on a loaded machine a long wait in that queue dropped a
  racer (`DBConnection.ConnectionError`) for nothing the code under test did.

  A racer that raises comes back as `{:raised, exception}` instead of failing
  the test from another process, so a test can assert nothing raised: an
  exception there is a 500 for a client.
  """

  alias Ecto.Adapters.SQL.Sandbox

  @race_timeout 30_000

  @doc """
  Runs `fun` on a connection of its own, outside the sandbox. What it writes
  is committed.
  """
  @spec unboxed((-> result)) :: result when result: term()
  def unboxed(fun) when is_function(fun, 0), do: Sandbox.unboxed_run(Gamend.Repo, fun)

  @doc """
  Runs `count` racers, `fun.(1)` to `fun.(count)`, all released at once.
  Answers their results in order, a raise as `{:raised, exception}`.
  """
  @spec race(pos_integer(), (pos_integer() -> result)) :: [result | {:raised, Exception.t()}]
        when result: term()
  def race(count, fun) when is_integer(count) and count > 0 and is_function(fun, 1) do
    race(Enum.map(1..count, fn i -> fn -> fun.(i) end end))
  end

  @doc """
  Runs each function in `funs` as one racer, all released at once. Answers
  their results in order, a raise as `{:raised, exception}`.
  """
  @spec race([(-> term())]) :: [term()]
  def race(funs) when is_list(funs) do
    if Gamend.Repo.AdvisoryLock.postgres?(),
      do: release_together(funs),
      else: Enum.map(funs, &(&1 |> racer() |> Task.async() |> Task.await(@race_timeout)))
  end

  defp release_together(funs) do
    parent = self()

    tasks =
      Enum.map(funs, fn fun ->
        Task.async(fn ->
          send(parent, {:race_ready, self()})

          receive do
            :race_go -> :ok
          end

          racer(fun).()
        end)
      end)

    pids =
      Enum.map(tasks, fn _task ->
        receive do
          {:race_ready, pid} -> pid
        after
          @race_timeout -> raise "a racer never started"
        end
      end)

    Enum.each(pids, &send(&1, :race_go))
    Task.await_many(tasks, @race_timeout)
  end

  defp racer(fun) do
    fn ->
      try do
        unboxed(fun)
      rescue
        exception -> {:raised, exception}
      end
    end
  end
end
