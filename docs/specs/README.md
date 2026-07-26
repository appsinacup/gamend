# Design specs

Per-item design specs for the planned phases in [../../ROADMAP.md](../../ROADMAP.md).
Each follows the Phase 0 house format: goal, why, concrete architecture grounded
in the existing codebase, and the full CONTRIBUTING checklist it must satisfy.

Phase 0 (background jobs, object storage) is specced inline in the ROADMAP; it
has shipped.

## Conventions

- [api-conventions.md](api-conventions.md) — **API conventions.** The
  vocabulary and shapes every schema, serializer and route follows —
  identifiers, names, time, lifecycle, the never-null policy, response shapes,
  paths. Six rules are enforced by `mix gamend.api.lint` in precommit and CI.

## Phase 1

- [push.md](push.md) — **Push: server delivery + token storage.** `push_tokens`
  table + `GameServer.Push` fan-out on the Oban `push` queue. FCM + APNs-direct
  behind one behaviour, routed per token, delivered via **Pigeon 2**.
- [push-godot-client.md](push-godot-client.md) — **Push: Godot client.** The
  client half — Android (FCM plugin) then iOS (native APNs plugin) behind one
  `GamendPush.gd` API; registers against the server's `/me/push_tokens`.
- [chat-moderation.md](chat-moderation.md) — **Chat moderation.** Word filter +
  report queue + mute, enforced in the existing `before_chat_message` pipeline.

## Phase 2

- [economy-inventory.md](economy-inventory.md) — **Economy / inventory.** Generic
  currencies, atomic wallet, append-only idempotent ledger, inventory —
  reintroduces the removed `wallet_ledger` decoupled from payments.
- [cloud-saves.md](cloud-saves.md) — **Cloud saves.** Versioned save-slots on
  Object storage with lock-free optimistic conflict detection.
- [skill-matchmaking.md](skill-matchmaking.md) — **Skill matchmaking.** Rating +
  wait-widening skill bands in the existing pure matcher, with the override hook
  intact.

## Phase 3

- [quests-progression.md](quests-progression.md) — **Quests / progression.** One
  event-driven engine; achievements fold in as permanent quests; rewards pay into
  the economy exactly-once. **Shipped July 2026.**
- [webhooks-remote-config.md](webhooks-remote-config.md) — **Webhooks + remote
  config.** Signed, retried outbound webhooks on the Oban `webhooks` queue;
  client-read-only live remote config.
- [event-tracking.md](event-tracking.md) — **Event-tracking API.** Batched,
  enriched, auto-pruned `events` capture in Postgres — the base a later
  ClickHouse/PostHog sink swaps into.

## Phase 4 — plugin-facing foundations

Seven specs from a July 2026 pass over the `gamend_polyglot` game, reading what
a real game had to build for itself because core had no primitive. Ordered by
what the rest depend on.

- [locking.md](locking.md) — **Locking that holds on SQLite too.**
  `Lock.serialize/3` is a no-op on the default adapter, so every plugin
  read-modify-write is unprotected there. Correctness, not a feature.
- [lobby-session.md](lobby-session.md) — **Lobby session.** One supervised,
  cluster-unique process per lobby that games run mutations inside; holds no
  authoritative state, owns one timer, carries a strict-mode tripwire.
- [netcode-sync.md](netcode-sync.md) — **Server time, state revision, action
  idempotency.** `server_now`, a monotonic `lobbies.revision` with optimistic
  updates, and `seq`-deduped actions. Latency compensation stays in the game.
- [disconnect-grace.md](disconnect-grace.md) — **Disconnect grace and
  state-aware reaping.** `after_user_absent/1` on a durable timer, and
  `prune_after_minutes` / `terminal` on declared lobby states finally read.
- [resource-regen.md](resource-regen.md) — **Regenerating currencies.** Lives,
  energy and stamina as a declared `%{amount, interval, cap}` on a wallet,
  folded lazily from a timestamp with no timers.
- [kv-prefix-streaming.md](kv-prefix-streaming.md) — **KV prefix queries and
  streaming.** Indexed left-anchored prefixes and a keyset cursor, replacing the
  substring filter and offset paging plugins loop over today.
- [discord-notifications.md](discord-notifications.md) — **Discord
  notifications.** One env var, Oban-delivered, rate-limit aware and redacted by
  construction — the concrete slice of the parked webhooks spec.

## Unscheduled

- [i18n.md](i18n.md) — **One place for every translatable string.** Theme
  config collapses from one JSON per locale to one config plus a `theme` PO
  domain; quest/leaderboard/tournament titles translate at render via
  `dgettext_noop` + `dgettext`, so code-defined content is translatable and
  admin-typed content degrades to its source language.
- [settings.md](settings.md) — **Settings: one declared config surface.** One
  provider macro core, hosts and plugins register into; env var names derived
  from the declaration; required/optional enforced at boot; every variable we
  own renamed onto one convention.
- [retention.md](retention.md) — **Retention for every unbounded table.**
  Extends the existing sweep to lobbies, expired tokens, resolved invites,
  stale tickets and the ledgers, batched and configurable via `RETENTION_*`.
- [lobby-state.md](lobby-state.md) — **Lobby state.** A server-owned
  `waiting/starting/playing/ended` column with legal transitions, hooks and a
  generic stale-lobby reaper; unoverloads `is_locked` and replaces the
  spoofable `metadata["game_state"]` games write today.

## Not specced (parked by the roadmap)

- **ClickHouse / PostHog analytics** ("Later") — gated behind volume; the
  event-tracking schema is kept portable so it's a sink swap. No spec until the
  capture layer proves it's needed.
- **Unity / Unreal SDKs** ("Defer") — the realtime layer is hand-written per SDK
  (the real cost); revisit on demonstrated demand.
