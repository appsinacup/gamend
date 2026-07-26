defmodule GameServerWeb.AdminLive.Users do
  use GameServerWeb, :live_view

  alias GameServer.Accounts
  alias GameServer.Accounts.User
  alias GameServer.Async

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">
          ← Back to Admin
        </.link>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <h2 class="card-title">Users ({@users_count})</h2>

              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  phx-click="bulk_delete"
                  data-confirm={"Delete #{MapSet.size(@selected_ids)} selected users?"}
                  class="btn btn-sm btn-outline btn-error"
                  disabled={MapSet.size(@selected_ids) == 0}
                >
                  Delete selected ({MapSet.size(@selected_ids)})
                </button>
                <form
                  id="admin-user-search-form"
                  phx-change="search_users"
                  phx-submit="search_users"
                  class="flex items-center"
                >
                  <input
                    type="text"
                    name="q"
                    id="admin-user-search"
                    placeholder="Search by name, email, or any ID"
                    value={@search_query}
                    class="input input-sm w-full md:w-64"
                  />
                </form>
                <button phx-click="clear_search" class="btn btn-sm">Clear</button>
              </div>
            </div>

            <div class="mt-2 flex flex-wrap items-center gap-4">
              <div class="text-sm">Sort by:</div>
              <div class="flex flex-wrap items-center gap-2">
                <button
                  phx-click="sort_users"
                  phx-value-field="inserted_at"
                  class={[
                    "btn btn-xs",
                    if(@sort_field == "inserted_at", do: "btn-primary", else: "btn-outline")
                  ]}
                >
                  Created
                  <%= if @sort_field == "inserted_at" do %>
                    {if(@sort_dir == "desc", do: "\u25BC", else: "\u25B2")}
                  <% end %>
                </button>
                <button
                  phx-click="sort_users"
                  phx-value-field="updated_at"
                  class={[
                    "btn btn-xs",
                    if(@sort_field == "updated_at", do: "btn-primary", else: "btn-outline")
                  ]}
                >
                  Updated
                  <%= if @sort_field == "updated_at" do %>
                    {if(@sort_dir == "desc", do: "\u25BC", else: "\u25B2")}
                  <% end %>
                </button>
                <button
                  phx-click="sort_users"
                  phx-value-field="last_seen_at"
                  class={[
                    "btn btn-xs",
                    if(@sort_field == "last_seen_at", do: "btn-primary", else: "btn-outline")
                  ]}
                >
                  Last Seen
                  <%= if @sort_field == "last_seen_at" do %>
                    {if(@sort_dir == "desc", do: "\u25BC", else: "\u25B2")}
                  <% end %>
                </button>
              </div>
            </div>

            <div class="mt-2 flex flex-wrap items-center gap-4">
              <div class="text-sm">Filter by auth provider:</div>
              <div class="flex flex-wrap items-center gap-3">
                <label class="label cursor-pointer">
                  <input
                    type="checkbox"
                    phx-click="toggle_provider"
                    phx-value-provider="discord"
                    checked={"discord" in @filters}
                    class="checkbox"
                  />
                  <span class="label-text ml-2">Discord</span>
                </label>
                <label class="label cursor-pointer">
                  <input
                    type="checkbox"
                    phx-click="toggle_provider"
                    phx-value-provider="google"
                    checked={"google" in @filters}
                    class="checkbox"
                  />
                  <span class="label-text ml-2">Google</span>
                </label>
                <label class="label cursor-pointer">
                  <input
                    type="checkbox"
                    phx-click="toggle_provider"
                    phx-value-provider="apple"
                    checked={"apple" in @filters}
                    class="checkbox"
                  />
                  <span class="label-text ml-2">Apple</span>
                </label>
                <label class="label cursor-pointer">
                  <input
                    type="checkbox"
                    phx-click="toggle_provider"
                    phx-value-provider="facebook"
                    checked={"facebook" in @filters}
                    class="checkbox"
                  />
                  <span class="label-text ml-2">Facebook</span>
                </label>
                <label class="label cursor-pointer">
                  <input
                    type="checkbox"
                    phx-click="toggle_provider"
                    phx-value-provider="device"
                    checked={"device" in @filters}
                    class="checkbox"
                  />
                  <span class="label-text ml-2">Device</span>
                </label>
                <label class="label cursor-pointer">
                  <input
                    type="checkbox"
                    phx-click="toggle_provider"
                    phx-value-provider="steam"
                    checked={"steam" in @filters}
                    class="checkbox"
                  />
                  <span class="label-text ml-2">Steam</span>
                </label>
                <label class="label cursor-pointer">
                  <input
                    type="checkbox"
                    phx-click="toggle_provider"
                    phx-value-provider="email"
                    checked={"email" in @filters}
                    class="checkbox"
                  />
                  <span class="label-text ml-2">Email (password)</span>
                </label>
                <span class="text-base-content/30">|</span>
                <label class="label cursor-pointer">
                  <input
                    type="checkbox"
                    phx-click="toggle_provider"
                    phx-value-provider="online"
                    checked={"online" in @filters}
                    class="checkbox"
                  />
                  <span class="label-text ml-2">Online</span>
                </label>
                <label class="label cursor-pointer">
                  <input
                    type="checkbox"
                    phx-click="toggle_provider"
                    phx-value-provider="unactivated"
                    checked={"unactivated" in @filters}
                    class="checkbox"
                  />
                  <span class="label-text ml-2">Unactivated</span>
                </label>
              </div>
            </div>
            <div class="overflow-x-auto">
              <table class="table table-zebra min-w-[72rem]">
                <thead>
                  <tr>
                    <th class="w-10">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        phx-click="toggle_select_all"
                        checked={
                          @recent_users != [] && MapSet.size(@selected_ids) == length(@recent_users)
                        }
                      />
                    </th>
                    <th>ID</th>
                    <th>Online</th>
                    <th>Lobby ID</th>
                    <th>Email</th>
                    <th>Username</th>
                    <th>Display Name</th>
                    <th>Discord ID</th>
                    <th>Steam ID</th>
                    <th>Device ID</th>
                    <th>Profile</th>
                    <th>Apple ID</th>
                    <th>Google ID</th>
                    <th>Facebook ID</th>
                    <th>Admin</th>
                    <th>Activated</th>
                    <th>Metadata</th>
                    <th>Confirmed</th>
                    <th>Last Seen</th>
                    <th>Created</th>
                    <th>Updated</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={user <- @recent_users} id={"user-#{user.id}"}>
                    <td class="w-10">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        phx-click="toggle_select"
                        phx-value-id={user.id}
                        checked={MapSet.member?(@selected_ids, user.id)}
                      />
                    </td>
                    <td>{user.id}</td>
                    <td>
                      <%= if user.is_online do %>
                        <span class="badge badge-success badge-sm">Online</span>
                      <% else %>
                        <span class="badge badge-ghost badge-sm">Offline</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm">
                      <%= if user.lobby_id do %>
                        {user.lobby_id}
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm">{user.email}</td>
                    <td class="font-mono text-sm">
                      <%= if user.username && user.username != "" do %>
                        {user.username}
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td class="text-sm">
                      <%= if user.display_name && user.display_name != "" do %>
                        {user.display_name}
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm">
                      <%= if user.discord_id do %>
                        {user.discord_id}
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm">
                      <%= if user.steam_id do %>
                        {user.steam_id}
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm">
                      <%= if user.device_id do %>
                        {user.device_id}
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td>
                      <%= if user.profile_url do %>
                        <div class="flex items-center gap-2">
                          <img src={user.profile_url} alt="avatar" class="w-8 h-8 rounded-full" />
                          <a href={user.profile_url} target="_blank" class="text-sm link">Profile</a>
                        </div>
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm">
                      <%= if user.apple_id do %>
                        {user.apple_id}
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm">
                      <%= if user.google_id do %>
                        {user.google_id}
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm">
                      <%= if user.facebook_id do %>
                        {user.facebook_id}
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td>
                      <%= if user.is_admin do %>
                        <span class="badge badge-success badge-sm">Yes</span>
                      <% else %>
                        <span class="badge badge-neutral badge-sm">No</span>
                      <% end %>
                    </td>
                    <td>
                      <%= if user.is_activated do %>
                        <span class="badge badge-success badge-sm">Yes</span>
                      <% else %>
                        <span class="badge badge-error badge-sm">No</span>
                      <% end %>
                    </td>
                    <td>
                      <%= if user.metadata && user.metadata != %{} do %>
                        <span class="badge badge-info badge-sm">Set</span>
                      <% else %>
                        <span class="badge badge-ghost badge-sm">Empty</span>
                      <% end %>
                    </td>
                    <td>
                      <%= if user.confirmed_at do %>
                        <span class="badge badge-success badge-sm">Yes</span>
                      <% else %>
                        <span class="badge badge-warning badge-sm">No</span>
                      <% end %>
                    </td>
                    <td class="text-sm">
                      <%= if user.last_seen_at do %>
                        <.timestamp at={user.last_seen_at} />
                      <% else %>
                        <span class="text-gray-500">-</span>
                      <% end %>
                    </td>
                    <td class="text-sm">
                      <.timestamp at={user.inserted_at} />
                    </td>
                    <td class="text-sm">
                      <.timestamp at={user.updated_at} />
                    </td>
                    <td>
                      <button
                        phx-click="edit_user"
                        phx-value-id={user.id}
                        class="btn btn-xs btn-outline btn-info mr-2"
                      >
                        Edit
                      </button>
                      <button
                        phx-click="delete_user"
                        phx-value-id={user.id}
                        data-confirm="Are you sure?"
                        class="btn btn-xs btn-outline btn-error"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="mt-4">
              <.pagination
                page={@users_page}
                total_pages={@users_total_pages}
                total_count={@users_count}
                page_size={@users_page_size}
                on_prev="admin_users_prev"
                on_next="admin_users_next"
                on_page_size="admin_users_page_size"
              />
            </div>
          </div>
        </div>
      </div>

      <%= if @selected_user do %>
        <div class="modal modal-open">
          <div class="modal-box max-w-2xl">
            <h3 class="font-bold text-lg">Edit User</h3>

            <%!-- Per-user drill-downs into the aggregate admin views, pre-filtered. --%>
            <div class="flex flex-wrap gap-2 mt-1 mb-3">
              <.link
                navigate={~p"/admin/economy?user_id=#{@selected_user.id}"}
                class="btn btn-xs btn-outline"
              >
                Wallet &amp; Items
              </.link>
              <.link
                navigate={~p"/admin/kv?user_id=#{@selected_user.id}"}
                class="btn btn-xs btn-outline"
              >
                KV Data
              </.link>
            </div>

            <.form for={@form} id="user-form" phx-submit="save_user">
              <.input field={@form[:email]} type="email" label="Email" />
              <.input field={@form[:display_name]} type="text" label="Display name" />
              <div class="form-control">
                <label class="label cursor-pointer">
                  <span class="label-text">Admin</span>
                  <input
                    type="checkbox"
                    name="user[is_admin]"
                    class="checkbox"
                    checked={@selected_user.is_admin}
                  />
                </label>
              </div>
              <div class="form-control">
                <label class="label cursor-pointer">
                  <span class="label-text">Activated</span>
                  <input
                    type="checkbox"
                    name="user[is_activated]"
                    class="checkbox"
                    checked={@selected_user.is_activated}
                  />
                </label>
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Metadata (JSON)</span>
                  <textarea
                    name="user[metadata]"
                    class="textarea textarea-bordered"
                    rows="4"
                  ><%= Jason.encode!(@selected_user.metadata || %{}) %></textarea>
                </label>
              </div>
              <div class="modal-action">
                <button type="button" phx-click="cancel_edit" class="btn">Cancel</button>
                <button type="submit" class="btn btn-primary">Save</button>
              </div>
            </.form>

            <%!-- Sessions / Tokens section --%>
            <div class="divider">Sessions &amp; Tokens ({length(@user_tokens)})</div>

            <%= if @user_tokens == [] do %>
              <p class="text-sm opacity-60">No tokens found.</p>
            <% else %>
              <div class="flex justify-end mb-2">
                <button
                  type="button"
                  phx-click="revoke_all_sessions"
                  phx-value-user-id={@selected_user.id}
                  data-confirm={"Revoke all #{length(@user_tokens)} tokens for this user?"}
                  class="btn btn-xs btn-outline btn-error"
                >
                  Revoke All
                </button>
              </div>
              <div class="overflow-x-auto">
                <table class="table table-zebra table-xs">
                  <thead>
                    <tr>
                      <th>ID</th>
                      <th>Context</th>
                      <th>Created</th>
                      <th>Auth At</th>
                      <th>Sent To</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={token <- @user_tokens} id={"token-#{token.id}"}>
                      <td class="font-mono text-xs">{token.id}</td>
                      <td>
                        <span class={[
                          "badge badge-xs",
                          token.context == "session" && "badge-primary",
                          token.context == "login" && "badge-accent",
                          token.context == "confirm" && "badge-info",
                          String.starts_with?(token.context || "", "change:") && "badge-warning"
                        ]}>
                          {token.context}
                        </span>
                      </td>
                      <td class="text-xs">
                        <.timestamp at={token.inserted_at} />
                      </td>
                      <td class="text-xs">
                        <%= if token.authenticated_at do %>
                          <.timestamp at={token.authenticated_at} />
                        <% else %>
                          <span class="opacity-40">-</span>
                        <% end %>
                      </td>
                      <td class="text-xs font-mono">
                        {token.sent_to || "-"}
                      </td>
                      <td>
                        <button
                          type="button"
                          phx-click="revoke_token"
                          phx-value-id={token.id}
                          data-confirm="Revoke this token?"
                          class="btn btn-xs btn-ghost text-error"
                        >
                          Revoke
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    # paginated admin users view (admins can see all users)
    page = 1
    page_size = 25
    sort_field = "inserted_at"
    sort_dir = "desc"

    # Support ?filter=unactivated from dashboard link
    initial_filters =
      case params["filter"] do
        "unactivated" -> ["unactivated"]
        _ -> []
      end

    {users, total_count, total_pages} =
      load_users(
        page,
        page_size,
        "",
        initial_filters,
        sort_field,
        sort_dir
      )

    {:ok,
     socket
     |> assign(:users_count, total_count)
     |> assign(:recent_users, users)
     |> assign(:users_page, page)
     |> assign(:users_page_size, page_size)
     |> assign(:users_total_pages, total_pages)
     |> assign(:selected_user, nil)
     |> assign(:form, nil)
     |> assign(:user_tokens, [])
     |> assign(:search_query, "")
     |> assign(:filters, initial_filters)
     |> assign(:sort_field, sort_field)
     |> assign(:sort_dir, sort_dir)
     |> assign(:selected_ids, MapSet.new())}
  end

  @impl true
  def handle_event("edit_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    changeset = User.admin_changeset(user, %{})
    form = to_form(changeset, as: "user")
    tokens = Accounts.list_user_tokens(user.id)

    {:noreply,
     socket
     |> assign(:selected_user, user)
     |> assign(:form, form)
     |> assign(:user_tokens, tokens)}
  end

  # Search / filter handlers
  def handle_event("search_users", %{"q" => q}, socket) do
    page = 1
    page_size = socket.assigns[:users_page_size] || 25

    {users, total_count, total_pages} = load_users(page, page_size, q, socket.assigns[:filters])

    {:noreply,
     socket
     |> assign(:search_query, q)
     |> assign(:users_page, page)
     |> assign(:recent_users, users)
     |> assign(:users_count, total_count)
     |> assign(:users_total_pages, total_pages)
     |> sync_selected_ids(user_ids(users))}
  end

  def handle_event("clear_search", _params, socket) do
    page = 1
    page_size = socket.assigns[:users_page_size] || 25

    {users, total_count, total_pages} = load_users(page, page_size, "", [])

    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:filters, [])
     |> assign(:users_page, page)
     |> assign(:recent_users, users)
     |> assign(:users_count, total_count)
     |> assign(:users_total_pages, total_pages)
     |> sync_selected_ids(user_ids(users))}
  end

  def handle_event("toggle_provider", %{"provider" => provider}, socket) do
    filters = socket.assigns[:filters] || []

    filters =
      if provider in filters do
        List.delete(filters, provider)
      else
        [provider | filters]
      end

    page = 1
    page_size = socket.assigns[:users_page_size] || 25
    q = socket.assigns[:search_query] || ""

    {users, total_count, total_pages} = load_users(page, page_size, q, filters)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:users_page, page)
     |> assign(:recent_users, users)
     |> assign(:users_count, total_count)
     |> assign(:users_total_pages, total_pages)
     |> sync_selected_ids(user_ids(users))}
  end

  def handle_event("sort_users", %{"field" => field}, socket) do
    current_field = socket.assigns[:sort_field] || "inserted_at"
    current_dir = socket.assigns[:sort_dir] || "desc"

    # Toggle direction if same field, otherwise default to desc
    sort_dir =
      if field == current_field do
        if current_dir == "desc", do: "asc", else: "desc"
      else
        "desc"
      end

    page = 1
    page_size = socket.assigns[:users_page_size] || 25
    q = socket.assigns[:search_query] || ""
    filters = socket.assigns[:filters] || []

    {users, total_count, total_pages} = load_users(page, page_size, q, filters, field, sort_dir)

    {:noreply,
     socket
     |> assign(:sort_field, field)
     |> assign(:sort_dir, sort_dir)
     |> assign(:users_page, page)
     |> assign(:recent_users, users)
     |> assign(:users_count, total_count)
     |> assign(:users_total_pages, total_pages)
     |> sync_selected_ids(user_ids(users))}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:form, nil)
     |> assign(:user_tokens, [])}
  end

  def handle_event("revoke_token", %{"id" => id}, socket) do
    token = Accounts.get_user_token!(id)
    Accounts.delete_user_token(token)
    user = socket.assigns.selected_user
    tokens = Accounts.list_user_tokens(user.id)

    {:noreply,
     socket
     |> assign(:user_tokens, tokens)
     |> put_flash(:info, "Token #{id} revoked")}
  end

  def handle_event("revoke_all_sessions", %{"user-id" => uid}, socket) do
    user_id = uid
    {count, _} = Accounts.revoke_all_user_sessions(user_id)
    tokens = Accounts.list_user_tokens(user_id)

    {:noreply,
     socket
     |> assign(:user_tokens, tokens)
     |> put_flash(:info, "Revoked #{count} session(s)")}
  end

  def handle_event("save_user", %{"user" => user_params}, socket) do
    user = socket.assigns.selected_user

    attrs =
      user_params
      |> Map.put(
        "confirmed_at",
        if(user_params["confirmed"] == "on", do: DateTime.utc_now(:second), else: nil)
      )
      |> Map.put("is_admin", user_params["is_admin"] == "on")
      |> Map.put("is_activated", user_params["is_activated"] == "on")
      |> Map.update("metadata", %{}, fn metadata_str ->
        case Jason.decode(metadata_str) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end
      end)

    case Accounts.update_user(user, attrs) do
      {:ok, updated_user} ->
        # Send activation email if the user was just activated
        if not user.is_activated and updated_user.is_activated do
          Async.run(fn ->
            Accounts.UserNotifier.deliver_account_activated(updated_user)
          end)
        end

        # re-fetch current page of users, keeping search and filters
        page = socket.assigns[:users_page] || 1
        page_size = socket.assigns[:users_page_size] || 25

        {users, total_count, total_pages} =
          load_users(
            page,
            page_size,
            socket.assigns[:search_query] || "",
            socket.assigns[:filters] || []
          )

        {:noreply,
         socket
         |> put_flash(:info, "User updated successfully")
         |> assign(:recent_users, users)
         |> assign(:users_count, total_count)
         |> assign(:users_total_pages, total_pages)
         |> assign(:selected_user, nil)
         |> assign(:form, nil)
         |> sync_selected_ids(user_ids(users))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}
    end
  end

  def handle_event("delete_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    case Accounts.delete_user(user) do
      {:ok, _user} ->
        page = socket.assigns[:users_page] || 1
        page_size = socket.assigns[:users_page_size] || 25

        {users, total_count, total_pages} =
          load_users(
            page,
            page_size,
            socket.assigns[:search_query] || "",
            socket.assigns[:filters] || []
          )

        # ensure current page is within range (if we deleted the last item on last page)
        page2 = max(1, min(page, total_pages))

        {users, total_count, total_pages} =
          if page2 != page do
            load_users(
              page2,
              page_size,
              socket.assigns[:search_query] || "",
              socket.assigns[:filters] || []
            )
          else
            {users, total_count, total_pages}
          end

        {:noreply,
         socket
         |> put_flash(:info, "User deleted successfully")
         |> assign(:users_count, total_count)
         |> assign(:recent_users, users)
         |> assign(:users_page, page2)
         |> assign(:users_total_pages, total_pages)
         |> sync_selected_ids(user_ids(users))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete user")}
    end
  end

  @impl true
  def handle_event("admin_users_prev", _params, socket) do
    page = max(1, (socket.assigns[:users_page] || 1) - 1)
    page_size = socket.assigns[:users_page_size] || 25

    {users, total_count, total_pages} =
      load_users(
        page,
        page_size,
        socket.assigns[:search_query] || "",
        socket.assigns[:filters] || []
      )

    {:noreply,
     socket
     |> assign(:users_page, page)
     |> assign(:recent_users, users)
     |> assign(:users_count, total_count)
     |> assign(:users_total_pages, total_pages)
     |> sync_selected_ids(user_ids(users))}
  end

  def handle_event("admin_users_next", _params, socket) do
    page = (socket.assigns[:users_page] || 1) + 1
    page_size = socket.assigns[:users_page_size] || 25

    {users, total_count, total_pages} =
      load_users(
        page,
        page_size,
        socket.assigns[:search_query] || "",
        socket.assigns[:filters] || []
      )

    {:noreply,
     socket
     |> assign(:users_page, page)
     |> assign(:recent_users, users)
     |> assign(:users_count, total_count)
     |> assign(:users_total_pages, total_pages)
     |> sync_selected_ids(user_ids(users))}
  end

  def handle_event("admin_users_page_size", %{"size" => size}, socket) do
    page_size = String.to_integer(size)

    {users, total_count, total_pages} =
      load_users(
        1,
        page_size,
        socket.assigns[:search_query] || "",
        socket.assigns[:filters] || []
      )

    {:noreply,
     socket
     |> assign(:users_page_size, page_size)
     |> assign(:users_page, 1)
     |> assign(:recent_users, users)
     |> assign(:users_count, total_count)
     |> assign(:users_total_pages, total_pages)
     |> sync_selected_ids(user_ids(users))}
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
     assign(socket, :selected_ids, selected)
     |> sync_selected_ids(user_ids(socket.assigns.recent_users))}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    users = socket.assigns.recent_users || []
    ids = user_ids(users)

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
        user = Accounts.get_user!(id)

        case Accounts.delete_user(user) do
          {:ok, _} -> {d + 1, f}
          {:error, _} -> {d, f + 1}
        end
      end)

    page = socket.assigns[:users_page] || 1
    page_size = socket.assigns[:users_page_size] || 25
    q = socket.assigns[:search_query] || ""
    filters = socket.assigns[:filters] || []

    {users, total_count, total_pages} = load_users(page, page_size, q, filters)
    page2 = max(1, min(page, total_pages))

    {users, total_count, total_pages} =
      if page2 != page do
        load_users(page2, page_size, q, filters)
      else
        {users, total_count, total_pages}
      end

    socket = assign(socket, :selected_ids, MapSet.new())

    socket =
      cond do
        failed == 0 ->
          put_flash(socket, :info, "Deleted #{deleted} users")

        deleted == 0 ->
          put_flash(socket, :error, "Failed to delete selected users")

        true ->
          put_flash(
            socket,
            :error,
            "Deleted #{deleted} users; failed #{failed}"
          )
      end

    {:noreply,
     socket
     |> assign(:users_count, total_count)
     |> assign(:recent_users, users)
     |> assign(:users_page, page2)
     |> assign(:users_total_pages, total_pages)
     |> sync_selected_ids(user_ids(users))}
  end

  # Delegates to Accounts.list_all_users/2 (the reusable, admin-scoped context
  # query) so search/filter/sort logic lives in one place, shared with anything
  # else that needs an admin user listing.
  defp load_users(
         page,
         page_size,
         search,
         filters,
         sort_field \\ "inserted_at",
         sort_dir \\ "desc"
       ) do
    query_filters = %{search: search || "", facets: filters}
    opts = [page: page, page_size: page_size, sort_field: sort_field, sort_dir: sort_dir]

    users = Accounts.list_all_users(query_filters, opts)
    total_count = Accounts.count_list_all_users(query_filters)
    total_pages = if page_size > 0, do: div(total_count + page_size - 1, page_size), else: 0

    {users, total_count, total_pages}
  end

  defp user_ids(users) when is_list(users), do: Enum.map(users, & &1.id)

  defp sync_selected_ids(socket, ids) when is_list(ids) do
    selected = socket.assigns[:selected_ids] || MapSet.new()
    allowed = MapSet.new(ids)
    assign(socket, :selected_ids, MapSet.intersection(selected, allowed))
  end
end
