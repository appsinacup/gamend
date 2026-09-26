# `Gamend.Accounts.ApiToken`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/api_token.ex#L1)

A personal API token's row. The token itself is never stored.

Fields:

- `name` – what the owner called it, so they can tell two apart
- `token_hash` – SHA-256 of the full token; the lookup key
- `hint` – the first characters after the prefix, shown in lists so a token
  in a CI secret can be matched to its row without revealing it
- `token_version` – the owner's `users.token_version` at creation; a later
  password or email change leaves this behind and the token stops working
- `expires_at` – nil for a token that does not expire. `auth.api_token_max_days`
  can end a token sooner; `Gamend.Accounts.ApiTokens.expires_at/1` has the
  effective date
- `last_used_at` – bumped at most once a minute

# `t`

```elixir
@type t() :: %Gamend.Accounts.ApiToken{
  __meta__: term(),
  expires_at: DateTime.t() | nil,
  expires_in_days: term(),
  hint: String.t() | nil,
  id: String.t() | nil,
  inserted_at: DateTime.t() | nil,
  last_used_at: DateTime.t() | nil,
  name: String.t() | nil,
  token_hash: binary() | nil,
  token_version: integer(),
  updated_at: DateTime.t() | nil,
  user: term(),
  user_id: String.t() | nil
}
```

A personal API token's row.

# `changeset`

```elixir
@spec changeset(t(), map()) :: Ecto.Changeset.t()
```

A new token's name and lifetime. `user_id`, `token_hash`, `hint` and
`token_version` are set by `Gamend.Accounts.ApiTokens.create/2`, never cast.

# `expiry_choices`

```elixir
@spec expiry_choices() :: [pos_integer() | nil]
```

The lifetimes a token may be created with, in days; nil never expires. With
`auth.api_token_max_days` set, the choices stop at the cap (which is itself
one) and nil is gone.

# `max_days`

```elixir
@spec max_days() :: pos_integer() | nil
```

`auth.api_token_max_days`, or nil when a token may live forever.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
