---
icon: hero-users
---

# Matchmaking

Ticket-based queueing that turns waiting players into hidden, locked lobbies. A player joins the queue with a set of match parameters; the server groups tickets whose parameters are identical, and when a group is big enough it creates the lobby, seats everyone, and tells each player where to go.

## How a match forms

```text
POST /matchmaking/tickets ──► ticket (queued)
                                  │
              worker sweep (every GAMEND_LIMITS_MATCHMAKING_TICK_MS)
                                  │
        group by identical match_params, oldest first
                                  │
        enough players?  ──► max_players reached: match now
                         ──► ≥ min_players and oldest waited
                             GAMEND_LIMITS_MATCHMAKING_TIMEOUT_MS: match now
                         ──► otherwise: keep waiting
                                  │
        hidden lobby created, players seated, lobby locked
                                  │
        "match_found" pushed on each player's user channel
```

Parameters match exactly — a ticket queued with map=dust2 never joins one with map=inferno. Skill bands, regions or modes are therefore encoded by the game client (or a server hook) as parameter values, and each distinct combination forms its own queue.

Blacklists are applied while the group is being formed, not after: two players who have blocked each other are never put in the same match, and each is matched with someone else instead. A player blocked with everyone ahead of them in the queue is skipped over rather than allowed to stall the players behind them. See the Friends & Blacklist guide.

## Client flow

Queue operations are HTTP under `/api/v1/matchmaking/tickets` - see
[/api/docs](/api/docs). The socket is only used for the result.

After joining, keep the user channel connected and wait for `match_found` on
`user:{user_id}`, carrying `{lobby_id, match_params}`. Disconnecting cancels
your tickets, and a periodic sweep also cancels tickets for users the server no
longer sees, so a queued ticket always belongs to someone who can be seated.

## Ticket lifecycle

```text
queued ────► matched      lobby created; match_id points at it
   │
   └───────► cancelled    player left the queue, disconnected,
                          went offline, or an admin cancelled it
```

## Server hooks

Five hooks cover the queue. Four are the usual gate-and-notify pattern; matchmaking_form_matches/2 is different — it replaces the matcher for one bucket.

| Hook | When | Returns |
|---|---|---|
| `before_matchmaking_join/2` | Before a ticket is written | {:ok, attrs} to allow (attrs may be rewritten), {:error, reason} to refuse |
| `after_matchmaking_join/2` | After the ticket is written, async | Ignored |
| `after_matchmaking_cancel/2` | After a user's tickets are cancelled, async; not fired when none were queued | Ignored |
| `matchmaking_form_matches/2` | Once per bucket per sweep | A list of ticket groups, or :default to use the built-in matcher |
| `after_matchmaking_matched/2` | After the lobby exists and players are seated, async | Ignored |

## Server-authoritative queue parameters

match_params is the bucket key: two tickets only meet when their params match byte for byte. That has one consequence worth internalising — put a precise value like an exact rating in match_params and every player lands in a bucket of one, so nothing ever matches. Keep params coarse (mode, region, a skill band) and read precise numbers off the user record inside matchmaking_form_matches/2.

Because the client sends the params, before_matchmaking_join/2 is where you stop it choosing its own bracket — recompute them server-side and overwrite whatever arrived:

```elixir
@impl true
def before_matchmaking_join(user, attrs) do
  mode = get_in(attrs, ["match_params", "mode"])

  if mode in ["ranked", "casual"] do
    # The rating comes from the user record, never from the client.
    rating = get_in(user.metadata, ["rating"]) || 1000

    params = %{"mode" => mode, "band" => Integer.to_string(div(rating, 500))}
    {:ok, Map.put(attrs, "match_params", params)}
  else
    {:error, :unknown_mode}
  end
end
```

## Replacing the matcher

matchmaking_form_matches/2 receives the bucket's params and every queued ticket in it, users preloaded, oldest first. Return groups of tickets to form, or :default to defer to the built-in FIFO matcher. It is called once per bucket per sweep rather than once per candidate pair, so an O(n log n) pass over a large queue stays well inside the tick budget.

```elixir
@impl true
def matchmaking_form_matches(%{"mode" => "ranked"}, tickets) do
  # Exact ratings are integers on the user record, not in the bucket key.
  tickets
  |> Enum.map(&{server_rating(&1.user), &1})
  |> Enum.sort_by(&elem(&1, 0))
  |> Enum.chunk_every(2, 2, :discard)
  |> Enum.filter(fn [{a, _}, {b, _}] -> abs(a - b) <= 100 end)
  |> Enum.map(fn [{_, a}, {_, b}] -> [a, b] end)
end

# Anything else falls back to the built-in matcher.
def matchmaking_form_matches(_params, _tickets), do: :default
```

The server re-checks whatever you return: groups containing a ticket from outside the bucket, a duplicate ticket, or a pair where one player has blocked the other are dropped with a warning rather than seated. A bug in your matcher costs you a match, not a broken lobby.

A worked example combining both — a string mode validated on join and an integer rating used in the matcher — ships in modules/plugins_examples/example_hook.

## Parties

A party queues as one. The leader calls join for everybody: the server writes one ticket per member, all sharing the party's id, and the matcher treats them as an indivisible unit — the whole party is seated in the same lobby or none of them are. A party is never split.

| Rule | Why |
|---|---|
| Only the leader can queue a party | A member calling join gets 409 not_party_leader. One caller means members can never disagree about min_players or max_players. |
| A party larger than max_players is refused | 409 party_too_large. It could never be seated, so it is rejected at join instead of waiting forever. |
| A party holding a blocked pair cannot queue | 409 party_has_blocked_pair. An invite cannot put a blocked pair in a party, but blocking someone already in it can. Such a party is unseatable, so it is refused at join rather than losing a member to a failed lobby. |
| One queued ticket per player | 409 already_queued, including when a party member is already queued solo. |
| Any member can cancel | Cancelling one member's ticket cancels the whole party's — only the leader queues, but nobody should be stuck in a queue they cannot leave. |
| One member times out, the party leaves | A party that can no longer field everyone should not hold a slot, so the sweep removes all of its tickets together. |

Packing is FIFO by the party's oldest ticket, anchored on the longest-waiting group and filled with whichever groups fit the seats left. A party that does not fit is skipped rather than broken up, and the sweep moves on to the next anchor so one oversized party cannot stall everyone behind it.

## Leaving the queue

Going offline does not immediately cost a queue position. A ticket is pruned only once its owner has been offline longer than GAMEND_LIMITS_MATCHMAKING_OFFLINE_GRACE_MS (5 minutes by default), so a brief disconnect is survivable. A player who queued over HTTP and never opened a socket has no last-seen time, so the same grace period runs from when they queued.

## Operations

- The Admin → Matchmaking page shows live queue depths and the ticket list, with per-ticket force-cancel and a manual sweep trigger.
- Admin HTTP mirrors of everything: GET/DELETE under /api/v1/admin/matchmaking.
- Tuning via env vars: GAMEND_LIMITS_MATCHMAKING_TICK_MS (sweep interval), GAMEND_LIMITS_MATCHMAKING_TIMEOUT_MS (wait before a below-max group forms), GAMEND_LIMITS_MATCHMAKING_OFFLINE_GRACE_MS (how long a disconnected player keeps their place), GAMEND_LIMITS_MAX_MATCHMAKING_PLAYERS, GAMEND_LIMITS_MAX_MATCHMAKING_PARAMS_SIZE.
- Multi-instance safe: every node runs the worker, but the sweep body is serialized cluster-wide by an advisory lock, so exactly one node forms matches per tick.

## Ready checks

A ready check asks a set of players to each answer before something proceeds. A host opens one over their lobby with POST /lobbies/ready_check and calls it off with DELETE — host-managed lobbies only, since a hostless matchmaking lobby belongs to the server. The host is pre-marked ready: clicking the button is their answer.

A player is in at most one check at a time, so answering needs no id: GET /me/ready_check returns the open one (or null) and POST /me/ready_check with {"ready": true} or false answers it. Members see each other's states; the four events ready_check_started, ready_check_updated, ready_check_passed and ready_check_failed arrive on the lobby channel.

What core does on failure is nothing. A declined or timed-out check kicks nobody, deletes no lobby and moves no lobby state — it records who did not answer and stops there. The host can kick them with the kick they already have, or your after_ready_check_failed hook can decide. Likewise a passed check starts no match by itself: call Lobbies.transition_state/3 from after_ready_check_passed, and gate your own start in before_lobby_state_change with ReadyChecks.passed?/1.

Tuning: GAMEND_LIMITS_READY_CHECK_TIMEOUT_MS (default 15s answering window; a host may override it per check) and GAMEND_LIMITS_MAX_READY_CHECK_PARTICIPANTS. The Admin → Matchmaking page lists recent checks with their outcomes and a force-cancel, mirrored at /api/v1/admin/ready_checks.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`GameServer.Matchmaking`](https://appsinacup.com/game_server/GameServer.Matchmaking.html) - the functions a plugin calls, with their
  signatures and docs.
