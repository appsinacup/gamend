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

A picked icon may carry one of the site's colours, `path/2`
(`/icons/<name>.svg?color=<color>`): `colors/0`, the theme's own by default
(`primary info success warning error`), each a CSS colour the website draws
the icon in (`color_css/1`). A client reads the name from the URL's `color`
and tints it its own way; the SVG served is the same. A host picks its own
colours in Elixir:

    config :gamend_core, Gamend.Icons,
      colors: ["primary", "success", {"rose", "#e11d48"}]

a bare name being the theme's (`var(--color-<name>)`), a pair any CSS colour.

Every user has an icon: one they never picked is theirs by their id, an
icon and a colour (`for_id/1`), the same everywhere they are shown.

# `color`

```elixir
@spec color(String.t() | nil) :: String.t() | nil
```

The colour of an icon's URL (`path/2`), one of `colors/0`, or nil.

# `color?`

```elixir
@spec color?(term()) :: boolean()
```

Whether `color` is one of `colors/0`.

# `color_css`

```elixir
@spec color_css(String.t() | nil) :: String.t() | nil
```

The CSS colour a colour is drawn in: a theme's own name its
`var(--color-<name>)`, a pair's what it gives. Nil for none of `colors/0`.

# `color_for`

```elixir
@spec color_for(term()) :: String.t() | nil
```

One of `colors/0` for `term`: as good as random, the same for it every time. Nil with none.

# `colors`

```elixir
@spec colors() :: [String.t()]
```

The colours an icon is drawn in, by name, in order: the host's
(`config :gamend_core, Gamend.Icons, colors: [...]`), else the theme's
`primary info success warning error`.

# `for_id`

```elixir
@spec for_id(String.t()) :: String.t() | nil
```

The icon a user who picked none has, by their `id`: one of `picks/0` in one
of `colors/0`, the same for that id every time, so it is theirs wherever they
are shown and in what every API answers. Nil when there are no icons.

# `name`

```elixir
@spec name(String.t() | nil) :: String.t() | nil
```

The name of the icon a URL is (`path/1`), or nil (none, an upload). A colour
on it (`?color=`) is no part of the name, and one the site no longer has
keeps the icon (drawn in none).

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
@spec path(String.t(), String.t() | nil) :: String.t()
```

The URL of an icon by name: `/icons/<name>.svg`, with `color` when one of `colors/0`.

# `picks`

```elixir
@spec picks() :: [String.t()]
```

The icons people pick from, `academic-cap`, …: the same order everywhere.

# `put_color`

```elixir
@spec put_color(map(), String.t()) :: map()
```

`params` with the colour picked beside an icon (`"<key>_color"`, what
`<.icon_picker>` sends) put on the icon's URL at `key` (`path/2`), the
colour's own key gone. An upload's URL stays as it is: a colour is only an
icon's. With no icon picked the colour's key stays, for the form to draw it
as the one an icon picked next will have.

# `random`

```elixir
@spec random() :: String.t() | nil
```

One of `picks/0` at random, nil when there are none.

# `random_path`

```elixir
@spec random_path() :: String.t() | nil
```

The URL of an icon at random in a colour at random (`path/2`), nil when there are none.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
