# Skill matchmaking — rating + widening bands + hook override

Design spec for the Phase 2 **Skill matchmaking** item in
[ROADMAP.md](../../ROADMAP.md). Extends the existing `GameServer.Matchmaking`
(matcher) — it does **not** replace it.

Goal: match players of **similar skill**, while **widening** the acceptable
skill gap the longer someone waits so no one is stuck in queue — and keep the
whole thing overridable by a game that wants its own logic.

## Why (matching today is skill-blind)

`GameServer.Matchmaking` is ticket-based: `join/4` writes a ticket with a
`match_params` map, the periodic `Matchmaking.Worker` sweeps queued tickets that
share **identical** `match_params`, and the pure `Matchmaking.Matcher.form_matches/2`
packs whole party-groups FIFO until a bucket hits `min/max_players` or the oldest
group passes `timeout_ms`. It already respects blocked pairs and parties. The one
thing it ignores is **skill** — a bronze and a grandmaster with the same
`match_params` get packed together purely by wait order. This item adds a rating
and a skill-band constraint to the packing step, and reuses the two extension
points the matcher already exposes.

## The two existing seams we build on

1. **`before_matchmaking_join`** — the server's authority over the queue; it can
   rewrite `match_params`. Skill MM uses it to **stamp the ticket's rating**
   (server-side, from the rating store) so a client can't inflate its own skill.
2. **`matchmaking_form_matches`** — already lets a plugin *replace* the built-in
   matcher for one bucket. Skill matching becomes the **default** behaviour of
   the core matcher; this hook remains the full-override escape hatch.

So the surface stays: skill MM is a smarter default `form_matches`, gated on, and
still fully replaceable.

## Rating store

- **`player_ratings`** table: `user_id`, `mode` (rating pool key — derived from
  `match_params["mode"]`, so a game rates deathmatch separately from ranked),
  `rating` (integer, e.g. Glicko-2 μ scaled), `deviation` (RD — uncertainty),
  `games_played`, `updated_at`. `unique_index([:user_id, :mode])`;
  `index([:mode, :rating])` for distribution/admin queries.
- **Algorithm** lives in `GameServer.Matchmaking.Rating` (default **Glicko-2** —
  its rating *deviation* naturally seeds the starting band width and grows with
  inactivity, which Elo can't express). A new/unrated player starts at a
  configured default rating with a high deviation. The module is small and
  swappable; the store is algorithm-agnostic (μ + RD covers Elo too, RD unused).

## Widening bands — the core change

The ticket gains a typed `rating` column (migration adds `rating :integer`,
nullable; null ⇒ unrated ⇒ current FIFO-only behaviour, so existing games are
unaffected until they opt in). `Matcher.form_matches/2` becomes skill-aware:

- Two groups may share a match only if their ratings fall within an **acceptance
  band** that grows with the *oldest* group's wait:

  ```
  band(waited_s) = min(max_band, base_band + growth_per_sec * waited_s)
  ```

- Packing still runs oldest-group-first (FIFO fairness), but a candidate is
  skipped if it falls outside the current group's band; by `timeout_ms` the band
  has widened to `max_band` (or effectively ∞), so the existing timeout guarantee
  — "the oldest group always gets seated by its deadline" — is preserved.
- Parties keep their indivisibility; a party's group rating is its members'
  average (configurable to max, to stop smurf-carrying).

The band params are config (per-mode overridable): `mm_base_band`,
`mm_band_growth_per_sec`, `mm_max_band`, plus a `skill_matchmaking_enabled`
toggle. The matcher stays a **pure function** (bands + now passed in), so it
remains unit-testable exactly as today.

## Feeding results back

Ratings only mean something if match outcomes update them:

```elixir
Matchmaking.record_result(match_id, %{winners: [...], losers: [...]}, opts)
```

- Updates each participant's `player_ratings` row via `Rating.update/…` inside a
  `GameServer.Lock.serialize(:rating, user_id_or_mode, …)` (read-modify-write —
  next free advisory-lock namespace after `matchmaking_sweep: 8`).
- The sweep itself already serializes cluster-wide under `:matchmaking_sweep`, so
  the *matching* side needs no new lock; only result-recording does.
- Result reporting is **server-authoritative** — no public endpoint; a game
  reports via this function from its match-end hook (or the tournament resolve
  path can call it).

## Hooks (per CONTRIBUTING §Hooks)

- Reuse **`before_matchmaking_join`** (stamp rating) and
  **`matchmaking_form_matches`** (full override) — already wired.
- Add **`after_rating_updated(user_id, mode, rating, deviation)`** — observe
  (leaderboards of rating, achievements). Six places: `@callback` +
  `@optional_callbacks`, `internal_hooks()`, `Hooks.Default` no-op, SDK mirror
  (incl. `defoverridable`), Server-scripting docs. Deferred after the rating
  transaction commits.

## Limits / config

`mm_base_band`, `mm_band_growth_per_sec`, `mm_max_band`, `mm_default_rating`,
`mm_default_deviation` in `GameServer.Limits`/config (auto `LIMIT_*` where they're
caps), `@limit_categories`. `skill_matchmaking_enabled` toggle.

## Web / API

- No new **public** mutation surface — joining is the existing `join/4`; rating is
  server-stamped; results are hook/authoritative.
- Read: `GET /me/rating?mode=…` (own rating), and a per-mode **rating
  leaderboard** listing behind a `LIST_*_ENABLED` gate (reuses the leaderboards
  LiveView layout, CONTRIBUTING §Web).

## Admin

- `admin_live/matchmaking_ratings.ex` — per-mode rating distribution, search a
  user, **manual adjust** (writes through `Rating` so `games_played`/history stay
  coherent), and queue-health (avg wait, current band widths, unmatched tickets).
- `/admin` stat card (rated players per mode, median wait) + route + nav +
  `admin_pages_render_test`.
- Admin API parity (read ratings, adjust, queue health).

## "Update everywhere" — file list

- **README** Features: skill matchmaking. **CHANGELOG** `[added]` Skill-based
  matchmaking (rating + widening bands).
- **.env.example** — band/rating config vars.
- **host_public_docs/** — Matchmaking docs page gains a Skill section (rating,
  bands, `record_result`, the override hook); Data Schema gains `player_ratings`
  + the ticket `rating` column.
- **api_spec.ex** — feature list + `GET /me/rating` + rating leaderboard.
- **SDK** — rating read stubs + struct; hooks mirrored; `gen.sdk`.
- **runtime_introspection.ex** — MM section already exists (repoint if needed);
  add rating counts + band config snapshot.
- **AdvisoryLock** — document the new `:rating` namespace.
- **i18n** — 30 locales; **mix demo.seed** — seed a rating distribution across a
  mode so the admin page + leaderboard show a curve.

## Deferred / rejected

- **Team-balancing / role queues: defer.** v1 seats by aggregate group rating;
  fair-team-split within a match and role constraints are a follow-up on top of
  the rating store.
- **Cross-mode unified rating: rejected.** Ratings are per `mode` on purpose —
  skill in deathmatch says little about ranked 1v1.
- **Exposing rating writes to clients: rejected.** Rating is server-authoritative
  end-to-end; a client that could set its own rating breaks matchmaking.

## Definition of done (CONTRIBUTING)

- [ ] Migration adds `matchmaking_tickets.rating` + creates `player_ratings`,
      applies on SQLite **and** `GAMEND_DB_ADAPTER=postgres`; indexes as above.
- [ ] `Matcher.form_matches/2` skill-aware (bands passed in, stays pure);
      timeout guarantee preserved; parties still indivisible; unrated ⇒ legacy
      FIFO.
- [ ] `record_result/3` updates ratings under a `:rating` lock; sweep still under
      `:matchmaking_sweep`.
- [ ] Hooks: `before_matchmaking_join` stamps rating, `matchmaking_form_matches`
      overrides, `after_rating_updated` added in all six places, RPC-blocked,
      SDK-mirrored.
- [ ] Admin page + `/admin` card + route + nav + `admin_pages_render_test`;
      admin API parity; rating read endpoint + leaderboard.
- [ ] Docs, `.env.example`, CHANGELOG, README, `api_spec.ex`; i18n 30 locales.
- [ ] Tests: pure matcher band tests (tight early, wide near timeout, timeout
      still seats); context/rating update tests; controller + admin + LiveView;
      both adapters; boot and actually queue mixed-rating players and confirm
      skill-sorted matches that still resolve by timeout.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.
