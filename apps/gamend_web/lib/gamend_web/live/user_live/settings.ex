defmodule GamendWeb.UserLive.Settings do
  @moduledoc """
  User settings page: a thin coordinator that renders the tab navigation and
  routes events to the per-tab modules under
  `GamendWeb.UserLive.Settings.*` (account, friends, groups, payments,
  data). Each tab module owns its template, events, and helpers.
  """

  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Friends
  alias Gamend.Groups
  alias GamendWeb.UserLive.Settings.AccountTab
  alias GamendWeb.UserLive.Settings.ApiTokensTab
  alias GamendWeb.UserLive.Settings.DataTab
  alias GamendWeb.UserLive.Settings.DevicesTab
  alias GamendWeb.UserLive.Settings.FriendsTab
  alias GamendWeb.UserLive.Settings.GroupsTab
  alias GamendWeb.UserLive.Settings.ItemsTab
  alias GamendWeb.UserLive.Settings.NotificationsTab
  alias GamendWeb.UserLive.Settings.PaymentsTab
  alias GamendWeb.UserLive.Settings.Shared
  alias GamendWeb.UserLive.Settings.WalletTab

  @valid_tabs ~w(account notifications friends groups wallet items payments data devices
                 api_tokens)

  # Tabs a feature flag can close. A closed tab is not drawn, not opened from
  # `?tab=` and refuses its events, so it reads as absent rather than broken.
  @feature_tabs %{"groups" => :web_groups}

  @account_events ~w(validate_email update_email validate_display_name update_display_name
                     validate_username update_username validate_avatar save_avatar cancel_avatar
                     validate_password update_password unlink_provider delete_user
                     delete_conflicting_account)
  @friends_events ~w(search_users send_friend block_friend accept_friend reject_friend
                     cancel_friend remove_friend unblock_friend search_prev search_next
                     incoming_prev incoming_next outgoing_prev outgoing_next friends_prev
                     friends_next blocked_prev blocked_next)
  @notifications_events ~w(notify_toggle notify_switch notify_time_zone)
  @payments_events ~w(cancel_stripe_subscription open_stripe_portal refund_stripe_purchase resume_stripe_subscription)
  @wallet_events ~w(wallet_ledger_prev wallet_ledger_next)
  @items_events ~w(items_prev items_next)
  @data_events ~w(kv_prev kv_next kv_filters_change kv_filters_apply kv_filters_clear)
  @devices_events ~w(devices_prev devices_next device_remove)
  @api_tokens_events ~w(api_token_create api_token_dismiss api_token_revoke api_tokens_prev
                        api_tokens_next)
  @groups_events ~w(groups_tab groups_toggle_create group_validate_create group_create
                    group_leave group_join group_request_join group_accept_invite
                    group_decline_invite group_cancel_request group_cancel_invite
                    group_approve_request group_reject_request browse_groups_filter
                    browse_groups_clear browse_groups_prev browse_groups_next
                    group_view_detail group_close_detail group_toggle_edit
                    group_validate_edit group_save_edit group_kick group_promote
                    group_demote group_members_prev group_members_next group_invite_search
                    group_invite_user)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="flex items-center gap-3">
        <.back_link href={home_path()} />
        <h1 class="text-4xl font-black text-base-content">{gettext("Account")}</h1>
      </div>

      <div class="text-center">
        <%= if @conflict_user do %>
          <div class="divider" />

          <div class="card bg-warning/10 border-warning p-4 rounded-lg">
            <div class="flex items-start justify-between">
              <div>
                <strong>{gettext("This sign-in is already linked to another account")}</strong>
                <div class="text-sm text-muted">
                  {@conflict_provider} ({@conflict_user.id})
                </div>
              </div>
              <div class="flex items-center gap-2">
                <button
                  phx-click="delete_conflicting_account"
                  class="btn btn-error btn-sm"
                  data-confirm={
                    gettext("Delete the other account permanently? This cannot be undone.")
                  }
                >
                  {gettext("Delete other account")}
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Settings tabs --%>
      <div class="mt-6 flex gap-1 border-b border-base-300 pb-0 overflow-x-auto">
        <button
          :for={
            {tab, label} <-
              Enum.filter(
                [
                  {"account", gettext("Account")},
                  {"notifications", gettext("Notifications")},
                  {"friends", gettext("Friends")},
                  {"groups", gettext("Groups")},
                  {"wallet", gettext("Wallet")},
                  {"items", gettext("Items")},
                  {"payments", gettext("Payments")},
                  {"data", gettext("Data")},
                  {"devices", gettext("Devices")},
                  {"api_tokens", gettext("API tokens")}
                ],
                fn {tab, _label} -> tab_enabled?(tab) end
              )
          }
          phx-click="settings_tab"
          phx-value-tab={tab}
          class={[
            "px-4 py-2.5 text-sm font-medium rounded-t-lg transition-colors whitespace-nowrap",
            if(@settings_tab == tab,
              do: "bg-primary text-primary-content shadow-sm",
              else: "text-muted hover:text-base-content hover:bg-base-200/50"
            )
          ]}
        >
          {label}
        </button>
      </div>

      <AccountTab.tab {tab_assigns(assigns)} />
      <NotificationsTab.tab
        settings_tab={@settings_tab}
        user={@user}
        notify_groups={@notify_groups}
      />
      <FriendsTab.tab {tab_assigns(assigns)} />
      <PaymentsTab.tab {tab_assigns(assigns)} />
      <WalletTab.tab {tab_assigns(assigns)} />
      <ItemsTab.tab {tab_assigns(assigns)} />
      <DataTab.tab {tab_assigns(assigns)} />
      <DevicesTab.tab {tab_assigns(assigns)} />
      <ApiTokensTab.tab {tab_assigns(assigns)} />
      <GroupsTab.tab :if={tab_enabled?("groups")} {tab_assigns(assigns)} />
    </Layouts.app>
    """
  end

  # The tab templates were split out of this LiveView verbatim; they are
  # plain function components receiving the full assigns.
  defp tab_assigns(assigns), do: Map.delete(assigns, :__changed__)

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(Scope.user(socket.assigns.current_scope), token) do
        {:ok, _user} ->
          put_flash(socket, :info, gettext("Success."))

        {:error, _} ->
          put_flash(socket, :error, gettext("Failed"))
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, session, socket) do
    user = Scope.user(socket.assigns.current_scope)
    {conflict_user, conflict_provider} = AccountTab.resolve_link_conflict(session, user)

    socket =
      socket
      |> assign(:page_title, gettext("Account"))
      |> assign(:settings_tab, "account")
      |> assign(:user, user)
      |> assign(:conflict_user, conflict_user)
      |> assign(:conflict_provider, conflict_provider)
      # Empty defaults only: a tab's data is read when it is opened
      # (`load_tab/2`, from `handle_params/3`). Reading all ten on every
      # mount was ~30 queries a render for the one tab on screen.
      |> AccountTab.assign_defaults(user)
      |> NotificationsTab.assign_defaults()
      |> FriendsTab.assign_defaults()
      |> DataTab.assign_defaults()
      |> DevicesTab.assign_defaults()
      |> ApiTokensTab.assign_defaults()
      |> WalletTab.assign_defaults()
      |> ItemsTab.assign_defaults()
      |> GroupsTab.assign_defaults()

    if connected?(socket) do
      Friends.subscribe_user(user.id)
      Groups.subscribe_groups()
      Phoenix.PubSub.subscribe(Gamend.PubSub, "user:#{user.id}")
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("settings_tab", %{"tab" => tab}, socket) when tab in @valid_tabs do
    if tab_enabled?(tab),
      do: {:noreply, push_patch(socket, to: ~p"/users/settings?tab=#{tab}")},
      else: {:noreply, socket}
  end

  def handle_event(event, params, socket) when event in @account_events,
    do: AccountTab.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @notifications_events,
    do: NotificationsTab.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @friends_events,
    do: FriendsTab.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @payments_events,
    do: PaymentsTab.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @wallet_events,
    do: WalletTab.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @items_events,
    do: ItemsTab.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @data_events,
    do: DataTab.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @devices_events,
    do: DevicesTab.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @api_tokens_events,
    do: ApiTokensTab.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @groups_events do
    if tab_enabled?("groups"),
      do: GroupsTab.handle_event(event, params, socket),
      else: {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # PubSub handlers
  @impl true
  def handle_info({event, _f}, socket)
      when event in [
             :incoming_request,
             :outgoing_request,
             :friend_accepted,
             :friend_rejected,
             :friend_blocked,
             :request_cancelled,
             :friend_removed,
             :friend_unblocked
           ] do
    {:noreply, reload_if_open(socket, "friends")}
  end

  # Online status change broadcast from UserChannel (via PubSub on "user:<id>")
  def handle_info(%Phoenix.Socket.Broadcast{event: event}, socket)
      when event in ["friend_online", "friend_offline"] do
    {:noreply, reload_if_open(socket, "friends")}
  end

  # Ignore other broadcasts on the user topic (e.g. "updated" events from channel)
  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, socket}

  # Groups PubSub — refresh groups when something changes
  def handle_info({event, _payload}, socket)
      when event in [
             :group_created,
             :group_updated,
             :group_deleted,
             :group_invite_accepted,
             :group_invite_cancelled,
             :group_join_request_approved,
             :group_join_request_rejected,
             :party_invite_accepted,
             :party_invite_declined,
             :party_invite_cancelled,
             :member_joined,
             :member_left,
             :member_kicked,
             :member_promoted,
             :member_demoted,
             :join_request_approved,
             :join_request_rejected
           ] do
    {:noreply, reload_if_open(socket, "groups")}
  end

  # Catch-all: ignore unhandled PubSub messages (e.g. :chat_message_created,
  # :notification_created) so the LiveView doesn't crash.
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_params(params, _url, socket) do
    # The link conflict comes from the session, resolved once in `mount/3` — never
    # from the query string. See `AccountTab.resolve_link_conflict/2`.
    conflict_user = socket.assigns[:conflict_user]
    conflict_provider = socket.assigns[:conflict_provider]

    tab =
      if Map.get(params, "tab") in @valid_tabs and tab_enabled?(params["tab"]),
        do: params["tab"],
        else: socket.assigns[:settings_tab] || "account"

    {:noreply,
     socket
     |> assign(
       conflict_user: conflict_user,
       conflict_provider: conflict_provider,
       settings_tab: tab
     )
     |> apply_group_params(params)
     |> load_tab(tab)}
  end

  defp apply_group_params(socket, params) do
    if tab_enabled?("groups"), do: GroupsTab.apply_params(socket, params), else: socket
  end

  defp tab_enabled?(tab) do
    case Map.fetch(@feature_tabs, tab) do
      {:ok, feature} -> GamendWeb.Features.enabled?(feature)
      :error -> true
    end
  end

  # The open tab's data, read when it opens (and again on a patch within it):
  # every tab's template is behind `:if={@settings_tab == ...}`, so nothing
  # else is drawn. Streams are re-sent here too, since an insert is consumed
  # on the next render even while its container is hidden.
  defp load_tab(socket, "friends"),
    do: FriendsTab.refresh_friend_lists(socket, Shared.current_user(socket))

  defp load_tab(socket, "data"), do: DataTab.reload_kv_entries(socket)
  defp load_tab(socket, "wallet"), do: WalletTab.load_wallet(socket)
  defp load_tab(socket, "items"), do: ItemsTab.reload_items(socket)
  defp load_tab(socket, "groups"), do: GroupsTab.reload_groups(socket)
  defp load_tab(socket, "payments"), do: PaymentsTab.assign_payment_data(socket)
  defp load_tab(socket, "devices"), do: DevicesTab.reload_devices(socket)
  defp load_tab(socket, "api_tokens"), do: ApiTokensTab.reload_api_tokens(socket)
  defp load_tab(socket, _tab), do: socket

  # A friend or group event reloads its tab only while it is open; opening it
  # reads it fresh anyway. Every friend's online/offline was eight queries.
  defp reload_if_open(socket, tab) do
    if socket.assigns.settings_tab == tab, do: load_tab(socket, tab), else: socket
  end
end
