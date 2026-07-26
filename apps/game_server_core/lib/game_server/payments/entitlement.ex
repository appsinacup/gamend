defmodule GameServer.Payments.Entitlement do
  @moduledoc """
  User access grant derived from a purchase or admin/server action.
  """

  use GameServer.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(active expired revoked)

  schema "entitlements" do
    belongs_to :user, GameServer.Accounts.User
    belongs_to :product, GameServer.Payments.Product
    belongs_to :source_purchase, GameServer.Payments.Purchase
    field :key, :string
    field :status, :string, default: "active"
    field :starts_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(user_id key status)a
  @optional_fields ~w(product_id source_purchase_id starts_at expires_at revoked_at metadata)a

  def changeset(entitlement, attrs) do
    entitlement
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:key, min: 1, max: 160)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:source_purchase_id)
    |> unique_constraint(:key, name: :entitlements_user_id_key_index)
  end
end

# Hand-written rather than @derive so nil strings encode as "" (see
# GameServer.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: GameServer.Payments.Entitlement do
  def encode(entitlement, opts) do
    GameServer.SchemaJSON.encode(
      entitlement,
      [
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
      ],
      opts
    )
  end
end
