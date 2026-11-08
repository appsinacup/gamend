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
  alias Gamend.Analytics.Catalog
  alias Gamend.Analytics.Segment

  require GamendWeb.FilterValue, as: FilterValue
  require GamendWeb.UrlParam, as: UrlParam

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
     |> assign(:days, int_param(params, UrlParam.days(), @windows, 30))
     |> load()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket, true)}

  # A view renders twice (the HTTP page, then the socket), and at a million
  # players one computation takes seconds, so the two share it for half a
  # minute. Refresh computes again.
  defp load(socket, fresh? \\ false) do
    %{segment: segment, days: days} = socket.assigns
    today = Date.utc_today()
    key = {:admin_analytics_overview, segment, days, today}
    if fresh?, do: Gamend.Cache.delete(key)

    data =
      Gamend.Cache.cached(key, [ttl: :timer.seconds(30)], fn ->
        # Gathered for up to a flush window; a reader wants now.
        _ = Analytics.flush()
        opts = [segment: segment]

        %{
          summary: Analytics.summary(today, opts),
          series: Analytics.daily_series(days, today, opts),
          active_days: Analytics.active_days(today, opts),
          cohorts: Analytics.weekly_cohorts(today, opts),
          activation: Analytics.activation(today, opts),
          funnel: Analytics.funnel(days, today),
          money: Analytics.money(days, today)
        }
      end)

    overview = Catalog.overview()

    socket
    |> assign(data)
    |> assign(:overview, overview)
    |> assign(:meanings, meanings(data.summary, overview.bands))
    |> assign(:active_total, Enum.sum_by(data.active_days, & &1.users))
  end

  defp here(assigns, changes) do
    params =
      Map.merge(
        %{"segment" => Atom.to_string(assigns.segment), "days" => assigns.days},
        changes
      )

    link_to("/admin/analytics", params, %{"segment" => FilterValue.everything(), "days" => "30"})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <.analytics_header
          tab="overview"
          note={"Accounts seen per UTC day, as of #{Date.to_iso8601(@summary.day)}. Registered = an email or a provider; Guests = a device or a browser only, as the account is now. Visitors without an account are in Counters. Hover a number for what it means."}
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
          <.stat
            title="DAU"
            value={num(@summary.dau)}
            desc="today so far"
            hint={hint(@meanings, "DAU")}
          />
          <.stat
            title="WAU"
            value={num(@summary.wau)}
            desc="last 7 days"
            hint={hint(@meanings, "WAU")}
          />
          <.stat
            title="MAU"
            value={num(@summary.mau)}
            desc="last 30 days"
            hint={hint(@meanings, "MAU")}
          />
          <.stat
            id="stat-stickiness"
            title="Stickiness"
            value={pct(@summary.stickiness)}
            desc={"avg DAU #{num(Float.round(@summary.dau_7d_avg * 1.0, 1))} ÷ MAU"}
            band={band(@summary.stickiness, @overview.bands[:stickiness])}
            hint={hint(@meanings, "Stickiness")}
          />
          <.stat
            id="stat-d1"
            title="D1"
            value={pct(@summary.d1)}
            desc={"back the next day · n=#{num(@summary.d1_cohort)}"}
            band={band(@summary.d1, @overview.bands[:d1])}
            hint={hint(@meanings, "D1")}
          />
          <.stat
            id="stat-d7"
            title="D7"
            value={pct(@summary.d7)}
            desc={"back on day 7 · n=#{num(@summary.d7_cohort)}"}
            band={band(@summary.d7, @overview.bands[:d7])}
            hint={hint(@meanings, "D7")}
          />
          <.stat
            id="stat-d30"
            title="D30"
            value={pct(@summary.d30)}
            desc={"back on day 30 · n=#{num(@summary.d30_cohort)}"}
            band={band(@summary.d30, @overview.bands[:d30])}
            hint={hint(@meanings, "D30")}
          />
          <.stat
            title="Payers"
            value={pct(@summary.conversion_30d)}
            desc={"#{@summary.payers_30d} of MAU, 30d"}
            hint={hint(@meanings, "Payers")}
          />
        </div>

        <p class="text-xs text-muted">
          New accounts: {num(@summary.new_users_7d)} in the last 7 days, {num(@summary.new_users_30d)} in the last 30. Retention is pooled over the sign-ups of the last 60 days{since_note(
            @summary.retention_since
          )} that have reached each horizon (a D7 needs a sign-up at least 7 days old); n is how many accounts a rate pools, and "—" means none yet.
        </p>

        <.panel>
          <div class="grid gap-6 md:grid-cols-2">
            <.stacked
              id="chart-active"
              title="Active: returning and new"
              series={["Returning", "New"]}
              points={for r <- @series, do: {r.day, [r.returning, r.new_active]}}
              summary={"today #{num(@summary.dau)}"}
            />
            <.bars
              id="chart-new"
              title="New accounts"
              points={for r <- @series, do: {r.day, r.new_users}}
              summary={"#{num(Enum.sum_by(@series, & &1.new_users))} in #{@days} days"}
            />
          </div>
        </.panel>

        <div class="grid gap-4 md:grid-cols-2">
          <.panel title="Return visits" id="analytics-return-visits" class="space-y-3">
            <p class="text-xs text-muted">
              The accounts seen in the last 30 days, by how many of those days each came.
              Seen on one day only is a visit nobody repeated.
            </p>
            <div class="space-y-2">
              <div
                :for={bucket <- @active_days}
                class="grid grid-cols-[5.5rem_1fr_7rem] items-center gap-2 text-sm"
              >
                <span>{bucket.label}</span>
                <div class="h-2 rounded-full bg-base-200">
                  <div
                    class="h-2 rounded-full bg-primary/80"
                    style={"width: #{share_width(bucket.users, @active_total)}%"}
                  />
                </div>
                <span class="text-right tabular-nums text-muted">
                  {num(bucket.users)} · {pct(share(bucket.users, @active_total))}
                </span>
              </div>
            </div>
          </.panel>

          <.panel title="Activation" id="analytics-activation" class="space-y-3">
            <%= if @activation do %>
              <p class="text-xs text-muted">
                Of the accounts made in the last 30 days{since_note(@summary.retention_since)}, the
                share that {String.downcase(@activation.label)} on the day they were made, and how
                many of each came back the next day.
              </p>
              <div class="flex flex-wrap gap-x-8 gap-y-3">
                <div>
                  <div class="text-2xl font-bold">{pct(@activation.rate)}</div>
                  <div class="text-xs text-muted">
                    {num(@activation.activated)} of {num(@activation.new)} new accounts
                  </div>
                </div>
                <div>
                  <div class="text-2xl font-bold">{pct(@activation.d1_activated)}</div>
                  <div class="text-xs text-muted">
                    D1 of those who did · n={num(@activation.d1_activated_cohort)}
                  </div>
                </div>
                <div>
                  <div class="text-2xl font-bold">{pct(@activation.d1_other)}</div>
                  <div class="text-xs text-muted">
                    D1 of the rest · n={num(@activation.d1_other_cohort)}
                  </div>
                </div>
              </div>
            <% else %>
              <p class="text-sm text-muted">
                No activation declared: the game names the events that count as a first real use
                (`activation` in its analytics catalogue's `overview/0`).
              </p>
            <% end %>
          </.panel>
        </div>

        <.panel title="Weekly cohorts" id="analytics-cohorts" class="space-y-3">
          <p class="text-xs text-muted">
            A row is a week of sign-ups, Monday to Sunday{since_note(@summary.retention_since)}; a
            cell is the share of them seen during their own week 1, 2, 3 or 4 after signing up.
            Empty until every account of the week has lived through it. A darker cell is a higher
            share.
          </p>
          <div :if={@cohorts != []} class="overflow-x-auto">
            <table class="table table-sm" id="analytics-cohorts-table">
              <thead>
                <tr>
                  <th>Week of</th>
                  <th class="text-right">Accounts</th>
                  <th :for={k <- 1..4} class="text-right">Week {k}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={cohort <- @cohorts}>
                  <td class="font-mono">{Date.to_iso8601(cohort.from)}</td>
                  <td class="text-right tabular-nums">{num(cohort.size)}</td>
                  <td
                    :for={cell <- cohort.cells}
                    class="text-right tabular-nums"
                    style={heat(cell.rate)}
                    title={cell.rate && "#{num(cell.users)} of #{num(cohort.size)}"}
                  >
                    {cell.rate && pct(cell.rate)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@cohorts == []} class="text-sm text-muted">No sign-up week yet.</p>
        </.panel>

        <div class="grid gap-4 md:grid-cols-2">
          <.panel title={"Funnel, last #{@days} days"} id="analytics-funnel" class="space-y-3">
            <p class="text-xs text-muted">
              Each step and its share of the one before, for every account whatever the segment. A
              step in events counts each time (a visitor too), one in people each account once, so
              no share is drawn where the two meet.
            </p>
            <table class="table table-sm">
              <tbody>
                <tr :for={step <- @funnel}>
                  <td>{step.label}</td>
                  <td class="text-right tabular-nums">
                    {num(step.value)} <span class="text-xs text-muted">{step.unit}</span>
                  </td>
                  <td class="text-right tabular-nums text-muted">
                    {step.of_previous && pct(step.of_previous)}
                  </td>
                </tr>
              </tbody>
            </table>
          </.panel>

          <.panel title={"Money, last #{@days} days"} id="analytics-money" class="space-y-3">
            <dl class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1.5 text-sm">
              <dt>Revenue</dt>
              <dd class="text-right tabular-nums">{revenue_text(@money.revenue)}</dd>
              <dt>Payers</dt>
              <dd class="text-right tabular-nums">{num(@money.payers)}</dd>
              <dt>Checkouts opened</dt>
              <dd class="text-right tabular-nums">{num(@money.checkouts_opened)}</dd>
              <dt>Purchases</dt>
              <dd class="text-right tabular-nums">{num(@money.purchases)}</dd>
              <dt>Checkouts refused or failed</dt>
              <dd class="text-right tabular-nums">{num(@money.checkouts_refused)}</dd>
              <dt>Webhooks failed or refused</dt>
              <dd class="text-right tabular-nums" id="analytics-webhook-problems">
                <span :if={@money.webhook_problems > 0} class="badge badge-soft badge-sm badge-error">
                  {num(@money.webhook_problems)}
                </span>
                <span :if={@money.webhook_problems == 0}>0</span>
              </dd>
              <%= if @money.trials do %>
                <dt>Free trials started</dt>
                <dd class="text-right tabular-nums">{num(@money.trials.started)}</dd>
                <dt>Free trials running</dt>
                <dd class="text-right tabular-nums">{num(@money.trials.running)}</dd>
                <dt>Trial → paid, ever</dt>
                <dd class="text-right tabular-nums">
                  {pct(@money.trials.conversion)}
                  <span class="text-xs text-muted">
                    {num(@money.trials.paid)} of {num(@money.trials.taken)}
                  </span>
                </dd>
              <% end %>
            </dl>
          </.panel>
        </div>

        <.panel tag="details" id="analytics-meanings">
          <summary class="cursor-pointer text-sm font-semibold">What these numbers mean</summary>
          <dl class="mt-3 grid gap-x-6 gap-y-3 text-sm md:grid-cols-[10rem_1fr]">
            <%= for {name, text, bands} <- @meanings do %>
              <dt class="font-semibold">{name}</dt>
              <dd>
                {text}
                <span :if={bands} class="text-muted">{band_text(bands)}</span>
              </dd>
            <% end %>
            <dt class="font-semibold">Bands</dt>
            <dd>
              <.band_chip band={:good} /> <.band_chip band={:fair} /> <.band_chip band={:low} />
              The thresholds are mobile-app medians a game can set for itself (`bands` in its
              analytics catalogue's `overview/0`): a website where an account is made on the first
              click reads lower, and the week-to-week trend says more than the gap.
            </dd>
          </dl>
        </.panel>

        <.panel title="Per day">
          <div class="overflow-x-auto">
            <table class="table table-sm table-zebra" id="analytics-days">
              <thead>
                <tr>
                  <th>Day (UTC)</th>
                  <th class="text-right">Active</th>
                  <th class="text-right">Returning</th>
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
                  <td class="text-right tabular-nums">{num(row.returning)}</td>
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
            Returning is Active less the accounts made that day. WAU / MAU on a row are the distinct
            accounts of the 7 / 30 days ending that day, and Stick. is that day's Active ÷ MAU. D1 /
            D7 / D30 on a row are that day's sign-ups: the share seen again exactly 1 / 7 / 30 days
            later ("—" before the first day whose visits all count).
          </p>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  # What each headline number means, how it is counted and what is usual for
  # an app, with its bands: the tiles' hover text and the "What these
  # numbers mean" panel. `{name, text, bands | nil}`.
  defp meanings(summary, bands) do
    pooled = "Pooled over the sign-ups of the last 60 days#{since_note(summary.retention_since)}."

    [
      {"DAU", "Accounts seen today so far: the day is UTC, and partial until midnight.", nil},
      {"WAU", "Accounts seen on any of the last 7 days.", nil},
      {"MAU", "Accounts seen on any of the last 30 days.", nil},
      {"Stickiness",
       "How much of the month comes on an average day: the average DAU of the 7 full days " <>
         "before today ÷ MAU. A typical app is about 14%, the top quarter 20% " <>
         "and up, Duolingo about 37%.", bands[:stickiness]},
      {"D1",
       "Of the accounts made, the share seen again the next day. #{pooled} Across mobile " <>
         "apps about 25%; education apps about 15%.", bands[:d1]},
      {"D7",
       "Of the accounts made, the share seen again on the 7th day after. #{pooled} Across " <>
         "mobile apps 11–13%.", bands[:d7]},
      {"D30",
       "Of the accounts made, the share seen again on the 30th day after. #{pooled} Across " <>
         "mobile apps 5–7%; education apps 2–8%.", bands[:d30]},
      {"Payers", "Accounts with a completed purchase in the last 30 days ÷ MAU.", nil},
      {"Return visits",
       "How many of the last 30 days each active account came. Stickiness is low when most " <>
         "of the month came once.", nil},
      {"Activation",
       "The share of new accounts that did the thing the game counts as a first real use " <>
         "on their first day. It is the lever: those who do come back far more often.", nil},
      {"Weekly cohorts",
       "Retention by sign-up week: whether newer weeks keep more people than older ones.", nil},
      {"Funnel", "The steps from arriving to paying, each as a share of the one before.", nil}
    ]
  end

  defp hint(meanings, name) do
    case List.keyfind(meanings, name, 0) do
      {_name, text, nil} -> text
      {_name, text, bands} -> text <> " " <> band_text(bands)
      nil -> nil
    end
  end

  defp since_note(nil), do: ""

  defp since_note(%Date{} = day),
    do: ", from #{Date.to_iso8601(day)} (the first day whose visits all count)"

  defp share(_part, 0), do: nil
  defp share(part, total), do: part / total

  defp share_width(_part, 0), do: 0
  defp share_width(part, total), do: Float.round(part / total * 100, 1)

  # A cohort cell's shade: the theme's primary, stronger as the share grows
  # (a third retained is the darkest), so the grid reads at a glance.
  defp heat(nil), do: nil

  defp heat(rate) do
    strength = rate |> Kernel.*(120) |> min(40) |> round()
    "background-color: color-mix(in oklab, var(--color-primary) #{strength}%, transparent)"
  end

  # Revenue by currency, in major units.
  defp revenue_text([]), do: "0"

  defp revenue_text(revenue) do
    Enum.map_join(revenue, ", ", fn {currency, minor} ->
      "#{String.upcase(to_string(currency))} #{:erlang.float_to_binary(minor / 100, decimals: 2)}"
    end)
  end
end
