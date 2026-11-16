# `Gamend.TimeLint`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/time_lint.ex#L1)

Finds a time a page formats by hand. `mix gamend.time.lint` runs it.

An instant a reader sees is `<.timestamp at={…} />` (relative by default,
"7m ago", "in 12 days"), and a span is `<.duration>` (CONTRIBUTING.md, Time).
Both are said again in the reader's zone and language, and the relative one
stays current while the page is open. A hand-made format is none of that: a
UTC hour that reads as local, English in every language, "3d ago" frozen at
the moment the page was drawn.

In a page's code (a LiveView, a component, a controller's HTML module, a
`.heex` template) it reports:

  * `Calendar.strftime/2` and `to_iso8601`: a date written out by hand
  * `{@thing.inserted_at}`: a DateTime interpolated raw, which Elixir writes
    as "2026-11-15 14:23:00Z"
  * a hand-built relative phrase in gettext: "%{count}m ago", "Ends in
    %{time}", "%{count} days left"

Plain text that cannot hold an element (a flash, an `<option>`, a stat
card's value) uses `GamendWeb.TimeText`. A use that is right as it is (a
chart's axis, a filename, a feed) is marked with the reason, on its line or
the line above:

    # time-ok: an axis label, a calendar day
    defp label(%Date{} = day), do: Calendar.strftime(day, "%m-%d")

It is a heuristic, read line by line, and says so.

# `offense`

```elixir
@type offense() :: %{
  file: String.t(),
  line: pos_integer(),
  rule: atom(),
  text: String.t()
}
```

# `offenses`

```elixir
@spec offenses() :: [offense()]
```

Every hand-made time in a page under the scan roots, by file and line.

# `offenses_in`

```elixir
@spec offenses_in(String.t(), String.t()) :: [offense()]
```

The hand-made times in one file's source.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
