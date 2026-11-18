# `Gamend.Matchmaking.Constants`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/matchmaking/constants.ex#L1)

Constants for the matchmaking system.

# `event_cancelled`

Event broadcast when a ticket leaves the queue without a match.

# `event_found`

Event broadcast when a match is found.

# `event_queued`

Event broadcast when a ticket goes in the queue: joined, or put back after a failed accept.

# `member_backfill`

The key `before_matchmaking_join/2` sets to `true` in the attrs it answers
when a player who sits in a lobby they do not host fills it too
(`Gamend.Matchmaking`, *Backfill*).

# `status_cancelled`

Status for a ticket that has been cancelled.

# `status_matched`

Status for a ticket that has been matched to a lobby.

# `status_queued`

Status for a ticket that is waiting for a match.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
