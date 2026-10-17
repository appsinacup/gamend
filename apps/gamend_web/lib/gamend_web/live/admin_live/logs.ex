defmodule GamendWeb.AdminLive.Logs do
  @moduledoc """
  Logs, from both sides of the wire.

  Two tabs over one stream. Client entries are re-emitted through `Logger`
  (see `Gamend.ClientLogs`), so they land in the same ring buffer as the
  server's own lines and can be read against them — which is the point, and
  also why the server tab defaults to hiding them. A tail swamped by every
  connected player's chatter is not a tail anyone can read.

  ## What is durable here and what is not

  The **client** tab's session list is a database table and survives restarts.
  The lines themselves are not stored: they leave through `Logger` to whatever
  the host runs (stdout, the rotating file, an aggregator), and what this page
  can show of them is the in-memory ring buffer — recent, and lost on redeploy.

  So a session's timeline here is "what is still in the buffer", and the page
  says so rather than rendering an empty list that reads like "nothing
  happened". For anything older, the session detail hands over the exact search
  string to paste into the host's log store, where both halves are already
  sitting next to each other under the same session id.
  """
  use GamendWeb, :live_view

  alias Gamend.ClientLogs
  alias GamendWeb.AdminLogBuffer
  alias GamendWeb.LiveHelpers

  @refresh_interval 3_000
  @page_size 200
  @session_page_size 50

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div class="flex items-center gap-3">
            <.link navigate={~p"/admin"} class="btn btn-surface btn-sm">&larr; Back to Admin</.link>
            <h1 class="text-xl font-bold">Logs</h1>
          </div>

          <div class="flex items-center gap-2 text-xs text-muted">
            <span>
              Buffer: {ngettext("%{count} entry", "%{count} entries", @total_buffered)}
            </span>
            <span>&middot;</span>
            <span>{@source_counts.client} from clients</span>
            <span :if={@buffer_level_counts[:error]} class="text-error font-semibold">
              &middot; {ngettext("%{count} error", "%{count} errors", @buffer_level_counts[:error])}
            </span>
          </div>
        </div>

        <%!-- Tabs --%>
        <div role="tablist" class="tabs tabs-box w-fit">
          <button
            :for={{tab, label} <- [{"server", "Server"}, {"client", "Client sessions"}]}
            role="tab"
            phx-click="switch_tab"
            phx-value-tab={tab}
            class={["tab", @tab == tab && "tab-active"]}
          >
            {label}
          </button>
        </div>

        <%!-- A client can be told to collect `info`, and the server's own Logger
              level can then throw it away before any handler runs. Two settings,
              no shared owner, and the failure mode is a page that just looks
              quiet — so say it outright. --%>
        <div :if={@logger_blocks} class="alert alert-warning text-sm">
          <div>
            <span class="font-semibold">Client entries are being discarded.</span>
            Collection asks for <span class="font-mono">{@policy.level}</span>
            but this server's Logger level is <span class="font-mono">{@logger_level}</span>, which drops everything below it. Lower the Logger level, or raise the client
            capture level, or expect to see only entries at
            <span class="font-mono">{@logger_level}</span>
            and above.
          </div>
        </div>

        <.server_tab :if={@tab == "server"} {assigns} />
        <.client_tab :if={@tab == "client"} {assigns} />
      </div>
    </Layouts.app>
    """
  end

  # ── Server tab ──────────────────────────────────────────────────────────────

  defp server_tab(assigns) do
    ~H"""
    <div class="space-y-4">
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
          <span :if={level == "all"} class="ml-1 opacity-70">({@facet_total})</span>
        </button>
      </div>

      <.form
        for={%{}}
        id="log-filters"
        phx-change="update_filters"
        phx-no-unused-field
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2"
      >
        <select name="source" class="select select-sm">
          <option
            :for={
              {value, label} <- [
                {"server", "Server only"},
                {"client", "Client only"},
                {"all", "Both"}
              ]
            }
            value={value}
            selected={@source_filter == value}
          >
            {label}
          </option>
        </select>
        <input
          id="log-module-filter"
          name="module"
          value={@module_filter}
          placeholder="Module (e.g. Gamend.Hooks)"
          class="input input-sm"
          phx-debounce="300"
        />
        <input
          id="log-session-filter"
          name="session"
          value={@session_filter}
          placeholder="Client session id"
          class="input input-sm font-mono"
          phx-debounce="300"
        />
        <input
          id="log-user-filter"
          name="user"
          value={@user_filter}
          placeholder="User id"
          class="input input-sm font-mono"
          phx-debounce="300"
        />
        <input
          id="log-search"
          name="query"
          value={@search_query}
          placeholder="Search message text"
          class="input input-sm sm:col-span-2"
          phx-debounce="300"
        />
        <div class="flex items-center gap-2 sm:col-span-2">
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
          <button type="button" phx-click="clear_filters" class="btn btn-ghost btn-sm">Clear</button>
        </div>
      </.form>

      <div
        id="log-container"
        class="bg-base-100 border rounded-lg font-mono text-xs overflow-auto"
        style="max-height: calc(100vh - 380px); min-height: 400px;"
        phx-hook={if @auto_scroll, do: "AutoScroll", else: nil}
      >
        <div class="p-3 space-y-0.5">
          <div :if={@logs == []} class="text-center text-muted py-8 italic">
            No logs match the current filters.
          </div>
          <div
            :for={entry <- Enum.reverse(@logs)}
            id={"log-#{entry_id(entry)}"}
            class={[
              "flex gap-2 py-0.5 px-1 rounded hover:bg-base-200 transition-colors",
              entry.level == :error && "bg-error/5",
              entry.level == :warning && "bg-warning/5"
            ]}
          >
            <span class="text-muted whitespace-nowrap shrink-0">
              <.timestamp at={entry.timestamp} format="time" empty="" />
            </span>
            <span class={[
              "whitespace-nowrap shrink-0 font-semibold w-14 text-right",
              level_color(entry.level)
            ]}>
              [{entry.level}]
            </span>
            <span
              :if={client_entry?(entry)}
              class="badge badge-xs badge-accent shrink-0"
              title="Uploaded by a game client"
            >
              client
            </span>
            <span
              :if={not client_entry?(entry) and entry.module}
              class="text-primary/60 whitespace-nowrap shrink-0 max-w-48 truncate"
              title={inspect(entry.module)}
            >
              {format_module(entry.module)}
            </span>
            <span class="break-all">{entry.message}</span>
          </div>
        </div>
      </div>

      <div class="flex items-center justify-between text-xs text-muted">
        <%!-- Two numbers, because they answer two different questions: how much
              the filters match, and how much is in the buffer behind them. One
              number here read as "the buffer only has one error in it". --%>
        <span>
          Showing {length(@logs)} of {@matching_total} matching
          <span :if={@matching_total != @total_buffered} class="opacity-70">
            ({@total_buffered} buffered)
          </span>
        </span>
        <span>Errors in last hour: {@recent_errors}</span>
      </div>
    </div>
    """
  end

  # ── Client tab ──────────────────────────────────────────────────────────────

  defp client_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div :if={not @policy.enabled} class="alert alert-info text-sm">
        <div>
          <span class="font-semibold">Client log collection is off.</span>
          Clients are told to send nothing. Enable it with
          <span class="font-mono">GAMEND_CLIENT_LOGS_ENABLED=true</span>
          (see <.link navigate={~p"/admin/settings"} class="link">Settings</.link>) and restart.
        </div>
      </div>

      <.selected_session :if={@selected} {assigns} />

      <.form
        for={%{}}
        id="session-filters"
        phx-change="update_session_filters"
        phx-no-unused-field
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2"
      >
        <input
          name="query"
          value={@session_filters.query}
          placeholder="Session or device id"
          class="input input-sm font-mono"
          phx-debounce="300"
        />
        <input
          name="user_id"
          value={@session_filters.user_id}
          placeholder="User id"
          class="input input-sm font-mono"
          phx-debounce="300"
        />
        <input
          name="lobby_id"
          value={@session_filters.lobby_id}
          placeholder="Lobby id"
          class="input input-sm font-mono"
          phx-debounce="300"
        />
        <select name="platform" class="select select-sm">
          <option value="">Any platform</option>
          <option
            :for={p <- ClientLogs.Session.platforms()}
            value={p}
            selected={@session_filters.platform == p}
          >
            {p}
          </option>
        </select>
        <input
          name="app_version"
          value={@session_filters.app_version}
          placeholder="App version"
          class="input input-sm"
          phx-debounce="300"
        />
        <label class="input input-sm flex items-center gap-2">
          <span class="text-xs opacity-70 whitespace-nowrap">From</span>
          <input type="date" name="since" value={@session_filters.since} class="grow" />
        </label>
        <label class="input input-sm flex items-center gap-2">
          <span class="text-xs opacity-70 whitespace-nowrap">To</span>
          <input type="date" name="until" value={@session_filters.until} class="grow" />
        </label>
        <div class="flex items-center gap-3">
          <label class="label cursor-pointer gap-2">
            <input
              type="checkbox"
              name="errors_only"
              value="true"
              checked={@session_filters.errors_only}
              class="checkbox checkbox-sm checkbox-error"
            />
            <span class="text-xs">Errors only</span>
          </label>
          <button type="button" phx-click="clear_session_filters" class="btn btn-ghost btn-sm">
            Clear
          </button>
        </div>
      </.form>

      <div class="overflow-x-auto border rounded-lg">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Last seen</th>
              <th>Session</th>
              <th>User</th>
              <th>Platform · version</th>
              <th class="text-right">Entries</th>
              <th class="text-right">Errors</th>
              <th class="text-right">Dropped</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@sessions == []}>
              <td colspan="7" class="text-center text-muted py-8 italic">
                No client sessions match these filters.
              </td>
            </tr>
            <tr
              :for={session <- @sessions}
              class={[
                "hover cursor-pointer",
                @selected && @selected.client_session_id == session.client_session_id &&
                  "bg-base-200"
              ]}
              phx-click="select_session"
              phx-value-id={session.client_session_id}
            >
              <td class="whitespace-nowrap">
                <.timestamp at={session.last_seen_at} format="full" empty="—" />
              </td>
              <td class="font-mono text-xs">
                <span class="flex items-center gap-1">
                  {short(session.client_session_id)}
                  <span :if={session.flagged} class="badge badge-xs badge-warning">flagged</span>
                </span>
              </td>
              <td class="text-xs">
                <span :if={session.user}>{session.user.username || short(session.user_id)}</span>
                <span :if={is_nil(session.user_id)} class="opacity-60 italic">anonymous</span>
              </td>
              <td class="text-xs whitespace-nowrap">
                {session.platform} &middot; {version(session)}
              </td>
              <td class="text-right tabular-nums">{session.entry_count}</td>
              <td class={[
                "text-right tabular-nums",
                session.error_count > 0 && "text-error font-semibold"
              ]}>
                {session.error_count}
              </td>
              <td class={[
                "text-right tabular-nums",
                session.dropped_count > 0 && "text-warning"
              ]}>
                {session.dropped_count}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="flex items-center justify-between text-xs text-muted">
        <span>Showing {length(@sessions)} of {@session_total} sessions</span>
        <div class="flex gap-2">
          <button
            phx-click="page"
            phx-value-dir="prev"
            disabled={@session_page <= 1}
            class="btn btn-ghost btn-xs"
          >
            &larr; Prev
          </button>
          <button
            phx-click="page"
            phx-value-dir="next"
            disabled={@session_page >= @session_total_pages}
            class="btn btn-ghost btn-xs"
          >
            Next &rarr;
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp selected_session(assigns) do
    ~H"""
    <div class="border rounded-lg bg-base-100 p-4 space-y-3">
      <div class="flex items-start justify-between gap-3">
        <div class="space-y-1">
          <div class="flex items-center gap-2">
            <h2 class="font-semibold font-mono text-sm">{@selected.client_session_id}</h2>
            <span :if={@selected.flagged} class="badge badge-sm badge-warning">flagged</span>
          </div>
          <div class="text-xs text-muted flex flex-wrap gap-x-3 gap-y-1">
            <span>{@selected.platform} &middot; {version(@selected)} &middot; {@selected.build}</span>
            <span :if={@selected.locale != ""}>locale {@selected.locale}</span>
            <span :if={@selected.device_id != ""} class="font-mono">device {short(@selected.device_id)}</span>
            <span>
              started <.timestamp at={@selected.started_at} format="full" empty="—" />
            </span>
            <span :if={@selected.dropped_count > 0} class="text-warning font-semibold">
              {ngettext(
                "%{count} entry never arrived",
                "%{count} entries never arrived",
                @selected.dropped_count
              )}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <button phx-click="toggle_flag" class="btn btn-ghost btn-xs">
            {if @selected.flagged, do: "Unflag", else: "Flag"}
          </button>
          <button phx-click="close_session" class="btn btn-ghost btn-xs">Close</button>
        </div>
      </div>

      <%!-- What the device was. Rendered as a plain grid rather than being
            summarised, because which of these matters is only obvious once you
            know what broke — the renderer for a black texture, the OS version
            for a crash, the browser for a web-only fault. --%>
      <div :if={@selected.meta != %{}} class="rounded bg-base-200 p-2">
        <dl class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-x-4 gap-y-1 text-xs">
          <div :for={{key, value} <- Enum.sort(@selected.meta)} class="min-w-0">
            <dt class="opacity-60">{key}</dt>
            <dd class="font-mono truncate" title={to_string(value)}>{value}</dd>
          </div>
        </dl>
      </div>

      <%!-- Lobbies are the join to the server's own run history, so they are
            links rather than text. --%>
      <div :if={@selected_lobbies != []} class="flex flex-wrap items-center gap-2 text-xs">
        <span class="opacity-70">Lobbies:</span>
        <.link
          :for={lobby_id <- @selected_lobbies}
          navigate={~p"/admin/lobby_snapshots?lobby_id=#{lobby_id}"}
          class="link link-primary font-mono"
        >
          {short(lobby_id)}
        </.link>
      </div>

      <%!-- The buffer is a ring and does not survive a restart, so what is
            missing here is not evidence that nothing happened. --%>
      <div class="space-y-1">
        <div class="flex items-center justify-between text-xs text-muted">
          <span>
            Recent lines still in the buffer: {length(@selected_entries)} of {@selected.entry_count} this session recorded
          </span>
        </div>
        <div class="bg-base-200 rounded font-mono text-xs overflow-auto max-h-96 p-2 space-y-0.5">
          <div :if={@selected_entries == []} class="italic opacity-70 py-4 text-center">
            None of this session's lines are still buffered — the ring is capped and clears on
            restart. Search the log store below.
          </div>
          <div
            :for={entry <- Enum.reverse(@selected_entries)}
            class={[
              "flex gap-2 px-1 rounded",
              entry.level == :error && "bg-error/10",
              entry.level == :warning && "bg-warning/10"
            ]}
          >
            <span class="opacity-60 whitespace-nowrap shrink-0">
              <.timestamp at={entry.timestamp} format="time" empty="" />
            </span>
            <span class="break-all">{entry.message}</span>
          </div>
        </div>
        <div class="text-xs text-muted">
          Full history lives in the log store. Search it for
          <code class="bg-base-200 px-1 rounded font-mono select-all">
            session={@selected.client_session_id}
          </code>
          — server lines carry the same id, so that one search returns both sides.
        </div>
      </div>
    </div>
    """
  end

  # ── Lifecycle ───────────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Gamend.PubSub, AdminLogBuffer.topic())
      schedule_refresh()
    end

    {:ok,
     socket
     |> assign(
       tab: "server",
       level_filter: "all",
       module_filter: "",
       search_query: "",
       session_filter: "",
       user_filter: "",
       # Client entries share this buffer; showing them by default would bury
       # the server's own tail.
       source_filter: "server",
       auto_scroll: true,
       selected: nil,
       selected_entries: [],
       selected_lobbies: [],
       session_page: 1,
       session_total_pages: 0,
       session_page_size: @session_page_size,
       session_filters: empty_session_filters()
     )
     |> refresh_logs()
     |> refresh_counts()
     |> load_sessions()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Deep link from a lobby's server-side history: "which clients were in this
    # run". Same route, so the link does not need to know this page's internals.
    case Map.get(params, "lobby_id") do
      lobby_id when is_binary(lobby_id) and lobby_id != "" ->
        filters = %{empty_session_filters() | lobby_id: lobby_id}

        {:noreply,
         socket
         |> assign(tab: "client", session_filters: filters, session_page: 1)
         |> load_sessions()}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:admin_log, entry}, socket) do
    socket =
      if socket.assigns.tab == "server" and matches_filters?(entry, socket.assigns) do
        assign(socket, logs: Enum.take([entry | socket.assigns.logs], @page_size))
      else
        socket
      end

    # A live line belonging to the open session extends its timeline.
    socket =
      if socket.assigns.selected && belongs_to_session?(entry, socket.assigns.selected) do
        # Newest first here; the template reverses once for display. Appending
        # per arriving line would walk the whole list on every log entry.
        assign(socket,
          selected_entries: Enum.take([entry | socket.assigns.selected_entries], 500)
        )
      else
        socket
      end

    {:noreply, refresh_counts(socket)}
  end

  def handle_info(:refresh_counts, socket) do
    schedule_refresh()
    socket = if socket.assigns.tab == "client", do: load_sessions(socket), else: socket
    {:noreply, refresh_counts(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in ["server", "client"] do
    socket = assign(socket, tab: tab)
    {:noreply, if(tab == "client", do: load_sessions(socket), else: socket)}
  end

  def handle_event("filter_level", %{"level" => level}, socket) do
    {:noreply, socket |> assign(level_filter: level) |> refresh_logs()}
  end

  def handle_event("update_filters", params, socket) do
    {:noreply,
     socket
     |> assign(
       module_filter: Map.get(params, "module", ""),
       search_query: Map.get(params, "query", ""),
       session_filter: Map.get(params, "session", ""),
       user_filter: Map.get(params, "user", ""),
       source_filter: Map.get(params, "source", "server"),
       auto_scroll: Map.get(params, "auto_scroll") == "true"
     )
     |> refresh_logs()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(
       module_filter: "",
       search_query: "",
       session_filter: "",
       user_filter: "",
       level_filter: "all",
       source_filter: "server"
     )
     |> refresh_logs()}
  end

  def handle_event("update_session_filters", params, socket) do
    filters = %{
      query: Map.get(params, "query", ""),
      user_id: Map.get(params, "user_id", ""),
      lobby_id: Map.get(params, "lobby_id", ""),
      platform: Map.get(params, "platform", ""),
      app_version: Map.get(params, "app_version", ""),
      since: Map.get(params, "since", ""),
      until: Map.get(params, "until", ""),
      errors_only: Map.get(params, "errors_only") == "true"
    }

    {:noreply, socket |> assign(session_filters: filters, session_page: 1) |> load_sessions()}
  end

  def handle_event("clear_session_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(session_filters: empty_session_filters(), session_page: 1)
     |> load_sessions()}
  end

  def handle_event("page", %{"dir" => "next"}, socket),
    do: {:noreply, socket |> LiveHelpers.next_page(:session_page) |> load_sessions()}

  def handle_event("page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page(:session_page) |> load_sessions()}

  def handle_event("select_session", %{"id" => id}, socket) do
    {:noreply, select_session(socket, id)}
  end

  def handle_event("close_session", _params, socket) do
    {:noreply, assign(socket, selected: nil, selected_entries: [], selected_lobbies: [])}
  end

  def handle_event("toggle_flag", _params, %{assigns: %{selected: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("toggle_flag", _params, socket) do
    session = socket.assigns.selected
    :ok = ClientLogs.set_flagged(session.client_session_id, not session.flagged)

    {:noreply, socket |> select_session(session.client_session_id) |> load_sessions()}
  end

  # ── Loading ─────────────────────────────────────────────────────────────────

  defp filter_opts(socket) do
    [
      module: socket.assigns.module_filter,
      level: socket.assigns.level_filter,
      query: socket.assigns.search_query,
      session: socket.assigns.session_filter,
      user: socket.assigns.user_filter,
      source: socket.assigns.source_filter
    ]
  end

  defp refresh_logs(socket) do
    socket
    |> assign(
      logs:
        safe(
          fn -> AdminLogBuffer.list(Keyword.put(filter_opts(socket), :limit, @page_size)) end,
          []
        )
    )
    |> refresh_filter_counts()
  end

  # The level chips are a filter control, so each count has to mean "how many
  # you would see if you clicked this": every other filter applied, the level
  # itself ignored. Counting the whole buffer instead is what let this page
  # offer `error(7)` and then list one entry — six of those seven were client
  # entries, and `source_filter` defaults to server-only.
  #
  # Recomputed with the list rather than on the counts tick, so it can never
  # disagree with the rows underneath it.
  defp refresh_filter_counts(socket) do
    level_counts = safe(fn -> AdminLogBuffer.count_by_level(filter_opts(socket)) end, %{})
    facet_total = level_counts |> Map.values() |> Enum.sum()

    matching_total =
      case level_atom(socket.assigns.level_filter) do
        nil -> facet_total
        level -> Map.get(level_counts, level, 0)
      end

    assign(socket,
      level_counts: level_counts,
      facet_total: facet_total,
      matching_total: matching_total
    )
  end

  # `nil` means "no level filter" — including a level string that names no
  # level, which `AdminLogBuffer` also ignores rather than filtering to nothing.
  defp level_atom(level) when level in [nil, "", "all"], do: nil

  defp level_atom(level) when is_binary(level) do
    String.to_existing_atom(level)
  rescue
    ArgumentError -> nil
  end

  defp level_atom(_level), do: nil

  defp refresh_counts(socket) do
    # Unfiltered, deliberately: the header line is labelled "Buffer", and a
    # number under that label must describe the buffer and not the view.
    buffer_level_counts = safe(&AdminLogBuffer.count_by_level/0, %{})

    socket
    |> assign(
      buffer_level_counts: buffer_level_counts,
      source_counts: safe(&AdminLogBuffer.count_by_source/0, %{server: 0, client: 0}),
      total_buffered: buffer_level_counts |> Map.values() |> Enum.sum(),
      recent_errors: safe(fn -> AdminLogBuffer.count_recent_errors(3600) end, 0),
      policy: ClientLogs.capture_policy(),
      logger_level: Logger.level(),
      logger_blocks: ClientLogs.logger_level_blocks_collection?()
    )
    |> refresh_filter_counts()
  end

  defp load_sessions(socket) do
    opts = session_opts(socket.assigns.session_filters, socket.assigns.session_page)
    total = ClientLogs.count_sessions(Keyword.drop(opts, [:page, :page_size]))

    assign(socket,
      sessions: ClientLogs.list_sessions(opts),
      session_total: total,
      session_total_pages: LiveHelpers.total_pages(total, @session_page_size)
    )
  end

  defp select_session(socket, id) do
    case ClientLogs.get_session(id) do
      nil ->
        assign(socket, selected: nil, selected_entries: [], selected_lobbies: [])

      session ->
        assign(socket,
          selected: session,
          # Newest first, matching what live arrivals prepend.
          selected_entries: safe(fn -> Enum.reverse(AdminLogBuffer.session_entries(id)) end, []),
          selected_lobbies: ClientLogs.session_lobby_ids(id)
        )
    end
  end

  defp session_opts(filters, page) do
    [page: page, page_size: @session_page_size]
    |> put_unless_blank(:query, filters.query)
    |> put_unless_blank(:user_id, filters.user_id)
    |> put_unless_blank(:lobby_id, filters.lobby_id)
    |> put_unless_blank(:platform, filters.platform)
    |> put_unless_blank(:app_version, filters.app_version)
    |> put_date(:since, filters.since, ~T[00:00:00])
    |> put_date(:until, filters.until, ~T[23:59:59])
    |> then(fn opts -> if filters.errors_only, do: [{:errors_only, true} | opts], else: opts end)
  end

  defp put_unless_blank(opts, _key, value) when value in [nil, ""], do: opts
  defp put_unless_blank(opts, key, value), do: [{key, value} | opts]

  defp put_date(opts, _key, value, _time) when value in [nil, ""], do: opts

  defp put_date(opts, key, value, time) do
    case Date.from_iso8601(value) do
      {:ok, date} -> [{key, DateTime.new!(date, time, "Etc/UTC")} | opts]
      _ -> opts
    end
  end

  defp empty_session_filters do
    %{
      query: "",
      user_id: "",
      lobby_id: "",
      platform: "",
      app_version: "",
      since: "",
      until: "",
      errors_only: false
    }
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp schedule_refresh, do: Process.send_after(self(), :refresh_counts, @refresh_interval)

  defp client_entry?(entry), do: Map.get(entry[:meta] || %{}, :source) == :client

  defp belongs_to_session?(entry, session) do
    to_string(Map.get(entry[:meta] || %{}, :client_session, "")) == session.client_session_id
  end

  defp matches_filters?(entry, assigns) do
    source_ok? =
      case assigns.source_filter do
        "client" -> client_entry?(entry)
        "server" -> not client_entry?(entry)
        _ -> true
      end

    level_ok? =
      case assigns.level_filter do
        "all" -> true
        level -> entry.level == String.to_existing_atom(level)
      end

    module_ok? =
      case String.trim(assigns.module_filter) do
        "" -> true
        filter -> String.contains?(module_string(entry.module), filter)
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

    session_ok? = meta_matches?(entry, :client_session, assigns.session_filter)

    user_ok? =
      assigns.user_filter in [nil, ""] or
        Enum.any?([:client_user_id, :user_id], &meta_matches?(entry, &1, assigns.user_filter))

    source_ok? and level_ok? and module_ok? and query_ok? and session_ok? and user_ok?
  end

  defp meta_matches?(_entry, _key, filter) when filter in [nil, ""], do: true

  defp meta_matches?(entry, key, filter),
    do: to_string(Map.get(entry[:meta] || %{}, key, "")) == filter

  defp module_string(nil), do: ""
  defp module_string(mod) when is_atom(mod), do: Atom.to_string(mod)
  defp module_string(other), do: to_string(other)

  defp entry_id(entry) do
    ts = if entry.timestamp, do: DateTime.to_unix(entry.timestamp, :microsecond), else: 0
    "#{ts}-#{:erlang.phash2(entry.message, 999_999)}"
  end

  defp format_module(mod) when is_atom(mod) do
    mod |> Atom.to_string() |> String.replace_leading("Elixir.", "")
  end

  defp format_module(_), do: ""

  defp short(nil), do: "—"
  defp short(""), do: "—"
  defp short(id) when is_binary(id), do: String.slice(id, 0, 12)

  defp version(%{app_version: ""}), do: "unknown"
  defp version(%{app_version: version}), do: version

  defp level_color(:error), do: "text-error"
  defp level_color(:warning), do: "text-warning"
  defp level_color(:info), do: "text-info"
  defp level_color(:debug), do: "text-muted"
  defp level_color(:notice), do: "text-info"
  defp level_color(_), do: "text-muted"

  # The buffer's ETS table may not exist yet during boot, and a log viewer that
  # crashes the moment there is nothing to view is worse than an empty one.
  defp safe(fun, default) do
    fun.()
  rescue
    _ -> default
  end
end
