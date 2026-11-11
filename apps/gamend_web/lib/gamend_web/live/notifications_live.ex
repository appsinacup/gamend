defmodule GamendWeb.NotificationsLive do
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Notifications
  alias GamendWeb.LiveHelpers
  alias GamendWeb.MountedRoutes
  alias GamendWeb.NotificationEmail
  alias GamendWeb.NotificationsLive.Sections

  # Pages of a fixed size would cut a stack in two, and neither a section (the
  # group is decided in code) nor a stack (the type is in the JSON metadata) is
  # something a query can page by. So the newest rows are arranged whole.
  @load_step 200

  require Gamend.Notifications.NotificationType, as: NotificationType
  require Gamend.Notifications.PreferenceGroup, as: PreferenceGroup
  require GamendWeb.UserLive.Settings.SettingsTab, as: SettingsTab

  require Gamend.Chat.ChatType, as: ChatType
  require Gamend.Quests.QuestCategory, as: QuestCategory

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <%!-- Wraps: on a 360 px phone the title and Delete all overran the
              screen by 10 px. --%>
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div data-heading-fit class="flex items-center gap-3">
              <.page_title
                icon="hero-bell-solid"
                tone={GamendWeb.HostLayouts.nav_tone("/notifications")}
              >
                {gettext("Notifications")}
              </.page_title>
            </div>
            <p class="text-muted mt-1">
              {@notif_count} / {@notif_unread_count}
            </p>
          </div>
          <div class="flex gap-2">
            <.link
              id="notification-settings"
              navigate={~p"/users/settings?tab=notifications"}
              class="btn btn-sm btn-surface"
            >
              <.icon name="hero-cog-6-tooth-solid" class="size-4" />
              {gettext("Settings")}
            </.link>
            <%= if @notif_count > 0 do %>
              <button
                type="button"
                phx-click="delete_all"
                data-confirm
                class="btn btn-sm btn-outline btn-error"
              >
                {gettext("Delete all")}
              </button>
            <% end %>
          </div>
        </div>

        <%= if @notif_count > 0 do %>
          <div id="notifications-sections" class="space-y-3">
            <.notification_section
              :for={section <- @sections}
              section={section}
              collapsed={MapSet.member?(@collapsed_sections, section.key)}
              open_stacks={@open_stacks}
            />

            <div :if={@notif_count > @notif_limit} class="flex justify-center">
              <button
                id="notifications-load-more"
                type="button"
                phx-click="load_more"
                class="btn btn-sm btn-surface"
              >
                {dgettext("notifications", "Load more")}
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :section, :map, required: true
  attr :collapsed, :boolean, required: true
  attr :open_stacks, :any, required: true

  defp notification_section(assigns) do
    assigns = assign(assigns, :label, section_label(assigns.section.key))

    ~H"""
    <section id={"notif-section-" <> @section.key} class="card bg-base-200 p-4 rounded-lg">
      <div class="flex items-center gap-2">
        <h2 class="min-w-0 flex-1">
          <button
            id={"notif-section-toggle-" <> @section.key}
            type="button"
            phx-click="toggle_section"
            phx-value-section={@section.key}
            aria-expanded={to_string(!@collapsed)}
            class="flex w-full cursor-pointer items-center gap-2 text-start font-semibold"
          >
            <.fold_chevron folded={@collapsed} />
            <.icon name={section_icon(@section.key)} class="size-5 shrink-0 text-muted" />
            <span class="truncate">{@label}</span>
            <span class="badge badge-sm shrink-0">{@section.count}</span>
          </button>
        </h2>
        <.delete_button
          id={"notif-section-delete-" <> @section.key}
          label={gettext("Delete") <> ": " <> @label}
          phx-click="delete_section"
          phx-value-section={@section.key}
          data-confirm
        />
      </div>

      <div :if={!@collapsed} class="mt-3 space-y-2">
        <%= for stack <- @section.stacks do %>
          <%= case stack.notifications do %>
            <% [notification] -> %>
              <.notification_row notification={notification} boxed />
            <% _several -> %>
              <.notification_stack stack={stack} open={MapSet.member?(@open_stacks, stack.key)} />
          <% end %>
        <% end %>
      </div>
    </section>
    """
  end

  attr :stack, :map, required: true
  attr :open, :boolean, required: true

  defp notification_stack(assigns) do
    assigns =
      assign(assigns,
        title: stack_title(assigns.stack),
        count: length(assigns.stack.notifications),
        newest_at: hd(assigns.stack.notifications).inserted_at
      )

    ~H"""
    <div id={"notif-stack-" <> @stack.key}>
      <div class="flex items-center gap-2 rounded-lg border border-base-300 bg-base-100 ps-2 pe-1">
        <button
          id={"notif-stack-toggle-" <> @stack.key}
          type="button"
          phx-click="toggle_stack"
          phx-value-stack={@stack.key}
          aria-expanded={to_string(@open)}
          class="flex min-w-0 flex-1 cursor-pointer items-center gap-2 py-2 text-start text-sm"
        >
          <.fold_chevron folded={!@open} />
          <span class="truncate font-medium">{@title}</span>
          <.timestamp
            at={@newest_at}
            format="relative"
            class="ms-auto shrink-0 whitespace-nowrap text-muted"
          />
        </button>
        <.delete_button
          id={"notif-stack-delete-" <> @stack.key}
          label={gettext("Delete") <> ": " <> @title}
          phx-click="delete_stack"
          phx-value-stack={@stack.key}
          data-confirm
        />
      </div>

      <%!-- The cards under the top one: what makes a closed stack read as
            several notices at a glance. --%>
      <div :if={!@open} aria-hidden="true">
        <div class="mx-2 h-1 rounded-b-lg border border-t-0 border-base-300 bg-base-100"></div>
        <div
          :if={@count > 2}
          class="mx-4 h-1 rounded-b-lg border border-t-0 border-base-300 bg-base-100"
        >
        </div>
      </div>

      <div :if={@open} class="ms-4 mt-1 space-y-1 border-s border-base-300 ps-2">
        <.notification_row :for={notification <- @stack.notifications} notification={notification} />
      </div>
    </div>
    """
  end

  attr :notification, :map, required: true
  attr :boxed, :boolean, default: false

  defp notification_row(assigns) do
    assigns = assign(assigns, :path, notification_path(assigns.notification))

    ~H"""
    <div
      id={"notif-" <> to_string(@notification.id)}
      class={[
        "flex items-center gap-2 rounded-lg py-1.5 ps-2 pe-1",
        @boxed && "border border-base-300 bg-base-100",
        @path && clickable_row()
      ]}
    >
      <.entity_icon
        icon_url={@notification.icon_url}
        type={:notification}
        class="w-4 h-4 shrink-0 text-muted"
      />
      <%!-- Wraps: on a phone the sender and the date go under the title. --%>
      <div class="flex min-w-0 flex-1 flex-wrap items-center gap-x-3 gap-y-1 text-sm">
        <div class="min-w-48 flex-1">
          <%!-- `href`, not `navigate`: a notice leads anywhere
                (`/admin/reports` is another live_session), and
                `live_nav.js` makes a same-session link live. --%>
          <.row_link :if={@path} href={@path}>
            {translate_notification_title(@notification)}
          </.row_link>
          <span :if={!@path}>{translate_notification_title(@notification)}</span>
        </div>
        <.notification_sender notification={@notification} />
        <.timestamp
          at={@notification.inserted_at}
          format="relative"
          class="shrink-0 whitespace-nowrap text-muted"
        />
      </div>
      <div class={row_control()}>
        <.delete_button
          id={"notif-delete-" <> to_string(@notification.id)}
          label={gettext("Delete")}
          phx-click="delete"
          phx-value-id={@notification.id}
        />
      </div>
    </div>
    """
  end

  attr :notification, :map, required: true

  defp notification_sender(assigns) do
    ~H"""
    <%= cond do %>
      <% @notification.metadata["chat_type"] != nil -> %>
        <span class="badge badge-sm badge-outline badge-info">{gettext("Chat")}</span>
      <% Ecto.assoc_loaded?(@notification.sender) && @notification.sender -> %>
        <.player_card
          user={@notification.sender}
          name={LiveHelpers.public_user_name(@notification.sender)}
          size="sm"
        />
      <% true -> %>
        <.player_name name={LiveHelpers.public_user_name(@notification.sender_id)} />
    <% end %>
    """
  end

  attr :folded, :boolean, required: true

  defp fold_chevron(assigns) do
    ~H"""
    <.icon
      name="hero-chevron-down-solid"
      class={"size-4 shrink-0 text-muted transition-transform" <> if(@folded, do: " -rotate-90", else: "")}
    />
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :rest, :global

  defp delete_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      aria-label={@label}
      title={@label}
      class="btn btn-ghost btn-sm btn-square shrink-0 text-error"
      {@rest}
    >
      <.icon name="hero-trash-solid" class="size-4" />
    </button>
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
      |> assign(:notif_limit, @load_step)
      |> assign(:sections, [])
      |> assign(:collapsed_sections, MapSet.new())
      |> assign(:open_stacks, MapSet.new())
      |> assign(:notif_count, 0)
      |> assign(:notif_unread_count, 0)
      |> reload_notifications()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_section", %{"section" => key}, socket),
    do: {:noreply, update(socket, :collapsed_sections, &toggle(&1, key))}

  def handle_event("toggle_stack", %{"stack" => key}, socket),
    do: {:noreply, update(socket, :open_stacks, &toggle(&1, key))}

  def handle_event("load_more", _params, socket) do
    {:noreply, socket |> update(:notif_limit, &(&1 + @load_step)) |> reload_notifications()}
  end

  def handle_event("delete", %{"id" => id}, socket),
    do: {:noreply, delete_rows(socket, [id])}

  def handle_event("delete_stack", %{"stack" => key}, socket),
    do: {:noreply, delete_rows(socket, Sections.stack_ids(socket.assigns.sections, key))}

  def handle_event("delete_section", %{"section" => key}, socket),
    do: {:noreply, delete_rows(socket, Sections.section_ids(socket.assigns.sections, key))}

  def handle_event("delete_all", _params, socket) do
    user = Scope.user(socket.assigns.current_scope)

    all_ids =
      Notifications.list_notifications(user.id, page: 1, page_size: 10_000)
      |> Enum.map(& &1.id)

    Notifications.delete_notifications(user.id, all_ids)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Success."))
     |> assign(:notif_limit, @load_step)
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

  # Where the row leads, or nil when it leads nowhere.
  defp notification_path(n) do
    case path_for_type(n.metadata["type"], n) || path_for_metadata(n.metadata) do
      nil -> nil
      path -> if page_open?(path), do: path
    end
  end

  # A notification still arrives when the site has no page for it (the game
  # sends chat, friend, group and cup traffic regardless), so its row leads
  # nowhere.
  defp page_open?(path) do
    cond do
      under?(path, "/chat") ->
        MountedRoutes.mounted?(~p"/chat")

      under?(path, "/groups") ->
        MountedRoutes.mounted?(~p"/groups") and GamendWeb.Features.enabled?(:list_groups)

      under?(path, "/tournaments") ->
        MountedRoutes.mounted?(~p"/tournaments") and
          GamendWeb.Features.enabled?(:list_tournaments)

      path == ~p"/users/settings?#{[tab: "friends"]}" ->
        MountedRoutes.settings_tab?(SettingsTab.friends())

      under?(path, "/play") ->
        MountedRoutes.mounted?(~p"/play")

      true ->
        true
    end
  end

  defp under?(path, root),
    do: path == root or String.starts_with?(path, [root <> "/", root <> "?"])

  defp path_for_type(NotificationType.group_invite(), n) do
    case n.metadata["group_id"] do
      nil -> ~p"/groups"
      group_id -> ~p"/groups/#{group_id}"
    end
  end

  defp path_for_type(type, _n)
       when type in [
              NotificationType.party_invite(),
              NotificationType.chat_lobby(),
              NotificationType.chat_party()
            ],
       do: ~p"/play"

  defp path_for_type(NotificationType.friend_request(), _n),
    do: ~p"/users/settings?#{[tab: "friends"]}"

  defp path_for_type(NotificationType.quest_completed(), _n), do: ~p"/quests"

  defp path_for_type(NotificationType.chat_group(), n),
    do: chat_path(ChatType.group(), n.metadata["group_id"])

  defp path_for_type(NotificationType.chat_friend(), n),
    do: chat_path(ChatType.friend(), n.metadata["friend_id"] || n.metadata["sender_id"])

  defp path_for_type(NotificationType.friend_accepted(), n),
    do: chat_path(ChatType.friend(), n.metadata["friend_id"] || n.sender_id)

  defp path_for_type(_type, _n), do: nil

  defp chat_path(_type, nil), do: ~p"/chat"
  defp chat_path(type, id), do: ~p"/chat?#{[type: type, id: id]}"

  # Fallback: infer the path from metadata keys for notifications without a known type
  # A server notification (`Gamend.Notifications.notify/3`) says where it
  # leads. Only a path on this site: never another host.
  defp path_for_metadata(%{"url" => url}) when is_binary(url) do
    if String.starts_with?(url, "/") and not String.starts_with?(url, ["//", "/\\"]),
      do: url
  end

  defp path_for_metadata(%{"leaderboard_slug" => slug}) when is_binary(slug),
    do: ~p"/leaderboards/#{slug}"

  defp path_for_metadata(%{"leaderboard_id" => _}), do: ~p"/leaderboards"

  defp path_for_metadata(%{"group_id" => group_id}) when is_binary(group_id),
    do: ~p"/groups/#{group_id}"

  defp path_for_metadata(%{"lobby_id" => _}), do: ~p"/play"
  defp path_for_metadata(%{"party_id" => _}), do: ~p"/play"
  defp path_for_metadata(_), do: nil

  defp reload_notifications(socket) do
    user = Scope.user(socket.assigns.current_scope)

    newest_first =
      user.id
      |> Notifications.list_recent_notifications(socket.assigns.notif_limit)
      |> Enum.reverse()

    socket
    |> assign(:sections, Sections.build(newest_first))
    |> assign(:notif_count, Notifications.count_notifications(user.id))
    |> assign(:notif_unread_count, Notifications.count_unread_notifications(user.id))
  end

  defp delete_rows(socket, ids) do
    user = Scope.user(socket.assigns.current_scope)
    Notifications.delete_notifications(user.id, ids)

    socket
    |> put_flash(:info, gettext("Success."))
    |> reload_notifications()
  end

  defp toggle(set, key) do
    if MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key)
  end

  defp section_label(key) do
    if key == Sections.other(),
      do: dgettext("notifications", "Other"),
      else: NotificationEmail.group_label(key)
  end

  defp section_icon(PreferenceGroup.chat()), do: "hero-chat-bubble-left-right-solid"
  defp section_icon(PreferenceGroup.social()), do: "hero-user-group-solid"
  defp section_icon(PreferenceGroup.quests()), do: "hero-trophy-solid"
  defp section_icon(PreferenceGroup.reports()), do: "hero-flag-solid"
  defp section_icon(PreferenceGroup.payments()), do: "hero-credit-card-solid"
  defp section_icon(PreferenceGroup.account()), do: "hero-shield-check-solid"
  defp section_icon(_key), do: "hero-bell-solid"

  # A plugin's type that is gone leaves rows with no description: the newest
  # one's own title still says what they are.
  defp stack_title(%{description: nil, notifications: [newest | _]}),
    do: translate_notification_title(newest)

  # Core's descriptions are in the catalogue (`I18n.NotificationTypesCatalog`),
  # a plugin's through the host's own.
  defp stack_title(%{description: description}) do
    case Gettext.dgettext(GamendWeb.Gettext, "notifications", description) do
      ^description -> GamendWeb.HostLayouts.translate(description)
      translated -> translated
    end
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

    if n.metadata["kind"] == QuestCategory.achievement() do
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
