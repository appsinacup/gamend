defmodule GamendWeb.RateLimit do
  @moduledoc """
  Rate limiter facade used by `GamendWeb.Plugs.RateLimiter`, LiveView
  helpers, and channels.

  Delegates to one of two Hammer-powered backends:

  - `GamendWeb.RateLimit.ETS` (default) — node-local counters.
  - `GamendWeb.RateLimit.Redis` — counters shared across all app
    instances via Redis; use this for multi-instance deployments so limits
    hold cluster-wide.

  ## Configuration

      config :gamend_web, GamendWeb.RateLimit,
        backend: :redis,
        redis: [url: "redis://localhost:6379"]

  Selected at runtime via the `GAMEND_RATELIMIT_BACKEND` env var (`"ets"` or
  `"redis"`); the Redis URL falls back from `GAMEND_RATELIMIT_REDIS_URL` to
  `GAMEND_CACHE_REDIS_URL`, then `GAMEND_CLUSTER_REDIS_URL`
  (`GamendWeb.HostRuntime`).

  The configured backend is started in the host application supervision tree.
  """

  import Bitwise

  @doc """
  The bucket a client address is limited under: the address itself for IPv4,
  its /64 for IPv6.

  An IPv6 subscriber is routinely handed a whole /64, 2^64 addresses, so a
  limit per address would not hold for them. An IPv4-mapped address
  (`::ffff:1.2.3.4`, what a dual-stack listener reports for an IPv4 client)
  is keyed as the IPv4 it carries; taking its /64 would put every IPv4 client
  in one bucket. A string that is not an address is its own key.
  """
  @spec ip_key(:inet.ip_address() | String.t()) :: String.t()
  def ip_key({_, _, _, _} = ip), do: ip |> :inet.ntoa() |> to_string()

  def ip_key({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: ip_key({hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF})

  def ip_key({a, b, c, d, _, _, _, _}),
    do: "#{:inet.ntoa({a, b, c, d, 0, 0, 0, 0})}/64"

  def ip_key(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, address} -> ip_key(address)
      {:error, _} -> ip
    end
  end

  @spec hit(String.t(), pos_integer(), pos_integer()) ::
          {:allow, non_neg_integer()} | {:deny, non_neg_integer()}
  def hit(key, scale, limit) do
    case backend().hit(key, scale, limit) do
      {:allow, _count} = result ->
        result

      {:deny, _retry_after} = result ->
        :telemetry.execute(
          [:gamend, :rate_limit, :deny],
          %{count: 1},
          %{scope: scope_of(key)}
        )

        result
    end
  end

  @doc """
  Daily chat quota for one user (`Gamend.Limits` `:max_chat_messages_per_day`,
  rolling 24h window). Returns `:ok` or `{:error, :chat_daily_limit}`.

  Skipped when rate limiting is disabled or the limit is 0.
  """
  @spec check_chat_daily(term()) :: :ok | {:error, :chat_daily_limit}
  def check_chat_daily(user_id) do
    limit = Gamend.Limits.get(:max_chat_messages_per_day)

    if Gamend.Settings.get(GamendWeb.Plugs.RateLimiter, :enabled) and
         is_integer(limit) and limit > 0 do
      case hit("chatd:#{user_id}", :timer.hours(24), limit) do
        {:allow, _count} -> :ok
        {:deny, _retry_after} -> {:error, :chat_daily_limit}
      end
    else
      :ok
    end
  end

  @doc """
  Daily chat-report quota for one user (`Gamend.Limits`
  `:max_chat_reports_per_user_per_day`, rolling 24h window). Returns `:ok` or
  `{:error, :report_daily_limit}`.

  Skipped when rate limiting is disabled or the limit is 0.
  """
  @spec check_report_daily(term()) :: :ok | {:error, :report_daily_limit}
  def check_report_daily(user_id) do
    limit = Gamend.Limits.get(:max_chat_reports_per_user_per_day)

    if Gamend.Settings.get(GamendWeb.Plugs.RateLimiter, :enabled) and
         is_integer(limit) and limit > 0 do
      case hit("chatrep:#{user_id}", :timer.hours(24), limit) do
        {:allow, _count} -> :ok
        {:deny, _retry_after} -> {:error, :report_daily_limit}
      end
    else
      :ok
    end
  end

  # Bucket keys look like "auth:1.2.3.4" / "general:..." / "ws:..." — the
  # part before the first colon is the scope used for metrics.
  defp scope_of(key) when is_binary(key) do
    case String.split(key, ":", parts: 2) do
      [scope, _rest] -> scope
      _ -> "unknown"
    end
  end

  defp scope_of(_key), do: "unknown"

  # ETS counts per node, which is fine for one instance and wrong for several:
  # with N instances every limit is effectively N times higher. Redis shares
  # the counters, so it is required rather than warned about once selected —
  # a rate limiter that silently does not limit is worse than none.
  use Gamend.Settings.Provider,
    app: :gamend_web,
    group: :ratelimit,
    label: "Rate limiting"

  setting(:backend, :atom,
    values: [:ets, :redis],
    default: :ets,
    doc: "ets (per-node counters) or redis (shared across instances)."
  )

  setting(:redis_url, :string,
    required: :prod,
    when: {[:ratelimit, :backend], :redis},
    doc: "Redis URL for shared counters."
  )

  @doc "Returns the currently configured backend module."
  @spec backend() :: module()
  def backend do
    case Gamend.Settings.get(__MODULE__, :backend) do
      :redis -> GamendWeb.RateLimit.Redis
      _ -> GamendWeb.RateLimit.ETS
    end
  end

  @doc false
  def child_spec(opts) do
    case backend() do
      GamendWeb.RateLimit.Redis = mod ->
        url = Gamend.Settings.get(__MODULE__, :redis_url)
        %{id: __MODULE__, start: {mod, :start_link, [[url: url]]}}

      mod ->
        %{id: __MODULE__, start: {mod, :start_link, [opts]}}
    end
  end
end
