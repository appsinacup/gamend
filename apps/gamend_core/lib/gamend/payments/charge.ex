defmodule Gamend.Payments.Charge do
  @moduledoc """
  One time money moved for a purchase (`payment_charges`): its sale, each
  renewal a provider charged, or its refund. Revenue is read from here, not
  from `purchases`, because a Stripe subscription is one purchase row however
  many periods it was paid for. Rows are written by `Gamend.Payments.Charges`
  and unique per provider, kind and `provider_ref` (a charge or transaction
  id), so a webhook delivered twice records once.

  `amount` is what the buyer paid, in the currency's smallest unit: tax
  included where it was charged, before the store's commission or Stripe's
  fees. It is `nil` only when neither the provider nor the SKU named a price;
  such a row counts as a sale but adds nothing to a total.
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Payments.ChargeKind

  @type t :: %__MODULE__{}

  schema "payment_charges" do
    belongs_to :purchase, Gamend.Payments.Purchase
    belongs_to :product, Gamend.Payments.Product
    field :provider, :string
    field :provider_ref, :string
    field :kind, :string
    field :amount, :integer
    field :currency, :string
    field :environment, :string
    field :occurred_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required ~w(provider provider_ref kind environment occurred_at)a
  @optional ~w(amount currency)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(charge, attrs) do
    charge
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:kind, ChargeKind.all())
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> validate_length(:currency, is: 3)
    |> validate_length(:provider_ref, max: 255)
    |> unique_constraint([:provider, :kind, :provider_ref])
  end
end
