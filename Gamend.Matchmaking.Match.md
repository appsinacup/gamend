# `Gamend.Matchmaking.Match`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/matchmaking/match.ex#L1)

Creates the lobby for a claimed match and notifies the players.

Runs *outside* the sweep's cluster lock: `Lobbies.create_lobby/1` and
`join_lobby/2` fire plugin hooks and broadcasts, which must never run
inside a transaction. The tickets are already claimed (status `matched`),
so no other node can pick them up meanwhile; on failure they are requeued
and retried on the next tick.

Errors return tuples instead of raising, so one bad match never aborts the
rest of the sweep.

A match whose tickets ask for an accept (`accept_timeout_ms`) is not seated
here at first: `start/1` opens the accept check, and `accept_resolved/1`
seats it once everyone accepted, or puts the ones who did back in the
queue. A match with a backfill ticket is seated in that lobby (see
`Gamend.Matchmaking`, *Backfill*).

# `accept_resolved`

```elixir
@spec accept_resolved(Gamend.ReadyChecks.Check.t()) ::
  {:ok, Ecto.UUID.t()} | :ok | {:error, term()}
```

A matchmaking accept check resolved (called by `Gamend.ReadyChecks` once
it passed or failed). Passed: the match is seated (`create/1`). Failed: the
tickets of whoever accepted, or had not answered yet when someone declined,
go back in the queue, keeping their place; whoever declined or let the
deadline pass has their ticket cancelled. Tickets no longer held by the match (an admin
cancelled one) are left alone; a check with no tickets is not
matchmaking's.

# `create`

```elixir
@spec create([Gamend.Types.matchmaking_ticket()]) ::
  {:ok, Ecto.UUID.t()} | {:error, term()}
```

Seats a claimed match: in its backfill ticket's lobby when it has one
(`Gamend.Matchmaking.target_ticket/1`), else in a new hidden lobby, locked
once everyone is in. Records the lobby on the tickets and broadcasts
`match_found`.

# `start`

```elixir
@spec start([Gamend.Types.matchmaking_ticket()]) ::
  {:ok, Ecto.UUID.t()} | {:accepting, Ecto.UUID.t()} | {:error, term()}
```

A claimed match, begun: its accept check opened when its oldest ticket
asks for one (`{:accepting, check_id}`), else seated at once (`create/1`).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
