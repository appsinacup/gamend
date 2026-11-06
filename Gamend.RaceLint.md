# `Gamend.RaceLint`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/race_lint.ex#L1)

Source checks for the shapes that race: a rule ("one per player", "pays
once", "at most N", "only while pending") checked by a read and kept by a
write that does not look again. `mix gamend.race.lint` runs them.

Each check reads one function at a time and asks whether it writes in a
way only an earlier read made safe, with nothing in the same function that
makes the pair atomic: `Gamend.Repo.compare_and_set/2`, `Repo.lock_rows/2`,
`Gamend.Lock.serialize/3` or `exclusive/3`, `Gamend.Lock.Local.trans/2`.
The rule they enforce is AGENTS.md, "Locks".

A call to a function of the same file that is itself guarded counts as a
guard too (`with_pair_lock/3` wrapping `Lock.serialize/3`), through any
number of such helpers.

They are heuristics, and say so: a function that only ever runs inside its
caller's lock reads as unguarded here. Mark it, with the reason, anywhere
inside the function:

    # race-safe: runs inside join_lobby's (:lobby, id) lock

The marker is the point. It puts the reasoning where the next person
changing the function will read it, and the lint keeps asking for one
whenever a new function has the shape.

## Checks

- **RACE1-transition-by-struct** — a status, state or seat column (`status`,
  `lobby_id`, `resolved_at`, …) written by `Repo.update` on a changeset of a
  struct. Whatever the struct said when it was read, two callers can both
  have read it. Write the transition as `compare_and_set/2` with the old
  state in its `where`.
- **RACE2-count-then-insert** — a count (`Repo.aggregate(_, :count)`, a
  `count_*` call, a `*_cap?`/`*_limit*` check, a `Gamend.Limits` read)
  and an insert in one function. Concurrent inserts all pass the count. Take
  the lock of the entity the cap belongs to around both.
- **RACE3-cached-gate** — a struct from a cached read (`Accounts.get_user/1`)
  decides a branch that writes. The cache can be a TTL old. Decide from the
  database inside the transaction (`Gamend.Cache.cached/3` reads the source
  there), or from the row the write answers.

# `violation`

```elixir
@type violation() :: %{
  rule: String.t(),
  file: String.t(),
  line: pos_integer(),
  message: String.t()
}
```

# `rules`

```elixir
@spec rules() :: [{String.t(), String.t()}]
```

The checks, as `{id, description}`.

# `violations`

```elixir
@spec violations() :: [violation()]
```

Every violation under the scan roots, ordered by rule then file.

# `violations_in`

```elixir
@spec violations_in(String.t(), String.t(), [{atom() | nil, atom()}]) :: [violation()]
```

The violations in one file's source. `guards` are the `{alias, function}`
calls that make a function safe (the built-in ones by default).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
