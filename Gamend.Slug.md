# `Gamend.Slug`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/slug.ex#L1)

A name that is also its URL, unique per account: a group's
(`Gamend.Groups`, `<owner>/<slug>`), and in a host a project's or a store
account's (Forge's `/projects/<owner>/<name>`).

Lowercase letters and digits of any script (`crimson-order`, `红色军团`),
joined by single `-` or `_`. A letter carries at most three combining marks,
as a username's does, and is spelled as a username is
(`Gamend.Accounts.Username.normalize/1`). Unique per account, by a unique
index the changeset names.

A leaderboard's and a tournament's slug is looser (`validate_loose/2`), since
seasons and editions share one and `__` and a leading `_` were always allowed:
the same letters, with `-` and `_` anywhere but a leading `-`.

# `format`

```elixir
@spec format() :: Regex.t()
```

The format a slug has to have.

# `free`

```elixir
@spec free(String.t(), (String.t() -&gt; boolean())) :: String.t()
```

`base`, or `base-2`, `base-3`… : the first one `taken?` says is free.

# `loose_format`

```elixir
@spec loose_format() :: Regex.t()
```

The format `validate_loose/2` checks.

# `normalize`

```elixir
@spec normalize(String.t()) :: String.t()
```

The spelling a slug is stored and looked up under.

# `random`

```elixir
@spec random() :: String.t()
```

Two random words, `swift-otter`: a name to start from, for a form that
offers one before anything is typed (a new group's, and in a host a new
server's). Checked against nothing: about 1,500 of them.

# `slugify`

```elixir
@spec slugify(String.t() | nil, String.t()) :: String.t()
```

The nearest slug to `text`: normalized, every run of anything else turned
into one `-`, trimmed, at most 64 long, and `fallback` when nothing is
left. `"My_Game.v2"` is `my_game-v2`, `"红色 军团"` is `红色-军团`.

# `validate`

```elixir
@spec validate(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
```

Check `field` is a slug, at most `:max` long, and unique per account by
the unique index `:index`.

# `validate_loose`

```elixir
@spec validate_loose(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
```

Normalize `field` and check it has `loose_format/0`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
