defmodule GamendWeb.AdminLive.AnalyticsCounters do
  @moduledoc """
  Analytics → Counters: the daily counters (`Gamend.Analytics.count/3`, and
  the ones `track/3` writes for every event and each of its dimensions),
  grouped the way the catalogue groups them. Each family is its key, a
  sparkline of its days, today, the window's total and the values of each
  dimension, largest first. Visitors are here: a counter counts everyone,
  where a row is an account's. `days` (7 / 30 / 90) and `group` are in the
  URL.
  """
  use GamendWeb, :live_view

  import GamendWeb.AdminLive.AnalyticsComponents
  import GamendWeb.Charts

  alias Gamend.Analytics
  alias Gamend.Analytics.Catalog

  @windows [7, 30, 90]
  @values_shown 12

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Admin · Analytics · Counters")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:days, int_param(params, "days", @windows, 7))
     |> assign(:group, params["group"] |> to_string() |> String.trim())
     |> load()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    _ = Analytics.flush()
    today = Date.utc_today()
    days = socket.assigns.days
    families = Analytics.families("*", days, today)
    by_key = Map.new(families, &{&1.key, &1})
    window = Enum.map((days - 1)..0//-1, &Date.add(today, -&1))

    all =
      families
      |> Enum.map(& &1.key)
      |> Catalog.grouped(kind: :counter)
      |> Enum.map(fn {group, entries} ->
        rows =
          entries
          |> Enum.map(&{&1, Map.get(by_key, &1.name)})
          |> Enum.sort_by(fn {entry, fam} -> {-((fam && fam.total) || 0), entry.name} end)

        {group, rows}
      end)

    shown =
      if socket.assigns.group == "",
        do: all,
        else: Enum.filter(all, fn {group, _} -> group.id == socket.assigns.group end)

    socket
    |> assign(:today, today)
    |> assign(:window, window)
    |> assign(:all_groups, Enum.map(all, &elem(&1, 0)))
    |> assign(:groups, shown)
  end

  defp here(assigns, changes) do
    link_to(
      "/admin/analytics/counters",
      Map.merge(%{"days" => assigns.days, "group" => assigns.group}, changes),
      %{"days" => "7"}
    )
  end

  defp explore(name, days),
    do: link_to("/admin/analytics/explore", %{"event" => name, "days" => days}, %{"days" => "30"})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <.analytics_header
          tab="counters"
          note="Daily counters: everyone, visitors and crawlers included, kept forever. Every event is counted here too, once more per value of each of its dimensions."
        >
          <:controls>
            <.switch
              label="Window"
              options={for d <- [7, 30, 90], do: {d, "#{d} days"}}
              selected={@days}
              to={&here(assigns, %{"days" => &1})}
            />
            <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
          </:controls>
        </.analytics_header>

        <nav class="flex flex-wrap gap-2" aria-label="Groups">
          <.link
            patch={here(assigns, %{"group" => ""})}
            class={["btn btn-sm", if(@group == "", do: "btn-active", else: "btn-ghost")]}
          >
            Every group
          </.link>
          <.link
            :for={g <- @all_groups}
            patch={here(assigns, %{"group" => g.id})}
            class={["btn btn-sm", if(@group == g.id, do: "btn-active", else: "btn-ghost")]}
          >
            {g.label}
          </.link>
        </nav>

        <.empty_state :if={@groups == []} title="No counters yet." />

        <.panel :for={{group, rows} <- @groups} tag="section" id={"counters-#{group.id}"}>
          <div class="mb-2 flex flex-wrap items-baseline justify-between gap-2">
            <.eyebrow tag="h2">{group.label}</.eyebrow>
            <p :if={group.description} class="text-xs text-muted">{group.description}</p>
          </div>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Counter</th>
                  <th>Per day</th>
                  <th class="text-right">Today</th>
                  <th class="text-right">{@days} days</th>
                  <th>By dimension</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{entry, fam} <- rows} class="align-top">
                  <td>
                    <div>{entry.label}</div>
                    <div :if={entry.label != entry.name} class="font-mono text-xs text-muted">
                      {entry.name}
                    </div>
                    <.link
                      :if={entry.kind == :event}
                      navigate={explore(entry.name, @days)}
                      class="link link-hover text-xs"
                    >
                      Explore
                    </.link>
                  </td>
                  <td>
                    <.spark points={
                      for d <- @window, do: {d, (fam && Map.get(fam.by_day, d, 0)) || 0}
                    } />
                  </td>
                  <td class="text-right tabular-nums">
                    {num((fam && Map.get(fam.by_day, @today, 0)) || 0)}
                  </td>
                  <td class="text-right font-semibold tabular-nums">
                    {num((fam && fam.total) || 0)}
                  </td>
                  <td>
                    <div :for={{dim, values} <- dims(fam, entry)} class="text-xs">
                      <span class="font-mono text-muted">{dim}:</span>
                      <span :for={{value, n} <- top(values)} class="me-2">
                        <span class="font-mono">{value}</span> {num(n)}
                      </span>
                      <span :if={more(values) > 0} class="text-muted">
                        +{more(values)} more
                      </span>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  defp top(values), do: Enum.take(values, @values_shown)
  defp more(values), do: max(length(values) - @values_shown, 0)

  # A family's dimensions in the catalogue's order (its labels), then any
  # other it was written with.
  defp dims(nil, _entry), do: []

  defp dims(fam, entry) do
    declared = Enum.map(entry.dims, &elem(&1, 0))
    rest = fam.dims |> Map.keys() |> Enum.reject(&(&1 in declared)) |> Enum.sort()

    for dim <- declared ++ rest, values = Map.get(fam.dims, dim), do: {dim, values}
  end
end
