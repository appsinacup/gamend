defmodule GamendWeb.Api.V1.NotificationSettingsController do
  @moduledoc """
  `GET` and `PUT /api/v1/me/notification_settings`: the settings page's
  Notifications tab for a client (`GamendWeb.UserLive.Settings.NotificationsTab`).
  The groups it has rows for and each one's channels
  (`Gamend.Notifications.Preferences`), the three switches, and the time
  zone reminders follow (`Gamend.Accounts.TimeZone`): a zone sent here is
  the user's own pick, as the tab's select makes it; `""` goes back to the
  device's.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Preferences, as: AccountPreferences
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.TimeZone
  alias Gamend.Accounts.User
  alias Gamend.Notifications.Preferences
  alias GamendWeb.NotificationEmail
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.NotificationSettingsResponse
  alias GamendWeb.UserLive.Settings.NotificationsTab
  alias OpenApiSpex.Schema

  require Gamend.Notifications.PreferenceSwitch, as: PreferenceSwitch

  tags(["Notifications"])

  operation(:show,
    operation_id: "get_notification_settings",
    summary: "Get own notification settings",
    description:
      "Which notifications the authenticated user gets and where, as the settings page's " <>
        "Notifications tab shows them: a row per group with each channel on or off and the " <>
        "channels the user may change, the switches that win over every group, and the time " <>
        "zone reminders follow.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Notification settings", "application/json", NotificationSettingsResponse},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:update,
    operation_id: "update_notification_settings",
    summary: "Change own notification settings",
    description:
      ~s(Changes what is sent and leaves what is left out as it is: `groups` sets channels of ) <>
        ~s(groups (`{"social": {"push": false}}`\), `off_all`, `off_email` and `off_push` ) <>
        ~s(turn a switch on or off, `timezone` picks the zone reminders follow (`""` goes ) <>
        "back to the device's). Refused whole, with nothing changed: 404 unknown_group, " <>
        "403 not_configurable (a channel the group keeps at its default), 422 " <>
        "invalid_time_zone. Answers the settings as they are now.",
    security: [%{"authorization" => []}],
    request_body: {
      "The choices to change",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          groups: %Schema{
            type: :object,
            additionalProperties: %Schema{
              type: :object,
              additionalProperties: %Schema{type: :boolean}
            },
            description: "Group key to channel to on or off"
          },
          off_all: %Schema{type: :boolean},
          off_email: %Schema{type: :boolean},
          off_push: %Schema{type: :boolean},
          timezone: %Schema{
            type: :string,
            description: "An IANA time zone (`Europe/Bucharest`), or `\"\"` for the device's"
          }
        }
      }
    },
    responses: [
      ok: {"Notification settings", "application/json", NotificationSettingsResponse},
      forbidden: Schemas.error("A channel the group does not let users change"),
      not_found: Schemas.error("A group the user has no row for"),
      unprocessable_entity: Schemas.error("An unknown time zone"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def show(conn, _params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user -> reply_data(conn, settings(user))
      _ -> reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def update(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user -> change(conn, user, params)
      _ -> reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  defp change(conn, user, params) do
    with {:ok, zone} <- zone(params),
         {:ok, user} <- Preferences.change(user, params),
         {:ok, user} <- choose_zone(user, zone) do
      reply_data(conn, settings(user))
    else
      {:error, reason} -> reply_reason(conn, reason)
    end
  end

  # `:keep` when the zone is left out, nil for the device's.
  defp zone(%{"timezone" => ""}), do: {:ok, nil}

  defp zone(%{"timezone" => zone}) when is_binary(zone) do
    if TimeZone.valid?(zone), do: {:ok, zone}, else: {:error, :invalid_time_zone}
  end

  defp zone(_params), do: {:ok, :keep}

  defp choose_zone(user, :keep), do: {:ok, user}
  defp choose_zone(user, zone), do: TimeZone.choose(user, zone)

  # The tab's rows in the user's language, as the page draws them.
  defp settings(user) do
    groups = fn -> Enum.map(NotificationsTab.shown_groups(user), &group(user, &1)) end

    %{
      channels: Preferences.channels(),
      groups:
        case AccountPreferences.locale(user) do
          nil -> groups.()
          locale -> Gettext.with_locale(locale, groups)
        end,
      off_all: Preferences.off?(user, PreferenceSwitch.off_all()),
      off_email: Preferences.off?(user, PreferenceSwitch.off_email()),
      off_push: Preferences.off?(user, PreferenceSwitch.off_push()),
      timezone: TimeZone.of(user) || "",
      timezone_manual: TimeZone.manual?(user)
    }
  end

  defp group(user, group) do
    %{
      key: group.key,
      label: NotificationEmail.group_label(group),
      enabled: Map.new(Preferences.channels(), &{&1, Preferences.enabled?(user, group.key, &1)}),
      configurable: group.configurable
    }
  end
end
