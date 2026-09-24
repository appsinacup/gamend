# `Gamend.Content.Frontmatter`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/content/frontmatter.ex#L1)

The `---` block at the top of a markdown file.

A subset of YAML, on purpose: scalars, flow lists (`[a, b]`) and block
lists (`- a` lines), and nothing nested. That is what the files in the wild
use — `title`, `description`, `position`, `keywords: [a, b]`,
`authors: [dragos]` — and a YAML parser dependency to read four kinds of
line would be its own liability, which is the argument the single-line
reader here started from. What changed is that a list is a list rather
than the string `"[a, b]"`, and a number is a number.

# `meta`

```elixir
@type meta() :: %{required(String.t()) =&gt; value()}
```

# `value`

```elixir
@type value() :: String.t() | integer() | boolean() | nil | [String.t()]
```

# `body`

```elixir
@spec body(String.t()) :: String.t()
```

Only the body.

# `integer`

```elixir
@spec integer(value()) :: integer() | nil
```

A value as an integer, or nil.

# `list`

```elixir
@spec list(value()) :: [String.t()]
```

A value as a list of strings, however it was written: a flow or block
list, a comma-separated string, one string, or nothing.

# `meta`

```elixir
@spec meta(String.t()) :: meta()
```

Only the keys.

# `parse`

```elixir
@spec parse(String.t()) :: {meta(), String.t()}
```

The block's keys and the body after it. `{%{}, content}` when there is none.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
