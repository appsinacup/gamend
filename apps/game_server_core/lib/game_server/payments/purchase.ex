defmodule GameServer.Payments.Purchase do
  @moduledoc """
  Provider transaction record.
  """

  use GameServer.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @providers ~w(apple google steam stripe)
  @statuses ~w(pending requires_action completed failed cancelled refunded revoked)
  @environments ~w(production sandbox test)

  schema "purchases" do
    belongs_to :user, GameServer.Accounts.User
    belongs_to :product, GameServer.Payments.Product
    belongs_to :provider_product, GameServer.Payments.ProviderProduct
    field :provider, :string
    field :order_id, :string
    field :provider_transaction_id, :string
    field :provider_original_transaction_id, :string
    field :status, :string, default: "pending"
    field :quantity, :integer, default: 1
    field :currency, :string
    field :amount, :integer
    field :environment, :string, default: "production"
    field :raw_provider_payload, :map, default: %{}
    field :metadata, :map, default: %{}
    field :purchased_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    has_many :entitlements, GameServer.Payments.Entitlement, foreign_key: :source_purchase_id

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(user_id product_id provider order_id status quantity environment)a
  @optional_fields ~w(provider_product_id provider_transaction_id provider_original_transaction_id currency amount raw_provider_payload metadata purchased_at expires_at revoked_at)a

  def changeset(purchase, attrs) do
    purchase
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:environment, @environments)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> validate_length(:currency, is: 3)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:provider_product_id)
    |> unique_constraint(:order_id)
    |> unique_constraint(:provider_transaction_id, name: :purchases_unique_provider_transaction)
  end

  def statuses, do: @statuses
  def providers, do: @providers
end

# Hand-written rather than @derive so nil strings encode as "" (see
# GameServer.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: GameServer.Payments.Purchase do
  def encode(purchase, opts) do
    GameServer.SchemaJSON.encode(
      purchase,
      [
        :id,
        :user_id,
        :product_id,
        :provider_product_id,
        :provider,
        :order_id,
        :provider_transaction_id,
        :provider_original_transaction_id,
        :status,
        :quantity,
        :currency,
        :amount,
        :environment,
        :raw_provider_payload,
        :metadata,
        :purchased_at,
        :expires_at,
        :revoked_at,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
