# `Gamend.ReadyChecks.Check`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/ready_checks/check.ex#L1)

Ecto schema for one ready check — a *moment* at which a set of players must
each answer before something proceeds.

Two kinds, differing only in what a "no" means and whether an answer can be
taken back (see `Gamend.ReadyChecks`):

  * `"accept"` — one-shot and irrevocable; the first decline fails the whole
    check; the deadline_at is mandatory.
  * `"ready"` — a toggle; a decline just leaves the check pending.

The subject is whichever of `lobby_id`/`party_id` is set — a lobby's
pre-match ready-up or a party's standing ready board. Both nil is a
matchmaking check: at that point the group exists only as its tickets, and
no lobby has been created.

# `t`

```elixir
@type t() :: %Gamend.ReadyChecks.Check{
  __meta__: term(),
  deadline_at: term(),
  id: term(),
  inserted_at: term(),
  kind: term(),
  lobby: term(),
  lobby_id: term(),
  metadata: term(),
  opened_by: term(),
  opened_by_user: term(),
  participants: term(),
  party: term(),
  party_id: term(),
  reason: term(),
  resolved_at: term(),
  seating: term(),
  status: term(),
  updated_at: term()
}
```

# `kinds`

```elixir
@spec kinds() :: [String.t()]
```

The kinds a check may have.

# `statuses`

```elixir
@spec statuses() :: [String.t()]
```

The statuses a check may have.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
