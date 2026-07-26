---
icon: hero-heart
---

# Friends & Blacklist

One table backs both features. A friendship row records a directed relationship between two users, and its status decides what that relationship means — a pending request, an accepted friendship, or a block. Blocking is therefore not a separate system: it is the same row, which is why a block cleanly supersedes whatever friendship existed before it.

## Friend lifecycle

```text
POST /friends ──► pending ──► accept ──► accepted
                     │
                     ├──► reject  ──► rejected
                     └──► block   ──► blocked

POST /users/:user_id/block ──► blocked   (no prior relationship needed)
```

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
id.** Accept, reject and delete take a *friendship* id; block and unblock take a
*user* id. You block a person, not a relationship, which is what lets you block
someone you have never interacted with.

## Realtime events

Friend changes do **not** each get their own channel event. Every one of them -
request, accept, reject, remove, block, unblock - reaches the client as a single
`friend_updated` on `user:{user_id}` carrying the refreshed friend list, plus a
`notification_created` whose `metadata.type` names what happened. A listener
bound to `friend_accepted` on the socket will never fire; see the Realtime
guide.

In a block, the row stores `target_id` as the blocker and `requester_id` as the
blocked user, regardless of who sent any earlier request.

## Server scripting

```elixir
# Blacklist a player from server-side code
GameServer.Friends.block_user(user, other_user_id)
GameServer.Friends.unblock_user(user, other_user_id)

# Read the blacklist
GameServer.Friends.list_blocked_users(user_id, page: 1, page_size: 25)

# Is this pair blocked, in either direction?
GameServer.Friends.blocked?(user_a_id, user_b_id)

# Resolve a whole group at once (one query) — used by the matcher
GameServer.Friends.blocked_pairs(user_ids)
GameServer.Friends.any_blocked?(user_id, other_ids)
```

A custom matchmaking_form_matches/2 hook does not need to check blocks itself: whatever groups it returns are validated against the block list before any lobby is created, and a group pairing blocked players is dropped.

## Operations

- The Admin → Blacklist page lists every block in the system, filterable by a user on either side, with force-unblock for support cases.
- Blocks are permanent until lifted; there is no expiry. Removing a block deletes the row rather than reverting it to a friendship.
- GAMEND_LIMITS_MAX_FRIENDS_PER_USER caps accepted friendships per user; blocks are not counted against it.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`GameServer.Friends`](https://appsinacup.com/game_server/GameServer.Friends.html) - the functions a plugin calls, with their
  signatures and docs.
