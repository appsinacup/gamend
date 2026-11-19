# `Gamend.Payments.Charge`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/charge.ex#L1)

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

# `t`

```elixir
@type t() :: %Gamend.Payments.Charge{
  __meta__: term(),
  amount: term(),
  currency: term(),
  environment: term(),
  id: term(),
  inserted_at: term(),
  kind: term(),
  occurred_at: term(),
  product: term(),
  product_id: term(),
  provider: term(),
  provider_ref: term(),
  purchase: term(),
  purchase_id: term(),
  updated_at: term()
}
```

# `changeset`

```elixir
@spec changeset(t(), map()) :: Ecto.Changeset.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
