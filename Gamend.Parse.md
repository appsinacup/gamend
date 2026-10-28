# `Gamend.Parse`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/parse.ex#L1)

Parsing and normalizing values that arrive from outside: request bodies, form
params, hook arguments, JSON.

Strict means the whole value must be the thing. `"12abc"` is not 12. That is
the difference from `GamendWeb.Helpers.ParamParser.parse_int/1`, which is
deliberately lenient for filter params where a stray suffix should still
narrow the list — for a value that gets *stored* (a score, a count, a
quantity), accepting a prefix quietly writes a number nobody sent.

It exists because there was no general home for this. The strict version
lived in `Gamend.Payments.Params` under a payments name, so code outside
payments either reached for `String.to_integer/1` — which raises, and turned
`"score": "abc"` on the admin leaderboard API into a 500 — or wrote its own.

# `blank_to_nil`

```elixir
@spec blank_to_nil(term()) :: term()
```

`nil` for `nil` or `""`, the value otherwise -- what an optional filter from a
form means when it is left empty. Not trimmed: a caller that wants
`"  "` treated as blank trims first.

Eleven admin LiveViews and two chat contexts each defined this privately.

# `integer`

```elixir
@spec integer(term()) :: integer() | nil
```

An integer, or a string that is exactly an integer (surrounding whitespace
allowed). `nil` for anything else, including floats and partial numbers.

# `integer`

```elixir
@spec integer(term(), default) :: integer() | default when default: term()
```

Like `integer/1`, with `default` in place of `nil`.

# `string_keys`

```elixir
@spec string_keys(map()) :: map()
```

A map with its atom keys turned into strings — the top level only.

Attributes reach a context either atom-keyed (an internal call, a plugin) or
string-keyed (a request), and `Ecto.Changeset.cast/3` rejects a mix of the
two. Nested values are left alone: a `metadata` map is stored as given.
Hooks and quests each carried a private copy.

# `string_keys_deep`

```elixir
@spec string_keys_deep(term()) :: term()
```

Like `string_keys/1`, but all the way down through nested maps and lists —
for a provider payload read field by field, where a nested atom key would
simply never match.

# `uuid`

```elixir
@spec uuid(term()) :: Ecto.UUID.t() | nil
```

A UUID string, or `nil`: the 36-character hyphenated form only.

`Ecto.UUID.cast/1` also takes any 16-byte binary as a raw UUID, so a
16-character slug or name (`"weekend-gauntlet"`) cast to an id and its own
lookup never ran. Ask this wherever a value may be an id or something else.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
