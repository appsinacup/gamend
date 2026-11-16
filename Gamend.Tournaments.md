# `Gamend.Tournaments`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/tournaments.ex#L1)

Bracket tournaments: registration → seeded single-elimination draw → timed
rounds → champions. See TOURNAMENT_DESIGN.md.

Core owns the structure (registration, seeding, rounds, deadlines,
advancement, recurrence). Gameplay and judgment belong to the game: when a
match becomes playable the `tournament_match_ready` hook fires, the game
plays it however it wants (a lobby, solo runs, anything) and reports the
verdict with `resolve_match/2`. Unresolved matches past their deadline_at fire
`tournament_match_expired` for the game to adjudicate; the tournament's
`deadline_policy` applies only if it doesn't.

Realtime: entry leaders receive `{:tournament_event, event, payload}` on the
`"tournaments:user:<user_id>"` PubSub topic (forwarded by the user channel
as `tournament_*` events).

# `advance_lifecycle`

```elixir
@spec advance_lifecycle(Gamend.Tournaments.Tournament.t(), DateTime.t()) ::
  Gamend.Tournaments.Tournament.t()
```

Applies any due state transition to one tournament and returns the current
row. Called lazily from API paths and periodically from `tick/0`.

# `bracket_rounds`

```elixir
@spec bracket_rounds(pos_integer()) :: pos_integer()
```

Rounds needed to win a bracket of `size` slots (2→1, 4→2, 8→3).

# `bracket_size_for`

```elixir
@spec bracket_size_for(pos_integer(), pos_integer()) :: pos_integer()
```

Smallest power of two seating `n` entries, min 2, capped at `max`.

# `cancel_tournament`

```elixir
@spec cancel_tournament(Gamend.Tournaments.Tournament.t()) ::
  {:ok, Gamend.Tournaments.Tournament.t()} | {:error, term()}
```

Cancels a tournament (terminal, no hooks fired, no recurrence spawn).

# `change_tournament`

```elixir
@spec change_tournament(Gamend.Tournaments.Tournament.t(), map()) ::
  Ecto.Changeset.t()
```

# `count_brackets`

```elixir
@spec count_brackets(Ecto.UUID.t()) :: non_neg_integer()
```

# `count_entries`

```elixir
@spec count_entries(Ecto.UUID.t(), keyword()) :: non_neg_integer()
```

Counts entries. Accepts the same `:state` and `:search` options as the listing.

# `count_tournament_groups`

```elixir
@spec count_tournament_groups() :: non_neg_integer()
```

Counts distinct tournament slugs.

# `count_tournaments`

```elixir
@spec count_tournaments(keyword()) :: non_neg_integer()
```

# `create_tournament`

```elixir
@spec create_tournament(map()) ::
  {:ok, Gamend.Tournaments.Tournament.t()} | {:error, Ecto.Changeset.t()}
```

# `delete_tournament`

```elixir
@spec delete_tournament(Gamend.Tournaments.Tournament.t()) ::
  {:ok, Gamend.Tournaments.Tournament.t()} | {:error, term()}
```

# `entries_by_id`

```elixir
@spec entries_by_id(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{
  required(Ecto.UUID.t()) =&gt; Gamend.Tournaments.Entry.t()
}
```

Entries by id, for rendering a bracket without loading the whole field.

# `get_bracket`

```elixir
@spec get_bracket(Ecto.UUID.t(), integer()) :: Gamend.Tournaments.Bracket.t() | nil
```

# `get_entry`

```elixir
@spec get_entry(Ecto.UUID.t(), Ecto.UUID.t()) :: Gamend.Tournaments.Entry.t() | nil
```

# `get_match`

```elixir
@spec get_match(Ecto.UUID.t()) :: Gamend.Tournaments.Match.t() | nil
```

# `get_tournament`

```elixir
@spec get_tournament(Ecto.UUID.t()) :: Gamend.Tournaments.Tournament.t() | nil
```

# `get_tournament!`

```elixir
@spec get_tournament!(Ecto.UUID.t()) :: Gamend.Tournaments.Tournament.t()
```

# `get_tournament_by_slug`

```elixir
@spec get_tournament_by_slug(String.t()) :: Gamend.Tournaments.Tournament.t() | nil
```

The current occurrence for a slug: the latest one that is not finished or
cancelled, falling back to the most recent row.

# `join_tournament`

```elixir
@spec join_tournament(Gamend.Accounts.User.t(), Gamend.Tournaments.Tournament.t()) ::
  {:ok, Gamend.Tournaments.Entry.t()}
  | {:error,
     :account_required
     | :registration_closed
     | :already_registered
     | :tournament_full
     | :not_found
     | Ecto.Changeset.t()
     | {:hook_rejected, term()}}
```

Registers `user` as an entry leader.

The seat is taken first, under the tournament's join lock with the
capacity and duplicate checks, and only then does the
`before_tournament_register` pipeline run (games gate or charge entry
there), outside any lock, with the seat held: a full tournament, closed
registration or a repeated request is refused before it and never reaches
it. When the hook refuses (or raises, or times out) the seat is given back
and its refusal answered; in a tournament drawn while the hook ran, the
refused entry forfeits its match instead. `after_tournament_register` fires
only once the hook allowed it.

Refuses with `:registration_closed`, `:already_registered`,
`:tournament_full`, `:not_found` (deleted meanwhile), a changeset, or
`{:hook_rejected, reason}` with the hook's own reason. A guest is refused
with `:account_required` where the host requires an account to enter
(`Gamend.AccountRequired`, `:tournaments`), before anything else.

# `leave_tournament`

```elixir
@spec leave_tournament(Gamend.Accounts.User.t(), Gamend.Tournaments.Tournament.t()) ::
  {:ok, Gamend.Tournaments.Tournament.t()}
  | {:error,
     :not_registered | :already_drawn | :not_found | {:hook_rejected, term()}}
```

Withdraws `user`'s entry. Only before the draw; `before_tournament_leave` can
veto, answered as `{:hook_rejected, reason}`.

# `list_brackets`

```elixir
@spec list_brackets(Ecto.UUID.t(), keyword()) :: [Gamend.Tournaments.Bracket.t()]
```

Brackets for a tournament. Options: `:page`, `:page_size`.

# `list_entries`

```elixir
@spec list_entries(Ecto.UUID.t(), keyword()) :: [Gamend.Tournaments.Entry.t()]
```

Entries for a tournament, oldest first (registration order = seed rank).

Options: `:page`, `:page_size` (capped at 100), `:state`, plus

  * `:search` — filter by leader name (display name or username)
  * `:preload_leader` — preload the leader, for callers that render names
  * `:order` — `:bracket` groups drawn entries by bracket and seed instead

# `list_matches`

```elixir
@spec list_matches(Ecto.UUID.t(), keyword()) :: [Gamend.Tournaments.Match.t()]
```

Matches for a tournament, bracket-major order.

Options: `:bracket_index` (single bracket), `:bracket_indexes` (several).

# `list_occurrences`

```elixir
@spec list_occurrences(String.t()) :: [Gamend.Tournaments.Tournament.t()]
```

Every occurrence of a slug, newest first.

# `list_tournament_groups`

```elixir
@spec list_tournament_groups(keyword()) :: [map()]
```

Tournaments grouped by slug — one entry per tournament *type*, the way
leaderboard seasons are grouped.

Each group carries the newest occurrence's title/description, the id of the
occurrence to open by default (the live one, else the newest), and how many
editions exist.

# `list_tournaments`

```elixir
@spec list_tournaments(keyword()) :: [Gamend.Tournaments.Tournament.t()]
```

# `match_index`

```elixir
@spec match_index(non_neg_integer(), pos_integer()) :: non_neg_integer()
```

The match a slot reaches in `round` (standard folding).

# `match_payload`

```elixir
@spec match_payload(Gamend.Tournaments.Tournament.t(), Gamend.Tournaments.Match.t()) ::
  Gamend.Tournaments.Match.t()
```

The match struct with tournament and both entries preloaded (hook payload).

# `merge_user_entries`

```elixir
@spec merge_user_entries(Ecto.UUID.t(), Ecto.UUID.t()) :: non_neg_integer()
```

Moves `from_user_id`'s entries onto `to_user_id`, the way a guest's play
joins the account they log in to (`Gamend.Accounts.GuestMerge`). An entry
in a tournament the account has not entered becomes the account's, with
its seed, bracket, wins and matches (a game's match metadata keyed by the
entry's id with them), so a guest who joined, or is playing, goes on as the
account. No hook fires: the entry was registered once.

Where the account has its own entry in that tournament, the account's
stands and the guest's leaves the field: withdrawn before the draw (its
seat given back), forfeited while it runs (its opponent advances, as
against a withdrawal), and left to go with the guest account once the
tournament is over. Answers how many entries reached the account.

# `my_match`

```elixir
@spec my_match(Gamend.Tournaments.Tournament.t(), Ecto.UUID.t()) ::
  Gamend.Tournaments.Match.t() | nil
```

The caller's current unresolved match (their entry filled in a slot), if any.

# `reopen_tournament`

```elixir
@spec reopen_tournament(Gamend.Tournaments.Tournament.t()) ::
  {:ok, Gamend.Tournaments.Tournament.t()} | {:error, term()}
```

Reopens a cancelled tournament.

A tournament that was never drawn goes back to `registration`; one that
already has a bracket resumes at `running`, so an accidental cancel does not
throw away the draw. Any due transition is applied immediately afterwards.

# `resolve_match`

```elixir
@spec resolve_match(Ecto.UUID.t(), Ecto.UUID.t() | :no_winner) ::
  {:ok, Gamend.Tournaments.Match.t()}
  | {:error,
     :not_found | :already_resolved | :invalid_winner | {:hook_rejected, term()}}
```

Records the verdict for a match: the winning entry's id, or `:no_winner`
(double forfeit — the next round's seat stays empty and cascades as a bye).

First write wins; anything later returns `{:error, :already_resolved}`. The
`before_tournament_result` pipeline can veto, leaving the match open: its
reason comes back as `{:hook_rejected, reason}`.

# `round_deadline`

```elixir
@spec round_deadline(Gamend.Tournaments.Tournament.t(), pos_integer()) :: DateTime.t()
```

Unix-independent deadline_at for `round`, anchored to `starts_at`.

# `round_matches`

```elixir
@spec round_matches(pos_integer(), pos_integer()) :: pos_integer()
```

Matches in `round` of a bracket of `size` slots.

# `round_opens_at`

```elixir
@spec round_opens_at(Gamend.Tournaments.Tournament.t(), pos_integer()) :: DateTime.t()
```

When `round` becomes playable (its window start).

# `standard_seed_order`

```elixir
@spec standard_seed_order(pos_integer()) :: [pos_integer()]
```

Standard single-elimination seeding order for a power-of-two `size`:
slot `i` holds this seed rank (1-based); top seeds are spread apart.

# `standings`

```elixir
@spec standings(Gamend.Tournaments.Tournament.t()) :: map()
```

Final (or current) placements: champions first, then by wins.

# `stats`

```elixir
@spec stats() :: %{
  tournaments: map(),
  entries: map(),
  matches: %{
    total: non_neg_integer(),
    open: non_neg_integer(),
    overdue: non_neg_integer()
  }
}
```

Aggregate counts for the admin dashboard.

Four grouped/filtered queries, all index-backed (`tournaments.state`,
`tournament_entries.state`, and the partial `tournament_matches` index on
open matches).

# `tick`

```elixir
@spec tick(DateTime.t()) :: :ok
```

Periodic driver, called by `Gamend.Tournaments.Ticker`. Runs every
transition, match-ready firing, deadline_at sweep, and recurrence spawn that is
due. Serialized cluster-wide so hooks fire once.

# `update_match_metadata`

```elixir
@spec update_match_metadata(Ecto.UUID.t(), map()) ::
  {:ok, Gamend.Tournaments.Match.t()} | {:error, term()}
```

Deep-merges `map` into the match's metadata (game scratch space).

Serialized per match and merged recursively so concurrent writers touching
different nested keys (e.g. each player's run under `"runs"`) never clobber
each other.

# `update_tournament`

```elixir
@spec update_tournament(Gamend.Tournaments.Tournament.t(), map()) ::
  {:ok, Gamend.Tournaments.Tournament.t()} | {:error, Ecto.Changeset.t()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
