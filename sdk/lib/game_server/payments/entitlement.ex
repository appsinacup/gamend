defmodule GameServer.Payments.Entitlement do
  @moduledoc """
  Entitlement struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  Handed to `after_entitlement_changed/1`.

  ## Fields

  - `id` - Entitlement ID (UUIDv7 string)
  - `user_id` - Holder (UUIDv7 string)
  - `product_id` - Product that granted it (UUIDv7 string)
  - `key` - The entitlement key the game checks (string)
  - `status` - `"active"` or `"revoked"` (string)
  - `starts_at` - When it became active
  - `expires_at` - When it lapses; nil for permanent entitlements
  - `revoked_at` - When it was revoked, if it was
  - `metadata` - Arbitrary entitlement metadata (map)
  """

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          product_id: String.t(),
          source_purchase_id: String.t() | nil,
          key: String.t(),
          status: String.t(),
          starts_at: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          revoked_at: DateTime.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :user_id,
    :product_id,
    :source_purchase_id,
    :key,
    :status,
    :starts_at,
    :expires_at,
    :revoked_at,
    :metadata,
    :inserted_at,
    :updated_at
  ]
end
