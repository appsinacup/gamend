# Quests / progression — generalizes achievements, pays into economy

Design spec for the Phase 3 **Quests/progression** item in
[ROADMAP.md](../../ROADMAP.md). **Depends on Economy** (rewards) and **Jobs**
(resets/timers). Completes the reward spine: economy → quests → achievements are
one design, and this is the engine the other two are special cases of.

Goal: one event-driven progression engine that covers **achievements** (permanent
one-shots), **daily/weekly quests** (repeat on a schedule), **event quests**
(time-boxed), and **chains** (prereq → next) — each able to **pay rewards into
the economy** exactly once.

## Why (achievements are 80% of a quest already)

`GameServer.Achievements` already models the hard part: a definition with a
`progress_target`, per-user progress (`increment_progress/3`), auto-unlock at the
target, and an `after_achievement_unlocked` hook. What it can't express is
everything that makes a *quest*: **multiple objectives**, **repetition on a
reset cycle**, **time windows**, **prerequisites**, and **rewards**. Rather than
grow a second half-copy of the progress machinery, quests generalize it: an
achievement becomes a quest of `reset: "never"`, `category: "achievement"` (permanent, non-repeating,
badge reward), and dailies, events and quest lines are the same engine with a
same engine.

### Decision: fold, don't fork — then remove

Achievements migrate into the quest tables as `reset: "never"`, `category: "achievement"`. Per the
project's "no backwards-compat shims" stance the fold is a full clean break
(`[breaking]` CHANGELOG): the `/achievements` API, page, admin surface,
`GameServer.Achievements` module and `after_achievement_unlocked` hook are
**removed** — `/quests` (and `GET /quests/user/:user_id` for public
completions), the `/quests` page and the quest hooks supersede them. Clients
and plugins branch on the quest's `category` where achievement-specific behavior
is wanted; completion notifications keep the "Achievement unlocked" wording
for `category: "achievement"` quests as product copy, not compatibility.

## Data model (both adapters)

- **`quests`** (definitions): `key` (unique slug), `title`, `description`,
  `icon_url`/`sort_order`/`hidden` (carried from achievements — the
  `/achievements` read view needs them),
  `reset` (`"never"|"daily"|"weekly"|"monthly"|"interval"`) +
  `reset_interval_days`, `category` (free-form UI label),
  `objectives` (jsonb list — each `{event, target, params}`),
  `rewards` (jsonb list — each `{type: "currency"|"item", code, amount}`),
  `auto_claim` (bool — grant on completion without a claim step; migrated
  achievements set it, they never had one),
  `prerequisite_quest_key` (nullable — chains),
  `starts_at`/`ends_at` (nullable — event windows), `active`, `metadata`,
  timestamps. Index `[:category]`, `[:reset]`, partial `index([:active], where: "active")`.
  **Three orthogonal dimensions**: `reset` drives period bucketing (daily →
  UTC date, weekly → ISO week, monthly → month, interval → N-day bucket,
  never → static); `starts_at`/`ends_at` make it an "event"; and
  `prerequisite_quest_key` makes it a "chain". Any combination is valid — a
  biweekly quest inside a seasonal window that also chains is just those
  fields set. `category` carries no engine behavior.
- **`quest_progress`** (per user per quest per period):
  `user_id`, `quest_key`, `period_key` (reset bucket — `"2026-07-22"` for a
  daily, `"static"` for a permanent), `objective_progress` (jsonb map,
  objective index → count), `status` (`"active"|"completed"|"claimed"`),
  `completed_at`, `claimed_at`, `rewards_granted_at`, `metadata` (preserves
  `user_achievements.metadata` through the fold), timestamps.
  `unique_index([:user_id, :quest_key, :period_key])`;
  partial `index([:user_id], where: "status = 'completed'")` for the
  "claimable" badge; partial
  `index([:claimed_at], where: "status = 'claimed' AND rewards_granted_at IS NULL")`
  for the reward-recovery sweep (below).
- **`inventory_ledger`** (new, this feature): mirror of the wallet ledger for
  item stacks — `user_id`, `item`, `delta`, `quantity_after`, `reason`,
  `idempotency_key` (unique), `metadata`, timestamps. Exists so
  `Inventory.grant_item/4` can honor `:idempotency_key` the way
  `Economy.grant/4` already does; without it item rewards cannot be
  exactly-once under retry. Also gives inventory the audit trail economy
  already has.

## Progress — event-driven dispatch (generalizes `increment_progress`)

```elixir
Quests.report_event(user_id, "enemy_killed", 1, meta)
```

- Finds the user's **active** quests whose objectives key on `"enemy_killed"`
  and advances each (creating the `quest_progress` row for the current
  `period_key` on first touch). This is the generalization of achievements'
  `increment_progress/3`.
- Definitions are read through `GameServer.Cache` (`cached/3`, with
  `invalidate/1` on every definition write) — `report_event` is a gameplay
  hot path and must not run a jsonb-containment query per event. Matching
  happens in memory against the cached active set (definitions are few;
  `max_quests` caps them).
- **Scale invariants**: an event matching no quests costs no DB work at all;
  a completed/claimed period is remembered in a cached done-marker so
  post-completion events (every earned achievement, forever) skip the
  advisory lock too — steady state is one L1 read. Prerequisite checks batch
  into one query per event. Progress ticks broadcast to the user topic only
  (never a global topic, which would scale with total event volume);
  completions/claims broadcast globally, and the admin page coalesces its
  reloads. Creating a quest never fans out writes: progress rows materialize
  per user on their first matching event, and a period roll writes nothing.
- **Server-authoritative**: there is **no** public "increment my quest"
  endpoint — a client can't advance its own quests. Core wires common events
  (score submitted, match won/`record_result`, chat sent, login) to
  `report_event`; games/plugins call it for custom events from their hooks.
- When every objective meets its target → `status: completed`. If the quest
  auto-claims, rewards grant immediately; otherwise the player claims.

## Rewards — exactly-once into Economy (the "pays into economy" part)

Claiming is gated by an **atomic status transition**: a single conditional
`UPDATE ... SET status = 'claimed' WHERE status = 'completed'` — a double-tap
or concurrent claim loses the transition and gets `{:error, :already_claimed}`.
Only the winner proceeds to grant rewards, **after** commit (never inside the
transaction or lock, per CONTRIBUTING). Each reward entry gets its **own**
idempotency key — `"quest:#{progress_id}:#{index}"` — because both ledgers
dedupe globally on the key alone, so two entries sharing one key would
silently drop the second:

```elixir
Economy.grant(user_id, "gold", 100, reason: "quest_reward", idempotency_key: "quest:#{progress_id}:0")
Inventory.grant_item(user_id, "loot_crate", 1, reason: "quest_reward", idempotency_key: "quest:#{progress_id}:1")
```

(`Inventory.grant_item/4` gains `:idempotency_key` via the new
`inventory_ledger` — see Data model.) When every entry has been applied,
`rewards_granted_at` is stamped on the progress row. If the process dies
between the claim commit and the grants, the row sits in
`claimed AND rewards_granted_at IS NULL`; a `GameServer.Schedule` sweep
re-runs the grants — the per-entry keys make the retry safe, so the pipeline
is exactly-once end to end: the status transition dedupes claims, the ledger
keys dedupe grants.

The progress increment → completion path is a read-modify-write (jsonb merge),
so it runs under a `:quest` advisory-lock namespace (next free id) keyed on
`(user_id, quest_key)`. Hooks are dispatched **after** the transaction
commits (`defer/1`), never inside the lock.

## Resets & timers — on Jobs/Schedule (Phase 0)

- **Daily/weekly**: `period_key` is **derived from UTC time** at read/write —
  `"2026-07-22"` for a daily, `"2026-W30"` for a weekly (per-game timezones
  deferred; a plugin that wants local-midnight resets can insert definitions
  with explicit windows). A new period ⇒ a new `quest_progress` row on next
  `report_event`, so reset is O(1) with no mass rewrite **and resolves
  correctly even if no job ever fires** — the `GameServer.Schedule` entry only
  prunes old periods and runs the reward-recovery sweep.
- **Event quests**: `starts_at`/`ends_at` gate eligibility; a
  `Jobs.enqueue_in/3` at `ends_at` finalizes/expires open progress.
- **Delayed grants** (e.g. "reward in 24h"): `Jobs.enqueue_hook`.

## Hooks (all six places, per CONTRIBUTING §Hooks)

- **`before_quest_claim(user_id, quest, progress)`** — pipeline veto (anti-cheat,
  eligibility). Add to `lifecycle_pipeline_hook?/2` + `normalize_pipeline_args/3`.
- **`after_quest_completed(progress)`** and **`after_quest_claimed(progress)`** —
  observe (push a notification, chain the next quest, analytics).

Each in all six places (`@callback`+`@optional_callbacks`, `internal_hooks()`,
`Hooks.Default`, SDK incl. `defoverridable`, docs). `after_achievement_unlocked`
stays as an alias fired for `reset: "never"`, `category: "achievement"` completions so existing plugins
keep working.

## Web / API

- `GET /me/quests` — active quests + progress + claimable flag (paginated).
- `POST /me/quests/:key/claim` — claim a completed quest's rewards.
- Quest **catalog** listing behind a `LIST_*_ENABLED` gate.
- `/achievements` read endpoints preserved as the `category = achievement` view.
- Event reporting: **no public endpoint** (server-authoritative).

## Limits (`GameServer.Limits`, auto `LIMIT_*`, `@limit_categories`)

`max_quests`, `max_objectives_per_quest`, `max_active_quests_per_user`,
`max_quest_reward_entries`, `max_quest_period_history`.

## Admin

- `admin_live/quests.ex` — quest definitions CRUD (objectives + rewards editor),
  per-user progress viewer with **grant/reset/force-claim** actions, completion
  funnels per quest.
- `/admin` stat card (active quests, completions today, rewards paid) + route +
  nav + `admin_pages_render_test`.
- Admin API parity for every action.

## "Update everywhere" — file list

- **README** Features: Quests/progression (mention achievements are now a quest
  category). **CHANGELOG** `[added]` Quests/progression; `[added]` inventory
  ledger + idempotent grants; `[changed]`/`[breaking]` achievements folded
  into quests.
- **.env.example** — the `LIMIT_*` caps.
- **host_public_docs/** — new Quests page (reset/window/prereq, objectives, `report_event`,
  reward/idempotency contract, resets); Server-scripting page gains the hooks;
  Data Schema gains `quests`/`quest_progress`, notes the achievements migration.
- **api_spec.ex** — feature list + quest endpoints; keep achievements entries.
- **SDK** — `Quests` stub + struct stubs; `@sdk_modules`, `gen.sdk`, placeholder
  rules; hooks mirrored (incl. the achievement alias).
- **AdvisoryLock** — `:quest` namespace documented.
- **runtime_introspection.ex** — quest stats (definitions, active, completions).
- **i18n** — 30 locales; **mix demo.seed** — a daily, a chain, and a migrated
  achievement, with some seeded progress + a claimable reward.

## Deferred / rejected

- **Visual quest-chain/DAG editor: defer.** `prerequisite_quest_key` expresses
  chains in data; a graphical editor is admin-UX polish for later.
- **Per-player dynamic/generated quests: defer.** The engine is
  definition-driven; procedural quests are a plugin that inserts definitions.
- **Leaderboard of quest completions: defer.** `after_quest_completed` can feed a
  leaderboard without core owning it.

## Definition of done (CONTRIBUTING)

- [ ] Migrations create `quests`/`quest_progress`/`inventory_ledger` and migrate
      achievement definitions/progress in; apply on SQLite **and**
      `GAMEND_DB_ADAPTER=postgres`.
- [ ] `report_event` dispatch advances objectives (definitions via
      `GameServer.Cache`); claim = atomic `completed → claimed` transition;
      rewards post-commit with **per-entry** idempotency keys through Economy
      **and** Inventory; `rewards_granted_at` + recovery sweep; UTC period
      roll on Schedule; event windows on Jobs; progress under the `:quest`
      lock, hooks deferred post-commit.
- [ ] Paginated `list_*`/`count_*`; `Limits` caps; achievements read-view intact.
- [ ] Hooks `before_quest_claim` / `after_quest_completed` / `after_quest_claimed`
      (+ achievement alias) in all six places, RPC-blocked, SDK-mirrored.
- [ ] Admin page + `/admin` card + route + nav + `admin_pages_render_test`;
      admin API parity.
- [ ] Docs, `.env.example`, CHANGELOG, README, `api_spec.ex`; i18n 30 locales.
- [ ] Tests: context + controller + admin + LiveView, both adapters; boot and
      actually complete a multi-objective quest, claim it, confirm the economy
      credit is exactly-once on double-claim, and roll a daily period.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.
