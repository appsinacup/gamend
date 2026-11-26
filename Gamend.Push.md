# `Gamend.Push`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/push.ex#L1)

Push context – device push-token registry and (see `send_to_user/3`)
server-authoritative delivery of push notifications.

Devices register their FCM registration token or APNs device token against
the authenticated user; a user has many devices. Delivery routes **per
token** off the `provider` column (`"fcm"` | `"apns"`), falling back to the
zero-config `Log` provider when nothing is configured
(see the moduledoc below).

## Usage

    # Register a device (typically via POST /me/push_tokens)
    {:ok, token} = Push.register_token(user_id, %{
      "token" => "fcm-registration-token",
      "platform" => "android",
      "device_id" => "stable-device-key"
    })

    # List a user's devices
    tokens = Push.list_tokens(user_id, page: 1, page_size: 25)

    # Remove one (DELETE /me/push_tokens/:id)
    {:ok, _} = Push.delete_token(user_id, token.id)

# `user_id`

```elixir
@type user_id() :: Ecto.UUID.t()
```

# `admin_delete_token`

```elixir
@spec admin_delete_token(Ecto.UUID.t()) ::
  {:ok, Gamend.Push.PushToken.t()} | {:error, :not_found}
```

Remove any token row by id (admin). Returns `{:ok, %PushToken{}}` or
`{:error, :not_found}`.

# `count_all_tokens`

```elixir
@spec count_all_tokens(map()) :: non_neg_integer()
```

Count for `list_all_tokens/2` (same filters).

# `count_tokens`

```elixir
@spec count_tokens(user_id()) :: non_neg_integer()
```

Count a user's registered tokens (including disabled).

# `delete_token`

```elixir
@spec delete_token(user_id(), Ecto.UUID.t()) ::
  {:ok, Gamend.Push.PushToken.t()} | {:error, :not_found}
```

Remove a token row by id, scoped to `user_id` (the `DELETE /me/push_tokens/:id`
path). Returns `{:ok, %PushToken{}}` or `{:error, :not_found}`.

# `disable_token`

```elixir
@spec disable_token(String.t()) :: :ok
```

Soft-disable a token the provider reported dead. The row is kept —
re-registration re-enables it — so a token bouncing between valid and
invalid never loses its device association.

# `force_log?`

```elixir
@spec force_log?() :: boolean()
```

Whether every delivery is forced to the Log provider (`PUSH_ADAPTER=log`).

# `list_all_tokens`

```elixir
@spec list_all_tokens(map(), keyword()) :: [Gamend.Push.PushToken.t()]
```

Admin listing across all users. Supported `filters` keys (atom or string):
`:user_id`, `:platform`, `:provider`, and `:status` (`"live"` | `"disabled"`).

Supports pagination via `:page` and `:page_size` options; preloads `:user`
so the admin UI can show names, not UUIDs.

# `list_tokens`

```elixir
@spec list_tokens(user_id(), keyword()) :: [Gamend.Push.PushToken.t()]
```

List a user's registered tokens, newest first. Includes disabled rows (they
are the user's devices; clients can show them greyed out).

Supports pagination via `:page` and `:page_size` options.

# `live_tokens`

```elixir
@spec live_tokens(user_id()) :: [Gamend.Push.PushToken.t()]
```

The user's live (non-disabled) tokens — the delivery fan-out set. Unpaginated
by design: bounded by `max_push_tokens_per_user`.

# `mark_token_used`

```elixir
@spec mark_token_used(String.t()) :: :ok
```

Bump `last_used_at` after a successful delivery.

# `provider_for`

```elixir
@spec provider_for(Gamend.Push.PushToken.t()) :: module()
```

Resolve the delivery provider for a token: its `provider` column's module
when that module's `configured?/0` says it can deliver, else the zero-config
`Log` provider. `PUSH_ADAPTER=log` short-circuits everything to `Log`.

# `register_token`

```elixir
@spec register_token(user_id(), map()) ::
  {:ok, Gamend.Push.PushToken.t()}
  | {:error, :too_many_tokens | Ecto.Changeset.t()}
```

Register (or refresh) a device push token for `user_id`.

Upsert semantics, serialized under the `:push_tokens` advisory lock:

- a row with the same `token` already exists → it is claimed for this
  user/device (a device that logged into another account must not keep
  receiving the old account's pushes) and re-enabled;
- else a row with the same `(user_id, device_id)` exists → its token is
  rotated in place and the row re-enabled;
- else a new row is inserted, subject to `max_push_tokens_per_user`
  (counting live tokens only).

`provider` defaults from the platform when omitted: `"ios"` → `"apns"`,
anything else → `"fcm"`.

Returns `{:ok, %PushToken{}}`, `{:error, :too_many_tokens}`, or
`{:error, changeset}`.

# `send_to_user`

```elixir
@spec send_to_user(user_id(), map(), keyword()) :: :ok | {:error, map()}
```

Queue a push message to all of `user_id`'s live devices.

Server-authoritative: exposed to plugins through the SDK and to admins —
never as a public client endpoint. Best-effort by design: no live devices
means no jobs, and delivery failures never propagate back to the caller.

Returns `:ok` or `{:error, errors}` when the message fails validation
(see `Gamend.Push.Message`).

`opts` say what the push is, for the admin's record of it (`Gamend.Sent`):
`:kind` (`Gamend.Sent.SentKind`, default `other`), `:group` (the
notification group) and `:batch` (the announcement it is part of).

# `send_to_users`

```elixir
@spec send_to_users([user_id()], map(), keyword()) :: :ok | {:error, map() | term()}
```

Queue a push message to every live device of `user_ids`.

Small audiences enqueue delivery jobs inline; past 100
recipients the expansion itself becomes a `FanoutWorker` job (chunked,
restart-safe, deduped against identical double-broadcasts).

# `token_stats`

```elixir
@spec token_stats() :: map()
```

Aggregate token counts for the admin stat card and runtime introspection:
`%{total: n, live: n, disabled: n, by_platform: %{...}, by_provider: %{...}}`
(platform/provider maps count live tokens only).

# `unregister_token`

```elixir
@spec unregister_token(user_id(), String.t()) ::
  {:ok, Gamend.Push.PushToken.t()} | {:error, :not_found}
```

Remove a token row by its raw `token` value, scoped to `user_id`.

Returns `{:ok, %PushToken{}}` or `{:error, :not_found}`.

# `user_has_live_tokens?`

```elixir
@spec user_has_live_tokens?(user_id()) :: boolean()
```

Whether the user has any live device. Cached (60s TTL + version bump on
register/remove/disable): `Notifications` asks this on every insert, and the
common no-device answer must not cost a query.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
