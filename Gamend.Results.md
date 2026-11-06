# `Gamend.Results`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/results.ex#L1)

What happened in a play (priv/docs/40-gameplay/45-results.md).

A **result** is one play by one player (`Gamend.Results.Result`), its
**events** what happened in it, in order (`Gamend.Results.Event`). The game
writes an event when something happens and nothing else: no summary kept up
to date, no copy of the play's state. The lobby holds the live state; the
result is the record it leaves. The same rows are the replay (the events by
id), the play at a glance (`stats/1`: each key's count and sum) and the
player's history (`list/2`).

**Writes are the server's.** A plugin, the host app or a hook handling a
move calls `start/3`, `record/4` and `finish/1`; no client writes a result.
An event is one insert and `finish/1` one update that only matches an open
row, so a play ends once; the two take turns under the result's lock, so
no event lands after the end and the event cap holds.

**Reads follow the result's visibility**, KV's words (`readable?/2`), and
every write is pushed as it happens (`result_started`, `result_event`,
`result_ended`) to the owner's `user:<id>` topic and, when its lobby's
members may read it, the lobby's `lobby:<id>`.

# `count`

```elixir
@spec count(map()) :: non_neg_integer()
```

How many results match `filters` (as `list/2`).

# `count_events`

```elixir
@spec count_events(String.t()) :: non_neg_integer()
```

How many events a result holds.

# `delete`

```elixir
@spec delete(Gamend.Results.Result.t()) ::
  {:ok, Gamend.Results.Result.t()} | {:error, :not_found | Ecto.Changeset.t()}
```

A result and its events, deleted. `{:error, :not_found}` when another
delete took it first.

# `events`

```elixir
@spec events(String.t(), keyword()) :: [Gamend.Results.Event.t()]
```

A result's events, oldest first. Opts: `:after`, an event id (the events
written after it: a reconnect's catch-up), `:limit` (500, at most 2,000).

# `events_by_key`

```elixir
@spec events_by_key([String.t()], [String.t()]) :: %{
  required(String.t()) =&gt; [Gamend.Results.Event.t()]
}
```

The events of many results whose key is one of `keys`, by result id, each
list oldest first: one query, for a page of results read whole (a
history list).

# `finish`

```elixir
@spec finish(Gamend.Results.Result.t() | String.t()) ::
  {:ok, Gamend.Results.Result.t()} | {:error, term()}
```

The play over: `{:ok, result}`, ended now. One update that only matches an
open row, so a second finish answers `{:error, :already_ended}`.

# `get`

```elixir
@spec get(String.t()) :: Gamend.Results.Result.t() | nil
```

A result by id, or nil.

# `kinds`

```elixir
@spec kinds() :: [String.t()]
```

The kinds results have been written under, for a filter.

# `list`

```elixir
@spec list(map(), keyword()) :: [Gamend.Results.Result.t()]
```

Results, newest first. Filters: `:user_id`, `:kind` (one, or a list),
`:status`, `:lobby_id`. Opts: `:page` and `:page_size`; with no `:page`, the first
`Gamend.Query.unpaginated_limit/0`.

# `move_user`

```elixir
@spec move_user(String.t(), String.t()) :: non_neg_integer()
```

A guest's results made the account's (`Gamend.Accounts.GuestMerge`): their
plays join the account's history instead of going with the guest.

# `prune_before`

```elixir
@spec prune_before(DateTime.t(), pos_integer()) :: non_neg_integer()
```

Results started before `cutoff` deleted with their events, `batch` at a
time; answers how many results went.

# `readable?`

```elixir
@spec readable?(Gamend.Results.Result.t(), Gamend.Accounts.User.t() | nil) ::
  boolean()
```

Whether `user` may read `result`, by its visibility: `public` anyone,
`owner_only` its player, `lobby_members_only` a player seated in its
lobby now, `owner_or_lobby_member` either, `admin_only` and every other
an admin. `server_only` no client.

# `record`

```elixir
@spec record(
  Gamend.Results.Result.t() | String.t(),
  String.t(),
  number() | nil,
  map()
) ::
  {:ok, Gamend.Results.Event.t()} | {:error, term()}
```

One thing that happened in a play: `key` what (`answer`, `hint`), `value`
the number it carries (or nil), `metadata` anything else. `{:ok, event}`;
`{:error, :ended}` once the play is over, `{:error, :not_found}`,
`{:error, :too_many_events}` past `GAMEND_LIMITS_MAX_RESULT_EVENTS`.

# `record_lobby`

```elixir
@spec record_lobby(String.t(), String.t(), number() | nil, map()) :: non_neg_integer()
```

`record/4` on every open result of `lobby_id`, for code that knows the
lobby and not its players (a timer, a disconnect). Answers how many it
wrote.

# `start`

```elixir
@spec start(String.t(), String.t(), keyword()) ::
  {:ok, Gamend.Results.Result.t()} | {:error, term()}
```

A play begun by `user_id`, of `kind` (`match`, `boat_run`): `{:ok,
result}`. Opts: `:lobby_id` the lobby it runs in, `:visibility` who may
read it (KV's words, atom or string; `owner_only` by default),
`:metadata` what the play is (its settings; never its outcome).

# `stats`

```elixir
@spec stats(Gamend.Results.Result.t() | [String.t()]) :: map()
```

Each event key's `count` and `sum` of `value`, for one result
(`%{"answer" => %{count: 10, sum: 7.0}}`) or a list of result ids (by id:
one query whatever their number). A key whose events carry no value sums
to 0.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
