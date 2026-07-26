defmodule GameServerWeb.AdminLive.Connections do
  use GameServerWeb, :live_view

  alias GameServer.Accounts
  alias GameServerWeb.ConnectionTracker

  @refresh_interval 3_000

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">&larr; Back to Admin</.link>

        <%!-- Summary cards --%>
        <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-5 gap-4">
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">Total Connections</div>
            <div class="text-2xl font-bold">{@conn_stats.total_connections}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">WebSockets</div>
            <div class="text-2xl font-bold">{@conn_stats.ws_sockets}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">LiveViews</div>
            <div class="text-2xl font-bold">{@conn_stats.live_views}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">WebRTC</div>
            <div class="text-2xl font-bold">{@conn_stats.webrtc_peers}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">Cluster Nodes</div>
            <div class="text-2xl font-bold">{@cluster_size}</div>
            <div class="text-xs text-base-content/40 truncate">{node()}</div>
          </div>
        </div>

        <%!-- How it works callout --%>
        <div class="alert shadow-sm">
          <.icon name="hero-information-circle" class="w-5 h-5" />
          <div>
            <p class="text-sm">
              <strong>1 WebSocket = multiple channels.</strong>
              Each game client opens a single WebSocket connection (via UserSocket), then joins multiple
              channel topics (user, lobby, groups, etc.) over that same connection. LiveView pages also
              use WebSocket (separate, Phoenix-managed). WebRTC peers run alongside both and provide
              low-latency DataChannels for high-frequency game data.
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- WebSocket Channels breakdown --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg flex items-center gap-2">
                WebSocket Channels
                <span class="badge badge-sm badge-primary">{@conn_stats.total_channels}</span>
              </h2>
              <p class="text-xs text-base-content/60 mb-2">
                Channel processes running on {@conn_stats.ws_sockets} WebSocket connections
              </p>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>Channel Type</th>
                      <th class="text-right">Count</th>
                      <th class="text-right">Description</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr>
                      <td class="font-medium">User</td>
                      <td class="text-right font-mono">{@conn_stats.user_channels}</td>
                      <td class="text-right text-xs text-base-content/60">
                        Authenticated users (notifications, presence)
                      </td>
                    </tr>
                    <tr>
                      <td class="font-medium">Lobby</td>
                      <td class="text-right font-mono">{@conn_stats.lobby_channels}</td>
                      <td class="text-right text-xs text-base-content/60">
                        Per-lobby events (members + spectators)
                      </td>
                    </tr>
                    <tr>
                      <td class="font-medium">Lobbies</td>
                      <td class="text-right font-mono">{@conn_stats.lobbies_channels}</td>
                      <td class="text-right text-xs text-base-content/60">
                        Global lobby list feed
                      </td>
                    </tr>
                    <tr>
                      <td class="font-medium">Group</td>
                      <td class="text-right font-mono">{@conn_stats.group_channels}</td>
                      <td class="text-right text-xs text-base-content/60">
                        Per-group events (members)
                      </td>
                    </tr>
                    <tr>
                      <td class="font-medium">Groups</td>
                      <td class="text-right font-mono">{@conn_stats.groups_channels}</td>
                      <td class="text-right text-xs text-base-content/60">
                        Global group list feed
                      </td>
                    </tr>
                    <tr>
                      <td class="font-medium">Party</td>
                      <td class="text-right font-mono">{@conn_stats.party_channels}</td>
                      <td class="text-right text-xs text-base-content/60">
                        Per-party events (members)
                      </td>
                    </tr>
                    <tr class="font-bold border-t border-base-300">
                      <td>Total Channels</td>
                      <td class="text-right font-mono">{@conn_stats.total_channels}</td>
                      <td></td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <%!-- LiveView + WebRTC --%>
          <div class="space-y-6">
            <%!-- LiveView Sessions --%>
            <div class="card bg-base-200 shadow">
              <div class="card-body">
                <h2 class="card-title text-lg flex items-center gap-2">
                  LiveView Sessions
                  <span class="badge badge-sm badge-primary">{@conn_stats.live_views}</span>
                </h2>
                <p class="text-xs text-base-content/60 mb-2">
                  Active browser tabs with server-rendered real-time pages
                </p>
                <%= if @live_view_pages == [] do %>
                  <div class="text-center py-4 text-base-content/40 text-sm">
                    No LiveView sessions active
                  </div>
                <% else %>
                  <div class="overflow-x-auto">
                    <table class="table table-sm">
                      <thead>
                        <tr>
                          <th>Page</th>
                          <th class="text-right">Active</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={{module, count} <- @live_view_pages}>
                          <td class="font-mono text-xs">{short_module(module)}</td>
                          <td class="text-right font-mono">{count}</td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                <% end %>
              </div>
            </div>
            <%!-- WebRTC Peers --%>
            <div class="card bg-base-200 shadow">
              <div class="card-body">
                <h2 class="card-title text-lg flex items-center gap-2">
                  WebRTC <span class="badge badge-sm badge-primary">{@conn_stats.webrtc_peers}</span>
                </h2>
                <p class="text-xs text-base-content/60 mb-2">
                  Active DataChannel connections
                </p>
                <%= if @webrtc_users == [] do %>
                  <div class="text-center py-4 text-base-content/40 text-sm">
                    No WebRTC peers active
                  </div>
                <% else %>
                  <div class="overflow-x-auto">
                    <table class="table table-sm">
                      <thead>
                        <tr>
                          <th>User ID</th>
                          <th>PID</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={peer <- @webrtc_users}>
                          <td class="text-sm" title={peer.user_id}>
                            {user_display(@user_names[peer.user_id])}
                          </td>
                          <td class="font-mono text-xs text-base-content/50">{peer.pid}</td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <%!-- Connected Users --%>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-lg flex items-center gap-2">
              Connected Users
              <span class="badge badge-sm badge-primary">{@total_connected_users}</span>
            </h2>
            <p class="text-sm text-base-content/60 mb-4">
              All users with active connections (WebSocket channels, LiveView, or WebRTC).
            </p>

            <%!-- Filter buttons --%>
            <div class="flex flex-wrap gap-2 mb-4">
              <button
                :for={
                  {label, value} <- [
                    {"All", "all"},
                    {"WebSocket", "websocket"},
                    {"LiveView", "liveview"},
                    {"WebRTC", "webrtc"}
                  ]
                }
                phx-click="filter-connections"
                phx-value-filter={value}
                class={[
                  "btn btn-sm",
                  if(@conn_filter == value, do: "btn-primary", else: "btn-outline")
                ]}
              >
                {label}
              </button>
            </div>

            <%= if @paged_users == [] do %>
              <div class="text-center py-8 text-base-content/40">
                No users currently connected
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table table-sm table-zebra">
                  <thead>
                    <tr>
                      <th>User ID</th>
                      <th>Connection Types</th>
                      <th>Details</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={user <- @paged_users} id={"conn-user-#{user.user_id}"}>
                      <td class="text-sm" title={user.user_id}>
                        {user_display(@user_names[user.user_id])}
                      </td>
                      <td>
                        <div class="flex flex-wrap gap-1">
                          <span
                            :if={user.channels != []}
                            class="badge badge-sm badge-primary"
                          >
                            WebSocket
                          </span>
                          <span :if={user.live_view} class="badge badge-sm badge-primary">
                            LiveView
                          </span>
                          <span :if={user.webrtc} class="badge badge-sm badge-primary">
                            WebRTC
                          </span>
                        </div>
                      </td>
                      <td class="text-xs text-base-content/50">
                        <span class="font-mono">
                          {Enum.join(user.detail_labels, ", ")}
                        </span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <%!-- Pagination controls --%>
              <div class="flex items-center justify-between mt-4">
                <span class="text-sm text-base-content/60">
                  Page {@conn_page} / {@conn_total_pages} ({@conn_filtered_count} users)
                </span>
                <div class="join">
                  <button
                    class="join-item btn btn-sm"
                    phx-click="page-connections"
                    phx-value-page={@conn_page - 1}
                    disabled={@conn_page <= 1}
                  >
                    &larr; Prev
                  </button>
                  <button
                    class="join-item btn btn-sm"
                    phx-click="page-connections"
                    phx-value-page={@conn_page + 1}
                    disabled={@conn_page >= @conn_total_pages}
                  >
                    Next &rarr;
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    socket =
      socket
      |> assign(conn_page: 1, conn_filter: "all")
      |> assign_all()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, assign_all(socket)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter-connections", %{"filter" => filter}, socket) do
    {:noreply,
     socket
     |> assign(conn_filter: filter, conn_page: 1)
     |> assign_all()}
  end

  @impl true
  def handle_event("page-connections", %{"page" => page}, socket) do
    page = String.to_integer(page)

    {:noreply,
     socket
     |> assign(conn_page: max(page, 1))
     |> assign_all()}
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval)

  defp assign_all(socket) do
    all = ConnectionTracker.all_registered()
    connected_users = build_connected_users(all)

    filter = socket.assigns.conn_filter
    page = socket.assigns.conn_page

    filtered =
      case filter do
        "websocket" -> Enum.filter(connected_users, &(&1.channels != []))
        "liveview" -> Enum.filter(connected_users, & &1.live_view)
        "webrtc" -> Enum.filter(connected_users, & &1.webrtc)
        _all -> connected_users
      end

    filtered_count = length(filtered)
    total_pages = max(ceil(filtered_count / @per_page), 1)
    page = min(page, total_pages)

    paged =
      filtered
      |> Enum.drop((page - 1) * @per_page)
      |> Enum.take(@per_page)

    webrtc = build_webrtc_users(all)

    assign(socket,
      conn_stats: ConnectionTracker.cluster_counts(),
      total_connected_users: length(connected_users),
      paged_users: paged,
      conn_filtered_count: filtered_count,
      conn_total_pages: total_pages,
      conn_page: page,
      live_view_pages: build_live_view_pages(all),
      webrtc_users: webrtc,
      user_names: Accounts.users_by_ids(Enum.map(paged ++ webrtc, & &1.user_id)),
      cluster_size: 1 + length(Node.list())
    )
  end

  defp build_connected_users(all) do
    channel_types = [
      {:user_channel, "user"},
      {:lobby_channel, "lobby"},
      {:group_channel, "group"},
      {:party_channel, "party"}
    ]

    user_data =
      Enum.reduce(channel_types, %{}, fn {type, label}, acc ->
        merge_channel_users(Map.get(all, type, []), label, acc)
      end)

    # Add LiveView info
    user_data =
      Enum.reduce(Map.get(all, :live_view, []), user_data, fn {_pid, meta}, acc ->
        user_id = Map.get(meta, :user_id)
        module = Map.get(meta, :module, "unknown")

        if user_id do
          Map.update(
            acc,
            user_id,
            %{channels: [], live_view: true, live_view_pages: [module], webrtc: false},
            fn existing ->
              %{existing | live_view: true, live_view_pages: [module | existing.live_view_pages]}
            end
          )
        else
          acc
        end
      end)

    # Add WebRTC info
    webrtc_users =
      all
      |> Map.get(:webrtc_peer, [])
      |> Enum.map(fn {_pid, meta} -> Map.get(meta, :user_id) end)
      |> MapSet.new()

    user_data
    |> Enum.map(fn {user_id, data} ->
      ws_labels = data.channels |> Enum.uniq() |> Enum.sort() |> Enum.map(&"WebSocket:#{&1}")
      lv_labels = data.live_view_pages |> Enum.uniq() |> Enum.map(&"LiveView:#{short_module(&1)}")

      %{
        user_id: user_id,
        channels: data.channels |> Enum.uniq() |> Enum.sort(),
        live_view: data.live_view,
        webrtc: MapSet.member?(webrtc_users, user_id),
        detail_labels: ws_labels ++ lv_labels
      }
    end)
    |> Enum.sort_by(& &1.user_id)
  end

  defp build_live_view_pages(all) do
    all
    |> Map.get(:live_view, [])
    |> Enum.map(fn {_pid, meta} -> Map.get(meta, :module, "unknown") end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
  end

  defp build_webrtc_users(all) do
    all
    |> Map.get(:webrtc_peer, [])
    |> Enum.map(fn {pid, meta} ->
      %{user_id: Map.get(meta, :user_id), pid: inspect(pid)}
    end)
    |> Enum.sort_by(& &1.user_id)
  end

  defp short_module(module) do
    module
    |> String.replace("GameServerWeb.", "")
    |> String.replace("AdminLive.", "Admin.")
  end

  defp merge_channel_users(entries, label, acc) do
    Enum.reduce(entries, acc, fn {_pid, meta}, inner_acc ->
      user_id = Map.get(meta, :user_id)

      if user_id do
        Map.update(
          inner_acc,
          user_id,
          %{channels: [label], live_view: false, live_view_pages: [], webrtc: false},
          fn existing -> %{existing | channels: [label | existing.channels]} end
        )
      else
        inner_acc
      end
    end)
  end
end
