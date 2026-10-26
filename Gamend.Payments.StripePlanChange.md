# `Gamend.Payments.StripePlanChange`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/stripe_plan_change.ex#L1)

Moving a running Stripe subscription to another product of the same period:
a hosted server's size, a tier of a monthly plan. Not a longer plan
(monthly to yearly), which is a new checkout (`Gamend.Payments.Upgrades`).

`change_stripe_subscription/4` moves the subscription's one item to the new
product's price (`Providers.Stripe.change_subscription_price/4`), prorated
and invoiced at once: a dearer product is charged its difference for the
rest of the period now, a cheaper one leaves a credit on the customer's
balance for the next invoices. When that invoice cannot be paid, Stripe
refuses and nothing changes. `end_trial: true` ends a trial now, so the new
product is charged in full from today: a host's free period may cover one
product and not another.

The purchase is then the new product's: its `product_id` and
`provider_product_id` move, and its entitlement row moves to the new
product's key (`Payments.entitlement_key/2`, with the purchase's subject),
keeping its period, so the row a renewal or a refund later finds by
`source_purchase_id` is the one the buyer now holds. A row already under
that key is a leftover of an older purchase and is deleted, unless it is
live through another purchase, which refuses the change
(`:already_owned`). Each change is listed on the purchase
(`metadata["plan_changes"]`, newest first) and counted (`payments.subscription.plan_changed`).

A price changed anywhere else (Stripe's dashboard, its customer portal)
reaches the purchase the same way, from `customer.subscription.updated`
(`follow/2`), so Stripe and the rows cannot disagree for longer than a
webhook, even when the write after a change here failed.

# `change_stripe_subscription`

```elixir
@spec change_stripe_subscription(
  Gamend.Accounts.User.t(),
  Ecto.UUID.t(),
  Gamend.Payments.ProviderProduct.t(),
  keyword()
) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     entitlement: Gamend.Payments.Entitlement.t(),
     stripe_subscription: map()
   }}
  | {:error, term()}
```

Move the user's subscription behind `entitlement_id` to `target`, an active
Stripe price of another subscription product with the same period, the
same currency and the same `per_subject`. Options: `end_trial: true`.

Refuses with core's `get_user_subscription_entitlement/2` errors,
`:not_for_sale` (an inactive or non-Stripe price), `:same_product`,
`:incompatible_product`, `:already_owned`, `:subscription_not_active`
(only `active` and `trialing` change) and `:several_items`; Stripe's
refusal, a card declined among them, as `{:stripe_error, error}`.

# `follow`

```elixir
@spec follow(Gamend.Payments.Purchase.t(), map()) ::
  {:ok, Gamend.Payments.Purchase.t()} | {:error, term()}
```

The purchase brought to the price `subscription` (a Stripe subscription
object) now bills: unchanged when it is the purchase's own, unknown here, or
of a product a plan change cannot move to. Called on every subscription
write (`StripeEvents.sync_stripe_subscription/3`), before its period is
copied.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
