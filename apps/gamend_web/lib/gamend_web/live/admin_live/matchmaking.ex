defmodule GamendWeb.AdminLive.Matchmaking do
  @moduledoc """
  Admin view over the matchmaking queue: live stats, per-queue depths, and a
  paginated, filterable ticket list with force-cancel.
  """
  use GamendWeb, :live_view

  alias Gamend.Matchmaking
  alias Gamend.Matchmaking.Worker
  alias Gamend.ReadyChecks
  alias GamendWeb.AdminLive.Shared
  alias GamendWeb.LiveHelpers

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
     |> Shared.put_filters(params, status_filter: {"status", "all"}, user_filter: "user_id")
     |> reload()}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload()}

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
    filters = Shared.list_opts(socket.assigns, status: :status_filter, user_id: :user_filter)

    tickets = Matchmaking.list_tickets(filters)
    total = Matchmaking.count_tickets(filters)

    socket
    |> assign(:tickets, tickets)
    |> assign(:count, total)
    |> assign(:total_pages, LiveHelpers.total_pages(total, socket.assigns.page_size))
    |> assign(:stats, Matchmaking.stats())
    |> assign(:ready_stats, ReadyChecks.stats())
    |> assign(:ready_checks, ReadyChecks.list_checks(page: 1, page_size: 10))
  end

  defp user_label(%{user: %{} = user}), do: user_name(user)
  defp user_label(%{user_id: user_id}), do: user_id

  # `display_label/1` rather than a local chain: it ends at the username, which
  # every account has, instead of falling through to the email (leaking it into
  # a list that does not otherwise show it) and then the raw id.
  defp user_name(user), do: Gamend.Accounts.display_label(user)

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
      <.link navigate={~p"/admin"} class="btn btn-surface mb-4">← Back to Admin</.link>

      <div class="grid gap-4 sm:grid-cols-3 mb-6">
        <div class="card bg-base-200">
          <div class="card-body py-4">
            <span class="text-sm text-muted">Queued</span>
            <div class="text-2xl font-bold">{@stats.queued}</div>
          </div>
        </div>
        <div class="card bg-base-200">
          <div class="card-body py-4">
            <span class="text-sm text-muted">Matched (total)</span>
            <div class="text-2xl font-bold">{@stats.matched}</div>
          </div>
        </div>
        <div class="card bg-base-200">
          <div class="card-body py-4">
            <span class="text-sm text-muted">Cancelled (total)</span>
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
            <span class="text-sm font-normal text-muted">
              {gettext("counts: last 24h · list: 10 most recent")}
            </span>
          </h2>
          <div class="flex flex-wrap gap-4 text-sm">
            <span>{gettext("Passed")}: <b>{Map.get(@ready_stats, "passed", 0)}</b></span>
            <span>{gettext("Failed")}: <b>{Map.get(@ready_stats, "failed", 0)}</b></span>
            <span>{gettext("Canceled")}: <b>{Map.get(@ready_stats, "cancelled", 0)}</b></span>
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
                  <td class="text-xs"><.timestamp at={check.inserted_at} format="full" /></td>
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
              <button phx-click="sweep_now" class="btn btn-surface btn-sm" id="sweep-now-btn">
                Run sweep now
              </button>
              <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
            </div>
          </div>

          <form
            phx-change="filter"
            phx-no-unused-field
            id="matchmaking-filter-form"
            class="flex flex-wrap gap-2 my-2"
          >
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
              placeholder="User (id or name)"
              phx-debounce="300"
              class="input input-sm w-72"
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
                      <%!-- Not a link: /admin/lobbies takes no id filter, so it
                            only ever opened the whole list. --%>
                      <span title={ticket.match_id}>{String.slice(ticket.match_id, 0, 8)}…</span>
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

          <div :if={@tickets == []} class="text-center py-8 text-muted">
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
