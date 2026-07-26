defmodule GameServer.Payments.Product do
  @moduledoc """
  Internal product sold by one or more payment providers.
  """

  use GameServer.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @kinds ~w(entitlement consumable subscription)

  schema "store_products" do
    field :sku, :string
    field :title, :string
    field :description, :string, default: ""
    field :kind, :string, default: "entitlement"
    field :active, :boolean, default: true
    field :grant_config, :map, default: %{}
    field :metadata, :map, default: %{}

    has_many :provider_products, GameServer.Payments.ProviderProduct
    has_many :purchases, GameServer.Payments.Purchase

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(sku title kind)a
  @optional_fields ~w(description active grant_config metadata)a

  def changeset(product, attrs) do
    product
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:sku, min: 1, max: 120)
    |> validate_length(:title, min: 1, max: 200)
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint(:sku)
  end

  def kinds, do: @kinds
end

# Hand-written rather than @derive so nil strings encode as "" (see
# GameServer.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: GameServer.Payments.Product do
  def encode(product, opts) do
    GameServer.SchemaJSON.encode(
      product,
      [
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
      ],
      opts
    )
  end
end
