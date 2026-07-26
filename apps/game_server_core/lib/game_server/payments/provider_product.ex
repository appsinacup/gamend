defmodule GameServer.Payments.ProviderProduct do
  @moduledoc """
  Maps an internal product to a provider-specific SKU or price id.
  """

  use GameServer.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @providers ~w(apple google steam stripe)

  schema "provider_products" do
    belongs_to :product, GameServer.Payments.Product
    field :provider, :string
    field :external_id, :string
    field :currency, :string
    field :unit_amount, :integer
    field :active, :boolean, default: true
    field :metadata, :map, default: %{}

    has_many :purchases, GameServer.Payments.Purchase

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(product_id provider external_id)a
  @optional_fields ~w(currency unit_amount active metadata)a

  def changeset(provider_product, attrs) do
    provider_product
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:provider, @providers)
    |> validate_length(:external_id, min: 1, max: 255)
    |> validate_length(:currency, is: 3)
    |> validate_number(:unit_amount, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:product_id)
    |> unique_constraint(:external_id, name: :provider_products_provider_external_id_index)
  end

  def providers, do: @providers
end

# Hand-written rather than @derive so nil strings encode as "" (see
# GameServer.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: GameServer.Payments.ProviderProduct do
  def encode(provider_product, opts) do
    GameServer.SchemaJSON.encode(
      provider_product,
      [
        :id,
        :product_id,
        :provider,
        :external_id,
        :currency,
        :unit_amount,
        :active,
        :metadata,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
