defmodule GameServerWeb.AdminLive.Users.Index do
  @moduledoc """
  Admin LiveView for listing and managing users.

  Shows a paginated list of users with quick actions to edit or delete.
  """

  use GameServerWeb, :live_view

  alias GameServer.Accounts
  alias GameServer.Accounts.User
  alias GameServer.Repo
  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <.header>
          User Management
          <:subtitle>Manage all users in the system</:subtitle>
          <:actions>
            <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm">
              Back to Admin
            </.link>
          </:actions>
        </.header>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="overflow-x-auto">
              <table class="table table-zebra">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Email</th>
                    <th>Profile</th>
                    <th>Discord ID</th>
                    <th>Steam ID</th>
                    <th>Confirmed</th>
                    <th>Created</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={user <- @users} id={"user-#{user.id}"}>
                    <td>{user.id}</td>
                    <td class="font-mono text-sm">{user.email}</td>
                    <td class="text-sm">
                      <%= if user.profile_url do %>
                        <a href={user.profile_url} target="_blank" class="link text-sm">Profile</a>
                      <% else %>
                        -
                      <% end %>
                    </td>
                    <td class="font-mono text-xs">{user.discord_id || "-"}</td>
                    <td class="font-mono text-xs">{user.steam_id || "-"}</td>
                    <td>
                      <%= if user.confirmed_at do %>
                        <span class="badge badge-success badge-sm">Yes</span>
                      <% else %>
                        <span class="badge badge-warning badge-sm">No</span>
                      <% end %>
                    </td>
                    <td class="text-sm">
                      <.timestamp at={user.inserted_at} />
                    </td>
                    <td>
                      <div class="flex gap-2">
                        <button
                          phx-click="edit_user"
                          phx-value-id={user.id}
                          class="btn btn-sm btn-ghost"
                        >
                          Edit
                        </button>
                        <button
                          phx-click="delete_user"
                          phx-value-id={user.id}
                          data-confirm="Are you sure you want to delete this user?"
                          class="btn btn-sm btn-error btn-ghost"
                        >
                          Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
          <div class="mt-4 px-4">
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

        <%!-- Edit User Modal --%>
        <div :if={@selected_user} class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">Edit User #{@selected_user.id}</h3>
            <.form
              for={@form}
              id="user-form"
              phx-submit="save_user"
              class="space-y-4"
            >
              <.input
                field={@form[:email]}
                type="email"
                label="Email"
                required
              />

              <div class="form-control">
                <label class="label cursor-pointer">
                  <span class="label-text">Confirmed</span>
                  <input
                    type="checkbox"
                    name="user[confirmed]"
                    checked={!!@selected_user.confirmed_at}
                    class="checkbox"
                  />
                </label>
              </div>

              <div class="modal-action">
                <button type="button" phx-click="cancel_edit" class="btn btn-ghost">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary">
                  Save
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    page = 1
    page_size = 25

    users =
      Repo.all(
        from u in User,
          order_by: [desc: u.inserted_at],
          offset: ^((page - 1) * page_size),
          limit: ^page_size
      )

    total_count = Repo.aggregate(User, :count)
    total_pages = if page_size > 0, do: div(total_count + page_size - 1, page_size), else: 0

    {:ok,
     socket
     |> assign(:users, users)
     |> assign(:users_page, page)
     |> assign(:users_page_size, page_size)
     |> assign(:users_total_pages, total_pages)
     |> assign(:users_count, total_count)
     |> assign(:selected_user, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("edit_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    form = to_form(changeset, as: "user")

    {:noreply,
     socket
     |> assign(:selected_user, user)
     |> assign(:form, form)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:form, nil)}
  end

  def handle_event("save_user", %{"user" => user_params}, socket) do
    user = socket.assigns.selected_user

    attrs =
      Map.put(
        user_params,
        "confirmed_at",
        if(user_params["confirmed"] == "on", do: DateTime.utc_now(:second), else: nil)
      )

    case update_user(user, attrs) do
      {:ok, _user} ->
        page = socket.assigns[:users_page] || 1
        page_size = socket.assigns[:users_page_size] || 25

        users =
          Repo.all(
            from u in User,
              order_by: [desc: u.inserted_at],
              offset: ^((page - 1) * page_size),
              limit: ^page_size
          )

        total_count = Repo.aggregate(User, :count)
        total_pages = if page_size > 0, do: div(total_count + page_size - 1, page_size), else: 0

        {:noreply,
         socket
         |> put_flash(:info, "User updated successfully")
         |> assign(:users, users)
         |> assign(:users_total_pages, total_pages)
         |> assign(:selected_user, nil)
         |> assign(:form, nil)}

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

        total_count = Repo.aggregate(User, :count)
        total_pages = if page_size > 0, do: div(total_count + page_size - 1, page_size), else: 0

        page = max(1, min(page, total_pages))

        users =
          Repo.all(
            from u in User,
              order_by: [desc: u.inserted_at],
              offset: ^((page - 1) * page_size),
              limit: ^page_size
          )

        {:noreply,
         socket
         |> put_flash(:info, "User deleted successfully")
         |> assign(:users, users)
         |> assign(:users_page, page)
         |> assign(:users_total_pages, total_pages)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete user")}
    end
  end

  @impl true
  def handle_event("admin_users_prev", _params, socket) do
    page = max(1, (socket.assigns[:users_page] || 1) - 1)
    page_size = socket.assigns[:users_page_size] || 25

    users =
      Repo.all(
        from u in User,
          order_by: [desc: u.inserted_at],
          offset: ^((page - 1) * page_size),
          limit: ^page_size
      )

    total_count = Repo.aggregate(User, :count)
    total_pages = if page_size > 0, do: div(total_count + page_size - 1, page_size), else: 0

    {:noreply,
     socket
     |> assign(:users_page, page)
     |> assign(:users, users)
     |> assign(:users_count, total_count)
     |> assign(:users_total_pages, total_pages)}
  end

  def handle_event("admin_users_next", _params, socket) do
    page = (socket.assigns[:users_page] || 1) + 1
    page_size = socket.assigns[:users_page_size] || 25

    users =
      Repo.all(
        from u in User,
          order_by: [desc: u.inserted_at],
          offset: ^((page - 1) * page_size),
          limit: ^page_size
      )

    total_count = Repo.aggregate(User, :count)
    total_pages = if page_size > 0, do: div(total_count + page_size - 1, page_size), else: 0

    {:noreply,
     socket
     |> assign(:users_page, page)
     |> assign(:users, users)
     |> assign(:users_count, total_count)
     |> assign(:users_total_pages, total_pages)}
  end

  def handle_event("admin_users_page_size", %{"size" => size}, socket) do
    page_size = String.to_integer(size)

    users =
      Repo.all(
        from u in User,
          order_by: [desc: u.inserted_at],
          offset: 0,
          limit: ^page_size
      )

    total_count = Repo.aggregate(User, :count)
    total_pages = if page_size > 0, do: div(total_count + page_size - 1, page_size), else: 0

    {:noreply,
     socket
     |> assign(:users_page_size, page_size)
     |> assign(:users_page, 1)
     |> assign(:users, users)
     |> assign(:users_count, total_count)
     |> assign(:users_total_pages, total_pages)}
  end

  defp update_user(user, attrs) do
    user
    |> Ecto.Changeset.cast(attrs, [:email, :confirmed_at])
    |> Ecto.Changeset.validate_required([:email])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email"
    )
    |> Ecto.Changeset.unique_constraint(:email)
    |> Repo.update()
  end
end
