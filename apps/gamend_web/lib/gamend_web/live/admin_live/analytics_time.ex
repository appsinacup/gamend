defmodule GamendWeb.AdminLive.AnalyticsTime do
  @moduledoc """
  Analytics → Time: how long accounts spend in the game per day, and where,
  worked out from the rows already stored (`Gamend.Analytics.TimeSpent`:
  analytics events and plays, a gap of more than the idle limit between two
  of them is time away). The average and median per account on a day it
  came, the total, per day, how the account-days spread, and the time per
  area (the catalogue's `overview/0` `time`) and per detail (a game). For
  one segment over 7, 30 or 90 UTC days. Read-only.
  """
  use GamendWeb, :live_view

  import GamendWeb.AdminLive.AnalyticsComponents
  import GamendWeb.Charts

  alias Gamend.Analytics
  alias Gamend.Analytics.Segment
  alias Gamend.Analytics.TimeSpent
  alias GamendWeb.TimeText

  require GamendWeb.FilterValue, as: FilterValue
  require GamendWeb.UrlParam, as: UrlParam

  @windows [7, 30, 90]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Admin · Analytics · Time")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:segment, Segment.parse(params["segment"]))
     |> assign(:trait, Segment.parse_trait(params["trait"]))
     |> assign(:traits, Analytics.trait_options())
     |> assign(:days, int_param(params, UrlParam.days(), @windows, 30))
     |> load()}
  end

  event("refresh")
  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket, true)}

  event("trait", trait: :string)

  def handle_event("trait", params, socket),
    do: {:noreply, push_patch(socket, to: here(socket.assigns, %{"trait" => params["trait"]}))}

  # Shared by the HTTP render and the socket's for half a minute, as the
  # overview's (`GamendWeb.AdminLive.Analytics`); Refresh computes again.
  defp load(socket, fresh? \\ false) do
    %{segment: segment, trait: trait, days: days} = socket.assigns
    today = Date.utc_today()
    key = {:admin_analytics_time, segment, trait, days, today}
    if fresh?, do: Gamend.Cache.delete(key)

    report =
      Gamend.Cache.cached(key, [ttl: :timer.seconds(30)], fn ->
        _ = Analytics.flush()
        TimeSpent.report(days, today, segment: Segment.with_trait(segment, trait))
      end)

    socket
    |> assign(:report, report)
    |> assign(:bucket_total, Enum.sum_by(report.buckets, & &1.count))
  end

  defp here(assigns, changes) do
    params =
      Map.merge(
        %{
          "segment" => Atom.to_string(assigns.segment),
          "trait" => Segment.trait_param(assigns.trait),
          "days" => assigns.days
        },
        changes
      )

    link_to("/admin/analytics/time", params, %{
      "segment" => FilterValue.everything(),
      "days" => "30"
    })
  end

  # Seconds as `GamendWeb.TimeText.duration/2` writes them ("9m 1s"); nil a dash.
  defp span(nil), do: "—"
  defp span(seconds) when is_number(seconds), do: TimeText.duration(round(seconds))

  defp minutes(nil), do: 0
  defp minutes(seconds), do: Float.round(seconds / 60, 1)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <.analytics_header
          tab="time"
          note={"Time an account spent, from the rows already stored: from one thing it did to the next, when at most #{span(@report.idle_seconds)} apart. A floor: the time after its last move of a visit is not counted, and a visitor with no account leaves no rows. UTC days, today so far."}
        >
          <:controls>
            <.switch
              label="Segment"
              options={for s <- Segment.all(), do: {s, Segment.label(s)}}
              selected={@segment}
              to={&here(assigns, %{"segment" => Atom.to_string(&1)})}
            />
            <.trait_picker traits={@traits} selected={@trait} />
            <.switch
              label="Window"
              options={[{7, "7 days"}, {30, "30 days"}, {90, "90 days"}]}
              selected={@days}
              to={&here(assigns, %{"days" => &1})}
            />
            <button phx-click="refresh" class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-path-solid" class="size-4" /> Refresh
            </button>
          </:controls>
        </.analytics_header>

        <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
          <.stat
            id="stat-time-avg"
            title="Avg a day"
            value={span(@report.per_day_avg)}
            desc="per account, on a day it came"
          />
          <.stat
            id="stat-time-median"
            title="Median a day"
            value={span(@report.per_day_median)}
            desc="half spent less, half more"
          />
          <.stat
            title="Per account"
            value={span(@report.per_person)}
            desc={"all #{@days} days together"}
          />
          <.stat title="Total" value={span(@report.seconds)} desc={"last #{@days} days"} />
          <.stat title="Accounts" value={num(@report.people)} desc="with any time" />
          <.stat title="Account-days" value={num(@report.account_days)} desc="an account on a day" />
        </div>

        <.panel>
          <div class="grid gap-6 md:grid-cols-2">
            <.bars
              id="chart-time-avg"
              title="Avg minutes per account a day"
              points={for r <- @report.series, do: {r.day, minutes(r.avg)}}
              summary={"median #{span(@report.per_day_median)}"}
            />
            <.bars
              id="chart-time-total"
              title="Total hours a day"
              points={for r <- @report.series, do: {r.day, Float.round(r.seconds / 3_600, 1)}}
              summary={"#{span(@report.seconds)} in #{@days} days"}
            />
          </div>
        </.panel>

        <div class="grid gap-4 md:grid-cols-2">
          <.panel title="Where the time goes" id="analytics-time-areas" class="space-y-3">
            <p class="text-xs text-muted">
              Each stretch is filed under where the account was when it began. Avg is per account
              on a day it was there.
            </p>
            <.empty_state :if={@report.areas == []} compact title="No time yet." />
            <table :if={@report.areas != []} class="table table-sm">
              <thead>
                <tr>
                  <th>Area</th>
                  <th class="text-right">Share</th>
                  <th class="text-right">Total</th>
                  <th class="text-right">Avg a day</th>
                  <th class="text-right">Accounts</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={a <- @report.areas}>
                  <td>{a.label}</td>
                  <td class="text-right tabular-nums">{pct(a.share)}</td>
                  <td class="text-right tabular-nums">{span(a.seconds)}</td>
                  <td class="text-right tabular-nums">{span(a.avg)}</td>
                  <td class="text-right tabular-nums">{num(a.people)}</td>
                </tr>
              </tbody>
            </table>
          </.panel>

          <.panel title="How long a day" id="analytics-time-buckets" class="space-y-3">
            <p class="text-xs text-muted">
              The account-days of the window, by how long the account spent that day.
            </p>
            <div class="space-y-2">
              <div
                :for={bucket <- @report.buckets}
                class="grid grid-cols-[6rem_1fr_7rem] items-center gap-2 text-sm"
              >
                <span>{bucket.label}</span>
                <div class="h-2 rounded-full bg-base-200">
                  <div
                    class="h-2 rounded-full bg-primary/80"
                    style={"width: #{part_width(bucket.count, @bucket_total)}%"}
                  />
                </div>
                <span class="text-right tabular-nums text-muted">
                  {num(bucket.count)} · {pct(part_of(bucket.count, @bucket_total))}
                </span>
              </div>
            </div>
          </.panel>
        </div>

        <.panel :if={@report.details != []} title="By kind" id="analytics-time-details">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Kind</th>
                <th>Area</th>
                <th class="text-right">Share</th>
                <th class="text-right">Total</th>
                <th class="text-right">Avg a day</th>
                <th class="text-right">Accounts</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={d <- @report.details}>
                <td class="font-mono">{d.label}</td>
                <td>{d.area_label}</td>
                <td class="text-right tabular-nums">{pct(d.share)}</td>
                <td class="text-right tabular-nums">{span(d.seconds)}</td>
                <td class="text-right tabular-nums">{span(d.avg)}</td>
                <td class="text-right tabular-nums">{num(d.people)}</td>
              </tr>
            </tbody>
          </table>
        </.panel>

        <.panel title="Per day">
          <div class="overflow-x-auto">
            <table class="table table-sm table-zebra" id="analytics-time-days">
              <thead>
                <tr>
                  <th>Day (UTC)</th>
                  <th class="text-right">Accounts</th>
                  <th class="text-right">Total</th>
                  <th class="text-right">Avg</th>
                  <th class="text-right">Median</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- Enum.reverse(@report.series)}>
                  <%!-- time-ok: a UTC calendar day, the row's key --%>
                  <td class="font-mono">{Date.to_iso8601(row.day)}</td>
                  <td class="text-right tabular-nums">{num(row.people)}</td>
                  <td class="text-right tabular-nums">{span(row.seconds)}</td>
                  <td class="text-right tabular-nums">{span(row.avg)}</td>
                  <td class="text-right tabular-nums">{span(row.median)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </.panel>
      </div>
    </Layouts.app>
    """
  end
end
