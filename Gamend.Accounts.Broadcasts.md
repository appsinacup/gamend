# `Gamend.Accounts.Broadcasts`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/broadcasts.ex#L1)

Telling connected clients a user changed: the `user:<id>` topic, and the
member and friend topics that show that user to others.

Split out of `Gamend.Accounts`, which still exposes every function here under
the same name.

Each runs after commit when called inside a transaction (`Gamend.AfterCommit`),
lookups included, so the fan-out sees and announces only committed state.

# `broadcast_friend_update`

```elixir
@spec broadcast_friend_update(Gamend.Accounts.User.t()) :: :ok
```

Broadcast a `friend_updated` event to all accepted friends.

Used when public user data changes: map presence, display name, avatar,
player metadata, ship metadata, lobby/party state, etc.

# `broadcast_member_update`

```elixir
@spec broadcast_member_update(Gamend.Accounts.User.t()) :: :ok
```

Broadcast a `member_updated` event to the user's current lobby and
party channels so other members see the profile change (display name, avatar,
metadata, etc.) in real-time.

This is fire-and-forget and safe to call even when the user is not in a lobby
or party.

# `broadcast_user_update`

```elixir
@spec broadcast_user_update(Gamend.Accounts.User.t()) :: :ok
```

Broadcast that the given user has been updated.

This helper is intentionally small and only broadcasts a compact payload
intended for client consumption through the `user:<id>` topic.

# `serialize_user_payload`

```elixir
@spec serialize_user_payload(Gamend.Accounts.User.t()) :: map()
```

Serialize a user into the compact payload used by realtime updates.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
