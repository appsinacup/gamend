defmodule Gamend.RaceCase do
  @moduledoc """
  Tests that a rule holds when requests land together: two claims of one
  quest, two results for one bracket, two seats for one player.

  `Gamend.DataCase` cannot show these races. Its sandbox runs a whole test
  on one connection, so calls made at once from several processes still
  reach the database one statement at a time, inside one transaction. A
  check-then-write bug passes there on every adapter. Here each racer runs on
  its own connection, outside the sandbox (`Ecto.Adapters.SQL.Sandbox.unboxed_run/2`),
  in its own transactions, and all of them are released at the same instant.

  The races only overlap on Postgres. SQLite runs one write transaction at a
  time, so there a test still runs and must still pass, but it proves
  nothing; CI's `test-postgres` job is where it bites. To run one locally:

      GAMEND_DB_URL=ecto://localhost/gamend_race_test MIX_BUILD_PATH=../../_build/test_pg \\
        mix test test/gamend/some_race_test.exs

  What a racer writes is committed. Build the fixture with `unboxed/1` and
  delete it in `cleanup/1`, or it stays for every later test. The test
  process has no sandbox connection either, so its own reads and assertions
  on the database go through `unboxed/1` too. The case is never async: ExUnit
  runs sync modules after every async one has finished, so nothing else is
  reading while these rows exist.

      use Gamend.RaceCase

      test "two claims pay once" do
        user = unboxed(fn -> AccountsFixtures.user_fixture() end)
        cleanup(fn -> Repo.delete_all(from u in User, where: u.id == ^user.id) end)

        results = race(2, fn _ -> Quests.claim(user.id, "daily") end)
        assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      end

  A racer that raises comes back as `{:raised, exception}` rather than
  failing the test from another process, so a test can assert that nothing
  raised: an exception there is a 500 for a client.
  """

  use ExUnit.CaseTemplate

  alias Gamend.Repo
  alias Gamend.TestSupport.Race

  using do
    quote do
      import Ecto.Query
      import Gamend.RaceCase

      alias Gamend.Repo
    end
  end

  setup tags do
    if tags[:async] do
      raise ArgumentError, "Gamend.RaceCase commits its rows and cannot run async"
    end

    # A racer's jobs (a notification's email, a push) are committed with the
    # rest of what it wrote, and a later test's `all_enqueued/1` read them as
    # its own. No sandboxed test can see a committed job it should keep.
    ExUnit.Callbacks.on_exit(fn -> unboxed(fn -> Repo.delete_all(Oban.Job) end) end)

    :ok
  end

  @doc "See `Gamend.TestSupport.Race.unboxed/1`."
  defdelegate unboxed(fun), to: Race

  @doc "See `Gamend.TestSupport.Race.race/1`."
  defdelegate race(funs), to: Race

  @doc "See `Gamend.TestSupport.Race.race/2`."
  defdelegate race(count, fun), to: Race

  @doc """
  Runs `fun` unboxed when the test exits, passed or failed: the place to
  delete what the test made.
  """
  @spec cleanup((-> term())) :: :ok
  def cleanup(fun) when is_function(fun, 0) do
    ExUnit.Callbacks.on_exit(fn -> unboxed(fun) end)
  end
end
