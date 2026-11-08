defmodule GamendWeb.AdminLive.Sessions do
  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Accounts.UserToken
  alias Gamend.Repo
  alias GamendWeb.AdminLive.Shared
  alias GamendWeb.LiveHelpers

  import Ecto.Query

  require Gamend.Accounts.TokenContext, as: TokenContext
  require GamendWeb.UrlParam, as: UrlParam

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.admin_header page="/admin/sessions" />

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex items-center justify-between gap-3">
              <h2 class="card-title">Active Sessions ({@sessions_count})</h2>
              <button
                type="button"
                phx-click="bulk_delete"
                data-confirm
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
                    <%!-- `authenticated_at` is set once, at sign-in; nothing
                         bumps it when the session is used. --%>
                    <th>Signed in</th>
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
                    <td class="font-mono text-sm">
                      <div class="flex items-center gap-2">
                        <.user_avatar user={session.user} class="size-6 shrink-0" />
                        {session.user.email}
                      </div>
                    </td>
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
                        <span class="text-gray-500">-</span>
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
                        data-confirm
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

  use GamendWeb.UrlState,
    reload: :reload_sessions,
    keys: [
      sessions_page: [param: UrlParam.page()],
      sessions_page_size: [param: UrlParam.page_size()]
    ]

  @impl true
  def mount(_params, _session, socket) do
    page = 1
    page_size = 50

    sessions_count =
      Repo.aggregate(from(t in UserToken, where: t.context == ^TokenContext.session()), :count)

    recent_sessions =
      Repo.all(
        from t in UserToken,
          join: u in assoc(t, :user),
          where: t.context == ^TokenContext.session(),
          order_by: [desc: t.inserted_at],
          offset: ^((page - 1) * page_size),
          limit: ^page_size,
          preload: [:user]
      )

    total_pages = LiveHelpers.total_pages(sessions_count, page_size)

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
        case Accounts.get_user_token(id) do
          # Expired or signed out since it was ticked: the outcome asked for.
          nil ->
            {d + 1, f}

          session ->
            case Accounts.delete_user_token(session) do
              {:ok, _} -> {d + 1, f}
              {:error, _} -> {d, f + 1}
            end
        end
      end)

    socket = assign(socket, :selected_ids, MapSet.new())

    socket =
      cond do
        failed == 0 ->
          put_flash(
            socket,
            :info,
            ngettext("Deleted %{count} session", "Deleted %{count} sessions", deleted)
          )

        deleted == 0 ->
          put_flash(socket, :error, "Failed to delete selected sessions")

        true ->
          put_flash(
            socket,
            :error,
            ngettext(
              "Deleted %{count} session; %{failed} failed",
              "Deleted %{count} sessions; %{failed} failed",
              deleted,
              failed: failed
            )
          )
      end

    {:noreply, reload_sessions(socket)}
  end

  @impl true
  def handle_event("delete_session", %{"id" => id}, socket) do
    Shared.with_record(socket, Accounts.get_user_token(id), &delete_session(socket, &1))
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

  def handle_event("admin_sessions_page_size", %{"size" => size}, socket),
    do:
      {:noreply,
       socket
       |> LiveHelpers.put_page_size(size, size_key: :sessions_page_size, page_key: :sessions_page)
       |> reload_sessions()}

  defp delete_session(socket, session) do
    case Accounts.delete_user_token(session) do
      {:ok, _session} ->
        page = socket.assigns[:sessions_page] || 1
        page_size = socket.assigns[:sessions_page_size] || 50

        sessions_count =
          Repo.aggregate(
            from(t in UserToken, where: t.context == ^TokenContext.session()),
            :count
          )

        total_pages =
          LiveHelpers.total_pages(sessions_count, page_size)

        page = max(1, min(page, total_pages))

        recent_sessions =
          Repo.all(
            from t in UserToken,
              join: u in assoc(t, :user),
              where: t.context == ^TokenContext.session(),
              order_by: [desc: t.inserted_at],
              offset: ^((page - 1) * page_size),
              limit: ^page_size,
              preload: [:user]
          )

        {:noreply,
         socket
         |> put_flash(:info, "Session deleted successfully")
         |> assign(:sessions_count, sessions_count)
         |> assign(:recent_sessions, recent_sessions)
         |> assign(:sessions_page, page)
         |> assign(:sessions_total_pages, total_pages)
         |> sync_selected_ids(session_ids(recent_sessions))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete session")}
    end
  end

  defp reload_sessions(socket) do
    page = socket.assigns[:sessions_page] || 1
    page_size = socket.assigns[:sessions_page_size] || 50

    sessions_count =
      Repo.aggregate(from(t in UserToken, where: t.context == ^TokenContext.session()), :count)

    total_pages =
      LiveHelpers.total_pages(sessions_count, page_size)

    page = max(1, min(page, total_pages))

    recent_sessions =
      Repo.all(
        from t in UserToken,
          join: u in assoc(t, :user),
          where: t.context == ^TokenContext.session(),
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
