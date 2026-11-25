# `Gamend.Analytics.Segment`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics/segment.ex#L1)

The ways the people numbers split: `:all`, `:registered` (an account with
an identity: an email, a provider) and `:guest` (an account backed by
nothing but a device or a browser, `Gamend.Accounts.User.anonymous?/1`).
A visitor with no account is in none of them: the daily counters count
them, no row does.

The split is by what the account is NOW, so a guest who registers later
reads as registered on the days before too: a guest's numbers are the
guests who stayed guests.

A segment can carry one TRAIT too, `{segment, {field, value}}`
(`with_trait/2`): the accounts with an event row whose field holds that
value, any day (`{"device", "phone"}`: an account seen on a phone). The
fields worth one are the host's (`Gamend.Analytics.Catalog.overview/0`'s
`traits`); an account seen on a phone and on a laptop is in both.

# `base`

```elixir
@type base() :: :all | :registered | :guest
```

# `t`

```elixir
@type t() :: base() | {base(), trait()}
```

# `trait`

```elixir
@type trait() :: {String.t(), String.t()}
```

# `all`

```elixir
@spec all() :: [base()]
```

Every segment, `:all` first.

# `condition`

```elixir
@spec condition(:registered | :guest) :: Ecto.Query.dynamic_expr()
```

The `where` for one segment over a `:user` binding.

# `label`

```elixir
@spec label(base()) :: String.t()
```

How a page names it.

# `parse`

```elixir
@spec parse(term()) :: base()
```

A segment from a request parameter (`"guest"`); anything else is `:all`.

# `parse_trait`

```elixir
@spec parse_trait(term()) :: trait() | nil
```

A trait from a request parameter, `"field:value"` (`"device:phone"`), or
nil: a field of letters, digits and `_` (32 at most) and a value of 64 at
most, so nothing else reaches a query.

# `restrict`

```elixir
@spec restrict(Ecto.Queryable.t(), t()) :: Ecto.Query.t()
```

Restricts `query` to one segment: a query on a table with a `user_id` is
joined to `users` (as `:user`); a query that already has a `:user` binding
(`users` itself, `as: :user`) is filtered on it.

# `trait_param`

```elixir
@spec trait_param(trait() | nil) :: String.t() | nil
```

A trait as its parameter (`parse_trait/1`'s); nil for none.

# `with_trait`

```elixir
@spec with_trait(base(), trait() | nil) :: t()
```

`segment` narrowed to the accounts with `trait`; nil leaves it as it is.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
