defmodule GameServerWeb.AdminLive.Economy do
  @moduledoc """
  Admin view over the virtual economy: grant/spend against any wallet, and
  browse wallets and the ledger.
  """
  use GameServerWeb, :live_view

  alias GameServer.Economy
  alias GameServer.Inventory

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin · Economy")
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:user_filter, "")
      |> assign(:currency_filter, "")
      |> assign(:form, %{"user_id" => "", "currency" => "", "amount" => "", "reason" => ""})
      |> assign(:item_form, %{"user_id" => "", "item" => "", "quantity" => ""})
      |> reload()

    {:ok, socket}
  end

  # Deep-link from the user admin page: `?user_id=` pre-filters the wallet/ledger/
  # inventory lists to one user and pre-fills the grant/spend forms with them.
  @impl true
  def handle_params(%{"user_id" => user_id}, _uri, socket) when is_binary(user_id) do
    trimmed = String.trim(user_id)

    if trimmed == "" do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:user_filter, trimmed)
       |> assign(:page, 1)
       |> assign(:form, Map.put(socket.assigns.form, "user_id", trimmed))
       |> assign(:item_form, Map.put(socket.assigns.item_form, "user_id", trimmed))
       |> reload()}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:user_filter, String.trim(Map.get(params, "user_id", "")))
     |> assign(:currency_filter, String.trim(Map.get(params, "currency", "")))
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("form_change", params, socket) do
    {:noreply, assign(socket, :form, Map.take(params, ~w(user_id currency amount reason)))}
  end

  def handle_event("item_form_change", params, socket) do
    {:noreply, assign(socket, :item_form, Map.take(params, ~w(user_id item quantity)))}
  end

  def handle_event(op, _params, socket) when op in ~w(grant_item consume_item) do
    f = socket.assigns.item_form

    socket =
      with {qty, ""} <- Integer.parse(String.trim(f["quantity"] || "")),
           true <- qty > 0 and f["user_id"] not in [nil, ""] and f["item"] not in [nil, ""],
           {:ok, quantity} <-
             apply(Inventory, String.to_existing_atom(op), [f["user_id"], f["item"], qty, []]) do
        put_flash(socket, :info, "#{op}: #{f["item"]} → #{quantity}")
      else
        {:error, reason} -> put_flash(socket, :error, "Failed: #{reason}")
        _ -> put_flash(socket, :error, "Enter user_id, item and a positive quantity")
      end

    {:noreply, reload(socket)}
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
     socket |> assign(:page_size, String.to_integer(size)) |> assign(:page, 1) |> reload()}
  end

  def handle_event("refresh", _params, socket), do: {:noreply, reload(socket)}

  def handle_event(op, _params, socket) when op in ~w(grant spend) do
    f = socket.assigns.form

    socket =
      with {amount, ""} <- Integer.parse(String.trim(f["amount"] || "")),
           true <- amount > 0 and f["user_id"] not in [nil, ""] and f["currency"] not in [nil, ""],
           {:ok, balance} <-
             apply(Economy, String.to_existing_atom(op), [
               f["user_id"],
               f["currency"],
               amount,
               [reason: blank(f["reason"]) || "admin_#{op}"]
             ]) do
        put_flash(socket, :info, "#{String.capitalize(op)}: #{f["currency"]} → #{balance}")
      else
        {:error, reason} -> put_flash(socket, :error, "Failed: #{reason}")
        _ -> put_flash(socket, :error, "Enter user_id, currency and a positive amount")
      end

    {:noreply, reload(socket)}
  end

  # ── data ──────────────────────────────────────────────────────────────────

  defp reload(socket) do
    filters = [
      user_id: blank(socket.assigns.user_filter),
      currency: blank(socket.assigns.currency_filter),
      page: socket.assigns.page,
      page_size: socket.assigns.page_size
    ]

    total = Economy.count_wallets(filters)

    socket
    |> assign(:wallets, Economy.list_wallets(filters))
    |> assign(
      :ledger,
      Economy.list_ledger(Keyword.put(filters, :page_size, 20) |> Keyword.put(:page, 1))
    )
    |> assign(
      :items,
      Inventory.list_items(user_id: blank(socket.assigns.user_filter), page: 1, page_size: 20)
    )
    |> assign(:count, total)
    |> assign(:total_pages, ceil_div(total, socket.assigns.page_size))
  end

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(v), do: v

  defp ceil_div(_num, 0), do: 0
  defp ceil_div(num, den), do: div(num + den - 1, den)

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-outline mb-4">← Back to Admin</.link>

      <div class="card bg-base-200 mb-4">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">Economy · grant / spend</h2>
            <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
          </div>
          <form phx-change="form_change" id="economy-form" class="flex flex-wrap items-end gap-2 mt-2">
            <input
              type="text"
              name="user_id"
              value={@form["user_id"]}
              placeholder="user id"
              class="input input-sm input-bordered font-mono w-72"
            />
            <input
              type="text"
              name="currency"
              value={@form["currency"]}
              placeholder="currency (e.g. gold)"
              class="input input-sm input-bordered font-mono w-40"
            />
            <input
              type="number"
              name="amount"
              value={@form["amount"]}
              min="1"
              placeholder="amount"
              class="input input-sm input-bordered w-28"
            />
            <input
              type="text"
              name="reason"
              value={@form["reason"]}
              placeholder="reason (optional)"
              class="input input-sm input-bordered w-48"
            />
            <button type="button" phx-click="grant" class="btn btn-primary btn-sm">Grant</button>
            <button type="button" phx-click="spend" class="btn btn-outline btn-sm">Spend</button>
          </form>
        </div>
      </div>

      <div class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="card-title">Wallets ({@count})</h2>
          <form phx-change="filter" id="economy-filter" class="flex flex-wrap gap-2 mb-2">
            <input
              type="text"
              name="user_id"
              value={@user_filter}
              placeholder="filter user (id or name)"
              phx-debounce="300"
              class="input input-sm font-mono w-72"
            />
            <input
              type="text"
              name="currency"
              value={@currency_filter}
              placeholder="filter currency"
              phx-debounce="300"
              class="input input-sm font-mono w-40"
            />
          </form>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>User</th><th>Currency</th><th class="text-right">Balance</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={w <- @wallets} id={"wallet-#{w.id}"}>
                  <td class="text-xs" title={w.user_id}>{user_display(w.user)}</td>
                  <td class="font-mono text-xs">{w.currency}</td>
                  <td class="text-right font-mono">{w.balance}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div :if={@wallets == []} class="text-center py-6 text-base-content/60">No wallets.</div>
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

      <div class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="card-title">Inventory · grant / consume</h2>
          <form
            phx-change="item_form_change"
            id="inventory-form"
            class="flex flex-wrap items-end gap-2 mt-2"
          >
            <input
              type="text"
              name="user_id"
              value={@item_form["user_id"]}
              placeholder="user id"
              class="input input-sm input-bordered font-mono w-72"
            />
            <input
              type="text"
              name="item"
              value={@item_form["item"]}
              placeholder="item (e.g. health_potion)"
              class="input input-sm input-bordered font-mono w-48"
            />
            <input
              type="number"
              name="quantity"
              value={@item_form["quantity"]}
              min="1"
              placeholder="qty"
              class="input input-sm input-bordered w-24"
            />
            <button type="button" phx-click="grant_item" class="btn btn-primary btn-sm">Grant</button>
            <button type="button" phx-click="consume_item" class="btn btn-outline btn-sm">Consume</button>
          </form>
          <div class="overflow-x-auto mt-3">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>User</th><th>Item</th><th class="text-right">Qty</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={i <- @items} id={"item-#{i.id}"}>
                  <td class="text-xs" title={i.user_id}>{user_display(i.user)}</td>
                  <td class="font-mono text-xs">{i.item}</td>
                  <td class="text-right font-mono">{i.quantity}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div :if={@items == []} class="text-center py-6 text-base-content/60">No items.</div>
        </div>
      </div>

      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title">Recent ledger</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>When</th><th>User</th><th>Currency</th><th class="text-right">Δ</th><th class="text-right">
                    After
                  </th><th>Reason</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={e <- @ledger} id={"ledger-#{e.id}"}>
                  <td class="text-xs whitespace-nowrap">
                    <.timestamp at={e.inserted_at} format="full" />
                  </td>
                  <td class="text-xs" title={e.user_id}>{user_display(e.user)}</td>
                  <td class="font-mono text-xs">{e.currency}</td>
                  <td class={[
                    "text-right font-mono",
                    e.delta < 0 && "text-error",
                    e.delta > 0 && "text-success"
                  ]}>
                    {e.delta}
                  </td>
                  <td class="text-right font-mono">{e.balance_after}</td>
                  <td class="text-xs">{e.reason}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div :if={@ledger == []} class="text-center py-6 text-base-content/60">
            No ledger entries.
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
