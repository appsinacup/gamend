---
icon: hero-flag-solid
---

# Quests / Progression

One engine for achievements, dailies, seasonal events, quest lines and redemption codes. A quest is objectives + rewards plus five independent settings that combine freely.

| Setting | What it does |
|---|---|
| reset | When progress restarts: `never`, `daily`, `weekly`, `monthly`, `interval` with `reset_interval_days` (biweekly = 14, any cadence), or `repeat` (again the moment it is claimed, no clock). Every period boundary is 00:00 UTC, the same instant for every player - so a daily rolls over at noon in New Zealand and the previous afternoon on the US west coast. Show players the countdown a quest already carries rather than a reset time. `config :gamend_core, :quest_clock, :player` turns each player's periods over on their own clock instead. |
| starts_at / ends_at | Availability window. Set them and it is an "event". |
| prerequisite_quest_key | Must be completed first. Set it and it is a "chain" — hidden and frozen until unlocked. |
| category | Free-form label for your UI tabs. No engine behavior. |
| group_key | Quests sharing it list as one entry the player opens. Set it and it is a "group". |

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
slot** in the quest list: the earliest tier the player can still act on, whether in
progress or completed-but-unclaimed. Claiming advances the slot to the next
tier; once every tier is claimed the final one stands for the chain. The web
quests page shows a chain as the tier the player is on and nothing more: the
next tier appears once this one is done.

Quests also carry an optional `icon_url`; when unset, the web UI shows the
shared default quest icon and the API returns an empty value so game clients
can apply their own.

## Groups

`group_key` also collapses many quests into **one slot**, but for the opposite
reason to a chain: nothing is ordered and every member is live at once, like 52
countries to visit, in any order. The slot is titled by `group_title` (every
member declares the same one) and shows the member worth acting on: claimable
first, then furthest along. `group_size` on the entry says how many it stands
for.

```text
%{key: "visit_spain", title: "Visit Spain", group_key: "world_tour",
  group_title: "Sail the world", objectives: [%{event: "port_visited", target: 1,
  params: %{"country" => "ES"}}]}
```

Clicking the card on the web quests page opens the members. Over HTTP, pass
`?group=world_tour` to `/api/v1/me/quests` to list that one group in full while
every other stays collapsed; plugins read the same view with
`Gamend.Quests.group(user_id, group_key)`. Either way a member the player
cannot see yet (out of window, prerequisite unmet) stays out.

A quest can carry both a category and a group key; they are unrelated. A chain
inside a group collapses as a chain first, then contributes its surviving entry
to the group.

## Redemption codes

A code is a way to finish a quest: reward codes for an event, invitation keys for a test server. Tick **Only by code** on a quest (`code_only: true`: no objectives, `reset: "never"`, no group or prerequisite), then press its **Codes** button on `/admin/quests` to generate a batch, or add one code with any text (`春节快乐`).

| Uses on a code | Who can redeem it |
|---|---|
| `1` | One player |
| `N` | The first N players |
| blank | Every player, once each |

A player types it at `/redeem`, or the game calls `POST /api/v1/me/quests/redeem` with `{"token": "ABCD-EFGH-JKMN-PQRS"}`. Spaces, dashes, letter case and full-width characters do not matter. It answers like a claim, `{progress, rewards}`, and pays at once.

| Situation | API | |
|---|---|---|
| Unknown, expired, revoked, disabled, used up | 404 `code_not_found` | One answer for every miss |
| This player has this quest, by any code | 409 `already_redeemed` | A player redeems a quest once |
| A guest, where `:quest_claims` needs an account | 403 `account_required` | |
| Too many tries | 429 `redeem_rate_limit` | `GAMEND_LIMITS_MAX_REDEEM_ATTEMPTS_PER_MIN` |
| `before_quest_claim` refused | 403 `rejected` | The hook's words. The code is not spent |

**`/redeem` lists every open code-only quest**, and `/redeem?quest=spring_gift` shows just that one, so an email can link to it. `GET /api/v1/quests/redeemable` is the same list. The link names the quest, never a code. A quest that is also `hidden` stays off the list until redeemed, while its codes work: a key you do not want advertised. `GAMEND_FEATURES_WEB_REDEEM=false` closes the page.

**A key that unlocks a game mode** is a quest with no rewards. It has a progress row for a player only once they redeem, so the gate is one line in a hook:

```elixir
Gamend.Quests.get_progress(user_id, "beta_access") != nil
```

**Guests may redeem.** A signed-out visitor who submits a working code at `/redeem` gets a guest account. Because a guest's wallet moves into the account it signs in to, one person could redeem a shared code on several devices and sign each in. To stop that, refuse in the hook; `progress.code_id` says which code, and nothing is written yet:

```elixir
def before_quest_claim(user_id, %{code_only: true}, %{code_id: code_id}) do
  guest? = user_id |> Gamend.Accounts.get_user() |> Gamend.Accounts.User.anonymous?()
  shared? = Gamend.Quests.get_code(code_id).max_uses != 1

  if guest? and shared?, do: {:error, "Register to redeem this code"}, else: :ok
end

def before_quest_claim(_user_id, _quest, _progress), do: :ok
```

To stop codes: **Revoke** one, untick **Active** on the quest for all of them, or set `ends_at`. A code's metadata is copied onto each player's progress row, where they can read it, so a hook can tell which channel a redemption came from; keep private notes out of it.

## Progress is server-authoritative

Clients cannot advance their own quests, except with a code the server issued. There is no endpoint for it. Core reports login, chat_message, score_submitted, lobby_joined and match_won; your game reports the rest from hooks:

```elixir
Gamend.Quests.report_event(user_id, "enemy_killed", 1, %{"map" => "desert"})
```

Every active quest with a matching objective advances (an objective's params must all match the event meta). Rewards pay into Economy/Inventory exactly once: auto_claim quests on completion, others on claim.

## API, events, hooks

Player endpoints live under `/api/v1/me/quests` and the catalogue under
`/api/v1/quests` (gated by `GAMEND_FEATURES_LIST_QUESTS`) - see [/api/docs](/api/docs).

- **Claiming:** `POST /api/v1/me/quests/:key/claim` answers the progress and
  the rewards paid. A quest not yet completed answers `not_completed` (403), a
  second claim `already_claimed` (409), and a `before_quest_claim` veto
  `rejected` (403) with the hook's reason as `message`.
- **A finished run never expires.** A completed run waits for its claim
  whatever period it finished in: a claim pays the oldest one, and the list
  shows it until then, then the next. A daily finished on three days and never
  claimed is three claims. A `repeat` quest banks the same way: it keeps
  counting while it waits, its objective counts pass the target, and each
  target's worth is one claim.
- **Channel events:** `quest_progress`, `quest_completed`, `quest_claimed`
- **Hooks:** `before_quest_claim/3` (may veto), `after_quest_completed/1`,
  `after_quest_claimed/1`
- **Admin:** `/admin/quests` and `/api/v1/admin/quests` — CRUD plus grant,
  reset, claim and completion funnels, and `/api/v1/admin/quests/:id/codes` for
  redemption codes

Resets need no scheduled job: the current period is derived from the clock, so a new period simply starts a new progress row. Hidden quests show as "???" until earned.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Quests`](https://docs.gamend.org/Gamend.Quests.html) - the functions a plugin calls, with their
  signatures and docs.
