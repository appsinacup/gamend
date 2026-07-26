defmodule GameServer.Quests.Reward do
  @moduledoc """
  One reward entry on a quest definition: `amount` of a currency
  (via `GameServer.Economy.grant/4`) or an item
  (via `GameServer.Inventory.grant_item/4`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @types ~w(currency item)

  @derive {Jason.Encoder, only: [:type, :code, :amount]}

  @primary_key false
  embedded_schema do
    field :type, :string
    field :code, :string
    field :amount, :integer, default: 1
  end

  @doc false
  def changeset(reward, attrs) do
    reward
    |> cast(attrs, [:type, :code, :amount])
    |> validate_required([:type, :code])
    |> validate_inclusion(:type, @types)
    |> validate_length(:code, min: 1, max: 64)
    |> validate_number(:amount, greater_than: 0)
  end
end
