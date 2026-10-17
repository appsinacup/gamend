defmodule GamendWeb.AdminLive.Blacklist do
  @moduledoc """
  Admin view over player blacklists: every block in the system, filterable by
  the user on either side of it, with force-unblock.
  """
  use GamendWeb, :live_view

  alias Gamend.Friends
  alias GamendWeb.AdminLive.Shared
  alias GamendWeb.LiveHelpers

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
     |> Shared.put_filters(params, user_filter: "user_id")
     |> reload()}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload()}

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
    filters = Shared.list_opts(socket.assigns, user_id: :user_filter)

    blocks = Friends.list_all_blocks(filters)
    total = Friends.count_all_blocks(filters)

    socket
    |> assign(:blocks, blocks)
    |> assign(:count, total)
    |> assign(:total_pages, LiveHelpers.total_pages(total, socket.assigns.page_size))
  end

  defp user_name(nil), do: "—"

  # `display_label/1` rather than a local chain: it ends at the username, which
  # every account has, instead of falling through to the email (leaking it into
  # a list that does not otherwise show it) and then the raw id.
  defp user_name(user), do: Gamend.Accounts.display_label(user)

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-surface mb-4">← Back to Admin</.link>

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">Blacklist ({@count})</h2>
            <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
          </div>

          <p class="text-sm text-muted">
            Blocked players are kept out of each other's matches and lobbies, and cannot
            invite or message each other.
          </p>

          <form
            phx-change="filter"
            phx-no-unused-field
            id="blacklist-filter-form"
            class="flex flex-wrap gap-2 my-2"
          >
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
                    <div class="font-mono text-xs text-muted">{block.target_id}</div>
                  </td>
                  <td>
                    {user_name(block.requester)}
                    <div class="font-mono text-xs text-muted">{block.requester_id}</div>
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

          <div :if={@blocks == []} class="text-center py-8 text-muted">
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
