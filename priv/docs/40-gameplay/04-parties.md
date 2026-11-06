---
icon: hero-user-group
---

# Parties

A party is the group a player brings with them: a pre-lobby unit that outlives any single match. Membership is a single column - `users.party_id`, one party per player - and the leader is the only member who can steer it: invite, kick, update, enter lobbies, queue. A lobby is the room a match happens in ([/docs/lobbies](/docs/lobbies)); a party is who you enter rooms with, and it stays intact while lobbies come and go.

## Lifecycle

```text
POST /parties ──► caller becomes leader and first member (max_size 4 by default)

leader invites ──► pending invite ──► accept ──► member joins
                              └─────► decline

leave ──► a leaving leader hands the party to the longest-present member;
          the last member out takes the party with them
POST /parties/disband ──► leader ends it outright for everyone
```

There is no join endpoint: the only way into a party is an invite. Accepting one automatically pulls the player out of whatever party they were in and cancels their pending invites from other parties - a player answers at most one party at a time.

## Invites

Only the leader invites, and only people the leader is *connected* to: a friend, or someone sharing a group with them (see [/docs/friends](/docs/friends) and [/docs/groups](/docs/groups)). A block between the target and **any** current member refuses the invite - and is checked again at accept, because membership can change in between.

The invite is a record, independent of the notification it sends - deleting notifications does not affect pending invites. Re-inviting someone with a pending invite is a no-op that returns the existing one, and a party that fills up before an invite is answered marks it declined and tells the sender why (`party_full`). Each player can hold at most GAMEND_LIMITS_MAX_PARTY_PENDING_INVITES pending invites.

Kicking is the leader's too, never of themselves; the target gets a `party_kicked` notification and their pending invites for that party are cleaned up.

## Entering lobbies as one unit

A party never trickles into a lobby one member at a time. The lobby endpoints themselves are party-aware: the leader calling POST /lobbies, POST /lobbies/:id/join or POST /lobbies/quick_join takes the whole party, seated in a single transaction - everyone or no one (`not_enough_space`). A non-leader member calling them gets 403 in_party. The explicit forms POST /parties/create_lobby and POST /parties/join_lobby/:id run the same flows.

Two preconditions guard every variant: no member may already be in a lobby (`member_in_lobby`), and every member must be recently active (`members_offline`) - a party should not reserve seats for people who are not there. A party enters only a lobby each member could enter alone: a hidden one is 404, as it is for a player, and a block between any member and anyone already seated is 403 `blocked`. Quick join passes over such a lobby and tries the next. The party itself survives: when the lobby ends, the party is still standing.

In matchmaking a party queues as one unit and is never split - the leader queues for everybody and the whole party is seated together or not at all. The leader can also open a ready board over the party with POST /parties/ready_check (DELETE cancels); members answer through the same `/me/ready_check` surface as lobby checks, passing `"scope": "party"`, and the `ready_check_*` events arrive on the party channel. Both are covered in [/docs/matchmaking](/docs/matchmaking).

## HTTP API

Endpoints live under `/api/v1/parties` - see [/api/docs](/api/docs). What the spec cannot tell you: **the invite routes address two different things.** Sending and cancelling take a *user* id (`target_user_id`); accepting and declining take the *party* id - a recipient answers the party, not an invite record, so the client never needs to track invite ids. GET /parties/me returns the caller's own party (404 when in none), and POST /parties/leave is idempotent.

## Realtime events

Members listen on `party:{party_id}`: `updated`, `member_joined`, `member_left`, `member_online`, `member_offline`, `member_updated`, `disbanded`, the four `ready_check_*` events and the three `chat_message_*` events. Invite outcomes go to the *sender's* `user:{user_id}` channel instead: `party_invite_accepted` and `party_invite_declined`. The recipient's side of an invite is a `notification_created` whose `metadata.type` is `party_invite`, and `party_invite_cancelled` on the *recipient's* `user:{user_id}` channel when the leader withdraws it.

## Server scripting

```elixir
{:ok, party} = Gamend.Parties.create_party(user, %{"max_size" => 4})
{:ok, _invite} = Gamend.Parties.invite_to_party(leader, target_user_id)
{:ok, party} = Gamend.Parties.accept_party_invite(target, party.id)

# The leader takes everyone into a lobby atomically
{:ok, lobby} = Gamend.Parties.create_lobby_with_party(leader, %{"title" => "arena"})
{:ok, lobby} = Gamend.Parties.join_lobby_with_party(leader, lobby_id, %{})

{:ok, _} = Gamend.Parties.kick_member(leader, target_user_id)
{:ok, _} = Gamend.Parties.leave_party(user)
{:ok, :disbanded} = Gamend.Parties.disband(party)
```

Hooks fire around create, join, update, kick, leave and disband (`before_party_create`, `after_party_join`, `after_party_disband`, ...), and a party entering a lobby asks `before_lobby_join` for every member who joins (all of them for an existing lobby, all but the leader for the one they create), with `"party_id"` in its opts; the first refusal keeps the whole party out (403 `rejected`, and quick join tries the next lobby). `after_lobby_join` fires for the same members.

## Operations

- The Admin → Parties page (/admin/parties) lists every party with its leader and members, with per-party edit (max_size, metadata) and disband.
- GAMEND_RETENTION_ABANDONED_PARTY_MINUTES (default 15): a party in which nobody has been seen for the window is disbanded, and an individual member offline that long has their seat released through the normal leave path - so a long-gone leader hands the party over rather than holding it hostage. 0 disables.
- GAMEND_LIMITS_MAX_PARTY_SIZE caps max_size; GAMEND_LIMITS_MAX_PARTY_PENDING_INVITES caps pending invites per recipient.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Parties`](https://docs.gamend.org/Gamend.Parties.html) - the functions a plugin calls, with their
  signatures and docs.
