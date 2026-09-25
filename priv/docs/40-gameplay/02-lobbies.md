---
icon: hero-home-modern
---

# Lobbies

A lobby is the room a match happens in: a short-lived record holding a title, a capacity, visibility flags and free-form metadata. Membership is a single column - `users.lobby_id` - so a player is in at most one lobby, and joining runs as one transaction under a per-lobby lock: capacity, blocks, the game's hook and the password are all checked before anyone is seated.

## Creating and joining

POST /lobbies creates a lobby with the caller as host and first member; POST /lobbies/:id/join seats them in an existing one. The join transaction checks, in order: not already in a lobby, not locked, not hidden, seats free, no block between the joiner and anyone already seated (403 blocked - see [/docs/friends](/docs/friends)), the game's before_lobby_join hook, then the password.

| Setting | Effect |
|---|---|
| `is_hidden` | Out of GET /lobbies and the lobby-list feed. Members and the pinned WebRTC host still see it; to everyone else GET /lobbies/:id answers 404, not 403 - a 403 would confirm the lobby exists. Joining one by id is refused too (403 `cannot_join`): a hidden lobby is invite-only, and server-side code may pass `bypass_hidden` to seat a player in it. |
| `is_locked` | Nobody can join, and the lobby cannot be spectated. Server-side code may pass `bypass_lock`; no player-facing surface does. |
| `password` | Stored as an Argon2id hash, like account passwords (older bcrypt hashes still verify); join must carry the password. Quick join never considers passworded lobbies. |
| `max_users` | Seat cap (default 8), enforced under the lobby's advisory lock. Shrinking it below the current member count is refused with `too_small`. |

POST /lobbies/quick_join finds a room instead of asking the player to pick one: it tries the oldest visible, unlocked, passwordless candidates whose max_users and metadata match the request, skips any that are full or that the game's before_lobby_join hook rejects, and creates a fresh lobby with the caller as host when none will take them.

All three endpoints are party-aware: a party leader calling them brings the whole party in atomically, and a non-leader party member gets 403 in_party - see [/docs/parties](/docs/parties).

## Host and membership lifecycle

```text
create  ──► caller becomes host and first member
join    ──► user_joined on the lobby channel
leave   ──► a leaving host hands the lobby to the longest-present
            member (host_changed); the last member out deletes it
kick    ──► host removes a member (never themselves); the target
            is notified with a lobby_kicked notification
disband ──► host deletes the lobby outright; every member is detached
```

Authority over a lobby - editing it, moving its state, kicking, disbanding, opening ready checks, moderating its chat - belongs to the host of a host-managed lobby, or to the pinned WebRTC host the game designates through `Gamend.Signaling.configure/2`. A hostless lobby with no pinned host belongs to the server, and no member may manage it.

## The `state` field

`state` is the lobby's lifecycle word: `created` on creation, then whatever the game says. Core does not model a state machine - it documents `created`, `starting`, `playing` and `ended`, but accepts any non-empty string up to 64 bytes, and any state may follow any other. A game that wants a vocabulary or an ordering enforces both in its before_lobby_state_change hook.

POST /lobbies/state moves it, gated by the same authority rule as editing. The column is not castable, so PATCH /lobbies can never change state, and a same-state call is a no-op that re-fires no hooks. Hostless matchmaking lobbies are moved from server-side hooks with `Gamend.Lobbies.transition_state/3` instead. Every move lands on the lobby channel as `state_changed` with `{lobby_id, from, to, state_changed_at}`.

Reaching `ended` deletes nothing: a game that finishes a match deletes the lobby itself, or leaves it to the abandoned-lobby sweep below.

## Spectators

A non-member can watch a public lobby - not hidden, not locked - by joining its `lobby:{lobby_id}` channel. Spectators receive every event members do (membership, updates, state changes, chat) but can write nothing, and a player seated in a *different* lobby cannot spectate at all (`must_spectate_own_lobby`). Spectator presence follows the channel process and is counted cluster-wide, so the `spectator_count` on GET /lobbies/:id survives disconnects and node failures with no cleanup path to forget.

## Matchmaking lobbies

The matcher creates its lobbies itself: hidden, hostless, sized to the match, seated one join at a time, then locked - so a matchmade room never appears in the public list and never gains a player host. If any winner cannot be seated, the half-built lobby is deleted and the remaining tickets requeue. See [/docs/matchmaking](/docs/matchmaking).

When a lobby is deleted or empties out, its final state is captured as a snapshot for later inspection - see [/docs/lobby-snapshots](/docs/lobby-snapshots).

## HTTP API

Endpoints live under `/api/v1/lobbies` - see [/api/docs](/api/docs). What the spec cannot tell you:

- PATCH /lobbies and POST /lobbies/state target the caller's own lobby unless `lobby_id` names another - which is how a pinned WebRTC host, seated in no lobby, manages the room it runs.
- POST /lobbies/leave is idempotent: leaving while in no lobby answers 200.
- GET /lobbies and the `lobbies` channel sit behind the same `list_lobbies` feature flag - disabling the listing disables the feed with it.

## Realtime events

Members and spectators listen on `lobby:{lobby_id}`: `updated`, `user_joined`, `user_left`, `user_kicked`, `user_online`, `user_offline`, `user_updated`, `host_changed`, `state_changed`, the four `ready_check_*` events and the three `chat_message_*` events. A lobby browser listens on the `lobbies` topic instead: `lobby_created`, `lobby_updated`, `lobby_deleted` and `lobby_membership_changed` - hidden lobbies never appear there. See the Realtime guide.

## Server scripting

```elixir
{:ok, lobby} = Gamend.Lobbies.create_lobby(%{title: "arena", host_id: user.id})
{:ok, _user} = Gamend.Lobbies.join_lobby(user, lobby.id, %{password: "hunter2"})
{:ok, lobby} = Gamend.Lobbies.transition_state(lobby, "playing")

# update_lobby/2 replaces metadata wholesale, so a plugin writing its own
# key merges instead - it cannot wipe anyone else's:
{:ok, lobby} = Gamend.Lobbies.merge_metadata(lobby, %{"round" => 2})

members = Gamend.Lobbies.get_lobby_members(lobby)
{:ok, _} = Gamend.Lobbies.delete_lobby(lobby)
```

Hooks fire around every step: before/after each of create, join, leave, kick, update, state change and delete, plus after_lobby_host_change when the host migrates.

## Operations

- The Admin → Lobbies page (/admin/lobbies) lists and edits every lobby, hidden ones included; /admin/lobbies/live is a live browser that updates as lobbies change. Admin HTTP mirrors: GET/PATCH/DELETE under /api/v1/admin/lobbies.
- GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES (default 15) is the silence window: a lobby nobody has been *seen* in for that long is deleted, and a member offline that long in a lobby still in use has their seat released - through the normal leave path, so host migration, ready checks and broadcasts still run. 0 disables both.
- GAMEND_LIMITS_MAX_LOBBY_USERS caps max_users; GAMEND_LIMITS_MAX_LOBBY_TITLE and GAMEND_LIMITS_MAX_LOBBY_PASSWORD cap the strings.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Lobbies`](https://docs.gamend.org/Gamend.Lobbies.html) - the functions a plugin calls, with their
  signatures and docs.
