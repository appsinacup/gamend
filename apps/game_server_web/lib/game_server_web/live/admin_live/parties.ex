defmodule GameServerWeb.AdminLive.Parties do
  use GameServerWeb, :live_view

  alias GameServer.Parties

  @impl true
  def mount(_params, _session, socket) do
    Parties.subscribe_parties()

    socket =
      socket
      |> assign(:parties_page, 1)
      |> assign(:parties_page_size, 25)
      |> assign(:filters, %{})
      |> assign(:sort_by, "updated_at")
      |> assign(:selected_party, nil)
      |> assign(:form, nil)
      |> assign(:members, [])
      |> assign(:show_members, false)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:show_create, false)
      |> assign(:create_form, to_form(%{"leader_id" => "", "max_size" => "4"}, as: "party"))
      |> assign(:add_member_id, "")
      |> reload_parties()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">&larr; Back to Admin</.link>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="card-title">Parties ({@count})</h2>
              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  phx-click="show_create"
                  class="btn btn-sm btn-outline btn-primary"
                  id="create-party-btn"
                >
                  + Create Party
                </button>
                <button
                  type="button"
                  phx-click="bulk_delete"
                  data-confirm={"Delete #{MapSet.size(@selected_ids)} selected parties?"}
                  class="btn btn-sm btn-outline btn-error"
                  disabled={MapSet.size(@selected_ids) == 0}
                >
                  Delete selected ({MapSet.size(@selected_ids)})
                </button>
              </div>
            </div>

            <form phx-change="filter" id="parties-filter-form">
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
                  <option value="max_size" selected={@sort_by == "max_size"}>
                    Max size (desc)
                  </option>
                  <option value="max_size_asc" selected={@sort_by == "max_size_asc"}>
                    Max size (asc)
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
                          checked={@parties != [] && MapSet.size(@selected_ids) == length(@parties)}
                        />
                      </th>
                      <th>ID</th>
                      <th>Leader</th>
                      <th>Members (Cap)</th>
                      <th>Metadata</th>
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
                          name="leader_id"
                          value={@filters["leader_id"]}
                          class="input input-bordered input-xs w-full"
                          placeholder="Leader ID"
                          phx-debounce="300"
                        />
                      </th>
                      <th class="flex gap-1">
                        <input
                          type="number"
                          name="min_size"
                          value={@filters["min_size"]}
                          class="input input-bordered input-xs w-16"
                          placeholder="Min"
                          phx-debounce="300"
                        />
                        <input
                          type="number"
                          name="max_size"
                          value={@filters["max_size"]}
                          class="input input-bordered input-xs w-16"
                          placeholder="Max"
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
                    <tr :for={p <- @parties} id={"admin-party-" <> to_string(p.id)}>
                      <td class="w-10">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-sm"
                          phx-click="toggle_select"
                          phx-value-id={p.id}
                          checked={MapSet.member?(@selected_ids, p.id)}
                        />
                      </td>
                      <td class="font-mono text-sm">{p.id}</td>
                      <td class="text-sm">
                        <span class="font-mono">{p.leader_id}</span>
                        <%= if p.leader do %>
                          <span class="text-base-content/60 ml-1">
                            ({p.leader.display_name || p.leader.email || "-"})
                          </span>
                        <% end %>
                      </td>
                      <td class="text-sm">
                        {Parties.count_party_members(p.id)} / {p.max_size}
                      </td>
                      <td class="text-sm max-w-[200px] truncate">
                        {Jason.encode!(p.metadata || %{})}
                      </td>
                      <td class="text-sm">
                        <.timestamp at={p.inserted_at} />
                      </td>
                      <td class="text-sm">
                        <.timestamp at={p.updated_at} />
                      </td>
                      <td class="text-sm">
                        <div class="flex flex-wrap gap-1">
                          <button
                            type="button"
                            phx-click="view_members"
                            phx-value-id={p.id}
                            class="btn btn-xs btn-outline btn-accent"
                          >
                            Members
                          </button>
                          <button
                            type="button"
                            phx-click="edit_party"
                            phx-value-id={p.id}
                            class="btn btn-xs btn-outline btn-info"
                          >
                            Edit
                          </button>
                          <button
                            type="button"
                            phx-click="delete_party"
                            phx-value-id={p.id}
                            data-confirm="Are you sure? This will disband the party."
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
                page={@parties_page}
                total_pages={@parties_total_pages}
                total_count={@count}
                page_size={@parties_page_size}
                on_prev="admin_parties_prev"
                on_next="admin_parties_next"
                on_page_size="admin_parties_page_size"
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>

    <%!-- Edit modal --%>
    <%= if @selected_party && @form do %>
      <div class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Edit Party</h3>

          <.form for={@form} id="party-edit-form" phx-submit="save_party">
            <.input field={@form[:max_size]} type="number" label="Max size (2–32)" />

            <div class="form-control">
              <label class="label">Metadata (JSON)</label>
              <textarea name="party[metadata]" class="textarea textarea-bordered" rows="4"><%= Jason.encode!(@selected_party.metadata || %{}) %></textarea>
            </div>

            <div class="mt-4 text-sm text-base-content/70 space-y-1">
              <div>
                Leader: <span class="font-mono">{@selected_party.leader_id}</span>
              </div>
              <div>
                Created:
                <span class="font-mono">
                  <.timestamp at={@selected_party.inserted_at} format="full" />
                </span>
              </div>
              <div>
                Updated:
                <span class="font-mono">
                  <.timestamp at={@selected_party.updated_at} format="full" />
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
    <%= if @selected_party && @show_members && @form == nil do %>
      <div class="modal modal-open">
        <div class="modal-box max-w-2xl">
          <h3 class="font-bold text-lg">
            Party #{@selected_party.id} members ({length(@members)})
          </h3>

          <div class="flex gap-2 mt-4">
            <input
              type="number"
              placeholder="User ID to add"
              value={@add_member_id}
              phx-keyup="update_add_member_id"
              class="input input-bordered input-sm w-40"
              id="party-add-member-input"
            />
            <button
              type="button"
              phx-click="add_party_member"
              class="btn btn-sm btn-outline btn-primary"
              id="party-add-member-btn"
            >
              Add Member
            </button>
          </div>

          <div class="overflow-x-auto mt-4">
            <table class="table table-zebra w-full min-w-[28rem]">
              <thead>
                <tr>
                  <th>User ID</th>
                  <th>Name</th>
                  <th>Role</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={m <- @members} id={"party-member-" <> to_string(m.id)}>
                  <td class="font-mono text-sm">{m.id}</td>
                  <td class="text-sm">{m.display_name || m.email || "-"}</td>
                  <td class="text-sm">
                    <%= if m.id == @selected_party.leader_id do %>
                      <span class="badge badge-primary badge-sm">Leader</span>
                    <% else %>
                      <span class="badge badge-ghost badge-sm">Member</span>
                    <% end %>
                  </td>
                  <td class="text-sm">
                    <%= if m.id != @selected_party.leader_id do %>
                      <button
                        type="button"
                        phx-click="kick_member"
                        phx-value-party-id={@selected_party.id}
                        phx-value-user-id={m.id}
                        data-confirm={"Kick user #{m.id} from party?"}
                        class="btn btn-xs btn-outline btn-error"
                      >
                        Kick
                      </button>
                    <% end %>
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

    <%!-- Create party modal --%>
    <%= if @show_create do %>
      <div class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Create Party</h3>

          <.form for={@create_form} id="party-create-form" phx-submit="create_party">
            <.input
              field={@create_form[:leader_id]}
              type="text"
              label="Leader User ID"
              required
            />
            <.input
              field={@create_form[:max_size]}
              type="number"
              label="Max size (2–32)"
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

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("show_create", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create, true)
     |> assign(:create_form, to_form(%{"leader_id" => "", "max_size" => "4"}, as: "party"))}
  end

  @impl true
  def handle_event("cancel_create", _params, socket) do
    {:noreply, assign(socket, :show_create, false)}
  end

  @impl true
  def handle_event("create_party", %{"party" => params}, socket) do
    leader_id = GameServer.UUIDv7.cast_or_nil(params["leader_id"])

    case leader_id do
      nil ->
        {:noreply, put_flash(socket, :error, "Leader ID must be a valid user ID")}

      id ->
        case GameServer.Accounts.get_user(id) do
          nil ->
            {:noreply, put_flash(socket, :error, "User #{id} not found")}

          user ->
            attrs = %{max_size: parse_create_int(params["max_size"]) || 4}

            case Parties.create_party(user, attrs) do
              {:ok, party} ->
                {:noreply,
                 socket
                 |> assign(:show_create, false)
                 |> put_flash(:info, "Party ##{party.id} created")
                 |> reload_parties()}

              {:error, :in_lobby} ->
                {:noreply, put_flash(socket, :error, "User is currently in a lobby")}

              {:error, :already_in_party} ->
                {:noreply, put_flash(socket, :error, "User is already in a party")}

              {:error, changeset} ->
                {:noreply,
                 put_flash(socket, :error, "Create failed: #{inspect(changeset.errors)}")}
            end
        end
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    sort_by = Map.get(params, "sort_by", socket.assigns[:sort_by] || "updated_at")

    {:noreply,
     socket
     |> assign(:filters, Map.drop(params, ["sort_by"]))
     |> assign(:sort_by, sort_by)
     |> assign(:parties_page, 1)
     |> reload_parties()}
  end

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:parties_page, 1)
     |> reload_parties()}
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
     |> sync_selected_ids(party_ids(socket.assigns.parties))}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    parties = socket.assigns.parties || []
    ids = party_ids(parties)
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
        case Parties.admin_delete_party(id) do
          {:ok, _} -> {d + 1, f}
          {:error, _} -> {d, f + 1}
        end
      end)

    socket = assign(socket, :selected_ids, MapSet.new())

    socket =
      cond do
        failed == 0 ->
          put_flash(socket, :info, "Deleted #{deleted} parties")

        deleted == 0 ->
          put_flash(socket, :error, "Failed to delete selected parties")

        true ->
          put_flash(socket, :error, "Deleted #{deleted} parties; failed #{failed}")
      end

    {:noreply, reload_parties(socket)}
  end

  @impl true
  def handle_event("edit_party", %{"id" => id}, socket) do
    party_id = to_string(id)
    party = Parties.get_party!(party_id)
    changeset = Parties.change_party(party)
    form = to_form(changeset, as: "party")

    {:noreply,
     socket
     |> assign(:selected_party, party)
     |> assign(:form, form)
     |> assign(:members, [])
     |> assign(:show_members, false)}
  end

  @impl true
  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_party, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("save_party", %{"party" => params}, socket) do
    party = socket.assigns.selected_party

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

    case Parties.admin_update_party(party, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Party updated")
         |> assign(:selected_party, nil)
         |> assign(:form, nil)
         |> reload_parties()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "party"))}
    end
  end

  @impl true
  def handle_event("delete_party", %{"id" => id}, socket) do
    party_id = to_string(id)

    case Parties.admin_delete_party(party_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Party deleted")
         |> reload_parties()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete party")}
    end
  end

  @impl true
  def handle_event("view_members", %{"id" => id}, socket) do
    party_id = to_string(id)
    party = Parties.get_party!(party_id)
    members = Parties.get_party_members(party_id)

    {:noreply,
     socket
     |> assign(:selected_party, party)
     |> assign(:members, members)
     |> assign(:show_members, true)
     |> assign(:form, nil)
     |> assign(:add_member_id, "")}
  end

  @impl true
  def handle_event("close_members", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_party, nil)
     |> assign(:members, [])
     |> assign(:show_members, false)
     |> assign(:add_member_id, "")}
  end

  @impl true
  def handle_event("update_add_member_id", %{"value" => val}, socket) do
    {:noreply, assign(socket, :add_member_id, val)}
  end

  @impl true
  def handle_event("add_party_member", _params, socket) do
    party = socket.assigns.selected_party
    raw = socket.assigns.add_member_id

    case GameServer.UUIDv7.cast_or_nil(raw) do
      nil ->
        {:noreply, put_flash(socket, :error, "Invalid user ID")}

      user_id ->
        user = GameServer.Accounts.get_user(user_id)

        if user do
          result =
            user
            |> Ecto.Changeset.change(%{party_id: party.id})
            |> GameServer.Repo.update()

          case result do
            {:ok, _user} ->
              members = Parties.get_party_members(party.id)

              {:noreply,
               socket
               |> assign(:members, members)
               |> assign(:add_member_id, "")
               |> put_flash(:info, "User added to party")
               |> reload_parties()}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Add failed: #{inspect(reason)}")}
          end
        else
          {:noreply, put_flash(socket, :error, "User not found")}
        end
    end
  end

  @impl true
  def handle_event("kick_member", %{"party-id" => pid, "user-id" => uid}, socket) do
    _party_id = to_string(pid)
    user_id = to_string(uid)

    party = socket.assigns.selected_party

    # Admin kick: use the leader as the acting user
    leader = GameServer.Accounts.get_user(party.leader_id)

    case Parties.kick_member(leader, user_id) do
      {:ok, _updated} ->
        members = Parties.get_party_members(party.id)

        {:noreply,
         socket
         |> assign(:members, members)
         |> put_flash(:info, "User kicked from party")
         |> reload_parties()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Kick failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("admin_parties_prev", _params, socket) do
    page = max(1, (socket.assigns[:parties_page] || 1) - 1)
    {:noreply, socket |> assign(:parties_page, page) |> reload_parties()}
  end

  @impl true
  def handle_event("admin_parties_next", _params, socket) do
    page = (socket.assigns[:parties_page] || 1) + 1
    {:noreply, socket |> assign(:parties_page, page) |> reload_parties()}
  end

  @impl true
  def handle_event("admin_parties_page_size", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:parties_page_size, String.to_integer(size))
     |> assign(:parties_page, 1)
     |> reload_parties()}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:party_created, :party_updated, :party_deleted] do
    {:noreply, reload_parties(socket)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp reload_parties(socket) do
    page = socket.assigns[:parties_page] || 1
    page_size = socket.assigns[:parties_page_size] || 25
    filters = socket.assigns[:filters] || %{}
    sort_by = socket.assigns[:sort_by] || "updated_at"

    parties =
      Parties.list_all_parties(filters,
        page: page,
        page_size: page_size,
        sort_by: sort_by
      )

    total_count = Parties.count_all_parties(filters)

    total_pages =
      if page_size > 0,
        do: div(total_count + page_size - 1, page_size),
        else: 0

    socket
    |> assign(:parties, parties)
    |> assign(:count, total_count)
    |> assign(:parties_total_pages, total_pages)
    |> assign(:parties_page, page)
    |> sync_selected_ids(party_ids(parties))
  end

  defp party_ids(parties) when is_list(parties), do: Enum.map(parties, & &1.id)

  defp sync_selected_ids(socket, ids) when is_list(ids) do
    selected = socket.assigns[:selected_ids] || MapSet.new()
    allowed = MapSet.new(ids)
    assign(socket, :selected_ids, MapSet.intersection(selected, allowed))
  end

  defp parse_create_int(val) when is_integer(val), do: val

  defp parse_create_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_create_int(_), do: nil
end
