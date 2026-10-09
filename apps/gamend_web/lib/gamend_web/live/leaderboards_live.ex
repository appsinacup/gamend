defmodule GamendWeb.LeaderboardsLive do
  @moduledoc """
  Public-facing leaderboards view.

  Users can browse active and historical leaderboards and see their rank.
  Leaderboards are grouped by slug, showing the active/latest one by default
  with navigation to previous seasons.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Leaderboards
  alias Gamend.Leaderboards.Leaderboard
  alias GamendWeb.ContentText
  alias GamendWeb.LiveHelpers
  alias GamendWeb.Plugs.FeatureGate

  @impl true
  def mount(_params, _session, socket) do
    unless FeatureGate.enabled?(:list_leaderboards) do
      raise GamendWeb.NotFoundError
    end

    socket =
      socket
      |> assign(:locale, Gettext.get_locale(GamendWeb.Gettext))
      |> assign(:page_title, gettext("Leaderboards"))
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:selected_leaderboard, nil)
      |> assign(:slug_leaderboards, [])
      |> assign(:current_season_index, 0)
      |> assign(:records_page, 1)
      |> assign(:records_search, "")
      |> assign(:user_record, nil)
      |> reload_groups()

    {:ok, socket}
  end

  @impl true
  # A hidden board is shown by the host's own pages, never here.
  def handle_params(%{"slug" => slug, "id" => id}, _uri, socket) do
    case Leaderboards.get_leaderboard(id) do
      board when is_nil(board) or board.hidden ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Not found"))
         |> push_navigate(to: ~p"/leaderboards")}

      leaderboard ->
        # Verify slug matches, redirect if not
        cond do
          leaderboard.slug != slug ->
            # Wrong slug, redirect to correct one
            {:noreply, push_navigate(socket, to: leaderboard_path(leaderboard))}

          Leaderboards.Leaderboard.active?(leaderboard) ->
            # Active leaderboard should use slug-only URL
            {:noreply, push_navigate(socket, to: ~p"/leaderboards/#{slug}")}

          true ->
            load_leaderboard(socket, leaderboard)
        end
    end
  end

  def handle_params(%{"slug" => slug}, _uri, socket) do
    # Slug-only URL: load the active leaderboard directly
    case Leaderboards.get_active_leaderboard_by_slug(slug) do
      board when is_nil(board) or board.hidden ->
        # No active one, redirect to the latest with ID (never a hidden one)
        case Leaderboards.list_leaderboards_by_slug(slug) do
          [latest | _] ->
            {:noreply, push_navigate(socket, to: ~p"/leaderboards/#{slug}/#{latest.id}")}

          [] ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Not found"))
             |> push_navigate(to: ~p"/leaderboards")}
        end

      leaderboard ->
        # Active leaderboard found, load it directly
        load_leaderboard(socket, leaderboard)
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:selected_leaderboard, nil)
     |> assign(:slug_leaderboards, [])
     |> assign(:current_season_index, 0)
     |> assign(:user_record, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <%!-- Back: from a board to the list, from the list home. --%>
        <div class="flex items-center gap-3">
          <.back_link
            :if={@selected_leaderboard}
            navigate={
              GamendWeb.HostLayouts.localized_href(
                "/leaderboards",
                GamendWeb.HostLayouts.current_locale()
              )
            }
          />
          <.back_link :if={!@selected_leaderboard} href={home_path()} />
          <h1 class="text-4xl font-black text-base-content">
            {gettext("Leaderboards")}
            <span class="text-muted font-normal">({@count})</span>
          </h1>
        </div>

        <%= if @selected_leaderboard do %>
          <.render_leaderboard_detail
            leaderboard={@selected_leaderboard}
            slug_leaderboards={@slug_leaderboards}
            current_season_index={@current_season_index}
            records={@records}
            records_page={@records_page}
            records_total_pages={@records_total_pages}
            records_count={@records_count}
            user_record={@user_record}
            records_search={@records_search}
            current_user_id={@current_scope && Scope.user(@current_scope) && @current_scope.user_id}
            locale={@locale}
          />
        <% else %>
          <.render_group_list
            groups={@groups}
            page={@page}
            page_size={@page_size}
            total_pages={@total_pages}
            count={@count}
            locale={@locale}
          />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Render Components
  # ---------------------------------------------------------------------------

  defp render_group_list(assigns) do
    ~H"""
    <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
      <.entity_card
        :for={group <- @groups}
        navigate={~p"/leaderboards/#{group.slug}"}
        title={group.title}
        icon_url={group.icon_url}
        type={:leaderboard}
        description={group.description}
      >
        <:badges>
          <%= if group.active_id do %>
            <span class="badge badge-success">{gettext("Active")}</span>
          <% else %>
            <span class="badge badge-neutral">{gettext("Ended")}</span>
          <% end %>
          <span :if={group.season_count > 1} class="badge badge-ghost badge-sm text-nowrap">
            {group.season_count}
          </span>
        </:badges>
      </.entity_card>
    </div>

    <%= if @groups == [] do %>
      <div class="text-center py-12 text-muted">
        <p>{gettext("No results.")}</p>
      </div>
    <% end %>

    <div class="mt-6 flex justify-center">
      <.pagination
        page={@page}
        total_pages={@total_pages}
        page_size={@page_size}
        on_prev="prev_page"
        on_next="next_page"
        on_page_size="leaderboards_page_size"
      />
    </div>
    """
  end

  defp render_leaderboard_detail(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 mb-6">
      <%!-- Back button and title --%>
      <div class="flex items-center gap-4">
        <.link navigate={~p"/leaderboards"} class="btn btn-surface btn-sm">
          {gettext("Back")}
        </.link>
        <div>
          <h2 class="text-2xl font-bold flex items-center gap-2">
            <.entity_icon
              icon_url={@leaderboard.icon_url}
              type={:leaderboard}
              class="w-7 h-7 text-muted"
            />
            {@leaderboard.title}
          </h2>
          <div class="flex items-center gap-2 mt-1">
            <%= if Leaderboard.active?(@leaderboard) do %>
              <span class="badge badge-success">{gettext("Active")}</span>
            <% else %>
              <span class="badge badge-neutral">{gettext("Ended")}</span>
            <% end %>
            <%= if @leaderboard.starts_at || @leaderboard.ends_at do %>
              <span class="text-sm text-muted">
                <%= cond do %>
                  <% @leaderboard.starts_at && @leaderboard.ends_at -> %>
                    <.timestamp at={@leaderboard.starts_at} format="date" /> —
                    <.timestamp at={@leaderboard.ends_at} format="date" />
                  <% @leaderboard.ends_at -> %>
                    <.timestamp at={@leaderboard.ends_at} format="date" />
                  <% @leaderboard.starts_at -> %>
                    <.timestamp at={@leaderboard.starts_at} format="date" />
                  <% true -> %>
                <% end %>
              </span>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Season navigation --%>
      <%= if length(@slug_leaderboards) > 1 do %>
        <div class="flex items-center gap-3 bg-base-200 rounded-lg px-4 py-2 w-fit">
          <button
            phx-click="prev_season"
            class="btn btn-sm btn-ghost"
            disabled={@current_season_index >= length(@slug_leaderboards) - 1}
          >
            {gettext("Older")}
          </button>
          <div class="text-sm">
            <span class="font-medium">
              {"##{length(@slug_leaderboards) - @current_season_index}"}
            </span>
            <span class="text-muted">
              {"/ #{length(@slug_leaderboards)}"}
            </span>
          </div>
          <button
            phx-click="next_season"
            class="btn btn-sm btn-ghost"
            disabled={@current_season_index <= 0}
          >
            {gettext("Newer")}
          </button>
        </div>
      <% end %>
    </div>

    <% localized_desc = @leaderboard.description %>
    <%= if localized_desc do %>
      <p class="text-muted mb-6">{localized_desc}</p>
    <% end %>

    <%= if @user_record do %>
      <div class="card bg-primary/10 border border-primary/30 mb-6">
        <div class="card-body py-4">
          <div class="flex items-center justify-between">
            <div>
              <span class="text-sm text-muted">
                {gettext("Rank")}
              </span>
              <div class="text-2xl font-bold">#{@user_record.rank}</div>
            </div>
            <div class="text-end">
              <span class="text-sm text-muted">
                {score_label(@leaderboard)}
              </span>
              <div class="text-2xl font-bold">
                {format_score(@user_record.score, @leaderboard)}
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>

    <div class="card bg-base-200">
      <div class="card-body">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <h2 class="card-title">
            {gettext("Rankings")}
            <span class="text-muted font-normal text-base">({@records_count})</span>
          </h2>

          <form
            phx-change="search"
            phx-no-unused-field
            phx-submit="search"
            id="records-search-form"
            class="sm:w-64"
          >
            <.input
              name="search"
              value={@records_search}
              placeholder={gettext("Search...")}
              phx-debounce="300"
              type="text"
            />
          </form>
        </div>

        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>{gettext("Rank")}</th>
                <th>{gettext("Name")}</th>
                <th class="text-end">{score_label(@leaderboard)}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={record <- @records}
                class={[
                  record.user_id != nil && record.user_id == @current_user_id && "bg-primary/10"
                ]}
              >
                <td class="font-mono">
                  <span class={[
                    "inline-flex items-center justify-center w-8 h-8 rounded-full",
                    record.rank == 1 && "bg-yellow-500/20 text-yellow-600",
                    record.rank == 2 && "bg-gray-400/20 text-gray-600",
                    record.rank == 3 && "bg-orange-500/20 text-orange-600"
                  ]}>
                    {record.rank}
                  </span>
                </td>
                <td>
                  <div class="flex items-center gap-2">
                    <%!-- A label-only record (an external scoreboard entry) has
                          no user behind it, so it gets no avatar. --%>
                    <.user_avatar :if={record.user} user={record.user} class="w-8 h-8" />
                    <div class="flex flex-col leading-tight">
                      <span class={[
                        record.user_id != nil && record.user_id == @current_user_id && "font-bold"
                      ]}>
                        <.player_name name={
                          record.label || LiveHelpers.public_user_name(record.user || record.user_id)
                        } />
                      </span>
                      <.user_title user={record.user} />
                    </div>
                    <%= if record.user_id != nil and record.user_id == @current_user_id do %>
                      <span class="badge badge-primary badge-sm">{gettext("You")}</span>
                    <% end %>
                  </div>
                </td>
                <td class="text-end font-mono">
                  {format_score(record.score, @leaderboard)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%= if @records == [] do %>
          <div class="text-center py-8 text-muted">
            <p>{gettext("No results.")}</p>
          </div>
        <% end %>

        <%= if @records_total_pages > 1 do %>
          <div class="mt-4 flex justify-center">
            <.pagination
              page={@records_page}
              total_pages={@records_total_pages}
              total_count={@records_count}
              on_prev="records_prev"
              on_next="records_next"
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Event Handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload_groups()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload_groups()}

  def handle_event("leaderboards_page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload_groups()}

  def handle_event("prev_season", _, socket) do
    # Go to older season (higher index)
    slug_lbs = socket.assigns.slug_leaderboards
    new_index = min(socket.assigns.current_season_index + 1, length(slug_lbs) - 1)
    leaderboard = Enum.at(slug_lbs, new_index)

    {:noreply, push_patch(socket, to: leaderboard_path(leaderboard))}
  end

  def handle_event("next_season", _, socket) do
    # Go to newer season (lower index)
    slug_lbs = socket.assigns.slug_leaderboards
    new_index = max(socket.assigns.current_season_index - 1, 0)
    leaderboard = Enum.at(slug_lbs, new_index)

    {:noreply, push_patch(socket, to: leaderboard_path(leaderboard))}
  end

  def handle_event("records_prev", _, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page(:records_page) |> reload_records()}

  def handle_event("records_next", _, socket),
    do: {:noreply, socket |> LiveHelpers.next_page(:records_page) |> reload_records()}

  def handle_event("search", %{"search" => term}, socket) do
    {:noreply,
     socket
     |> assign(:records_search, term)
     |> assign(:records_page, 1)
     |> reload_records()}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp reload_groups(socket) do
    page = socket.assigns[:page] || 1
    page_size = socket.assigns[:page_size] || 25

    groups = Leaderboards.list_leaderboard_groups(page: page, page_size: page_size)
    count = Leaderboards.count_leaderboard_groups()
    total_pages = max(1, LiveHelpers.total_pages(count, page_size))

    socket
    |> assign(:groups, ContentText.translate(groups))
    |> assign(:count, count)
    |> assign(:total_pages, total_pages)
  end

  defp reload_records(socket) do
    lb = socket.assigns.selected_leaderboard
    page = socket.assigns[:records_page] || 1
    page_size = 25
    search = socket.assigns[:records_search] || ""

    records = Leaderboards.list_records(lb.id, page: page, page_size: page_size, search: search)
    count = Leaderboards.count_records(lb.id, search: search)
    total_pages = max(1, LiveHelpers.total_pages(count, page_size))

    socket
    |> assign(:records, records)
    |> assign(:records_count, count)
    |> assign(:records_total_pages, total_pages)
  end

  defp get_user_record(socket, leaderboard_id) do
    case socket.assigns[:current_scope] do
      %{user_id: user_id} when is_binary(user_id) ->
        case Leaderboards.get_user_record(leaderboard_id, user_id) do
          {:ok, record} -> record
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp load_leaderboard(socket, leaderboard) do
    # Load all leaderboards with same slug for season navigation
    slug_leaderboards = Leaderboards.list_leaderboards_by_slug(leaderboard.slug)
    current_index = Enum.find_index(slug_leaderboards, &(&1.id == leaderboard.id)) || 0
    user_record = get_user_record(socket, leaderboard.id)

    {:noreply,
     socket
     |> assign(:selected_leaderboard, ContentText.translate(leaderboard))
     |> assign(:slug_leaderboards, ContentText.translate(slug_leaderboards))
     |> assign(:current_season_index, current_index)
     |> assign(:user_record, user_record)
     |> assign(:records_page, 1)
     |> assign(:records_search, "")
     |> reload_records()}
  end

  # Returns the appropriate URL for a leaderboard:
  # - Active leaderboards use slug-only: /leaderboards/weekly_kills
  # - Historical leaderboards use slug/id: /leaderboards/weekly_kills/123
  defp leaderboard_path(leaderboard) do
    if Leaderboard.active?(leaderboard) do
      ~p"/leaderboards/#{leaderboard.slug}"
    else
      ~p"/leaderboards/#{leaderboard.slug}/#{leaderboard.id}"
    end
  end

  # What the score column is called, and what a value in it means. A board that
  # counts kilometres was headed "Score" and printed a bare `500`, next to a
  # column literally called "Rank" — three different senses of the word on one
  # screen. `metadata` carries the board's own wording; anything without it
  # keeps the generic pair.
  defp score_label(%{metadata: %{"score_label" => label}}) when is_binary(label), do: label
  defp score_label(_leaderboard), do: gettext("Score")

  defp format_score(score, %{metadata: %{"score_unit" => unit}}) when is_binary(unit),
    do: "#{format_score(score)} #{unit}"

  defp format_score(score, _leaderboard), do: format_score(score)

  defp format_score(score) when is_integer(score) do
    score
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end

  defp format_score(score), do: to_string(score)
end
