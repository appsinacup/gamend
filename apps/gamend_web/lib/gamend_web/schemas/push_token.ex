defmodule GamendWeb.Schemas.PushToken do
  @moduledoc "A registered device, as the push token endpoints send it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PushToken",
    description: "A device registered for push",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      token: %Schema{type: :string, description: "The provider's device token"},
      platform: %Schema{type: :string},
      provider: %Schema{type: :string, description: "fcm or apns; empty picks by platform"},
      device_id: %Schema{type: :string, description: "Empty when unset"},
      disabled_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Set when the provider reported the token dead"
      },
      last_used_at: %Schema{type: :string, format: :"date-time", nullable: true},
      metadata: GamendWeb.Schemas.FreeForm.metadata(),
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :token,
      :platform,
      :provider,
      :device_id,
      :disabled_at,
      :last_used_at,
      :metadata,
      :inserted_at
    ]
  })
end

defmodule GamendWeb.Schemas.PushTokenPage do
  @moduledoc "A page of the user's devices."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.PushToken
end

defmodule GamendWeb.Schemas.PushTokenResponse do
  @moduledoc "One registered device under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.PushToken
end
