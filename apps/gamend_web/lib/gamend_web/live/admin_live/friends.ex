defmodule GamendWeb.AdminLive.Friends do
  @moduledoc """
  Admin view over friendships: every non-block row in the system — pending,
  accepted and rejected — filterable by the user on either side and by status,
  with force-remove (unfriend an accepted pair or cancel a request).
  """
  use GamendWeb, :live_view

  alias Gamend.Friends
  alias GamendWeb.AdminLive.Shared
  alias GamendWeb.LiveHelpers

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin · Friends")
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:status_filter, "all")
      |> assign(:user_filter, "")
      |> reload()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> Shared.put_filters(params, status_filter: {"status", "all"}, user_filter: "user_id")
     |> reload()}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload()}

  def handle_event("remove", %{"id" => id}, socket) do
    socket =
      case Friends.delete_friendship(id) do
        {:ok, :removed} -> put_flash(socket, :info, "Friendship removed")
        {:error, :not_found} -> put_flash(socket, :error, "Friendship not found")
      end

    {:noreply, reload(socket)}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, reload(socket)}
  end

  # ── data ──────────────────────────────────────────────────────────────────

  defp reload(socket) do
    filters = Shared.list_opts(socket.assigns, status: :status_filter, user_id: :user_filter)

    friendships = Friends.list_all_friendships(filters)
    total = Friends.count_all_friendships(filters)

    socket
    |> assign(:friendships, friendships)
    |> assign(:count, total)
    |> assign(:total_pages, LiveHelpers.total_pages(total, socket.assigns.page_size))
  end

  defp user_name(nil), do: "—"

  # `display_label/1` rather than a local chain: it ends at the username, which
  # every account has, instead of falling through to the email (leaking it into
  # a list that does not otherwise show it) and then the raw id.
  defp user_name(user), do: Gamend.Accounts.display_label(user)

  defp status_class("pending"), do: "badge-info"
  defp status_class("accepted"), do: "badge-success"
  defp status_class("rejected"), do: "badge-ghost"
  defp status_class(_status), do: "badge-ghost"

  # `Friends.delete_friendship/1` also deletes an accepted pair's direct
  # messages, which nothing can bring back.
  defp remove_confirm("accepted"),
    do: "Remove this friendship? Their direct-message history is deleted too."

  defp remove_confirm("pending"), do: "Cancel this friend request?"
  defp remove_confirm(_status), do: "Remove this rejected request?"

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-surface mb-4">← Back to Admin</.link>

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">Friendships ({@count})</h2>
            <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
          </div>

          <p class="text-sm text-muted">
            Every friend request and friendship, in any status. Blocks live on the
            <.link navigate={~p"/admin/blacklist"} class="link">Blacklist</.link>
            page.
          </p>

          <form
            phx-change="filter"
            phx-no-unused-field
            id="friends-filter-form"
            class="flex flex-wrap gap-2 my-2"
          >
            <select name="status" class="select select-sm w-40">
              <option value="all" selected={@status_filter == "all"}>All statuses</option>
              <option value="pending" selected={@status_filter == "pending"}>Pending</option>
              <option value="accepted" selected={@status_filter == "accepted"}>Accepted</option>
              <option value="rejected" selected={@status_filter == "rejected"}>Rejected</option>
            </select>
            <input
              type="text"
              name="user_id"
              value={@user_filter}
              placeholder="Filter by user ID (either side)"
              phx-debounce="300"
              class="input input-sm w-80 font-mono"
            />
          </form>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Requester</th>
                  <th>Target</th>
                  <th>Status</th>
                  <th>Requested</th>
                  <th>Updated</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={friendship <- @friendships} id={"friendship-#{friendship.id}"}>
                  <td>
                    {user_name(friendship.requester)}
                    <div class="font-mono text-xs text-muted">
                      {friendship.requester_id}
                    </div>
                  </td>
                  <td>
                    {user_name(friendship.target)}
                    <div class="font-mono text-xs text-muted">{friendship.target_id}</div>
                  </td>
                  <td>
                    <span class={["badge badge-sm", status_class(friendship.status)]}>
                      {friendship.status}
                    </span>
                  </td>
                  <td class="text-xs">
                    <.timestamp at={friendship.inserted_at} format="full" />
                  </td>
                  <td class="text-xs">
                    <.timestamp at={friendship.updated_at} format="full" />
                  </td>
                  <td class="text-right">
                    <button
                      phx-click="remove"
                      phx-value-id={friendship.id}
                      data-confirm={remove_confirm(friendship.status)}
                      class="btn btn-outline btn-error btn-xs"
                    >
                      Remove
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@friendships == []} class="text-center py-8 text-muted">
            No friendships.
          </div>

          <div class="mt-4 flex justify-center">
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
end
