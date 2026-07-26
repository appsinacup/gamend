defmodule GameServerWeb.AdminLive.Logs do
  use GameServerWeb, :live_view

  alias GameServerWeb.AdminLogBuffer

  @refresh_interval 3_000
  @page_size 200

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div class="flex items-center gap-3">
            <.link navigate={~p"/admin"} class="btn btn-outline btn-sm">&larr; Admin</.link>
            <h1 class="text-xl font-bold">Logs</h1>
          </div>

          <div class="flex items-center gap-2 text-xs text-base-content/60">
            <span>Buffer: {@total_buffered} entries</span>
            <span>&middot;</span>
            <span :if={@level_counts[:error]} class="text-error font-semibold">
              {@level_counts[:error]} errors
            </span>
            <span :if={@level_counts[:warning]} class="text-warning font-semibold">
              {@level_counts[:warning]} warnings
            </span>
          </div>
        </div>

        <%!-- Level summary badges --%>
        <div class="flex flex-wrap gap-2">
          <button
            :for={
              {level, color} <- [
                {"all", "badge-neutral"},
                {"debug", "badge-ghost"},
                {"info", "badge-info"},
                {"warning", "badge-warning"},
                {"error", "badge-error"}
              ]
            }
            phx-click="filter_level"
            phx-value-level={level}
            class={[
              "badge badge-sm cursor-pointer transition-all",
              color,
              @level_filter == level && "badge-outline ring-2 ring-offset-1 ring-primary"
            ]}
          >
            {level}
            <span :if={level != "all"} class="ml-1 opacity-70">
              ({Map.get(@level_counts, String.to_existing_atom(level), 0)})
            </span>
            <span :if={level == "all"} class="ml-1 opacity-70">
              ({@total_buffered})
            </span>
          </button>
        </div>

        <%!-- Filters --%>
        <.form
          for={%{}}
          id="log-filters"
          phx-change="update_filters"
          class="flex flex-col sm:flex-row gap-2"
        >
          <input
            id="log-module-filter"
            name="module"
            value={@module_filter}
            placeholder="Filter by module (eg GameServer.Hooks)"
            class="input input-sm flex-1"
            phx-debounce="300"
          />
          <input
            id="log-search"
            name="query"
            value={@search_query}
            placeholder="Search message text (eg tournament, user_id=42)"
            class="input input-sm flex-1"
            phx-debounce="300"
          />
          <div class="flex items-center gap-2">
            <label class="label cursor-pointer gap-2">
              <input
                type="checkbox"
                name="auto_scroll"
                value="true"
                checked={@auto_scroll}
                class="checkbox checkbox-sm checkbox-primary"
              />
              <span class="text-xs">Auto-scroll</span>
            </label>
            <button type="button" phx-click="clear_filters" class="btn btn-ghost btn-sm">
              Clear
            </button>
          </div>
        </.form>

        <%!-- Log entries --%>
        <div
          id="log-container"
          class="bg-base-100 border rounded-lg font-mono text-xs overflow-auto"
          style="max-height: calc(100vh - 320px); min-height: 400px;"
          phx-hook={if @auto_scroll, do: "AutoScroll", else: nil}
        >
          <div class="p-3 space-y-0.5">
            <%= if @logs == [] do %>
              <div class="text-center text-base-content/40 py-8 italic">
                No logs match the current filters.
              </div>
            <% else %>
              <div
                :for={entry <- Enum.reverse(@logs)}
                id={"log-#{entry_id(entry)}"}
                class={[
                  "flex gap-2 py-0.5 px-1 rounded hover:bg-base-200 transition-colors",
                  entry.level == :error && "bg-error/5",
                  entry.level == :warning && "bg-warning/5"
                ]}
              >
                <span class="text-base-content/40 whitespace-nowrap shrink-0">
                  <.timestamp at={entry.timestamp} format="time" empty="" />
                </span>
                <span class={[
                  "whitespace-nowrap shrink-0 font-semibold w-14 text-right",
                  level_color(entry.level)
                ]}>
                  [{entry.level}]
                </span>
                <span
                  :if={entry.module}
                  class="text-primary/60 whitespace-nowrap shrink-0 max-w-48 truncate"
                  title={inspect(entry.module)}
                >
                  {format_module(entry.module)}
                </span>
                <span class="break-all">{entry.message}</span>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Footer stats --%>
        <div class="flex items-center justify-between text-xs text-base-content/40">
          <span>Showing {length(@logs)} of {@total_buffered} buffered entries</span>
          <span>Errors in last hour: {@recent_errors}</span>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(GameServer.PubSub, AdminLogBuffer.topic())
      schedule_refresh()
    end

    level_counts = safe_count_by_level()
    logs = AdminLogBuffer.list(module: "", level: "all", query: "", limit: @page_size)

    {:ok,
     assign(socket,
       logs: logs,
       level_filter: "all",
       module_filter: "",
       search_query: "",
       auto_scroll: true,
       level_counts: level_counts,
       total_buffered: Enum.reduce(level_counts, 0, fn {_, v}, acc -> acc + v end),
       recent_errors: safe_count_recent_errors()
     )}
  end

  @impl true
  def handle_info({:admin_log, entry}, socket) do
    # Check if entry matches current filters before prepending
    if matches_filters?(entry, socket.assigns) do
      logs =
        [entry | socket.assigns.logs]
        |> Enum.take(@page_size)

      level_counts = safe_count_by_level()

      {:noreply,
       assign(socket,
         logs: logs,
         level_counts: level_counts,
         total_buffered: Enum.reduce(level_counts, 0, fn {_, v}, acc -> acc + v end)
       )}
    else
      # Still update counts even if entry doesn't match filter
      level_counts = safe_count_by_level()

      {:noreply,
       assign(socket,
         level_counts: level_counts,
         total_buffered: Enum.reduce(level_counts, 0, fn {_, v}, acc -> acc + v end)
       )}
    end
  end

  @impl true
  def handle_info(:refresh_counts, socket) do
    schedule_refresh()

    {:noreply,
     assign(socket,
       recent_errors: safe_count_recent_errors()
     )}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter_level", %{"level" => level}, socket) do
    logs =
      AdminLogBuffer.list(
        module: socket.assigns.module_filter,
        level: level,
        query: socket.assigns.search_query,
        limit: @page_size
      )

    {:noreply, assign(socket, level_filter: level, logs: logs)}
  end

  def handle_event("update_filters", params, socket) do
    module = Map.get(params, "module", "")
    query = Map.get(params, "query", "")
    auto_scroll = Map.get(params, "auto_scroll") == "true"

    logs =
      AdminLogBuffer.list(
        module: module,
        level: socket.assigns.level_filter,
        query: query,
        limit: @page_size
      )

    {:noreply,
     assign(socket,
       module_filter: module,
       search_query: query,
       auto_scroll: auto_scroll,
       logs: logs
     )}
  end

  def handle_event("clear_filters", _params, socket) do
    logs = AdminLogBuffer.list(module: "", level: "all", query: "", limit: @page_size)

    {:noreply,
     assign(socket,
       module_filter: "",
       search_query: "",
       level_filter: "all",
       logs: logs
     )}
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh_counts, @refresh_interval)

  defp matches_filters?(entry, assigns) do
    level_ok? =
      case assigns.level_filter do
        "all" -> true
        level -> entry.level == String.to_existing_atom(level)
      end

    module_ok? =
      case String.trim(assigns.module_filter) do
        "" ->
          true

        filter ->
          mod_str = if entry.module, do: Atom.to_string(entry.module), else: ""
          String.contains?(mod_str, filter)
      end

    query_ok? =
      case String.trim(assigns.search_query) do
        "" ->
          true

        needle ->
          entry.message
          |> to_string()
          |> String.downcase()
          |> String.contains?(String.downcase(needle))
      end

    level_ok? and module_ok? and query_ok?
  end

  defp entry_id(entry) do
    ts = if entry.timestamp, do: DateTime.to_unix(entry.timestamp, :microsecond), else: 0
    "#{ts}-#{:erlang.phash2(entry.message, 999_999)}"
  end

  defp format_module(mod) when is_atom(mod) do
    mod
    |> Atom.to_string()
    |> String.replace_leading("Elixir.", "")
  end

  defp format_module(_), do: ""

  defp level_color(:error), do: "text-error"
  defp level_color(:warning), do: "text-warning"
  defp level_color(:info), do: "text-info"
  defp level_color(:debug), do: "text-base-content/40"
  defp level_color(:notice), do: "text-info"
  defp level_color(_), do: "text-base-content/60"

  defp safe_count_by_level do
    AdminLogBuffer.count_by_level()
  rescue
    _ -> %{}
  end

  defp safe_count_recent_errors do
    AdminLogBuffer.count_recent_errors(3600)
  rescue
    _ -> 0
  end
end
