# `Gamend.Accounts.ApiTokens`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/api_tokens.ex#L1)

Personal API tokens: long-lived bearer tokens for scripts and CI.

An access token from `POST /api/v1/login` lasts fifteen minutes and needs a
password, which suits a game client and nothing that runs unattended — and an
account made with a social login has no password at all. A personal token is
created once on the settings page, sent as `Authorization: Bearer
gamend_pat_…` to any API route that takes an access token, and lasts until it
expires or is revoked.

## What is kept

Only a SHA-256 of the token, under a unique index: a request is one indexed
lookup, and the table holds nothing a client could send. The token is shown
once, at creation. `hint` is its first few characters, so a list can say
which token a CI secret holds without holding it.

## When a token stops working

- It expires (`expires_at/1`: its own `expires_at`, or `auth.api_token_max_days`
  after creation when that is sooner), or its owner revokes it.
- Its owner changes their password or email, or signs out everywhere: each
  bumps `users.token_version`, and a token remembers the version it was made
  under. A stolen session therefore cannot leave a token behind that
  survives the password reset that ends it.
- The account is deactivated — the same check an access token gets, in
  `GamendWeb.Auth.Guardian.resource_from_claims/1`.

Tokens are made only through the settings page, never through the API, so a
leaked token cannot mint another. `Gamend.Retention` prunes expired and
superseded rows.

# `count`

```elixir
@spec count(String.t()) :: non_neg_integer()
```

Count for `list/2`'s pagination.

# `create`

```elixir
@spec create(Gamend.Accounts.User.t(), map()) ::
  {:ok, String.t(), Gamend.Accounts.ApiToken.t()}
  | {:error, Ecto.Changeset.t() | :limit_reached}
```

Create a token for `user`. Answers the token itself — the only time it
exists outside the caller — and the stored row.

`attrs` takes `name` and `expires_in_days`, one of `ApiToken.expiry_choices/0`
(30, 90, 365, or nil for none, unless `auth.api_token_max_days` caps them).
Refused with `:limit_reached` past `Gamend.Limits` `max_api_tokens_per_user`.

# `dead_query`

```elixir
@spec dead_query() :: Ecto.Query.t()
```

Rows no request can use any more: past `expires_at`, or made under an older
`token_version` than their owner's. For `Gamend.Retention`.

# `expired?`

```elixir
@spec expired?(Gamend.Accounts.ApiToken.t()) :: boolean()
```

Whether the token's own lifetime has run out.

# `expires_at`

```elixir
@spec expires_at(Gamend.Accounts.ApiToken.t()) :: DateTime.t() | nil
```

When the token stops working on its own: its `expires_at`, or
`auth.api_token_max_days` after it was made when that comes first. nil when
it never expires. The cap reaches tokens made before it was set.

# `list`

```elixir
@spec list(String.t(), keyword()) :: [Gamend.Accounts.ApiToken.t()]
```

A user's tokens, newest first.

# `prefix`

```elixir
@spec prefix() :: String.t()
```

What every personal token starts with; how the auth plug tells one from a JWT.

# `revoke`

```elixir
@spec revoke(String.t(), String.t()) ::
  {:ok, Gamend.Accounts.ApiToken.t()} | {:error, :not_found}
```

Revoke one of the user's tokens. It stops working on the next request.

# `superseded?`

```elixir
@spec superseded?(Gamend.Accounts.ApiToken.t(), Gamend.Accounts.User.t()) :: boolean()
```

Whether the owner's password or email changed since the token was made.
Such a token is dead; the settings page says so rather than listing it as
working.

# `token?`

```elixir
@spec token?(term()) :: boolean()
```

Whether `value` is shaped like a personal token.

# `touch`

```elixir
@spec touch(Gamend.Accounts.ApiToken.t()) :: :ok
```

Record a use, at most once a minute per token, off the request path: the
caller is an authenticated request and should not wait on a write.

# `verify`

```elixir
@spec verify(String.t()) ::
  {:ok, Gamend.Accounts.User.t(), Gamend.Accounts.ApiToken.t()} | :error
```

The owner and row of a presented token, or `:error` when it is unknown,
expired, or older than its owner's last credential change.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
