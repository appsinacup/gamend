defmodule GamendWeb.AdminLive.Geo do
  use GamendWeb, :live_view

  alias GamendWeb.Crawlers
  alias GamendWeb.Plugs.GeoCountry

  @refresh_interval 5_000

  @windows [
    {"1h", :hour},
    {"24h", :day},
    {"7d", :week},
    {"All", :all}
  ]

  @traffic [
    {"Everyone", :all},
    {"People", :people},
    {"Crawlers", :crawlers}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div class="flex items-center gap-3">
            <.link navigate={~p"/admin"} class="btn btn-surface btn-sm">&larr; Back to Admin</.link>
            <h1 class="text-xl font-bold">Geo Traffic</h1>
          </div>

          <div class="flex items-center gap-3">
            <span class="text-xs text-muted">
              Source:
              <span class="font-semibold">
                {if(@geoip_available?, do: "MMDB database", else: "CF-IPCountry header")}
              </span>
            </span>
            <button
              phx-click="reset_stats"
              data-confirm="Reset all geo traffic counters to zero?"
              class="btn btn-outline btn-error btn-xs"
            >
              Reset
            </button>
          </div>
        </div>

        <%!-- Time window and traffic selectors --%>
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex flex-wrap gap-2">
            <button
              :for={{label, window} <- @windows}
              phx-click="set_window"
              phx-value-window={window}
              class={[
                "btn btn-sm",
                if(@window == window, do: "btn-primary", else: "btn-ghost")
              ]}
            >
              {label}
            </button>
          </div>
          <div class="flex flex-wrap gap-2" id="geo-traffic">
            <button
              :for={{label, traffic} <- @traffic_options}
              id={"geo-traffic-#{traffic}"}
              phx-click="set_traffic"
              phx-value-traffic={traffic}
              class={[
                "btn btn-sm",
                if(@traffic == traffic, do: "btn-primary", else: "btn-ghost")
              ]}
            >
              {label}
            </button>
          </div>
        </div>

        <%!-- Summary stats --%>
        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          <div class="card bg-base-100 p-3 text-center">
            <div class="text-2xl font-bold font-mono">{format_number(@snapshot.total)}</div>
            <div class="text-xs text-muted">Requests</div>
          </div>
          <div class="card bg-base-100 p-3 text-center" id="geo-people">
            <div class="text-2xl font-bold font-mono">{format_number(@snapshot.people)}</div>
            <div class="text-xs text-muted">
              People &middot; {share(@snapshot.people, @snapshot.total)}%
            </div>
          </div>
          <div class="card bg-base-100 p-3 text-center" id="geo-crawlers">
            <div class="text-2xl font-bold font-mono">{format_number(@snapshot.crawlers)}</div>
            <div class="text-xs text-muted">
              Crawlers &middot; {share(@snapshot.crawlers, @snapshot.total)}%
            </div>
          </div>
          <div class="card bg-base-100 p-3 text-center" id="geo-rate-limited">
            <div class="text-2xl font-bold font-mono">
              {format_number(@snapshot.rate_limited.people + @snapshot.rate_limited.crawlers)}
            </div>
            <div class="text-xs text-muted">
              429s &middot; {format_number(@snapshot.rate_limited.people)} people, {format_number(
                @snapshot.rate_limited.crawlers
              )} crawlers
            </div>
          </div>
          <div class="card bg-base-100 p-3 text-center">
            <div class="text-2xl font-bold font-mono">{length(@stats)}</div>
            <div class="text-xs text-muted">Countries</div>
          </div>
          <div class="card bg-base-100 p-3 text-center">
            <div class="text-2xl font-bold font-mono">{format_number(@unknown_count)}</div>
            <div class="text-xs text-muted">Unknown (XX)</div>
          </div>
        </div>

        <%!-- MMDB status --%>
        <div :if={!@geoip_available?} class="alert alert-warning text-sm">
          <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
          <div>
            <div class="font-semibold">No GeoIP database loaded</div>
            <div class="text-xs opacity-80">
              Countries come only from Cloudflare's CF-IPCountry header; a request without
              it is counted as "XX" (Unknown). Download
              <a
                href="https://dev.maxmind.com/geoip/geolite2-free-geolocation-data"
                target="_blank"
                class="link"
              >
                GeoLite2-Country.mmdb
              </a>
              under <code class="bg-base-200 px-1 rounded">data</code>
              or set <code class="bg-base-200 px-1 rounded">GAMEND_CONTENT_GEOIP_DB_PATH</code>
              to a custom location to resolve countries from the client IP.
            </div>
          </div>
        </div>

        <%!-- Filter & sort --%>
        <div class="flex flex-col sm:flex-row gap-2 items-start sm:items-center">
          <.form
            for={%{}}
            id="geo-filter"
            phx-change="update_filter"
            phx-no-unused-field
            class="flex-1 w-full sm:w-auto"
          >
            <input
              id="geo-search"
              name="search"
              value={@search}
              placeholder="Filter by country code (e.g. US, DE, XX)"
              class="input input-sm w-full"
              phx-debounce="300"
            />
          </.form>
          <div class="flex items-center gap-2 text-xs text-muted">
            <span>Sort:</span>
            <button
              phx-click="toggle_sort"
              class="btn btn-ghost btn-xs"
            >
              {if @sort == :count, do: "By Count ↓", else: "By Code A→Z"}
            </button>
          </div>
        </div>

        <%!-- Country table --%>
        <div class="card bg-base-100 overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr class="text-xs text-muted">
                <th class="w-8">#</th>
                <th>Country</th>
                <th class="text-right">Requests</th>
                <th class="text-right">People</th>
                <th class="text-right">Crawlers</th>
                <th class="text-right w-20">%</th>
                <th class="w-1/3">Distribution</th>
              </tr>
            </thead>
            <tbody>
              <%= if @filtered_stats == [] do %>
                <tr>
                  <td colspan="7" class="text-center py-8 text-muted">
                    <%= if @stats == [] do %>
                      No geo data yet — traffic will appear as requests come in
                    <% else %>
                      No countries match your filter
                    <% end %>
                  </td>
                </tr>
              <% else %>
                <tr
                  :for={{idx, country, count, pct, row} <- @filtered_stats}
                  class={[
                    country == "XX" && "opacity-60"
                  ]}
                >
                  <td class="font-mono text-muted">{idx}</td>
                  <td>
                    <span class="text-lg mr-1">{GamendWeb.AdminLive.Shared.country_flag(country)}</span>
                    <span class="font-mono font-semibold">{country}</span>
                    <span :if={country == "XX"} class="text-xs text-muted ml-1">
                      (Unknown)
                    </span>
                  </td>
                  <td class="text-right font-mono">{format_number(count)}</td>
                  <td class="text-right font-mono text-muted">
                    {format_number(row.people)}
                  </td>
                  <td class="text-right font-mono text-muted">
                    {format_number(row.crawlers)}
                  </td>
                  <td class="text-right font-mono text-muted">{pct}%</td>
                  <td>
                    <div class="w-full bg-base-200 rounded-full h-2">
                      <div
                        class={[
                          "h-2 rounded-full transition-all duration-500",
                          bar_color(idx)
                        ]}
                        style={"width: #{pct}%"}
                      >
                      </div>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <%!-- Crawlers --%>
        <div class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-muted">
            Crawlers
          </h2>
          <div :if={@snapshot.kinds != []} class="flex flex-wrap gap-2" id="geo-crawler-kinds">
            <span
              :for={{kind, count} <- @snapshot.kinds}
              class={["badge badge-sm", kind == :impostor && "badge-error"]}
            >
              {Crawlers.label(kind)} &middot; {format_number(count)}
            </span>
          </div>
          <div class="card bg-base-100 overflow-x-auto">
            <table class="table table-sm" id="geo-crawlers-table">
              <thead>
                <tr class="text-xs text-muted">
                  <th class="w-8">#</th>
                  <th>Crawler</th>
                  <th>Kind</th>
                  <th class="text-right">Requests</th>
                  <th class="text-right w-20">%</th>
                  <th class="text-right">429s</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@snapshot.bots == []}>
                  <td colspan="6" class="text-center py-8 text-muted">
                    No crawler traffic in this window
                  </td>
                </tr>
                <tr
                  :for={{bot, idx} <- Enum.with_index(@snapshot.bots, 1)}
                  id={"geo-bot-#{bot.kind}-#{idx}"}
                  class={[bot.kind == :impostor && "text-error"]}
                >
                  <td class="font-mono text-muted">{idx}</td>
                  <td class="font-semibold">{bot.name}</td>
                  <td class="text-muted">{Crawlers.label(bot.kind)}</td>
                  <td class="text-right font-mono">{format_number(bot.count)}</td>
                  <td class="text-right font-mono text-muted">
                    {share(bot.count, @snapshot.crawlers)}%
                  </td>
                  <td class={[
                    "text-right font-mono",
                    if(bot.rate_limited > 0, do: "text-warning", else: "text-muted")
                  ]}>
                    {format_number(bot.rate_limited)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-xs text-muted">
            Named by user-agent (<code class="bg-base-200 px-1 rounded">GamendWeb.Crawlers</code>).
            A request naming a search engine is checked against that engine's reverse DNS {if(
              @verify?,
              do: "(on)",
              else: "(off: GAMEND_CRAWLERS_VERIFY)"
            )}; a failed
            check counts as a fake search bot. Static files are not counted.
          </p>
        </div>

        <%!-- Footer --%>
        <div class="text-xs text-muted text-center">
          Auto-refreshes every {div(@refresh_interval, 1000)}s &middot;
          7-day retention &middot;
          Data is in-memory (ETS) &middot;
          Exported to Prometheus as <code class="bg-base-200 px-1 rounded">gamend_geo_requests_total</code>,
          <code class="bg-base-200 px-1 rounded">gamend_crawler_requests_total</code>
          and <code class="bg-base-200 px-1 rounded">gamend_crawler_rate_limited_total</code>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    {:ok,
     socket
     |> assign(
       window: :all,
       windows: @windows,
       traffic: :all,
       traffic_options: @traffic,
       geoip_available?: GeoCountry.geoip_available?(),
       verify?: Gamend.Settings.get(Crawlers, :verify),
       search: "",
       sort: :count,
       refresh_interval: @refresh_interval
     )
     |> load_snapshot()}
  end

  @impl true
  def handle_event("set_window", %{"window" => window_str}, socket) do
    window =
      Enum.find_value(@windows, :all, fn {_, w} -> if to_string(w) == window_str, do: w end)

    {:noreply, socket |> assign(window: window) |> load_snapshot()}
  end

  @impl true
  def handle_event("set_traffic", %{"traffic" => traffic_str}, socket) do
    traffic =
      Enum.find_value(@traffic, :all, fn {_, t} -> if to_string(t) == traffic_str, do: t end)

    {:noreply, socket |> assign(traffic: traffic) |> compute_derived()}
  end

  @impl true
  def handle_event("update_filter", %{"search" => search}, socket) do
    {:noreply, socket |> assign(search: String.upcase(String.trim(search))) |> compute_derived()}
  end

  @impl true
  def handle_event("toggle_sort", _params, socket) do
    new_sort = if socket.assigns.sort == :count, do: :alpha, else: :count
    {:noreply, socket |> assign(sort: new_sort) |> compute_derived()}
  end

  @impl true
  def handle_event("reset_stats", _params, socket) do
    GeoCountry.reset_stats()

    {:noreply,
     socket
     |> load_snapshot()
     |> put_flash(:info, "Geo traffic counters reset.")}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()

    {:noreply,
     socket
     |> assign(geoip_available?: GeoCountry.geoip_available?())
     |> load_snapshot()}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Derived state ---

  defp load_snapshot(socket) do
    socket
    |> assign(snapshot: GeoCountry.traffic_snapshot(window: socket.assigns.window))
    |> compute_derived()
  end

  defp compute_derived(socket) do
    %{snapshot: snapshot, traffic: traffic, search: search, sort: sort} = socket.assigns

    # `{country, count, row}` for the chosen traffic, busiest first.
    stats =
      snapshot.countries
      |> Enum.map(fn row -> {row.country, traffic_count(row, traffic), row} end)
      |> Enum.reject(fn {_country, count, _row} -> count == 0 end)
      |> Enum.sort_by(fn {_country, count, _row} -> count end, :desc)

    total = traffic_count(snapshot, traffic)

    sorted =
      case sort do
        :count -> stats
        :alpha -> Enum.sort_by(stats, fn {country, _, _} -> country end)
      end

    filtered =
      if search == "" do
        sorted
      else
        Enum.filter(sorted, fn {country, _, _} -> String.contains?(country, search) end)
      end

    # Add rank, percentage
    filtered_with_meta =
      filtered
      |> Enum.with_index(1)
      |> Enum.map(fn {{country, count, row}, idx} ->
        {idx, country, count, share(count, total), row}
      end)

    unknown_count = Enum.find_value(stats, 0, fn {c, cnt, _} -> if c == "XX", do: cnt end)

    assign(socket,
      stats: stats,
      filtered_stats: filtered_with_meta,
      unknown_count: unknown_count
    )
  end

  defp traffic_count(row, :all), do: row.people + row.crawlers
  defp traffic_count(row, :people), do: row.people
  defp traffic_count(row, :crawlers), do: row.crawlers

  defp share(_count, total) when total in [0, nil], do: 0.0
  defp share(count, total), do: Float.round(count / total * 100, 1)

  # --- Helpers ---

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval)

  defp format_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n) when is_number(n), do: to_string(n)
  defp format_number(n), do: to_string(n)

  defp bar_color(rank) when rank <= 1, do: "bg-primary"
  defp bar_color(rank) when rank <= 3, do: "bg-secondary"
  defp bar_color(rank) when rank <= 5, do: "bg-accent"
  defp bar_color(_), do: "bg-base-content/20"
end
