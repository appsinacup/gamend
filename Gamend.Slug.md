# `Gamend.Slug`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/slug.ex#L1)

A name that is also its URL, unique per account: a group's
(`Gamend.Groups`, `<owner>/<slug>`), and in a host a project's or a store
account's (Forge's `/projects/<owner>/<name>`).

Lowercase letters and digits, joined by single `-` or `_`, as a GitHub
repository name reads once it is lowercased. Unique per account, by a
unique index the changeset names.

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

The nearest slug to `text`: lowercased, every run of anything else turned
into one `-`, trimmed, at most 64 long, and `fallback` when nothing is
left. `"My_Game.v2"` is `my_game-v2`.

# `validate`

```elixir
@spec validate(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
```

Check `field` is a slug, at most `:max` long, and unique per account by
the unique index `:index`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
