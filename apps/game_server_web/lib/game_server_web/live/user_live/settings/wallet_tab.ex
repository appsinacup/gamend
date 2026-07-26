defmodule GameServerWeb.UserLive.Settings.WalletTab do
  @moduledoc """
  Wallet tab of the user settings page: the user's virtual-currency balances
  and a paginated ledger of every credit/debit. Read-only — balances are
  server-authoritative (see `GameServer.Economy`).
  """

  use GameServerWeb, :html
  import Phoenix.LiveView, only: [stream: 4]

  alias GameServer.Economy

  @page_size 50

  def assign_defaults(socket) do
    socket
    |> assign(:wallet_balances, [])
    |> assign(:ledger_page, 1)
    |> assign(:ledger_page_size, @page_size)
    |> assign(:ledger_count, 0)
    |> assign(:ledger_total_pages, 0)
    |> load_wallet()
  end

  def tab(assigns) do
    ~H"""
    <div :if={@settings_tab == "wallet"}>
      <div class="card bg-base-200 p-4 rounded-lg mt-6">
        <div class="font-semibold text-lg">{gettext("Wallet")}</div>

        <div class="mt-4">
          <div :if={@wallet_balances == []} class="text-sm text-base-content/50 italic">
            {gettext("No results.")}
          </div>
          <div :if={@wallet_balances != []} class="flex flex-wrap gap-3">
            <div
              :for={{currency, balance} <- @wallet_balances}
              class="rounded-lg bg-base-100 px-4 py-3 min-w-32"
            >
              <div class="text-xs uppercase tracking-wide text-base-content/50">{currency}</div>
              <div class="text-xl font-bold tabular-nums">{balance}</div>
            </div>
          </div>
        </div>
      </div>

      <div class="card bg-base-200 p-4 rounded-lg mt-4">
        <div class="font-semibold text-lg">{gettext("Transactions")}</div>

        <div class="overflow-x-auto mt-4">
          <table id="wallet-ledger-table" class="table table-zebra w-full table-fixed min-w-[40rem]">
            <colgroup>
              <col class="w-44" />
              <col class="w-24" />
              <col class="w-24" />
              <col class="w-28" />
              <col />
            </colgroup>
            <thead>
              <tr>
                <th class="w-44">{gettext("Date")}</th>
                <th>{gettext("Currency")}</th>
                <th class="text-right">{gettext("Change")}</th>
                <th class="text-right">{gettext("Balance")}</th>
                <th>{gettext("Reason")}</th>
              </tr>
            </thead>
            <tbody id="wallet-ledger-rows" phx-update="stream">
              <tr
                :for={{dom_id, e} <- @streams.ledger_entries}
                id={dom_id}
                class="hover"
              >
                <td class="text-xs font-mono"><.timestamp at={e.inserted_at} /></td>
                <td class="text-sm">{e.currency}</td>
                <td class={[
                  "text-right font-mono tabular-nums",
                  if(e.delta >= 0, do: "text-success", else: "text-error")
                ]}>
                  {format_delta(e.delta)}
                </td>
                <td class="text-right font-mono tabular-nums text-sm">{e.balance_after}</td>
                <td class="text-sm break-all">{e.reason}</td>
              </tr>
            </tbody>
          </table>
          <div
            :if={@ledger_count == 0}
            class="text-sm text-base-content/50 italic py-4 text-center"
          >
            {gettext("No results.")}
          </div>
        </div>

        <div class="mt-4">
          <.pagination
            page={@ledger_page}
            total_pages={@ledger_total_pages}
            total_count={@ledger_count}
            on_prev="wallet_ledger_prev"
            on_next="wallet_ledger_next"
          />
        </div>
      </div>
    </div>
    """
  end

  def handle_event("wallet_ledger_prev", _params, socket) do
    page = max(1, (socket.assigns.ledger_page || 1) - 1)
    {:noreply, socket |> assign(:ledger_page, page) |> reload_ledger()}
  end

  def handle_event("wallet_ledger_next", _params, socket) do
    page = (socket.assigns.ledger_page || 1) + 1
    {:noreply, socket |> assign(:ledger_page, page) |> reload_ledger()}
  end

  @doc "Reloads balances and the current ledger page."
  def load_wallet(socket) do
    balances =
      socket.assigns.user.id
      |> Economy.balances()
      |> Enum.sort_by(fn {currency, _balance} -> currency end)

    socket
    |> assign(:wallet_balances, balances)
    |> reload_ledger()
  end

  @doc "Reloads the ledger list for the current page."
  def reload_ledger(socket) do
    page = socket.assigns[:ledger_page] || 1
    page_size = socket.assigns[:ledger_page_size] || @page_size
    user = socket.assigns.user

    filters = [user_id: user.id, page: page, page_size: page_size]
    entries = Economy.list_ledger(filters)
    count = Economy.count_ledger(filters)
    total_pages = if page_size > 0, do: div(count + page_size - 1, page_size), else: 0

    socket
    |> stream(:ledger_entries, entries, reset: true, dom_id: &"wallet-ledger-#{&1.id}")
    |> assign(:ledger_count, count)
    |> assign(:ledger_total_pages, total_pages)
    |> clamp_ledger_page()
  end

  defp clamp_ledger_page(socket) do
    page = socket.assigns.ledger_page
    total_pages = socket.assigns.ledger_total_pages

    page =
      cond do
        total_pages == 0 -> 1
        page < 1 -> 1
        page > total_pages -> total_pages
        true -> page
      end

    assign(socket, :ledger_page, page)
  end

  defp format_delta(delta) when is_integer(delta) and delta >= 0, do: "+#{delta}"
  defp format_delta(delta), do: to_string(delta)
end
