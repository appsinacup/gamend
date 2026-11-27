defmodule GamendWeb.Schemas.WalletBalances do
  @moduledoc "Every currency the caller holds, by code."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "WalletBalances",
    description: "Currency code to balance",
    type: :object,
    additionalProperties: %Schema{type: :integer},
    example: %{"gold" => 250, "gems" => 3}
  })
end

defmodule GamendWeb.Schemas.InventoryItem do
  @moduledoc "One stack of the caller's, as `Gamend.Inventory` keeps it."
  require OpenApiSpex
  alias GamendWeb.Schemas.FreeForm
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "InventoryItem",
    description: "An item stack",
    type: :object,
    properties: %{
      item: %Schema{type: :string, description: "The item's code"},
      quantity: %Schema{type: :integer},
      metadata: FreeForm.metadata(description: "The stack's own properties"),
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:item, :quantity, :metadata, :updated_at]
  })
end

defmodule GamendWeb.Schemas.LedgerEntry do
  @moduledoc "One wallet change, as `Gamend.Economy` records it."
  require OpenApiSpex
  alias GamendWeb.Schemas.FreeForm
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "LedgerEntry",
    description: "A wallet change",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      currency: %Schema{type: :string},
      delta: %Schema{type: :integer, description: "Positive for a grant, negative for a spend"},
      balance_after: %Schema{type: :integer, description: "The balance right after this change"},
      reason: %Schema{type: :string, description: "Why, as the granting code named it"},
      metadata: FreeForm.metadata(),
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :currency, :delta, :balance_after, :reason, :metadata, :inserted_at]
  })
end

defmodule GamendWeb.Schemas.WalletBalancesResponse do
  @moduledoc "The caller's balances under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.WalletBalances
end

defmodule GamendWeb.Schemas.InventoryItemPage do
  @moduledoc "A page of the caller's item stacks."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.InventoryItem
end

defmodule GamendWeb.Schemas.LedgerEntryPage do
  @moduledoc "A page of ledger entries."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.LedgerEntry
end
