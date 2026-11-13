# `Gamend.Accounts.GuestMerge`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/guest_merge.ex#L1)

A guest's progress joins the account they log in to.

A guest (`Gamend.Accounts.User.anonymous?/1`: no email, no provider) who
signs in to an account they already have used to lose everything they did:
the session moved to the account and the guest account was deleted. Before
it is deleted now, its progress is merged into the account
(`GamendWeb.UserAuth.log_in_user/3` calls `merge/2`).

One rule throughout: **the account's own data is never overwritten or
deleted.** The guest's is added where it fits, and what cannot be combined
stays with the guest account, which nobody can reach once the session has
moved, and goes with it.

First the guest's credentials are revoked (`Accounts.revoke_all_tokens/1`):
its access and refresh tokens and sessions stop working, so a game client
still signed in as the guest cannot spend what is being moved. Then, in
order, each step logged and skipped on failure so a sign-in never fails
because of a merge:

  1. The host (`merge_user_data/2` hook) merges what it understands: its own
     KV keys with its own rules (counts added, histories joined). A key it
     is done with it deletes from the guest, so step 2 leaves it alone.
  2. KV: every guest key the account lacks moves over (`Gamend.KV`, so caches
     and subscribers follow). A key both have stays the account's.
  3. Wallets: each balance is moved, taken off the guest
     (`Gamend.Economy.spend/4`) and added to the account's
     (`Gamend.Economy.grant/4`) in one transaction. A host that grants
     starting coins spends the guest's own grant first in step 1, so it is
     not counted twice.
  4. Inventory: quantities moved the same way (`Gamend.Inventory.consume_item/4`,
     `Gamend.Inventory.grant_item/4`).
  5. Purchases and the entitlements they made
     (`Gamend.Payments.move_purchases/2`): every purchase becomes the
     account's, so its subscription goes on renewing for the account and is
     not cancelled with the guest. A key both hold keeps the row that lasts
     longer. Then entitlements granted without a purchase, through
     `Gamend.Payments.grant_entitlement/3`, which never shortens what the
     account holds. One the account had revoked stays revoked.
  6. Leaderboards: `Gamend.Leaderboards.merge_user_records/2` (best kept,
     counters added, the account's never lowered).
  7. Quests: `Gamend.Quests.merge_user_progress/2` (periods the account has
     not played).
  8. Activity days the account lacks; the guest's analytics events,
     content reports and notifications become the account's.
  9. `users.metadata` and `users.preferences` keys the account lacks.

Sessions, push tokens, bans, lobby and party seats are not moved. Wallet
and inventory moves carry idempotency keys and every other step only moves
what the account lacks, so running it twice adds nothing twice.

# `merge`

```elixir
@spec merge(Gamend.Accounts.User.t(), Gamend.Accounts.User.t()) :: :ok
```

Merges `guest`'s progress into `user`, as the moduledoc describes. A no-op
unless `guest` is a guest and the two differ. Answers `:ok`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
