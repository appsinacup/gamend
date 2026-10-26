# `Gamend.Payments.Providers.Stripe`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/providers/stripe.ex#L1)

Minimal Stripe Checkout and webhook adapter.

# `cancel_subscription_at_period_end`

# `cancel_subscription_now`

Cancels a subscription now, not at the period end. No proration credit and
no final invoice (`prorate`/`invoice_now` false, Stripe's defaults, sent so
a changed default cannot add a credit on top of a refund). Stripe then
sends `customer.subscription.deleted`.

# `change_subscription_price`

Moves a subscription's item `item_id` to the price `price_id`: a plan
change. Prorated and invoiced at once (`always_invoice`), so a dearer price
is charged its difference for the rest of the period now and a cheaper one
leaves a credit on the customer's balance for the next invoices.
`error_if_incomplete`: when that invoice cannot be paid, Stripe answers an
error and the subscription stays as it was.

`end_trial: true` ends a trial now (`trial_end: "now"`), so the new price
is charged in full from today. `idempotency_key:` makes a retry of the
same change answer the first one's result.

# `create_billing_portal_session`

A Stripe customer-portal session for `customer_id`: the Stripe-hosted page
where the buyer cancels, changes card and downloads invoices. Returns the
session; its `"url"` is single-use and short-lived, so open it right away.

# `create_checkout_session`

# `create_refund`

Refunds a payment: a PaymentIntent (`pi_`) or a charge (`ch_`, `py_`).
In full, or `:amount` of it (minor units; a plan given up for a longer
one, `Upgrades`). Other `opts`: `:idempotency_key`, so a repeat within
Stripe's 24 hours answers the same refund instead of trying a second, and
`:metadata`, which the refund's own webhooks carry.

# `expire_checkout_session`

Expires an open Checkout Session, so it can no longer be paid, and returns
it. Stripe answers an error when the session is not open any more: paid,
being paid, or expired already.

# `list_invoice_payments`

The invoice payments a PaymentIntent paid, each with its invoice expanded:
what a refund or dispute on a subscription's payment is traced back to its
subscription through (a charge does not name its invoice). Returns the list
object; `"data"` holds the payments.

# `resume_subscription`

Takes back a cancellation scheduled for the period end: the subscription
renews again. Stripe refuses it once the subscription has ended.

# `retrieve_checkout_session`

# `retrieve_subscription`

# `retrieve_subscription_with_latest_invoice`

A subscription with its latest invoice and that invoice's payments
expanded: what the subscription last charged, and when.

# `verify_webhook`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
