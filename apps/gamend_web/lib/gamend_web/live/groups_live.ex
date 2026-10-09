defmodule GamendWeb.GroupsLive do
  use GamendWeb, :live_view

  import GamendWeb.PresenceIndicator, only: [presence_dot: 1]

  alias Gamend.Accounts.PresenceStatus
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Groups
  alias GamendWeb.LiveHelpers
  alias GamendWeb.OnMount.SeoTitle
  alias GamendWeb.Plugs.FeatureGate

  @page_size 12

  @impl true
  def mount(_params, _session, socket) do
    unless FeatureGate.enabled?(:list_groups) and FeatureGate.enabled?(:web_groups) do
      raise GamendWeb.NotFoundError
    end

    if connected?(socket), do: Groups.subscribe_groups()

    user = Scope.user(socket.assigns[:current_scope])

    # Build a set of group IDs the user has pending requests for
    pending_request_ids =
      if user do
        user.id
        |> Groups.list_user_pending_requests()
        |> MapSet.new(& &1.group_id)
      else
        MapSet.new()
      end

    # Build a set of group IDs the user is a member of
    member_group_ids =
      if user do
        user.id
        |> Groups.list_user_groups([])
        |> MapSet.new(& &1.id)
      else
        MapSet.new()
      end

    {:ok,
     assign(socket,
       page_title: gettext("Groups"),
       search: "",
       type_filter: "all",
       sort_by: "updated_at",
       page: 1,
       page_size: @page_size,
       groups: [],
       total_count: 0,
       total_pages: 0,
       pending_request_ids: pending_request_ids,
       member_group_ids: member_group_ids,
       selected_group: nil,
       selected_members: [],
       members_page: 1,
       members_search: "",
       members_total: 0,
       members_matched: 0,
       members_total_pages: 0
     )
     |> load_groups()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :show ->
        group_id = params["id"]

        case Groups.get_group(group_id) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Not found"))
             |> push_navigate(to: ~p"/groups")}

          group ->
            {:noreply,
             socket
             |> resubscribe_group(group.id)
             |> SeoTitle.assign_page_title(group.title)
             |> assign(
               selected_group: group,
               members_page: 1,
               members_search: ""
             )
             |> load_members()}
        end

      _ ->
        {:noreply,
         socket
         |> unsubscribe_group()
         |> assign(selected_group: nil)
         |> SeoTitle.assign_page_title(gettext("Groups"))}
    end
  end

  # `handle_params/3` runs on every navigation, and `Phoenix.PubSub` is a
  # duplicate registry: subscribing here without dropping the last one meant a
  # reader who opened the same group twice in a session handled its events
  # twice, three times on the third visit. One subscription at a time, tracked
  # in assigns — the same shape as `LobbyLive.Index.maybe_update_lobby_subscription/2`.
  defp resubscribe_group(socket, group_id) do
    case socket.assigns[:subscribed_group_id] do
      ^group_id ->
        socket

      previous ->
        if previous, do: Groups.unsubscribe_group(previous)
        if connected?(socket), do: Groups.subscribe_group(group_id)
        assign(socket, :subscribed_group_id, group_id)
    end
  end

  defp unsubscribe_group(socket) do
    if previous = socket.assigns[:subscribed_group_id] do
      Groups.unsubscribe_group(previous)
      assign(socket, :subscribed_group_id, nil)
    else
      socket
    end
  end

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply,
     socket
     |> assign(search: term, page: 1)
     |> load_groups()}
  end

  def handle_event("filter_type", %{"type" => type}, socket) do
    {:noreply,
     socket
     |> assign(type_filter: type, page: 1)
     |> load_groups()}
  end

  def handle_event("sort_by", %{"sort" => sort}, socket) do
    {:noreply,
     socket
     |> assign(sort_by: sort, page: 1)
     |> load_groups()}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> load_groups()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> load_groups()}

  def handle_event("groups_page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> load_groups()}

  def handle_event("view_group", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/groups/#{id}")}
  end

  def handle_event("back_to_list", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/groups")}
  end

  def handle_event("join_group", %{"id" => id}, socket) do
    group_id = id

    case Scope.user(socket.assigns.current_scope) do
      %User{} = user ->
        case Groups.join_group(user.id, group_id) do
          {:ok, _member} ->
            {:noreply,
             socket
             |> put_success_flash()
             |> update(:member_group_ids, &MapSet.put(&1, group_id))
             |> maybe_refresh_selected(group_id)}

          {:error, :already_member} ->
            {:noreply, put_flash(socket, :info, gettext("Joined"))}

          {:error, :not_public} ->
            {:noreply, put_flash(socket, :error, gettext("Failed"))}

          {:error, reason} ->
            {:noreply, put_failure_flash(socket, reason)}
        end

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}
    end
  end

  def handle_event("request_join", %{"id" => id}, socket) do
    group_id = id

    case Scope.user(socket.assigns.current_scope) do
      %User{} = user ->
        case Groups.request_join(user.id, group_id) do
          {:ok, _request} ->
            {:noreply,
             socket
             |> put_success_flash()
             |> update(:pending_request_ids, &MapSet.put(&1, group_id))}

          {:error, :already_member} ->
            {:noreply, put_flash(socket, :info, gettext("Joined"))}

          {:error, :already_requested} ->
            {:noreply, put_flash(socket, :info, gettext("Pending"))}

          {:error, :not_private} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Failed")
             )}

          {:error, reason} ->
            {:noreply, put_failure_flash(socket, reason)}
        end

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}
    end
  end

  def handle_event("leave_group", %{"id" => id}, socket) do
    group_id = id

    case Scope.user(socket.assigns.current_scope) do
      %User{} = user ->
        case Groups.leave_group(user.id, group_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_success_flash()
             |> update(:member_group_ids, &MapSet.delete(&1, group_id))
             |> maybe_refresh_selected(group_id)}

          {:error, reason} ->
            {:noreply, put_failure_flash(socket, reason)}
        end

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}
    end
  end

  def handle_event("members_prev", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page(:members_page) |> load_members()}

  def handle_event("members_next", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page(:members_page) |> load_members()}

  def handle_event("search_members", %{"search" => term}, socket) do
    {:noreply, load_members(assign(socket, members_search: term, members_page: 1))}
  end

  # ── PubSub handlers ────────────────────────────────────────────────────────

  @impl true
  def handle_info({:group_created, _group}, socket) do
    {:noreply, load_groups(socket)}
  end

  def handle_info({:group_updated, _group}, socket) do
    {:noreply, load_groups(socket)}
  end

  def handle_info({:group_deleted, _group_id}, socket) do
    {:noreply,
     socket
     |> assign(selected_group: nil)
     |> load_groups()}
  end

  def handle_info({:member_joined, group_id, _user_id}, socket) do
    {:noreply,
     socket
     |> load_groups()
     |> maybe_refresh_selected(group_id)}
  end

  def handle_info({:member_left, group_id, _user_id}, socket) do
    {:noreply,
     socket
     |> load_groups()
     |> maybe_refresh_selected(group_id)}
  end

  def handle_info({:join_request_created, _group_id, _user_id}, socket) do
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp put_success_flash(socket), do: LiveHelpers.put_success(socket, gettext("Success."))

  defp put_failure_flash(socket, reason) do
    LiveHelpers.put_failure(socket, LiveHelpers.failure_message(gettext("Failed"), reason))
  end

  defp build_filters(socket) do
    filters = %{}

    filters =
      if socket.assigns.search != "" do
        Map.put(filters, :title, socket.assigns.search)
      else
        filters
      end

    if socket.assigns.type_filter != "all" do
      Map.put(filters, :type, socket.assigns.type_filter)
    else
      filters
    end
  end

  defp load_groups(socket) do
    filters = build_filters(socket)

    groups =
      Groups.list_groups(filters,
        page: socket.assigns.page,
        page_size: socket.assigns.page_size,
        sort_by: socket.assigns.sort_by
      )

    total_count = Groups.count_list_groups(filters)

    total_pages =
      LiveHelpers.total_pages(total_count, socket.assigns.page_size)

    # Build a map of member counts per group
    member_counts = Enum.into(groups, %{}, fn g -> {g.id, Groups.count_group_members(g.id)} end)

    assign(socket,
      groups: groups,
      total_count: total_count,
      total_pages: total_pages,
      member_counts: member_counts
    )
  end

  defp load_members(socket) do
    case socket.assigns.selected_group do
      nil ->
        socket

      group ->
        search = socket.assigns[:members_search] || ""

        members =
          Groups.get_group_members_paginated(group.id,
            page: socket.assigns.members_page,
            page_size: @page_size,
            search: search
          )

        # The stat card reports the real roster size; the table and its pager
        # report whatever the search matched.
        matched = Groups.count_group_members(group.id, search: search)

        assign(socket,
          selected_members: members,
          members_total: Groups.count_group_members(group.id),
          members_matched: matched,
          members_total_pages: LiveHelpers.total_pages(matched, @page_size)
        )
    end
  end

  defp maybe_refresh_selected(socket, group_id) do
    case socket.assigns.selected_group do
      %{id: ^group_id} -> load_members(socket)
      _ -> socket
    end
  end

  # ── Render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <%!-- Back: from a group to the list, from the list home. --%>
        <div class="flex items-center gap-3">
          <.back_link
            :if={@selected_group}
            navigate={
              GamendWeb.HostLayouts.localized_href(
                "/groups",
                GamendWeb.HostLayouts.current_locale()
              )
            }
          />
          <.back_link :if={!@selected_group} href={home_path()} />
          <h1 class="text-4xl font-black text-base-content">{gettext("Groups")}</h1>
        </div>

        <%= if @selected_group do %>
          {render_group_detail(assigns)}
        <% else %>
          {render_group_list(assigns)}
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp render_group_list(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row gap-4 items-start sm:items-center">
      <form
        phx-change="search"
        phx-no-unused-field
        phx-submit="search"
        class="flex-1 w-full"
        id="groups-search-form"
      >
        <.input
          name="search"
          value={@search}
          placeholder={gettext("Search...")}
          phx-debounce="300"
          type="text"
        />
      </form>

      <div class="flex gap-2" id="groups-type-filter">
        <button
          :for={
            {label, value} <- [
              {gettext("All"), "all"},
              {gettext("Public"), "public"},
              {gettext("Private"), "private"}
            ]
          }
          phx-click="filter_type"
          phx-value-type={value}
          class={[
            "btn btn-sm",
            if(@type_filter == value, do: "btn-primary", else: "btn-ghost")
          ]}
        >
          {label}
        </button>
      </div>
    </div>

    <div class="flex gap-2 items-center" id="groups-sort">
      <span class="text-sm text-muted">{gettext("Sort by:")}</span>
      <button
        :for={
          {label, value} <- [
            {gettext("Date"), "updated_at"},
            {gettext("Newest"), "inserted_at"},
            {gettext("Name"), "title"},
            {gettext("Max members"), "max_members"}
          ]
        }
        phx-click="sort_by"
        phx-value-sort={value}
        class={[
          "btn btn-xs",
          if(@sort_by == value, do: "btn-primary", else: "btn-ghost")
        ]}
      >
        {label}
      </button>
    </div>

    <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3" id="groups-list">
      <.entity_card
        :for={group <- @groups}
        id={"group-#{group.id}"}
        title={group.title}
        icon_url={group.icon_url}
        type={:group}
        description={group.description}
        class="cursor-pointer"
        phx-click="view_group"
        phx-value-id={group.id}
      >
        <:badges>
          <%= if group.type == "public" do %>
            <span class="badge badge-success">{gettext("Public")}</span>
          <% else %>
            <span class="badge badge-warning">{gettext("Private")}</span>
          <% end %>
          {render_group_action_button(
            assigns
            |> Map.put(:group, group)
          )}
        </:badges>

        <div class="flex items-center gap-2 mt-1">
          <span class="badge badge-ghost badge-sm text-nowrap">
            {@member_counts[group.id] || 0} / {group.max_members} {gettext("Members")}
          </span>
        </div>
      </.entity_card>
    </div>

    <%= if @groups == [] do %>
      <div class="text-center py-12 text-muted" id="groups-empty">
        <p>{gettext("No results.")}</p>
      </div>
    <% end %>

    <div class="mt-6 flex justify-center">
      <.pagination
        page={@page}
        total_pages={@total_pages}
        total_count={@total_count}
        page_size={@page_size}
        on_prev="prev_page"
        on_next="next_page"
        on_page_size="groups_page_size"
      />
    </div>
    """
  end

  defp render_group_action_button(assigns) do
    ~H"""
    <%= if @current_scope && Scope.user(@current_scope) do %>
      <%= cond do %>
        <% MapSet.member?(@member_group_ids, @group.id) -> %>
          <span class="badge badge-success badge-sm">{gettext("Member")}</span>
        <% MapSet.member?(@pending_request_ids, @group.id) -> %>
          <span class="badge badge-warning badge-sm">{gettext("Pending")}</span>
        <% @group.type == "public" -> %>
          <button
            phx-click="join_group"
            phx-value-id={@group.id}
            class="btn btn-primary btn-sm"
          >
            {gettext("Join")}
          </button>
        <% @group.type == "private" -> %>
          <button
            phx-click="request_join"
            phx-value-id={@group.id}
            class="btn btn-surface btn-sm"
          >
            {gettext("Request")}
          </button>
        <% true -> %>
      <% end %>
    <% else %>
      <.link navigate={~p"/users/log_in"} class="btn btn-ghost btn-sm">
        {gettext("Log in")}
      </.link>
    <% end %>
    """
  end

  defp render_group_detail(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 mb-6">
      <div class="flex items-center gap-4">
        <button phx-click="back_to_list" class="btn btn-surface btn-sm" id="groups-back-btn">
          ← {gettext("Back")}
        </button>
        <div>
          <h2 class="text-2xl font-bold flex items-center gap-2">
            <.entity_icon
              icon_url={@selected_group.icon_url}
              type={:group}
              class="w-7 h-7 text-muted"
            />
            {@selected_group.title}
          </h2>
          <div class="flex items-center gap-2 mt-1">
            <%= if @selected_group.type == "public" do %>
              <span class="badge badge-success">{gettext("Public")}</span>
            <% else %>
              <span class="badge badge-warning">{gettext("Private")}</span>
            <% end %>
            <span class="text-sm text-muted">
              <.timestamp at={@selected_group.inserted_at} format="date" />
            </span>
          </div>
        </div>
      </div>
    </div>

    <%= if @selected_group.description && @selected_group.description != "" do %>
      <p class="text-muted mb-6">{@selected_group.description}</p>
    <% end %>

    <%!-- Action card --%>
    <div class="card bg-base-200 mb-6">
      <div class="card-body py-4">
        <div class="flex items-center justify-between">
          <div>
            <span class="text-sm text-muted">{gettext("Members")}</span>
            <div class="text-2xl font-bold">{@members_total} / {@selected_group.max_members}</div>
          </div>
          <div>
            {render_detail_action_button(assigns)}
          </div>
        </div>
      </div>
    </div>

    <%!-- Members table --%>
    <div class="card bg-base-200">
      <div class="card-body">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <h2 class="card-title">{gettext("Members")}</h2>

          <form
            phx-change="search_members"
            phx-no-unused-field
            phx-submit="search_members"
            id="members-search-form"
            class="sm:w-64"
          >
            <.input
              name="search"
              value={@members_search}
              placeholder={gettext("Search players...")}
              phx-debounce="300"
              type="text"
            />
          </form>
        </div>

        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>{gettext("Name")}</th>
                <th class="text-end">{gettext("Role")}</th>
              </tr>
            </thead>
            <tbody id="group-members-list">
              <tr
                :for={member <- @selected_members}
                id={"member-#{member.id}"}
              >
                <td>
                  <div class="flex items-center gap-2">
                    <.user_avatar user={member.user} class="w-8 h-8" />
                    <.presence_dot status={PresenceStatus.status(member.user)} />
                    <span>
                      <.player_name name={LiveHelpers.public_user_name(member.user)} />
                    </span>
                  </div>
                </td>
                <td class="text-end">
                  <%= if member.role == "admin" do %>
                    <span class="badge badge-primary badge-sm">{gettext("Admin")}</span>
                  <% else %>
                    <span class="badge badge-ghost badge-sm">{gettext("Member")}</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%= if @selected_members == [] do %>
          <div class="text-center py-8 text-muted">
            <p>{gettext("No results.")}</p>
          </div>
        <% end %>

        <div class="mt-4 flex justify-center">
          <.pagination
            page={@members_page}
            total_pages={@members_total_pages}
            total_count={@members_matched}
            on_prev="members_prev"
            on_next="members_next"
          />
        </div>
      </div>
    </div>
    """
  end

  defp render_detail_action_button(assigns) do
    ~H"""
    <%= if @current_scope && Scope.user(@current_scope) do %>
      <%= cond do %>
        <% MapSet.member?(@member_group_ids, @selected_group.id) -> %>
          <.link
            navigate={~p"/chat?#{[type: "group", id: @selected_group.id]}"}
            class="btn btn-surface btn-sm"
            id="group-chat-btn"
          >
            {gettext("Open chat")}
          </.link>
          <button
            phx-click="leave_group"
            phx-value-id={@selected_group.id}
            class="btn btn-outline btn-error btn-sm"
            id="group-leave-btn"
          >
            {gettext("Leave")}
          </button>
        <% MapSet.member?(@pending_request_ids, @selected_group.id) -> %>
          <span class="badge badge-warning">{gettext("Pending")}</span>
        <% @selected_group.type == "public" -> %>
          <button
            phx-click="join_group"
            phx-value-id={@selected_group.id}
            class="btn btn-primary btn-sm"
            id="group-join-btn"
          >
            {gettext("Join")}
          </button>
        <% @selected_group.type == "private" -> %>
          <button
            phx-click="request_join"
            phx-value-id={@selected_group.id}
            class="btn btn-surface btn-sm"
            id="group-request-btn"
          >
            {gettext("Request")}
          </button>
        <% true -> %>
      <% end %>
    <% else %>
      <.link navigate={~p"/users/log_in"} class="btn btn-surface btn-sm">
        {gettext("Log in")}
      </.link>
    <% end %>
    """
  end
end
