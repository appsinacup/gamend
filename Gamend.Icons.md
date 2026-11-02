# `Gamend.Icons`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/icons.ex#L1)

The site's own icons, by name (`rocket-launch`): heroicons.com's 24px solid
set, read from the host's `heroicons` dependency when this compiles, the same
set the website draws (`GamendWeb.Icons`).

People pick from a few of them instead of uploading an image, for a group's
icon or an account's avatar: `picks/0`. Any other still works where it is
stored, by an API client or from before there was a list.

An icon is nothing but a URL, `path/1` (`/icons/<name>.svg`), stored where
an uploaded image's URL would be (a group's `icon_url`, a user's
`profile_url`, a leaderboard's or a quest's `icon_url`). The website serves
it and draws it inline; a client fetches it against the server's address
like an uploaded image.

# `name`

```elixir
@spec name(String.t() | nil) :: String.t() | nil
```

The name of the icon a URL is (`path/1`), or nil (none, an upload).

# `name?`

```elixir
@spec name?(term()) :: boolean()
```

Whether `name` is an icon's.

# `names`

```elixir
@spec names() :: [String.t()]
```

Every icon's name, sorted: `academic-cap`, …

# `path`

```elixir
@spec path(String.t()) :: String.t()
```

The URL of an icon by name: `/icons/<name>.svg`.

# `picks`

```elixir
@spec picks() :: [String.t()]
```

The icons people pick from, `academic-cap`, …: the same order everywhere.

# `random`

```elixir
@spec random() :: String.t() | nil
```

One of `picks/0` at random, nil when there are none.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
