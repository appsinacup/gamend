defmodule GameServer.Payments.Product do
  @moduledoc """
  Product struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  ## Fields

  - `id` - Product ID (UUIDv7 string)
  - `sku` - Stable identifier the game and providers agree on (string)
  - `title` - Display title (string)
  - `description` - Display description (string)
  - `kind` - `"entitlement"`, `"consumable"` or `"subscription"` (string)
  - `active` - Whether the product is offered in the store (boolean)
  - `grant_config` - Free-form payout description; the game reads it in
    `after_purchase_fulfilled/1` (map)
  - `metadata` - Arbitrary product metadata (map)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          sku: String.t(),
          title: String.t(),
          description: String.t(),
          kind: String.t(),
          active: boolean(),
          grant_config: map(),
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :sku,
    :title,
    :description,
    :kind,
    :active,
    :grant_config,
    :metadata,
    :inserted_at,
    :updated_at
  ]
end
