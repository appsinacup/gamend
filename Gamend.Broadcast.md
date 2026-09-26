# `Gamend.Broadcast`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/broadcast.ex#L1)

PubSub broadcasts that must never take the caller down with them.

Some state is applied locally first and only *mirrored* to other nodes — an
IP ban, a chat mute, a moderation notice. For those, a failed broadcast must
not undo the local effect: the ban still has to block this node's traffic
even when PubSub is unavailable, which happens in early boot and in bare
ExUnit cases.

The subtle part, and why this is one function rather than three copies:
`Phoenix.PubSub.broadcast/3` *exits* rather than raising when the PubSub
server is not registered, so a `rescue` alone does not catch it. The chat
moderation cache, its user notices and the IP-ban plug each carried their own
`rescue`/`catch :exit` pair to get this right.

# `best_effort`

```elixir
@spec best_effort(String.t(), term(), String.t() | nil) :: :ok
```

Broadcasts `message` on `topic` through `Gamend.PubSub`, always returning `:ok`.

A raise is logged as a warning naming `label`, when one is given; an exit
(no PubSub server) is silent, since that is the expected state during boot.

# `publish`

```elixir
@spec publish(String.t(), term()) :: :ok
```

Broadcasts `message` on `topic` through `Gamend.PubSub` once the enclosing
transaction commits (`Gamend.AfterCommit`), or now outside one.

Subscribers then never see a write before it is visible, nor one a rollback
erases, and the broadcast never runs while a transaction holds the database.
Every broadcast in core goes through here; the cache's own invalidation
messages are the exception (`Gamend.Cache`).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
