defmodule GameServer.Inventory.LedgerEntry do
  @moduledoc """
  Append-only record of a single item-stack change (grant, consume, admin
  adjustment) — the inventory counterpart of `GameServer.Economy.LedgerEntry`.
  Carries the `idempotency_key` that makes item grants safe to retry.
  """

  use GameServer.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "inventory_ledger" do
    belongs_to :user, GameServer.Accounts.User
    field :item, :string
    # +grant / -consume; quantity_after is the stack size right after this row.
    field :delta, :integer
    field :quantity_after, :integer
    field :reason, :string, default: "unspecified"
    field :idempotency_key, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :user_id,
      :item,
      :delta,
      :quantity_after,
      :reason,
      :idempotency_key,
      :metadata
    ])
    |> validate_required([:user_id, :item, :delta, :quantity_after])
    |> validate_length(:item, min: 1, max: 64)
    |> validate_length(:reason, max: 64)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:idempotency_key, name: :inventory_ledger_idempotency_key_index)
  end
end

# Hand-written rather than @derive so nil strings encode as "" (see
# GameServer.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: GameServer.Inventory.LedgerEntry do
  def encode(entry, opts) do
    GameServer.SchemaJSON.encode(
      entry,
      [
        :id,
        :user_id,
        :item,
        :delta,
        :quantity_after,
        :reason,
        :metadata,
        :inserted_at
      ],
      opts
    )
  end
end
