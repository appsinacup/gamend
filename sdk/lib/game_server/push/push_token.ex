defmodule GameServer.Push.PushToken do
  @moduledoc """
  Registered device push token struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  ## Fields

  - `id` - Token row ID (UUID string)
  - `user_id` - Owner (UUID string)
  - `token` - The FCM registration token or APNs device token
  - `platform` - `"android" | "ios" | "web"`
  - `provider` - `"fcm" | "apns"` — selects the delivery backend per token
  - `device_id` - Optional stable device key (re-registration rotates in place)
  - `disabled_at` - Set when the provider reported the token dead (DateTime or nil)
  - `last_used_at` - Last successful delivery (DateTime or nil)
  - `metadata` - Optional client info (map)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          token: String.t(),
          platform: String.t(),
          provider: String.t(),
          device_id: String.t() | nil,
          disabled_at: DateTime.t() | nil,
          last_used_at: DateTime.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :user_id,
    :token,
    :platform,
    :provider,
    :device_id,
    :disabled_at,
    :last_used_at,
    :metadata,
    :inserted_at,
    :updated_at
  ]
end
