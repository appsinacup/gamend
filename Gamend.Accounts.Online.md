# `Gamend.Accounts.Online`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/online.ex#L1)

A player online, one way for every client. The SDK's game socket
(`GamendWeb.UserChannel`) and a host's own page (a LiveView the player
plays in) call the same functions, so `users.is_online`, friends' online
dots, lobby, party and group presence, matchmaking's offline prune and the
abandoned-lobby reaper see them alike.

  * `connected/2`: the socket's process tracked on the user's presence
    topic (`Gamend.Presence.users_topic/1`), `users.is_online` set, and the
    user's lobby, party and groups told.
  * `heartbeat/1`: `last_seen_at` refreshed. A socket calls it every
    `heartbeat_ms/0`, so `StalePresenceSweeper` leaves a live player alone.
  * `disconnected/2`: when no other socket of theirs is left, the user's
    matchmaking tickets cancelled (an accept they were asked for declined)
    and `users.is_online` cleared. Checked again a moment later for a
    socket another node had not replicated yet.

`watch/2` does all three for a process with no `terminate/2` to rely on:
a LiveView's is not called when the process is killed or crashes. It
monitors the process, keeps its heartbeat and runs `disconnected/2` when
it goes. A node going down takes its watchers with it, and
`StalePresenceSweeper` marks those players offline.

    config :gamend_core, Gamend.Accounts.Online, watch: false

leaves `watch/2` at `connected/2`, with no watcher (tests: a watcher outlives
the test's database sandbox, and its writes fail once the test is done).

# `connected`

```elixir
@spec connected(pid(), Ecto.UUID.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

`pid`, a socket of `user_id`'s, is open: tracked on the user's presence
topic, `users.is_online` set, the user's lobby, party and groups told.
Answers the user as written, or `{:error, reason}` when the account is gone.

# `disconnected`

```elixir
@spec disconnected(Ecto.UUID.t(), pid()) :: :ok
```

`pid`, a socket of `user_id`'s, closed (or is closing). With no other
socket of theirs left, their matchmaking tickets are cancelled,
`users.is_online` is cleared and their lobby, party and groups told, then
checked again after a moment and the flag put back if a socket is there
after all.

# `heartbeat`

```elixir
@spec heartbeat(Ecto.UUID.t()) :: :ok
```

A socket of `user_id`'s is still open: `last_seen_at` refreshed.

# `heartbeat_ms`

```elixir
@spec heartbeat_ms() :: pos_integer()
```

How often an open socket calls `heartbeat/1`.

# `watch`

```elixir
@spec watch(pid(), Ecto.UUID.t()) :: :ok | {:error, term()}
```

`pid` (a LiveView, any process with no `terminate/2` to rely on) is a
socket of `user_id`'s for as long as it lives: `connected/2` now, a
`heartbeat/1` every `heartbeat_ms/0`, `disconnected/2` when it ends however
it ends. One watcher process per socket, under its own supervisor.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
