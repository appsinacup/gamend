defmodule GameServerWeb.AdminLive.Lobbies do
  use GameServerWeb, :live_view

  alias GameServer.Lobbies
  alias GameServer.Lobbies.SpectatorTracker
  alias GameServer.ReadyChecks

  @impl true
  def mount(_params, _session, socket) do
    Lobbies.subscribe_lobbies()

    socket =
      socket
      |> assign(:lobbies_page, 1)
      |> assign(:lobbies_page_size, 25)
      |> assign(:filters, %{})
      |> assign(:sort_by, "updated_at")
      |> assign(:selected_lobby, nil)
      |> assign(:form, nil)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:members, [])
      |> assign(:ready_check, nil)
      |> assign(:show_members, false)
      |> assign(:show_create, false)
      |> assign(
        :create_form,
        to_form(%{"host_id" => "", "title" => "", "max_users" => "10"}, as: "lobby")
      )
      |> assign(:add_member_id, "")
      |> reload_lobbies()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">← Back to Admin</.link>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="card-title">Lobbies ({@count})</h2>
              <div class="flex flex-wrap gap-2">
                <.link navigate={~p"/admin/lobbies/live"} class="btn btn-sm btn-outline">
                  Open lobby page
                </.link>
                <button
                  type="button"
                  phx-click="show_create"
                  class="btn btn-sm btn-outline btn-primary"
                  id="create-lobby-btn"
                >
                  + Create Lobby
                </button>
                <button
                  type="button"
                  phx-click="bulk_delete"
                  data-confirm={"Delete #{MapSet.size(@selected_ids)} selected lobbies?"}
                  class="btn btn-sm btn-outline btn-error"
                  disabled={MapSet.size(@selected_ids) == 0}
                >
                  Delete selected ({MapSet.size(@selected_ids)})
                </button>
              </div>
            </div>

            <form phx-change="filter" id="lobbies-filter-form">
              <div class="flex items-center gap-3 mt-4">
                <label class="text-sm text-base-content/70">Sort by:</label>
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
                  <option value="max_users" selected={@sort_by == "max_users"}>
                    Max users (desc)
                  </option>
                  <option value="max_users_asc" selected={@sort_by == "max_users_asc"}>
                    Max users (asc)
                  </option>
                </select>
              </div>

              <div class="overflow-x-auto mt-4">
                <table class="table table-zebra w-full min-w-[56rem]">
                  <thead>
                    <tr>
                      <th class="w-10">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-sm"
                          phx-click="toggle_select_all"
                          checked={@lobbies != [] && MapSet.size(@selected_ids) == length(@lobbies)}
                        />
                      </th>
                      <th>ID</th>
                      <th>Title</th>
                      <th>Host ID</th>
                      <th>Users (Cap)</th>
                      <th>Spectators</th>
                      <th>Hidden</th>
                      <th>Locked</th>
                      <th>State</th>
                      <th>Password</th>
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
                      <th></th>
                      <th class="flex gap-1">
                        <input
                          type="number"
                          name="min_users"
                          value={@filters["min_users"]}
                          class="input input-bordered input-xs w-16"
                          placeholder="Min"
                          phx-debounce="300"
                        />
                        <input
                          type="number"
                          name="max_users"
                          value={@filters["max_users"]}
                          class="input input-bordered input-xs w-16"
                          placeholder="Max"
                          phx-debounce="300"
                        />
                      </th>
                      <th></th>
                      <th>
                        <select name="is_hidden" class="select select-bordered select-xs w-full">
                          <option value="" selected={@filters["is_hidden"] == ""}>All</option>
                          <option value="true" selected={@filters["is_hidden"] == "true"}>
                            Hidden
                          </option>
                          <option value="false" selected={@filters["is_hidden"] == "false"}>
                            Public
                          </option>
                        </select>
                      </th>
                      <th>
                        <select name="is_locked" class="select select-bordered select-xs w-full">
                          <option value="" selected={@filters["is_locked"] == ""}>All</option>
                          <option value="true" selected={@filters["is_locked"] == "true"}>
                            Locked
                          </option>
                          <option value="false" selected={@filters["is_locked"] == "false"}>
                            Open
                          </option>
                        </select>
                      </th>
                      <th>
                        <input
                          type="text"
                          name="state"
                          value={@filters["state"] || ""}
                          placeholder="state"
                          class="input input-bordered input-xs w-full"
                        />
                      </th>
                      <th>
                        <select name="has_password" class="select select-bordered select-xs w-full">
                          <option value="" selected={@filters["has_password"] == ""}>All</option>
                          <option value="true" selected={@filters["has_password"] == "true"}>
                            Yes
                          </option>
                          <option value="false" selected={@filters["has_password"] == "false"}>
                            No
                          </option>
                        </select>
                      </th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={l <- @lobbies} id={"admin-lobby-" <> to_string(l.id)}>
                      <td class="w-10">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-sm"
                          phx-click="toggle_select"
                          phx-value-id={l.id}
                          checked={MapSet.member?(@selected_ids, l.id)}
                        />
                      </td>
                      <td class="font-mono text-sm">{l.id}</td>
                      <td class="text-sm">{l.title || "-"}</td>
                      <td class="font-mono text-sm">{l.host_id}</td>
                      <td class="text-sm">{length(l.users || [])} / {l.max_users}</td>
                      <td class="text-sm font-mono">{Map.get(@spectator_counts, l.id, 0)}</td>
                      <td class="text-sm">
                        <%= if l.is_hidden do %>
                          <span class="badge badge-info badge-sm">Hidden</span>
                        <% else %>
                          <span class="badge badge-ghost badge-sm">Public</span>
                        <% end %>
                      </td>
                      <td class="text-sm">
                        <%= if l.is_locked do %>
                          <span class="badge badge-warning badge-sm">Locked</span>
                        <% else %>
                          <span class="badge badge-ghost badge-sm">Open</span>
                        <% end %>
                      </td>
                      <td class="text-sm">
                        <span class="badge badge-ghost badge-sm font-mono">{l.state}</span>
                      </td>
                      <td class="text-sm">
                        <%= if l.password_hash do %>
                          <span class="badge badge-success badge-sm">Yes</span>
                        <% else %>
                          <span class="badge badge-ghost badge-sm">No</span>
                        <% end %>
                      </td>
                      <td class="text-sm">
                        <.timestamp at={l.inserted_at} />
                      </td>
                      <td class="text-sm">
                        <.timestamp at={l.updated_at} />
                      </td>
                      <td class="text-sm">
                        <div class="flex flex-wrap gap-1">
                          <button
                            type="button"
                            phx-click="view_members"
                            phx-value-id={l.id}
                            class="btn btn-xs btn-outline btn-accent"
                          >
                            Members
                          </button>
                          <button
                            type="button"
                            phx-click="edit_lobby"
                            phx-value-id={l.id}
                            class="btn btn-xs btn-outline btn-info"
                          >
                            Edit
                          </button>
                          <button
                            type="button"
                            phx-click="delete_lobby"
                            phx-value-id={l.id}
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
                page={@lobbies_page}
                total_pages={@lobbies_total_pages}
                total_count={@count}
                page_size={@lobbies_page_size}
                on_prev="admin_lobbies_prev"
                on_next="admin_lobbies_next"
                on_page_size="admin_lobbies_page_size"
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>

    <%!-- Edit modal --%>
    <%= if @selected_lobby && @form do %>
      <div class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Edit Lobby</h3>

          <.form for={@form} id="lobby-form" phx-submit="save_lobby">
            <.input field={@form[:title]} type="text" label="Title" />
            <.input field={@form[:max_users]} type="number" label="Max users" />
            <.input field={@form[:is_hidden]} type="checkbox" label="Hidden" />
            <.input field={@form[:is_locked]} type="checkbox" label="Locked" />

            <div class="form-control">
              <label class="label">Password (leave blank to clear)</label>
              <input name="lobby[password]" type="text" class="input input-bordered" />
            </div>

            <div class="form-control">
              <label class="label">Metadata (JSON)</label>
              <textarea name="lobby[metadata]" class="textarea textarea-bordered" rows="4"><%= Jason.encode!(@selected_lobby.metadata || %{}) %></textarea>
            </div>

            <div class="mt-4 text-sm text-base-content/70 space-y-1">
              <div>
                Created:
                <span class="font-mono">
                  <.timestamp at={@selected_lobby.inserted_at} format="full" />
                </span>
              </div>
              <div>
                Updated:
                <span class="font-mono">
                  <.timestamp at={@selected_lobby.updated_at} format="full" />
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
    <%= if @selected_lobby && @show_members && @form == nil do %>
      <div class="modal modal-open">
        <div class="modal-box max-w-2xl">
          <h3 class="font-bold text-lg">
            Lobby #{@selected_lobby.id} members ({length(@members)})
          </h3>
          <p class="text-sm text-base-content/70 mt-1">
            Spectators: {Map.get(@spectator_counts, @selected_lobby.id, 0)}
            <span class="ml-2">State: <span class="font-mono">{@selected_lobby.state}</span></span>
          </p>

          <div :if={@ready_check} class="alert alert-info mt-3 py-2 text-sm">
            <span>
              {gettext("Ready check")}
              <span class="font-mono">{@ready_check.kind}</span>
              — {ready_summary(@ready_check)}
              <span :if={@ready_check.deadline_at}>
                · {gettext("deadline_at")} <.timestamp at={@ready_check.deadline_at} format="full" />
              </span>
            </span>
            <button
              type="button"
              phx-click="cancel_ready_check"
              phx-value-id={@ready_check.id}
              class="btn btn-xs"
            >
              {gettext("Cancel")}
            </button>
          </div>

          <div class="flex gap-2 mt-4">
            <input
              type="number"
              placeholder="User ID to add"
              value={@add_member_id}
              phx-keyup="update_add_member_id"
              class="input input-bordered input-sm w-40"
              id="add-member-input"
            />
            <button
              type="button"
              phx-click="add_member"
              class="btn btn-sm btn-outline btn-primary"
              id="add-member-btn"
            >
              Add Member
            </button>
          </div>

          <div class="overflow-x-auto mt-4">
            <table class="table table-zebra w-full">
              <thead>
                <tr>
                  <th>User ID</th>
                  <th>Name</th>
                  <th>Role</th>
                  <th>{gettext("Ready")}</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={m <- @members} id={"lobby-member-" <> to_string(m.id)}>
                  <td class="font-mono text-sm">{m.id}</td>
                  <td class="text-sm">{m.display_name || m.email || "-"}</td>
                  <td class="text-sm">
                    <%= if m.id == @selected_lobby.host_id do %>
                      <span class="badge badge-primary badge-sm">Host</span>
                    <% else %>
                      <span class="badge badge-ghost badge-sm">Member</span>
                    <% end %>
                  </td>
                  <td class="text-sm">
                    <span class={"badge badge-sm #{ready_state_class(@ready_check, m.id)}"}>
                      {member_ready_state(@ready_check, m.id)}
                    </span>
                  </td>
                  <td class="text-sm">
                    <button
                      type="button"
                      phx-click="kick_member"
                      phx-value-lobby-id={@selected_lobby.id}
                      phx-value-user-id={m.id}
                      data-confirm={"Remove user #{m.id} from lobby?"}
                      class="btn btn-xs btn-outline btn-error"
                    >
                      Remove
                    </button>
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

    <%!-- Create lobby modal --%>
    <%= if @show_create do %>
      <div class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Create Lobby</h3>

          <.form for={@create_form} id="lobby-create-form" phx-submit="create_lobby">
            <.input
              field={@create_form[:host_id]}
              type="text"
              label="Host User ID (optional)"
            />
            <.input
              field={@create_form[:title]}
              type="text"
              label="Title (optional, auto-generated if blank)"
            />
            <.input
              field={@create_form[:max_users]}
              type="number"
              label="Max users"
            />

            <div class="modal-action">
              <button type="button" phx-click="cancel_create" class="btn">Cancel</button>
              <button type="submit" class="btn btn-primary">Create</button>
            </div>
          </.form>
        </div>
      </div>
    <% end %>
    """
  end

  @impl true
  def handle_event("filter", params, socket) do
    sort_by = Map.get(params, "sort_by", socket.assigns[:sort_by] || "updated_at")

    {:noreply,
     socket
     |> assign(:filters, Map.drop(params, ["sort_by"]))
     |> assign(:sort_by, sort_by)
     |> assign(:lobbies_page, 1)
     |> reload_lobbies()}
  end

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:lobbies_page, 1)
     |> reload_lobbies()}
  end

  @impl true
  def handle_event("show_create", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create, true)
     |> assign(
       :create_form,
       to_form(%{"host_id" => "", "title" => "", "max_users" => "10"}, as: "lobby")
     )}
  end

  @impl true
  def handle_event("cancel_create", _params, socket) do
    {:noreply, assign(socket, :show_create, false)}
  end

  @impl true
  def handle_event("create_lobby", %{"lobby" => params}, socket) do
    attrs = %{
      title: blank_to_nil(params["title"]),
      max_users: parse_admin_int(params["max_users"]) || 10
    }

    host_id = GameServer.UUIDv7.cast_or_nil(params["host_id"])

    attrs = if host_id, do: Map.put(attrs, :host_id, host_id), else: attrs

    case Lobbies.create_lobby(attrs) do
      {:ok, lobby} ->
        {:noreply,
         socket
         |> assign(:show_create, false)
         |> put_flash(:info, "Lobby ##{lobby.id} created")
         |> reload_lobbies()}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, put_flash(socket, :error, "Create failed: #{inspect(cs.errors)}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Create failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("view_members", %{"id" => id}, socket) do
    lobby_id = to_string(id)
    lobby = Lobbies.get_lobby!(lobby_id)
    members = lobby_members(lobby_id)

    {:noreply,
     socket
     |> assign(:selected_lobby, lobby)
     |> assign(:members, members)
     |> assign(:ready_check, ReadyChecks.pending_for_lobby(lobby_id))
     |> assign(:show_members, true)
     |> assign(:form, nil)
     |> assign(:add_member_id, "")}
  end

  @impl true
  def handle_event("cancel_ready_check", %{"id" => id}, socket) do
    socket =
      with %{status: "pending"} = check <- ReadyChecks.get_check(id),
           {:ok, _} <- ReadyChecks.cancel(check) do
        put_flash(socket, :info, "Ready check cancelled")
      else
        _ -> put_flash(socket, :error, "Ready check not found or already resolved")
      end

    lobby = socket.assigns.selected_lobby
    {:noreply, assign(socket, :ready_check, lobby && ReadyChecks.pending_for_lobby(lobby.id))}
  end

  @impl true
  def handle_event("close_members", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_lobby, nil)
     |> assign(:members, [])
     |> assign(:ready_check, nil)
     |> assign(:show_members, false)}
  end

  @impl true
  def handle_event("update_add_member_id", %{"value" => val}, socket) do
    {:noreply, assign(socket, :add_member_id, val)}
  end

  @impl true
  def handle_event("add_member", _params, socket) do
    lobby = socket.assigns.selected_lobby

    case GameServer.UUIDv7.cast_or_nil(socket.assigns.add_member_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Enter a valid user ID")}

      user_id ->
        case GameServer.Accounts.get_user(user_id) do
          nil ->
            {:noreply, put_flash(socket, :error, "User #{user_id} not found")}

          user ->
            case Lobbies.join_lobby(user, lobby.id) do
              {:ok, _} ->
                members = lobby_members(lobby.id)

                {:noreply,
                 socket
                 |> assign(:members, members)
                 |> assign(:add_member_id, "")
                 |> put_flash(:info, "User #{user_id} added to lobby")
                 |> reload_lobbies()}

              {:error, reason} ->
                {:noreply, put_flash(socket, :error, "Add failed: #{inspect(reason)}")}
            end
        end
    end
  end

  @impl true
  def handle_event("kick_member", %{"lobby-id" => lid, "user-id" => uid}, socket) do
    _lobby_id = to_string(lid)
    user_id = to_string(uid)

    lobby = socket.assigns.selected_lobby

    # Admin removal: directly clear the user's lobby_id
    case GameServer.Accounts.get_user(user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "User not found")}

      user ->
        user
        |> Ecto.Changeset.change(%{lobby_id: nil})
        |> GameServer.Repo.update()

        members = lobby_members(lobby.id)

        {:noreply,
         socket
         |> assign(:members, members)
         |> put_flash(:info, "User #{user_id} removed from lobby")
         |> reload_lobbies()}
    end
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
     |> sync_selected_ids(lobby_ids(socket.assigns.lobbies))}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    lobbies = socket.assigns.lobbies || []
    ids = lobby_ids(lobbies)
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
    ids = socket.assigns[:selected_ids] || MapSet.new()
    ids = MapSet.to_list(ids)

    {deleted, failed} =
      Enum.reduce(ids, {0, 0}, fn id, {d, f} ->
        lobby = Lobbies.get_lobby!(id)

        case Lobbies.delete_lobby(lobby) do
          {:ok, _} -> {d + 1, f}
          {:error, _} -> {d, f + 1}
        end
      end)

    socket = assign(socket, :selected_ids, MapSet.new())

    socket =
      cond do
        failed == 0 ->
          put_flash(socket, :info, "Deleted #{deleted} lobbies")

        deleted == 0 ->
          put_flash(socket, :error, "Failed to delete selected lobbies")

        true ->
          put_flash(
            socket,
            :error,
            "Deleted #{deleted} lobbies; failed #{failed}"
          )
      end

    {:noreply, socket |> reload_lobbies()}
  end

  def handle_event("edit_lobby", %{"id" => id}, socket) do
    lobby_id = to_string(id)
    lobby = Lobbies.get_lobby!(lobby_id)
    changeset = Lobbies.change_lobby(lobby)
    form = to_form(changeset, as: "lobby")

    {:noreply,
     socket
     |> assign(:selected_lobby, lobby)
     |> assign(:form, form)
     |> assign(:members, [])
     |> assign(:show_members, false)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, socket |> assign(:selected_lobby, nil) |> assign(:form, nil)}
  end

  def handle_event("admin_lobbies_prev", _params, socket) do
    page = max(1, (socket.assigns[:lobbies_page] || 1) - 1)
    {:noreply, socket |> assign(:lobbies_page, page) |> reload_lobbies()}
  end

  def handle_event("admin_lobbies_next", _params, socket) do
    page = (socket.assigns[:lobbies_page] || 1) + 1
    {:noreply, socket |> assign(:lobbies_page, page) |> reload_lobbies()}
  end

  def handle_event("admin_lobbies_page_size", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:lobbies_page_size, String.to_integer(size))
     |> assign(:lobbies_page, 1)
     |> reload_lobbies()}
  end

  def handle_event("save_lobby", %{"lobby" => params}, socket) do
    lobby = socket.assigns.selected_lobby

    # HTML checkboxes only send value when checked, so we must default missing keys to false
    params = Map.put_new(params, "is_hidden", "false")
    params = Map.put_new(params, "is_locked", "false")

    # Convert checkbox string values to booleans for Ecto
    params =
      params
      |> Map.update("is_hidden", false, fn v -> v in ["true", "on", true] end)
      |> Map.update("is_locked", false, fn v -> v in ["true", "on", true] end)

    # normalize metadata if provided as JSON string in the textarea
    params =
      case Map.get(params, "metadata") do
        nil ->
          params

        "" ->
          Map.put(params, "metadata", %{})

        s when is_binary(s) ->
          case Jason.decode(s) do
            {:ok, map} when is_map(map) -> Map.put(params, "metadata", map)
            _ -> Map.put(params, "metadata", %{})
          end

        other ->
          Map.put(params, "metadata", other)
      end

    res = Lobbies.update_lobby(lobby, params)

    case res do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lobby updated")
         |> assign(:selected_lobby, nil)
         |> assign(:form, nil)
         |> reload_lobbies()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "lobby"))}
    end
  end

  def handle_event("delete_lobby", %{"id" => id}, socket) do
    lobby_id = to_string(id)
    lobby = Lobbies.get_lobby!(lobby_id)

    case Lobbies.delete_lobby(lobby) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lobby deleted")
         |> reload_lobbies()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete lobby")}
    end
  end

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:lobby_created, :lobby_updated, :lobby_deleted, :lobby_membership_changed] do
    {:noreply, reload_lobbies(socket)}
  end

  defp reload_lobbies(socket) do
    page = socket.assigns[:lobbies_page] || 1
    page_size = socket.assigns[:lobbies_page_size] || 25
    filters = socket.assigns[:filters] || %{}
    sort_by = socket.assigns[:sort_by] || "updated_at"

    filters_with_sort = Map.put(filters, "sort_by", sort_by)

    lobbies =
      Lobbies.list_all_lobbies(filters_with_sort, page: page, page_size: page_size)
      |> GameServer.Repo.preload(:users)

    total_count = Lobbies.count_list_all_lobbies(filters)

    total_pages =
      if page_size > 0,
        do: div(total_count + page_size - 1, page_size),
        else: 0

    spectator_counts =
      lobbies
      |> Enum.map(& &1.id)
      |> SpectatorTracker.counts()

    socket
    |> assign(:lobbies, lobbies)
    |> assign(:count, total_count)
    |> assign(:spectator_counts, spectator_counts)
    |> assign(:lobbies_total_pages, total_pages)
    |> assign(:lobbies_page, page)
    |> sync_selected_ids(lobby_ids(lobbies))
  end

  defp lobby_ids(lobbies) when is_list(lobbies), do: Enum.map(lobbies, & &1.id)

  # Ready state is per (check, member); a lobby with no open check shows "—"
  # rather than implying everyone is un-ready.
  defp member_ready_state(nil, _user_id), do: "—"

  defp member_ready_state(check, user_id) do
    Enum.find_value(check.participants, "—", &if(&1.user_id == user_id, do: &1.state))
  end

  defp ready_state_class(nil, _user_id), do: "badge-ghost"

  defp ready_state_class(check, user_id) do
    case member_ready_state(check, user_id) do
      "ready" -> "badge-success"
      "declined" -> "badge-warning"
      "timed_out" -> "badge-error"
      _ -> "badge-ghost"
    end
  end

  defp ready_summary(check) do
    ready = Enum.count(check.participants, &(&1.state == "ready"))
    "#{ready}/#{length(check.participants)}"
  end

  defp lobby_members(lobby_id) do
    import Ecto.Query, only: [from: 2]
    GameServer.Repo.all(from u in GameServer.Accounts.User, where: u.lobby_id == ^lobby_id)
  end

  defp sync_selected_ids(socket, ids) when is_list(ids) do
    selected = socket.assigns[:selected_ids] || MapSet.new()
    allowed = MapSet.new(ids)
    assign(socket, :selected_ids, MapSet.intersection(selected, allowed))
  end

  defp parse_admin_int(val) when is_integer(val), do: val

  defp parse_admin_int(val) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_admin_int(_), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s) when is_binary(s), do: s
end
