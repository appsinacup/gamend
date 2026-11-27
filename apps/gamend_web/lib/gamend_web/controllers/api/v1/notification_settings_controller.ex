defmodule GamendWeb.Api.V1.NotificationSettingsController do
  @moduledoc """
  `GET` and `PUT /api/v1/me/notification_settings`: the settings page's
  Notifications tab for a client (`GamendWeb.NotificationSettings.view/1`).
  A change is `Gamend.Notifications.Preferences.change/2`'s, written whole
  or refused: a zone sent here is the user's own pick, as the tab's select
  makes it; `""` goes back to the device's, whose next zone is kept.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.ControllerScope

  alias Gamend.Notifications.Preferences
  alias GamendWeb.NotificationSettings
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.NotificationSettingsResponse
  alias OpenApiSpex.Schema

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

  def show(conn, _params),
    do: with_user(conn, &reply_data(conn, NotificationSettings.view(&1)))

  def update(conn, params) do
    with_user(conn, fn user ->
      case Preferences.change(user, params) do
        {:ok, user} -> reply_data(conn, NotificationSettings.view(user))
        {:error, reason} -> reply_reason(conn, reason)
      end
    end)
  end
end
