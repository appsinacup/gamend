defmodule Gamend.Repo.Migrations.CreatePaymentCharges do
  @moduledoc """
  `payment_charges`: one row per time money moved (`Gamend.Payments.Charge`),
  so revenue counts every renewal of a subscription and not only the purchase
  that started it. Filled from the purchases already sold: a `sale` for each
  one that was paid (`purchased_at` set), a `refund` for each a refund or a
  lost dispute ended. Renewals Stripe charged before this table existed were
  written over the one purchase row and cannot be recovered.
  """

  # Typed so ids and times dump as the adapter stores them; defined before
  # `use Ecto.Migration`, whose `timestamps/1` would clash with the schema's.
  defmodule ChargeRow do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, Ecto.UUID, autogenerate: false}
    @foreign_key_type Ecto.UUID

    schema "payment_charges" do
      field(:purchase_id, Ecto.UUID)
      field(:product_id, Ecto.UUID)
      field(:provider, :string)
      field(:provider_ref, :string)
      field(:kind, :string)
      field(:amount, :integer)
      field(:currency, :string)
      field(:environment, :string)
      field(:occurred_at, :utc_datetime)
      timestamps(type: :utc_datetime)
    end
  end

  defmodule PurchaseRow do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, Ecto.UUID, autogenerate: false}
    @foreign_key_type Ecto.UUID

    schema "purchases" do
      field(:product_id, Ecto.UUID)
      field(:provider, :string)
      field(:order_id, :string)
      field(:provider_transaction_id, :string)
      field(:status, :string)
      field(:amount, :integer)
      field(:currency, :string)
      field(:environment, :string)
      field(:purchased_at, :utc_datetime)
      field(:revoked_at, :utc_datetime)
    end
  end

  use Ecto.Migration

  import Ecto.Query

  def up do
    create table(:payment_charges) do
      add :purchase_id, references(:purchases, on_delete: :nilify_all)
      add :product_id, references(:store_products, on_delete: :nilify_all)
      add :provider, :string, null: false
      add :provider_ref, :string, null: false
      add :kind, :string, null: false
      add :amount, :integer
      add :currency, :string
      add :environment, :string, null: false
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:payment_charges, [:provider, :kind, :provider_ref])
    create index(:payment_charges, [:occurred_at])
    create index(:payment_charges, [:purchase_id])
    create index(:payment_charges, [:product_id])

    flush()

    now = DateTime.utc_now(:second)

    from(p in PurchaseRow, where: not is_nil(p.purchased_at))
    |> repo().all()
    |> Enum.flat_map(&rows(&1, now))
    |> Enum.chunk_every(500)
    |> Enum.each(&repo().insert_all(ChargeRow, &1, on_conflict: :nothing))
  end

  def down do
    drop table(:payment_charges)
  end

  defp rows(purchase, now) do
    sale =
      row(purchase, now, "sale", purchase.provider_transaction_id || purchase.order_id,
        at: purchase.purchased_at
      )

    if purchase.status in ["refunded", "revoked"] and purchase.revoked_at do
      [sale, row(purchase, now, "refund", purchase.id, at: purchase.revoked_at)]
    else
      [sale]
    end
  end

  defp row(purchase, now, kind, ref, at: at) do
    %{
      id: Gamend.UUIDv7.generate(),
      purchase_id: purchase.id,
      product_id: purchase.product_id,
      provider: purchase.provider,
      provider_ref: ref,
      kind: kind,
      amount: purchase.amount,
      currency: purchase.currency,
      environment: purchase.environment,
      occurred_at: at,
      inserted_at: now,
      updated_at: now
    }
  end
end
