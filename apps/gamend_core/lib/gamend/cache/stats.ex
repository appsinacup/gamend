defmodule Gamend.Cache.Stats do
  @moduledoc """
  Lightweight in-memory counters for cache effectiveness and overload signals,
  aggregated from telemetry events:

  - `[:gamend, :cache, :command, :stop]` — cache reads (`:fetch`), keyed
    by the first element of the cache key tuple (`:accounts`, `:kv`, …),
    classified as hit or miss.
  - `[:gamend, :rate_limit, :deny]` — rate-limiter denials by scope.
  - `[:gamend, :async, :overload]` — async tasks run inline because the
    task supervisor was at capacity.

  Counters live in a public ETS table written via `:ets.update_counter` from
  the telemetry handler (caller process), so the hot path never crosses a
  process boundary. `snapshot/0` powers the admin dashboard panel; the same
  events feed Prometheus via `GamendWeb.PromEx.CachePlugin`.
  """

  use GenServer

  require Gamend.Placeholder, as: Placeholder

  @unknown Placeholder.unknown()

  @table __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    _ =
      :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])

    :ok =
      :telemetry.attach_many(
        "gamend-cache-stats",
        [
          [:gamend, :cache, :command, :stop],
          [:gamend, :rate_limit, :deny],
          [:gamend, :async, :overload]
        ],
        &__MODULE__.handle_event/4,
        nil
      )

    {:ok, %{}}
  end

  @doc false
  def handle_event([:gamend, :cache, :command, :stop], _measurements, metadata, _config) do
    with %{command: :fetch, args: [key | _]} <- metadata do
      case classify_result(metadata.result) do
        :ignore -> :ok
        outcome -> bump({:cache, key_prefix(key), outcome})
      end
    end

    :ok
  end

  def handle_event([:gamend, :rate_limit, :deny], _measurements, metadata, _config) do
    bump({:rate_limit_deny, Map.get(metadata, :scope, @unknown)})
  end

  def handle_event([:gamend, :async, :overload], _measurements, _metadata, _config) do
    bump(:async_overload)
  end

  @doc """
  Returns aggregated counters:

      %{
        cache: [%{prefix: :accounts, hits: 10, misses: 2, hit_rate: 0.83}, ...],
        rate_limit_denies: %{"auth" => 3, ...},
        async_overloads: 0
      }
  """
  @spec snapshot() :: map()
  def snapshot do
    entries = if :ets.whereis(@table) == :undefined, do: [], else: :ets.tab2list(@table)

    grouped =
      Enum.reduce(entries, %{cache: %{}, denies: %{}, overloads: 0}, fn
        {{:cache, prefix, outcome}, count}, acc ->
          update_in(acc, [:cache, Access.key(prefix, %{})], fn counts ->
            Map.update(counts || %{}, outcome, count, &(&1 + count))
          end)

        {{:rate_limit_deny, scope}, count}, acc ->
          put_in(acc, [:denies, scope], count)

        {:async_overload, count}, acc ->
          %{acc | overloads: count}

        _other, acc ->
          acc
      end)

    cache =
      grouped.cache
      |> Enum.map(fn {prefix, counts} ->
        hits = Map.get(counts, :hit, 0)
        misses = Map.get(counts, :miss, 0)
        total = hits + misses

        %{
          prefix: prefix,
          hits: hits,
          misses: misses,
          hit_rate: if(total > 0, do: hits / total, else: 0.0)
        }
      end)
      |> Enum.sort_by(&(&1.hits + &1.misses), :desc)

    %{
      cache: cache,
      rate_limit_denies: grouped.denies,
      async_overloads: grouped.overloads
    }
  end

  @doc "Resets all counters (admin dashboard action)."
  @spec reset() :: :ok
  def reset do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  defp bump(key) do
    _ = :ets.update_counter(@table, key, 1, {key, 0})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc false
  def classify_result({:ok, _value}), do: :hit
  def classify_result({:error, %Nebulex.KeyError{}}), do: :miss
  def classify_result(_other), do: :ignore

  @doc false
  def key_prefix(key) when is_tuple(key) and tuple_size(key) > 0 do
    case elem(key, 0) do
      atom when is_atom(atom) -> atom
      _ -> :other
    end
  end

  def key_prefix(key) when is_atom(key), do: key
  def key_prefix(_key), do: :other
end
