defmodule GamendWeb.Schemas.NotificationGroupSetting do
  @moduledoc "One group's row of the notification settings, as the settings tab shows it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "NotificationGroupSetting",
    description: "Which channels a notification group reaches the user through",
    type: :object,
    properties: %{
      key: %Schema{type: :string, description: "The group (`social`, `chat`, a host's)"},
      label: %Schema{type: :string, description: "Its name, in the user's language"},
      enabled: %Schema{
        type: :object,
        additionalProperties: %Schema{type: :boolean},
        description: "Each channel (`in_app`, `email`, `push`): whether it is sent there"
      },
      configurable: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "The channels the user may change; the others keep their default"
      }
    },
    required: [:key, :label, :enabled, :configurable]
  })
end

defmodule GamendWeb.Schemas.NotificationSettings do
  @moduledoc """
  The user's notification choices (`Gamend.Notifications.Preferences`) and
  the time zone reminders follow (`Gamend.Accounts.TimeZone`): the settings
  page's Notifications tab.
  """
  require OpenApiSpex
  alias GamendWeb.Schemas.NotificationGroupSetting
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "NotificationSettings",
    description: "Which notifications the user gets, and where",
    type: :object,
    properties: %{
      channels: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "The channels, in the order the settings page shows them"
      },
      groups: %Schema{type: :array, items: NotificationGroupSetting},
      off_all: %Schema{type: :boolean, description: "Everything off"},
      off_email: %Schema{type: :boolean, description: "All email off"},
      off_push: %Schema{type: :boolean, description: "All phone notifications off"},
      timezone: %Schema{
        type: :string,
        description: "The user's IANA time zone, empty when unknown (UTC then)"
      },
      timezone_manual: %Schema{
        type: :boolean,
        description: "Chosen by hand: a device's zone does not replace it"
      }
    },
    required: [
      :channels,
      :groups,
      :off_all,
      :off_email,
      :off_push,
      :timezone,
      :timezone_manual
    ]
  })
end

defmodule GamendWeb.Schemas.NotificationSettingsResponse do
  @moduledoc "The notification settings under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.NotificationSettings
end
