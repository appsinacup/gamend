# `Gamend.Quests.QuestProgress`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/quests/quest_progress.ex#L1)

Ecto schema for the `quest_progress` table — one row per user, quest and
reset period.

## Fields

- `period_key` — reset bucket: a date (`"2026-07-22"`, UTC or the
  player's own, `:quest_clock`) for a daily,
  an ISO week (`"2026-W30"`) for a weekly, `"static"` otherwise. Rolling
  the period is what "resets" a quest — a new period means a fresh row.
- `objective_progress` — map of objective index (as a string) to count
- `status` — `"active"` → `"completed"` (all targets met) → `"claimed"`
- `rewards_granted_at` — set once every reward entry has been applied;
  `claimed` rows without it are retried by the reward-recovery sweep
- `code_id` — the redemption code that finished it, if one did. Written with
  the struct, never cast

# `t`

```elixir
@type t() :: %Gamend.Quests.QuestProgress{
  __meta__: term(),
  claim_count: term(),
  claimed_at: term(),
  code: term(),
  code_id: term(),
  completed_at: term(),
  id: term(),
  inserted_at: term(),
  lock_version: term(),
  metadata: term(),
  objective_progress: term(),
  period_key: term(),
  quest: term(),
  quest_key: term(),
  rewards_granted_at: term(),
  status: term(),
  updated_at: term(),
  user: term(),
  user_id: term()
}
```

# `statuses`

The valid progress statuses.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
