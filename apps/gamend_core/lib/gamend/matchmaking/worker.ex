defmodule Gamend.Matchmaking.Worker do
  @moduledoc """
  Periodic driver for the matchmaking sweep.

  Runs on every node as a plain local GenServer; the sweep body is serialized
  cluster-wide via `Gamend.Lock`, so only one node forms matches per tick
  and a node joining or leaving never breaks supervision (a `:global` name
  would fail the second node's supervisor start with `:already_started`).

  Each tick, inside the lock: prune tickets of users that went offline, then
  group the queued tickets by `match_params` and create a hidden lobby per
  formed match. Broadcasts go out after the lock's transaction commits.

      config :gamend_core, Gamend.Matchmaking.Worker,
        enabled: true               # set false to leave the worker idle

  Disabled in test configs, like the other periodic workers: the tick owns no
  sandbox connection, so it only produces "database is locked" noise. Tests
  call `sweep/0` directly.
  """

  use GenServer
  require Logger

  alias Gamend.Friends
  alias Gamend.Matchmaking
  alias Gamend.Matchmaking.Match
  alias Gamend.Matchmaking.Matcher

  @initial_delay_ms :timer.seconds(3)

  # Long enough to absorb the joins of a party arriving together or a burst of
  # players hitting queue at once, short enough that it reads as immediate.
  @nudge_debounce_ms 100

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Stays supervised but idle when disabled (tests): the sweep has no sandbox
    # connection to check out, so it would just stall and then error.
    if enabled?(), do: Process.send_after(self(), :tick, @initial_delay_ms)
    {:ok, %{}}
  end

  defp enabled?, do: Application.get_env(:gamend_core, __MODULE__, [])[:enabled] != false

  @doc """
  Ask for a sweep now rather than at the next tick.

  Called when a ticket is created: the tick exists so nobody waits forever in a
  half-full bucket, but a join that *completes* a bucket should not sit out the
  remainder of an interval for no reason. Time-to-match was a flat ~3 s —
  a uniform draw over the interval — and none of it was work.

  Asynchronous and coalescing: a burst of joins produces one sweep, not one per
  ticket, and the caller never waits on the sweep. If the worker is not running
  (tests, a partial supervision tree) this is a no-op, because the tick would
  not have run either.
  """
  @spec nudge() :: :ok
  def nudge do
    case Process.whereis(__MODULE__) do
      nil ->
        :ok

      pid ->
        send(pid, :nudge)
        :ok
    end
  end

  @impl true
  def handle_info(:tick, state) do
    run_sweep()

    Process.send_after(self(), :tick, Gamend.Limits.get(:matchmaking_tick_ms))
    {:noreply, Map.delete(state, :nudge_pending)}
  end

  # Coalesced: the first nudge in a window schedules one sweep, and further
  # nudges before it fires are absorbed. Without this a hundred simultaneous
  # joins would queue a hundred sweeps, each taking the cluster lock.
  def handle_info(:nudge, %{nudge_pending: true} = state), do: {:noreply, state}

  def handle_info(:nudge, state) do
    Process.send_after(self(), :nudge_sweep, @nudge_debounce_ms)
    {:noreply, Map.put(state, :nudge_pending, true)}
  end

  def handle_info(:nudge_sweep, state) do
    run_sweep()
    {:noreply, Map.delete(state, :nudge_pending)}
  end

  defp run_sweep do
    sweep()
  rescue
    e -> Logger.error("matchmaking sweep failed: #{Exception.message(e)}")
  end

  @doc """
  One matchmaking sweep. Public so tests and consoles can run a tick on
  demand without waiting for the timer.

  Two phases: inside the cluster lock, prune offline players and *claim* the
  formed matches (an atomic queued→matched flip). Outside the lock, create a
  lobby per claimed match — lobby creation fires hooks and broadcasts, which
  must never run inside a transaction. Claimed tickets are invisible to other
  sweepers, and a failed lobby simply requeues them for the next tick.

  Returns the number of lobbies created.
  """
  @spec sweep() :: non_neg_integer()
  def sweep do
    # Backstop for a ready check whose durable expiry job was lost. Outside the
    # lock: expiring fires hooks and broadcasts. One indexed query per tick.
    _ = Gamend.ReadyChecks.expire_due()

    _ = Matchmaking.prune_offline()

    # Matching happens *outside* the lock; only the claim is inside it.
    #
    # `Lock.serialize/3` opens a transaction, which on SQLite (the production
    # default) means holding the single pooled write connection. `form_bucket/1`
    # calls the `matchmaking_form_matches` hook, which waits on a task for up to
    # the hook timeout — a minute by default. A slow plugin therefore stalled
    # every write in the application, not just matchmaking; worse, the hook's
    # own task could not check out a connection, because this sweep held the
    # only one, so a plugin that touched the database blocked until the busy
    # timeout and then burned its whole budget.
    #
    # Reading queued tickets without the lock means the proposed groups may be
    # stale by the time the claim runs. That is already handled:
    # `Matchmaking.claim/1` is a conditional update and seats a group only if
    # every ticket in it is still queued.
    proposed =
      Matchmaking.list_queued_by_params()
      |> Enum.flat_map(&form_bucket/1)

    claimed =
      case Gamend.Lock.serialize(:matchmaking_sweep, "global", fn -> claim_phase(proposed) end) do
        {:ok, matches} -> matches
        {:error, _} -> []
      end

    claimed
    |> Enum.map(&Match.create/1)
    |> Enum.count(&match?({:ok, _}, &1))
  end

  defp claim_phase(proposed) do
    # A ticket must not be seated twice in one sweep: a custom matcher is free
    # to return the same ticket in two groups, and `Matchmaking.requeue/1` would
    # then flip a ticket that another group had already claimed back to queued.
    {claimed, _seen} =
      Enum.reduce(proposed, {[], MapSet.new()}, fn group, {acc, seen} ->
        ids = Enum.map(group, & &1.id)

        cond do
          Enum.any?(ids, &MapSet.member?(seen, &1)) ->
            Logger.warning("matchmaking: ticket proposed in two groups this sweep; dropped")
            {acc, seen}

          Matchmaking.claim(group) == :ok ->
            {[group | acc], MapSet.union(seen, MapSet.new(ids))}

          true ->
            {acc, seen}
        end
      end)

    Enum.reverse(claimed)
  end

  # One bucket = the tickets sharing identical match_params. A game may
  # replace the matcher for the bucket; core still enforces the block list on
  # whatever comes back, so a custom matcher cannot seat blocked players.
  defp form_bucket({params, tickets}) do
    blocked = Friends.blocked_pairs(Enum.map(tickets, & &1.user_id))

    case custom_matches(params, tickets) do
      :default ->
        {matches, _remaining} = Matcher.form_matches(tickets, blocked)
        matches

      groups ->
        groups
        |> Enum.filter(&valid_group?(&1, tickets, blocked))
    end
  end

  defp custom_matches(params, tickets) do
    case Gamend.Hooks.internal_call(:matchmaking_form_matches, [params, tickets]) do
      {:ok, groups} when is_list(groups) -> groups
      _ -> :default
    end
  end

  # A custom matcher must return groups of real, distinct, unblocked tickets
  # from this bucket. Anything else is dropped with a warning rather than
  # trusted — a plugin bug must not seat the wrong players.
  defp valid_group?(group, tickets, blocked) when is_list(group) and group != [] do
    ids = MapSet.new(tickets, & &1.id)
    group_ids = Enum.map(group, & &1.id)

    cond do
      not Enum.all?(group_ids, &MapSet.member?(ids, &1)) ->
        Logger.warning("matchmaking: custom matcher returned tickets outside the bucket; dropped")
        false

      length(Enum.uniq(group_ids)) != length(group_ids) ->
        Logger.warning("matchmaking: custom matcher returned a duplicate ticket; dropped")
        false

      blocked_within?(group, blocked) ->
        Logger.warning("matchmaking: custom matcher paired blocked players; dropped")
        false

      true ->
        true
    end
  end

  defp valid_group?(_group, _tickets, _blocked), do: false

  defp blocked_within?(group, blocked) do
    group
    |> Enum.map(& &1.user_id)
    |> pairs()
    |> Enum.any?(fn {a, b} -> MapSet.member?(blocked, Friends.pair_key(a, b)) end)
  end

  defp pairs([]), do: []
  defp pairs([_only]), do: []
  defp pairs([h | t]), do: Enum.map(t, &{h, &1}) ++ pairs(t)
end
