---
icon: hero-flag
---

# Quests / Progression

One engine for achievements, dailies, seasonal events and quest lines. A quest is objectives + rewards plus four independent settings — combine them freely.

| reset | When progress restarts: `never`, `daily`, `weekly`, `monthly`, or `interval` with `reset_interval_days` (biweekly = 14, any cadence). Every period boundary is 00:00 UTC, the same instant for every player - so a daily rolls over at noon in New Zealand and the previous afternoon on the US west coast. Show players the countdown a quest already carries rather than a reset time. |
|---|---|
| starts_at / ends_at | Availability window. Set them and it is an "event". |
| prerequisite_quest_key | Must be completed first. Set it and it is a "chain" — hidden and frozen until unlocked. |
| category | Free-form label for your UI tabs. No engine behavior. |

## Examples

```text
# Achievement — permanent, pays out on completion, no claim step.
%{key: "first_win", title: "First Blood", category: "achievement",
  reset: "never", auto_claim: true,
  objectives: [%{event: "match_won", target: 1}]}

# Daily — resets at UTC midnight, player taps Claim for the reward.
%{key: "daily_win_3", title: "Win 3 matches", category: "daily",
  reset: "daily",
  objectives: [%{event: "match_won", target: 3}],
  rewards: [%{type: "currency", code: "gold", amount: 100}]}

# Biweekly — any cadence via interval.
%{key: "fortnight_raid", title: "Fortnight Raid", reset: "interval",
  reset_interval_days: 14,
  objectives: [%{event: "raid_won", target: 5}]}

# Event — a weekly quest that only runs during a season.
%{key: "summer_weekly", title: "Summer Splash", category: "seasonal",
  reset: "weekly",
  starts_at: ~U[2026-06-01 00:00:00Z], ends_at: ~U[2026-09-01 00:00:00Z],
  objectives: [%{event: "match_won", target: 10}]}

# Chain — hidden until "first_win" is done. Works with ANY reset, so
# dailies and events chain too. Multi-objective, item reward.
%{key: "veteran", title: "Veteran", category: "story", reset: "never",
  prerequisite_quest_key: "first_win",
  objectives: [%{event: "match_won", target: 10},
               %{event: "enemy_killed", target: 50, params: %{"map" => "desert"}}],
  rewards: [%{type: "item", code: "loot_crate", amount: 1}]}
```

## Chains

`prerequisite_quest_key` links quests into tiers. A chain occupies **one
slot** in the quest list: the earliest tier the player can still act on — in
progress or completed-but-unclaimed. Claiming advances the slot to the next
tier; once every tier is claimed the final one stands for the chain. On the
web quests page, clicking the chained card opens the whole chain — earlier
tiers and locked ones ahead alike (hidden quests stay `???` until earned).
Plugins can read the same view with
`GameServer.Quests.chain(user_id, quest_key)`.

Quests also carry an optional `icon_url`; when unset, the web UI shows the
shared default quest icon and the API returns an empty value so game clients
can apply their own.

## Progress is server-authoritative

Clients cannot advance their own quests — there is no endpoint for it. Core reports login, chat_message, score_submitted, lobby_joined and match_won; your game reports the rest from hooks:

```elixir
GameServer.Quests.report_event(user_id, "enemy_killed", 1, %{"map" => "desert"})
```

Every active quest with a matching objective advances (an objective's params must all match the event meta). Rewards pay into Economy/Inventory exactly once: auto_claim quests on completion, others on claim.

## API, events, hooks

Player endpoints live under `/api/v1/me/quests` and the catalogue under
`/api/v1/quests` (gated by `GAMEND_FEATURES_LIST_QUESTS`) - see [/api/docs](/api/docs).

- **Channel events:** `quest_progress`, `quest_completed`, `quest_claimed`
- **Hooks:** `before_quest_claim/3` (may veto), `after_quest_completed/1`,
  `after_quest_claimed/1`
- **Admin:** `/admin/quests` and `/api/v1/admin/quests` — CRUD plus grant,
  reset, claim and completion funnels

Resets need no scheduled job — the current period is derived from the clock, so a new period simply starts a new progress row. Hidden quests show as "???" until earned.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`GameServer.Quests`](https://appsinacup.com/game_server/GameServer.Quests.html) - the functions a plugin calls, with their
  signatures and docs.
