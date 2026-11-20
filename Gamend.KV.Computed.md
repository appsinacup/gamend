# `Gamend.KV.Computed`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/kv/computed.ex#L1)

Rows the host computes: read like any row, stored nowhere.

A page often draws more than what is stored: a level from the km banked, a
track with what is owned and what waits. A client needs the same, live,
and a second copy of it in a row would have to be kept in step with the
first. A computed row is that value under a key of its own:

    config :gamend_core, :computed_rows, %{
      "pass" => %{value: {MyGame.Pass, :row}, from: ["progress", "sail_day"]}
    }

  * `value` is `{module, function}`, called with the scope asked for
    (`%{user_id: id | nil, lobby_id: id | nil, part: part | nil}`): a map
    is the row's value, anything else no row.
  * `from` lists the stored keys it is worked out from. A write or a delete
    of one, in the same scope, says the computed row moved.

A key ending in `*` is a family of rows, one a part: a row per language
worked out from that language's stored row.

    "word_pools:*" => %{value: {MyGame.WordPools, :row}, from: ["words:*"]}

`word_pools:fr` is then `MyGame.WordPools.row/1` with `part: "fr"`, and a
write of `words:fr` moves it, and only it. A `from` key with no `*` moves
no row of a family: which part would it be? A key named whole wins over a
family, and the longest prefix over a shorter one, as `kv_schemas`
patterns do.

`Gamend.KV.get/2` answers it, so the HTTP API and `kv:subscribe` do too,
behind the same `before_kv_get` decision as a stored row. When it moves,
everyone subscribed to it is told `{:kv_stale, %{key, user_id, lobby_id}}`
on its topic (`Gamend.KV.subscribe/2`), after the write commits; the user
channel then reads it once and pushes `kv_updated` (or `kv_deleted` where
it is gone), so a client sees an ordinary row. Nobody subscribed, nothing
computed.

What it depends on outside the store (an inventory, a wallet) the host
says itself: `Gamend.KV.refresh/2`.

A computed key is never stored: a row written under it is never read.

# `scope`

```elixir
@type scope() :: %{
  user_id: String.t() | nil,
  lobby_id: String.t() | nil,
  part: String.t() | nil
}
```

# `computed?`

```elixir
@spec computed?(String.t()) :: boolean()
```

Whether `key` is a computed row, one of a family's included.

# `dependents`

```elixir
@spec dependents(String.t()) :: [String.t()]
```

The computed rows worked out from the stored key `key`.

# `fetch`

```elixir
@spec fetch(String.t(), String.t() | nil, String.t() | nil) ::
  {:ok, Gamend.KV.payload()} | :error | :not_computed
```

The computed row `key` in a scope: `{:ok, payload}`, `:error` where the host
answers no row, `:not_computed` for a key that is stored.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
