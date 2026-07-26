defmodule GameServer.Matchmaking.Worker do
  @moduledoc """
  Periodic driver for the matchmaking sweep.

  Runs on every node as a plain local GenServer; the sweep body is serialized
  cluster-wide via `GameServer.Lock`, so only one node forms matches per tick
  and a node joining or leaving never breaks supervision (a `:global` name
  would fail the second node's supervisor start with `:already_started`).

  Each tick, inside the lock: prune tickets of users that went offline, then
  group the queued tickets by `match_params` and create a hidden lobby per
  formed match. Broadcasts go out after the lock's transaction commits.

      config :game_server_core, GameServer.Matchmaking.Worker,
        enabled: true               # set false to leave the worker idle

  Disabled in test configs, like the other periodic workers: the tick owns no
  sandbox connection, so it only produces "database is locked" noise. Tests
  call `sweep/0` directly.
  """

  use GenServer
  require Logger

  alias GameServer.Friends
  alias GameServer.Matchmaking
  alias GameServer.Matchmaking.Match
  alias GameServer.Matchmaking.Matcher

  @initial_delay_ms :timer.seconds(3)

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

  defp enabled?, do: Application.get_env(:game_server_core, __MODULE__, [])[:enabled] != false

  @impl true
  def handle_info(:tick, state) do
    _ =
      try do
        sweep()
      rescue
        e -> Logger.error("matchmaking sweep failed: #{Exception.message(e)}")
      end

    Process.send_after(self(), :tick, GameServer.Limits.get(:matchmaking_tick_ms))
    {:noreply, state}
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
    _ = GameServer.ReadyChecks.expire_due()

    claimed =
      case GameServer.Lock.serialize(:matchmaking_sweep, "global", &claim_phase/0) do
        {:ok, matches} -> matches
        {:error, _} -> []
      end

    claimed
    |> Enum.map(&Match.create/1)
    |> Enum.count(&match?({:ok, _}, &1))
  end

  defp claim_phase do
    _ = Matchmaking.prune_offline()

    Matchmaking.list_queued_by_params()
    |> Enum.flat_map(&form_bucket/1)
    |> Enum.filter(&(Matchmaking.claim(&1) == :ok))
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
    case GameServer.Hooks.internal_call(:matchmaking_form_matches, [params, tickets]) do
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
