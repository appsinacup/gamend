defmodule GamendWeb.Plugs.GeoCountry do
  @moduledoc """
  Resolves the client's country and stores it on `conn.assigns[:country]`.

  **Resolution order** (first match wins):

  1. **Geolix MMDB lookup** — if a GeoLite2-Country (or compatible) database
     is configured via `GAMEND_CONTENT_GEOIP_DB_PATH`, the client IP is
     resolved locally.
     This is the most accurate and works without any proxy.

  2. **Cloudflare `CF-IPCountry` header** — fallback when behind Cloudflare.
     Cloudflare auto-appends the ISO 3166-1 alpha-2 country code.

  3. **`nil`** — when neither source is available (local dev without DB).

  Also classifies the client (`GamendWeb.Crawlers`: a person, or which kind
  of crawler and which one) and keeps an **in-memory ETS aggregate** of
  request counts by country, kind and crawler name, bucketed by minute, for
  the admin Geo page. Supports time-windowed queries (last 1h, 24h, 7d, or
  all-time) and a people/crawlers split. The rate limiter adds its 429s
  (`record_rate_limited/1`), so the page shows who gets throttled.

  Emits `:telemetry` events for Prometheus (`GamendWeb.PromEx.GeoPlugin`),
  which keeps the history across restarts that ETS loses:

    * `[:gamend, :geo, :request]` — every request, `%{country:, class:}`
    * `[:gamend, :crawler, :request]` — crawler requests, `%{class:, bot:}`
    * `[:gamend, :crawler, :rate_limited]` — 429s, `%{class:, bot:}`

  The classification is on `conn.assigns[:client_class]` as `{kind, name}`.

  ## Configuration

    To enable Geolix lookup, either place the MMDB file under the host-owned
    default path:

      data/GeoLite2-Country.mmdb

    or set a custom path in your environment:

      GAMEND_CONTENT_GEOIP_DB_PATH=/path/to/GeoLite2-Country.mmdb

  Download the free database from:
  https://dev.maxmind.com/geoip/geolite2-free-geolocation-data
  """

  import Plug.Conn

  alias GamendWeb.Crawlers

  @behaviour Plug

  @table :geo_country_stats
  # Keep 7 days of minute buckets
  @retention_minutes 7 * 24 * 60

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    country = resolve_country(conn)
    code = country || "XX"
    {kind, name} = Crawlers.classify_conn(conn)

    increment({code, kind, name})

    :telemetry.execute([:gamend, :geo, :request], %{count: 1}, %{country: code, class: kind})

    if Crawlers.crawler?(kind) do
      :telemetry.execute([:gamend, :crawler, :request], %{count: 1}, %{class: kind, bot: name})
    end

    conn
    |> assign(:country, country)
    |> assign(:client_class, {kind, name})
  end

  @doc """
  Counts a 429 against the request's client class (`GamendWeb.Plugs.RateLimiter`
  calls it on every denial). A conn this plug never saw counts as a person.
  """
  @spec record_rate_limited(Plug.Conn.t()) :: :ok
  def record_rate_limited(%Plug.Conn{} = conn) do
    {kind, name} = conn.assigns[:client_class] || {:human, nil}
    increment({:rate_limited, kind, name})

    :telemetry.execute(
      [:gamend, :crawler, :rate_limited],
      %{count: 1},
      %{class: kind, bot: name || "none"}
    )

    :ok
  end

  # --- Resolution strategies ---

  defp resolve_country(conn) do
    geolix_lookup(conn.remote_ip) || cf_header(conn)
  end

  # Strategy 1: Local MMDB database lookup via Geolix
  defp geolix_lookup(ip) do
    case Geolix.lookup(ip, where: :country) do
      %{country: %{iso_code: code}} when is_binary(code) ->
        String.upcase(code)

      _ ->
        nil
    end
  rescue
    # Geolix not configured or database not loaded
    _ -> nil
  end

  # Strategy 2: Cloudflare CF-IPCountry header
  defp cf_header(conn) do
    case get_req_header(conn, "cf-ipcountry") do
      [code | _] when byte_size(code) in 2..3 -> String.upcase(code)
      _ -> nil
    end
  end

  # --- Public API for admin dashboard ---

  @doc """
  Initialize the ETS table. Call once at application startup.
  """
  def init_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    end

    :ok
  end

  @doc """
  Returns a sorted list of `{country_code, count}` tuples, descending by count.

  ## Options

    * `:window` — one of `:all`, `:hour`, `:day`, `:week` (default: `:all`)
    * `:traffic` — `:all`, `:people` or `:crawlers` (default: `:all`)
  """
  def country_stats(opts \\ []) do
    keep? = traffic_filter(opts[:traffic] || :all)

    opts
    |> fold_requests(%{}, fn country, kind, _name, count, acc ->
      if keep?.(kind), do: Map.update(acc, country, count, &(&1 + count)), else: acc
    end)
    |> Enum.sort_by(fn {_country, count} -> count end, :desc)
  end

  @doc """
  Returns the total number of tracked requests across all countries.

  ## Options

    * `:window` — one of `:all`, `:hour`, `:day`, `:week` (default: `:all`)
    * `:traffic` — `:all`, `:people` or `:crawlers` (default: `:all`)
  """
  def total_requests(opts \\ []) do
    keep? = traffic_filter(opts[:traffic] || :all)

    fold_requests(opts, 0, fn _country, kind, _name, count, acc ->
      if keep?.(kind), do: acc + count, else: acc
    end)
  end

  @doc """
  Everything the admin Geo page shows for one window, in one ETS scan:

      %{
        total: integer, people: integer, crawlers: integer,
        countries: [%{country:, people:, crawlers:}],      # by total, desc
        kinds: [{kind, count}],                            # crawler kinds, desc
        bots: [%{name:, kind:, count:, rate_limited:}],    # desc
        rate_limited: %{people: integer, crawlers: integer}
      }

  ## Options

    * `:window` — one of `:all`, `:hour`, `:day`, `:week` (default: `:all`)
  """
  def traffic_snapshot(opts \\ []) do
    empty = %{countries: %{}, kinds: %{}, bots: %{}, limited: %{}, people: 0, crawlers: 0}

    acc =
      fold_all(opts, empty, fn
        {:rate_limited, kind, name}, count, acc -> tally_limited(acc, kind, name, count)
        {country, kind, name}, count, acc -> tally_request(acc, country, kind, name, count)
      end)

    {limited_people, limited_crawlers} =
      Enum.reduce(acc.limited, {0, 0}, fn {kind, count}, {people, crawlers} ->
        if Crawlers.crawler?(kind),
          do: {people, crawlers + count},
          else: {people + count, crawlers}
      end)

    %{
      total: acc.people + acc.crawlers,
      people: acc.people,
      crawlers: acc.crawlers,
      countries:
        acc.countries
        |> Enum.map(fn {country, counts} -> Map.put(counts, :country, country) end)
        |> Enum.sort_by(&(&1.people + &1.crawlers), :desc),
      kinds: Enum.sort_by(acc.kinds, fn {_kind, count} -> count end, :desc),
      bots:
        acc.bots
        |> Enum.map(fn {{name, kind}, counts} ->
          Map.merge(%{name: name, kind: kind, count: 0, rate_limited: 0}, counts)
        end)
        |> Enum.sort_by(&{&1.count, &1.rate_limited}, :desc),
      rate_limited: %{people: limited_people, crawlers: limited_crawlers}
    }
  end

  defp tally_limited(acc, kind, name, count) do
    acc = update_in(acc.limited, &Map.update(&1, kind, count, fn n -> n + count end))
    if name, do: update_bot(acc, name, kind, :rate_limited, count), else: acc
  end

  defp tally_request(acc, country, kind, name, count) do
    crawler? = Crawlers.crawler?(kind)
    side = if crawler?, do: :crawlers, else: :people

    acc =
      acc
      |> Map.update!(side, &(&1 + count))
      |> update_in(
        [:countries, Access.key(country, %{people: 0, crawlers: 0}), side],
        &(&1 + count)
      )

    if crawler? do
      acc
      |> update_in([:kinds], &Map.update(&1, kind, count, fn n -> n + count end))
      |> update_bot(name, kind, :count, count)
    else
      acc
    end
  end

  defp update_bot(acc, name, kind, field, count) do
    update_in(acc, [:bots, Access.key({name, kind}, %{}), Access.key(field, 0)], &(&1 + count))
  end

  @doc """
  Reset all counters (useful from admin panel).
  """
  def reset_stats do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc """
  Remove minute buckets older than the retention period (#{@retention_minutes} minutes).
  Called periodically by `GamendWeb.GeoCountryCleaner`.
  """
  def cleanup_old_buckets do
    if :ets.whereis(@table) != :undefined do
      cutoff = current_minute() - @retention_minutes
      :ets.select_delete(@table, [{{{:_, :_, :_, :"$1"}, :_}, [{:<, :"$1", cutoff}], [true]}])
    else
      0
    end
  end

  @doc """
  Returns whether Geolix has a country database loaded.
  """
  def geoip_available? do
    case Application.get_env(:geolix, :databases) do
      databases when is_list(databases) and databases != [] -> true
      _ -> false
    end
  end

  @doc """
  Single-pass dashboard stats, all traffic (people and crawlers). Returns a
  map with all-time and 1h data in one ETS scan.

  Returns:

      %{
        stats_all: [{country, count}, ...],
        total_all: integer,
        stats_1h: [{country, count}, ...],
        total_1h: integer,
        crawlers_1h: integer
      }
  """
  def dashboard_stats do
    cutoff_1h = minute_cutoff(:hour)

    {by_country_all, by_country_1h, total_all, total_1h, crawlers_1h} =
      fold_buckets(
        fn
          {country, kind, _name, minute}, count, {all, h1, t_all, t_1h, c_1h}
          when is_binary(country) ->
            all = Map.update(all, country, count, &(&1 + count))
            t_all = t_all + count

            if minute >= cutoff_1h do
              h1 = Map.update(h1, country, count, &(&1 + count))
              c_1h = if Crawlers.crawler?(kind), do: c_1h + count, else: c_1h
              {all, h1, t_all, t_1h + count, c_1h}
            else
              {all, h1, t_all, t_1h, c_1h}
            end

          _key, _count, acc ->
            acc
        end,
        {%{}, %{}, 0, 0, 0}
      )

    sort_desc = fn map ->
      map |> Enum.sort_by(fn {_, c} -> c end, :desc)
    end

    %{
      stats_all: sort_desc.(by_country_all),
      total_all: total_all,
      stats_1h: sort_desc.(by_country_1h),
      total_1h: total_1h,
      crawlers_1h: crawlers_1h
    }
  end

  # --- Internal ---

  # Request rows only (not the rate limiter's), inside the window.
  defp fold_requests(opts, acc, fun) do
    fold_all(opts, acc, fn
      {country, kind, name}, count, acc when is_binary(country) ->
        fun.(country, kind, name, count, acc)

      _key, _count, acc ->
        acc
    end)
  end

  # Every row inside the window, keyed without its minute.
  defp fold_all(opts, acc, fun) do
    cutoff = minute_cutoff(opts[:window] || :all)

    fold_buckets(
      fn
        {a, kind, name, minute}, count, acc when minute >= cutoff ->
          fun.({a, kind, name}, count, acc)

        _key, _count, acc ->
          acc
      end,
      acc
    )
  end

  defp fold_buckets(fun, acc) do
    if :ets.whereis(@table) == :undefined do
      acc
    else
      :ets.foldl(fn {key, count}, acc -> fun.(key, count, acc) end, acc, @table)
    end
  end

  defp traffic_filter(:all), do: fn _kind -> true end
  defp traffic_filter(:people), do: &(not Crawlers.crawler?(&1))
  defp traffic_filter(:crawlers), do: &Crawlers.crawler?/1

  defp current_minute, do: System.system_time(:second) |> div(60)

  defp minute_cutoff(:all), do: 0
  defp minute_cutoff(:hour), do: current_minute() - 60
  defp minute_cutoff(:day), do: current_minute() - 1440
  defp minute_cutoff(:week), do: current_minute() - 10_080

  # A request row is `{country, kind, name, minute}`; a 429 is
  # `{:rate_limited, kind, name, minute}` (an atom where the country goes).
  defp increment({first, kind, name}) do
    if :ets.whereis(@table) != :undefined do
      key = {first, kind, name, current_minute()}
      :ets.update_counter(@table, key, {2, 1}, {key, 0})
    end
  end
end
