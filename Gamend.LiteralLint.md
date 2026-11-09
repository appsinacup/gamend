# `Gamend.LiteralLint`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/literal_lint.ex#L1)

Finds the strings that are really names: a status, an action, a kind, typed
out wherever it is used. `mix gamend.literal.lint` runs it.

`"creat"` compiles, and the module that reads it simply never matches. A
name that one module writes and another reads belongs to a module that owns
it, and everyone else asks that module (CONTRIBUTING.md, "Named strings").

A string counts when it is shaped like a name (`"failed"`, `"move_in"`,
`"gamend.db"`, no spaces) and stands in code, and it is reported when it
stands in two or more modules, or five or more times in one. In a template
(`~H`, `.heex`) only a comparison counts: `@s == "failed"`.

`@failed "failed"` and `defp failed, do: "failed"` name a string for their
own module, which is fine, until a second module of the same context gives
the same string the same name. Then the name has two homes, and needs an
owner. Across contexts the same word is nearly always a different thing
(`@page` in a schema, `@page` in a presence record).

These do not count, because a name for them would say less than they do:

  * what an owner declares: `use Gamend.Names`, and a public function that
    is nothing but its value (`defmacro failed, do: "failed"`)
  * documentation attributes
  * a key: `%{"id" => id}`, `params["id"]`, `Map.get(params, "id")`, `Map.take/2`,
    `get_in/2`. Keys are the shape of a document, not a closed set of values
  * text: gettext, `Logger`, `raise`, `IO`, `Mix`, `System`, and any sigil
    other than a string `~w` or a template
  * a LiveView event's name in `handle_event/3`, and HTTP header names
  * an API error's code in `reply_error/3`, which has to be a literal:
    `mix gamend.api.lint` (R18) holds it to `GamendWeb.ErrorStatus`
  * a CSS class of the shared vocabulary (`"badge-error"`), and `"true"`

It is a heuristic, and says so. A use it is wrong about is marked with the
reason, on its line or the line above:

    # literal-ok: Stripe's event name
    "invoice.paid" -> paid(event)

    <%!-- literal-ok: the browser's value --%>
    <b :if={@kind == "submit"}>x</b>

# `occurrence`

```elixir
@type occurrence() :: %{
  literal: String.t(),
  file: String.t(),
  line: pos_integer() | nil,
  module: String.t() | nil,
  as: atom()
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

---

*Consult [api-reference.md](api-reference.md) for complete listing*
