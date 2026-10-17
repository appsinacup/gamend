defmodule GamendWeb.AdminLive.AnalyticsPeople do
  @moduledoc """
  Analytics → People: one account's activity. Find it by id, email,
  username or name (the admin search, `Gamend.Accounts.list_all_users/2`),
  then read its kind (registered or guest), when it was made and last seen,
  the days it was active (a strip of the last 13 weeks), its events by name
  (each opening Explore on that account) and one by one, and its coin
  ledger. `?user=<id>` is the account, `?event=` narrows its events.
  """
  use GamendWeb, :live_view

  import GamendWeb.AdminLive.AnalyticsComponents

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Analytics
  alias Gamend.Analytics.Catalog
  alias Gamend.Analytics.Explore
  alias Gamend.Economy

  @weeks 13
  @page_size 50
  @ledger_rows 25
  @search_rows 10
  # Every row an account can have: events are pruned after a year.
  @events_days 400

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Admin · Analytics · People")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    q = String.trim(params["q"] || "")
    user = params["user"] |> uuid() |> then(&(&1 && Accounts.get_user(&1)))

    {:noreply,
     socket
     |> assign(:q, q)
     |> assign(:results, search(q))
     |> assign(:user, user)
     |> assign(:event, blank(params["event"]))
     |> assign(:page, max(int_param(params, "page", Enum.to_list(1..10_000), 1), 1))
     |> load()}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: here(%{"q" => String.trim(q)}))}
  end

  defp search(""), do: []
  defp search(q), do: Accounts.list_all_users(%{search: q}, page: 1, page_size: @search_rows)

  defp load(%{assigns: %{user: nil}} = socket), do: socket

  defp load(%{assigns: %{user: user}} = socket) do
    _ = Analytics.flush()
    today = Date.utc_today()
    first = today |> Date.add(-(@weeks * 7 - 1)) |> Date.beginning_of_week()

    filter =
      Explore.filter(
        names: if(socket.assigns.event, do: [socket.assigns.event], else: :all),
        days: @events_days,
        to: today,
        user_id: user.id
      )

    socket
    |> assign(:person, Explore.person(user.id, today))
    |> assign(:weeks, weeks(first, today, Explore.active_days(user.id, first, today)))
    |> assign(:rows, Explore.rows(filter, page: socket.assigns.page, page_size: @page_size))
    |> assign(:ledger, Economy.list_ledger(user_id: user.id, page: 1, page_size: @ledger_rows))
    |> assign(:labels, Map.new(Catalog.events(), &{&1.name, &1.label}))
  end

  # The strip: one column per week (Monday first), one cell per day,
  # `{date, active?}`, nil past today.
  defp weeks(first, today, active) do
    first
    |> Stream.iterate(&Date.add(&1, 7))
    |> Enum.take_while(&(Date.compare(&1, today) != :gt))
    |> Enum.map(fn monday ->
      for d <- 0..6 do
        day = Date.add(monday, d)
        if Date.compare(day, today) != :gt, do: {day, MapSet.member?(active, day)}
      end
    end)
  end

  defp here(params), do: link_to("/admin/analytics/people", params, %{"page" => "1"})

  defp uuid(nil), do: nil

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(value), do: value

  defp explore(user_id, name),
    do: link_to("/admin/analytics/explore", %{"event" => name, "user" => user_id, "days" => 90})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <.analytics_header
          tab="people"
          note="One account at a time: what it is, the days it was seen, what it did."
        />

        <.panel>
          <form id="people-search" phx-change="search" phx-submit="search">
            <.search_input
              label="Find an account: id, email, username or name"
              name="q"
              value={@q}
              phx-debounce="300"
              class="max-w-xl"
            />
          </form>
          <ul :if={@results != []} class="mt-3 divide-y divide-base-300" id="people-results">
            <li :for={u <- @results} class="flex flex-wrap items-center gap-3 py-2">
              <.link patch={here(%{"user" => u.id, "q" => @q})} class="link link-hover font-semibold">
                {name(u)}
              </.link>
              <span class="badge badge-ghost badge-sm">{kind(u)}</span>
              <span class="font-mono text-xs text-muted">{u.id}</span>
              <span :if={u.email} class="text-xs text-muted">{u.email}</span>
            </li>
          </ul>
          <p :if={@q != "" and @results == []} class="mt-3 text-sm text-muted">No account found.</p>
        </.panel>

        <.empty_state
          :if={is_nil(@user)}
          icon="hero-user-circle"
          title="No account chosen"
          text="Search above, or open one from a row in Explore."
        />

        <%= if @user do %>
          <.panel id="person">
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <div class="flex items-center gap-2">
                  <span class="text-xl font-bold">{name(@user)}</span>
                  <span class="badge badge-ghost">{kind(@user)}</span>
                  <span :if={@user.is_admin} class="badge badge-ghost">admin</span>
                </div>
                <div class="font-mono text-xs text-muted">{@user.id}</div>
                <div :if={@user.email} class="text-sm">{@user.email}</div>
              </div>
              <div class="flex flex-wrap gap-2">
                <.link
                  navigate={~p"/admin/economy?user_id=#{@user.id}"}
                  class="btn btn-surface btn-sm"
                >
                  Wallet &amp; items
                </.link>
                <.link navigate={~p"/admin/kv?user_id=#{@user.id}"} class="btn btn-surface btn-sm">
                  KV data
                </.link>
              </div>
            </div>
          </.panel>

          <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
            <.stat title="Created" value={Calendar.strftime(@user.inserted_at, "%Y-%m-%d")} />
            <.stat
              title="Last seen"
              value={
                if @user.last_seen_at,
                  do: Calendar.strftime(@user.last_seen_at, "%m-%d %H:%M"),
                  else: "—"
              }
              desc={if @user.is_online, do: "online now"}
            />
            <.stat title="Days active" value={num(@person.days_active)} desc="ever" />
            <.stat title="Days active" value={num(@person.days_active_30)} desc="last 30 days" />
            <.stat title="Events" value={num(@person.events)} desc="kept rows" />
            <.stat
              title="First / last day"
              value={day(@person.first_day)}
              desc={"to #{day(@person.last_day)}"}
            />
          </div>

          <.panel title="Days seen, last 13 weeks">
            <div class="flex gap-1 overflow-x-auto pb-1" role="img" aria-label="Days seen">
              <div :for={week <- @weeks} class="flex flex-col gap-1">
                <%= for cell <- week do %>
                  <div :if={is_nil(cell)} class="size-4" />
                  <div
                    :if={cell}
                    class={[
                      "group relative size-4 rounded-sm",
                      if(elem(cell, 1), do: "bg-primary/80", else: "bg-base-300")
                    ]}
                  >
                    <span class="pointer-events-none absolute bottom-full start-1/2 z-10 mb-1 hidden -translate-x-1/2 whitespace-nowrap rounded bg-base-content px-1.5 py-0.5 text-xs text-base-100 group-hover:block">
                      {Date.to_iso8601(elem(cell, 0))}{if elem(cell, 1), do: " · seen"}
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
            <p class="mt-1 text-xs text-muted">Columns are weeks, Monday on top. UTC days.</p>
          </.panel>

          <div class="grid gap-4 xl:grid-cols-3">
            <.panel title="Events by name" class="xl:col-span-1">
              <table class="table table-sm" id="person-by-name">
                <tbody>
                  <tr :for={row <- @person.by_name}>
                    <td>
                      <.link navigate={explore(@user.id, row.name)} class="link link-hover">
                        {Map.get(@labels, row.name, row.name)}
                      </.link>
                    </td>
                    <td class="text-right tabular-nums">{num(row.events)}</td>
                    <td class="whitespace-nowrap text-right text-xs text-muted">
                      {Calendar.strftime(row.last_at, "%m-%d %H:%M")}
                    </td>
                  </tr>
                  <tr :if={@person.by_name == []}>
                    <td class="text-muted">No events kept.</td>
                  </tr>
                </tbody>
              </table>
            </.panel>

            <.panel class="xl:col-span-2">
              <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
                <.eyebrow tag="h2">
                  {if @event, do: "Events: #{Map.get(@labels, @event, @event)}", else: "Events"}
                </.eyebrow>
                <div class="flex items-center gap-2 text-xs text-muted">
                  <.link :if={@event} patch={here(%{"user" => @user.id})} class="btn btn-xs">
                    Every event
                  </.link>
                  <span>{num(@rows.total)} rows</span>
                  <.link
                    :if={@page > 1}
                    patch={here(%{"user" => @user.id, "event" => @event, "page" => @page - 1})}
                    class="btn btn-xs"
                  >
                    Newer
                  </.link>
                  <.link
                    :if={@page * 50 < @rows.total}
                    patch={here(%{"user" => @user.id, "event" => @event, "page" => @page + 1})}
                    class="btn btn-xs"
                  >
                    Older
                  </.link>
                </div>
              </div>
              <div class="overflow-x-auto">
                <table class="table table-sm table-zebra" id="person-events">
                  <tbody>
                    <tr :for={e <- @rows.rows}>
                      <td class="whitespace-nowrap font-mono">
                        {Calendar.strftime(e.inserted_at, "%m-%d %H:%M:%S")}
                      </td>
                      <td>
                        <.link
                          patch={here(%{"user" => @user.id, "event" => e.name})}
                          class="link link-hover"
                        >
                          {Map.get(@labels, e.name, e.name)}
                        </.link>
                      </td>
                      <td class="font-mono text-xs">{fields(e.dims)}</td>
                    </tr>
                    <tr :if={@rows.rows == []}>
                      <td class="text-muted">No events kept.</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </.panel>
          </div>

          <.panel title="Coin ledger, newest first">
            <div class="overflow-x-auto">
              <table class="table table-sm table-zebra" id="person-ledger">
                <thead>
                  <tr>
                    <th>When (UTC)</th>
                    <th>Currency</th>
                    <th>Reason</th>
                    <th class="text-right">Change</th>
                    <th class="text-right">Balance</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={l <- @ledger}>
                    <td class="whitespace-nowrap font-mono">
                      {Calendar.strftime(l.inserted_at, "%m-%d %H:%M:%S")}
                    </td>
                    <td class="font-mono">{l.currency}</td>
                    <td class="font-mono">{l.reason}</td>
                    <td class="text-right tabular-nums">{num(l.delta)}</td>
                    <td class="text-right tabular-nums">{num(l.balance_after)}</td>
                  </tr>
                  <tr :if={@ledger == []}>
                    <td colspan="5" class="text-muted">No ledger entries.</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.panel>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp name(%User{} = user),
    do: Accounts.display_label(user)

  defp kind(%User{} = user), do: if(User.anonymous?(user), do: "guest", else: "registered")

  defp day(nil), do: "—"
  defp day(%Date{} = d), do: Date.to_iso8601(d)

  defp fields(dims) when is_map(dims),
    do: dims |> Enum.sort() |> Enum.map_join("  ", fn {k, v} -> "#{k}=#{v}" end)
end
