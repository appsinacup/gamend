# `Gamend.OAuthSessions`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/oauth_sessions.ex#L1)

Helpers for creating and retrieving short-lived OAuth sessions.

# `create_session`

```elixir
@spec create_session(String.t(), map()) ::
  {:ok, Gamend.OAuthSession.t()} | {:error, Ecto.Changeset.t()}
```

# `get_pending_session`

```elixir
@spec get_pending_session(String.t(), String.t() | nil) ::
  Gamend.OAuthSession.t() | nil
```

A session that may still accept a callback: it exists, is `pending`, was
started for `provider`, and is inside `pending_ttl_seconds/0`.

Returns `nil` otherwise, so a stale, replayed or provider-mismatched state is
indistinguishable from one that was never issued.

# `get_session`

```elixir
@spec get_session(String.t()) :: Gamend.OAuthSession.t() | nil
```

# `pending_ttl_seconds`

```elixir
@spec pending_ttl_seconds() :: pos_integer()
```

How long a session may sit in `pending` before a callback stops being accepted.

An OAuth round trip is seconds; the only thing a long window buys is time for
someone to hand a started flow's URL to another person and have that person's
consent land in the starter's session.

# `update_session`

```elixir
@spec update_session(String.t(), map()) ::
  {:ok, Gamend.OAuthSession.t()} | {:error, Ecto.Changeset.t()} | :not_found
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
