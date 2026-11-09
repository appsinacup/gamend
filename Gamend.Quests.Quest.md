# `Gamend.Quests.Quest`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/quests/quest.ex#L1)

Ecto schema for the `quests` table.

Three independent dimensions, so any combination is expressible:

- **`reset`** — when progress starts over: `"never"` (permanent, e.g. an
  achievement), `"daily"`, `"weekly"`, `"monthly"`, or `"interval"` with
  `reset_interval_days` (biweekly = 14, or any cadence).
- **`starts_at`/`ends_at`** — an availability window ("event" quests). Works
  with any reset, so a daily can run only during a seasonal window.
- **`prerequisite_quest_key`** — must be completed first ("chains"). Works
  with any reset, so dailies and events can chain too.

## Fields

- `key` — unique slug (e.g. "daily_win_3"); progress rows reference it
- `objectives` — list of `Gamend.Quests.Objective` (event/target/params)
- `rewards` — list of `Gamend.Quests.Reward`, paid exactly-once
- `auto_claim` — grant rewards on completion without a claim step
- `hidden` — details withheld until earned (a teaser); the row still lists
- `active` — inactive quests never advance and are not listed
- `code_only` — nothing but a redemption code finishes it
  (`Gamend.Quests.redeem_code/2`). It has no objectives, never resets, and
  sits in no group or chain, which keeps the event engine, periods and
  collapsing out of it. It lists for a player only once they redeem it

## Grouping, which has three unrelated forms

- **`category`** — a label your UI filters or tabs by. No engine behavior;
  every quest in a category still lists as its own row.
- **`group_key`** (+ `group_title`, naming the collapsed entry) — many quests,
  one list entry the player opens. Unordered: every member is live at once and
  the entry stands for whichever is most worth acting on (52 countries to
  chart, in any order).
- **`prerequisite_quest_key`** — a chain. Also one entry, but because the
  tiers are *ordered* and only one is reachable at a time.

A quest may carry both a category and a group key. A chain inside a group
collapses as a chain first, then contributes its surviving entry to the group.

# `t`

```elixir
@type t() :: %Gamend.Quests.Quest{
  __meta__: term(),
  active: term(),
  auto_claim: term(),
  category: term(),
  code_only: term(),
  counter: term(),
  description: term(),
  ends_at: term(),
  group_key: term(),
  group_title: term(),
  hidden: term(),
  icon_url: term(),
  id: term(),
  inserted_at: term(),
  key: term(),
  metadata: term(),
  objectives: term(),
  prerequisite_quest_key: term(),
  progress: term(),
  reset: term(),
  reset_interval_days: term(),
  rewards: term(),
  sort_order: term(),
  starts_at: term(),
  title: term(),
  updated_at: term()
}
```

# `resets`

The valid reset cycles.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
