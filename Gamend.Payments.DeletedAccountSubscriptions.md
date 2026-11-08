# `Gamend.Payments.DeletedAccountSubscriptions`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/deleted_account_subscriptions.ex#L1)

A deleted account stops being charged.

Its entitlements go with its row and its purchases lose their owner, so
nothing would ever tell Stripe, which goes on renewing.
`Gamend.Accounts.delete_user/1` reads the account's subscriptions first
(`of_user/1`), while its purchases still say whose they are, and queues a job
for each once the row is gone (`cancel/1`), so an account whose delete failed
keeps them.

A job rather than a call in the delete: an admin's click or a retention sweep
should not wait on Stripe, and an outage must not lose a cancellation nothing
else would revisit. Every Stripe purchase the account made with a
subscription gets one, and the job asks Stripe what is still live, so a
renewal that is past due counts and one already over is left alone. Cancelled
now, with no refund (`Gamend.Payments.Providers.Stripe.cancel_subscription_now/2`).

# `cancel`

```elixir
@spec cancel([String.t()]) :: :ok
```

Queue the end of each subscription.

# `of_user`

```elixir
@spec of_user(Ecto.UUID.t()) :: [String.t()]
```

The Stripe subscriptions `user_id`'s purchases started, whatever became of them.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
