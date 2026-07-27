defmodule GameServer.Payments.Purchase do
  @moduledoc """
  Purchase struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  Handed to `after_purchase_fulfilled/1` and `after_purchase_revoked/1`.

  ## Fields

  - `id` - Purchase ID (UUIDv7 string)
  - `user_id` - Buyer (UUIDv7 string)
  - `product_id` - The product bought (UUIDv7 string)
  - `provider` - `"stripe"`, `"google"`, `"apple"` or `"steam"` (string)
  - `status` - Lifecycle status, e.g. `"fulfilled"` (string)
  - `quantity` - Units bought (integer)
  - `currency` - Real-money currency code (string)
  - `amount` - Real-money amount in minor units (integer)
  - `environment` - `"production"` or `"sandbox"` (string)
  - `metadata` - Arbitrary purchase metadata (map)
  - `purchased_at` - When the provider recorded the purchase
  """

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          product_id: String.t(),
          provider: String.t(),
          order_id: String.t() | nil,
          provider_transaction_id: String.t() | nil,
          status: String.t(),
          quantity: integer(),
          currency: String.t() | nil,
          amount: integer() | nil,
          environment: String.t(),
          metadata: map(),
          purchased_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :user_id,
    :product_id,
    :provider,
    :order_id,
    :provider_transaction_id,
    :status,
    :quantity,
    :currency,
    :amount,
    :environment,
    :metadata,
    :purchased_at,
    :inserted_at,
    :updated_at
  ]
end
