defmodule GamendWeb.UserLive.Settings.NotificationsTab do
  @moduledoc """
  Notifications tab of the user settings page: which notifications a user
  gets and where (`Gamend.Notifications.Preferences`), one row per group and
  one box per channel, plus the three switches (all email off, all phone off,
  everything off) and the time zone reminders use.

  A box the group does not let users change is shown, ticked or not, and
  disabled: "Account and security" email is how the account works.
  """

  use GamendWeb, :html
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Gamend.Accounts.TimeZone
  alias Gamend.Notifications.Preferences
  alias GamendWeb.NotificationEmail

  def assign_defaults(socket), do: assign(socket, :notify_groups, shown_groups())

  # A group whose every notification is about a feature the site has switched
  # off (`GamendWeb.Features`) has nothing to choose on the website: its row
  # goes. The game still sends that traffic, and the stored choice is kept.
  defp shown_groups, do: Enum.filter(Preferences.groups(), &shown?/1)

  defp shown?(%{key: "social"}),
    do: GamendWeb.Features.enabled?(:web_friends) or GamendWeb.Features.enabled?(:web_groups)

  defp shown?(%{key: "chat"}), do: GamendWeb.Features.enabled?(:web_chat)
  defp shown?(_group), do: true

  attr :settings_tab, :string, required: true
  attr :user, :map, required: true
  attr :notify_groups, :list, required: true

  def tab(assigns) do
    ~H"""
    <div :if={@settings_tab == "notifications"} id="notifications-settings">
      <div class="card bg-base-200 p-4 rounded-lg mt-6 space-y-4">
        <div>
          <div class="font-semibold text-lg">{gettext("Notifications")}</div>
          <div class="text-sm text-muted">
            {gettext("Choose what we tell you, and where.")}
          </div>
        </div>

        <%!-- A grid, not a table: on a phone each group's boxes wrap under
              its name instead of scrolling sideways. --%>
        <div class="divide-y divide-base-300 rounded-lg border border-base-300 bg-base-100">
          <div
            :for={group <- @notify_groups}
            id={"notify-group-#{group.key}"}
            class="flex flex-col gap-2 p-3 sm:flex-row sm:items-center sm:justify-between"
          >
            <span class="font-medium">{NotificationEmail.group_label(group)}</span>
            <div class="flex flex-wrap gap-x-5 gap-y-2">
              <label
                :for={channel <- Preferences.channels()}
                class={[
                  "flex items-center gap-2 text-sm",
                  channel not in group.configurable && "opacity-60"
                ]}
              >
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  id={"notify-#{group.key}-#{channel}"}
                  checked={Preferences.enabled?(@user, group.key, channel)}
                  disabled={channel not in group.configurable}
                  phx-click="notify_toggle"
                  phx-value-group={group.key}
                  phx-value-channel={channel}
                />
                {NotificationEmail.channel_label(channel)}
              </label>
            </div>
          </div>
        </div>

        <div class="flex flex-wrap gap-2">
          <.switch_button
            user={@user}
            switch="off_email"
            off={gettext("Turn off all email")}
            on={gettext("Turn email back on")}
          />
          <.switch_button
            user={@user}
            switch="off_push"
            off={gettext("Turn off all phone notifications")}
            on={gettext("Turn phone notifications back on")}
          />
          <.switch_button
            user={@user}
            switch="off_all"
            off={gettext("Turn off everything")}
            on={gettext("Turn notifications back on")}
          />
        </div>
        <p class="text-sm text-muted">
          {gettext("Account messages, such as sign-in links, are always sent.")}
        </p>

        <form id="notify-time-zone" phx-change="notify_time_zone" class="space-y-1">
          <label for="notify-time-zone-select" class="text-sm font-medium">
            {gettext("Time zone")}
          </label>
          <select
            id="notify-time-zone-select"
            name="zone"
            class="select select-bordered select-sm w-full max-w-xs"
          >
            <option value="" selected={not TimeZone.manual?(@user)}>
              {gettext("Automatic (this device): %{zone}", zone: TimeZone.of(@user) || "UTC")}
            </option>
            <option
              :for={zone <- TimeZone.names()}
              value={zone}
              selected={TimeZone.manual?(@user) and TimeZone.of(@user) == zone}
            >
              {zone}
            </option>
          </select>
          <p class="text-sm text-muted">
            {gettext("Your day and your reminders follow it.")}
          </p>
        </form>
      </div>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :switch, :string, required: true
  attr :off, :string, required: true
  attr :on, :string, required: true

  defp switch_button(assigns) do
    ~H"""
    <button
      type="button"
      id={"notify-#{@switch}"}
      phx-click="notify_switch"
      phx-value-switch={@switch}
      class={[
        "btn btn-sm",
        if(Preferences.off?(@user, @switch), do: "btn-primary", else: "btn-outline")
      ]}
    >
      {if Preferences.off?(@user, @switch), do: @on, else: @off}
    </button>
    """
  end

  def handle_event("notify_toggle", %{"group" => group, "channel" => channel}, socket) do
    user = socket.assigns.user
    on? = not Preferences.enabled?(user, group, channel)

    case Preferences.put(user, group, channel, on?) do
      {:ok, user} -> {:noreply, assign(socket, :user, user)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, gettext("Failed"))}
    end
  end

  def handle_event("notify_switch", %{"switch" => switch}, socket)
      when switch in ~w(off_email off_push off_all) do
    user = socket.assigns.user
    which = %{"off_email" => :email, "off_push" => :push, "off_all" => :all}[switch]

    result =
      if Preferences.off?(user, switch),
        do: Preferences.turn_on(user, which),
        else: Preferences.turn_off(user, which)

    case result do
      {:ok, user} -> {:noreply, assign(socket, :user, user)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, gettext("Failed"))}
    end
  end

  def handle_event("notify_time_zone", %{"zone" => zone}, socket) do
    case TimeZone.choose(socket.assigns.user, if(zone == "", do: nil, else: zone)) do
      {:ok, user} -> {:noreply, assign(socket, :user, user)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, gettext("Failed"))}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}
end
