# `Gamend.Payments.StripeEvents`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/stripe_events.ex#L1)

Stripe: starting a checkout, and keeping purchases and entitlements in step
with what Stripe says — webhooks as they arrive, reconciliation when one was
missed, and cancelling a subscription at the end of its period.

Split out of `Gamend.Payments`, which still exposes every function here under
the same name.

# `cancel_stripe_subscription_at_period_end`

```elixir
@spec cancel_stripe_subscription_at_period_end(
  Gamend.Accounts.User.t(),
  Ecto.UUID.t()
) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     entitlement: Gamend.Payments.Entitlement.t(),
     stripe_subscription: map()
   }}
  | {:error, term()}
```

# `create_stripe_billing_portal`

```elixir
@spec create_stripe_billing_portal(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, String.t()} | {:error, term()}
```

Open Stripe's customer portal for this account: cancel, change card, download
invoices. `{:error, :no_stripe_customer}` when the account never paid through
Stripe Checkout.

# `create_stripe_checkout`

```elixir
@spec create_stripe_checkout(Gamend.Accounts.User.t(), map()) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     checkout_url: String.t() | nil,
     provider_session_id: String.t() | nil
   }}
  | {:error, term()}
```

# `handle_stripe_webhook`

```elixir
@spec handle_stripe_webhook(binary(), binary() | nil) ::
  {:ok, atom()} | {:error, term()}
```

# `reconcile_stripe_purchase`

```elixir
@spec reconcile_stripe_purchase(Gamend.Payments.Purchase.t()) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     result: atom(),
     stripe_session: map()
   }}
  | {:error, term()}
```

# `stripe_customer_id`

```elixir
@spec stripe_customer_id(Gamend.Accounts.User.t()) :: String.t() | nil
```

The Stripe customer this account has paid as, or nil: the newest Stripe
purchase whose stored checkout session names one. Stripe creates the customer
at checkout (subscriptions always; one-off payments since
`customer_creation: "always"`), and `checkout.session.completed` stores the
session on the purchase.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
