# `Gamend.Quests.QuestCode`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/quests/quest_code.ex#L1)

Ecto schema for the `quest_codes` table: one redemption code of a
`code_only` quest (`Gamend.Quests.redeem_code/2`).

## Fields

- `token` — the code as people see it (`ABCD-EFGH-JKMN-PQRS`, `春节快乐`).
  Kept in plain text so an admin can export a batch again and read a public
  code
- `lookup` — `normalize/1` of the token, unique across quests, and the only
  column a redeem reads by: the player types only the code, so nothing else
  can say which quest is meant
- `max_uses` — `1` single-use, `N` the first N players, `nil` every player
  once
- `uses` — how many players redeemed it, counted on the row for a capped
  code only (the cap is checked against it). An uncapped code's redeems
  would all update this one row, so it stays as it is and
  `Gamend.Quests.Codes` reads its count from `quest_progress`
- `status` — `"active"` or `"revoked"`
- `metadata` — copied onto each player's `quest_progress` row, so a hook can
  tell which channel a redemption came from. Players can read it there

# `t`

```elixir
@type t() :: %Gamend.Quests.QuestCode{
  __meta__: term(),
  id: term(),
  inserted_at: term(),
  lookup: term(),
  max_uses: term(),
  metadata: term(),
  quest: term(),
  quest_key: term(),
  status: term(),
  token: term(),
  updated_at: term(),
  uses: term()
}
```

# `lookups`

```elixir
@spec lookups(String.t()) :: [String.t()]
```

The lookups a typed code may stand for: its `normalize/1`, then the same
with the letters people type for Crockford's look-alike digits folded in
(`o` → `0`, `i` and `l` → `1`). A generated token has none of those
letters, so `ABCD-0O1L` typed from a printed card still finds `ABCD-0011`;
a token an admin chose keeps its own letters, and its exact form comes first.

# `max_token`

```elixir
@spec max_token() :: pos_integer()
```

The longest a token may be, in characters of its normalized form.

# `normalize`

```elixir
@spec normalize(String.t()) :: String.t()
```

The form of a code redeems compare: full-width forms folded, spaces, dashes
and case gone, so `ＡＢＣ－１２３`, `abc 123` and `ABC-123` are one code.
In Elixir, so both adapters compare the same bytes with no collation.

# `plausible?`

```elixir
@spec plausible?(String.t()) :: boolean()
```

Whether `raw` is short enough to normalize at all. NFKC can lengthen a
string, so the real cap applies after it; this one refuses a megabyte before
any work is done on it.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
