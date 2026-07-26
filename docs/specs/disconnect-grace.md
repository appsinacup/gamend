# Disconnect grace and state-aware reaping

Goal: core knows when a player has been gone long enough to matter, tells the
game once, and reaps a lobby on a schedule that depends on what the lobby was
doing — so no game has to run its own cleanup loop.

Two halves of one problem: **when is a player really gone**, and **when is a
lobby really dead**.

## Why core

`after_user_offline/1` fires the instant a socket closes. That is not the same
question a game needs answered — *"is this player coming back?"* — so every game
schedules its own delay and answers it privately.

Polyglot answers it twice, both times in ways core forbids elsewhere:

- `user_offline.ex` — `Task.start` + `Process.sleep(15 min)` + a
  `:persistent_term` dedupe key, to disband a party whose members all went
  offline. Unsupervised, lost on restart and on deploy, and its own
  `PLAN_TIMERS.MD` (in the `gamend_polyglot` repo) lists it as "keep: no
  in current form".
- `lobby_cleanup.ex` — 318 lines running a recursive `Task.start` loop every two
  minutes with three different max-ages: a paused game kept while any member is
  online and deleted 15 minutes after all are offline, an active game reaped
  after 5 minutes of silence, an ended one after 60 seconds. Also unsupervised.

The second half is a gap core left open on purpose. `Lobbies.States` is
**documentation, not an enum** — core accepts any state word and attaches no
meaning to any of it, on the stated principle that it cannot know when a match
starts or ends. Retention therefore has exactly one knob,
`GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES`, applied to every lobby regardless of
what it is doing. So a finished scoreboard and a paused 40-minute raid are
reaped on the same clock, and a game that wants otherwise writes a cleanup loop.
The fix must give the *deployment* and the *game* a say without core pretending
to understand the words.

## Half 1 — grace

When a user's last socket closes, core already records `is_online` and
`last_seen_at`. Add one durable timer:

- On disconnect, enqueue an Oban job at `now + grace_seconds` (default 120),
  unique per user so reconnect churn does not pile up jobs.
- On reconnect, cancel it (or let it run and no-op — the job re-checks
  `is_online` before acting, so cancellation is an optimization, not a
  correctness requirement).
- If the user is still offline when it runs, fire **`after_user_absent(user)`**
  and apply core's own absence handling.

`after_user_absent/1` is the hook games actually wanted: *this player is not
coming back right now*. Pause the match, substitute a bot, release their
matchmaking ticket, disband the party. `after_user_offline/1` keeps its current
meaning (the socket closed — useful for presence UI) and is unchanged.

Core's own absence handling is one settings provider — group `:presence`, so
every env name below is derived, per `GameServer.Settings.Provider` — all opt-in,
all defaulting to today's behaviour:

```elixir
defmodule GameServer.Presence do
  use GameServer.Settings.Provider, app: :game_server_core, group: :presence

  setting :grace_seconds, :integer, default: 120
  setting :absent_leave_party, :boolean, default: false
  setting :absent_cancel_matchmaking, :boolean, default: true
  setting :absent_leave_lobby, :boolean, default: false
end
```

| Setting | Env | Effect when the grace expires |
| --- | --- | --- |
| `grace_seconds` | `GAMEND_PRESENCE_GRACE_SECONDS` | when `after_user_absent` fires |
| `absent_leave_party` | `GAMEND_PRESENCE_ABSENT_LEAVE_PARTY` | remove the user from their party |
| `absent_cancel_matchmaking` | `GAMEND_PRESENCE_ABSENT_CANCEL_MATCHMAKING` | cancel their queued ticket (today: 5-minute prune) |
| `absent_leave_lobby` | `GAMEND_PRESENCE_ABSENT_LEAVE_LOBBY` | clear `users.lobby_id` |

Disbanding a *whole* party whose members have all gone is **not** here — it
belongs to retention. See below.

`absent_leave_lobby` defaults **false** deliberately: disconnecting must not
mean forfeiting a match, and the abandoned-lobby reaper below already handles
the case where nobody comes back. The party disband is the one polyglot needed,
now durable and supervised.

## Half 1b — abandoned parties belong to retention, not to the grace job

An abandoned party is the *same shape* as an abandoned lobby, so it gets the
same treatment and the same code path — not a per-user timer.

Today nothing ever removes one. A party disbands when its **leader** leaves, and
disconnecting does not clear `users.party_id`, so four players who close the
game leave a party that lives forever. It still holds all four members (a user
is in at most one party, so it blocks the next one), still shows in party lists,
and still receives invites.

Retention gets one more rule, next to `prune_lobbies/0`:

```elixir
setting :abandoned_party_minutes, :integer, default: 15
```

→ `GAMEND_RETENTION_ABANDONED_PARTY_MINUTES`; `0` keeps them forever. The query
is the lobby query with one column changed — no member online, none seen inside
the window, party row untouched — because "silence, not emptiness" is the same
rule for the same reason.

**Why retention and not `after_user_absent/1`:**

- **Self-healing.** The sweep re-derives the answer from the database every
  tick. A disconnect-time job that was never enqueued (node died, deploy
  mid-window) is simply lost, and the party lives forever again — the exact
  failure polyglot's `:persistent_term` dedupe has today.
- **It catches the backlog.** A sweep disbands parties abandoned *before* the
  feature shipped. A reactive job only ever sees disconnects that happen after
  it exists.
- **Precision is worthless here.** Nobody is watching a party get collected. The
  grace job exists for things a player feels — pausing a match, releasing a
  ticket — and those are per-user and want the exact boundary.
- **No job churn.** Four members going offline is four unique jobs to enqueue
  and cancel, for one row that one query already finds.

The division that falls out: **`after_user_absent/1` is per-user, precise and
reactive; retention is per-entity, periodic and self-healing.** "Remove *this
player* from their party" is the first; "this whole party is residue" is the
second.

**It must go through the lifecycle op, not a bulk delete.** Retention calls
`Parties.disband_party/1` per row (as `reap_lobby/1` already does for lobbies),
so `party_id` is cleared on members, pending invites are cancelled, caches are
invalidated, `party_disbanded` is broadcast and `after_party_disband` fires. A
`Repo.delete_all` would leave every member pointing at a party that no longer
exists.

Two things to fix on the way, both pre-existing:

- **`disband_party/1` is private.** Only `leave_party/1` (leader leaves) reaches
  it. Make it public — or add `reap_party/1` beside it — so retention is not
  tempted into a raw delete.
- **`admin_delete_party/1` does not fire `after_party_disband`.** It clears
  members, cancels invites and broadcasts, but skips the hook, so a plugin
  tracking party lifecycle silently misses every admin deletion — and every
  deletion polyglot's own 15-minute task performs, since that task calls
  `admin_delete_party/1`. Route it through the same disband path.

Note the asymmetry with lobbies while deciding: a lobby reap runs
`before_lobby_delete`, so a game **can veto** it (and a buggy veto makes lobbies
immortal). Parties have no `before_party_disband`, so a party reap cannot be
vetoed. Leave it that way unless a game asks — one fewer way to defeat the
sweep — but say so in the docs rather than letting it be discovered.

**On the default.** 15 minutes, the same as `abandoned_lobby_minutes` — the two
answer the same question ("has everyone gone?") and there is no reason for a
player to learn two numbers. A game that wants its parties to survive overnight
raises it; `0` keeps them forever. This also means `retention.md`'s
"deliberately not given retention: … `parties` …" line stops being true, and is
amended there.

## Half 2 — per-state reaping without core learning the states

Core will not gain a state vocabulary — `Lobbies.States` says a state is a word
and core attaches no meaning to it, and that decision stands. Two additions
respect it, because in both of them the meaning is supplied from outside.

**1. A setting the deployment owns.** One new key on the existing
`GameServer.Retention` provider:

```elixir
setting :lobby_state_minutes, :list,
  default: [],
  doc: ~s(Per-state override, e.g. "ended:5,playing:180". Unlisted states use abandoned_lobby_minutes.)
```

→ `GAMEND_RETENTION_LOBBY_STATE_MINUTES="ended:5,playing:180"`. Core still knows
nothing about `"ended"`; the operator does, and says so. Empty by default, so an
existing deployment reaps exactly as it does today.

**2. A hook the game owns**, for anything a static table cannot express (a
tournament lobby that must outlive its bracket, a paused match kept while the
party is intact):

```elixir
@callback lobby_prune_minutes(Lobby.t()) :: non_neg_integer() | :default | :never
```

Optional, defaults to `:default`. `:never` exempts a lobby entirely — the escape
hatch that makes it safe to shorten the global window.

**How the sweep stays one query.** Retention selects candidates with the
*shortest* window in play (`min(abandoned_lobby_minutes, configured overrides)`),
then filters the candidates in Elixir: each one's effective window is the hook's
answer, else the state override, else the global default. The candidate set is
bounded by "quiet for at least the shortest window", so the hook is called for a
handful of rows per sweep, not for the table.

Everything that makes the existing sweep safe is unchanged:

- **Silence, not emptiness.** A lobby is reaped only when no member is online
  *and* none has been seen inside the window *and* the lobby row has not been
  touched. Disconnecting does not clear `users.lobby_id`, so "no members" is
  never the signal.
- **Being over is still not, by itself, a reason to delete.** A short window for
  `"ended"` is the operator or the game saying so — not core inferring it from a
  word.

**How this differs from the variant [retention.md](retention.md) rejects.** That
one gave *core* the semantics: a declared `terminal: true` meaning "delete this
sooner", which core would then act on. Dropped for good reasons — a game that
ends a match can call `delete_lobby/1` itself, so the rule only ever made
reaping sooner, and the presence condition applied regardless.

Both reasons survive here, and neither covers the case this section is for:
lobbies **nobody ever ends**. Polyglot's three windows are a paused game (kept
while any member is online), a never-started lobby (10 min) and an active one
(5 min) — no explicit end event exists in any of them, so "the game deletes its
own lobby" has nothing to hang on. The value is a *shorter* window for junk that
would otherwise sit for the global 15 minutes, and the meaning still comes from
outside core.

If that case does not feel worth a setting plus a hook, the honest reduction is
to keep only the hook (`lobby_prune_minutes/1`) and drop the parsed setting —
the hook alone covers every game-specific window, and the operator-facing table
is the part that mostly duplicates it.

Deliberately **not** included: rejecting transitions out of a "terminal" state.
That is vocabulary enforcement, which `Lobbies.States` already tells games to do
in `before_lobby_state_change`, and core adding a second opinion there would
undo the decision this spec is built on.

## Interaction with lobby sessions

A [lobby session](lobby-session.md) stops on lobby delete, so reaping a lobby
tears down its session. The reverse is not true — a session idling out does not
mean the lobby is dead, since state lives in the database. Retention is the only
thing that deletes lobbies, before and after this spec.

## What core still does not do

- **No auto-kick, no forfeit, no rating penalty.** Core records absence; the
  game decides what it costs. Same division as ready checks (core records who
  stalled, the host decides) and lobby states (core stores the word, the game
  gives it meaning).
- **No reconnect token, no session resume.** Reconnecting is already just
  authenticating again; the grace window is about *state*, not identity.
- **No presence heartbeat protocol.** `is_online` + `last_seen_at` and socket
  lifecycle are what core has; this spec adds a delay on top, not a new
  transport-level mechanism.

## Alternatives considered

- **A supervised sweeper GenServer scanning for absent users** instead of a job
  per disconnect. Simpler in one way (no job churn), worse in another: the
  grace becomes a poll interval, so a 120 s grace fires anywhere between 120 s
  and 120 s + interval, and every game that wants a precise pause point is back
  to guessing. `Accounts.StalePresenceSweeper` already exists as the backstop
  for jobs that were lost, which is the right division: precise jobs, plus a
  sweep that catches what fell through.
- **Firing `after_user_absent` from `StalePresenceSweeper` only.** Same
  imprecision, and the sweeper's job is fixing stale `is_online` flags after a
  node dies — a different concern that should not grow game semantics.
- **Per-lobby grace instead of per-user.** A player is in at most one lobby, so
  per-user is the same thing with fewer rows and it also covers party and
  matchmaking, which have no lobby.
- **Party disband on the grace job** (polyglot's shape, promoted). Rejected for
  the four reasons in Half 1b — chiefly that a lost job means the party lives
  forever, which is the bug being fixed.
- **Letting games keep their own loops.** They do today, unsupervised, and both
  polyglot instances are on its own removal list.

## Definition of done (CONTRIBUTING)

- [ ] Disconnect enqueues a unique Oban job at the grace deadline; reconnect
      cancels it; the job re-checks `is_online` and no-ops if the user returned.
- [ ] `after_user_absent/1` hook in all six places, RPC-blocked, SDK-mirrored;
      `after_user_offline/1` unchanged in meaning and timing.
- [ ] Absence settings applied per the table, all defaulting to today's
      behaviour except matchmaking cancellation, which replaces the 5-minute
      prune and is called out in the CHANGELOG.
- [ ] `Lobbies.States` gains no enum and no meaning; the per-state window comes
      from the `retention.lobby_state_minutes` setting and the optional
      `lobby_prune_minutes/1` hook only.
- [ ] Retention's candidate query uses the shortest window in play, then filters
      per candidate (hook → state override → global); falls back to
      `GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES`; `:never` exempts a lobby; the
      silence rule holds — a lobby with any member seen inside the window is
      never reaped, whatever its state (test).
- [ ] Abandoned parties reaped by retention on the same silence rule, through
      `Parties.disband_party/1` (members cleared, invites cancelled, caches
      invalidated, `party_disbanded` broadcast, `after_party_disband` fired) —
      never a bulk delete; `GAMEND_RETENTION_ABANDONED_PARTY_MINUTES=0` disables.
- [ ] `retention.md`'s "not given retention" list amended: `parties` moves out
      of it, with the silence rule stated alongside lobbies.
- [ ] Settings declared with `GameServer.Settings.Provider` (group `:presence`,
      plus the two new retention keys), so env names derive; `.env.example`
      regenerated with `mix gamend.settings.env_example`; admin Settings page
      renders them.
- [ ] Tests on both adapters: reconnect inside the grace fires nothing;
      staying away fires exactly once; a restart between disconnect and deadline
      still fires (durability); per-state reaping picks the right window; an
      `ended` lobby with an online member is not reaped early; a party with one
      member seen inside the window survives, and a fully silent one disbands
      with every member's `party_id` cleared.
- [ ] Admin: presence card shows users inside the grace window; lobby list shows
      each lobby's effective prune window; API parity.
- [ ] Docs (Lobbies, Parties, Retention pages), `api_spec.ex`, CHANGELOG, i18n.
- [ ] Polyglot deletes `lobby_cleanup.ex` and the party-disband task in favour
      of declarations plus `after_user_absent/1` (tracked in that repo).
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin warning-free.
