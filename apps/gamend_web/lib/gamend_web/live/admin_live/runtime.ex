defmodule GamendWeb.AdminLive.Runtime do
  @moduledoc """
  Read-only introspection of the running server: hooks, env vars, protobuf
  messages, channels and realtime events, the data model (with an ER diagram),
  plugins and their RPCs, scheduled jobs, advisory lock namespaces, and
  migration status.

  Unlike `/admin/config`, nothing here can be changed — every tab reflects
  what the code and the runtime actually loaded, so it cannot drift the way a
  hand-written page can. All tabs share one search + pagination pipeline over
  rows produced by `GamendWeb.RuntimeIntrospection`.
  """
  use GamendWeb, :live_view

  alias GamendWeb.LiveHelpers
  alias GamendWeb.RuntimeIntrospection, as: Introspection

  # {key, label, provider, facet} — facet is the row field a per-tab dropdown
  # filters on, with its options derived from the rows themselves so plugin
  # names appear without being hardcoded.
  @tabs [
    {"hooks", "Hooks", &Introspection.hooks/0, {:implemented, "All hooks"}},
    {"env", "Env vars", &Introspection.env_vars/0, {:state, "All variables"}},
    {"proto", "Protobuf", &Introspection.protobuf_messages/0, {:source, "All sources"}},
    {"channels", "Channels", &Introspection.channels/0, nil},
    {"events", "Events", &Introspection.events/0, {:source, "All sources"}},
    {"notifications", "Notifications", &Introspection.notification_types/0,
     {:source, "All sources"}},
    {"model", "Data model", &Introspection.data_model/0, {:source, "All sources"}},
    {"plugins", "Plugins", &Introspection.plugins/0, nil},
    {"rpcs", "RPCs", &Introspection.dynamic_rpcs/0, {:plugin, "All plugins"}},
    {"jobs", "Jobs", &Introspection.scheduled_jobs/0, nil},
    {"locks", "Locks", &Introspection.advisory_locks/0, nil},
    {"migrations", "Migrations", &Introspection.migrations/0, {:status, "All statuses"}}
  ]

  @tab_keys Enum.map(@tabs, &elem(&1, 0))

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin · Runtime")
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:page_size, 25)
     |> assign(:expanded, MapSet.new())
     |> assign(:show_diagram, false)
     |> assign(:diagram, nil)
     |> assign(:facet, "all")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tab_keys, do: params["tab"], else: "hooks"

    {:noreply,
     socket
     |> assign(:tab, tab)
     |> assign(:search, "")
     |> assign(:facet, "all")
     |> assign(:page, 1)
     |> assign(:expanded, MapSet.new())
     |> load_rows()
     |> paginate()}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:search, q) |> assign(:page, 1) |> paginate()}
  end

  def handle_event("facet", %{"value" => value}, socket) do
    {:noreply, socket |> assign(:facet, value) |> assign(:page, 1) |> paginate()}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> paginate()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> paginate()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> paginate()}

  def handle_event("toggle_row", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("toggle_diagram", _params, socket) do
    socket = assign(socket, :show_diagram, not socket.assigns.show_diagram)

    # Built once, on first reveal: the schema cannot change while the page is
    # open, so there is nothing to invalidate.
    if socket.assigns.show_diagram and socket.assigns.diagram == nil do
      {:noreply, assign(socket, :diagram, Introspection.mermaid_domain_flowchart())}
    else
      {:noreply, socket}
    end
  end

  # ── data ──────────────────────────────────────────────────────────────────

  defp load_rows(socket) do
    {_key, _label, provider, _facet} = current_tab(socket.assigns)
    assign(socket, :all_rows, provider.())
  end

  # These take assigns rather than the socket so the template can call them too.
  defp current_tab(assigns), do: List.keyfind(@tabs, assigns.tab, 0)

  defp facet_field(assigns) do
    case current_tab(assigns) do
      {_key, _label, _provider, {field, _all_label}} -> field
      _ -> nil
    end
  end

  # Options come from the rows in view, so a newly loaded plugin shows up
  # without touching this module.
  defp facet_options(assigns) do
    case facet_field(assigns) do
      nil ->
        []

      field ->
        assigns.all_rows |> Enum.map(&Map.get(&1, field)) |> Enum.uniq() |> Enum.sort()
    end
  end

  defp facet_label(assigns) do
    case current_tab(assigns) do
      {_key, _label, _provider, {_field, all_label}} -> all_label
      _ -> nil
    end
  end

  defp paginate(socket) do
    %{all_rows: all, search: search, page: page} = socket.assigns
    # Hooks render grouped by category, so they show all at once — a section
    # split across pages would defeat the grouping.
    page_size = if socket.assigns.tab == "hooks", do: 1000, else: socket.assigns.page_size

    filtered =
      all
      |> filter_by_facet(facet_field(socket.assigns), socket.assigns.facet)
      |> filter_by_search(search)

    total = length(filtered)
    total_pages = max(LiveHelpers.total_pages(total, page_size), 1)
    page = min(page, total_pages)

    socket
    |> assign(:rows, Enum.slice(filtered, (page - 1) * page_size, page_size))
    |> assign(:count, total)
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
  end

  defp filter_by_facet(rows, nil, _value), do: rows
  defp filter_by_facet(rows, _field, "all"), do: rows

  defp filter_by_facet(rows, field, value),
    do: Enum.filter(rows, &(to_string(Map.get(&1, field)) == value))

  defp filter_by_search(rows, search) do
    case String.trim(String.downcase(search)) do
      "" -> rows
      q -> Enum.filter(rows, &String.contains?(&1.search, q))
    end
  end

  defp tabs, do: @tabs

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-surface mb-4">← Back to Admin</.link>

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">Runtime introspection</h2>
            <span class="text-xs text-muted">
              Read-only; reflects the running node
            </span>
          </div>

          <div role="tablist" class="tabs tabs-box tabs-sm my-2 flex-wrap">
            <.link
              :for={{key, label, _provider, _facet} <- tabs()}
              patch={~p"/admin/runtime?tab=#{key}"}
              role="tab"
              class={["tab", @tab == key && "tab-active"]}
            >
              {label}
            </.link>
          </div>

          <div class="flex flex-wrap items-center gap-2 mb-2">
            <form
              phx-change="search"
              phx-no-unused-field
              id={"runtime-search-#{@tab}"}
              class="grow max-w-md"
            >
              <input
                type="text"
                name="q"
                value={@search}
                placeholder={
                  ngettext("Search %{count} entry...", "Search %{count} entries...", @count)
                }
                phx-debounce="200"
                class="input input-sm w-full"
              />
            </form>
            <form
              :if={facet_field(assigns) != nil}
              phx-change="facet"
              phx-no-unused-field
              id={"facet-#{@tab}"}
            >
              <select name="value" class="select select-sm w-48">
                <option value="all" selected={@facet == "all"}>{facet_label(assigns)}</option>
                <option
                  :for={option <- facet_options(assigns)}
                  value={option}
                  selected={@facet == to_string(option)}
                >
                  {option}
                </option>
              </select>
            </form>
            <button
              :if={@tab == "model"}
              phx-click="toggle_diagram"
              class="btn btn-surface btn-sm"
            >
              {if @show_diagram, do: "Hide ER diagram", else: "Show ER diagram"}
            </button>
          </div>

          <div
            :if={@tab == "model" && @show_diagram}
            class="bg-base-100 rounded-lg p-4 mb-4 overflow-hidden"
          >
            <div
              id="er-diagram"
              phx-hook="MermaidDiagram"
              phx-update="ignore"
              data-diagram={@diagram}
              class="max-h-[40rem] overflow-hidden text-xs cursor-grab select-none"
            >
              Rendering…
            </div>
            <p class="text-xs text-muted mt-1">
              Boxes are domains · thick edges cross a domain boundary · scroll to zoom · drag to pan
            </p>
            <details class="mt-2">
              <summary class="cursor-pointer text-xs text-muted">
                Mermaid source (copyable)
              </summary>
              <pre class="text-xs overflow-x-auto mt-2"><code>{@diagram}</code></pre>
            </details>
          </div>

          <div class="overflow-x-auto">
            <.tab_table tab={@tab} rows={@rows} expanded={@expanded} />
          </div>

          <div :if={@rows == []} class="text-center py-8 text-muted">
            Nothing matches.
          </div>

          <%!-- Not on Hooks: that tab renders every row at once, grouped by
                category, so a page size there changed nothing. --%>
          <div :if={@tab != "hooks"} class="mt-4 flex justify-center">
            <.pagination
              page={@page}
              total_pages={@total_pages}
              total_count={@count}
              page_size={@page_size}
              on_prev="prev_page"
              on_next="next_page"
              on_page_size="page_size"
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :tab, :string, required: true
  attr :rows, :list, required: true
  attr :expanded, :any, required: true

  defp tab_table(%{tab: "hooks"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Hook</th>
          <th>Kind</th>
          <th>Category</th>
          <th>Implemented by</th>
          <th>Signature</th>
        </tr>
      </thead>
      <tbody>
        <%= for row <- ordered_hooks(@rows) do %>
          <tr
            class={[
              "cursor-pointer hover:bg-base-300/40",
              row.implementers == [] && "opacity-50"
            ]}
            phx-click="toggle_row"
            phx-value-id={row.id}
          >
            <td class="font-mono text-xs whitespace-nowrap">{row.name}/{row.arity}</td>
            <td>
              <span class={["badge badge-sm", row.kind == "pipeline" && "badge-info"]}>
                {row.kind}
              </span>
            </td>
            <td class="text-xs whitespace-nowrap">{row.section}</td>
            <td class="text-xs">
              {if row.implementers == [], do: "—", else: Enum.join(row.implementers, ", ")}
            </td>
            <td class="font-mono text-xs text-muted max-w-md truncate">
              {row.signature}
            </td>
          </tr>
          <tr :if={MapSet.member?(@expanded, row.id)}>
            <td colspan="5" class="bg-base-100">
              <div class="p-2 space-y-2">
                <pre class="text-xs whitespace-pre-wrap font-mono">{row.signature}</pre>
                <pre :if={row.doc != ""} class="text-xs whitespace-pre-wrap">{row.doc}</pre>
              </div>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "env"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Variable</th>
          <th>State</th>
          <th>Type</th>
          <th>Value</th>
          <th>Default</th>
          <th>Description</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows} class={!row.set && "opacity-50"}>
          <td class="font-mono text-xs whitespace-nowrap">{row.name}</td>
          <td>
            <span class={["badge badge-sm", (row.set && "badge-success") || "badge-ghost"]}>
              {if row.set, do: "set", else: "unset"}
            </span>
          </td>
          <td class="font-mono text-xs text-muted">{row.type}</td>
          <td class="font-mono text-xs">{row.value || "—"}</td>
          <td class="font-mono text-xs">{row.default}</td>
          <td class="text-xs text-muted">{row.description}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "proto"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Message</th>
          <th>Source</th>
          <th>Syntax</th>
          <th class="text-right">Fields</th>
        </tr>
      </thead>
      <tbody>
        <%= for row <- @rows do %>
          <tr
            class="cursor-pointer hover:bg-base-300/40"
            phx-click="toggle_row"
            phx-value-id={row.id}
          >
            <td class="font-mono text-xs">{row.full_name}</td>
            <td>
              <span class={["badge badge-sm", row.source == "plugin" && "badge-warning"]}>
                {row.source}
              </span>
            </td>
            <td class="text-xs">{row.syntax}</td>
            <td class="text-right font-mono text-xs">{row.field_count}</td>
          </tr>
          <tr :if={MapSet.member?(@expanded, row.id)}>
            <td colspan="4" class="bg-base-100">
              <table class="table table-xs">
                <thead>
                  <tr>
                    <th class="text-right">#</th>
                    <th>Field</th>
                    <th>Type</th>
                    <th>Flags</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={f <- row.fields}>
                    <td class="text-right font-mono">{f.tag}</td>
                    <td class="font-mono">{f.name}</td>
                    <td class="font-mono">{f.type}</td>
                    <td class="text-xs">
                      {[f.repeated && "repeated", f.oneof && "oneof"]
                      |> Enum.filter(& &1)
                      |> Enum.join(", ")}
                    </td>
                  </tr>
                </tbody>
              </table>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "channels"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Topic pattern</th>
          <th>Module</th>
          <th>Purpose</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td class="font-mono text-xs">{row.pattern}</td>
          <td class="font-mono text-xs">{row.module}</td>
          <td class="text-xs text-muted">{row.description}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "events"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Topic</th>
          <th>Event</th>
          <th>Source</th>
          <th>Format</th>
          <th>Payload</th>
          <th>When</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td class="font-mono text-xs">{row.topic}</td>
          <td class="font-mono text-xs">{row.event}</td>
          <td>
            <span class={["badge badge-sm", row.source != "server" && "badge-warning"]}>
              {row.source}
            </span>
          </td>
          <td>
            <span class={["badge badge-sm", (row.pb && "badge-primary") || "badge-ghost"]}>
              {if row.pb, do: "pb+json", else: "json"}
            </span>
          </td>
          <td class="text-xs">{row.payload}</td>
          <td class="text-xs text-muted">{row.description}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "notifications"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Code</th>
          <th>Source</th>
          <th>Meaning</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td class="font-mono text-xs">{row.code}</td>
          <td>
            <span class={["badge badge-sm", row.source != "server" && "badge-warning"]}>
              {row.source}
            </span>
          </td>
          <td class="text-xs text-muted">{row.description}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "model"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Table</th>
          <th>Source</th>
          <th>Module</th>
          <th class="text-right">Fields</th>
          <th>Associations</th>
        </tr>
      </thead>
      <tbody>
        <%= for row <- @rows do %>
          <tr
            class="cursor-pointer hover:bg-base-300/40"
            phx-click="toggle_row"
            phx-value-id={row.id}
          >
            <td class="font-mono text-xs">{row.table}</td>
            <td>
              <span class={["badge badge-sm", row.source != "server" && "badge-warning"]}>
                {row.source}
              </span>
            </td>
            <td class="font-mono text-xs">{row.module}</td>
            <td class="text-right font-mono text-xs">{row.field_count}</td>
            <td class="text-xs">{Enum.map_join(row.assocs, ", ", & &1.name)}</td>
          </tr>
          <tr :if={MapSet.member?(@expanded, row.id)}>
            <td colspan="5" class="bg-base-100">
              <div class="grid gap-4 md:grid-cols-2 p-2">
                <table class="table table-xs">
                  <thead>
                    <tr>
                      <th>Field</th>
                      <th>Type</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={f <- row.fields}>
                      <td class="font-mono">{f.name}</td>
                      <td class="font-mono">{f.type}</td>
                    </tr>
                  </tbody>
                </table>
                <table class="table table-xs">
                  <thead>
                    <tr>
                      <th>Assoc</th>
                      <th>Kind</th>
                      <th>Related</th>
                      <th>Key</th>
                      <th>On delete</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={a <- row.assocs}>
                      <td class="font-mono">{a.name}</td>
                      <td>{a.kind}</td>
                      <td class="font-mono">{a.related_table || a.related}</td>
                      <td class="font-mono">{a.owner_key}</td>
                      <td>
                        <span
                          :if={a.on_delete}
                          class={[
                            "badge badge-xs",
                            a.on_delete == "cascade" && "badge-error",
                            a.on_delete == "nilify" && "badge-warning"
                          ]}
                          title="What happens to this row when the referenced row is deleted"
                        >
                          {a.on_delete}
                        </span>
                        <span :if={is_nil(a.on_delete)} class="opacity-40">—</span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "plugins"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Plugin</th>
          <th>Hooks module</th>
          <th class="text-right">RPCs</th>
          <th class="text-right">Typed hooks</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td class="font-mono text-xs">{row.name}</td>
          <td class="font-mono text-xs">{row.module}</td>
          <td class="text-right font-mono text-xs">{row.rpcs}</td>
          <td class="text-right font-mono text-xs">{row.typed_hooks}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "rpcs"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Plugin</th>
          <th>Function</th>
          <th>Signature</th>
          <th>Payload</th>
          <th>Description</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td class="font-mono text-xs">{row.plugin}</td>
          <td class="font-mono text-xs whitespace-nowrap">{row.hook}</td>
          <td class="font-mono text-xs max-w-xs truncate" title={row.signature}>{row.signature}</td>
          <td>
            <span class={[
              "badge badge-sm",
              (String.starts_with?(row.payload, "protobuf") && "badge-primary") || "badge-ghost"
            ]}>
              {row.payload}
            </span>
          </td>
          <td class="text-xs text-muted max-w-md truncate" title={row.description}>
            {row.description}
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "jobs"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Job</th>
          <th>Schedule</th>
          <th>State</th>
          <th>Timezone</th>
          <th>Task</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td class="font-mono text-xs">{row.name}</td>
          <td class="font-mono text-xs">{row.schedule}</td>
          <td>
            <span class={[
              "badge badge-sm",
              (row.state == "active" && "badge-success") || "badge-ghost"
            ]}>
              {row.state}
            </span>
          </td>
          <td class="text-xs">{row.timezone}</td>
          <td class="font-mono text-xs">{row.task}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "locks"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th class="text-right">ID</th>
          <th>Namespace</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td class="text-right font-mono text-xs">{row.namespace_id}</td>
          <td class="font-mono text-xs">{row.name}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp tab_table(%{tab: "migrations"} = assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Version</th>
          <th>Name</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td class="font-mono text-xs">{row.version}</td>
          <td class="font-mono text-xs">{row.name}</td>
          <td>
            <span class={[
              "badge badge-sm",
              (row.status == "up" && "badge-success") || "badge-warning"
            ]}>
              {row.status}
            </span>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  # Order hook rows by category (fixed order), so the Category column reads
  # grouped without needing section-divider rows.
  defp ordered_hooks(rows) do
    by_section = Enum.group_by(rows, & &1.section)

    GamendWeb.RuntimeIntrospection.hook_group_order()
    |> Enum.flat_map(fn section -> Map.get(by_section, section, []) end)
  end
end
