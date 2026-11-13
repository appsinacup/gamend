# `Gamend.Quests.Codes`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/quests/codes.ex#L1)

Redemption codes: making them, finding them, stopping them.

A code is a way to finish a `code_only` quest; the quest holds everything
about what the code gives. Redeeming one is `Gamend.Quests.redeem_code/2`,
which uses the engine's private steps. Public API is re-exported by
`Gamend.Quests`.

# `all`

```elixir
@spec all(String.t()) :: [Gamend.Quests.QuestCode.t()]
```

Every code of a quest, oldest first: what an export writes.

# `count`

```elixir
@spec count(String.t(), keyword()) :: non_neg_integer()
```

How many codes match (same filters as `list/2`).

# `create`

```elixir
@spec create(Gamend.Quests.Quest.t(), map()) ::
  {:ok, Gamend.Quests.QuestCode.t()}
  | {:error, :not_code_only | Ecto.Changeset.t()}
```

Makes one code with a chosen token. A token another code already has, even
on another quest, fails on `:token`.

# `find`

```elixir
@spec find(String.t()) :: Gamend.Quests.QuestCode.t() | nil
```

The code what a player typed stands for, its quest preloaded, or nil.
Says nothing about whether it still works.

# `generate`

```elixir
@spec generate(Gamend.Quests.Quest.t(), integer(), keyword()) ::
  {:ok, non_neg_integer()}
  | {:error,
     :not_code_only | :invalid_count | :too_many_codes | Ecto.Changeset.t()}
```

Makes `count` random codes, shown as `XXXX-XXXX-XXXX-XXXX`, and answers how
many it made. Capped at `max_codes_per_generate`, so a run finishes inside
one request; to have more, run it again.

## Options
- `:max_uses` — default `1`, `nil` for every player once
- `:metadata` — copied onto each player's progress row

# `get`

```elixir
@spec get(Ecto.UUID.t()) :: Gamend.Quests.QuestCode.t() | nil
```

A code by id, or nil.

# `list`

```elixir
@spec list(String.t(), keyword()) :: [Gamend.Quests.QuestCode.t()]
```

One quest's codes, newest first.

## Options
- `:search` — the exact code, typed any way a player could type it
- `:page` / `:page_size`

# `set_status`

```elixir
@spec set_status(Ecto.UUID.t(), String.t()) ::
  {:ok, Gamend.Quests.QuestCode.t()}
  | {:error, :code_not_found | :invalid_state}
```

Revokes a code or restores it. Stopping every code of a quest at once is
unticking the quest's `active`.

# `stream_all`

```elixir
@spec stream_all(String.t(), pos_integer()) :: Enumerable.t()
```

`all/1` read `batch` codes at a time, as a lazy stream: an export of a
quest with a few hundred thousand codes holds one batch, never the table.
Each batch is its own query, paged by `(inserted_at, id)`, so no
transaction stays open while the caller writes.

# `used_by`

```elixir
@spec used_by(Ecto.UUID.t(), pos_integer()) :: [Gamend.Accounts.User.t()]
```

The first few players who redeemed a code, with how many there are in the
`uses` column for the rest. A public code can have millions.

# `used_by_codes`

```elixir
@spec used_by_codes([Ecto.UUID.t()], pos_integer()) :: %{
  required(Ecto.UUID.t()) =&gt; [Gamend.Accounts.User.t()]
}
```

`used_by/2` for a page of codes in one statement: `%{code_id => [User.t()]}`,
a code nobody redeemed absent. Each code's first `limit` rows come off the
`(code_id, completed_at, id)` index, so a code with millions costs as
little as one with three.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
