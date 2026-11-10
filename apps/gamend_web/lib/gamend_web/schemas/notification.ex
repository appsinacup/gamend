defmodule GamendWeb.Schemas.Notification do
  @moduledoc "A notification as `GamendWeb.Serializers.serialize_notification/1` sends it."
  require OpenApiSpex
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
      metadata: %Schema{type: :object},
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
