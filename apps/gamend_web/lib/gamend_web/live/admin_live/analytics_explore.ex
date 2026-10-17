defmodule GamendWeb.AdminLive.AnalyticsExplore do
  @moduledoc """
  Analytics → Explore: one event, a group of them or every event, over 7 /
  30 / 90 days, in one segment, narrowed by any of its dimensions (`lang =
  ro`) or to one account. Shows the events and the accounts per day (and the
  counter, visitors included, where one holds the same question), the
  totals and averages of the event's numbers, a breakdown by any dimension,
  and the rows themselves, newest first, a page at a time.

  Everything is in the URL: `?event=web.game.finished&f[lang]=ro&by=game`
  (or `group=games`), `days`, `segment`, `user`, `page`. Reads
  `Gamend.Analytics.Explore`; names, labels and dimensions come from the
  catalogue (`Gamend.Analytics.Catalog`), and an undeclared event offers the
  dimensions its counters were written with.
  """
  use GamendWeb, :live_view

  import GamendWeb.AdminLive.AnalyticsComponents
  import GamendWeb.Charts

  alias Gamend.Accounts.User
  alias Gamend.Analytics
  alias Gamend.Analytics.Catalog
  alias Gamend.Analytics.Explore
  alias Gamend.Analytics.Segment

  @windows [7, 30, 90]
  @page_size 50
  @values_shown 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Admin · Analytics · Explore")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign(:params, read_params(params)) |> load()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  # The filter form: the target, a value per dimension, the breakdown, the
  # account. Any change starts again from page 1.
  def handle_event("filter", form, socket) do
    p = socket.assigns.params

    {event, group} =
      case form["target"] do
        "event:" <> name -> {name, nil}
        "group:" <> id -> {nil, id}
        _ -> {nil, nil}
      end

    target_changed? = {event, group} != {p.event, p.group}

    where =
      if target_changed?,
        do: %{},
        else: form |> Map.get("f", %{}) |> Map.reject(fn {_k, v} -> v in [nil, ""] end)

    params = %{
      p
      | event: event,
        group: group,
        where: where,
        by: if(target_changed?, do: nil, else: blank(form["by"])),
        user: blank(String.trim(form["user"] || "")),
        page: 1
    }

    {:noreply, push_patch(socket, to: explore_url(params))}
  end

  defp read_params(params) do
    %{
      event: blank(params["event"]),
      group: blank(params["group"]),
      days: int_param(params, "days", @windows, 30),
      segment: Segment.parse(params["segment"]),
      where:
        params
        |> Map.get("f", %{})
        |> then(&if(is_map(&1), do: &1, else: %{}))
        |> Map.filter(fn {k, v} ->
          is_binary(v) and v != "" and Regex.match?(~r/\A[a-z0-9_]{1,32}\z/, k)
        end),
      by: blank(params["by"]),
      user: params["user"] |> blank() |> valid_uuid(),
      page: max(int_param(params, "page", Enum.to_list(1..10_000), 1), 1)
    }
  end

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(value) when is_binary(value), do: value
  defp blank(_), do: nil

  defp valid_uuid(nil), do: nil

  defp valid_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  # ── loading ───────────────────────────────────────────────────────────

  defp load(socket) do
    _ = Analytics.flush()
    p = socket.assigns.params
    today = Date.utc_today()

    seen = Explore.names(90, today)
    seen_names = Enum.map(seen, &elem(&1, 0))
    groups = Catalog.grouped(seen_names, kind: :event)

    {names, events, title} = target(p, groups)
    dims = dims_of(events, p.days, today)
    by = if p.by in Enum.map(dims, &elem(&1, 0)), do: p.by, else: dims |> List.first() |> key()
    measures = events |> Enum.flat_map(& &1.measures) |> Enum.uniq()
    rates = events |> Enum.flat_map(& &1.rates) |> Enum.uniq()
    measure_opts = [measures: Enum.map(measures, &elem(&1, 0)), rates: rates]

    filter =
      Explore.filter(
        names: names,
        days: p.days,
        to: today,
        segment: p.segment,
        where: p.where,
        user_id: p.user
      )

    socket
    |> assign(:groups, groups)
    |> assign(:title, title)
    |> assign(:events, events)
    |> assign(:dims, dims)
    |> assign(:columns, columns(events, dims, measures))
    |> assign(:by, by)
    |> assign(:measures, measures)
    |> assign(:rates, rates)
    |> assign(:values, values(filter, dims))
    |> assign(:series, Explore.series(filter))
    |> assign(:counter, Explore.counter_series(filter))
    |> assign(:totals, Explore.totals(filter))
    |> assign(:averages, Explore.measures(filter, measure_opts))
    |> assign(:breakdown, if(by, do: Explore.breakdown(filter, by, measure_opts), else: []))
    |> assign(:rows, Explore.rows(filter, page: p.page, page_size: @page_size))
    |> assign(:user, p.user && Gamend.Accounts.get_user(p.user))
    |> assign(:labels, Map.new(Catalog.events(), &{&1.name, &1.label}))
  end

  # The names to read, their catalogue entries and the page's title.
  defp target(%{event: name}, _groups) when is_binary(name) do
    event = Catalog.event(name)
    {[name], [event], event.label}
  end

  defp target(%{group: id}, groups) when is_binary(id) do
    case Enum.find(groups, fn {group, _} -> group.id == id end) do
      {group, events} -> {Enum.map(events, & &1.name), events, group.label}
      nil -> {[], [], Catalog.group(id).label}
    end
  end

  defp target(_params, _groups), do: {:all, [], "Every event"}

  # The dimensions to filter and break down by: the catalogue's, else the
  # ones the counters of an undeclared event were written with.
  defp dims_of(events, days, today) do
    events
    |> Enum.flat_map(fn
      %{declared: true, dims: dims} ->
        dims

      %{name: name} ->
        (name <> ".*")
        |> Analytics.families(days, today)
        |> Enum.find_value([], fn fam ->
          if fam.key == name, do: fam.dims |> Map.keys() |> Enum.sort() |> Enum.map(&{&1, &1})
        end)
    end)
    |> Enum.uniq_by(&elem(&1, 0))
  end

  # One event: a column per field it declares (or its counters were
  # written with), the rest in Other. Several: the fields in one column.
  defp columns([_one], dims, measures), do: dims ++ measures
  defp columns(_events, _dims, _measures), do: nil

  defp key(nil), do: nil
  defp key({key, _label}), do: key

  # For each dimension, the values it takes under the OTHER filters, most
  # people first, so a filter can be changed without clearing the rest.
  defp values(filter, dims) do
    Map.new(dims, fn {dim, _label} ->
      others = %{filter | where: Map.delete(filter.where, dim)}
      {dim, others |> Explore.breakdown(dim) |> Enum.take(@values_shown)}
    end)
  end

  # ── links ─────────────────────────────────────────────────────────────

  defp explore_url(p) do
    link_to(
      "/admin/analytics/explore",
      %{
        "event" => p.event,
        "group" => p.group,
        "days" => p.days,
        "segment" => Atom.to_string(p.segment),
        "f" => p.where,
        "by" => p.by,
        "user" => p.user,
        "page" => p.page
      },
      %{"days" => "30", "segment" => "all", "page" => "1"}
    )
  end

  defp nav(assigns, changes),
    do: explore_url(Map.merge(assigns.params, Map.put_new(changes, :page, 1)))

  defp people_url(user_id), do: link_to("/admin/analytics/people", %{"user" => user_id})

  # ── render ────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <.analytics_header
          tab="explore"
          note="Event rows: an account's events only (a visitor's are counted, never kept). The Everyone chart is the daily counter, visitors included, shown while it holds the same question."
        >
          <:controls>
            <.switch
              label="Segment"
              options={for s <- Segment.all(), do: {s, Segment.label(s)}}
              selected={@params.segment}
              to={&nav(assigns, %{segment: &1})}
            />
            <.switch
              label="Window"
              options={for d <- [7, 30, 90], do: {d, "#{d} days"}}
              selected={@params.days}
              to={&nav(assigns, %{days: &1})}
            />
            <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
          </:controls>
        </.analytics_header>

        <.panel>
          <form
            id="explore-filter"
            phx-change="filter"
            phx-submit="filter"
            class="flex flex-wrap items-end gap-3"
          >
            <label class="form-control">
              <span class="label-text text-xs">Event</span>
              <select name="target" class="select select-bordered select-sm">
                <option value="" selected={is_nil(@params.event) and is_nil(@params.group)}>
                  Every event
                </option>
                <optgroup :for={{group, events} <- @groups} label={group.label}>
                  <option value={"group:#{group.id}"} selected={@params.group == group.id}>
                    All of {group.label}
                  </option>
                  <option
                    :for={event <- events}
                    value={"event:#{event.name}"}
                    selected={@params.event == event.name}
                  >
                    {event.label}
                  </option>
                </optgroup>
              </select>
            </label>

            <label :for={{dim, label} <- @dims} class="form-control">
              <span class="label-text text-xs">{label}</span>
              <select name={"f[#{dim}]"} class="select select-bordered select-sm">
                <option value="">Any</option>
                <option
                  :for={row <- Map.get(@values, dim, [])}
                  value={row.value}
                  selected={Map.get(@params.where, dim) == row.value}
                >
                  {row.value} ({row.people})
                </option>
                <option
                  :if={
                    (v = Map.get(@params.where, dim)) &&
                      not Enum.any?(Map.get(@values, dim, []), &(&1.value == v))
                  }
                  value={Map.get(@params.where, dim)}
                  selected
                >
                  {Map.get(@params.where, dim)}
                </option>
              </select>
            </label>

            <label :if={@dims != []} class="form-control">
              <span class="label-text text-xs">Break down by</span>
              <select name="by" class="select select-bordered select-sm">
                <option :for={{dim, label} <- @dims} value={dim} selected={dim == @by}>
                  {label}
                </option>
              </select>
            </label>

            <label class="form-control">
              <span class="label-text text-xs">Account id</span>
              <input
                type="text"
                name="user"
                value={@params.user}
                placeholder="any"
                phx-debounce="500"
                class="input input-bordered input-sm w-72 font-mono"
              />
            </label>

            <.link
              :if={@params.where != %{} or @params.user}
              patch={nav(assigns, %{where: %{}, user: nil})}
              class="btn btn-ghost btn-sm"
            >
              Clear filters
            </.link>
          </form>
          <p :if={@user} class="mt-2 text-sm">
            One account:
            <.link navigate={people_url(@user.id)} class="link">{account_name(@user)}</.link>
            ({if User.anonymous?(@user), do: "guest", else: "registered"})
          </p>
        </.panel>

        <div class="grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-6">
          <.stat title="Events" value={num(@totals.events)} desc={"#{@params.days} days"} />
          <.stat title="Accounts" value={num(@totals.people)} desc="distinct" />
          <.stat
            title="Per account"
            value={
              num((@totals.people > 0 && Float.round(@totals.events / @totals.people, 1)) || nil)
            }
            desc="events"
          />
          <.stat
            :for={{m, label} <- @measures}
            title={"Average #{label}"}
            value={num(round1(@averages.measures[m]))}
          />
          <.stat
            :for={{_n, _d, label} <- @rates}
            title={label}
            value={pct(@averages.rates[label])}
            desc="sum ÷ sum"
          />
        </div>

        <.panel>
          <.eyebrow tag="h2" class="mb-3">{@title}</.eyebrow>
          <div class={["grid gap-6", if(@counter, do: "md:grid-cols-3", else: "md:grid-cols-2")]}>
            <.bars
              id="chart-events"
              title="Events"
              points={for r <- @series, do: {r.day, r.events}}
              summary={num(@totals.events)}
            />
            <.bars
              id="chart-people"
              title="Accounts"
              points={for r <- @series, do: {r.day, r.people}}
              summary="distinct per day"
            />
            <.bars
              :if={@counter}
              id="chart-counter"
              title="Everyone (counter)"
              points={for r <- @counter, do: {r.day, r.count}}
              summary={num(Enum.sum_by(@counter, & &1.count))}
            />
          </div>
        </.panel>

        <.panel :if={@by}>
          <.eyebrow tag="h2" class="mb-2">
            By {@dims |> Enum.find_value(fn {d, l} -> d == @by && l end)}
          </.eyebrow>
          <div class="overflow-x-auto">
            <table class="table table-sm" id="explore-breakdown">
              <thead>
                <tr>
                  <th>Value</th>
                  <th class="text-right">Accounts</th>
                  <th class="text-right">Events</th>
                  <th class="text-right">Share</th>
                  <th :for={{_m, label} <- @measures} class="text-right">Avg {label}</th>
                  <th :for={{_n, _d, label} <- @rates} class="text-right">{label}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @breakdown} class="hover:bg-base-200">
                  <td class="font-mono">
                    <.link
                      patch={nav(assigns, %{where: Map.put(@params.where, @by, row.value)})}
                      class="link link-hover"
                    >
                      {row.value}
                    </.link>
                  </td>
                  <td class="text-right tabular-nums">{num(row.people)}</td>
                  <td class="text-right tabular-nums">{num(row.events)}</td>
                  <td class="text-right tabular-nums">{share(row.events, @totals.events)}</td>
                  <td :for={{m, _label} <- @measures} class="text-right tabular-nums">
                    {num(round1(row.measures[m]))}
                  </td>
                  <td :for={{_n, _d, label} <- @rates} class="text-right tabular-nums">
                    {pct(row.rates[label])}
                  </td>
                </tr>
                <tr :if={@breakdown == []}>
                  <td colspan="9" class="text-muted">Nothing in the window.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </.panel>

        <.panel>
          <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
            <.eyebrow tag="h2">Rows</.eyebrow>
            <div class="flex items-center gap-2 text-xs text-muted">
              <span>
                {num(@rows.total)} rows · page {@params.page} of {max(
                  ceil_div(@rows.total, 50),
                  1
                )}
              </span>
              <.link
                :if={@params.page > 1}
                patch={nav(assigns, %{page: @params.page - 1})}
                class="btn btn-xs"
              >
                Newer
              </.link>
              <.link
                :if={@params.page * 50 < @rows.total}
                patch={nav(assigns, %{page: @params.page + 1})}
                class="btn btn-xs"
              >
                Older
              </.link>
            </div>
          </div>
          <div class="overflow-x-auto">
            <table class="table table-sm table-zebra" id="explore-rows">
              <thead>
                <tr>
                  <th>When (UTC)</th>
                  <th :if={is_nil(@columns)}>Event</th>
                  <th>Account</th>
                  <th :for={{_key, label} <- @columns || []}>{label}</th>
                  <th>{if @columns, do: "Other", else: "Fields"}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={e <- @rows.rows}>
                  <td class="font-mono whitespace-nowrap">
                    {Calendar.strftime(e.inserted_at, "%m-%d %H:%M:%S")}
                  </td>
                  <td :if={is_nil(@columns)} class="whitespace-nowrap">
                    <.link
                      patch={nav(assigns, %{event: e.name, group: nil, where: %{}})}
                      class="link link-hover"
                    >
                      {Map.get(@labels, e.name, e.name)}
                    </.link>
                  </td>
                  <td class="whitespace-nowrap">
                    <%= if e.user do %>
                      <.link navigate={people_url(e.user.id)} class="link link-hover font-mono">
                        {short_id(e.user.id)}
                      </.link>
                      <span class="badge badge-ghost badge-sm">
                        {if User.anonymous?(e.user), do: "guest", else: "registered"}
                      </span>
                    <% else %>
                      <span class="text-muted">deleted</span>
                    <% end %>
                  </td>
                  <td :for={{key, _label} <- @columns || []} class="font-mono text-xs">
                    {Map.get(e.dims, key)}
                  </td>
                  <td class="font-mono text-xs">
                    {fields(Map.drop(e.dims, Enum.map(@columns || [], &elem(&1, 0))))}
                  </td>
                </tr>
                <tr :if={@rows.rows == []}>
                  <td colspan="20" class="text-muted">No rows.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  defp fields(dims) when is_map(dims),
    do: dims |> Enum.sort() |> Enum.map_join("  ", fn {k, v} -> "#{k}=#{v}" end)

  defp share(_n, 0), do: "—"
  defp share(n, total), do: pct(n / total)

  defp round1(nil), do: nil
  defp round1(x), do: Float.round(x / 1, 1)

  defp ceil_div(n, d), do: div(n + d - 1, d)

  defp account_name(%User{} = user),
    do: Gamend.Accounts.display_label(user)
end
