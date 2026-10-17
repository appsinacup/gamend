defmodule GamendWeb.AdminLive.Groups do
  use GamendWeb, :live_view

  alias Gamend.Groups
  alias GamendWeb.AdminLive.Shared
  alias GamendWeb.LiveHelpers

  @impl true
  def mount(_params, _session, socket) do
    Groups.subscribe_groups()

    socket =
      socket
      |> assign(:groups_page, 1)
      |> assign(:groups_page_size, 25)
      |> assign(:filters, %{})
      |> assign(:sort_by, "updated_at")
      |> assign(:selected_group, nil)
      |> assign(:form, nil)
      |> assign(:members, [])
      |> assign(:selected_ids, MapSet.new())
      |> reload_groups()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-surface mb-4">&larr; Back to Admin</.link>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="card-title">Groups ({@count})</h2>
              <button
                type="button"
                phx-click="bulk_delete"
                data-confirm={
                  ngettext(
                    "Delete %{count} selected group?",
                    "Delete %{count} selected groups?",
                    MapSet.size(@selected_ids)
                  )
                }
                class="btn btn-sm btn-outline btn-error"
                disabled={MapSet.size(@selected_ids) == 0}
              >
                Delete selected ({MapSet.size(@selected_ids)})
              </button>
            </div>

            <form phx-change="filter" phx-no-unused-field id="groups-filter-form">
              <div class="flex items-center gap-3 mt-4">
                <label class="text-sm text-muted">Sort by:</label>
                <select
                  name="sort_by"
                  class="select select-bordered select-sm"
                  phx-change="sort"
                >
                  <option value="updated_at" selected={@sort_by == "updated_at"}>
                    Updated (newest)
                  </option>
                  <option value="updated_at_asc" selected={@sort_by == "updated_at_asc"}>
                    Updated (oldest)
                  </option>
                  <option value="inserted_at" selected={@sort_by == "inserted_at"}>
                    Created (newest)
                  </option>
                  <option value="inserted_at_asc" selected={@sort_by == "inserted_at_asc"}>
                    Created (oldest)
                  </option>
                  <option value="title" selected={@sort_by == "title"}>Title (A-Z)</option>
                  <option value="title_desc" selected={@sort_by == "title_desc"}>
                    Title (Z-A)
                  </option>
                  <option value="max_members" selected={@sort_by == "max_members"}>
                    Max members (desc)
                  </option>
                  <option value="max_members_asc" selected={@sort_by == "max_members_asc"}>
                    Max members (asc)
                  </option>
                </select>
              </div>

              <div class="overflow-x-auto mt-4">
                <table class="table table-zebra w-full min-w-[48rem]">
                  <thead>
                    <tr>
                      <th class="w-10">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-sm"
                          phx-click="toggle_select_all"
                          checked={@groups != [] && MapSet.size(@selected_ids) == length(@groups)}
                        />
                      </th>
                      <th>ID</th>
                      <th>Title</th>
                      <th>Type</th>
                      <th>Members (Cap)</th>
                      <th>Creator</th>
                      <th>Created</th>
                      <th>Updated</th>
                      <th>Actions</th>
                    </tr>
                    <tr>
                      <th></th>
                      <th></th>
                      <th>
                        <input
                          type="text"
                          name="title"
                          value={@filters["title"]}
                          class="input input-bordered input-xs w-full"
                          placeholder="Filter..."
                          phx-debounce="300"
                        />
                      </th>
                      <th>
                        <select name="type" class="select select-bordered select-xs w-full">
                          <option value="" selected={@filters["type"] == ""}>All</option>
                          <option value="public" selected={@filters["type"] == "public"}>
                            Public
                          </option>
                          <option value="private" selected={@filters["type"] == "private"}>
                            Private
                          </option>
                          <option value="hidden" selected={@filters["type"] == "hidden"}>
                            Hidden
                          </option>
                        </select>
                      </th>
                      <th class="flex gap-1">
                        <input
                          type="number"
                          name="min_members"
                          value={@filters["min_members"]}
                          class="input input-bordered input-xs w-20"
                          placeholder="Min cap"
                          phx-debounce="300"
                        />
                        <input
                          type="number"
                          name="max_members"
                          value={@filters["max_members"]}
                          class="input input-bordered input-xs w-20"
                          placeholder="Max cap"
                          phx-debounce="300"
                        />
                      </th>
                      <th></th>
                      <th></th>
                      <th></th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={g <- @groups} id={"admin-group-" <> to_string(g.id)}>
                      <td class="w-10">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-sm"
                          phx-click="toggle_select"
                          phx-value-id={g.id}
                          checked={MapSet.member?(@selected_ids, g.id)}
                        />
                      </td>
                      <td class="font-mono text-sm">{g.id}</td>
                      <td class="text-sm">{g.title || "-"}</td>
                      <td class="text-sm">
                        <%= cond do %>
                          <% g.type == "public" -> %>
                            <span class="badge badge-success badge-sm">Public</span>
                          <% g.type == "private" -> %>
                            <span class="badge badge-warning badge-sm">Private</span>
                          <% true -> %>
                            <span class="badge badge-info badge-sm">Hidden</span>
                        <% end %>
                      </td>
                      <td class="text-sm">
                        {Groups.count_group_members(g.id)} / {g.max_members}
                      </td>
                      <td class="font-mono text-sm">{g.creator_id}</td>
                      <td class="text-sm">
                        <.timestamp at={g.inserted_at} />
                      </td>
                      <td class="text-sm">
                        <.timestamp at={g.updated_at} />
                      </td>
                      <td class="text-sm">
                        <div class="flex flex-wrap gap-1">
                          <button
                            type="button"
                            phx-click="view_members"
                            phx-value-id={g.id}
                            class="btn btn-xs btn-outline btn-accent"
                          >
                            Members
                          </button>
                          <button
                            type="button"
                            phx-click="edit_group"
                            phx-value-id={g.id}
                            class="btn btn-xs btn-outline btn-info"
                          >
                            Edit
                          </button>
                          <button
                            type="button"
                            phx-click="delete_group"
                            phx-value-id={g.id}
                            data-confirm="Are you sure?"
                            class="btn btn-xs btn-outline btn-error"
                          >
                            Delete
                          </button>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </form>

            <div class="mt-4">
              <.pagination
                page={@groups_page}
                total_pages={@groups_total_pages}
                total_count={@count}
                page_size={@groups_page_size}
                on_prev="admin_groups_prev"
                on_next="admin_groups_next"
                on_page_size="admin_groups_page_size"
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>

    <%!-- Edit modal --%>
    <%= if @selected_group && @form do %>
      <div class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Edit Group</h3>

          <.form for={@form} id="group-edit-form" phx-submit="save_group">
            <.input field={@form[:title]} type="text" label="Title (unique)" />
            <.input field={@form[:description]} type="text" label="Description" />
            <.input field={@form[:icon_url]} type="text" label="Icon URL (optional)" />
            <.input
              field={@form[:type]}
              type="select"
              label="Type"
              options={[{"Public", "public"}, {"Private", "private"}, {"Hidden", "hidden"}]}
            />
            <.input field={@form[:max_members]} type="number" label="Max members" />

            <div class="form-control">
              <label class="label">Metadata (JSON)</label>
              <textarea name="group[metadata]" class="textarea textarea-bordered" rows="4"><%= Jason.encode!(@selected_group.metadata || %{}) %></textarea>
            </div>

            <div class="mt-4 text-sm text-muted space-y-1">
              <div>
                Creator: <span class="font-mono">{@selected_group.creator_id}</span>
              </div>
              <div>
                Created:
                <span class="font-mono">
                  <.timestamp at={@selected_group.inserted_at} format="full" />
                </span>
              </div>
              <div>
                Updated:
                <span class="font-mono">
                  <.timestamp at={@selected_group.updated_at} format="full" />
                </span>
              </div>
            </div>

            <div class="modal-action">
              <button type="button" phx-click="cancel_edit" class="btn">Cancel</button>
              <button type="submit" class="btn btn-primary">Save</button>
            </div>
          </.form>
        </div>
      </div>
    <% end %>

    <%!-- Members modal --%>
    <%= if @selected_group && @members != [] && @form == nil do %>
      <div class="modal modal-open">
        <div class="modal-box max-w-2xl">
          <h3 class="font-bold text-lg">
            Members of "{@selected_group.title}" ({length(@members)})
          </h3>

          <div class="overflow-x-auto mt-4">
            <table class="table table-zebra w-full min-w-[36rem]">
              <thead>
                <tr>
                  <th>User ID</th>
                  <th>Name</th>
                  <th>Role</th>
                  <th>Joined</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={m <- @members} id={"member-" <> to_string(m.id)}>
                  <td class="font-mono text-sm">{m.user_id}</td>
                  <td class="text-sm">{user_display(m.user)}</td>
                  <td class="text-sm">
                    <%= if m.role == "admin" do %>
                      <span class="badge badge-primary badge-sm">Admin</span>
                    <% else %>
                      <span class="badge badge-ghost badge-sm">Member</span>
                    <% end %>
                  </td>
                  <td class="text-sm">
                    <.timestamp at={m.inserted_at} />
                  </td>
                  <td class="text-sm">
                    <div class="flex flex-wrap gap-1">
                      <%= if m.role == "member" do %>
                        <button
                          type="button"
                          phx-click="promote_member"
                          phx-value-group-id={m.group_id}
                          phx-value-user-id={m.user_id}
                          class="btn btn-xs btn-outline btn-info"
                        >
                          Promote
                        </button>
                      <% else %>
                        <button
                          type="button"
                          phx-click="demote_member"
                          phx-value-group-id={m.group_id}
                          phx-value-user-id={m.user_id}
                          class="btn btn-xs btn-outline btn-warning"
                        >
                          Demote
                        </button>
                      <% end %>
                      <button
                        type="button"
                        phx-click="kick_member"
                        phx-value-group-id={m.group_id}
                        phx-value-user-id={m.user_id}
                        data-confirm={"Kick #{user_display(m.user)} from the group?"}
                        class="btn btn-xs btn-outline btn-error"
                      >
                        Kick
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="modal-action">
            <button type="button" phx-click="close_members" class="btn">Close</button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("filter", params, socket) do
    # The sort select is inside the filter form, so extract it
    sort_by = Map.get(params, "sort_by", socket.assigns[:sort_by] || "updated_at")

    {:noreply,
     socket
     |> assign(:filters, Map.drop(params, ["sort_by"]))
     |> assign(:sort_by, sort_by)
     |> assign(:groups_page, 1)
     |> reload_groups()}
  end

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:groups_page, 1)
     |> reload_groups()}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = to_string(id)
    selected = socket.assigns[:selected_ids] || MapSet.new()

    selected =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    {:noreply,
     socket
     |> assign(:selected_ids, selected)
     |> sync_selected_ids(group_ids(socket.assigns.groups))}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    groups = socket.assigns.groups || []
    ids = group_ids(groups)
    selected = socket.assigns[:selected_ids] || MapSet.new()

    selected =
      if ids != [] and MapSet.size(selected) == length(ids) do
        MapSet.new()
      else
        MapSet.new(ids)
      end

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("bulk_delete", _params, socket) do
    ids = socket.assigns[:selected_ids] |> MapSet.to_list()

    {deleted, failed} =
      Enum.reduce(ids, {0, 0}, fn id, {d, f} ->
        case Groups.admin_delete_group(id) do
          {:ok, _} -> {d + 1, f}
          {:error, _} -> {d, f + 1}
        end
      end)

    socket = assign(socket, :selected_ids, MapSet.new())

    socket =
      cond do
        failed == 0 ->
          put_flash(
            socket,
            :info,
            ngettext("Deleted %{count} group", "Deleted %{count} groups", deleted)
          )

        deleted == 0 ->
          put_flash(socket, :error, "Failed to delete selected groups")

        true ->
          put_flash(
            socket,
            :error,
            ngettext(
              "Deleted %{count} group; %{failed} failed",
              "Deleted %{count} groups; %{failed} failed",
              deleted,
              failed: failed
            )
          )
      end

    {:noreply, reload_groups(socket)}
  end

  @impl true
  def handle_event("edit_group", %{"id" => id}, socket) do
    Shared.with_record(socket, Groups.get_group(to_string(id)), fn group ->
      form = group |> Groups.change_group() |> to_form(as: "group")

      {:noreply,
       socket
       |> assign(:selected_group, group)
       |> assign(:form, form)
       |> assign(:members, [])}
    end)
  end

  @impl true
  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_group, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("save_group", %{"group" => params}, socket) do
    group = socket.assigns.selected_group

    # Text that is not a JSON object is refused rather than saved as %{},
    # which would wipe the group's metadata behind a success flash.
    case normalize_metadata(params) do
      {:ok, params} -> do_save_group(socket, group, params)
      :error -> {:noreply, put_flash(socket, :error, "Metadata must be a JSON object")}
    end
  end

  @impl true
  def handle_event("delete_group", %{"id" => id}, socket) do
    group_id = to_string(id)

    case Groups.admin_delete_group(group_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Group deleted")
         |> reload_groups()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete group")}
    end
  end

  @impl true
  def handle_event("view_members", %{"id" => id}, socket) do
    Shared.with_record(socket, Groups.get_group(to_string(id)), fn group ->
      {:noreply,
       socket
       |> assign(:selected_group, group)
       |> assign(:members, Groups.get_group_members(group.id))
       |> assign(:form, nil)}
    end)
  end

  @impl true
  def handle_event("close_members", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_group, nil)
     |> assign(:members, [])}
  end

  @impl true
  def handle_event("promote_member", %{"group-id" => gid, "user-id" => uid}, socket) do
    run_member_action(
      socket,
      gid,
      uid,
      &Groups.promote_member/3,
      "User promoted to admin",
      "Promote failed"
    )
  end

  @impl true
  def handle_event("demote_member", %{"group-id" => gid, "user-id" => uid}, socket) do
    run_member_action(
      socket,
      gid,
      uid,
      &Groups.demote_member/3,
      "User demoted to member",
      "Demote failed"
    )
  end

  @impl true
  def handle_event("kick_member", %{"group-id" => gid, "user-id" => uid}, socket) do
    run_member_action(socket, gid, uid, &Groups.kick_member/3, "User kicked", "Kick failed")
  end

  @impl true
  def handle_event("admin_groups_prev", _params, socket) do
    page = max(1, (socket.assigns[:groups_page] || 1) - 1)
    {:noreply, socket |> assign(:groups_page, page) |> reload_groups()}
  end

  @impl true
  def handle_event("admin_groups_next", _params, socket) do
    page = (socket.assigns[:groups_page] || 1) + 1
    {:noreply, socket |> assign(:groups_page, page) |> reload_groups()}
  end

  @impl true
  def handle_event("admin_groups_page_size", %{"size" => size}, socket) do
    socket =
      LiveHelpers.put_page_size(socket, size,
        min: 25,
        size_key: :groups_page_size,
        page_key: :groups_page
      )

    {:noreply, reload_groups(socket)}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:group_created, :group_updated, :group_deleted] do
    {:noreply, reload_groups(socket)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp reload_groups(socket) do
    page = socket.assigns[:groups_page] || 1
    page_size = socket.assigns[:groups_page_size] || 25
    filters = socket.assigns[:filters] || %{}
    sort_by = socket.assigns[:sort_by] || "updated_at"

    groups =
      Groups.list_all_groups(filters,
        page: page,
        page_size: page_size,
        sort_by: sort_by
      )

    total_count = Groups.count_all_groups(filters)

    total_pages =
      LiveHelpers.total_pages(total_count, page_size)

    socket
    |> assign(:groups, groups)
    |> assign(:count, total_count)
    |> assign(:groups_total_pages, total_pages)
    |> assign(:groups_page, page)
    |> sync_selected_ids(group_ids(groups))
  end

  defp group_ids(groups) when is_list(groups), do: Enum.map(groups, & &1.id)

  defp sync_selected_ids(socket, ids) when is_list(ids) do
    selected = socket.assigns[:selected_ids] || MapSet.new()
    allowed = MapSet.new(ids)
    assign(socket, :selected_ids, MapSet.intersection(selected, allowed))
  end

  defp normalize_metadata(params) do
    case Map.get(params, "metadata") do
      nil ->
        {:ok, params}

      s when is_binary(s) ->
        case String.trim(s) do
          "" ->
            {:ok, Map.put(params, "metadata", %{})}

          trimmed ->
            case Jason.decode(trimmed) do
              {:ok, map} when is_map(map) -> {:ok, Map.put(params, "metadata", map)}
              _ -> :error
            end
        end

      other ->
        {:ok, Map.put(params, "metadata", other)}
    end
  end

  defp do_save_group(socket, group, params) do
    case Groups.admin_update_group(group, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Group updated")
         |> assign(:selected_group, nil)
         |> assign(:form, nil)
         |> reload_groups()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "group"))}
    end
  end

  # The Groups member commands authorise an acting group admin, and the console
  # has none of its own. It used to pass `creator_id` unconditionally, which
  # crashed on a group whose creator was deleted (nil id), failed with
  # `:not_admin` once the creator was demoted, and reported "cannot kick self"
  # when the target WAS the creator. Act as the creator while they are still an
  # admin, else as any other admin, and never as the target.
  defp run_member_action(socket, gid, uid, command, success, failure) do
    user_id = to_string(uid)

    Shared.with_record(socket, Groups.get_group(to_string(gid)), fn group ->
      case acting_admin_id(group, Groups.get_group_members(group.id), user_id) do
        nil ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "#{failure}: the group has no other admin to act as"
           )}

        admin_id ->
          case command.(admin_id, group.id, user_id) do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(:members, Groups.get_group_members(group.id))
               |> put_flash(:info, success)}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "#{failure}: #{member_error(reason)}")}
          end
      end
    end)
  end

  defp acting_admin_id(group, members, target_id) do
    admins = for %{role: "admin", user_id: id} <- members, id != target_id, do: id

    if group.creator_id in admins, do: group.creator_id, else: List.first(admins)
  end

  defp member_error(:last_admin), do: "this is the group's last admin"
  defp member_error(:not_member), do: "the user is not a member of this group"
  defp member_error(:already_admin), do: "the user is already an admin"
  defp member_error(:already_member), do: "the user is already a member"
  defp member_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp member_error(reason), do: inspect(reason)
end
