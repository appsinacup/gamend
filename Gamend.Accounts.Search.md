# `Gamend.Accounts.Search`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/search.ex#L1)

Finding users: the player-facing search and the admin user listing.

Split out of `Gamend.Accounts`, which still exposes every function here under
the same name.

# `count_list_all_users`

```elixir
@spec count_list_all_users(map()) :: non_neg_integer()
```

Row count for `list_all_users/2` under the same filters.

# `count_search_users`

```elixir
@spec count_search_users(String.t()) :: non_neg_integer()
```

Count users matching a username/display name query or exact id. Returns integer.

# `list_all_users`

```elixir
@spec list_all_users(map(), keyword()) :: [Gamend.Accounts.User.t()]
```

Admin user listing: search across identity fields (or an exact id), optional
facet filters, sorting and pagination — the query behind the admin Users page.

Distinct from `search_users/2`, the privacy-safe player search: this matches
sensitive fields a player cannot, so it is admin-only.

`filters` keys (string or atom): `:search` (term or full id), `:facets` (list
of `"online"`, `"unactivated"`, `"unverified"` — an email never confirmed —
and provider names). `opts`: `:page`,
`:page_size`, `:sort_field`, `:sort_dir`.

# `search_users`

```elixir
@spec search_users(String.t(), Gamend.Types.pagination_opts()) :: [
  Gamend.Accounts.User.t()
]
```

Search users by display name (case-insensitive prefix match) or exact numeric id.

Returns a list of User structs.

## Options

See `t:Gamend.Types.pagination_opts/0` for available options.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
