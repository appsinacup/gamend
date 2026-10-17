defmodule GamendWeb.AdminLive.AnalyticsFeatures do
  @moduledoc """
  Analytics → Features: every event as a feature, grouped the way the
  catalogue (`Gamend.Analytics.Catalog`) groups them, with the accounts that
  used it today / in 7 / in 30 days, stickiness, how many were new to it
  and, of those, the share back at it 1 / 7 / 30 days later. A declared
  event nobody has used yet shows with dashes, so what is tracked is in
  view. A row opens it in Explore.
  """
  use GamendWeb, :live_view

  import GamendWeb.AdminLive.AnalyticsComponents

  alias Gamend.Analytics
  alias Gamend.Analytics.Catalog
  alias Gamend.Analytics.Segment

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Admin · Analytics · Features")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign(:segment, Segment.parse(params["segment"])) |> load()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    _ = Analytics.flush()
    summary = Analytics.feature_summary(Date.utc_today(), segment: socket.assigns.segment)
    by_name = Map.new(summary, &{&1.name, &1})

    groups =
      by_name
      |> Map.keys()
      |> Catalog.grouped(kind: :event)
      |> Enum.map(fn {group, events} ->
        {group, Enum.map(events, &{&1, Map.get(by_name, &1.name)})}
      end)

    assign(socket, :groups, groups)
  end

  defp here(segment),
    do: link_to("/admin/analytics/features", %{"segment" => segment}, %{"segment" => "all"})

  defp explore(name, segment),
    do:
      link_to("/admin/analytics/explore", %{"event" => name, "segment" => segment}, %{
        "segment" => "all"
      })

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <.analytics_header
          tab="features"
          note="Distinct accounts with the event that day / in 7 / in 30 days. New = their first time in the last 60 days; D1 / D7 / D30 = of those, the share back at it exactly that many days later. Only an account's events are rows; a visitor's are in Counters."
        >
          <:controls>
            <.switch
              label="Segment"
              options={for s <- Segment.all(), do: {s, Segment.label(s)}}
              selected={@segment}
              to={&here(Atom.to_string(&1))}
            />
            <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
          </:controls>
        </.analytics_header>

        <.empty_state :if={@groups == []} title="No events yet." />

        <.panel :if={@groups != []}>
          <div class="overflow-x-auto">
            <table class="table table-sm" id="features">
              <thead>
                <tr>
                  <th>Feature</th>
                  <th class="text-right">DAU</th>
                  <th class="text-right">WAU</th>
                  <th class="text-right">MAU</th>
                  <th class="text-right">Stick.</th>
                  <th class="text-right">New 7d</th>
                  <th class="text-right">New 30d</th>
                  <th class="text-right">D1</th>
                  <th class="text-right">D7</th>
                  <th class="text-right">D30</th>
                  <th class="text-right">Events 7d</th>
                </tr>
              </thead>
              <tbody :for={{group, rows} <- @groups} id={"group-#{group.id}"}>
                <tr>
                  <th colspan="11" class="pt-5">
                    <.eyebrow tag="h2">{group.label}</.eyebrow>
                    <p :if={group.description} class="text-xs font-normal text-muted">
                      {group.description}
                    </p>
                  </th>
                </tr>
                <tr :for={{event, f} <- rows} class="hover:bg-base-200">
                  <td>
                    <.link
                      navigate={explore(event.name, Atom.to_string(@segment))}
                      class="link link-hover"
                    >
                      {event.label}
                    </.link>
                    <div :if={event.label != event.name} class="font-mono text-xs text-muted">
                      {event.name}
                    </div>
                  </td>
                  <td class="text-right tabular-nums">{num(f && f.dau)}</td>
                  <td class="text-right tabular-nums">{num(f && f.wau)}</td>
                  <td class="text-right tabular-nums">{num(f && f.mau)}</td>
                  <td class="text-right tabular-nums">{pct(f && f.stickiness)}</td>
                  <td class="text-right tabular-nums">{num(f && f.new_7d)}</td>
                  <td class="text-right tabular-nums">{num(f && f.new_30d)}</td>
                  <td class="text-right tabular-nums">{pct(f && f.d1)}</td>
                  <td class="text-right tabular-nums">{pct(f && f.d7)}</td>
                  <td class="text-right tabular-nums">{pct(f && f.d30)}</td>
                  <td class="text-right tabular-nums">{num(f && f.events_7d)}</td>
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
