# `Gamend.Matchmaking.Broadcast`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/matchmaking/broadcast.ex#L1)

Broadcasts matchmaking events to users: a ticket queued, cancelled, or
matched into a lobby.

Core publishes on the `matchmaking:user:<id>` PubSub topic; the user
channel subscribes on join and forwards to the client (same shape as the
tournament events). Core never references the web endpoint directly.

# `match_found`

```elixir
@spec match_found([map()], Ecto.UUID.t()) :: :ok
```

Notifies every matched user that a lobby has been found.

# `ticket_cancelled`

```elixir
@spec ticket_cancelled([map()], String.t()) :: :ok
```

Tells each ticket's user it left the queue with no match
(`ticket_cancelled`), and why: `"left"` (they cancelled, or their socket
closed), `"declined"` or `"timeout"` (an accept), `"offline"` (the sweep),
`"admin"`, `"unseated"` (the lobby could not seat them). `tickets` carry
`id` and `user_id`.

# `ticket_queued`

```elixir
@spec ticket_queued([map()], boolean()) :: :ok
```

Tells each ticket's user it is in the queue (`ticket_queued`): `requeued`
when a failed accept put it back, in its old place. `tickets` carry `id`,
`user_id`, `match_params` and `queued_at`; the event says `queued_at_ms`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
