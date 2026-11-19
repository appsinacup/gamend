# `Gamend.Payments.Charges`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/charges.ex#L1)

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

# `drop_refund`

```elixir
@spec drop_refund(Gamend.Payments.Purchase.t()) :: :ok
```

A won dispute handed the money back: its refund row goes.

# `empty_totals`

```elixir
@spec empty_totals() :: map()
```

A totals map with nothing in it.

# `record_refund`

```elixir
@spec record_refund(Gamend.Payments.Purchase.t(), keyword()) :: :ok
```

Record the money a refund or lost dispute gave back. One per purchase:
revoking it twice records once. Options: `amount:` (the purchase's by
default), `currency:`, and `ref:` for a refund that does not end the
purchase (the unused part of a plan changed mid-period), keyed by the
provider's refund id.

# `record_renewal`

```elixir
@spec record_renewal(Gamend.Payments.Purchase.t(), String.t(), keyword()) :: :ok
```

Record a renewal of `purchase`'s subscription, keyed by the provider's id
for that one charge. Options: `amount:`, `currency:`, `occurred_at:`.

# `record_sale`

```elixir
@spec record_sale(Gamend.Payments.Purchase.t()) :: :ok
```

Record a purchase's sale. Runs inside its fulfilment's transaction.

# `revenue_summary`

```elixir
@spec revenue_summary(keyword()) :: map()
```

Revenue for the admin payments page, per currency (amounts never add across
currencies): `lifetime`, `this_month`, `last_month` and `last_30_days`
totals, the last 12 calendar months oldest first, and lifetime totals by
provider and by product. Each total is `%{sales, renewals, refunds, gross,
refunded, net}`: counts, then amounts in the smallest unit.

Options: `environment:` (`"production"` by default, `:all` for every one),
`now:`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
