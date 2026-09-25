defmodule GamendWeb.Plugs.IpBan do
  @moduledoc """
  Plug that blocks requests from banned IP addresses.

  The hot-path check reads a dedicated ETS table (`:ip_bans`). Bans are also
  persisted via `Gamend.IpBans`, so they survive restarts, and broadcast
  on PubSub so every app instance applies them (see `GamendWeb.IpBanSync`,
  which loads persisted bans at boot and mirrors remote changes into ETS).

  ## Banning / unbanning an IP

      GamendWeb.Plugs.IpBan.ban("1.2.3.4")                    # permanent
      GamendWeb.Plugs.IpBan.ban("1.2.3.4", :timer.hours(24))  # 24h ban
      GamendWeb.Plugs.IpBan.unban("1.2.3.4")
      GamendWeb.Plugs.IpBan.banned?("1.2.3.4")
      GamendWeb.Plugs.IpBan.list_bans()

  This plug runs early in the endpoint pipeline, after `RealIp` extracts
  the true client address.

  An IPv6 address is banned by its /64 (`GamendWeb.RateLimit.ip_key/1`): one
  subscriber is routinely handed the whole /64 and moves around inside it, so
  a ban on a single address would not hold. `ban("2001:db8::1")` is listed as
  `2001:db8::/64`. An IPv4 address is banned as itself.
  """

  import Plug.Conn

  require Logger

  @behaviour Plug
  @table :ip_bans
  @log_table :ip_ban_log
  @max_log_entries 100
  @topic "ip_bans"

  # ── Public API ────────────────────────────────────────────────────────────

  @doc "PubSub topic on which ban/unban events are broadcast."
  def topic, do: @topic

  @doc "Ensure the ETS tables exist (called once at app startup)."
  def init_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    if :ets.whereis(@log_table) == :undefined do
      :ets.new(@log_table, [:ordered_set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc """
  Ban an IP address. Pass `ttl_ms` for a temporary ban (milliseconds)
  or `:infinity` (default) for a permanent ban.

  The ban takes effect locally right away, is persisted to the database,
  and is broadcast to the other app instances.
  """
  def ban(ip, ttl_ms \\ :infinity) do
    init_table()
    ip = GamendWeb.RateLimit.ip_key(ip)

    expires_at =
      case ttl_ms do
        :infinity -> :infinity
        ms when is_integer(ms) -> System.monotonic_time(:millisecond) + ms
      end

    expires_at_utc =
      case ttl_ms do
        :infinity -> nil
        ms when is_integer(ms) -> DateTime.add(DateTime.utc_now(), ms, :millisecond)
      end

    :ets.insert(@table, {ip, expires_at})
    append_log(:ban, ip, ttl_ms)
    persist(fn -> Gamend.IpBans.upsert_ban(ip, expires_at_utc) end)
    broadcast({:ip_ban, :banned, ip, expires_at_utc, Node.self()})
    :ok
  end

  @doc """
  Remove a ban for the given IP (locally, persisted, and cluster-wide): the
  ban on its /64 for IPv6, and any on the exact address, which is how IPv6
  bans were stored before they covered the /64.
  """
  def unban(ip) do
    [GamendWeb.RateLimit.ip_key(ip), ip] |> Enum.uniq() |> Enum.each(&unban_key/1)
  end

  defp unban_key(ip) do
    init_table()
    :ets.delete(@table, ip)
    append_log(:unban, ip, nil)
    persist(fn -> Gamend.IpBans.delete_ban(ip) end)
    broadcast({:ip_ban, :unbanned, ip, nil, Node.self()})
    :ok
  end

  @doc "Check if an IP is currently banned: itself, or its /64 for IPv6."
  def banned?(ip) do
    [ip, GamendWeb.RateLimit.ip_key(ip)] |> Enum.uniq() |> Enum.any?(&banned_key?/1)
  end

  defp banned_key?(ip) do
    init_table()

    case :ets.lookup(@table, ip) do
      [{^ip, :infinity}] ->
        true

      [{^ip, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          true
        else
          # Expired — clean up
          :ets.delete(@table, ip)
          false
        end

      [] ->
        false
    end
  end

  @doc "List all currently active bans as `[{ip, expires_at}]`."
  def list_bans do
    init_table()
    now = System.monotonic_time(:millisecond)

    :ets.tab2list(@table)
    |> Enum.filter(fn
      {_ip, :infinity} -> true
      {_ip, expires_at} -> expires_at > now
    end)
  end

  @doc """
  Load persisted bans from the database into ETS and drop expired rows.

  Called at boot by `GamendWeb.IpBanSync`.
  """
  def load_persisted do
    init_table()
    _ = Gamend.IpBans.purge_expired()

    Enum.each(Gamend.IpBans.list_active(), fn ban ->
      :ets.insert(@table, {ban.ip, to_monotonic(ban.expires_at)})
    end)

    :ok
  end

  @doc """
  Apply a ban/unban event that originated on another app instance.

  Only touches ETS — the originating instance already persisted the change.
  """
  def apply_remote(:banned, ip, expires_at_utc) do
    init_table()
    :ets.insert(@table, {ip, to_monotonic(expires_at_utc)})
    :ok
  end

  def apply_remote(:unbanned, ip, _expires_at_utc) do
    init_table()
    :ets.delete(@table, ip)
    :ok
  end

  @doc """
  Return recent ban/unban log entries as a list of maps, newest first.

  Each entry: `%{action: :ban | :unban, ip: String.t(), ttl: term(), at: DateTime.t()}`
  """
  def list_log do
    init_table()

    :ets.tab2list(@log_table)
    |> Enum.sort_by(fn {ts, _action, _ip, _ttl} -> ts end, :desc)
    |> Enum.map(fn {_ts, action, ip, ttl} ->
      %{action: action, ip: ip, ttl: ttl}
    end)
  end

  defp to_monotonic(nil), do: :infinity

  defp to_monotonic(%DateTime{} = expires_at_utc) do
    remaining_ms = DateTime.diff(expires_at_utc, DateTime.utc_now(), :millisecond)
    System.monotonic_time(:millisecond) + remaining_ms
  end

  # Persistence and broadcast are best-effort: a ban must still apply locally
  # even if the database or PubSub is unavailable (e.g. early boot, tests).
  defp persist(fun) do
    fun.()
    :ok
  rescue
    e ->
      Logger.warning("ip ban persistence failed: " <> Exception.message(e))
      :ok
  end

  defp broadcast(message), do: Gamend.Broadcast.best_effort(@topic, message, "ip ban")

  defp append_log(action, ip, ttl) do
    ts = System.monotonic_time(:nanosecond)
    :ets.insert(@log_table, {ts, action, ip, ttl})
    prune_log()
  end

  defp prune_log do
    size = :ets.info(@log_table, :size)

    if size > @max_log_entries do
      # Remove oldest entries (smallest keys in ordered_set)
      to_remove = size - @max_log_entries

      @log_table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {ts, _, _, _} -> ts end)
      |> Enum.take(to_remove)
      |> Enum.each(fn {ts, _, _, _} -> :ets.delete(@log_table, ts) end)
    end
  end

  # ── Plug callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    network = GamendWeb.RateLimit.ip_key(conn.remote_ip)

    if banned_key?(ip) or (network != ip and banned_key?(network)) do
      conn
      |> send_resp(403, "Forbidden")
      |> halt()
    else
      conn
    end
  end
end
