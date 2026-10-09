defmodule GamendWeb.NotificationsLive do
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Notifications
  alias GamendWeb.LiveHelpers

  @page_size 25

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <div class="flex items-center gap-3">
              <.back_link href={home_path()} />
              <h1 class="text-4xl font-black text-base-content">{gettext("Notifications")}</h1>
            </div>
            <p class="text-muted mt-1">
              {@notif_count} / {@notif_unread_count}
            </p>
          </div>
          <div class="flex gap-2">
            <%= if @notif_count > 0 do %>
              <button
                type="button"
                phx-click="delete_all"
                data-confirm={gettext("Delete all notifications?")}
                class="btn btn-sm btn-outline btn-error"
              >
                {gettext("Delete all")}
              </button>
            <% end %>
          </div>
        </div>

        <%= if @notif_count > 0 do %>
          <div class="card bg-base-200 p-4 rounded-lg">
            <div class="overflow-x-auto">
              <table id="notifications-table" class="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>{gettext("Title")}</th>
                    <th>{gettext("From")}</th>
                    <th>{gettext("Date")}</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={n <- @notifications}
                    id={"notif-" <> to_string(n.id)}
                  >
                    <td class="text-sm">
                      <div class="flex items-center gap-2">
                        <.entity_icon
                          icon_url={n.icon_url}
                          type={:notification}
                          class="w-4 h-4 shrink-0 text-muted"
                        />
                        {translate_notification_title(n)}
                      </div>
                    </td>
                    <td class="text-sm">
                      <%= cond do %>
                        <% n.metadata["chat_type"] != nil -> %>
                          <span class="badge badge-sm badge-outline badge-info">
                            {gettext("Chat")}
                          </span>
                        <% Ecto.assoc_loaded?(n.sender) && n.sender -> %>
                          <.player_name name={LiveHelpers.public_user_name(n.sender)} />
                        <% true -> %>
                          <.player_name name={LiveHelpers.public_user_name(n.sender_id)} />
                      <% end %>
                    </td>
                    <td class="text-sm whitespace-nowrap">
                      <.timestamp at={n.inserted_at} />
                    </td>
                    <td class="flex gap-1 flex-wrap">
                      <%= if action = notification_action(n) do %>
                        <% {label, path} = action %>
                        <.link navigate={path} class="btn btn-sm btn-outline btn-primary">
                          {label}
                        </.link>
                      <% end %>
                      <button
                        type="button"
                        phx-click="delete"
                        phx-value-id={n.id}
                        class="btn btn-sm btn-outline btn-error"
                      >
                        {gettext("Delete")}
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="mt-4">
              <.pagination
                page={@notif_page}
                total_pages={@notif_total_pages}
                total_count={@notif_count}
                page_size={@notif_page_size}
                on_prev="prev_page"
                on_next="next_page"
                on_page_size="notif_page_size"
              />
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = Scope.user(socket.assigns.current_scope)

    if connected?(socket) do
      Notifications.subscribe(user.id)
      # Auto-mark all notifications as read when the user opens the page
      Notifications.mark_all_notifications_read(user.id)
    end

    socket =
      socket
      |> assign(:page_title, gettext("Notifications"))
      |> assign(:notif_page, 1)
      |> assign(:notif_page_size, @page_size)
      |> assign(:notifications, [])
      |> assign(:notif_count, 0)
      |> assign(:notif_unread_count, 0)
      |> assign(:notif_total_pages, 0)
      |> reload_notifications()

    {:ok, socket}
  end

  @impl true
  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page(:notif_page) |> reload_notifications()}

  def handle_event("next_page", _params, socket),
    do:
      {:noreply,
       socket |> LiveHelpers.next_page(:notif_page, :notif_total_pages) |> reload_notifications()}

  def handle_event("notif_page_size", %{"size" => size}, socket),
    do:
      {:noreply,
       socket
       |> LiveHelpers.put_page_size(size, size_key: :notif_page_size, page_key: :notif_page)
       |> reload_notifications()}

  def handle_event("delete", %{"id" => id}, socket) do
    user = Scope.user(socket.assigns.current_scope)
    Notifications.delete_notifications(user.id, [id])

    {:noreply,
     socket
     |> put_flash(:info, gettext("Success."))
     |> reload_notifications()}
  end

  def handle_event("delete_all", _params, socket) do
    user = Scope.user(socket.assigns.current_scope)

    all_ids =
      Notifications.list_notifications(user.id, page: 1, page_size: 10_000)
      |> Enum.map(& &1.id)

    Notifications.delete_notifications(user.id, all_ids)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Success."))
     |> assign(:notif_page, 1)
     |> reload_notifications()}
  end

  @impl true
  def handle_info({:notification_created, _notification}, socket) do
    user = Scope.user(socket.assigns.current_scope)
    # Auto-mark new notifications as read since the user is viewing the page
    Notifications.mark_all_notifications_read(user.id)
    {:noreply, reload_notifications(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp notification_action(n) do
    case action_for_type(n.metadata["type"], n) || action_for_metadata(n.metadata) do
      {_label, path} = action -> if page_open?(path), do: action
      nil -> nil
    end
  end

  # A notification still arrives when its page is switched off on the site
  # (the game sends chat, group and cup traffic regardless), so its button
  # goes.
  defp page_open?(path) do
    cond do
      under?(path, "/chat") ->
        GamendWeb.Features.enabled?(:web_chat)

      under?(path, "/groups") ->
        GamendWeb.Features.enabled?(:web_groups) and GamendWeb.Features.enabled?(:list_groups)

      under?(path, "/tournaments") ->
        GamendWeb.Features.enabled?(:web_tournaments) and
          GamendWeb.Features.enabled?(:list_tournaments)

      true ->
        true
    end
  end

  defp under?(path, root),
    do: path == root or String.starts_with?(path, [root <> "/", root <> "?"])

  defp action_for_type("group_invite", n) do
    group_id = n.metadata["group_id"]

    if group_id,
      do: {gettext("View"), ~p"/groups/#{group_id}"},
      else: {gettext("View"), ~p"/groups"}
  end

  defp action_for_type("party_invite", _n), do: {gettext("View"), ~p"/play"}
  defp action_for_type("chat_lobby", _n), do: {gettext("Open"), ~p"/play"}
  defp action_for_type("chat_party", _n), do: {gettext("View"), ~p"/play"}

  defp action_for_type("friend_request", _n),
    do: {gettext("View"), ~p"/users/settings?#{[tab: "friends"]}"}

  defp action_for_type("quest_completed", _n),
    do: {gettext("View"), ~p"/quests"}

  defp action_for_type("chat_group", n) do
    group_id = n.metadata["group_id"]

    if group_id,
      do: {gettext("Open"), ~p"/chat?#{[type: "group", id: group_id]}"},
      else: {gettext("Open"), ~p"/chat"}
  end

  defp action_for_type("chat_friend", n) do
    friend_id = n.metadata["friend_id"] || n.metadata["sender_id"]

    if friend_id,
      do: {gettext("Open"), ~p"/chat?#{[type: "friend", id: friend_id]}"},
      else: {gettext("Open"), ~p"/chat"}
  end

  defp action_for_type("friend_accepted", n) do
    friend_id = n.metadata["friend_id"] || n.sender_id

    if friend_id,
      do: {gettext("Open"), ~p"/chat?#{[type: "friend", id: friend_id]}"},
      else: {gettext("Open"), ~p"/chat"}
  end

  defp action_for_type(_type, _n), do: nil

  # Fallback: infer action from metadata keys for notifications without a known type
  # A server notification (`Gamend.Notifications.notify/3`) says where it
  # leads. Only a path on this site: never another host.
  defp action_for_metadata(%{"url" => url}) when is_binary(url) do
    if String.starts_with?(url, "/") and not String.starts_with?(url, ["//", "/\\"]),
      do: {gettext("Open"), url}
  end

  defp action_for_metadata(%{"leaderboard_slug" => slug}) when is_binary(slug),
    do: {gettext("View"), ~p"/leaderboards/#{slug}"}

  defp action_for_metadata(%{"leaderboard_id" => _}),
    do: {gettext("View"), ~p"/leaderboards"}

  defp action_for_metadata(%{"group_id" => group_id}) when is_binary(group_id),
    do: {gettext("View"), ~p"/groups/#{group_id}"}

  defp action_for_metadata(%{"lobby_id" => _}), do: {gettext("Open"), ~p"/play"}
  defp action_for_metadata(%{"party_id" => _}), do: {gettext("View"), ~p"/play"}
  defp action_for_metadata(_), do: nil

  defp reload_notifications(socket) do
    user = Scope.user(socket.assigns.current_scope)
    page = socket.assigns.notif_page
    page_size = socket.assigns.notif_page_size

    notifications = Notifications.list_notifications(user.id, page: page, page_size: page_size)
    count = Notifications.count_notifications(user.id)
    unread_count = Notifications.count_unread_notifications(user.id)
    total_pages = LiveHelpers.total_pages(count, page_size)

    socket
    |> assign(:notifications, notifications)
    |> assign(:notif_count, count)
    |> assign(:notif_unread_count, unread_count)
    |> assign(:notif_total_pages, total_pages)
  end

  # ---------------------------------------------------------------------------
  # Notification display-time translation
  #
  # Most notification types now store the full descriptive title in the DB
  # (e.g. "Alice joined Chess Club"), so we just return n.title directly.
  # Chat and achievement types still use gettext for translatable patterns.
  # ---------------------------------------------------------------------------

  defp translate_notification_title(n), do: title_for_type(n.metadata["type"], n)

  defp title_for_type("chat_friend", _n),
    do: dgettext("notifications", "New messages from friends")

  defp title_for_type("chat_party", _n), do: dgettext("notifications", "New message in party")

  defp title_for_type("quest_completed", n) do
    name = n.metadata["quest_title"] || ""

    if n.metadata["kind"] == "achievement" do
      dgettext("notifications", "Achievement unlocked: %{name}", name: name)
    else
      dgettext("notifications", "Quest completed: %{name}", name: name)
    end
  end

  defp title_for_type("chat_group", n) do
    name = n.metadata["group_name"] || ""
    dgettext("notifications", "New messages from %{name}", name: name)
  end

  defp title_for_type("chat_lobby", n) do
    name = n.metadata["lobby_name"] || ""
    dgettext("notifications", "New messages from %{name}", name: name)
  end

  # All other types: the DB title already contains the full descriptive text
  defp title_for_type(_type, n), do: n.title
end
