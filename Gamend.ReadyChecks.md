# `Gamend.ReadyChecks`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/ready_checks.ex#L1)

Ready checks: *these players must each answer before this proceeds*.

One primitive, two kinds — the only differences are what a "no" means and
whether an answer can be taken back:

| | `"accept"` | `"ready"` |
| --- | --- | --- |
| Answer | one-shot, irrevocable | a toggle |
| A "no" | fails the check for everyone | leaves it pending |
| Deadline | mandatory | optional |
| On timeout | fails | fails, naming who stalled |

`"ready"` is the lobby's ready-up and the party's standing ready board;
`"accept"` is matchmaking's match confirmation (see
the moduledoc below).

## Two lanes

A player can be in at most one open check *per lane*: the match lane (lobby
ready or matchmaking accept — one match at a time) and the party lane. The
lanes are independent, so a party's standing board never blocks the party's
lobby from opening its own check.

## What core does *not* do

A failed check kicks nobody, deletes no lobby and moves no lobby state. Core
records who did not answer (`not_ready/1`); the host — or the game, in
`after_ready_check_failed` — decides what that is worth.

## Usage

    {:ok, check} = ReadyChecks.open(lobby, member_ids, opened_by: host.id)
    {:ok, check} = ReadyChecks.respond(user, true)
    ReadyChecks.passed?(lobby)

## Concurrency

Answering is a single-row write, so no two players can lose each other's
flag. *Evaluating* the result is the part that races: two players answering
at once can each count the other as still pending, and nobody passes. So
`respond/3` holds a per-check advisory lock (`:ready_check`) around
write-then-evaluate. Hooks and broadcasts fire after the lock is released —
never inside the transaction.

# `answer`

```elixir
@type answer() :: boolean()
```

# `scope`

```elixir
@type scope() :: :match | :party
```

# `subject`

```elixir
@type subject() :: Gamend.Lobbies.Lobby.t() | Gamend.Parties.Party.t() | :matchmaking
```

# `add_member`

```elixir
@spec add_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
```

Adds a member to the lobby's open check, if there is one.

Call it inside the transaction that seats them, under the lobby's lock, as
`Gamend.Lobbies` and `Gamend.Parties` do: the check then either takes the
seat before it counts the next answer, or passed before the seat existed.

# `add_party_member`

```elixir
@spec add_party_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
```

Adds a member to the party's open check, if there is one. As `add_member/2`.

# `answer_for`

```elixir
@spec answer_for(Gamend.ReadyChecks.Check.t(), Ecto.UUID.t(), answer()) ::
  {:ok, Gamend.ReadyChecks.Check.t()} | {:error, term()}
```

Answers on behalf of a member — for bots and AI-controlled players, which
cannot press anything.

Server-side only: this is in `internal_hooks()`, so a client cannot reach it
over RPC and mark someone else ready.

# `cancel`

```elixir
@spec cancel(Gamend.ReadyChecks.Check.t(), String.t()) ::
  {:ok, Gamend.ReadyChecks.Check.t()}
  | {:error, :already_resolved | :no_open_check}
```

Cancels a pending check — the host called it off, or the subject went away.

# `cancel_for_lobby`

```elixir
@spec cancel_for_lobby(Ecto.UUID.t()) ::
  :ok | {:error, :already_resolved | :no_open_check}
```

Cancels the lobby's pending check, if it has one.

`{:error, :already_resolved}` when it passed or failed before the cancel
took its lock (or `:no_open_check` when it went with its lobby): it was
read pending, and the cancel did not happen.

# `cancel_for_party`

```elixir
@spec cancel_for_party(Ecto.UUID.t()) ::
  :ok | {:error, :already_resolved | :no_open_check}
```

Cancels the party's pending check, if it has one. As `cancel_for_lobby/1`.

# `count_checks`

```elixir
@spec count_checks(keyword()) :: non_neg_integer()
```

Counts checks matching the same filters as `list_checks/1`.

# `expire`

```elixir
@spec expire(Gamend.ReadyChecks.Check.t()) :: :ok | :noop
```

Fails one check on its deadline_at. A no-op if it already resolved.

# `expire_due`

```elixir
@spec expire_due(DateTime.t()) :: non_neg_integer()
```

Fails every pending check whose deadline_at has passed.

Each still-unanswered participant becomes `timed_out`. Returns how many
checks were expired. Idempotent, so the durable expiry job and the
matchmaking sweep's backstop can both run it.

# `for_user`

```elixir
@spec for_user(Gamend.Accounts.User.t() | Ecto.UUID.t(), scope() | :any) ::
  Gamend.ReadyChecks.Check.t() | nil
```

The caller's open check, with participants preloaded, or nil.

`scope` narrows to one lane: `:match` (lobby or matchmaking) or `:party`.
`:any` returns the newest across both lanes — the admin's view, not the
API's.

# `get_check`

```elixir
@spec get_check(Ecto.UUID.t()) :: Gamend.ReadyChecks.Check.t() | nil
```

Fetches a check by id (with participants), or nil.

# `list_checks`

```elixir
@spec list_checks(keyword()) :: [Gamend.ReadyChecks.Check.t()]
```

Lists checks for the admin views, newest first.

Options: `:status`, `:kind`, `:lobby_id`, `:party_id`, `:page`,
`:page_size`.

# `not_ready`

```elixir
@spec not_ready(Gamend.ReadyChecks.Check.t()) :: [Gamend.ReadyChecks.Participant.t()]
```

The participants who did not answer ready — the host's kick list, and what
`after_ready_check_failed` is handed.

# `open`

```elixir
@spec open(subject(), [Ecto.UUID.t()] | :members, keyword()) ::
  {:ok, Gamend.ReadyChecks.Check.t()} | {:error, term()}
```

Opens a check over `user_ids` and notifies them.

`subject` is a `%Lobby{}` or `%Party{}` (kind `"ready"`) or `:matchmaking`
(kind `"accept"`). For a lobby or a party, `user_ids` may be `:members`:
every member, read again under the subject's lock as the check is written,
so a member who joins or leaves while it opens is on the board exactly when
they are in the lobby or party. `before_ready_check_open` sees the members
as read before that lock. Options:

  * `:kind` — override the kind implied by the subject
  * `:timeout_ms` — answering window; `nil` leaves a `"ready"` check open
    until it passes or is cancelled. Defaults to `ready_check_timeout_ms`.
  * `:opened_by` — the user who asked for it; they are pre-marked ready,
    since clicking the button is their answer
  * `:ready` — user ids to pre-mark ready (bots, an auto-ready mode)
  * `:tickets` — `%{user_id => ticket_id}` for matchmaking checks
  * `:metadata` — game payload echoed to clients (match params, mode)
  * `:seating` — where a matchmaking check's match sits once accepted
    (`Gamend.MatchSeating.dump/1`), never sent to clients

Fails with `{:error, :already_pending}` when the subject already has an open
check or any player is in one in the same lane, `{:error, :no_participants}`,
and `{:error, :too_many_participants}` past `max_ready_check_participants`.

# `passed?`

```elixir
@spec passed?(Gamend.Lobbies.Lobby.t() | Gamend.Parties.Party.t() | Ecto.UUID.t()) ::
  boolean()
```

True when the subject's most recent check passed.

What a game calls from `before_lobby_state_change` to gate its own start.
A reset opens a fresh pending check, which makes this false again — so a
rematch cannot ride the previous match's pass.

# `pending_for_lobby`

```elixir
@spec pending_for_lobby(Ecto.UUID.t()) :: Gamend.ReadyChecks.Check.t() | nil
```

The lobby's open check, with participants preloaded, or nil.

# `pending_for_party`

```elixir
@spec pending_for_party(Ecto.UUID.t()) :: Gamend.ReadyChecks.Check.t() | nil
```

The party's open check, with participants preloaded, or nil.

# `remove_member`

```elixir
@spec remove_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
```

Drops a member from the lobby's open check and re-evaluates it.

Called when someone leaves or is kicked: kicking the one player who never
answered is a legitimate way to pass a check.

# `remove_party_member`

```elixir
@spec remove_party_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
```

Drops a member from the party's open check and re-evaluates it.

# `reset`

```elixir
@spec reset(subject(), [Ecto.UUID.t()] | :members, keyword()) ::
  {:ok, Gamend.ReadyChecks.Check.t()} | {:error, term()}
```

Resets the subject's board: quietly cancels its pending check (no failed
event, no hook — the fresh `ready_check_started` replaces it on clients) and
opens a new one over `user_ids`.

The one verb behind every "answers are stale now" moment: a match ended
(rematch needs a fresh board), the game mode changed, a member joined a
party whose board had already resolved, or the host wants everyone to
re-confirm on a deadline_at ("force ready"). Same options as `open/3`.

# `respond`

```elixir
@spec respond(Gamend.Accounts.User.t() | Ecto.UUID.t(), answer(), scope()) ::
  {:ok, Gamend.ReadyChecks.Check.t()} | {:error, term()}
```

Records the caller's answer to their open check in `scope` and re-evaluates
it.

`scope` is `:match` (the lobby ready-up or matchmaking accept — the default)
or `:party` (the party's standing board): a player can hold one open check
in each lane, so the answer needs to say which one it is for.

`true` is "ready"/"accept"; `false` is "not ready"/"decline". In an `accept`
check a decline fails the whole check; in a `ready` check it just leaves the
check pending and can be taken back.

A `ready` board that ran out of time is still answerable: the deadline
passing is the weakest kind of no — nobody refused, the clock did — and the
board is still the one on everyone's screen. A late yes lands like any other
and passes the board if it was the last one missing. (An `accept` check is
not: its timeout has already released the tickets and re-queued everyone.)

Returns the check as it stands after the answer. Fails with
`{:error, :no_open_check}` and, for an `accept` check the caller already
answered, `{:error, :not_revocable}`.

# `stats`

```elixir
@spec stats(pos_integer()) :: %{required(String.t()) =&gt; non_neg_integer()}
```

Counts by status over the last `hours` — the accept-rate and dodge-rate
numbers on the admin page.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
