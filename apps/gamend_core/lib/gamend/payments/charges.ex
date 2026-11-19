defmodule Gamend.Payments.Charges do
  @moduledoc """
  The money a purchase moved (`Gamend.Payments.Charge`), written where it
  moves and read back as revenue for the admin payments page.

  Written at three points, each idempotent on `(provider, kind, provider_ref)`:

    * the sale, when `Payments.fulfill_purchase/2` first completes a purchase,
      keyed by its provider transaction (or order) id;
    * a renewal, for each later charge of a subscription: Stripe's
      `charge.succeeded` (keyed by the charge id) and Apple's renewal
      notifications (by the new transaction id, at its `price`). Google renewals the client
      validates are purchases of their own, so they arrive as sales;
    * a refund, when a refund or lost dispute ends the purchase
      (`Payments.revoke_purchase/2`), removed again by a dispute the seller
      won (`Payments.restore_purchase/2`), and the unused part of a Stripe
      plan refunded when a player changes plan (`Gamend.Payments.Upgrades`).
      Any other partial refund ends nothing and is not recorded.
  """

  import Ecto.Query, warn: false

  alias Gamend.Payments.Charge
  alias Gamend.Payments.Purchase
  alias Gamend.Repo

  require Gamend.Payments.ChargeKind, as: ChargeKind
  require Gamend.Payments.PaymentEnvironment, as: PaymentEnvironment

  # -- writes --------------------------------------------------------------------

  @doc "Record a purchase's sale. Runs inside its fulfilment's transaction."
  @spec record_sale(Purchase.t()) :: :ok
  def record_sale(%Purchase{} = purchase) do
    record(purchase, ChargeKind.sale(), purchase.provider_transaction_id || purchase.order_id,
      amount: purchase.amount,
      currency: purchase.currency,
      occurred_at: purchase.purchased_at
    )
  end

  @doc """
  Record a renewal of `purchase`'s subscription, keyed by the provider's id
  for that one charge. Options: `amount:`, `currency:`, `occurred_at:`.
  """
  @spec record_renewal(Purchase.t(), String.t(), keyword()) :: :ok
  def record_renewal(%Purchase{} = purchase, ref, opts) when is_binary(ref) do
    record(purchase, ChargeKind.renewal(), ref, opts)
  end

  @doc """
  Record the money a refund or lost dispute gave back. One per purchase:
  revoking it twice records once. Options: `amount:` (the purchase's by
  default), `currency:`, and `ref:` for a refund that does not end the
  purchase (the unused part of a plan changed mid-period), keyed by the
  provider's refund id.
  """
  @spec record_refund(Purchase.t(), keyword()) :: :ok
  def record_refund(%Purchase{} = purchase, opts \\ []) do
    record(purchase, ChargeKind.refund(), Keyword.get(opts, :ref) || purchase.id,
      amount: Keyword.get(opts, :amount) || purchase.amount,
      currency: Keyword.get(opts, :currency) || purchase.currency
    )
  end

  @doc "A won dispute handed the money back: its refund row goes."
  @spec drop_refund(Purchase.t()) :: :ok
  def drop_refund(%Purchase{} = purchase) do
    from(c in Charge,
      where:
        c.purchase_id == ^purchase.id and c.kind == ^ChargeKind.refund() and
          c.provider_ref == ^purchase.id
    )
    |> Repo.delete_all()

    :ok
  end

  defp record(%Purchase{} = purchase, kind, ref, opts) do
    attrs = %{
      provider: purchase.provider,
      provider_ref: ref,
      kind: kind,
      amount: Keyword.get(opts, :amount),
      currency: Keyword.get(opts, :currency) || purchase.currency,
      environment: purchase.environment,
      occurred_at: Keyword.get(opts, :occurred_at) || DateTime.utc_now(:second)
    }

    # The unique index decides: a second delivery of one webhook, or the
    # client and the provider confirming one sale, inserts nothing.
    {:ok, _charge} =
      %Charge{purchase_id: purchase.id, product_id: purchase.product_id}
      |> Charge.changeset(attrs)
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:provider, :kind, :provider_ref]
      )

    :ok
  end

  # -- reads ---------------------------------------------------------------------

  @doc """
  Revenue for the admin payments page, per currency (amounts never add across
  currencies): `lifetime`, `this_month`, `last_month` and `last_30_days`
  totals, the last 12 calendar months oldest first, and lifetime totals by
  provider and by product. Each total is `%{sales, renewals, refunds, gross,
  refunded, net}`: counts, then amounts in the smallest unit.

  Options: `environment:` (`"production"` by default, `:all` for every one),
  `now:`.
  """
  @spec revenue_summary(keyword()) :: map()
  def revenue_summary(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))
    base = base_query(Keyword.get(opts, :environment, PaymentEnvironment.production()))
    this_month = month_start(now)
    last_month = shift_month(this_month, -1)

    months =
      for offset <- -11..0 do
        first = shift_month(this_month, offset)
        %{month: DateTime.to_date(first), totals: totals(base, first, shift_month(first, 1))}
      end

    %{
      currencies: currencies(base),
      lifetime: totals(base, nil, nil),
      this_month: totals(base, this_month, nil),
      last_month: totals(base, last_month, this_month),
      last_30_days: totals(base, DateTime.add(now, -30, :day), nil),
      months: months,
      by_provider: grouped(base, :provider),
      by_product: grouped(base, :product)
    }
  end

  defp base_query(:all), do: from(c in Charge)
  defp base_query(environment), do: from(c in Charge, where: c.environment == ^environment)

  defp currencies(base) do
    from(c in base, distinct: true, select: c.currency, order_by: c.currency)
    |> Repo.all()
  end

  # %{currency => totals}
  defp totals(base, from_at, to_at) do
    base
    |> between(from_at, to_at)
    |> group_by([c], [c.currency, c.kind])
    |> select([c], {c.currency, c.kind, count(c.id), sum(c.amount)})
    |> Repo.all()
    |> fold(fn {currency, _kind, _count, _sum} -> currency end)
  end

  defp grouped(base, :provider) do
    base
    |> group_by([c], [c.provider, c.currency, c.kind])
    |> select([c], {c.provider, c.currency, c.kind, count(c.id), sum(c.amount)})
    |> Repo.all()
    |> fold_groups()
  end

  defp grouped(base, :product) do
    from(c in base,
      left_join: p in assoc(c, :product),
      group_by: [c.product_id, p.title, p.sku, c.currency, c.kind],
      select:
        {{c.product_id, coalesce(p.title, p.sku)}, c.currency, c.kind, count(c.id), sum(c.amount)}
    )
    |> Repo.all()
    |> fold_groups()
  end

  # [%{key, currency, totals}], highest net first.
  defp fold_groups(rows) do
    rows
    |> Enum.group_by(fn {key, currency, _kind, _count, _sum} -> {key, currency} end)
    |> Enum.map(fn {{key, currency}, group} ->
      rows =
        Enum.map(group, fn {_key, currency, kind, count, sum} -> {currency, kind, count, sum} end)

      %{key: key, currency: currency, totals: Map.get(fold(rows, &elem(&1, 0)), currency)}
    end)
    |> Enum.sort_by(&{-&1.totals.net, -&1.totals.sales})
  end

  defp fold(rows, currency_of) do
    rows
    |> Enum.group_by(currency_of)
    |> Map.new(fn {currency, group} ->
      {currency, Enum.reduce(group, empty_totals(), &add_row/2)}
    end)
  end

  @doc "A totals map with nothing in it."
  @spec empty_totals() :: map()
  def empty_totals, do: %{sales: 0, renewals: 0, refunds: 0, gross: 0, refunded: 0, net: 0}

  defp add_row({_currency, kind, count, sum}, acc) do
    amount = to_int(sum)

    case kind do
      ChargeKind.sale() ->
        %{acc | sales: acc.sales + count, gross: acc.gross + amount}

      ChargeKind.renewal() ->
        %{acc | renewals: acc.renewals + count, gross: acc.gross + amount}

      ChargeKind.refund() ->
        %{acc | refunds: acc.refunds + count, refunded: acc.refunded + amount}
    end
    |> then(&%{&1 | net: &1.gross - &1.refunded})
  end

  defp between(query, nil, nil), do: query
  defp between(query, from_at, nil), do: where(query, [c], c.occurred_at >= ^from_at)

  defp between(query, from_at, to_at),
    do: where(query, [c], c.occurred_at >= ^from_at and c.occurred_at < ^to_at)

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_float(value), do: trunc(value)

  defp month_start(%DateTime{} = now) do
    {:ok, at} = DateTime.new(Date.beginning_of_month(DateTime.to_date(now)), ~T[00:00:00])
    at
  end

  defp shift_month(%DateTime{} = first, months) do
    {:ok, at} = DateTime.new(Date.shift(DateTime.to_date(first), month: months), ~T[00:00:00])
    at
  end
end
