# `Gamend.Presence`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/presence.ex#L1)

Cluster-wide tracking of who is connected where.

Backed by `Phoenix.Presence`, so entries are tied to process liveness and
replicated between nodes by CRDT: a node that dies takes its entries with it,
with no sweeper to notice. That is the property node-local ETS and database
flags both lack.

Used for signaling room membership and lobby spectators. Not for anything
queried in SQL — presence lives in memory and cannot be joined against a
table — and not for anything durable, since a full cluster restart empties it.

During a netsplit each side sees only its own members until they heal.

## Reads

Read through `keys/1` and `last_socket?/1`, never `list/1` or
`get_by_key/2`. phoenix_pubsub 2.4 answers those two with a call to the
topic's shard whose reply is its whole state, a tag for every presence on
it, which the caller then filters: at 2,000 players each call copied ~1 MB
and queued behind every other on the one shard process, and a thousand
disconnects at once ran a 1 GB server out of memory. These read the shard's
protected table instead, only the topic asked for. Unlike the two they
replace they keep the entries of a replica that just went down, until the
tracker removes them.

# `child_spec`

# `entries`

```elixir
@spec entries(String.t()) :: [{String.t(), map()}]
```

The entries tracked on `topic`, `{key, meta}`, one per tracked process (two
tabs of one player are two). `keys/1` with the meta, read the same way
(*Reads*). Cluster-wide.

# `fetch`

# `fetchers_pids`

# `get_by_key`

# `keys`

```elixir
@spec keys(String.t()) :: [String.t()]
```

The distinct keys tracked on `topic`, as strings and sorted: the keys of
`list/1`, without its copy (*Reads*). Cluster-wide.

# `last_socket?`

```elixir
@spec last_socket?(Ecto.UUID.t()) :: boolean()
```

Whether the calling process holds this user's only tracked socket.

Cluster-wide, unlike the per-node registry count it replaces.

# `list`

# `other_socket?`

```elixir
@spec other_socket?(Ecto.UUID.t(), pid()) :: boolean()
```

Whether `user_id` has a socket tracked other than `pid`'s. Exact whether or
not `pid`'s own entry is still there, so a process watching a socket that
has already gone can ask it too (`Gamend.Accounts.Online`).

# `track`

# `track`

# `untrack`

# `untrack`

# `update`

# `update`

# `users_buckets`

```elixir
@spec users_buckets() :: pos_integer()
```

Number of topics connected users are spread over.

# `users_topic`

```elixir
@spec users_topic(Ecto.UUID.t()) :: String.t()
```

Topic this user is tracked on.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
