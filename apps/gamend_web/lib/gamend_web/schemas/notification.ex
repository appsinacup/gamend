defmodule GamendWeb.Schemas.Notification do
  @moduledoc "A notification as `GamendWeb.Serializers.serialize_notification/1` sends it."
  require OpenApiSpex
  alias GamendWeb.Schemas.FreeForm
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Notification",
    description: "A notification",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      sender_id: %Schema{type: :string, description: "Empty for a system notification"},
      sender_name: %Schema{type: :string},
      recipient_id: %Schema{type: :string, format: :uuid},
      title: %Schema{type: :string},
      content: %Schema{type: :string},
      icon_url: %Schema{type: :string, description: "Empty when unset"},
      group: %Schema{
        type: :string,
        description: "The notification group it belongs to (`social`, `chat`, …). Empty for none"
      },
      metadata: FreeForm.metadata(),
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :sender_id,
      :sender_name,
      :recipient_id,
      :title,
      :content,
      :icon_url,
      :group,
      :metadata,
      :inserted_at
    ]
  })
end

defmodule GamendWeb.Schemas.NotificationPage do
  @moduledoc "A page of notifications."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.Notification
end

defmodule GamendWeb.Schemas.DeletedCount do
  @moduledoc "How many rows a bulk delete removed."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "DeletedCount",
    description: "Rows deleted",
    type: :object,
    properties: %{deleted: %Schema{type: :integer}},
    required: [:deleted]
  })
end

defmodule GamendWeb.Schemas.DeletedCountResponse do
  @moduledoc "The deleted count under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.DeletedCount
end

defmodule GamendWeb.Schemas.NotificationResponse do
  @moduledoc "One notification under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Notification
end

defmodule GamendWeb.Schemas.Announcement do
  @moduledoc "An announcement on its way to every player."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Announcement",
    description: "An announcement queued for every player",
    type: :object,
    properties: %{
      recipients: %Schema{
        type: :integer,
        description: "Accounts it is going to (banned ones are skipped as it reaches them)"
      }
    },
    required: [:recipients]
  })
end

defmodule GamendWeb.Schemas.AnnouncementResponse do
  @moduledoc "A queued announcement under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Announcement
end
