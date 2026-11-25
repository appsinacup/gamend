# `Gamend.Signaling`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/signaling.ex#L1)

WebRTC signaling: who is in a room, and relaying offers between them.

A "room" is a lobby. There is no room record and no room process — the
configuration lives in the lobby's own `webrtc_*` columns, membership lives
in `Gamend.Presence`, and relayed messages travel over `Phoenix.PubSub`.
All three are cluster-wide, so a peer on one node can signal a peer on
another.

That is the reason for this shape. The previous version kept rooms in a
GenServer registered under a plain local name, so a room created on one node
did not exist on any other, and every player whose socket landed elsewhere
failed to join with `:room_not_found`.

## Configuration

Read from the lobby, never mirrored:

    Signaling.configure(lobby, enabled: true, topology: :mesh)
    Signaling.configure(lobby, enabled: true, topology: :star, host_id: some_server_user_id)

Held in server-owned `lobbies.webrtc_*` columns, written only by
`configure/2`, not in `metadata`: that map is replaced wholesale by any
writer, so a game storing match state would wipe it, and the lobby host can
`PATCH` it, so a player could flip the topology and hand everyone the right
to broadcast. The star host defaults to
`lobby.host_id`; `configure/2` can pin a different one, which is how a
headless server process hosts a lobby it is not a member of.

## Topology

  * `:mesh` — any peer may signal any other.
  * `:star` — every exchange must involve the host, and only the host may
    broadcast.

# `config`

```elixir
@type config() :: %{
  topology: topology(),
  host_user_id: user_id() | nil,
  late_join: boolean(),
  reconnect_timeout: non_neg_integer()
}
```

# `message_type`

```elixir
@type message_type() :: :offer | :answer | :ice
```

# `role`

```elixir
@type role() :: :host | :user
```

# `room_id`

```elixir
@type room_id() :: String.t()
```

# `topology`

```elixir
@type topology() :: :mesh | :star
```

# `user_id`

```elixir
@type user_id() :: String.t()
```

# `authorize`

```elixir
@spec authorize(room_id(), user_id()) ::
  {:ok, role()} | {:error, :room_not_found | :not_allowed}
```

The role `user_id` may join with, or `{:error, :not_allowed}`.

Membership comes from the lobby. `late_join` decides whether a non-member may
connect at all; the host of a star room is whoever the lobby says it is.

# `broadcast`

```elixir
@spec broadcast(room_id(), user_id(), message_type(), map()) ::
  :ok | {:error, :room_not_found | :user_not_found | :not_allowed}
```

Sends `payload` to every other peer in the room.

Only the host may broadcast in a star room.

# `close`

```elixir
@spec close(room_id()) :: :ok
```

Tells every connected peer the room is over, so their channels stop.

# `config`

```elixir
@spec config(room_id()) :: {:ok, config()} | {:error, :room_not_found}
```

The room's configuration, derived from the lobby.

`{:error, :room_not_found}` when the lobby is gone or WebRTC is not enabled
on it — deliberately indistinguishable to a caller.

# `configure`

```elixir
@spec configure(Gamend.Lobbies.Lobby.t() | room_id(), keyword()) ::
  {:ok, Gamend.Lobbies.Lobby.t()} | {:error, term()}
```

Turns signaling on or off for a lobby, and sets how it behaves.

The only writer of the `webrtc_*` columns. Options: `:enabled`, `:topology`
(`:star` | `:mesh`), `:host_id`, `:late_join`, `:reconnect_timeout`.

Deliberately not part of the lobby changeset — a client `PATCH` must not be
able to reach any of it. That matters most for `:host_id`: pinning the star
host grants that user the `:host` role on join, membership or not, so it is
checked against `users` here and returns `{:error, :host_not_found}` rather
than reaching the database constraint (SQLite reports no constraint name, so
a bad id would raise instead of erroring).

# `enabled?`

```elixir
@spec enabled?(room_id()) :: boolean()
```

Whether the lobby has WebRTC enabled.

# `inbox`

```elixir
@spec inbox(room_id(), user_id()) :: String.t()
```

PubSub topic one peer listens on for messages addressed to it.

# `peer_role`

```elixir
@spec peer_role(room_id(), user_id()) :: role() | nil
```

The role `user_id` is connected with, or `nil`.

# `peers`

```elixir
@spec peers(room_id()) :: %{required(user_id()) =&gt; role()}
```

Everyone currently connected to the room, as `%{user_id => role}`.

The role is computed from the lobby on every read rather than read back from
the presence meta it was tracked with. Otherwise a host change leaves the new
host tracked as `:user` and the old one still holding `:host` until they
happen to reconnect.

# `relay`

```elixir
@spec relay(room_id(), user_id(), user_id(), message_type(), map()) ::
  :ok | {:error, :room_not_found | :user_not_found | :not_allowed}
```

Sends `payload` to one peer.

In a star room every exchange must involve the host; in a mesh room any pair
may talk.

# `stats`

```elixir
@spec stats() :: %{
  rooms_enabled: non_neg_integer(),
  rooms_active: non_neg_integer(),
  peers_connected: non_neg_integer()
}
```

Aggregate room counts for the public stats endpoint.

`rooms_enabled` is what the lobbies are configured for; `rooms_active` counts
only rooms someone is actually connected to. Presence cannot enumerate its own
topics, so the room ids come from the lobby table first.

# `topic`

```elixir
@spec topic(room_id()) :: String.t()
```

PubSub topic carrying a room's presence.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
