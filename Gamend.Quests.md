# `Gamend.Quests`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/quests.ex#L1)

Event-driven quest/progression engine.

One engine, three independent dimensions: a **reset** cycle (never / daily /
weekly / monthly / every N days / repeat-on-claim), an optional **window**
(`starts_at`/`ends_at`), and an optional **prerequisite**
(`prerequisite_quest_key`). Any combination works — a biweekly quest inside
a seasonal window that also requires an earlier quest is just those three
fields set. Rewards pay into `Gamend.Economy` / `Gamend.Inventory`
exactly once. `category` is a free-form label for your UI only.

## Reporting progress (server-side / hooks)

    Quests.report_event(user_id, "enemy_killed", 1, %{"map" => "desert"})

Every **active** quest with an objective on `"enemy_killed"` (whose `params`
all match the meta) advances; a quest completes when every objective meets
its target. There is deliberately **no public endpoint** for this — clients
cannot advance their own quests. Core wires common events; games call it
from their hooks for custom events.

## Claiming

    {:ok, %{progress: progress, rewards: rewards}} = Quests.claim(user_id, "daily_win_3")

Claiming is gated by an atomic `completed → claimed` status transition, so a
double-tap or a concurrent claim can't double-pay. Rewards are granted after
the transition with a per-entry idempotency key (`"quest:<progress_id>:<i>"`,
or `"quest:<progress_id>:<claim_count>:<i>"` once a `repeat` quest has been
claimed before — the row alone would dedupe its own second payout),
so a crashed or retried grant can't double-apply either; rows that claimed
but never finished granting are healed by `recover_pending_rewards/1`.
Quests with `auto_claim` grant immediately on completion (skipping the
`before_quest_claim` hook — there is no player request to veto).

## Resets

`period_key` is derived from **UTC time** by the quest's reset (daily →
`"2026-07-22"`, weekly → `"2026-W30"`, monthly → `"2026-07"`, interval →
`"I14-1436"`, never → `"static"`). A new period simply means a new progress
row on the next reported event — nothing needs to fire at midnight, and
state resolves correctly even if no job ever runs.

`repeat` is the exception: it has no clock at all. The row is re-armed the
moment its reward is paid, so the quest is available again immediately and
as often as the player can finish it — for an endless objective, a calendar
reset would cap the payout at once per period. It reuses `"static"` as its
period and counts claims on the row instead (see `claim_count`).

UTC means one global rollover instant rather than one per player: a daily
turns over at noon in New Zealand and mid-afternoon the day before on the US
west coast. That is deliberate — everyone races the same clock — but it is
why the API exposes the *remaining time* on a period and never a reset
timestamp, and why clients should show a countdown rather than an hour.

# `user_id`

```elixir
@type user_id() :: Ecto.UUID.t()
```

# `active_quests`

```elixir
@spec active_quests() :: [Gamend.Quests.Quest.t()]
```

All active quest definitions (cached — this backs event dispatch).

# `active_quests_for_event`

```elixir
@spec active_quests_for_event(String.t()) :: [Gamend.Quests.Quest.t()]
```

The active quests with an objective listening to `event`.

`report_event/4` is the hottest write a player makes, and it used to scan
every active quest to find the handful that care. That is linear in the size
of the whole catalogue, so a host that adds a large family of quests — one
per language, say — pays for all of them on every unrelated event.

Cached **per event**, not as one grouped map. Nebulex copies a value out on
read, so a single map of every event's quests would copy the entire
catalogue on every lookup, which is the cost this exists to remove. One key
per event copies only the quests that event can advance.

Both keys carry `quests_version/0`, so creating, updating or deleting a
definition drops these along with `active_quests/0`.

# `admin_claim`

```elixir
@spec admin_claim(user_id(), String.t()) ::
  {:ok, %{progress: Gamend.Quests.QuestProgress.t(), rewards: [map()]}}
  | {:error, term()}
```

Claim on a user's behalf, skipping the `before_quest_claim` veto (admin).

# `admin_complete`

```elixir
@spec admin_complete(user_id(), String.t()) ::
  {:ok, Gamend.Quests.QuestProgress.t()} | {:error, term()}
```

Force-complete a quest for a user (admin grant): every objective jumps to
its target and the normal completion side effects fire (hooks, auto-claim).

# `admin_reset`

```elixir
@spec admin_reset(user_id(), String.t()) ::
  {:ok, Gamend.Quests.QuestProgress.t() | :not_found} | {:error, term()}
```

Delete a user's current-period progress row for a quest (admin reset).

# `chain`

```elixir
@spec chain(user_id() | nil, String.t()) :: [
  %{
    quest: Gamend.Quests.Quest.t(),
    progress: Gamend.Quests.QuestProgress.t() | nil,
    claimable: boolean(),
    locked: boolean(),
    tier: pos_integer()
  }
]
```

Every quest in `quest_key`'s prerequisite chain, in tier order, each with the
user's current-period progress.

The quest list hides a tier until its prerequisite is done; this is the one
read that shows a whole chain — earlier tiers and the ones still ahead. Each
entry carries `:tier` (1-based), `:locked` (prerequisite not yet done for
this user) and the usual `:progress`/`:claimable`. With a `nil` user every
tier after the first is locked and progress is `nil`.

Returns `[]` for an unknown or inactive key. A quest with no chain links
returns just its own entry.

# `change_quest`

```elixir
@spec change_quest(Gamend.Quests.Quest.t(), map()) :: Ecto.Changeset.t()
```

Returns a changeset for tracking quest changes (used by forms).

# `claim`

```elixir
@spec claim(user_id(), String.t(), keyword()) ::
  {:ok, %{progress: Gamend.Quests.QuestProgress.t(), rewards: [map()]}}
  | {:error, term()}
```

Claim a completed quest's rewards for the current period.

Runs the `before_quest_claim` pipeline hook (veto), then transitions
`completed → claimed` atomically — only the winner grants rewards.

Returns `{:ok, %{progress: progress, rewards: rewards}}` or
`{:error, :quest_not_found | :not_completed | :already_claimed | term()}`.

# `claimable_count`

```elixir
@spec claimable_count(user_id()) :: non_neg_integer()
```

Number of completed-but-unclaimed quests for a user (badge count).

# `count_progress`

```elixir
@spec count_progress(keyword()) :: non_neg_integer()
```

Count progress rows (same filters as `list_progress/1`).

# `count_quests`

```elixir
@spec count_quests(keyword()) :: non_neg_integer()
```

Count quest definitions (same filters as `list_quests/1`).

# `count_user_completions`

```elixir
@spec count_user_completions(user_id(), keyword()) :: non_neg_integer()
```

Count of a user's completed quests (same filters as `list_user_completions/2`).

# `count_user_quests`

```elixir
@spec count_user_quests(user_id(), keyword()) :: non_neg_integer()
```

Count of quests visible to the user (same filters as `list_user_quests/2`).

# `create_quest`

```elixir
@spec create_quest(map()) :: {:ok, Gamend.Quests.Quest.t()} | {:error, term()}
```

Creates a quest definition. Capped by the `max_quests` limit.

# `dashboard_stats`

```elixir
@spec dashboard_stats() :: map()
```

Quest statistics for the admin dashboard.

# `delete_quest`

```elixir
@spec delete_quest(Gamend.Quests.Quest.t()) ::
  {:ok, Gamend.Quests.Quest.t()} | {:error, Ecto.Changeset.t()}
```

Deletes a quest definition and all related progress.

# `funnel`

```elixir
@spec funnel(String.t()) :: %{required(String.t()) =&gt; non_neg_integer()}
```

Per-status progress counts for one quest (admin completion funnel).

# `get_progress`

```elixir
@spec get_progress(user_id(), String.t()) :: Gamend.Quests.QuestProgress.t() | nil
```

Get a user's progress row for a quest's current period.

# `get_quest`

```elixir
@spec get_quest(Ecto.UUID.t()) :: Gamend.Quests.Quest.t() | nil
```

Get a quest by ID.

# `get_quest_by_key`

```elixir
@spec get_quest_by_key(String.t()) :: Gamend.Quests.Quest.t() | nil
```

Get a quest by key.

# `group`

```elixir
@spec group(user_id() | nil, String.t()) :: [
  %{
    quest: Gamend.Quests.Quest.t(),
    progress: Gamend.Quests.QuestProgress.t() | nil,
    claimable: boolean()
  }
]
```

Every member of a group, with the viewer's progress — what a UI shows when the
player opens the one entry the group collapsed into.

Ordered by `sort_order` like any list; a group has no tiers, so unlike
`chain/2` there is nothing locked and nothing to number. Members the quest
list would not show this viewer (out of window, prerequisite unmet) are left
out too, so the count on the collapsed entry matches what opening it reveals.

Returns `[]` for a group key nothing carries.

# `groups`

```elixir
@spec groups(user_id() | nil, String.t() | nil) :: [
  %{key: String.t(), title: String.t()}
]
```

The groups this viewer's quests fall into, as `%{key, title}` in the order
the list would show them — what a group selector offers. `title` is the
stored `group_title` (the first member's when they disagree), untranslated,
like every other stored string here. `category` narrows it the way the list
filter does; `nil` is the signed-out catalog.

# `host_lock_label`

```elixir
@spec host_lock_label(Gamend.Quests.Quest.t(), user_id() | nil) :: String.t() | nil
```

Why this viewer cannot claim this quest yet, as a short label to draw — or
`nil` when they can. Set `config :gamend_core, :quest_lock_filter,
{Module, :function}`; it is called as `function(user_id | nil, Quest.t())`.

The display counterpart of `before_quest_claim`. A quest can be worth showing
and still not claimable — a premium tier a player has not bought is an offer,
and hiding it means only the people who already took the offer ever see it.
`host_visible/2` cannot express that: it keeps a quest or drops it, and
`hidden` is a column, the same for everyone, that draws "???" over the very
title the offer is made of.

A label here changes nothing about what pays: the veto in `before_quest_claim`
is still the authority, and a lock filter that disagrees with it only makes
the page lie. Return the reason from the same condition the veto tests.

# `host_visible`

```elixir
@spec host_visible([Gamend.Quests.Quest.t()], user_id() | nil) :: [
  Gamend.Quests.Quest.t()
]
```

The host's say on which quest definitions one viewer may see at all — a
premium-only daily, a quest for a country the player has not unlocked. Set
`config :gamend_core, :quest_visibility_filter, {Module, :function}`; it is
called as `function(user_id | nil, [Quest.t()])` and returns the quests to
keep. Applied to every per-user listing (`list_user_quests/2`,
`count_user_quests/2`, `visible_categories/1`) and to the signed-out catalog
with `nil`. Progress is NOT filtered: an event still advances a quest the
viewer cannot see, so a player who gains access later finds it where they
left it; veto the claim in `before_quest_claim` if that must not pay.

# `list_progress`

```elixir
@spec list_progress(keyword()) :: [Gamend.Quests.QuestProgress.t()]
```

Lists progress rows (admin viewer).

## Options
- `:user_id` — exact UUID or username/display-name substring
- `:quest_key`, `:status`
- `:page` / `:page_size`

# `list_quests`

```elixir
@spec list_quests(keyword()) :: [Gamend.Quests.Quest.t()]
```

Lists quest definitions (admin view — no per-user state).

## Options
- `:category` — filter by category
- `:active` — filter by active flag
- `:search` — substring match on key/title
- `:page` / `:page_size`

# `list_user_completions`

```elixir
@spec list_user_completions(user_id(), keyword()) :: [
  %{quest: Gamend.Quests.Quest.t(), progress: Gamend.Quests.QuestProgress.t()}
]
```

A user's completed quests, newest first — the public-profile view
("their achievements"). Hidden quests appear once earned.

## Options
- `:category` — filter by category (a profile typically wants `"achievement"`)
- `:page` / `:page_size`

# `list_user_quests`

```elixir
@spec list_user_quests(user_id(), keyword()) :: [
  %{
    quest: Gamend.Quests.Quest.t(),
    progress: Gamend.Quests.QuestProgress.t() | nil,
    claimable: boolean()
  }
]
```

Lists quests as seen by one user: active definitions in-window with the
user's current-period progress and a claimable flag.

Hidden quests are listed but carry no details until earned (callers obscure
them). Chain quests only appear once their prerequisite is met. Grouped
quests collapse to one entry carrying `:group_size` and `collapsed: true`;
the members of a group listed in full carry the size alone.

## Options
- `:category` — filter by category
- `:group` — expand this one group's members; every other group stays
  collapsed
- `:drop_groups` — group keys to leave out entirely, collapsed or not: what
  a page with a selector over some groups does with the ones not picked
- `:status` — `"in_progress"` (not yet completed), `"claimable"`
  (completed, waiting to be claimed) or `"done"` (completed or claimed)
- `:page` / `:page_size`

# `period_key`

```elixir
@spec period_key(Gamend.Quests.Quest.t() | String.t(), DateTime.t()) :: String.t()
```

The reset bucket a quest is in at `now` (UTC).

`"static"` when it never resets, else the current day (`"2026-07-22"`),
ISO week (`"2026-W30"`), month (`"2026-07"`), or interval bucket
(`"I14-1436"` — the 1436th 14-day window since the epoch). Derived purely
from the clock, so a reset needs nothing to fire at midnight.

# `prerequisite_met?`

```elixir
@spec prerequisite_met?(user_id(), Gamend.Quests.Quest.t()) :: boolean()
```

True when the quest's prerequisite (if any) is completed by the user.

# `prune_old_periods`

```elixir
@spec prune_old_periods() :: non_neg_integer()
```

Deletes daily/weekly progress rows whose period ended more than
`max_quest_period_history` days ago (called from `Gamend.Retention`).

# `rearm_repeat_quests`

```elixir
@spec rearm_repeat_quests(keyword()) :: non_neg_integer()
```

Re-open `repeat` quests whose reward was paid but which never re-armed.

Only reachable by crashing between the grant and the re-arm. Healing on read
keeps that window from stranding a player on a quest that will never come
back, without a job that has to be running for the feature to work.

# `recover_pending_rewards`

```elixir
@spec recover_pending_rewards(keyword()) :: non_neg_integer()
```

Re-runs reward grants for rows that claimed but never finished granting
(e.g. the process died mid-grant). Safe to run anywhere, any time — the
per-entry idempotency keys dedupe. Pass `:user_id` to heal one user (done
lazily when they list their quests). Returns the number of rows retried.

# `render_counter`

```elixir
@spec render_counter(Gamend.Quests.Quest.t()) :: Gamend.Quests.Quest.t()
```

The quest with `%{n}` replaced by its resolved counter, untranslated.

For consumers that emit the stored string as-is. Anything that translates
interpolates through Gettext instead, so the placeholder survives long
enough to be looked up. An unresolved counter reads as run 1 — an anonymous
visitor browsing the catalog is looking at the run they would start.

# `report_event`

```elixir
@spec report_event(user_id(), String.t(), pos_integer(), map()) ::
  {:ok, [Gamend.Quests.QuestProgress.t()]}
```

Report a gameplay event for a user, advancing every matching active quest.

`meta` narrows objective matching: an objective with `params` only advances
when every param key/value is present in `meta`.

Returns `{:ok, progress_rows}` for the quests that advanced.

# `resolve_counter`

```elixir
@spec resolve_counter(Gamend.Quests.Quest.t(), Gamend.Quests.QuestProgress.t() | nil) ::
  Gamend.Quests.Quest.t()
```

Works out which run of a `repeat` quest a player is on, into `:counter`.

A repeat quest is one definition and one row that re-arms forever, so it has
no natural way to say *which* run the player is on — the card reads the same
the tenth time as the first. `"Treasures x %{n}"` renders "Treasures x 1"
before the first claim and "Treasures x 2" after it.

Resolved here, at the point a definition is paired with a player's row,
because the definition is global and the count is not: writing the number
into the stored title would show every player the same one.

The number lands on the virtual `:counter` field and `%{n}` stays in the
title, because the title is also a **msgid**: `GamendWeb.ContentText` looks
the translation up by it and hands `n` to Gettext as a binding, so a German
card reads "Schätze x 3" instead of falling back to English. Filling it in
here would leave "Treasures x 3", which matches no msgid in any locale.
Callers that render the title without translating it — the JSON API — call
`render_counter/1` to collapse the placeholder.

Non-repeat quests and titles without the placeholder pass through untouched,
so this is invisible to everything that does not opt in.

# `stats`

```elixir
@spec stats() :: %{
  quests_total: non_neg_integer(),
  completed: non_neg_integer(),
  claimed: non_neg_integer()
}
```

Aggregate quest progress counts for the public stats endpoint.

Grouped by status in one query — `quest_progress` carries a partial index on
completed rows, and the group-by reads the same rows the listing already does.

# `subscribe_quests`

```elixir
@spec subscribe_quests() :: :ok | {:error, term()}
```

Subscribe to global quest events (definition changes, completions).

# `update_quest`

```elixir
@spec update_quest(Gamend.Quests.Quest.t(), map()) ::
  {:ok, Gamend.Quests.Quest.t()} | {:error, Ecto.Changeset.t()}
```

Updates a quest definition.

# `visible_categories`

```elixir
@spec visible_categories(user_id() | nil) :: [String.t()]
```

The categories that actually have something behind them for this viewer.

Derived from the same visibility rule as `list_user_quests/2` rather than
from every definition: a chain's later tiers are hidden until unlocked, so
listing their category gives a tab that opens onto nothing. Pass `nil` for
the signed-out catalog.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
