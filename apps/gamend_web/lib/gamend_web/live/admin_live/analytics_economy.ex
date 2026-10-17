defmodule GamendWeb.AdminLive.AnalyticsEconomy do
  @moduledoc """
  Analytics → Economy: what each wallet currency gained and lost, per day
  and per ledger `reason`, straight from `ledger_entries`
  (`Gamend.Analytics.economy_flow/2`). Sources are positive, sinks
  negative; the net is what inflates or drains balances. One currency at a
  time (the busiest by default), 7 / 30 / 90 days. The ledger itself, entry
  by entry, is `/admin/economy`.
  """
  use GamendWeb, :live_view

  import GamendWeb.AdminLive.AnalyticsComponents
  import GamendWeb.Charts

  alias Gamend.Analytics

  @windows [7, 30, 90]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Admin · Analytics · Economy")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:days, int_param(params, "days", @windows, 30))
     |> assign(:currency_param, params["currency"])
     |> load()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    today = Date.utc_today()
    days = socket.assigns.days
    flow = Analytics.economy_flow(days, today: today)

    currencies =
      flow
      |> Enum.group_by(& &1.currency, & &1.entries)
      |> Enum.map(fn {c, entries} -> {c, Enum.sum(entries)} end)
      |> Enum.sort_by(fn {c, n} -> {-n, c} end)
      |> Enum.map(&elem(&1, 0))

    currency =
      if socket.assigns.currency_param in currencies,
        do: socket.assigns.currency_param,
        else: List.first(currencies)

    rows = Enum.filter(flow, &(&1.currency == currency))
    by_day = Enum.group_by(rows, & &1.day)
    window = Enum.map((days - 1)..0//-1, &Date.add(today, -&1))

    per_day =
      for day <- window do
        entries = Map.get(by_day, day, [])
        granted = Enum.sum_by(entries, & &1.granted)
        spent = Enum.sum_by(entries, & &1.spent)
        %{day: day, granted: granted, spent: spent, net: granted - spent}
      end

    socket
    |> assign(:currencies, currencies)
    |> assign(:currency, currency)
    |> assign(:per_day, per_day)
    |> assign(
      :totals,
      if(currency, do: Analytics.economy_totals(days, today: today, currency: currency), else: [])
    )
  end

  defp here(assigns, changes) do
    link_to(
      "/admin/analytics/economy",
      Map.merge(%{"days" => assigns.days, "currency" => assigns.currency}, changes),
      %{"days" => "30"}
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <.analytics_header
          tab="economy"
          note="Every wallet grant and spend, by the ledger reason the game gave. The Net column is what inflates or drains balances."
        >
          <:controls>
            <.switch
              :if={@currencies != []}
              label="Currency"
              options={for c <- @currencies, do: {c, c}}
              selected={@currency}
              to={&here(assigns, %{"currency" => &1})}
            />
            <.switch
              label="Window"
              options={for d <- [7, 30, 90], do: {d, "#{d} days"}}
              selected={@days}
              to={&here(assigns, %{"days" => &1})}
            />
            <.link navigate={~p"/admin/economy"} class="btn btn-ghost btn-sm">Ledger</.link>
          </:controls>
        </.analytics_header>

        <.empty_state :if={is_nil(@currency)} title="No ledger entries in the window." />

        <%= if @currency do %>
          <div class="grid grid-cols-2 gap-3 md:grid-cols-3">
            <.stat title="Granted" value={num(Enum.sum_by(@per_day, & &1.granted))} desc={@currency} />
            <.stat title="Spent" value={num(Enum.sum_by(@per_day, & &1.spent))} desc={@currency} />
            <.stat title="Net" value={num(Enum.sum_by(@per_day, & &1.net))} desc="granted − spent" />
          </div>

          <.panel>
            <div class="grid gap-6 md:grid-cols-2">
              <.bars
                id="chart-granted"
                title={"Granted · #{@currency}"}
                points={for r <- @per_day, do: {r.day, r.granted}}
              />
              <.bars
                id="chart-spent"
                title={"Spent · #{@currency}"}
                points={for r <- @per_day, do: {r.day, r.spent}}
              />
            </div>
          </.panel>

          <.panel title={"By reason · last #{@days} days"}>
            <div class="overflow-x-auto">
              <table class="table table-sm table-zebra" id="economy-reasons">
                <thead>
                  <tr>
                    <th>Reason</th>
                    <th class="text-right">Granted</th>
                    <th class="text-right">Spent</th>
                    <th class="text-right">Net</th>
                    <th class="text-right">Entries</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @totals}>
                    <td class="font-mono">{row.reason}</td>
                    <td class="text-right tabular-nums">{num(row.granted)}</td>
                    <td class="text-right tabular-nums">{num(row.spent)}</td>
                    <td class="text-right font-semibold tabular-nums">{num(row.net)}</td>
                    <td class="text-right tabular-nums">{num(row.entries)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.panel>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
