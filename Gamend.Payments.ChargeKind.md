# `Gamend.Payments.ChargeKind`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/charge_kind.ex#L1)

What a `payment_charges` row records: the `sale` that started a purchase,
a subscription's `renewal`, or the `refund` (or lost dispute) that gave the
money back.

# `t`

```elixir
@type t() :: String.t()
```

# `all`

```elixir
@spec all() :: [t()]
```

Every value.

# `refund`
*macro* 

# `renewal`
*macro* 

# `sale`
*macro* 

---

*Consult [api-reference.md](api-reference.md) for complete listing*
