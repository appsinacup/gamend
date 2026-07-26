defmodule GameServerWeb.UserLive.Settings.GroupsTab do
  @moduledoc """
  Groups tab of the user settings page: my groups, browsing/joining,
  invitations, join requests, and per-group management (members, roles,
  editing, notifications).
  """

  use GameServerWeb, :html
  import Phoenix.LiveView

  alias GameServer.Accounts
  alias GameServer.Friends
  alias GameServer.Groups
  alias GameServer.Groups.Group
  alias GameServerWeb.LiveHelpers
  alias GameServerWeb.UserLive.Settings.Shared

  def assign_defaults(socket) do
    socket
    |> assign(:groups_tab, "my_groups")
    |> assign(:my_groups, [])
    |> assign(:groups_count, 0)
    |> assign(:group_invitations, [])
    |> assign(:group_pending_requests, [])
    |> assign(:group_sent_invitations, [])
    |> stream(:browse_groups, [], dom_id: &"browse-group-#{&1.id}")
    |> assign(:browse_groups_page, 1)
    |> assign(:browse_groups_page_size, 25)
    |> assign(:browse_groups_total, 0)
    |> assign(:browse_groups_total_pages, 0)
    |> assign(:browse_groups_filters, %{})
    |> assign(:browse_groups_form, to_form(%{"title" => "", "type" => ""}, as: :browse_groups))
    |> assign(:groups_show_create, false)
    |> assign(:create_group_form, to_form(Groups.change_group(%Group{}), as: :group))
    |> assign(:group_detail, nil)
    |> assign(:group_detail_role, nil)
    |> assign(:group_members, [])
    |> assign(:group_members_page, 1)
    |> assign(:group_members_page_size, 25)
    |> assign(:group_members_total, 0)
    |> assign(:group_members_total_pages, 0)
    |> assign(:invite_search_query, "")
    |> assign(:invite_search_results, [])
    |> assign(:invite_friends, [])
    |> assign(:group_editing, false)
    |> assign(:group_edit_form, nil)
    |> assign(:group_join_requests, [])
    |> assign(:group_notify_form, to_form(%{"content" => "", "title" => ""}, as: :notify))
    |> reload_groups()
  end

  def tab(assigns) do
    ~H"""
    <div :if={@settings_tab == "groups"}>
      <%!-- Groups section --%>
      <div class="card bg-base-200 p-4 rounded-lg mt-6">
        <div class="flex items-center justify-between">
          <div>
            <div class="font-semibold text-lg">{gettext("Groups")}</div>
          </div>
          <div class="flex gap-2">
            <%= if @group_detail do %>
              <button phx-click="group_close_detail" class="btn btn-sm btn-ghost">
                {gettext("Back")}
              </button>
            <% end %>
            <button
              phx-click="groups_toggle_create"
              class={[
                "btn btn-sm",
                if(@groups_show_create, do: "btn-ghost", else: "btn-primary")
              ]}
            >
              <%= if @groups_show_create do %>
                {gettext("Cancel")}
              <% else %>
                {gettext("Create")}
              <% end %>
            </button>
          </div>
        </div>

        <%!-- Create group form --%>
        <%= if @groups_show_create do %>
          <div class="mt-4 border border-base-300 rounded-lg p-4 bg-base-100">
            <div class="font-semibold text-sm mb-3">{gettext("Create")}</div>
            <.form
              for={@create_group_form}
              id="create-group-form"
              phx-change="group_validate_create"
              phx-submit="group_create"
            >
              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <.input
                  field={@create_group_form[:title]}
                  type="text"
                  label={gettext("Title")}
                  required
                />
                <.input
                  field={@create_group_form[:description]}
                  type="text"
                  label={gettext("Description")}
                />
                <.input
                  field={@create_group_form[:type]}
                  type="select"
                  label={gettext("Type")}
                  options={[
                    {gettext("Public"), "public"},
                    {gettext("Private"), "private"},
                    {gettext("Hidden"), "hidden"}
                  ]}
                />
                <.input
                  field={@create_group_form[:max_members]}
                  type="number"
                  label={gettext("Members")}
                />
              </div>
              <div class="mt-3">
                <button type="submit" class="btn btn-sm btn-primary">
                  {gettext("Create")}
                </button>
              </div>
            </.form>
          </div>
        <% end %>

        <%!-- Group Detail View --%>
        <%= if @group_detail && !@groups_show_create do %>
          <div class="mt-4">
            <%!-- Edit form (admin only) --%>
            <%= if @group_editing && @group_detail_role == "admin" do %>
              <.form
                for={@group_edit_form}
                id="group-edit-form"
                phx-change="group_validate_edit"
                phx-submit="group_save_edit"
                class="space-y-3"
              >
                <.input field={@group_edit_form[:title]} label={gettext("Name")} type="text" />
                <.input
                  field={@group_edit_form[:description]}
                  label={gettext("Description")}
                  type="textarea"
                />
                <.input
                  field={@group_edit_form[:type]}
                  label={gettext("Type")}
                  type="select"
                  options={[
                    {gettext("Public"), "public"},
                    {gettext("Private"), "private"},
                    {gettext("Hidden"), "hidden"}
                  ]}
                />
                <.input
                  field={@group_edit_form[:max_members]}
                  label={gettext("Members")}
                  type="number"
                />
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-sm btn-primary">{gettext("Save")}</button>
                  <button
                    type="button"
                    phx-click="group_toggle_edit"
                    class="btn btn-sm btn-ghost"
                  >
                    {gettext("Cancel")}
                  </button>
                </div>
              </.form>
            <% else %>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div class="space-y-2 text-sm">
                  <div><strong>{gettext("Name")}:</strong> {@group_detail.title}</div>
                  <div>
                    <strong>{gettext("Description")}:</strong> {@group_detail.description ||
                      "-"}
                  </div>
                  <div>
                    <strong>{gettext("Type")}:</strong>
                    <span class={[
                      "badge badge-sm",
                      cond do
                        @group_detail.type == "public" -> "badge-success"
                        @group_detail.type == "private" -> "badge-warning"
                        true -> "badge-error"
                      end
                    ]}>
                      {@group_detail.type}
                    </span>
                  </div>
                  <div>
                    <strong>{gettext("Members")}:</strong> {@group_detail.max_members}
                  </div>
                  <div>
                    <strong>{gettext("Date")}:</strong> <.timestamp at={@group_detail.inserted_at} />
                  </div>
                </div>
                <div class="space-y-2 text-sm">
                  <div>
                    <strong>{gettext("Role")}:</strong>
                    <span class={[
                      "badge badge-sm",
                      if(@group_detail_role == "admin", do: "badge-info", else: "badge-ghost")
                    ]}>
                      {@group_detail_role || gettext("No results.")}
                    </span>
                  </div>
                  <div class="flex gap-2">
                    <button
                      :if={@group_detail_role == "admin"}
                      phx-click="group_toggle_edit"
                      class="btn btn-xs btn-outline btn-info"
                    >
                      {gettext("Edit")}
                    </button>
                    <button
                      phx-click="group_leave"
                      phx-value-group_id={@group_detail.id}
                      class="btn btn-xs btn-outline btn-error"
                      data-confirm={gettext("Leave?")}
                    >
                      {gettext("Leave")}
                    </button>
                  </div>
                </div>
              </div>
            <% end %>

            <%!-- Members list --%>
            <div class="mt-4">
              <div class="font-semibold text-sm">{gettext("Members")} ({@group_members_total})</div>
              <div class="overflow-x-auto mt-2">
                <table id="group-members-table" class="table table-zebra w-full">
                  <thead>
                    <tr>
                      <th></th>
                      <th>{gettext("Name")}</th>
                      <th>{gettext("Role")}</th>
                      <th>{gettext("Joined")}</th>
                      <%= if @group_detail_role == "admin" do %>
                        <th>{gettext("Actions")}</th>
                      <% end %>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={m <- @group_members}
                      id={"gm-" <> to_string(m.id)}
                    >
                      <td>
                        <span
                          class={[
                            "inline-block w-2 h-2 rounded-full",
                            if(m.user.is_online, do: "bg-green-500", else: "bg-gray-400")
                          ]}
                          title={if(m.user.is_online, do: "Online", else: "Offline")}
                        />
                      </td>
                      <td class="text-sm">{LiveHelpers.public_user_name(m.user)}</td>
                      <td>
                        <span class={[
                          "badge badge-sm",
                          if(m.role == "admin", do: "badge-info", else: "badge-ghost")
                        ]}>
                          {m.role}
                        </span>
                      </td>
                      <td class="text-sm whitespace-nowrap">
                        <.timestamp at={m.inserted_at} />
                      </td>
                      <%= if @group_detail_role == "admin" do %>
                        <td class="flex gap-1">
                          <%= if m.user_id != @user.id do %>
                            <%= if m.role == "member" do %>
                              <button
                                phx-click="group_promote"
                                phx-value-group_id={@group_detail.id}
                                phx-value-user_id={m.user_id}
                                class="btn btn-xs btn-outline btn-primary"
                              >
                                {gettext("Promote")}
                              </button>
                            <% else %>
                              <button
                                phx-click="group_demote"
                                phx-value-group_id={@group_detail.id}
                                phx-value-user_id={m.user_id}
                                class="btn btn-xs btn-outline btn-warning"
                              >
                                {gettext("Demote")}
                              </button>
                            <% end %>
                            <button
                              phx-click="group_kick"
                              phx-value-group_id={@group_detail.id}
                              phx-value-user_id={m.user_id}
                              class="btn btn-xs btn-outline btn-error"
                              data-confirm={gettext("Kick?")}
                            >
                              {gettext("Kick")}
                            </button>
                          <% else %>
                            <span class="text-xs text-base-content/50">{gettext("You")}</span>
                          <% end %>
                        </td>
                      <% end %>
                    </tr>
                  </tbody>
                </table>
              </div>

              <div :if={@group_members_total_pages > 1} class="mt-2">
                <.pagination
                  page={@group_members_page}
                  total_pages={@group_members_total_pages}
                  total_count={@group_members_total}
                  on_prev="group_members_prev"
                  on_next="group_members_next"
                />
              </div>
            </div>

            <%!-- Incoming Join Requests (admin only) --%>
            <div :if={@group_detail_role == "admin" && @group_join_requests != []} class="mt-6">
              <h4 class="font-semibold text-base mb-3">
                {gettext("Request")} ({length(@group_join_requests)})
              </h4>
              <div class="space-y-2">
                <div
                  :for={req <- @group_join_requests}
                  class="flex items-center justify-between p-2 rounded-lg bg-base-200/60"
                >
                  <div class="flex items-center gap-2">
                    <div class="text-sm font-medium">
                      {LiveHelpers.public_user_name(req.user)}
                    </div>
                    <span class="text-xs text-base-content/50">
                      #{req.user_id} &mdash; <.timestamp at={req.inserted_at} />
                    </span>
                  </div>
                  <div class="flex gap-1">
                    <button
                      phx-click="group_approve_request"
                      phx-value-request_id={req.id}
                      class="btn btn-xs btn-primary"
                    >
                      {gettext("Approve")}
                    </button>
                    <button
                      phx-click="group_reject_request"
                      phx-value-request_id={req.id}
                      class="btn btn-xs btn-outline btn-error"
                    >
                      {gettext("Reject")}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Invite Members (admin only) --%>
            <div :if={@group_detail_role == "admin"} class="mt-6">
              <h4 class="font-semibold text-base mb-3">{gettext("Invite")}</h4>

              <%!-- Search by name or user ID --%>
              <div class="form-control mb-3">
                <label class="label">
                  <span class="label-text">{gettext("Search...")}</span>
                </label>
                <input
                  id="invite-search-input"
                  type="text"
                  phx-keyup="group_invite_search"
                  phx-debounce="300"
                  value={@invite_search_query}
                  placeholder={gettext("Search...")}
                  class="input input-bordered input-sm w-full max-w-xs"
                  autocomplete="off"
                />
              </div>

              <%!-- Search results --%>
              <div :if={@invite_search_results != []} class="mb-4">
                <div class="text-xs font-medium text-base-content/60 mb-1">
                  {gettext("Name")}
                </div>
                <div class="space-y-1 max-h-48 overflow-y-auto">
                  <div
                    :for={u <- @invite_search_results}
                    class="flex items-center justify-between p-2 rounded-lg bg-base-200/60"
                  >
                    <div class="flex items-center gap-2">
                      <div class={[
                        "w-2 h-2 rounded-full",
                        if(Map.get(u, :is_online, false),
                          do: "bg-success",
                          else: "bg-base-content/30"
                        )
                      ]} />
                      <div>
                        <span class="text-sm font-medium">{LiveHelpers.public_user_name(u)}</span>
                        <span class="text-xs text-base-content/50 ml-1">#{u.id}</span>
                      </div>
                    </div>
                    <button
                      :if={u.id != @current_scope.user_id}
                      phx-click="group_invite_user"
                      phx-value-group_id={@group_detail.id}
                      phx-value-user_id={u.id}
                      class="btn btn-xs btn-primary"
                    >
                      {gettext("Invite")}
                    </button>
                  </div>
                </div>
              </div>

              <div
                :if={@invite_search_query != "" && @invite_search_results == []}
                class="mb-4 text-sm text-base-content/50"
              >
                {gettext("No results.")}
              </div>

              <%!-- Quick invite from friends --%>
              <div :if={@invite_friends != []} class="mt-3">
                <div class="text-xs font-medium text-base-content/60 mb-1">
                  {gettext("Friends")}
                </div>
                <div class="space-y-1 max-h-48 overflow-y-auto">
                  <div
                    :for={f <- @invite_friends}
                    class="flex items-center justify-between p-2 rounded-lg bg-base-200/40"
                  >
                    <div class="flex items-center gap-2">
                      <div class={[
                        "w-2 h-2 rounded-full",
                        if(Map.get(f, :is_online, false),
                          do: "bg-success",
                          else: "bg-base-content/30"
                        )
                      ]} />
                      <span class="text-sm">{LiveHelpers.public_user_name(f)}</span>
                    </div>
                    <button
                      phx-click="group_invite_user"
                      phx-value-group_id={@group_detail.id}
                      phx-value-user_id={f.id}
                      class="btn btn-xs btn-outline btn-primary"
                    >
                      {gettext("Invite")}
                    </button>
                  </div>
                </div>
              </div>

              <div :if={@invite_friends == []} class="mt-3 text-sm text-base-content/40">
                {gettext("No results.")}
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Tabs (hidden when viewing detail) --%>
        <%= if !@group_detail && !@groups_show_create do %>
          <%!-- Sub-tabs --%>
          <div class="mt-4 border-b border-base-300 pb-2 overflow-x-auto">
            <div class="flex gap-2 min-w-max">
              <button
                :for={
                  {tab, label} <- [
                    {"my_groups", gettext("Groups") <> " (#{@groups_count})"},
                    {"browse", gettext("Search...")},
                    {"invitations", gettext("Invite") <> " (#{length(@group_invitations)})"},
                    {"requests", gettext("Request") <> " (#{length(@group_pending_requests)})"},
                    {"sent_invitations",
                     gettext("Send") <>
                       " (#{length(@group_sent_invitations)})"}
                  ]
                }
                phx-click="groups_tab"
                phx-value-tab={tab}
                class={[
                  "btn btn-sm flex-none",
                  if(@groups_tab == tab, do: "btn-primary", else: "btn-ghost")
                ]}
              >
                {label}
              </button>
            </div>
          </div>

          <%!-- My Groups tab --%>
          <%= if @groups_tab == "my_groups" do %>
            <%= if @groups_count == 0 do %>
              <div class="mt-4 text-sm text-base-content/60">
                {gettext("No results.")}
              </div>
            <% else %>
              <div class="overflow-x-auto mt-4">
                <table id="my-groups-table" class="table table-zebra w-full">
                  <thead>
                    <tr>
                      <th>{gettext("Title")}</th>
                      <th>{gettext("Type")}</th>
                      <th>{gettext("Members")}</th>
                      <th>{gettext("Role")}</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={{group, role} <- @my_groups}
                      id={"my-group-" <> to_string(group.id)}
                    >
                      <td class="text-sm">
                        <button
                          phx-click="group_view_detail"
                          phx-value-group_id={group.id}
                          class="link link-primary font-medium inline-flex items-center gap-1"
                        >
                          {group.title}
                        </button>
                      </td>
                      <td>
                        <span class={[
                          "badge badge-sm",
                          cond do
                            group.type == "public" -> "badge-success"
                            group.type == "private" -> "badge-warning"
                            true -> "badge-error"
                          end
                        ]}>
                          {group.type}
                        </span>
                      </td>
                      <td class="text-sm">{group.max_members}</td>
                      <td>
                        <span class={[
                          "badge badge-sm",
                          if(role == "admin", do: "badge-info", else: "badge-ghost")
                        ]}>
                          {role}
                        </span>
                      </td>
                      <td class="flex gap-1">
                        <button
                          phx-click="group_view_detail"
                          phx-value-group_id={group.id}
                          class="btn btn-xs btn-ghost"
                        >
                          {gettext("View")}
                        </button>
                        <button
                          phx-click="group_leave"
                          phx-value-group_id={group.id}
                          class="btn btn-xs btn-outline btn-error"
                          data-confirm={gettext("Leave?")}
                        >
                          {gettext("Leave")}
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          <% end %>

          <%!-- Browse Groups tab --%>
          <%= if @groups_tab == "browse" do %>
            <div class="mt-4">
              <.form
                for={@browse_groups_form}
                id="browse-groups-form"
                phx-change="browse_groups_filter"
                phx-submit="browse_groups_filter"
              >
                <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                  <.input
                    field={@browse_groups_form[:title]}
                    type="text"
                    label={gettext("Title")}
                    phx-debounce="300"
                  />
                  <.input
                    field={@browse_groups_form[:type]}
                    type="select"
                    label={gettext("Type")}
                    options={[
                      {gettext("All"), ""},
                      {gettext("Public"), "public"},
                      {gettext("Private"), "private"}
                    ]}
                  />
                  <div class="flex items-end">
                    <button
                      type="button"
                      phx-click="browse_groups_clear"
                      class="btn btn-sm btn-ghost"
                    >
                      {gettext("Clear")}
                    </button>
                  </div>
                </div>
              </.form>
            </div>

            <div class="overflow-x-auto mt-4">
              <table id="browse-groups-table" class="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>{gettext("Title")}</th>
                    <th>{gettext("Type")}</th>
                    <th>{gettext("Members")}</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody id="browse-groups" phx-update="stream">
                  <tr class="hidden only:table-row">
                    <td colspan="4" class="text-center text-sm text-base-content/60">
                      {gettext("No results.")}
                    </td>
                  </tr>
                  <tr
                    :for={{dom_id, group} <- @streams.browse_groups}
                    id={dom_id}
                  >
                    <td class="text-sm font-medium">{group.title}</td>
                    <td>
                      <span class={[
                        "badge badge-sm",
                        if(group.type == "public", do: "badge-success", else: "badge-warning")
                      ]}>
                        {group.type}
                      </span>
                    </td>
                    <td class="text-sm">{group.max_members}</td>
                    <td>
                      <%= cond do %>
                        <% Enum.any?(@my_groups, fn {g, _role} -> g.id == group.id end) -> %>
                          <span class="badge badge-sm badge-ghost">
                            {gettext("Joined")}
                          </span>
                        <% Enum.any?(@group_pending_requests, fn r -> r.group_id == group.id end) -> %>
                          <span class="badge badge-sm badge-warning">
                            {gettext("Pending")}
                          </span>
                        <% group.type == "public" -> %>
                          <button
                            phx-click="group_join"
                            phx-value-group_id={group.id}
                            class="btn btn-xs btn-primary"
                          >
                            {gettext("Join")}
                          </button>
                        <% group.type == "private" -> %>
                          <button
                            phx-click="group_request_join"
                            phx-value-group_id={group.id}
                            class="btn btn-xs btn-outline btn-primary"
                          >
                            {gettext("Request")}
                          </button>
                        <% true -> %>
                          <span class="text-xs text-base-content/50">-</span>
                      <% end %>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="mt-4">
              <.pagination
                page={@browse_groups_page}
                total_pages={@browse_groups_total_pages}
                total_count={@browse_groups_total}
                on_prev="browse_groups_prev"
                on_next="browse_groups_next"
              />
            </div>
          <% end %>

          <%!-- Invitations tab --%>
          <%= if @groups_tab == "invitations" do %>
            <%= if length(@group_invitations) == 0 do %>
              <div class="mt-4 text-sm text-base-content/60">
                {gettext("No results.")}
              </div>
            <% else %>
              <div class="overflow-x-auto mt-4">
                <table id="group-invitations-table" class="table table-zebra w-full">
                  <thead>
                    <tr>
                      <th>{gettext("Group")}</th>
                      <th>{gettext("From")}</th>
                      <th>{gettext("Date")}</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={inv <- @group_invitations}
                      id={"group-inv-" <> to_string(inv.id)}
                    >
                      <td class="text-sm font-mono">
                        {inv.group_name || "Group ##{inv.group_id}"}
                      </td>
                      <td class="text-sm font-mono">
                        {inv.sender_name || "User ##{inv.sender_id}"}
                      </td>
                      <td class="text-sm whitespace-nowrap">
                        <.timestamp at={inv.inserted_at} />
                      </td>
                      <td class="flex gap-1">
                        <button
                          phx-click="group_accept_invite"
                          phx-value-invite_id={inv.id}
                          class="btn btn-xs btn-primary"
                        >
                          {gettext("Accept")}
                        </button>
                        <button
                          phx-click="group_decline_invite"
                          phx-value-invite_id={inv.id}
                          class="btn btn-xs btn-outline btn-error"
                        >
                          {gettext("Decline")}
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          <% end %>

          <%!-- My Pending Requests tab --%>
          <%= if @groups_tab == "requests" do %>
            <%= if length(@group_pending_requests) == 0 do %>
              <div class="mt-4 text-sm text-base-content/60">
                {gettext("No results.")}
              </div>
            <% else %>
              <div class="overflow-x-auto mt-4">
                <table id="group-requests-table" class="table table-zebra w-full">
                  <thead>
                    <tr>
                      <th>{gettext("Group")}</th>
                      <th>{gettext("Status")}</th>
                      <th>{gettext("Request")}</th>
                      <th>{gettext("Actions")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={req <- @group_pending_requests}
                      id={"group-req-" <> to_string(req.id)}
                    >
                      <td class="text-sm font-mono">{req.group.title}</td>
                      <td>
                        <span class="badge badge-sm badge-warning">{req.status}</span>
                      </td>
                      <td class="text-sm whitespace-nowrap">
                        <.timestamp at={req.inserted_at} />
                      </td>
                      <td>
                        <button
                          phx-click="group_cancel_request"
                          phx-value-request_id={req.id}
                          class="btn btn-xs btn-outline btn-error"
                          data-confirm={gettext("Cancel?")}
                        >
                          {gettext("Cancel")}
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          <% end %>

          <%!-- Sent Invitations tab --%>
          <%= if @groups_tab == "sent_invitations" do %>
            <%= if @group_sent_invitations == [] do %>
              <div class="mt-4 text-sm text-base-content/60">{gettext("No results.")}</div>
            <% else %>
              <div class="overflow-x-auto mt-4">
                <table id="group-sent-invitations-table" class="table table-zebra w-full">
                  <thead>
                    <tr>
                      <th>{gettext("Group")}</th>
                      <th>{gettext("Invite")}</th>
                      <th>{gettext("Date")}</th>
                      <th>{gettext("Actions")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={inv <- @group_sent_invitations}
                      id={"group-sent-inv-" <> to_string(inv.id)}
                    >
                      <td class="text-sm font-mono">
                        {inv.group_name || "Group ##{inv.group_id}"}
                      </td>
                      <td class="text-sm font-mono">
                        {inv.recipient_name || "User ##{inv.recipient_id}"}
                      </td>
                      <td class="text-sm whitespace-nowrap">
                        <.timestamp at={inv.inserted_at} />
                      </td>
                      <td>
                        <button
                          phx-click="group_cancel_invite"
                          phx-value-invite_id={inv.id}
                          class="btn btn-xs btn-outline btn-error"
                          data-confirm={gettext("Cancel?")}
                        >
                          {gettext("Cancel")}
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("groups_tab", %{"tab" => tab}, socket) do
    socket = assign(socket, :groups_tab, tab)

    # Stream inserts are consumed by renders even while the browse table is
    # hidden, so refill it when the sub-tab becomes visible.
    socket = if tab == "browse", do: reload_browse_groups(socket), else: socket

    {:noreply, socket}
  end

  def handle_event("groups_toggle_create", _params, socket) do
    show = !socket.assigns.groups_show_create

    form =
      if show,
        do: to_form(Groups.change_group(%Group{}), as: :group),
        else: socket.assigns.create_group_form

    {:noreply, assign(socket, groups_show_create: show, create_group_form: form)}
  end

  def handle_event("group_validate_create", %{"group" => group_params}, socket) do
    changeset =
      Groups.change_group(%Group{}, group_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, create_group_form: to_form(changeset, as: :group))}
  end

  def handle_event("group_create", %{"group" => group_params}, socket) do
    user = Shared.current_user(socket)

    case Groups.create_group(user.id, group_params) do
      {:ok, _group} ->
        {:noreply,
         socket
         |> put_success_flash()
         |> assign(:groups_show_create, false)
         |> assign(:create_group_form, to_form(Groups.change_group(%Group{}), as: :group))
         |> assign(:groups_tab, "my_groups")
         |> reload_groups()}

      {:error, changeset} ->
        changeset = Map.put(changeset, :action, :validate)

        {:noreply,
         socket
         |> put_flash(:error, gettext("Failed"))
         |> assign(create_group_form: to_form(changeset, as: :group))}
    end
  end

  def handle_event("group_leave", %{"group_id" => gid}, socket) do
    user = Shared.current_user(socket)
    gid = to_string(gid)

    case Groups.leave_group(user.id, gid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_success_flash()
         |> assign(:group_detail, nil)
         |> assign(:group_detail_role, nil)
         |> reload_groups()}

      {:error, reason} ->
        {:noreply, put_failure_flash(socket, reason)}
    end
  end

  def handle_event("group_join", %{"group_id" => gid}, socket) do
    user = Shared.current_user(socket)
    gid = to_string(gid)

    case Groups.join_group(user.id, gid) do
      {:ok, _} ->
        {:noreply, socket |> put_success_flash() |> reload_groups()}

      {:error, reason} ->
        {:noreply, put_failure_flash(socket, reason)}
    end
  end

  def handle_event("group_request_join", %{"group_id" => gid}, socket) do
    user = Shared.current_user(socket)
    gid = to_string(gid)

    case Groups.request_join(user.id, gid) do
      {:ok, _} ->
        {:noreply, socket |> put_success_flash() |> reload_groups()}

      {:error, reason} ->
        {:noreply, put_failure_flash(socket, reason)}
    end
  end

  def handle_event("group_accept_invite", %{"invite_id" => iid}, socket) do
    user = Shared.current_user(socket)
    iid = to_string(iid)

    case Groups.accept_invite(user.id, iid) do
      {:ok, _} ->
        {:noreply, socket |> put_success_flash() |> reload_groups()}

      {:error, reason} ->
        {:noreply, put_failure_flash(socket, reason)}
    end
  end

  def handle_event("group_decline_invite", %{"invite_id" => iid}, socket) do
    user = Shared.current_user(socket)
    iid = to_string(iid)

    case Groups.decline_invite(user.id, iid) do
      :ok ->
        {:noreply, socket |> put_success_flash() |> reload_groups()}

      {:error, reason} ->
        {:noreply, put_failure_flash(socket, reason)}
    end
  end

  def handle_event("group_cancel_request", %{"request_id" => rid}, socket) do
    user = Shared.current_user(socket)
    rid = to_string(rid)

    case Groups.cancel_join_request(user.id, rid) do
      {:ok, _} ->
        {:noreply, socket |> put_success_flash() |> reload_groups()}

      {:error, reason} ->
        {:noreply, put_failure_flash(socket, reason)}
    end
  end

  def handle_event("group_cancel_invite", %{"invite_id" => iid}, socket) do
    user = Shared.current_user(socket)
    iid = to_string(iid)

    case Groups.cancel_invite(user.id, iid) do
      :ok ->
        {:noreply, socket |> put_success_flash() |> reload_groups()}

      {:error, reason} ->
        {:noreply, put_failure_flash(socket, reason)}
    end
  end

  def handle_event("group_approve_request", %{"request_id" => rid}, socket) do
    user = Shared.current_user(socket)
    rid = to_string(rid)

    case Groups.approve_join_request(user.id, rid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_success_flash()
         |> assign(
           :group_join_requests,
           Enum.reject(socket.assigns.group_join_requests, &(&1.id == rid))
         )
         |> reload_group_members()
         |> reload_groups()}

      {:error, reason} ->
        {:noreply, put_failure_flash(socket, reason)}
    end
  end

  def handle_event("group_reject_request", %{"request_id" => rid}, socket) do
    user = Shared.current_user(socket)
    rid = to_string(rid)

    case Groups.reject_join_request(user.id, rid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_success_flash()
         |> assign(
           :group_join_requests,
           Enum.reject(socket.assigns.group_join_requests, &(&1.id == rid))
         )}

      {:error, reason} ->
        {:noreply, put_failure_flash(socket, reason)}
    end
  end

  def handle_event("browse_groups_filter", %{"browse_groups" => filter_params}, socket) do
    title = String.trim(filter_params["title"] || "")
    type = filter_params["type"] || ""

    filters = %{}
    filters = if title != "", do: Map.put(filters, "title", title), else: filters
    filters = if type != "", do: Map.put(filters, "type", type), else: filters

    {:noreply,
     socket
     |> assign(:browse_groups_filters, filters)
     |> assign(:browse_groups_page, 1)
     |> assign(:browse_groups_form, to_form(filter_params, as: :browse_groups))
     |> reload_browse_groups()}
  end

  def handle_event("browse_groups_clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:browse_groups_filters, %{})
     |> assign(:browse_groups_page, 1)
     |> assign(:browse_groups_form, to_form(%{"title" => "", "type" => ""}, as: :browse_groups))
     |> reload_browse_groups()}
  end

  def handle_event("browse_groups_prev", _params, socket) do
    page = max(1, socket.assigns.browse_groups_page - 1)
    {:noreply, socket |> assign(:browse_groups_page, page) |> reload_browse_groups()}
  end

  def handle_event("browse_groups_next", _params, socket) do
    page = socket.assigns.browse_groups_page + 1
    {:noreply, socket |> assign(:browse_groups_page, page) |> reload_browse_groups()}
  end

  def handle_event("group_view_detail", %{"group_id" => gid}, socket) do
    gid = to_string(gid)
    handle_group_view_detail(socket, gid)
  end

  def handle_event("group_close_detail", _params, socket) do
    {:noreply,
     socket
     |> assign(:group_detail, nil)
     |> assign(:group_detail_role, nil)
     |> assign(:group_members, [])
     |> assign(:group_members_total, 0)
     |> assign(:group_members_total_pages, 0)
     |> assign(:invite_search_query, "")
     |> assign(:invite_search_results, [])
     |> assign(:invite_friends, [])
     |> assign(:group_editing, false)
     |> assign(:group_edit_form, nil)
     |> assign(:group_join_requests, [])}
  end

  def handle_event("group_toggle_edit", _params, socket) do
    editing = !socket.assigns.group_editing

    form =
      if editing do
        group = socket.assigns.group_detail
        to_form(Groups.change_group(group), as: :group)
      else
        nil
      end

    {:noreply, assign(socket, group_editing: editing, group_edit_form: form)}
  end

  def handle_event("group_validate_edit", %{"group" => group_params}, socket) do
    changeset =
      Groups.change_group(socket.assigns.group_detail, group_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, group_edit_form: to_form(changeset, as: :group))}
  end

  def handle_event("group_save_edit", %{"group" => group_params}, socket) do
    user = Shared.current_user(socket)
    group = socket.assigns.group_detail

    case Groups.update_group(user.id, group.id, group_params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> assign(:group_detail, updated)
         |> assign(:group_editing, false)
         |> assign(:group_edit_form, nil)
         |> reload_groups()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, group_edit_form: to_form(changeset, as: :group))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed") <> ": " <> inspect(reason))}
    end
  end

  def handle_event("group_kick", %{"group_id" => gid, "user_id" => uid}, socket) do
    user = Shared.current_user(socket)
    gid = to_string(gid)
    uid = to_string(uid)

    case Groups.kick_member(user.id, gid, uid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> reload_groups()
         |> reload_group_members()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed") <> ": " <> inspect(reason))}
    end
  end

  def handle_event("group_promote", %{"group_id" => gid, "user_id" => uid}, socket) do
    user = Shared.current_user(socket)
    gid = to_string(gid)
    uid = to_string(uid)

    case Groups.promote_member(user.id, gid, uid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> reload_group_members()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed") <> ": " <> inspect(reason))}
    end
  end

  def handle_event("group_demote", %{"group_id" => gid, "user_id" => uid}, socket) do
    user = Shared.current_user(socket)
    gid = to_string(gid)
    uid = to_string(uid)

    case Groups.demote_member(user.id, gid, uid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> reload_group_members()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed") <> ": " <> inspect(reason))}
    end
  end

  def handle_event("group_members_prev", _params, socket) do
    page = max(1, socket.assigns.group_members_page - 1)
    {:noreply, socket |> assign(:group_members_page, page) |> reload_group_members()}
  end

  def handle_event("group_members_next", _params, socket) do
    page = socket.assigns.group_members_page + 1
    {:noreply, socket |> assign(:group_members_page, page) |> reload_group_members()}
  end

  def handle_event("group_invite_search", %{"value" => query}, socket) do
    query = String.trim(query)

    results =
      if query == "" do
        []
      else
        group_id = socket.assigns.group_detail.id

        all_member_ids =
          Groups.get_group_members(group_id)
          |> Enum.map(& &1.user_id)
          |> MapSet.new()

        Accounts.search_users(query, page: 1, page_size: 10)
        |> Enum.reject(fn u -> MapSet.member?(all_member_ids, u.id) end)
      end

    {:noreply,
     socket
     |> assign(:invite_search_query, query)
     |> assign(:invite_search_results, results)}
  end

  def handle_event("group_invite_user", %{"group_id" => gid, "user_id" => uid}, socket) do
    user = Shared.current_user(socket)
    gid = to_string(gid)
    uid = to_string(uid)

    case Groups.invite_to_group(user.id, gid, uid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> assign(
           :invite_search_results,
           Enum.reject(socket.assigns.invite_search_results, &(&1.id == uid))
         )
         |> assign(
           :invite_friends,
           Enum.reject(socket.assigns.invite_friends, &(&1.id == uid))
         )}

      {:error, :already_member} ->
        {:noreply, put_flash(socket, :error, gettext("Failed"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed") <> ": " <> inspect(reason))}
    end
  end

  def handle_event("group_notify", %{"notify" => notify_params}, socket) do
    user = Shared.current_user(socket)
    group = socket.assigns.group_detail
    content = String.trim(Map.get(notify_params, "content", ""))
    title = String.trim(Map.get(notify_params, "title", ""))

    if group && content != "" do
      metadata = if title != "", do: %{"title" => title}, else: %{}

      case Groups.notify_group(user.id, group.id, content, metadata) do
        {:ok, _sent} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Success."))
           |> assign(:group_notify_form, to_form(%{"content" => "", "title" => ""}, as: :notify))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, gettext("Failed") <> ": " <> inspect(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Cannot be empty."))}
    end
  end

  defp put_success_flash(socket), do: LiveHelpers.put_success(socket, gettext("Success."))

  defp put_failure_flash(socket, reason) do
    LiveHelpers.put_failure(socket, LiveHelpers.failure_message(gettext("Failed"), reason))
  end

  @doc "Reloads the user's group lists (mine, invitations, requests, browse)."
  def reload_groups(socket) do
    user = Shared.current_user(socket)

    if user do
      my_groups = Groups.list_user_groups_with_role(user.id)
      groups_count = Groups.count_user_groups(user.id)
      invitations = Groups.list_invitations(user.id)
      pending_requests = Groups.list_user_pending_requests(user.id)
      sent_invitations = Groups.list_sent_invitations(user.id)

      socket
      |> assign(:my_groups, my_groups)
      |> assign(:groups_count, groups_count)
      |> assign(:group_invitations, invitations)
      |> assign(:group_pending_requests, pending_requests)
      |> assign(:group_sent_invitations, sent_invitations)
      |> assign(:group_unread_counts, %{})
      |> reload_browse_groups()
    else
      socket
    end
  end

  defp reload_browse_groups(socket) do
    page = socket.assigns.browse_groups_page
    page_size = socket.assigns.browse_groups_page_size
    filters = socket.assigns.browse_groups_filters

    groups = Groups.list_groups(filters, page: page, page_size: page_size)
    total = Groups.count_list_groups(filters)
    total_pages = if page_size > 0, do: div(total + page_size - 1, page_size), else: 0

    socket
    |> stream(:browse_groups, groups, reset: true, dom_id: &"browse-group-#{&1.id}")
    |> assign(:browse_groups_total, total)
    |> assign(:browse_groups_total_pages, total_pages)
  end

  defp handle_group_view_detail(socket, gid) do
    user = Shared.current_user(socket)

    case Groups.get_group(gid) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Not found"))}

      group ->
        role =
          case Groups.get_membership(gid, user.id) do
            %{role: r} -> r
            _ -> nil
          end

        member_ids =
          Groups.get_group_members(gid) |> Enum.map(& &1.user_id) |> MapSet.new()

        friends_not_in_group =
          Friends.list_friends_for_user(user.id)
          |> Enum.reject(fn f -> MapSet.member?(member_ids, f.id) end)

        join_requests = load_join_requests(role, user.id, gid)

        {:noreply,
         socket
         |> assign(:group_detail, group)
         |> assign(:group_detail_role, role)
         |> assign(:group_members_page, 1)
         |> assign(:invite_search_query, "")
         |> assign(:invite_search_results, [])
         |> assign(:invite_friends, friends_not_in_group)
         |> assign(:group_join_requests, join_requests)
         |> reload_group_members()}
    end
  end

  defp load_join_requests("admin", user_id, group_id) do
    case Groups.list_join_requests(user_id, group_id) do
      {:ok, reqs} -> reqs
      _ -> []
    end
  end

  defp load_join_requests(_role, _user_id, _group_id), do: []

  defp reload_group_members(socket) do
    group = socket.assigns.group_detail

    if group do
      page = socket.assigns.group_members_page
      page_size = socket.assigns.group_members_page_size

      members = Groups.get_group_members_paginated(group.id, page: page, page_size: page_size)
      total = Groups.count_group_members(group.id)
      total_pages = if page_size > 0, do: div(total + page_size - 1, page_size), else: 0

      socket
      |> assign(:group_members, members)
      |> assign(:group_members_total, total)
      |> assign(:group_members_total_pages, total_pages)
    else
      socket
    end
  end
end
