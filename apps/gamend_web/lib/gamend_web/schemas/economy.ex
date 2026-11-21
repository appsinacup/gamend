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

defmodule GamendWeb.Schemas.Inventory do
  @moduledoc "Every item the caller holds, by code."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Inventory",
    description: "Item code to quantity",
    type: :object,
    additionalProperties: %Schema{type: :integer},
    example: %{"sword" => 1, "potion" => 5}
  })
end

defmodule GamendWeb.Schemas.LedgerEntry do
  @moduledoc "One wallet change, as `Gamend.Economy` records it."
  require OpenApiSpex
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
      metadata: GamendWeb.Schemas.FreeForm.metadata(),
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :currency, :delta, :balance_after, :reason, :metadata, :inserted_at]
  })
end

defmodule GamendWeb.Schemas.WalletBalancesResponse do
  @moduledoc "The caller's balances under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.WalletBalances
end

defmodule GamendWeb.Schemas.InventoryResponse do
  @moduledoc "The caller's inventory under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Inventory
end

defmodule GamendWeb.Schemas.LedgerEntryPage do
  @moduledoc "A page of ledger entries."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.LedgerEntry
end
