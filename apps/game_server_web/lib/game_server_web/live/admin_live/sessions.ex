defmodule GameServerWeb.AdminLive.Sessions do
  use GameServerWeb, :live_view

  alias GameServer.Accounts
  alias GameServer.Accounts.UserToken
  alias GameServer.Repo

  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">
          ← Back to Admin
        </.link>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex items-center justify-between gap-3">
              <h2 class="card-title">Active Sessions ({@sessions_count})</h2>
              <button
                type="button"
                phx-click="bulk_delete"
                data-confirm={"Delete #{MapSet.size(@selected_ids)} selected sessions?"}
                class="btn btn-sm btn-outline btn-error"
                disabled={MapSet.size(@selected_ids) == 0}
              >
                Delete selected ({MapSet.size(@selected_ids)})
              </button>
            </div>
            <div class="overflow-x-auto">
              <table class="table table-zebra">
                <thead>
                  <tr>
                    <th class="w-10">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        phx-click="toggle_select_all"
                        checked={
                          @recent_sessions != [] &&
                            MapSet.size(@selected_ids) == length(@recent_sessions)
                        }
                      />
                    </th>
                    <th>User Email</th>
                    <th>Context</th>
                    <th>Created</th>
                    <th>Last Used</th>
                    <th>Expires</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={session <- @recent_sessions} id={"session-#{session.id}"}>
                    <td class="w-10">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        phx-click="toggle_select"
                        phx-value-id={session.id}
                        checked={MapSet.member?(@selected_ids, session.id)}
                      />
                    </td>
                    <td class="font-mono text-sm">{session.user.email}</td>
                    <td>
                      <span class="badge badge-info badge-sm">{session.context}</span>
                    </td>
                    <td class="text-sm">
                      <.timestamp at={session.inserted_at} />
                    </td>
                    <td class="text-sm">
                      <%= if session.authenticated_at do %>
                        <.timestamp at={session.authenticated_at} />
                      <% else %>
                        <span class="text-gray-500">Never</span>
                      <% end %>
                    </td>
                    <td class="text-sm">
                      <%= if session.context == "session" do %>
                        <.timestamp at={DateTime.add(session.inserted_at, 14, :day)} />
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td>
                      <button
                        phx-click="delete_session"
                        phx-value-id={session.id}
                        data-confirm="Are you sure you want to delete this session?"
                        class="btn btn-xs btn-outline btn-error"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="mt-4">
              <.pagination
                page={@sessions_page}
                total_pages={@sessions_total_pages}
                total_count={@sessions_count}
                page_size={@sessions_page_size}
                on_prev="admin_sessions_prev"
                on_next="admin_sessions_next"
                on_page_size="admin_sessions_page_size"
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    page = 1
    page_size = 50

    sessions_count = Repo.aggregate(from(t in UserToken, where: t.context == "session"), :count)

    recent_sessions =
      Repo.all(
        from t in UserToken,
          join: u in assoc(t, :user),
          where: t.context == "session",
          order_by: [desc: t.inserted_at],
          offset: ^((page - 1) * page_size),
          limit: ^page_size,
          preload: [:user]
      )

    total_pages = if page_size > 0, do: div(sessions_count + page_size - 1, page_size), else: 0

    {:ok,
     socket
     |> assign(:sessions_count, sessions_count)
     |> assign(:recent_sessions, recent_sessions)
     |> assign(:sessions_page, page)
     |> assign(:sessions_page_size, page_size)
     |> assign(:sessions_total_pages, total_pages)
     |> assign(:selected_ids, MapSet.new())}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns[:selected_ids] || MapSet.new()

    selected =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    {:noreply,
     socket
     |> assign(:selected_ids, selected)
     |> sync_selected_ids(session_ids(socket.assigns.recent_sessions))}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    sessions = socket.assigns.recent_sessions || []
    ids = session_ids(sessions)
    selected = socket.assigns[:selected_ids] || MapSet.new()

    selected =
      if ids != [] and MapSet.size(selected) == length(ids) do
        MapSet.new()
      else
        MapSet.new(ids)
      end

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("bulk_delete", _params, socket) do
    ids = socket.assigns[:selected_ids] || MapSet.new()
    ids = MapSet.to_list(ids)

    {deleted, failed} =
      Enum.reduce(ids, {0, 0}, fn id, {d, f} ->
        session = Accounts.get_user_token!(id)

        case Accounts.delete_user_token(session) do
          {:ok, _} -> {d + 1, f}
          {:error, _} -> {d, f + 1}
        end
      end)

    socket = assign(socket, :selected_ids, MapSet.new())

    socket =
      cond do
        failed == 0 ->
          put_flash(socket, :info, "Deleted #{deleted} sessions")

        deleted == 0 ->
          put_flash(socket, :error, "Failed to delete selected sessions")

        true ->
          put_flash(
            socket,
            :error,
            "Deleted #{deleted} sessions; failed #{failed}"
          )
      end

    {:noreply, reload_sessions(socket)}
  end

  @impl true
  def handle_event("delete_session", %{"id" => id}, socket) do
    session = Accounts.get_user_token!(id)

    case Accounts.delete_user_token(session) do
      {:ok, _session} ->
        page = socket.assigns[:sessions_page] || 1
        page_size = socket.assigns[:sessions_page_size] || 50

        sessions_count =
          Repo.aggregate(from(t in UserToken, where: t.context == "session"), :count)

        total_pages =
          if page_size > 0, do: div(sessions_count + page_size - 1, page_size), else: 0

        page = max(1, min(page, total_pages))

        recent_sessions =
          Repo.all(
            from t in UserToken,
              join: u in assoc(t, :user),
              where: t.context == "session",
              order_by: [desc: t.inserted_at],
              offset: ^((page - 1) * page_size),
              limit: ^page_size,
              preload: [:user]
          )

        {:noreply,
         socket
         |> put_flash(:info, "Token deleted successfully")
         |> assign(:sessions_count, sessions_count)
         |> assign(:recent_sessions, recent_sessions)
         |> assign(:sessions_page, page)
         |> assign(:sessions_total_pages, total_pages)
         |> sync_selected_ids(session_ids(recent_sessions))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete token")}
    end
  end

  @impl true
  def handle_event("admin_sessions_prev", _params, socket) do
    {:noreply,
     socket
     |> assign(:sessions_page, max(1, (socket.assigns[:sessions_page] || 1) - 1))
     |> reload_sessions()}
  end

  def handle_event("admin_sessions_next", _params, socket) do
    {:noreply,
     socket
     |> assign(:sessions_page, (socket.assigns[:sessions_page] || 1) + 1)
     |> reload_sessions()}
  end

  def handle_event("admin_sessions_page_size", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:sessions_page_size, String.to_integer(size))
     |> assign(:sessions_page, 1)
     |> reload_sessions()}
  end

  defp reload_sessions(socket) do
    page = socket.assigns[:sessions_page] || 1
    page_size = socket.assigns[:sessions_page_size] || 50

    sessions_count = Repo.aggregate(from(t in UserToken, where: t.context == "session"), :count)

    total_pages =
      if page_size > 0,
        do: div(sessions_count + page_size - 1, page_size),
        else: 0

    page = max(1, min(page, total_pages))

    recent_sessions =
      Repo.all(
        from t in UserToken,
          join: u in assoc(t, :user),
          where: t.context == "session",
          order_by: [desc: t.inserted_at],
          offset: ^((page - 1) * page_size),
          limit: ^page_size,
          preload: [:user]
      )

    socket
    |> assign(:sessions_count, sessions_count)
    |> assign(:recent_sessions, recent_sessions)
    |> assign(:sessions_page, page)
    |> assign(:sessions_total_pages, total_pages)
    |> sync_selected_ids(session_ids(recent_sessions))
  end

  defp session_ids(sessions) when is_list(sessions), do: Enum.map(sessions, & &1.id)

  defp sync_selected_ids(socket, ids) when is_list(ids) do
    selected = socket.assigns[:selected_ids] || MapSet.new()
    allowed = MapSet.new(ids)
    assign(socket, :selected_ids, MapSet.intersection(selected, allowed))
  end
end
