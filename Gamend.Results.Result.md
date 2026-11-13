# `Gamend.Results.Result`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/results/result.ex#L1)

Ecto schema for `results`: one play by one player (`Gamend.Results`).

`metadata` is what the play was (its settings), set when it starts; what
happened is its events (`Gamend.Results.Event`). `lobby_id` is the lobby
it ran in, kept as a plain id: the lobby is deleted long before the
result is.

# `t`

```elixir
@type t() :: %Gamend.Results.Result{
  __meta__: term(),
  ended_at: term(),
  event_count: term(),
  id: term(),
  kind: term(),
  lobby_id: term(),
  metadata: term(),
  started_at: term(),
  status: term(),
  user: term(),
  user_id: term(),
  visibility: term()
}
```

# `statuses`

```elixir
@spec statuses() :: [String.t()]
```

Where a play is: `open` while it runs, `ended` once it is over.

# `visibilities`

```elixir
@spec visibilities() :: [String.t()]
```

Who may read a result: KV's access words.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
