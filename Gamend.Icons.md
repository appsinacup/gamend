# `Gamend.Icons`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/icons.ex#L1)

The icons people pick for what is theirs: a group's (`Gamend.Groups`), and
an account's in place of a picture (`Gamend.Accounts.User`'s
`avatar_icon`). Heroicon names (`rocket-launch`, heroicons.com's solid
set), one list for every picker (`choices`).

A picked icon is stored or answered as its URL, `path/1`
(`/icons/<name>.svg`): the website serves it and draws it inline
(`GamendWeb.Icons`, which also draws a leaderboard's, a tournament's or a
quest's `icon_url` of that form), and a client fetches it against the
server's address like an uploaded image.

# `choice?`

```elixir
@spec choice?(term()) :: boolean()
```

Whether `name` is one of `choices/0`.

# `choices`

```elixir
@spec choices() :: [String.t()]
```

The icons to pick from (`choices`), heroicon names.

# `name`

```elixir
@spec name(String.t() | nil) :: String.t() | nil
```

The name of one of `choices/0` a URL is (`path/1`), or nil (none, an upload).

# `path`

```elixir
@spec path(String.t()) :: String.t()
```

The URL of an icon by name: `/icons/<name>.svg`.

# `random`

```elixir
@spec random() :: String.t() | nil
```

One of `choices/0` at random, nil when there are none.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
