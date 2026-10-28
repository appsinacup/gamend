defmodule GamendWeb.AdminLive.Results do
  @moduledoc """
  Results (`Gamend.Results`) at a glance: every play, newest first, filtered
  by kind, status, player and lobby, each with how long it ran and its stats
  by event key; and one play (`/admin/results/:id`) with its rows, its stats
  and its events in order, each at its time into the play.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Results
  alias Gamend.Results.Result
  alias GamendWeb.LiveHelpers

  @filters ~w(kind status user_id lobby_id)
  @events_page 500

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin · Results")
     |> assign(:page, 1)
     |> assign(:page_size, 25)
     |> assign(:filters, Map.new(@filters, &{&1, ""}))
     |> assign(:kinds, Results.kinds())
     |> assign(:result, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Gamend.UUIDv7.cast_or_nil(id) && Results.get(id) do
      %Result{} = result -> {:noreply, load_result(socket, result)}
      _ -> {:noreply, socket |> put_flash(:error, gettext("Result not found")) |> load_list()}
    end
  end

  def handle_params(params, _uri, socket) do
    filters =
      Enum.reduce(@filters, socket.assigns.filters, fn key, acc ->
        case params[key] do
          value when is_binary(value) -> Map.put(acc, key, String.trim(value))
          _ -> acc
        end
      end)

    {:noreply, socket |> assign(:filters, filters) |> assign(:page, 1) |> load_list()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.merge(socket.assigns.filters, Map.take(params, @filters))
    {:noreply, push_patch(socket, to: ~p"/admin/results?#{query(filters)}")}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> load_list()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> load_list()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> load_list()}

  def handle_event("refresh", _params, %{assigns: %{result: %Result{} = result}} = socket),
    do: {:noreply, load_result(socket, Results.get(result.id) || result)}

  def handle_event("refresh", _params, socket), do: {:noreply, load_list(socket)}

  def handle_event("more_events", _params, %{assigns: %{result: %Result{} = result}} = socket) do
    last = List.last(socket.assigns.events)
    more = Results.events(result.id, after: last && last.id, limit: @events_page)

    {:noreply,
     socket |> update(:events, &(&1 ++ more)) |> assign(:more?, length(more) == @events_page)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    socket =
      with %Result{} = result <- Results.get(id),
           {:ok, _result} <- Results.delete(result) do
        put_flash(socket, :info, gettext("Result deleted"))
      else
        _ -> put_flash(socket, :error, gettext("Could not delete the result"))
      end

    {:noreply, push_navigate(socket, to: ~p"/admin/results")}
  end

  # ── data ─────────────────────────────────────────────────────────────────

  defp load_list(socket) do
    filters = active(socket.assigns.filters)

    results =
      Results.list(filters, page: socket.assigns.page, page_size: socket.assigns.page_size)

    total = Results.count(filters)
    ids = Enum.map(results, & &1.id)

    socket
    |> assign(:result, nil)
    |> assign(:results, results)
    |> assign(:stats, Results.stats(ids))
    |> assign(:players, players(results))
    |> assign(:count, total)
    |> assign(:by_status, %{
      "open" => Results.count(Map.put(filters, "status", "open")),
      "ended" => Results.count(Map.put(filters, "status", "ended"))
    })
    |> assign(:total_pages, LiveHelpers.total_pages(total, socket.assigns.page_size))
  end

  defp load_result(socket, %Result{} = result) do
    events = Results.events(result.id, limit: @events_page)

    socket
    |> assign(:page_title, "Admin · Result")
    |> assign(:result, result)
    |> assign(:result_stats, Results.stats(result))
    |> assign(:event_count, Results.count_events(result.id))
    |> assign(:events, events)
    |> assign(:more?, length(events) == @events_page)
    |> assign(:players, players([result]))
  end

  defp active(filters),
    do: filters |> Enum.reject(fn {_key, value} -> value in [nil, ""] end) |> Map.new()

  defp query(filters), do: filters |> active() |> Enum.sort()

  defp players(results) do
    results
    |> Enum.map(& &1.user_id)
    |> Enum.uniq()
    |> Map.new(fn id -> {id, Accounts.get_user(id)} end)
  end

  defp player_label(players, user_id) do
    case players[user_id] do
      %Accounts.User{} = user -> user_display(user)
      _ -> user_id
    end
  end

  # How long a play ran: to its end, or so far.
  defp duration(%Result{started_at: started, ended_at: ended}) do
    (ended || DateTime.utc_now()) |> DateTime.diff(started, :millisecond) |> format_ms()
  end

  defp format_ms(ms) when ms < 1_000, do: "#{ms} ms"
  defp format_ms(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)} s"
  defp format_ms(ms) when ms < 3_600_000, do: "#{div(ms, 60_000)} min #{rem(div(ms, 1000), 60)} s"
  defp format_ms(ms), do: "#{div(ms, 3_600_000)} h #{rem(div(ms, 60_000), 60)} min"

  defp event_total(stats), do: stats |> Map.values() |> Enum.map(& &1.count) |> Enum.sum()

  defp number(value) when is_float(value) do
    if value == Float.round(value), do: value |> trunc() |> Integer.to_string(), else: "#{value}"
  end

  defp number(nil), do: ""
  defp number(value), do: to_string(value)

  defp status_class("open"), do: "badge-warning"
  defp status_class(_status), do: "badge-ghost"

  defp short(id), do: String.slice(id, -8, 8)

  # ── render ───────────────────────────────────────────────────────────────

  @impl true
  def render(%{result: %Result{}} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin/results"} class="btn btn-surface mb-4">
        ← {gettext("Results")}
      </.link>

      <div class="card bg-base-200">
        <div class="card-body space-y-4">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">
              <span class="badge badge-neutral">{@result.kind}</span>
              <span class="font-mono text-sm">{@result.id}</span>
            </h2>
            <div class="flex gap-2">
              <button phx-click="refresh" class="btn btn-ghost btn-sm">{gettext("Refresh")}</button>
              <button
                phx-click="delete"
                phx-value-id={@result.id}
                data-confirm={gettext("Delete this result and its events?")}
                class="btn btn-outline btn-error btn-sm"
              >
                {gettext("Delete")}
              </button>
            </div>
          </div>

          <dl id="result-fields" class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
            <dt class="text-muted">{gettext("Player")}</dt>
            <dd>
              <.link navigate={~p"/admin/results?#{[user_id: @result.user_id]}"} class="link">
                {player_label(@players, @result.user_id)}
              </.link>
            </dd>
            <dt class="text-muted">{gettext("Status")}</dt>
            <dd>
              <span class={["badge badge-sm", status_class(@result.status)]}>{@result.status}</span>
            </dd>
            <dt class="text-muted">{gettext("Visibility")}</dt>
            <dd class="font-mono">{@result.visibility}</dd>
            <dt class="text-muted">{gettext("Lobby")}</dt>
            <dd>
              <.link
                :if={@result.lobby_id}
                navigate={~p"/admin/results?#{[lobby_id: @result.lobby_id]}"}
                class="link font-mono"
              >
                {@result.lobby_id}
              </.link>
              <span :if={is_nil(@result.lobby_id)} class="text-muted">—</span>
            </dd>
            <dt class="text-muted">{gettext("Started")}</dt>
            <dd><.timestamp at={@result.started_at} format="full" /></dd>
            <dt class="text-muted">{gettext("Ended")}</dt>
            <dd>
              <.timestamp :if={@result.ended_at} at={@result.ended_at} format="full" />
              <span :if={is_nil(@result.ended_at)} class="text-muted">—</span>
            </dd>
            <dt class="text-muted">{gettext("Duration")}</dt>
            <dd>{duration(@result)}</dd>
            <dt class="text-muted">{gettext("Events")}</dt>
            <dd>{@event_count}</dd>
          </dl>

          <div :if={@result.metadata != %{}}>
            <h3 class="text-sm font-semibold">{gettext("Metadata")}</h3>
            <pre class="mt-1 overflow-x-auto rounded-box bg-base-100 p-3 text-xs">{Jason.encode!(@result.metadata, pretty: true)}</pre>
          </div>

          <div>
            <h3 class="text-sm font-semibold">{gettext("At a glance")}</h3>
            <div :if={@result_stats == %{}} class="text-sm text-muted">{gettext("No events.")}</div>
            <table :if={@result_stats != %{}} id="result-stats" class="table table-sm mt-1">
              <thead>
                <tr>
                  <th>{gettext("Key")}</th>
                  <th class="text-right">{gettext("Count")}</th>
                  <th class="text-right">{gettext("Sum")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{key, stat} <- Enum.sort(@result_stats)}>
                  <td class="font-mono">{key}</td>
                  <td class="text-right">{stat.count}</td>
                  <td class="text-right">{number(stat.sum)}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div>
            <h3 class="text-sm font-semibold">{gettext("Events")}</h3>
            <div :if={@events == []} class="text-sm text-muted">{gettext("No events.")}</div>
            <table :if={@events != []} id="result-events" class="table table-sm mt-1">
              <thead>
                <tr>
                  <th>#</th>
                  <th>{gettext("Time")}</th>
                  <th>{gettext("Key")}</th>
                  <th class="text-right">{gettext("Value")}</th>
                  <th>{gettext("Metadata")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{event, n} <- Enum.with_index(@events, 1)} id={"event-#{event.id}"}>
                  <td class="text-muted">{n}</td>
                  <td class="font-mono whitespace-nowrap">{format_ms(event.elapsed_ms)}</td>
                  <td class="font-mono">{event.key}</td>
                  <td class="text-right">{number(event.value)}</td>
                  <td
                    class="max-w-md truncate font-mono text-xs"
                    title={Jason.encode!(event.metadata)}
                  >
                    {if event.metadata == %{}, do: "", else: Jason.encode!(event.metadata)}
                  </td>
                </tr>
              </tbody>
            </table>
            <button :if={@more?} phx-click="more_events" class="btn btn-surface btn-sm mt-2">
              {gettext("More events")}
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-surface mb-4">
        ← {gettext("Back to Admin")}
      </.link>

      <div class="card bg-base-200">
        <div class="card-body space-y-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">{gettext("Results")} ({@count})</h2>
            <button phx-click="refresh" class="btn btn-ghost btn-sm">{gettext("Refresh")}</button>
          </div>

          <p class="text-sm text-muted">
            {gettext(
              "What happened in each play, written by the game as it happens. Open: %{open}, ended: %{ended}.",
              open: @by_status["open"],
              ended: @by_status["ended"]
            )}
          </p>

          <form
            phx-change="filter"
            phx-submit="filter"
            phx-no-unused-field
            id="results-filter-form"
            class="flex flex-wrap gap-2"
          >
            <select name="kind" class="select select-sm">
              <option value="">{gettext("Any kind")}</option>
              <option :for={kind <- @kinds} value={kind} selected={@filters["kind"] == kind}>
                {kind}
              </option>
            </select>
            <select name="status" class="select select-sm">
              <option value="">{gettext("Any status")}</option>
              <option
                :for={status <- Result.statuses()}
                value={status}
                selected={@filters["status"] == status}
              >
                {status}
              </option>
            </select>
            <input
              type="text"
              name="user_id"
              value={@filters["user_id"]}
              placeholder={gettext("Player id")}
              phx-debounce="400"
              class="input input-sm w-72 font-mono"
            />
            <input
              type="text"
              name="lobby_id"
              value={@filters["lobby_id"]}
              placeholder={gettext("Lobby id")}
              phx-debounce="400"
              class="input input-sm w-72 font-mono"
            />
          </form>

          <div :if={@results == []} class="py-8 text-center text-muted">
            {gettext("No results.")}
          </div>

          <div :if={@results != []} class="overflow-x-auto">
            <table id="results-table" class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Kind")}</th>
                  <th>{gettext("Player")}</th>
                  <th>{gettext("Status")}</th>
                  <th>{gettext("Started")}</th>
                  <th>{gettext("Duration")}</th>
                  <th class="text-right">{gettext("Events")}</th>
                  <th>{gettext("At a glance")}</th>
                  <th>{gettext("Lobby")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={result <- @results} id={"result-#{result.id}"} class={clickable_row()}>
                  <td>
                    <.row_link navigate={~p"/admin/results/#{result.id}"} class="link font-mono">
                      {result.kind}
                    </.row_link>
                  </td>
                  <td>
                    <.link
                      navigate={~p"/admin/results?#{[user_id: result.user_id]}"}
                      class={["link", row_control()]}
                    >
                      {player_label(@players, result.user_id)}
                    </.link>
                  </td>
                  <td>
                    <span class={["badge badge-sm", status_class(result.status)]}>{result.status}</span>
                  </td>
                  <td class="whitespace-nowrap">
                    <.timestamp at={result.started_at} format="full" />
                  </td>
                  <td class="whitespace-nowrap">{duration(result)}</td>
                  <td class="text-right">{event_total(@stats[result.id] || %{})}</td>
                  <td class="text-xs">
                    <span
                      :for={{key, stat} <- Enum.sort(@stats[result.id] || %{})}
                      class="mr-2 whitespace-nowrap"
                    >
                      <span class="font-mono">{key}</span>
                      ×{stat.count}<span :if={stat.sum != 0.0}> Σ{number(stat.sum)}</span>
                    </span>
                  </td>
                  <td>
                    <.link
                      :if={result.lobby_id}
                      navigate={~p"/admin/results?#{[lobby_id: result.lobby_id]}"}
                      class={["link font-mono text-xs", row_control()]}
                    >
                      {short(result.lobby_id)}
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
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
