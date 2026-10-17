defmodule GamendWeb.AdminLive.Analytics do
  @moduledoc """
  Analytics → Overview: DAU / WAU / MAU, stickiness, D1 / D7 / D30 cohort
  retention and payer conversion, charts of active and new accounts and of
  stickiness per day, and the per-day table, for one segment (all /
  registered / guest) over 30 or 90 UTC days. The other tabs
  (`GamendWeb.AdminLive.AnalyticsComponents.tabs/0`) look at features,
  single events, one account, the counters and the economy. Read-only; the
  numbers come from `Gamend.Analytics`.
  """
  use GamendWeb, :live_view

  import GamendWeb.AdminLive.AnalyticsComponents
  import GamendWeb.Charts

  alias Gamend.Analytics
  alias Gamend.Analytics.Segment

  @windows [30, 90]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Admin · Analytics")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:segment, Segment.parse(params["segment"]))
     |> assign(:days, int_param(params, "days", @windows, 30))
     |> load()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    # Gathered for up to a flush window; a reader wants now.
    _ = Analytics.flush()
    today = Date.utc_today()
    opts = [segment: socket.assigns.segment]
    series = Analytics.daily_series(socket.assigns.days, today, opts)

    socket
    |> assign(:summary, Analytics.summary(today, opts))
    |> assign(:series, series)
  end

  defp here(assigns, changes) do
    params =
      Map.merge(
        %{"segment" => Atom.to_string(assigns.segment), "days" => assigns.days},
        changes
      )

    link_to("/admin/analytics", params, %{"segment" => "all", "days" => "30"})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <.analytics_header
          tab="overview"
          note={"Accounts seen per UTC day, as of #{Date.to_iso8601(@summary.day)}. Registered = an email or a provider; Guests = a device or a browser only, as the account is now. Visitors without an account are in Counters."}
        >
          <:controls>
            <.switch
              label="Segment"
              options={for s <- Segment.all(), do: {s, Segment.label(s)}}
              selected={@segment}
              to={&here(assigns, %{"segment" => Atom.to_string(&1)})}
            />
            <.switch
              label="Window"
              options={[{30, "30 days"}, {90, "90 days"}]}
              selected={@days}
              to={&here(assigns, %{"days" => &1})}
            />
            <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
          </:controls>
        </.analytics_header>

        <div class="grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-8">
          <.stat title="DAU" value={num(@summary.dau)} desc="seen today" />
          <.stat title="WAU" value={num(@summary.wau)} desc="last 7 days" />
          <.stat title="MAU" value={num(@summary.mau)} desc="last 30 days" />
          <.stat title="Stickiness" value={pct(@summary.stickiness)} desc="DAU ÷ MAU" />
          <.stat title="D1" value={pct(@summary.d1)} desc="back the next day" />
          <.stat title="D7" value={pct(@summary.d7)} desc="back on day 7" />
          <.stat title="D30" value={pct(@summary.d30)} desc="back on day 30" />
          <.stat
            title="Payers"
            value={pct(@summary.conversion_30d)}
            desc={"#{@summary.payers_30d} of MAU, 30d"}
          />
        </div>

        <p class="text-xs text-muted">
          New accounts: {num(@summary.new_users_7d)} in the last 7 days, {num(@summary.new_users_30d)} in the last 30. Retention is pooled over the cohorts of the last 60 days that have
          reached each horizon (a D7 needs a cohort at least 7 days old); "—" means none has yet.
        </p>

        <.panel>
          <div class="grid gap-6 md:grid-cols-3">
            <.bars
              id="chart-active"
              title="Active"
              points={for r <- @series, do: {r.day, r.active}}
              summary={"today #{num(@summary.dau)}"}
            />
            <.bars
              id="chart-new"
              title="New accounts"
              points={for r <- @series, do: {r.day, r.new_users}}
              summary={"#{num(Enum.sum_by(@series, & &1.new_users))} in #{@days} days"}
            />
            <.line
              id="chart-stickiness"
              title="Stickiness"
              points={for r <- @series, do: {r.day, r.stickiness}}
              summary="active ÷ MAU"
            />
          </div>
        </.panel>

        <.panel title="Per day">
          <div class="overflow-x-auto">
            <table class="table table-sm table-zebra" id="analytics-days">
              <thead>
                <tr>
                  <th>Day (UTC)</th>
                  <th class="text-right">Active</th>
                  <th class="text-right">WAU</th>
                  <th class="text-right">MAU</th>
                  <th class="text-right">Stick.</th>
                  <th class="text-right">New</th>
                  <th class="text-right">D1</th>
                  <th class="text-right">D7</th>
                  <th class="text-right">D30</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- Enum.reverse(@series)}>
                  <td class="font-mono">{Date.to_iso8601(row.day)}</td>
                  <td class="text-right tabular-nums">{num(row.active)}</td>
                  <td class="text-right tabular-nums">{num(row.wau)}</td>
                  <td class="text-right tabular-nums">{num(row.mau)}</td>
                  <td class="text-right tabular-nums">{pct(row.stickiness)}</td>
                  <td class="text-right tabular-nums">{num(row.new_users)}</td>
                  <td class="text-right tabular-nums">{pct(row.d1)}</td>
                  <td class="text-right tabular-nums">{pct(row.d7)}</td>
                  <td class="text-right tabular-nums">{pct(row.d30)}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="mt-2 text-xs text-muted">
            WAU / MAU on a row are the distinct accounts of the 7 / 30 days ending that day, and
            Stick. is that day's Active ÷ MAU. D1 / D7 / D30 on a row are that day's sign-up
            cohort: of the accounts made that day, the share seen again exactly 1 / 7 / 30 days
            later.
          </p>
        </.panel>
      </div>
    </Layouts.app>
    """
  end
end
