# `Gamend.LiteralLint`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/literal_lint.ex#L1)

Finds the strings that are really names: a status, an action, a kind, typed
out wherever it is used. `mix gamend.literal.lint` runs it.

`"creat"` compiles, and the module that reads it simply never matches. A
name that one module writes and another reads belongs to a module that owns
it, and everyone else asks that module (CONTRIBUTING.md, "Named strings").

A string counts when it is shaped like a name (`"failed"`, `"move_in"`,
`"gamend.db"`, no spaces) and stands in code, and it is reported when it
stands in two or more modules, or five or more times in one. These do not
count, because a name for them would say less than they do:

  * the value of a module attribute, or a function that is nothing but its
    value: `@failed "failed"` and `defmacro failed, do: "failed"` are the cure
  * a key: `%{"id" => id}`, `params["id"]`, `Map.get(params, "id")`, `Map.take/2`,
    `get_in/2`. Keys are the shape of a document, not a closed set of values
  * text: gettext, `Logger`, `raise`, `IO`, `Mix`, `System`, and any sigil
    other than a string `~w`, so a HEEx template is not read
  * a LiveView event's name in `handle_event/3`, and HTTP header names
  * an API error's code in `reply_error/3`, which has to be a literal:
    `mix gamend.api.lint` (R18) holds it to `GamendWeb.ErrorStatus`
  * a CSS class of the shared vocabulary (`"badge-error"`), and `"true"`

It is a heuristic, and says so. A use it is wrong about is marked with the
reason, on its line or the line above:

    # literal-ok: Stripe's event name
    "invoice.paid" -> paid(event)

What was already there when the check arrived is counted in
`.literal-lint-baseline`. A string there may appear that many times and no
more, so the count only goes down.

# `baseline`

```elixir
@type baseline() :: %{optional(String.t()) =&gt; non_neg_integer()}
```

# `occurrence`

```elixir
@type occurrence() :: %{
  literal: String.t(),
  file: String.t(),
  line: pos_integer() | nil,
  module: String.t() | nil
}
```

# `offender`

```elixir
@type offender() :: %{
  literal: String.t(),
  count: pos_integer(),
  modules: pos_integer(),
  occurrences: [occurrence()]
}
```

# `baseline_file`

```elixir
@spec baseline_file() :: String.t()
```

Where the counts of what was already there are kept.

# `format_baseline`

```elixir
@spec format_baseline([offender()]) :: String.t()
```

The text of a baseline holding these offenders.

# `new_offenders`

```elixir
@spec new_offenders([offender()], baseline()) :: [offender()]
```

The offenders beyond what the baseline allows.

# `occurrences_in`

```elixir
@spec occurrences_in(String.t(), String.t()) :: [occurrence()]
```

The named-looking strings in one file's source.

# `offenders`

```elixir
@spec offenders() :: [offender()]
```

Every string under the scan roots that should be named, most used first.

# `offenders`

```elixir
@spec offenders([occurrence()]) :: [offender()]
```

Groups occurrences into the strings that should be named, most used first.

# `parse_baseline`

```elixir
@spec parse_baseline(String.t()) :: baseline()
```

Reads a baseline's text: `<count> <string>`, a line each, `#` for a comment.

# `read_baseline`

```elixir
@spec read_baseline(String.t()) :: baseline()
```

The baseline in the working directory, empty if there is none.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
