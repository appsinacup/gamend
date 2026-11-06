---
icon: hero-heart
---

# Friends & Blacklist

One table backs both features. A friendship row records a directed relationship between two users, and its status decides what that relationship means: a pending request, an accepted friendship, or a block. Blocking is therefore not a separate system: it is the same row, which is why a block cleanly supersedes whatever friendship existed before it.

## Friend lifecycle

```text
POST /friends ──► pending ──► accept ──► accepted
                     │
                     ├──► reject  ──► rejected
                     └──► block   ──► blocked

POST /users/:user_id/block ──► blocked   (no prior relationship needed)
```

A pending request is answered once. Of an accept, a reject, a block and a
cancel landing together, the first to move it out of pending stands and is the
only one anybody hears about; the others answer what it became: 409
`already_friends` for an accept of an accepted request, 403 `not_pending` for a
request already answered another way, and 404 `not_found` for one cancelled
first. `DELETE /friends/:id` cancels only a request still pending and removes
only an accepted friendship, so a block placed meanwhile is never deleted by
it. GAMEND_LIMITS_MAX_FRIENDS_PER_USER and
GAMEND_LIMITS_MAX_PENDING_FRIEND_REQUESTS are each player's, and hold however
many requests they accept or send at once.

## Blacklist

A player can block any user, whether or not a friendship exists between them. The block is symmetric in effect: it does not matter who blocked whom, the two are simply kept apart everywhere. Only the player who created a block can lift it.

| Surface | Effect of a block |
|---|---|
| Matchmaking | The matcher never puts a blocked pair in the same match. Both players keep waiting and are matched with other people instead; neither is starved, and a player blocked with everyone ahead of them does not stall the queue. |
| Lobbies | Joining a lobby that already holds a blocked player is refused with 403 blocked. This is enforced in the join transaction, so it holds for party joins and quick-join too. |
| Parties & invites | Party and group invites between blocked users are refused. |
| Chat | Direct messages between blocked users are refused. |
| Friend requests | A new request between blocked users is refused. |

## HTTP API

Endpoints live under `/api/v1/friends`, `/api/v1/me/friends` and
`/api/v1/users/:user_id/block` - see [/api/docs](/api/docs).

One thing the spec cannot tell you: **the routes take two different kinds of
id.** Everything under `/friends/:id` (accept, reject, delete, and
`/friends/:id/block` / `/friends/:id/unblock`) takes a *friendship* id.
`/users/:user_id/block` and `/users/:user_id/unblock` take a *user* id: you block
a person, not a relationship, which is what lets you block someone you have
never interacted with.

## Realtime events

Each friendship change is pushed on `user:{user_id}` to the users it involves,
as its own event. The payload is the friendship row: `id`, `requester_id`,
`target_id` and `status`.

| Event | Sent when |
|---|---|
| `incoming_request` | Someone sent you a request (to the target) |
| `outgoing_request` | You sent a request (to the requester) |
| `friend_accepted` | A request was accepted |
| `friend_rejected` | A request was rejected |
| `request_cancelled` | A pending request was withdrawn |
| `friend_removed` | A friendship was deleted |
| `friend_blocked` | A block was placed |
| `friend_unblocked` | A block was lifted |

A request, an accept and a reject also create a notification
(`notification_created`, with `metadata.type` `friend_request`,
`friend_accepted` or `friend_rejected`).

`friend_updated` is a different thing: a friend's profile and presence (online
state, name, avatar, lobby or party), as `{"friends": {user_id => profile}}`.
The whole list arrives once on join, then one entry per change.

In a block, the row stores `target_id` as the blocker and `requester_id` as the
blocked user, regardless of who sent any earlier request.

## Server scripting

```elixir
# Blacklist a player from server-side code
Gamend.Friends.block_user(user, other_user_id)
Gamend.Friends.unblock_user(user, other_user_id)

# Read the blacklist
Gamend.Friends.list_blocked_users(user_id, page: 1, page_size: 25)

# Is this pair blocked, in either direction?
Gamend.Friends.blocked?(user_a_id, user_b_id)

# Resolve a whole group at once (one query) — used by the matcher
Gamend.Friends.blocked_pairs(user_ids)
Gamend.Friends.any_blocked?(user_id, other_ids)
```

A custom matchmaking_form_matches/2 hook does not need to check blocks itself: whatever groups it returns are validated against the block list before any lobby is created, and a group pairing blocked players is dropped.

## Operations

- The Admin → Blacklist page lists every block in the system, filterable by a user on either side, with force-unblock for support cases.
- Blocks are permanent until lifted; there is no expiry. Removing a block deletes the row rather than reverting it to a friendship.
- GAMEND_LIMITS_MAX_FRIENDS_PER_USER caps accepted friendships per user; blocks are not counted against it.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Friends`](https://docs.gamend.org/Gamend.Friends.html) - the functions a plugin calls, with their
  signatures and docs.
