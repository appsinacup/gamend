# `Gamend.Accounts.Presence`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/presence.ex#L1)

Whether a user is online, and when they were last seen.

Split out of `Gamend.Accounts`, which still exposes every function here under
the same name. The writes themselves are coalesced by
`Gamend.Accounts.PresenceWriter`.

# `set_user_offline`

```elixir
@spec set_user_offline(Ecto.UUID.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Mark a user as offline and update last_seen_at.

Writes only on a real online→offline transition (see `set_user_online/1`).

Returns {:ok, user} on success.

# `set_user_online`

```elixir
@spec set_user_online(Ecto.UUID.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Mark a user as online and update last_seen_at.

Writes only on a real offline→online transition: reconnects and extra
tabs/sockets while already online are no-ops, so reconnect storms don't
hammer the `users` table (and the `after_user_online` hook fires once per
session, not once per socket).

Returns {:ok, user} on success.

# `touch_last_seen`

```elixir
@spec touch_last_seen(Gamend.Accounts.User.t()) :: :ok
```

Updates `last_seen_at` to now for the given user. Fire-and-forget — errors are ignored.
Call on login (session or JWT) to track activity. Also records the UTC day
for `Gamend.Analytics` (DAU / retention).

# `touch_last_seen_by_id`

```elixir
@spec touch_last_seen_by_id(Ecto.UUID.t()) :: :ok
```

Lightweight version of `touch_last_seen/1` that accepts a user ID directly.
Performs a single UPDATE without loading the full struct first, setting
`last_seen_at` to now. Fire-and-forget — errors are ignored.

`is_online` is not touched: an offline to online move is `set_user_online/1`'s,
which tells the user's lobby, party and friends and runs `after_user_online`.
Written here, the flag came back with none of that, and a game's offline
mark (a voyage's "disconnected" card) stayed up on a player back online.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
