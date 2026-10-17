defmodule GamendWeb.LobbyLive.Index do
  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Lobbies
  alias GamendWeb.LiveHelpers

  @impl true
  def mount(_params, _session, socket) do
    # Get current user from scope if available
    user = Scope.user(socket.assigns[:current_scope])

    # Subscribe to global lobby events
    if connected?(socket) do
      Lobbies.subscribe_lobbies()

      # If user is in a lobby, subscribe to that lobby's events
      if user && user.lobby_id do
        Lobbies.subscribe_lobby(user.lobby_id)
      end
    end

    # default pagination values for the lobbies listing
    lobbies_page = 1
    lobbies_page_size = 12

    lobbies =
      Lobbies.list_lobbies_for_user(user, %{}, page: lobbies_page, page_size: lobbies_page_size)

    total_count = Lobbies.count_list_lobbies(%{})

    total_pages =
      LiveHelpers.total_pages(total_count, lobbies_page_size)

    memberships_map =
      Enum.into(lobbies, %{}, fn l -> {l.id, Lobbies.list_memberships_for_lobby(l.id)} end)

    {:ok,
     assign(socket,
       page_title: gettext("Lobbies"),
       lobbies: lobbies,
       memberships_map: memberships_map,
       lobbies_page: lobbies_page,
       lobbies_page_size: lobbies_page_size,
       lobbies_total: total_count,
       lobbies_total_pages: total_pages,
       title: "",
       joining_lobby_id: nil,
       join_password: "",
       editing_lobby_id: nil,
       edit_attrs: %{},
       editing_can_edit: false,
       subscribed_lobby_id: user && user.lobby_id
     )}
  end

  # Which lobby is being joined or managed lives in the URL (`join`, `manage`):
  # a reconnect re-mounts the view, and the form has to be in the new render for
  # LiveView to recover what was typed into it.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign_joining(params["join"])
     |> assign_managing(params["manage"])}
  end

  @impl true
  def handle_event("create_change", %{"title" => title}, socket) do
    {:noreply, assign(socket, title: title)}
  end

  def handle_event("create", %{"title" => title}, socket) do
    attrs = %{"title" => title}

    case socket.assigns.current_scope do
      %{user_id: id} when id != nil ->
        attrs = Map.put(attrs, "host_id", id)

        # prevent creating more than one lobby for the same user
        case Accounts.get_user(id) do
          %Gamend.Accounts.User{lobby_id: existing} when existing != nil ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Failed")
             )}

          _ ->
            create_lobby_for_user(socket, attrs, id)
        end

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}
    end
  end

  def handle_event("leave", _params, socket) do
    case Scope.user(socket.assigns.current_scope) do
      %User{} = user ->
        case Lobbies.leave_lobby(user) do
          {:ok, _} ->
            # refresh user to update lobby_id first (nil once deleted: a guest's list)
            refreshed_user = Gamend.Accounts.get_user(user.id)

            lobbies =
              Lobbies.list_lobbies_for_user(refreshed_user, %{},
                page: socket.assigns[:lobbies_page] || 1,
                page_size: socket.assigns[:lobbies_page_size] || 12
              )

            memberships_map =
              Enum.into(lobbies, %{}, fn l -> {l.id, Lobbies.list_memberships_for_lobby(l.id)} end)

            updated_scope = socket.assigns.current_scope

            {:noreply,
             assign(socket,
               lobbies: lobbies,
               memberships_map: memberships_map,
               current_scope: updated_scope
             )}

          {:error, reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               LiveHelpers.failure_message(gettext("Failed"), reason)
             )}
        end

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}
    end
  end

  def handle_event("join_lobby", %{"id" => id}, socket) do
    case Lobbies.get_lobby(id) do
      lobby when lobby != nil ->
        if lobby.password_hash != nil do
          {:noreply, patch_lobbies(socket, join: lobby.id)}
        else
          # Public lobby, join directly
          handle_start_join_for_lobby(socket, lobby)
        end

      nil ->
        {:noreply, put_flash(socket, :error, gettext("Not found"))}
    end
  end

  def handle_event("confirm_join", %{"_id" => id, "password" => password}, socket) do
    case Scope.user(socket.assigns.current_scope) do
      %User{} = user ->
        confirm_lobby_join(socket, user, id, password)

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}
    end
  end

  def handle_event("join_change", %{"password" => password}, socket) do
    {:noreply, assign(socket, join_password: password)}
  end

  @impl true
  def handle_event("start_join", %{"id" => id}, socket) do
    case parse_int(id) do
      {:ok, lobby_id} ->
        case Lobbies.get_lobby(lobby_id) do
          nil ->
            {:noreply, put_flash(socket, :error, gettext("Not found"))}

          %{} = l when l.is_locked ->
            {:noreply, put_flash(socket, :error, gettext("Failed"))}

          %{} = l when l.password_hash != nil ->
            {:noreply, patch_lobbies(socket, join: l.id)}

          %{} = l ->
            # delegate the complicated user check / join flow to helpers to keep
            # the public handler shallow and readable
            handle_start_join_for_lobby(socket, l)
        end

      :error ->
        {:noreply, put_flash(socket, :error, gettext("Not found"))}
    end
  end

  def handle_event("cancel_join", _params, socket) do
    {:noreply, patch_lobbies(socket, join: nil)}
  end

  def handle_event("start_manage", %{"id" => id}, socket) do
    {:noreply, patch_lobbies(socket, manage: id)}
  end

  def handle_event("cancel_manage", _params, socket) do
    {:noreply, patch_lobbies(socket, manage: nil)}
  end

  def handle_event("manage_change", params, socket) do
    if (params["_id"] || params["id"]) == socket.assigns.editing_lobby_id do
      edit_attrs = %{
        "title" => params["title"] || "",
        "max_users" => params["max_users"],
        "is_hidden" => params["is_hidden"] == "true",
        "is_locked" => params["is_locked"] == "true",
        "password" => params["password"] || ""
      }

      {:noreply, assign(socket, edit_attrs: edit_attrs)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_lobby", params, socket) do
    case Scope.user(socket.assigns.current_scope) do
      %User{} = user ->
        id = params["_id"] || params["id"]
        lobby = Lobbies.get_lobby(id)

        attrs = %{}
        attrs = if params["title"], do: Map.put(attrs, "title", params["title"]), else: attrs

        # A player-facing form: `String.to_integer/1` here crashed the page on a
        # non-numeric value. An unparseable one is simply not applied.
        attrs =
          case Gamend.Parse.integer(params["max_users"]) do
            nil -> attrs
            max_users -> Map.put(attrs, "max_users", max_users)
          end

        attrs =
          if Map.get(params, "is_locked") == "true",
            do: Map.put(attrs, "is_locked", true),
            else: Map.put(attrs, "is_locked", false)

        attrs =
          if Map.get(params, "is_hidden") == "true",
            do: Map.put(attrs, "is_hidden", true),
            else: Map.put(attrs, "is_hidden", false)

        attrs =
          if params["password"] && params["password"] != "",
            do: Map.put(attrs, "password", params["password"]),
            else: attrs

        case Lobbies.update_lobby_by_host(user, lobby, attrs) do
          {:ok, updated_lobby} ->
            lobbies =
              Lobbies.list_lobbies_for_user(user, %{},
                page: socket.assigns[:lobbies_page] || 1,
                page_size: socket.assigns[:lobbies_page_size] || 12
              )

            memberships_map =
              Enum.into(lobbies, %{}, fn lp ->
                {lp.id, Lobbies.list_memberships_for_lobby(lp.id)}
              end)

            {:noreply,
             socket
             |> put_flash(:info, gettext("Success."))
             |> assign(
               lobbies: lobbies,
               memberships_map: memberships_map,
               editing_lobby_id: updated_lobby.id,
               # refresh edit_attrs so the form shows updated values
               edit_attrs: edit_attrs(updated_lobby)
             )}

          {:error, reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               LiveHelpers.failure_message(gettext("Failed"), reason)
             )}
        end

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}
    end
  end

  def handle_event("kick", %{"lobby_id" => lobby_id, "target_id" => target_id}, socket) do
    case Scope.user(socket.assigns.current_scope) do
      %User{} = user ->
        # Either may be gone since the page drew them: kick_user/3 answers that.
        lobby = Lobbies.get_lobby(lobby_id)
        target = Gamend.Accounts.get_user(target_id)

        case Lobbies.kick_user(user, lobby, target) do
          {:ok, _} ->
            lobbies =
              Lobbies.list_lobbies_for_user(user, %{},
                page: socket.assigns[:lobbies_page] || 1,
                page_size: socket.assigns[:lobbies_page_size] || 12
              )

            memberships_map =
              Enum.into(lobbies, %{}, fn lp ->
                {lp.id, Lobbies.list_memberships_for_lobby(lp.id)}
              end)

            {:noreply, assign(socket, lobbies: lobbies, memberships_map: memberships_map)}

          {:error, reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               LiveHelpers.failure_message(gettext("Failed"), reason)
             )}
        end

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}
    end
  end

  def handle_event("lobbies_prev", _params, socket) do
    page = max(1, (socket.assigns[:lobbies_page] || 1) - 1)
    {:noreply, refresh_lobbies(assign(socket, lobbies_page: page))}
  end

  def handle_event("lobbies_next", _params, socket) do
    page = (socket.assigns[:lobbies_page] || 1) + 1
    {:noreply, refresh_lobbies(assign(socket, lobbies_page: page))}
  end

  defp create_lobby_for_user(socket, attrs, user_id) do
    case Lobbies.create_lobby(attrs) do
      {:ok, _lobby} ->
        # refresh user to update lobby_id first (nil once deleted: a guest's list)
        refreshed_user = Gamend.Accounts.get_user(user_id)

        lobbies =
          Lobbies.list_lobbies_for_user(refreshed_user, %{},
            page: socket.assigns[:lobbies_page] || 1,
            page_size: socket.assigns[:lobbies_page_size] || 12
          )

        memberships_map =
          Enum.into(lobbies, %{}, fn l ->
            {l.id, Lobbies.list_memberships_for_lobby(l.id)}
          end)

        updated_scope = socket.assigns.current_scope

        {:noreply,
         assign(socket,
           lobbies: lobbies,
           memberships_map: memberships_map,
           title: "",
           current_scope: updated_scope
         )}

      {:error, :already_in_lobby} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Failed")
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp confirm_lobby_join(socket, user, lobby_id, password) do
    # use atom-keyed map so the Lobbies.do_join Map.get(:password) recognizes it
    result = Lobbies.join_lobby(user, lobby_id, %{password: password})

    case result do
      {:ok, _} ->
        # refresh user to update lobby_id first (nil once deleted: a guest's list)
        refreshed_user = Gamend.Accounts.get_user(user.id)

        lobbies =
          Lobbies.list_lobbies_for_user(refreshed_user, %{},
            page: socket.assigns[:lobbies_page] || 1,
            page_size: socket.assigns[:lobbies_page_size] || 12
          )

        memberships_map =
          Enum.into(lobbies, %{}, fn lp ->
            {lp.id, Lobbies.list_memberships_for_lobby(lp.id)}
          end)

        updated_scope = socket.assigns.current_scope

        {:noreply,
         socket
         |> assign(
           lobbies: lobbies,
           memberships_map: memberships_map,
           current_scope: updated_scope
         )
         |> patch_lobbies(join: nil)}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           LiveHelpers.failure_message(gettext("Failed"), reason)
         )}
    end
  end

  # Helpers for start_join flow that were moved here so all public
  # `handle_event/3` clauses stay grouped together at the top of the file.
  defp handle_start_join_for_lobby(socket, lobby) do
    case Scope.user(socket.assigns.current_scope) do
      %User{} = user -> handle_start_join_for_user(socket, lobby, user)
      _ -> {:noreply, push_navigate(socket, to: ~p"/users/log_in")}
    end
  end

  defp handle_start_join_for_user(socket, lobby, user) do
    if user.lobby_id == lobby.id do
      {:noreply, put_flash(socket, :info, gettext("Joined"))}
    else
      case Lobbies.join_lobby(user, lobby.id) do
        {:ok, _member} ->
          # refresh user to update lobby_id first (nil once deleted: a guest's list)
          refreshed_user = Gamend.Accounts.get_user(user.id)

          lobbies =
            Lobbies.list_lobbies_for_user(refreshed_user, %{},
              page: socket.assigns[:lobbies_page] || 1,
              page_size: socket.assigns[:lobbies_page_size] || 12
            )

          memberships_map =
            Enum.into(lobbies, %{}, fn lp ->
              {lp.id, Lobbies.list_memberships_for_lobby(lp.id)}
            end)

          updated_scope = socket.assigns.current_scope

          {:noreply,
           assign(socket,
             lobbies: lobbies,
             memberships_map: memberships_map,
             current_scope: updated_scope
           )}

        {:error, reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             LiveHelpers.failure_message(gettext("Failed"), reason)
           )}
      end
    end
  end

  defp parse_int(v) when is_binary(v), do: Ecto.UUID.cast(v)
  defp parse_int(_), do: :error

  # Re-applying the open lobby keeps what was typed into its form so far.
  defp assign_joining(%{assigns: %{joining_lobby_id: id}} = socket, id) when id != nil,
    do: socket

  defp assign_joining(socket, id) do
    case id && Lobbies.get_lobby(id) do
      %{password_hash: hash} = lobby when hash != nil ->
        assign(socket, joining_lobby_id: lobby.id, join_password: "")

      _ ->
        assign(socket, joining_lobby_id: nil, join_password: "")
    end
  end

  defp assign_managing(%{assigns: %{editing_lobby_id: id}} = socket, id) when id != nil,
    do: socket

  defp assign_managing(socket, id) do
    case id && Lobbies.get_lobby(id) do
      %{} = lobby ->
        # everyone without authority over the lobby gets a view-only modal
        can_edit = Lobbies.can_manage_lobby?(Scope.user(socket.assigns.current_scope), lobby)

        assign(socket,
          editing_lobby_id: lobby.id,
          edit_attrs: edit_attrs(lobby),
          editing_can_edit: can_edit
        )

      _ ->
        assign(socket, editing_lobby_id: nil, edit_attrs: %{}, editing_can_edit: false)
    end
  end

  defp edit_attrs(lobby) do
    %{
      "title" => lobby.title || "",
      "max_users" => lobby.max_users,
      "is_hidden" => lobby.is_hidden,
      "is_locked" => lobby.is_locked
    }
  end

  defp patch_lobbies(socket, changes) do
    query =
      [join: socket.assigns.joining_lobby_id, manage: socket.assigns.editing_lobby_id]
      |> Keyword.merge(changes)
      |> Enum.reject(fn {_key, id} -> is_nil(id) end)

    push_patch(socket, to: ~p"/admin/lobbies/live?#{query}", replace: true)
  end

  # PubSub handlers for real-time updates

  @impl true
  def handle_info({:lobby_created, _lobby}, socket) do
    {:noreply, refresh_lobbies(socket)}
  end

  @impl true
  def handle_info({:lobby_updated, _lobby}, socket) do
    {:noreply, refresh_lobbies(socket)}
  end

  @impl true
  def handle_info({:lobby_deleted, _lobby_id}, socket) do
    {:noreply, refresh_lobbies(socket)}
  end

  @impl true
  def handle_info({:lobby_membership_changed, _lobby_id}, socket) do
    {:noreply, refresh_lobbies(socket)}
  end

  @impl true
  def handle_info({:user_joined, lobby_id, _user_id}, socket) do
    # Update memberships for the specific lobby
    {:noreply, refresh_lobby_memberships(socket, lobby_id)}
  end

  @impl true
  def handle_info({:user_left, lobby_id, _user_id}, socket) do
    {:noreply, refresh_lobby_memberships(socket, lobby_id)}
  end

  @impl true
  def handle_info({:user_kicked, lobby_id, user_id}, socket) do
    socket = refresh_lobby_memberships(socket, lobby_id)

    # If I was kicked, update my user state and show a message
    case socket.assigns.current_scope do
      %{user_id: ^user_id} ->
        updated_scope = socket.assigns.current_scope

        # Unsubscribe from the old lobby
        if socket.assigns[:subscribed_lobby_id] do
          Lobbies.unsubscribe_lobby(socket.assigns.subscribed_lobby_id)
        end

        {:noreply,
         socket
         |> assign(current_scope: updated_scope, subscribed_lobby_id: nil)
         |> patch_lobbies(manage: nil)
         |> put_flash(:error, gettext("Removed"))}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:host_changed, lobby_id, _new_host_id}, socket) do
    {:noreply, refresh_lobby_memberships(socket, lobby_id)}
  end

  # Catch-all for unexpected PubSub messages to prevent LiveView crashes
  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Helper to refresh all lobbies and memberships
  defp refresh_lobbies(socket) do
    user =
      case Scope.user(socket.assigns[:current_scope]) do
        %{} = u ->
          u

        _ ->
          nil
      end

    lobbies =
      Lobbies.list_lobbies_for_user(user, %{},
        page: socket.assigns[:lobbies_page] || 1,
        page_size: socket.assigns[:lobbies_page_size] || 12
      )

    memberships_map =
      Enum.into(lobbies, %{}, fn l -> {l.id, Lobbies.list_memberships_for_lobby(l.id)} end)

    # Update subscription if user's lobby changed
    socket = maybe_update_lobby_subscription(socket, user)

    # Update current_scope with refreshed user
    socket =
      if user do
        updated_scope = socket.assigns.current_scope
        assign(socket, current_scope: updated_scope)
      else
        socket
      end

    total_count = Lobbies.count_list_lobbies(%{})

    total_pages =
      if (socket.assigns[:lobbies_page_size] || 12) > 0,
        do:
          div(
            total_count + (socket.assigns[:lobbies_page_size] || 12) - 1,
            socket.assigns[:lobbies_page_size] || 12
          ),
        else: 0

    assign(socket,
      lobbies: lobbies,
      memberships_map: memberships_map,
      lobbies_total: total_count,
      lobbies_total_pages: total_pages
    )
  end

  # Helper to refresh just one lobby's memberships
  defp refresh_lobby_memberships(socket, lobby_id) do
    memberships = Lobbies.list_memberships_for_lobby(lobby_id)
    memberships_map = Map.put(socket.assigns.memberships_map, lobby_id, memberships)

    # Also refresh the lobby itself in case it was updated
    user = Scope.user(socket.assigns[:current_scope])

    lobbies =
      Lobbies.list_lobbies_for_user(user, %{},
        page: socket.assigns[:lobbies_page] || 1,
        page_size: socket.assigns[:lobbies_page_size] || 12
      )

    assign(socket, lobbies: lobbies, memberships_map: memberships_map)
  end

  # Helper to manage lobby subscriptions
  defp maybe_update_lobby_subscription(socket, user) do
    current_subscription = socket.assigns[:subscribed_lobby_id]
    new_lobby_id = user && user.lobby_id

    cond do
      current_subscription == new_lobby_id ->
        # No change needed
        socket

      current_subscription != nil and new_lobby_id != current_subscription ->
        # Unsubscribe from old, subscribe to new
        Lobbies.unsubscribe_lobby(current_subscription)

        if new_lobby_id do
          Lobbies.subscribe_lobby(new_lobby_id)
        end

        assign(socket, subscribed_lobby_id: new_lobby_id)

      new_lobby_id != nil ->
        # Subscribe to new lobby
        Lobbies.subscribe_lobby(new_lobby_id)
        assign(socket, subscribed_lobby_id: new_lobby_id)

      true ->
        socket
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="p-6">
        <.link navigate={~p"/admin"} class="btn btn-surface mb-4">← Back to Admin</.link>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mt-4">
          <div class="card bg-base-200 p-4 rounded-lg">
            <div class="font-semibold">{gettext("Create")}</div>
            <.pagination
              page={@lobbies_page}
              total_pages={@lobbies_total_pages}
              total_count={@lobbies_total}
              on_prev="lobbies_prev"
              on_next="lobbies_next"
              class="mt-2"
            />

            <form
              id="lobby-create-form"
              phx-change="create_change"
              phx-submit="create"
              phx-no-unused-field
              class="mt-4 space-y-3"
            >
              <.input name="title" label={gettext("Title")} value={@title} />
              <div class="flex items-center gap-2">
                <button type="submit" class="btn btn-primary">{gettext("Create")}</button>
                <%= if @current_scope && Scope.user(@current_scope) && Scope.user(@current_scope).lobby_id do %>
                  <span class="text-sm text-warning">
                    {gettext("Joined")}
                  </span>
                <% end %>
              </div>
            </form>
          </div>

          <div class="lg:col-span-2">
            <div class="font-semibold">{gettext("Lobbies")}</div>
            <div class="mt-3 grid grid-cols-1 md:grid-cols-2 gap-4">
              <div
                :for={lobby <- @lobbies}
                id={"lobby-" <> to_string(lobby.id)}
                class="card bg-base-200 p-4 rounded-lg"
              >
                <div class="flex justify-between items-start">
                  <div>
                    <div class="text-lg font-semibold">{lobby.title}</div>
                    <div class="text-xs text-muted mt-2">
                      {length(@memberships_map[lobby.id] || [])} / {lobby.max_users}
                    </div>
                  </div>
                  <div class="flex flex-col items-end gap-2">
                    <%= if @current_scope && Scope.user(@current_scope) do %>
                      <% user = Scope.user(@current_scope) %>

                      <%= cond do %>
                        <% user.id == lobby.host_id -> %>
                          <%!-- Host sees Manage button --%>
                          <button
                            phx-click="start_manage"
                            phx-value-id={lobby.id}
                            class="btn btn-surface btn-sm"
                          >
                            {gettext("Edit")}
                          </button>
                        <% user.lobby_id == lobby.id -> %>
                          <%!-- Non-host member can View (with Leave inside) --%>
                          <button
                            phx-click="start_manage"
                            phx-value-id={lobby.id}
                            class="btn btn-ghost btn-sm"
                          >
                            {gettext("View")}
                          </button>
                        <% user.lobby_id != nil -> %>
                          <%!-- User in another lobby can only view this one --%>
                          <button
                            phx-click="start_manage"
                            phx-value-id={lobby.id}
                            class="btn btn-ghost btn-sm"
                          >
                            {gettext("View")}
                          </button>
                        <% lobby.is_locked -> %>
                          <button class="btn btn-disabled btn-sm">{gettext("Locked")}</button>
                        <% true -> %>
                          <button
                            phx-click="start_join"
                            phx-value-id={lobby.id}
                            class="btn btn-primary btn-sm"
                          >
                            {gettext("Join")}
                          </button>
                      <% end %>
                    <% else %>
                      <%= if lobby.is_locked do %>
                        <button class="btn btn-disabled btn-sm">{gettext("Locked")}</button>
                      <% else %>
                        <button
                          phx-click="start_join"
                          phx-value-id={lobby.id}
                          class="btn btn-primary btn-sm"
                        >
                          {gettext("Join")}
                        </button>
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <%= if @joining_lobby_id == lobby.id do %>
                  <div class="mt-3">
                    <form
                      id={"lobby-join-" <> to_string(lobby.id)}
                      phx-change="join_change"
                      phx-submit="confirm_join"
                      phx-no-unused-field
                    >
                      <input type="hidden" name="_id" value={lobby.id} />
                      <div class="flex items-center gap-2">
                        <input
                          name="password"
                          value={@join_password}
                          placeholder={gettext("Password")}
                          class="input input-sm"
                        />
                        <button type="submit" class="btn btn-primary btn-sm">
                          {gettext("Confirm")}
                        </button>
                        <button type="button" phx-click="cancel_join" class="btn btn-ghost btn-sm">
                          {gettext("Cancel")}
                        </button>
                      </div>
                    </form>
                  </div>
                <% end %>

                <%= if @editing_lobby_id == lobby.id do %>
                  <div class="mt-3 bg-base-300 p-3 rounded">
                    <%= if @editing_can_edit do %>
                      <form
                        id={"lobby-manage-" <> to_string(lobby.id)}
                        phx-change="manage_change"
                        phx-submit="update_lobby"
                        phx-no-unused-field
                      >
                        <input type="hidden" name="_id" value={lobby.id} />
                        <div class="grid grid-cols-1 gap-2">
                          <input
                            name="title"
                            class="input input-sm"
                            value={@edit_attrs["title"] || lobby.title || ""}
                          />
                          <input
                            name="max_users"
                            type="number"
                            class="input input-sm"
                            value={@edit_attrs["max_users"] || lobby.max_users}
                          />
                          <div class="flex items-center gap-2">
                            <input
                              type="checkbox"
                              name="is_locked"
                              value="true"
                              checked={@edit_attrs["is_locked"]}
                            />
                            <label class="text-sm">{gettext("Locked")}</label>
                          </div>
                          <div class="flex items-center gap-2">
                            <input
                              type="checkbox"
                              name="is_hidden"
                              value="true"
                              checked={@edit_attrs["is_hidden"]}
                            />
                            <label class="text-sm">{gettext("Hidden")}</label>
                          </div>
                          <input
                            name="password"
                            class="input input-sm"
                            value={@edit_attrs["password"]}
                            placeholder={gettext("Clear")}
                          />
                          <div class="flex items-center gap-2 mt-2">
                            <button type="submit" class="btn btn-primary btn-sm">
                              {gettext("Save")}
                            </button>
                            <button
                              type="button"
                              phx-click="cancel_manage"
                              class="btn btn-ghost btn-sm"
                            >
                              {gettext("Close")}
                            </button>
                          </div>
                        </div>
                      </form>

                      <div class="mt-3">
                        <h4 class="font-semibold">{gettext("Members")}</h4>
                        <ul>
                          <li
                            :for={m <- @memberships_map[lobby.id] || []}
                            id={"member-" <> to_string(m.id)}
                            class="flex items-center justify-between py-1"
                          >
                            <div><.player_name name={LiveHelpers.public_user_name(m)} /></div>
                            <div class="flex items-center gap-2">
                              <%= if m.id == lobby.host_id do %>
                                <span class="text-xs text-muted">
                                  {gettext("Host")}
                                </span>
                              <% end %>
                              <%= cond do %>
                                <% @current_scope && Scope.user(@current_scope) && m.id == @current_scope.user_id -> %>
                                  <%!-- Current user (host or member) can leave --%>
                                  <button phx-click="leave" class="btn btn-sm btn-warning">
                                    {gettext("Leave")}
                                  </button>
                                <% m.id == lobby.host_id -> %>
                                  <%!-- Host row without Leave (handled above if current user) --%>
                                <% true -> %>
                                  <button
                                    phx-click="kick"
                                    phx-value-lobby_id={lobby.id}
                                    phx-value-target_id={m.id}
                                    class="btn btn-surface btn-xs"
                                  >
                                    {gettext("Kick")}
                                  </button>
                              <% end %>
                            </div>
                          </li>
                        </ul>
                      </div>
                    <% else %>
                      <div class="mt-3">
                        <h4 class="font-semibold">{gettext("Members")}</h4>
                        <ul>
                          <li
                            :for={m <- @memberships_map[lobby.id] || []}
                            id={"member-" <> to_string(m.id)}
                            class="flex items-center justify-between py-1"
                          >
                            <div><.player_name name={LiveHelpers.public_user_name(m)} /></div>
                            <div>
                              <%= if m.id == lobby.host_id do %>
                                <span class="text-xs text-muted">
                                  {gettext("Host")}
                                </span>
                              <% end %>
                              <%= if @current_scope && Scope.user(@current_scope) && m.id == @current_scope.user_id do %>
                                <button phx-click="leave" class="btn btn-sm btn-warning ms-2">
                                  {gettext("Leave")}
                                </button>
                              <% end %>
                            </div>
                          </li>
                        </ul>
                      </div>
                      <div class="flex items-center gap-2 mt-2">
                        <button type="button" phx-click="cancel_manage" class="btn btn-ghost btn-sm">
                          {gettext("Close")}
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
