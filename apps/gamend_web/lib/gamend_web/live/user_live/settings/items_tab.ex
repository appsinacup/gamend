defmodule GamendWeb.UserLive.Settings.ItemsTab do
  @moduledoc """
  Items tab of the user settings page: the user's inventory item stacks with
  quantities and per-stack metadata, paginated. Read-only — inventory is
  server-authoritative (see `Gamend.Inventory`).
  """

  use GamendWeb, :html
  import Phoenix.LiveView, only: [stream: 4]

  alias Gamend.Inventory
  alias GamendWeb.LiveHelpers

  @page_size 50

  def assign_defaults(socket) do
    socket
    |> assign(:items_page, 1)
    |> assign(:items_page_size, @page_size)
    |> assign(:items_count, 0)
    |> assign(:items_total_pages, 0)
  end

  def tab(assigns) do
    ~H"""
    <div :if={@settings_tab == "items"}>
      <div class="card bg-base-200 p-4 rounded-lg mt-6">
        <div class="font-semibold text-lg">{gettext("Items")}</div>

        <div class="overflow-x-auto mt-4">
          <table id="inventory-items-table" class="table table-zebra w-full table-fixed min-w-[40rem]">
            <colgroup>
              <col class="w-[40%]" />
              <col class="w-28" />
              <col />
            </colgroup>
            <thead>
              <tr>
                <th class="font-mono text-sm break-all">{gettext("Item")}</th>
                <th class="text-end">{gettext("Quantity")}</th>
                <th>{gettext("Metadata")}</th>
              </tr>
            </thead>
            <tbody id="inventory-items-rows" phx-update="stream">
              <tr :for={{dom_id, i} <- @streams.inventory_items} id={dom_id} class="hover">
                <td class="font-mono text-sm break-all">{i.item}</td>
                <td class="text-end font-mono tabular-nums">{i.quantity}</td>
                <td class="text-sm">
                  <pre class="text-xs font-mono whitespace-pre-wrap max-h-24 overflow-auto bg-base-100/60 rounded p-2">{json_preview(i.metadata)}</pre>
                </td>
              </tr>
            </tbody>
          </table>
          <div
            :if={@items_count == 0}
            class="text-sm text-muted italic py-4 text-center"
          >
            {gettext("No results.")}
          </div>
        </div>

        <div class="mt-4">
          <.pagination
            page={@items_page}
            total_pages={@items_total_pages}
            total_count={@items_count}
            on_prev="items_prev"
            on_next="items_next"
          />
        </div>
      </div>
    </div>
    """
  end

  def handle_event("items_prev", _params, socket) do
    page = max(1, (socket.assigns.items_page || 1) - 1)
    {:noreply, socket |> assign(:items_page, page) |> reload_items()}
  end

  def handle_event("items_next", _params, socket) do
    page = (socket.assigns.items_page || 1) + 1
    {:noreply, socket |> assign(:items_page, page) |> reload_items()}
  end

  @doc "Reloads the inventory item list for the current page."
  def reload_items(socket) do
    page = socket.assigns[:items_page] || 1
    page_size = socket.assigns[:items_page_size] || @page_size
    user = socket.assigns.user

    filters = [user_id: user.id, page: page, page_size: page_size]
    items = Inventory.list_items(filters)
    count = Inventory.count_items(filters)
    total_pages = LiveHelpers.total_pages(count, page_size)

    socket
    |> stream(:inventory_items, items, reset: true, dom_id: &"inv-item-#{&1.id}")
    |> assign(:items_count, count)
    |> assign(:items_total_pages, total_pages)
    |> clamp_items_page()
  end

  defp clamp_items_page(socket) do
    page = socket.assigns.items_page
    total_pages = socket.assigns.items_total_pages

    page =
      cond do
        total_pages == 0 -> 1
        page < 1 -> 1
        page > total_pages -> total_pages
        true -> page
      end

    assign(socket, :items_page, page)
  end

  defp json_preview(nil), do: ""
  defp json_preview(map) when is_map(map), do: Jason.encode!(map) |> String.slice(0, 2048)
  defp json_preview(_), do: ""
end
