# `Gamend.Accounts.Profile`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/profile.ex#L1)

Changing what a user shows the world: display name, username, avatar, age and
metadata, and the storage that goes with them.

Split out of `Gamend.Accounts`, which still exposes every function here under
the same name.

# `change_user_display_name`

```elixir
@spec change_user_display_name(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
```

Returns an `%Ecto.Changeset{}` for changing the user display_name.

# `change_username`

```elixir
@spec change_username(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
```

# `delete_user_storage`

```elixir
@spec delete_user_storage(Ecto.UUID.t()) :: :ok
```

Removes every stored object belonging to `user_id`.

Best-effort, like `prune_user_avatars/2`: a storage backend that is down must
not block an account deletion that has already happened at the database level.

# `merge_metadata`

```elixir
@spec merge_metadata(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Merges `patch` into the user's metadata, leaving untouched every key it does
not mention.

The counterpart to `Gamend.Lobbies.merge_metadata/2`, and for the same
reason: `metadata` is one shared map, so a writer that replaces it wipes keys
belonging to code it has never heard of. Top-level merge, serialized so two
concurrent merges cannot lose each other.

# `prune_user_avatars`

```elixir
@spec prune_user_avatars(Ecto.UUID.t(), String.t()) :: :ok
```

Delete a user's stored avatar objects except `keep_key`.

Each new avatar gets a fresh random key (`avatars/<user_id>/<rand><ext>`), so
without this the previous upload or mirror copy lingers in storage forever.
Best-effort: a failed cleanup leaves the old object rather than failing the
update that already succeeded.

# `refresh_account_class`

```elixir
@spec refresh_account_class(Gamend.Accounts.User.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Re-derive `account_class` for a user whose stored answer has not changed.

An account graduates on the first of its birth month, and nothing writes to it
on that day — the derivation is a function of the calendar, not of an event.
Call this to bring the denormalised column back in step, from a scheduled
sweep or on login.

# `set_user_age`

```elixir
@spec set_user_age(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Record a user's age answer and re-derive what it permits.

Three things happen together, and they have to: the answer is stored, the
denormalised `account_class` is recomputed from it, and `grandfathered_at` is
cleared. That last one is the point — an account that predated the age gate
stops being treated as an adult-by-default the moment it tells us what it
actually is, in whichever direction that goes.

Refuses with `{:error, :age_change_not_allowed}` when the answer would raise
the user's age without a stronger signal than the one already recorded. See
`AgePolicy.may_change_age?/4`: lowering is always allowed, because it only
ever increases protection.

`attrs` must carry `birth_year`, `birth_month` and `age_method`, and should
carry `age_country` — without it the highest digital-consent age in the table
applies, which is the safe reading but not always the right one.

# `update_user_avatar`

```elixir
@spec update_user_avatar(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Set the user's avatar URL (`profile_url`), typically after an upload confirmed
by `Gamend.Storage`. Same cache/broadcast/hook path as other profile edits.

# `update_user_display_name`

```elixir
@spec update_user_display_name(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Updates the user's display name and broadcasts the change.

# `update_username`

```elixir
@spec update_username(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Updates the user's unique username handle and broadcasts the change.

Strict, unlike registration: an invalid or taken username returns
`{:error, changeset}` with no generated fallback, so the player can pick
again. Routed through the `before_user_update` hook pipeline, where games
can forbid changes entirely or reject names (profanity, reserved words).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
