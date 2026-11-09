---
icon: hero-trophy-solid
---

# Tournaments

Single-elimination bracket tournaments: players register during a registration window, the bracket is drawn at start time (seeded, byes auto-resolved), and winners advance through timed rounds until each bracket crowns a champion. The server owns the structure (registration, seeding, rounds, deadlines, advancement, recurrence) while your game owns gameplay and judgment through hooks: the server never creates lobbies and never decides winners on its own.

## Lifecycle

```text
  scheduled ──(registration_opens_at)──► registration ──(starts_at: draw)──► running ──► finished
                                          (nil starts_at = stays open until
                                           an admin/game triggers the draw)
                                                                               │
                                              rounds of round_window_sec each; │
                                              champion decided or ends_at ─────┘

  recur (cron) set? finishing spawns the next occurrence with the same slug
  and config — "current occurrence per slug" works like leaderboard seasons.
```

Transitions, draws, match deadlines and recurrence run on a tick every `GAMEND_TOURNAMENTS_TICK_INTERVAL_SECONDS` (default `30`), so a round can start or time out up to that late. Lower it for short rounds.

## Entries

A bracket side is an entry, and an entry is a leader (one user). For team tournaments (team_size 2+, advisory) the leader registers and team composition is game policy, enforced in hooks if you care. The server tracks who leads, not who shows up. Entry states: registered → active (after the draw) → eliminated or winner.

## Client API

| Endpoint | Description |
|---|---|
| GET /api/v1/tournaments | List (filter by state, or slug for occurrence history) |
| GET /api/v1/tournaments/:id | Details by id or slug (current occurrence); includes my_entry when authenticated |
| POST /api/v1/tournaments/:id/join | Register as entry leader; answers the entry (before_tournament_register hook gates) |
| DELETE /api/v1/tournaments/:id/join | Withdraw before the draw (before_tournament_leave hook can veto) |
| GET /api/v1/tournaments/:id/standings | Champions and every entry's placement |
| GET /api/v1/tournaments/:id/bracket | A page of brackets, each with its matches and the entries they name; `?index=` for one |
| GET /api/v1/tournaments/:id/my_match | The caller's current unresolved match; 404 `no_current_match` when none is waiting |

Registration answers `registration_closed` or `tournament_full` (403) and `already_registered` (409); a hook that rejects answers `rejected` (403) with its reason in `message`. Leaving after the draw answers `already_drawn` (409).

### Registration and the entry fee

A join takes the seat first and asks the game second. The seat is taken under the tournament's lock, with the capacity and duplicate checks; only then does `before_tournament_register` run, outside any lock, with the seat held. So charge the entry fee there: a full tournament, closed registration or a repeated request (a double tap) is refused before the hook and never reaches it, and a player the hook lets in has their seat.

- While the hook runs, the caller's entry already exists: `Tournaments.get_entry/2` finds it and `count_entries/1` counts it. Do not refuse a player for being registered.
- `{:error, reason}`, a raise or a timeout refuses: the seat is given back (only that entry, and only while the tournament is still in registration) and the client gets `rejected`. Charge last, after every other check in the hook, so a refusal never follows a charge.
- The draw does not wait for a hook. If the tournament is drawn while a hook that then refuses was running, the entry is already in a bracket: it forfeits instead, its open match resolved for the opponent with `"withdrawn": true` in the match metadata (`after_tournament_match_resolved` fires for it) and the entry eliminated. A field of one that the draw finished keeps its winner.
- `after_tournament_register` fires only for a join the hook allowed.
- A cancel or a delete inside the hook comes after the seat, as one a moment later would: the join still answers the entry.

Match resolution has no public endpoint: verdicts are server-side (hooks); expose your own call_hook RPC if your flow needs a client trigger. Entry leaders receive tournament_updated, tournament_match_ready, tournament_match_resolved and tournament_finished on their user channel (see WebSocket Channels).

## Match resolution contract (hooks)

A tournament match is a pairing plus a verdict: two entries that must produce a winner by a deadline. How it is played (a live lobby your hook creates, solo runs compared afterwards, anything) is invisible to the server.

```elixir
# fires when both slots are filled and the round window is open
def tournament_match_ready(match) do
  # create a lobby via the SDK, set up the challenge, notify players ...
  # scratch space: Gamend.Tournaments.update_match_metadata(match.id, map)
  :ok
end

# report the verdict (first write wins; :no_winner = double forfeit)
Gamend.Tournaments.resolve_match(match_id, winner_entry_id)
Gamend.Tournaments.resolve_match(match_id, :no_winner)

# deadline passed and still unresolved: adjudicate here, or the
# tournament's deadline_policy applies (forfeit_both / advance_first_slot / random)
def tournament_match_expired(match) do
  Gamend.Tournaments.resolve_match(match.id, pick_winner(match))
end
```

| Hook | Purpose |
|---|---|
| before_tournament_register/2 | Gate or charge entry (fees are game economy); runs with the seat held, and {:error, reason} rejects and gives the seat back (see *Registration and the entry fee*) |
| after_tournament_register/2 | Side effects after a join the hook allowed |
| before_tournament_leave/2 | Veto leaving (e.g. paid entry is final) |
| tournament_match_ready/1 | Start the match: lobby creation, challenge setup |
| tournament_match_expired/1 | Adjudicate an unresolved match at its deadline |
| before_tournament_result/2 | Validate or veto a verdict before it is accepted |
| after_tournament_match_resolved/1 | Side effects after resolution (stats, rewards per match) |
| after_tournament_finished/2 | Reward distribution — receives champions + placements |

## Admin

The Tournaments admin page covers create/edit (cron recurrence included), live bracket view and force actions. Every force action is also available over HTTP for admin tooling:

Admin endpoints under `/api/v1/admin/tournaments` cover create, update, delete,
cancel, draw, finish and match resolution - see [/api/docs](/api/docs).
Resolving a match takes `winner_entry_id`; omit it for a double forfeit.

Tournaments carry an optional `icon_url` (set it in the admin form or via the
API; upload the image through the admin Storage page to host it on the
server). When unset, the web UI shows the shared default tournament icon and
the API returns `""` so game clients can apply their own.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Tournaments`](https://docs.gamend.org/Gamend.Tournaments.html) - the functions a plugin calls, with their
  signatures and docs.
