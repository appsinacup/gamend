defmodule Gamend.MatchmakingSweepRaceTest do
  @moduledoc """
  Two sweeps over one queue at once: one per node, or the admin's "Run sweep
  now" beside the timer.

  Each reads the queue and forms its groups outside the cluster lock, then
  claims them inside it. The second sweep's claim of a group the first had
  claimed found nothing still queued, and its partial-claim cleanup requeued
  the whole group: the first sweep's tickets, which it was seating at that
  moment. That sweep then named its lobby on tickets back in the queue, and
  the next sweep matched those players a second time.

  The matcher hook holds the first sweep until the second has read the queue
  too, so both propose the same group; seating holds the first until the
  second has finished. The interleaving happens on every run and on both
  adapters.
  """

  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Matchmaking
  alias Gamend.Matchmaking.Ticket
  alias Gamend.Matchmaking.Worker

  defmodule InterleavingHook do
    use Gamend.TestSupport.NoopHooks

    # Both sweeps propose from the same read of the queue.
    @impl true
    def matchmaking_form_matches(_params, _tickets) do
      coordinator = Application.fetch_env!(:gamend, :matchmaking_sweep_race)
      Agent.update(coordinator, &Map.update!(&1, :formed, fn n -> n + 1 end))
      wait_until(fn -> Agent.get(coordinator, & &1.formed) >= 2 end)
      :default
    end

    # The sweep that claimed seats its players only once the other sweep has
    # finished: its claim has failed by then, and done whatever it does.
    @impl true
    def matchmaking_seat_match(_tickets) do
      coordinator = Application.fetch_env!(:gamend, :matchmaking_sweep_race)
      wait_until(fn -> Agent.get(coordinator, & &1.done) >= 1 end)
      :default
    end

    defp wait_until(fun, attempts \\ 300) do
      cond do
        fun.() ->
          :ok

        attempts == 0 ->
          raise "the other sweep never got there"

        true ->
          Process.sleep(10)
          wait_until(fun, attempts - 1)
      end
    end
  end

  setup do
    {:ok, coordinator} = Agent.start_link(fn -> %{formed: 0, done: 0} end)
    previous = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, InterleavingHook)
    Application.put_env(:gamend, :matchmaking_sweep_race, coordinator)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, :hooks_module, previous),
        else: Application.delete_env(:gamend_core, :hooks_module)

      Application.delete_env(:gamend, :matchmaking_sweep_race)
    end)

    users =
      for _ <- 1..2 do
        user = AccountsFixtures.user_fixture()
        {:ok, user} = user |> Ecto.Changeset.change(is_online: true) |> Repo.update()
        {:ok, _ticket} = Matchmaking.join(user, %{"mode" => "sweep-race"}, 2, 2)
        user
      end

    %{coordinator: coordinator, user_ids: Enum.map(users, & &1.id)}
  end

  test "a sweep never undoes the claim of another sweep seating those players", ctx do
    sweep = fn ->
      created = Worker.sweep()
      Agent.update(ctx.coordinator, &Map.update!(&1, :done, fn n -> n + 1 end))
      created
    end

    results = [sweep, sweep] |> Enum.map(&Task.async/1) |> Task.await_many(15_000)

    assert Enum.sort(results) == [0, 1], "one match is formed, once: #{inspect(results)}"

    tickets = Repo.all(from t in Ticket, where: t.user_id in ^ctx.user_ids)

    for ticket <- tickets do
      assert ticket.status == "matched" and is_binary(ticket.match_id),
             "a seated player's ticket went back to the queue: #{inspect(ticket)}"
    end

    [lobby_id] = tickets |> Enum.map(& &1.match_id) |> Enum.uniq()
    seated = Repo.all(from u in Gamend.Accounts.User, where: u.id in ^ctx.user_ids)
    assert Enum.all?(seated, &(&1.lobby_id == lobby_id))

    # And the next sweep has nothing to match again.
    assert Worker.sweep() == 0
  end
end
