defmodule GameServerWeb.AdminLive.Blacklist do
  @moduledoc """
  Admin view over player blacklists: every block in the system, filterable by
  the user on either side of it, with force-unblock.
  """
  use GameServerWeb, :live_view

  alias GameServer.Friends

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin · Blacklist")
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:user_filter, "")
      |> reload()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:user_filter, String.trim(Map.get(params, "user_id", "")))
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("prev_page", _params, socket) do
    {:noreply, socket |> assign(:page, max(socket.assigns.page - 1, 1)) |> reload()}
  end

  def handle_event("next_page", _params, socket) do
    page = min(socket.assigns.page + 1, max(socket.assigns.total_pages, 1))
    {:noreply, socket |> assign(:page, page) |> reload()}
  end

  def handle_event("page_size", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:page_size, String.to_integer(size))
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("unblock", %{"id" => id}, socket) do
    socket =
      case Friends.delete_block(id) do
        {:ok, :unblocked} -> put_flash(socket, :info, "Block removed")
        {:error, :not_found} -> put_flash(socket, :error, "Block not found")
      end

    {:noreply, reload(socket)}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, reload(socket)}
  end

  # ── data ──────────────────────────────────────────────────────────────────

  defp reload(socket) do
    filters = [
      user_id: presence(socket.assigns.user_filter),
      page: socket.assigns.page,
      page_size: socket.assigns.page_size
    ]

    blocks = Friends.list_all_blocks(filters)
    total = Friends.count_all_blocks(filters)

    socket
    |> assign(:blocks, blocks)
    |> assign(:count, total)
    |> assign(:total_pages, ceil_div(total, socket.assigns.page_size))
  end

  defp presence(""), do: nil
  defp presence(value), do: value

  defp ceil_div(_num, 0), do: 0
  defp ceil_div(num, den), do: div(num + den - 1, den)

  defp user_name(nil), do: "—"

  defp user_name(user) do
    cond do
      is_binary(user.display_name) and user.display_name != "" -> user.display_name
      is_binary(user.username) and user.username != "" -> user.username
      is_binary(user.email) and user.email != "" -> user.email
      true -> user.id
    end
  end

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-outline mb-4">← Back to Admin</.link>

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">Blacklist ({@count})</h2>
            <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
          </div>

          <p class="text-sm text-base-content/70">
            Blocked players are kept out of each other's matches and lobbies, and cannot
            invite or message each other.
          </p>

          <form phx-change="filter" id="blacklist-filter-form" class="flex flex-wrap gap-2 my-2">
            <input
              type="text"
              name="user_id"
              value={@user_filter}
              placeholder="Filter by user id (either side)"
              phx-debounce="300"
              class="input input-sm w-80 font-mono"
            />
          </form>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Blocker</th>
                  <th>Blocked</th>
                  <th>Since</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={block <- @blocks} id={"block-#{block.id}"}>
                  <td>
                    {user_name(block.target)}
                    <div class="font-mono text-xs text-base-content/60">{block.target_id}</div>
                  </td>
                  <td>
                    {user_name(block.requester)}
                    <div class="font-mono text-xs text-base-content/60">{block.requester_id}</div>
                  </td>
                  <td class="text-xs">
                    <.timestamp at={block.inserted_at} format="full" />
                  </td>
                  <td class="text-right">
                    <button
                      phx-click="unblock"
                      phx-value-id={block.id}
                      class="btn btn-outline btn-error btn-xs"
                    >
                      Unblock
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@blocks == []} class="text-center py-8 text-base-content/60">
            No blocks.
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
