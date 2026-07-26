defmodule GameServerWeb.AdminLive.LobbySnapshots do
  @moduledoc """
  Browse the durable per-run record of lobby state.

  Complements `AdminLive.Logs` rather than replacing it: logs are a live tail of
  an in-memory ring buffer, this is history you can still read tomorrow.

  Diffs are computed only for the snapshot the reader expanded. Reconstructing
  state walks every snapshot up to that point, so diffing the whole timeline
  eagerly would be quadratic in a run's length for a view where one row is
  usually the interesting one.
  """
  use GameServerWeb, :live_view

  alias GameServer.LobbySnapshots

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div class="flex items-center gap-3">
            <.link navigate={~p"/admin"} class="btn btn-outline btn-sm">&larr; Admin</.link>
            <h1 class="text-xl font-bold">Lobby snapshots</h1>
          </div>

          <div class="flex items-center gap-2 text-xs text-base-content/60">
            <span :if={not @enabled} class="badge badge-warning badge-sm">capture disabled</span>
            <span>Buffered: {@writer.buffered}</span>
            <span :if={@writer.dropped > 0} class="text-error font-semibold">
              &middot; {@writer.dropped} dropped
            </span>
            <span :if={@writer.nodes > 1}>&middot; {@writer.nodes} nodes</span>
            <span :if={@writer.unreachable > 0} class="text-warning">
              &middot; {@writer.unreachable} unreachable
            </span>
          </div>
        </div>

        <%!-- Coverage gaps: mutations that bypassed a capture chokepoint, so the
              snapshots around them are known to be incomplete. --%>
        <div :if={@gaps != []} class="alert alert-warning items-start text-sm">
          <div class="space-y-2 w-full">
            <div class="font-semibold">
              {length(@gaps)} coverage gap{if length(@gaps) == 1, do: "", else: "s"}
            </div>
            <div class="text-xs opacity-80">
              State was written outside a capture chokepoint, so snapshots around these
              are missing a mutation.
            </div>
            <div :for={gap <- Enum.take(@gaps, 5)} class="flex items-baseline gap-2 text-xs">
              <span class="font-mono">{gap.kind}</span>
              <.link
                patch={~p"/admin/lobby_snapshots?lobby_id=#{gap.lobby_id}"}
                class="link font-mono truncate"
              >
                {gap.lobby_id}
              </.link>
              <span class="opacity-60"><.timestamp at={gap.inserted_at} format="full" empty="—" /></span>
            </div>
          </div>
        </div>

        <div :if={not @enabled} class="alert alert-warning text-sm">
          <span>
            Capture is off. Set <code class="font-mono">LOBBY_SNAPSHOTS_ENABLED=true</code>
            to record runs. Existing records stay readable either way.
          </span>
        </div>

        <%!-- Lobby list --%>
        <div :if={is_nil(@lobby_id)} class="space-y-3">
          <div class="flex items-center gap-2">
            <button
              phx-click="toggle_flagged"
              class={[
                "badge badge-sm cursor-pointer",
                (@flagged_only && "badge-error") || "badge-ghost"
              ]}
            >
              flagged only
            </button>
            <span class="text-xs text-base-content/60">{length(@lobbies)} runs</span>
          </div>

          <div :if={@lobbies == []} class="text-sm text-base-content/60 py-8 text-center">
            No runs recorded yet.
          </div>

          <div class="overflow-x-auto">
            <table :if={@lobbies != []} class="table table-sm">
              <thead>
                <tr>
                  <th>Lobby</th>
                  <th>Snapshots</th>
                  <th>Started</th>
                  <th>Ended</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={run <- @lobbies} class="hover">
                  <td class="font-mono text-xs">
                    {run.lobby_id}
                    <span :if={run.flagged} class="badge badge-error badge-xs ml-1">flagged</span>
                  </td>
                  <td>{run.snapshots}</td>
                  <td class="text-xs">
                    <.timestamp at={run.started_at} format="full" empty="—" />
                  </td>
                  <td class="text-xs"><.timestamp at={run.ended_at} format="full" empty="—" /></td>
                  <td>
                    <.link
                      patch={~p"/admin/lobby_snapshots?lobby_id=#{run.lobby_id}"}
                      class="link link-primary text-xs"
                    >
                      Timeline →
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Timeline for one lobby --%>
        <div :if={@lobby_id} class="space-y-3">
          <div class="flex flex-col sm:flex-row sm:items-center gap-3">
            <.link patch={~p"/admin/lobby_snapshots"} class="btn btn-ghost btn-xs">
              &larr; All runs
            </.link>
            <span class="font-mono text-sm truncate">{@lobby_id}</span>

            <%!-- Filters everything on the page at once: diff paths and values,
                  event kinds and payloads. A real run puts hundreds of rows on
                  screen, so finding one field by eye is the slow path. --%>
            <form id="run-filter" phx-change="filter" class="sm:ml-auto">
              <input
                type="search"
                name="q"
                value={@filter}
                phx-debounce="150"
                placeholder="Filter run — e.g. distance, speed_mode, hp"
                class="input input-bordered input-sm w-full sm:w-80"
              />
            </form>
          </div>

          <div :if={@filter != ""} class="text-xs text-base-content/60">
            Showing rows and events matching <span class="font-mono">{@filter}</span>. Snapshots
            with no match are still listed so the timeline keeps its shape.
          </div>

          <.event_list
            events={filter_events(@timeline.prologue, @filter)}
            total={length(@timeline.prologue)}
            label="before first snapshot"
            id="prologue"
            expanded={"prologue" in @expanded_events}
          />

          <div :for={interval <- @timeline.intervals} class="space-y-1">
            <div class="card bg-base-100 p-3">
              <button
                phx-click="toggle_snapshot"
                phx-value-id={interval.snapshot.id}
                class="flex items-center justify-between w-full text-left"
              >
                <div class="flex items-center gap-2">
                  <span class="badge badge-neutral badge-sm">#{interval.index}</span>
                  <span class="font-mono text-sm">{interval.snapshot.trigger}</span>
                  <span :if={interval.snapshot.flagged} class="badge badge-error badge-xs">
                    flagged
                  </span>
                </div>
                <span class="text-xs text-base-content/50">
                  <.timestamp at={interval.snapshot.inserted_at} format="full" empty="—" />
                </span>
              </button>

              <div :if={@expanded == interval.snapshot.id} class="mt-3 space-y-3">
                <div :if={@diff == %{} and interval.index == 1} class="text-xs text-base-content/60">
                  First snapshot of the run — nothing to compare against. Full state below.
                </div>
                <div :if={@diff == %{} and interval.index > 1} class="text-xs text-base-content/60">
                  No changes from the previous snapshot.
                </div>

                <div :for={{section, changes} <- @diff} class="space-y-1">
                  <div class="flex items-center justify-between gap-2">
                    <div class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                      {section}
                      <span class="opacity-50 normal-case font-normal">
                        {shown_count(changes, @filter, @section_filters[section])}
                      </span>
                    </div>

                    <%!-- Per-section filter, on top of the run-wide one. A
                          kv_lobby diff alone can run to dozens of rows. --%>
                    <form
                      id={"section-filter-#{interval.snapshot.id}-#{section}"}
                      phx-change="filter_section"
                    >
                      <input type="hidden" name="section" value={section} />
                      <input
                        type="search"
                        name="q"
                        value={@section_filters[section] || ""}
                        phx-debounce="150"
                        placeholder={"filter #{section}"}
                        class="input input-bordered input-xs w-40 sm:w-56"
                      />
                    </form>
                  </div>

                  <div class="overflow-x-auto">
                    <table class="table table-xs">
                      <tbody>
                        <tr :for={
                          change <- visible_changes(changes, @filter, @section_filters[section])
                        }>
                          <td class="font-mono text-xs whitespace-nowrap">
                            {Enum.join(change.path, ".")}
                          </td>
                          <td class="font-mono text-xs text-error break-all">
                            {preview(change.from)}
                          </td>
                          <td class="font-mono text-xs text-success break-all">
                            {preview(change.to)}
                          </td>
                        </tr>
                      </tbody>
                    </table>
                    <div
                      :if={visible_changes(changes, @filter, @section_filters[section]) == []}
                      class="text-xs text-base-content/50 py-2"
                    >
                      No rows match.
                    </div>
                  </div>
                </div>

                <details class="text-xs">
                  <summary class="cursor-pointer text-base-content/60">Raw sections</summary>
                  <pre class="mt-2 p-2 bg-base-200 rounded overflow-x-auto text-xs">{@raw}</pre>
                </details>
              </div>
            </div>

            <.event_list
              events={filter_events(interval.events, @filter)}
              total={length(interval.events)}
              label={nil}
              id={interval.snapshot.id}
              expanded={interval.snapshot.id in @expanded_events}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @events_collapsed 8

  attr :events, :list, required: true
  attr :total, :integer, required: true
  attr :label, :any, default: nil
  attr :id, :string, required: true
  attr :expanded, :boolean, default: false

  # A real run puts ~50 events in a single interval. Showing them all inline
  # recreated exactly the wall of undifferentiated log lines this view exists to
  # replace, so long lists collapse to a head and open on demand.
  defp event_list(assigns) do
    assigns =
      assign(assigns,
        shown:
          if(assigns.expanded,
            do: assigns.events,
            else: Enum.take(assigns.events, @events_collapsed)
          ),
        hidden: max(length(assigns.events) - @events_collapsed, 0),
        # Precomputed rather than referenced in the template: inside HEEx, `@name`
        # resolves against assigns, never a module attribute.
        collapsible?: length(assigns.events) > @events_collapsed
      )

    ~H"""
    <div :if={@events != []} class="pl-4 border-l-2 border-base-300 space-y-1">
      <div :if={@label} class="text-xs text-base-content/50">
        {@label}
        <span :if={@total != length(@events)} class="opacity-70">
          — {length(@events)} of {@total} match
        </span>
      </div>

      <.event :for={event <- @shown} event={event} />

      <button
        :if={@hidden > 0 and not @expanded}
        phx-click="toggle_events"
        phx-value-id={@id}
        class="link link-primary text-xs"
      >
        Show {@hidden} more event{if @hidden == 1, do: "", else: "s"}
      </button>
      <button
        :if={@expanded and @collapsible?}
        phx-click="toggle_events"
        phx-value-id={@id}
        class="link text-xs opacity-60"
      >
        Collapse
      </button>
    </div>
    """
  end

  attr :event, :map, required: true

  defp event(assigns) do
    assigns =
      assign(assigns,
        gap?: LobbySnapshots.coverage_gap?(assigns.event),
        fields: payload_fields(assigns.event.payload)
      )

    ~H"""
    <div class="flex items-baseline gap-2 text-xs flex-wrap">
      <span class={["font-mono", (@gap? && "text-warning font-semibold") || "text-primary"]}>
        {@event.kind}
      </span>
      <%!-- Rendered as discrete key/value chips rather than one inspect/1 blob:
            the blob was truncated mid-token ("serialized" => tru), which is both
            unreadable and unsearchable. --%>
      <span :for={{key, value} <- @fields} class="font-mono text-base-content/60">
        <span class="opacity-70">{key}=</span>{value}
      </span>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin · Lobby snapshots")
     |> assign(:flagged_only, false)
     |> assign(:filter, "")
     |> assign(:section_filters, %{})
     |> assign(:expanded_events, MapSet.new())
     |> assign(:enabled, LobbySnapshots.enabled?())
     |> assign(:gaps, LobbySnapshots.list_coverage_gaps(limit: 25))
     # Cluster-wide: each node buffers independently, so a local read would
     # under-report exactly the dropped rows this is here to expose.
     |> assign(:writer, LobbySnapshots.Writer.cluster_stats())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    lobby_id = params["lobby_id"]

    socket =
      socket
      |> assign(:lobby_id, lobby_id)
      |> assign(:expanded, nil)
      |> assign(:diff, %{})
      |> assign(:raw, "")

    {:noreply, if(lobby_id, do: load_timeline(socket), else: load_lobbies(socket))}
  end

  @impl true
  def handle_event("toggle_flagged", _params, socket) do
    {:noreply,
     socket
     |> assign(:flagged_only, not socket.assigns.flagged_only)
     |> load_lobbies()}
  end

  def handle_event("filter", %{"q" => query}, socket) do
    {:noreply, assign(socket, :filter, String.trim(query))}
  end

  def handle_event("filter_section", %{"section" => section, "q" => query}, socket) do
    filters = Map.put(socket.assigns.section_filters, section, String.trim(query))
    {:noreply, assign(socket, :section_filters, filters)}
  end

  def handle_event("toggle_events", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded_events

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, :expanded_events, expanded)}
  end

  # Collapsing only needs to drop the assigns; expanding is what costs a read.
  def handle_event("toggle_snapshot", %{"id" => id}, socket)
      when id == socket.assigns.expanded do
    {:noreply, assign(socket, expanded: nil, diff: %{}, raw: "")}
  end

  def handle_event("toggle_snapshot", %{"id" => id}, socket) do
    snapshots = Enum.map(socket.assigns.timeline.intervals, & &1.snapshot)

    case Enum.find_index(snapshots, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      index ->
        snapshot = Enum.at(snapshots, index)
        state = LobbySnapshots.state_at(snapshot)

        # The first snapshot has nothing to diff against; the raw view below is
        # the whole answer for it.
        diff =
          if index == 0,
            do: %{},
            else: LobbySnapshots.diff(Enum.at(snapshots, index - 1), snapshot)

        {:noreply,
         assign(socket, expanded: id, diff: diff, raw: Jason.encode!(state, pretty: true))}
    end
  end

  defp load_lobbies(socket) do
    assign(
      socket,
      :lobbies,
      LobbySnapshots.list_lobbies(flagged_only: socket.assigns.flagged_only)
    )
  end

  defp load_timeline(socket) do
    assign(socket, :timeline, LobbySnapshots.timeline(socket.assigns.lobby_id))
  end

  ## Filtering

  # Matching covers the path *and* both values, so "8423" finds a row by what it
  # changed to, not only by field name.
  defp visible_changes(changes, run_filter, section_filter) do
    changes
    |> apply_filter(run_filter, &change_haystack/1)
    |> apply_filter(section_filter, &change_haystack/1)
  end

  defp filter_events(events, filter) do
    apply_filter(events, filter, &event_haystack/1)
  end

  defp apply_filter(items, filter, _haystack) when filter in [nil, ""], do: items

  defp apply_filter(items, filter, haystack) do
    needle = String.downcase(filter)
    Enum.filter(items, &String.contains?(String.downcase(haystack.(&1)), needle))
  end

  defp change_haystack(change) do
    "#{Enum.join(change.path, ".")} #{inspect(change.from)} #{inspect(change.to)}"
  end

  defp event_haystack(event), do: "#{event.kind} #{inspect(event.payload)}"

  defp shown_count(changes, run_filter, section_filter) do
    shown = length(visible_changes(changes, run_filter, section_filter))
    total = length(changes)

    if shown == total, do: "(#{total})", else: "(#{shown} of #{total})"
  end

  ## Rendering

  # Split into fields so long payloads wrap and stay searchable, instead of one
  # inspect/1 string cut mid-token.
  defp payload_fields(payload) when is_map(payload) do
    payload
    |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> {to_string(key), preview(value)} end)
  end

  defp payload_fields(payload), do: [{"payload", preview(payload)}]

  # Shown in full rather than truncated: ids are UUIDv7, so the leading hex is a
  # millisecond timestamp and every lobby from the same ~65s window shares it.
  # The full id is also what correlates a run with the client's own records.

  # Strings render bare so a value reads as `boost` not `"boost"`, and floats keep
  # full precision — 8423.199939727783 vs 8423.2 is exactly the kind of drift
  # worth seeing.
  defp preview(value) when is_binary(value), do: String.slice(value, 0, 120)

  defp preview(value) when is_number(value) or is_boolean(value) or is_nil(value),
    do: inspect(value)

  defp preview(value) do
    value |> inspect(limit: 6, printable_limit: 80) |> String.slice(0, 120)
  end
end
