defmodule GamendWeb.NotificationSettings do
  @moduledoc """
  Which notification groups a user has a row for, and their settings as a
  client reads them: the rows of the settings page's Notifications tab
  (`GamendWeb.UserLive.Settings.NotificationsTab`) and of
  `/admin/notifications`, and the answer of
  `GET /api/v1/me/notification_settings`
  (`GamendWeb.Api.V1.NotificationSettingsController`).
  """

  use GamendWeb, :verified_routes

  alias Gamend.Accounts.Preferences, as: AccountPreferences
  alias Gamend.Accounts.TimeZone
  alias Gamend.Accounts.User
  alias Gamend.Notifications.Preferences
  alias Gamend.Notifications.PreferenceSwitch
  alias GamendWeb.MountedRoutes
  alias GamendWeb.NotificationEmail

  require GamendWeb.UserLive.Settings.SettingsTab, as: SettingsTab
  require Gamend.Notifications.PreferenceGroup, as: PreferenceGroup

  @doc """
  The groups `user` has a row for on the Notifications tab, and a client.
  A group whose every notification is about a feature the site does not
  have (`GamendWeb.MountedRoutes`, `GamendWeb.Features`) has nothing to
  choose: its row goes. The game still sends that traffic, and the stored
  choice is kept. An admins' group (`admin: true`) is on the admin's page.
  """
  @spec shown_groups(User.t()) :: [map()]
  def shown_groups(user),
    do: Enum.filter(Preferences.groups_for(user), &(not &1.admin and shown?(&1)))

  @doc "The admins' groups `user` gets (none for anyone else), for `/admin/notifications`."
  @spec admin_groups(User.t()) :: [map()]
  def admin_groups(user), do: Enum.filter(Preferences.groups_for(user), & &1.admin)

  defp shown?(%{key: PreferenceGroup.social()}),
    do:
      MountedRoutes.settings_tab?(SettingsTab.friends()) or
        MountedRoutes.settings_tab?(SettingsTab.groups())

  defp shown?(%{key: PreferenceGroup.chat()}), do: MountedRoutes.mounted?(~p"/chat")
  defp shown?(%{key: PreferenceGroup.quests()}), do: GamendWeb.Features.enabled?(:list_quests)
  defp shown?(_group), do: true

  @doc """
  `user`'s settings as the tab shows them, for a client
  (`GamendWeb.Schemas.NotificationSettings`): `channels`; `groups`, each
  `key`, `label` in the user's language, `enabled` per channel and the
  `configurable` channels; each switch (`off_all`, `off_email`,
  `off_push`); `timezone` (empty when unknown) and `timezone_manual`.
  """
  @spec view(User.t()) :: map()
  def view(%User{} = user) do
    groups =
      NotificationEmail.in_locale(AccountPreferences.locale(user), fn ->
        Enum.map(shown_groups(user), &group(user, &1))
      end)

    PreferenceSwitch.all()
    |> Map.new(&{&1, Preferences.off?(user, &1)})
    |> Map.merge(%{
      "channels" => Preferences.channels(),
      "groups" => groups,
      "timezone" => TimeZone.of(user) || "",
      "timezone_manual" => TimeZone.manual?(user)
    })
  end

  defp group(user, group) do
    %{
      "key" => group.key,
      "label" => NotificationEmail.group_label(group),
      "enabled" =>
        Map.new(Preferences.channels(), &{&1, Preferences.enabled?(user, group.key, &1)}),
      "configurable" => group.configurable
    }
  end
end
