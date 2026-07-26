defmodule GameServerWeb.AdminLive.Matchmaking do
  @moduledoc """
  Admin view over the matchmaking queue: live stats, per-queue depths, and a
  paginated, filterable ticket list with force-cancel.
  """
  use GameServerWeb, :live_view

  alias GameServer.Matchmaking
  alias GameServer.Matchmaking.Worker
  alias GameServer.ReadyChecks

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin · Matchmaking")
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
     |> assign(:status_filter, Map.get(params, "status", "all"))
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

  def handle_event("cancel_ticket", %{"id" => id}, socket) do
    socket =
      case Matchmaking.cancel_ticket(id) do
        {:ok, _} -> put_flash(socket, :info, "Ticket cancelled")
        {:error, :not_found} -> put_flash(socket, :error, "Ticket not found or not queued")
      end

    {:noreply, reload(socket)}
  end

  def handle_event("cancel_ready_check", %{"id" => id}, socket) do
    socket =
      with %{status: "pending"} = check <- ReadyChecks.get_check(id),
           {:ok, _} <- ReadyChecks.cancel(check) do
        put_flash(socket, :info, "Ready check cancelled")
      else
        _ -> put_flash(socket, :error, "Ready check not found or already resolved")
      end

    {:noreply, reload(socket)}
  end

  def handle_event("sweep_now", _params, socket) do
    created = Worker.sweep()
    {:noreply, socket |> put_flash(:info, "Sweep done: #{created} match(es) formed") |> reload()}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, reload(socket)}
  end

  # ── data ──────────────────────────────────────────────────────────────────

  defp reload(socket) do
    filters = [
      status: status_filter(socket.assigns.status_filter),
      user_id: presence(socket.assigns.user_filter),
      page: socket.assigns.page,
      page_size: socket.assigns.page_size
    ]

    tickets = Matchmaking.list_tickets(filters)
    total = Matchmaking.count_tickets(filters)

    socket
    |> assign(:tickets, tickets)
    |> assign(:count, total)
    |> assign(:total_pages, ceil_div(total, socket.assigns.page_size))
    |> assign(:stats, Matchmaking.stats())
    |> assign(:ready_stats, ReadyChecks.stats())
    |> assign(:ready_checks, ReadyChecks.list_checks(page: 1, page_size: 10))
  end

  defp status_filter("all"), do: nil
  defp status_filter(status), do: status

  defp presence(""), do: nil
  defp presence(value), do: value

  defp ceil_div(_num, 0), do: 0
  defp ceil_div(num, den), do: div(num + den - 1, den)

  defp user_label(%{user: %{} = user}), do: user_name(user)
  defp user_label(%{user_id: user_id}), do: user_id

  defp user_name(user) do
    cond do
      is_binary(user.display_name) and user.display_name != "" -> user.display_name
      is_binary(user.username) and user.username != "" -> user.username
      is_binary(user.email) and user.email != "" -> user.email
      true -> user.id
    end
  end

  defp status_class("queued"), do: "badge-info"
  defp status_class("matched"), do: "badge-success"
  defp status_class("cancelled"), do: "badge-ghost"
  defp status_class("pending"), do: "badge-info"
  defp status_class("passed"), do: "badge-success"
  defp status_class("failed"), do: "badge-error"
  defp status_class(_status), do: "badge-ghost"

  defp ready_counts(check) do
    ready = Enum.count(check.participants, &(&1.state == "ready"))
    "#{ready}/#{length(check.participants)}"
  end

  # Nobody answered vs. someone said no vs. the clock ran out — the three are
  # different problems, so the admin sees the reason rather than just "failed".
  defp check_reason(%{reason: reason}) when is_binary(reason) and reason != "", do: reason
  defp check_reason(_check), do: "—"

  defp params_label(params) when params == %{}, do: "—"

  defp params_label(params) do
    Enum.map_join(params, ", ", fn {k, v} -> "#{k}=#{v}" end)
  end

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-outline mb-4">← Back to Admin</.link>

      <div class="grid gap-4 sm:grid-cols-3 mb-6">
        <div class="card bg-base-200">
          <div class="card-body py-4">
            <span class="text-sm text-base-content/70">Queued</span>
            <div class="text-2xl font-bold">{@stats.queued}</div>
          </div>
        </div>
        <div class="card bg-base-200">
          <div class="card-body py-4">
            <span class="text-sm text-base-content/70">Matched (total)</span>
            <div class="text-2xl font-bold">{@stats.matched}</div>
          </div>
        </div>
        <div class="card bg-base-200">
          <div class="card-body py-4">
            <span class="text-sm text-base-content/70">Cancelled (total)</span>
            <div class="text-2xl font-bold">{@stats.cancelled}</div>
          </div>
        </div>
      </div>

      <div :if={@stats.queues != []} class="card bg-base-200 mb-6">
        <div class="card-body">
          <h2 class="card-title">Active queues</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Match params</th>
                  <th class="text-right">Waiting</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={queue <- @stats.queues}>
                  <td class="font-mono text-xs">{params_label(queue.params)}</td>
                  <td class="text-right font-mono">{queue.waiting}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div class="card bg-base-200 mb-6">
        <div class="card-body">
          <h2 class="card-title">
            {gettext("Ready checks")}
            <span class="text-sm font-normal text-base-content/70">{gettext("last 24h")}</span>
          </h2>
          <div class="flex flex-wrap gap-4 text-sm">
            <span>{gettext("Passed")}: <b>{Map.get(@ready_stats, "passed", 0)}</b></span>
            <span>{gettext("Failed")}: <b>{Map.get(@ready_stats, "failed", 0)}</b></span>
            <span>{gettext("Cancelled")}: <b>{Map.get(@ready_stats, "cancelled", 0)}</b></span>
            <span>{gettext("Pending")}: <b>{Map.get(@ready_stats, "pending", 0)}</b></span>
          </div>

          <div :if={@ready_checks != []} class="overflow-x-auto mt-2">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Kind")}</th>
                  <th>{gettext("Status")}</th>
                  <th>{gettext("Reason")}</th>
                  <th class="text-right">{gettext("Ready")}</th>
                  <th>{gettext("Created")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={check <- @ready_checks}>
                  <td class="font-mono text-xs">{check.kind}</td>
                  <td><span class={"badge #{status_class(check.status)}"}>{check.status}</span></td>
                  <td class="font-mono text-xs">{check_reason(check)}</td>
                  <td class="text-right font-mono">{ready_counts(check)}</td>
                  <td class="text-xs">{check.inserted_at}</td>
                  <td class="text-right">
                    <button
                      :if={check.status == "pending"}
                      phx-click="cancel_ready_check"
                      phx-value-id={check.id}
                      class="btn btn-ghost btn-xs"
                    >
                      {gettext("Cancel")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">Tickets ({@count})</h2>
            <div class="flex gap-2">
              <button phx-click="sweep_now" class="btn btn-outline btn-sm" id="sweep-now-btn">
                Run sweep now
              </button>
              <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
            </div>
          </div>

          <form phx-change="filter" id="matchmaking-filter-form" class="flex flex-wrap gap-2 my-2">
            <select name="status" class="select select-sm w-40">
              <option value="all" selected={@status_filter == "all"}>All statuses</option>
              <option value="queued" selected={@status_filter == "queued"}>Queued</option>
              <option value="matched" selected={@status_filter == "matched"}>Matched</option>
              <option value="cancelled" selected={@status_filter == "cancelled"}>Cancelled</option>
            </select>
            <input
              type="text"
              name="user_id"
              value={@user_filter}
              placeholder="Filter by user id"
              phx-debounce="300"
              class="input input-sm w-72 font-mono"
            />
          </form>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>User</th>
                  <th>Status</th>
                  <th>Params</th>
                  <th class="text-right">Min/Max</th>
                  <th>Queued at</th>
                  <th>Lobby</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={ticket <- @tickets} id={"ticket-#{ticket.id}"}>
                  <td>{user_label(ticket)}</td>
                  <td>
                    <span class={["badge badge-sm", status_class(ticket.status)]}>
                      {ticket.status}
                    </span>
                  </td>
                  <td class="font-mono text-xs">{params_label(ticket.match_params)}</td>
                  <td class="text-right font-mono">{ticket.min_players}/{ticket.max_players}</td>
                  <td class="text-xs"><.timestamp at={ticket.queued_at} format="full" /></td>
                  <td class="font-mono text-xs">
                    <%= if ticket.match_id do %>
                      <.link navigate={~p"/admin/lobbies"} class="link link-primary">
                        {String.slice(ticket.match_id, 0, 8)}…
                      </.link>
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class="text-right">
                    <button
                      :if={ticket.status == "queued"}
                      phx-click="cancel_ticket"
                      phx-value-id={ticket.id}
                      class="btn btn-outline btn-error btn-xs"
                    >
                      Cancel
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@tickets == []} class="text-center py-8 text-base-content/60">
            No tickets.
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
