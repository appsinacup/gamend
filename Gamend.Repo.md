# `Gamend.Repo`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/repo.ex#L1)

# `aggregate`

# `aggregate`

# `all`

# `all_by`

# `checked_out?`

# `checkout`

# `child_spec`

# `compare_and_set`

```elixir
@spec compare_and_set(Ecto.Queryable.t(), keyword()) ::
  {:ok, Ecto.Schema.t()} | {:error, :precondition_failed}
```

Updates the one row `query` matches, only while it still matches, and
answers that row as the database now holds it.

The way to keep a rule that a read made earlier cannot: put the
precondition in `query`, and the statement either finds the row still in
that state and changes it, or finds nothing and answers
`{:error, :precondition_failed}`. Check and write are one statement, so two
callers racing cannot both pass, on either adapter or across nodes, and no
lock is taken beyond the row the `UPDATE` writes.

The row comes back through `RETURNING`, so it is never a copy read before
the write. On Postgres a writer that waited for another's commit re-checks
the condition against the committed row and answers that newer version: a
side the other transaction filled in is there.

    from(p in QuestProgress,
      where: p.id == ^id and p.status == "completed" and p.claim_count == ^seen
    )
    |> Repo.compare_and_set(set: [status: "claimed"], inc: [lock_version: 1])

`query` must pin one row: its primary key or a unique index, plus the
precondition. Matching several is a bug, and raises.

# `config`

# `default_options`

# `delete`

# `delete!`

# `delete_all`

# `disconnect_all`

```elixir
@spec disconnect_all(non_neg_integer(), opts :: Keyword.t()) :: :ok
```

Forces all connections in the repo pool to disconnect within the given interval.

Once this function is called, the pool will disconnect all of its connections
as they are checked in or as they are pinged. Checked in and idle connections
will be randomly disconnected within the given time interval.

If the connection has a backoff configured (which is the case by default),
disconnecting means an attempt at a new connection will be done immediately
after, without starting a new process for each connection. However, if backoff
has been disabled, the connection process will terminate. In such cases,
disconnecting all connections may cause the pool supervisor to restart
depending on the max_restarts/max_seconds configuration of the pool,
so you will want to set those carefully.

If you need connections to be restarted periodically, set the `:max_lifetime`
option in your repository configuration instead.

# `durable_transaction`

```elixir
@spec durable_transaction((-&gt; result), keyword()) :: {:ok, result} | {:error, term()}
when result: term()
```

Run `fun` in a transaction whose commit is on disk before it returns.

`db.postgres_synchronous_commit` is an app-wide durability choice, and `off`
is a reasonable one for game data: an OS crash loses a few hundred
milliseconds of commits, nothing is corrupted, and a player re-earns a
little progress. That trade is wrong for money — a purchase the provider has
already charged for must not be the thing that disappears.

`SET LOCAL` raises `synchronous_commit` back to `on` for this transaction
only, so payments stay durable whatever the global setting is, and every
other write keeps the faster commit. It costs one fsync per payment, which
is not a path that needs throughput.

A no-op on SQLite: durability there is `db.sqlite_synchronous`, a
connection-wide pragma with no per-transaction override.

# `escape_like`

```elixir
@spec escape_like(String.t()) :: String.t()
```

Escapes `LIKE` wildcards (`%`, `_`) and the escape character (`\`) in
user-supplied search input so it matches literally.

Queries must pair the escaped pattern with an explicit escape clause,
because SQLite (unlike Postgres) has no default `LIKE` escape character:

    fragment("? LIKE ? ESCAPE '\\'", u.name, ^("%" <> Repo.escape_like(term) <> "%"))

# `exists?`

# `explain`

```elixir
@spec explain(
  :all | :update_all | :delete_all,
  Ecto.Queryable.t(),
  opts :: Keyword.t()
) ::
  String.t() | Exception.t() | [map()]
```

Executes an EXPLAIN statement or similar for the given query according to its kind and the
adapter in the given repository.

## Examples

    # Postgres
    iex> MyRepo.explain(:all, Post)
    "Seq Scan on posts p0  (cost=0.00..12.12 rows=1 width=443)"

    iex> Ecto.Adapters.SQL.explain(Repo, :all, Post)
    "Seq Scan on posts p0  (cost=0.00..12.12 rows=1 width=443)"

    # MySQL
    iex> MyRepo.explain(:all, from(p in Post, where: p.title == "title")) |> IO.puts()
    +----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------------+
    | id | select_type | table | partitions | type | possible_keys | key  | key_len | ref  | rows | filtered | Extra       |
    +----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------------+
    |  1 | SIMPLE      | p0    | NULL       | ALL  | NULL          | NULL | NULL    | NULL |    1 |    100.0 | Using where |
    +----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------------+

    # Shared opts
    iex> MyRepo.explain(:all, Post, analyze: true, timeout: 20_000)
    "Seq Scan on posts p0  (cost=0.00..11.70 rows=170 width=443) (actual time=0.013..0.013 rows=0 loops=1)\nPlanning Time: 0.031 ms\nExecution Time: 0.021 ms"

It's safe to execute it for updates and deletes, no data change will be committed:

    iex> MyRepo.explain(Repo, :update_all, from(p in Post, update: [set: [title: "new title"]]))
    "Update on posts p0  (cost=0.00..11.70 rows=170 width=449)\n  ->  Seq Scan on posts p0  (cost=0.00..11.70 rows=170 width=449)"

This function is also available under the repository with name `explain`:

    iex> MyRepo.explain(:all, from(p in Post, where: p.title == "title"))
    "Seq Scan on posts p0  (cost=0.00..12.12 rows=1 width=443)\n  Filter: ((title)::text = 'title'::text)"

### Options

Built-in adapters support passing `opts` to the EXPLAIN statement according to the following:

Adapter          | Supported opts
---------------- | --------------
Postgrex         | `analyze`, `verbose`, `costs`, `settings`, `buffers`, `timing`, `summary`, `format`, `plan`, `wrap_in_transaction`
MyXQL            | `format`, `wrap_in_transaction`

All options except `format` are boolean valued and default to `false`.

The allowed `format` values are `:map`, `:yaml`, and `:text`:
  * `:map` is the deserialized JSON encoding.
  * `:yaml` and `:text` return the result as a string.

The built-in adapters support the following formats:
  * Postgrex: `:map`, `:yaml` and `:text`
  * MyXQL: `:map` and `:text`

The `wrap_in_transaction` option is a boolean that controls whether the command is run inside of a
transaction that is rolled back. This is useful when, for example, you'd like to use `analyze: true`
on an update or delete query without modifying data. Defaults to `true`.

The `:plan` option in Postgrex can take the values `:custom` or `:fallback_generic`. When `:custom`
is specified, the explain plan generated will consider the specific values of the query parameters
that are supplied. When using `:fallback_generic`, the specific values of the query parameters will
be ignored. `:fallback_generic` does not use PostgreSQL's built-in support for a generic explain
plan (available as of PostgreSQL 16), but instead uses a special implementation that works for PostgreSQL
versions 12 and above. Defaults to `:custom`.

Any other value passed to `opts` will be forwarded to the underlying adapter query function, including
shared Repo options such as `:timeout`. Non built-in adapters may have specific behaviour and you should
consult their documentation for more details.

For version compatibility, please check your database's documentation:

  * _Postgrex_: [PostgreSQL doc](https://www.postgresql.org/docs/current/sql-explain.html).
  * _MyXQL_: [MySQL doc](https://dev.mysql.com/doc/refman/8.0/en/explain.html).

# `get`

# `get!`

# `get_by`

# `get_by!`

# `get_dynamic_repo`

# `get_uuid`

```elixir
@spec get_uuid(Ecto.Queryable.t(), term(), Keyword.t()) :: Ecto.Schema.t() | nil
```

Like `get/3`, but returns `nil` (instead of raising `Ecto.Query.CastError`)
when `id` is not a valid UUID. Use for lookups whose id comes from external
input (URL params, channel payloads, hook args).

# `get_uuid!`

```elixir
@spec get_uuid!(Ecto.Queryable.t(), term(), Keyword.t()) :: Ecto.Schema.t()
```

Like `get!/3`, but raises `Ecto.NoResultsError` (instead of
`Ecto.Query.CastError`) when `id` is not a valid UUID, so invalid ids from
external input surface as 404s rather than 400s.

# `in_transaction?`

# `insert`

# `insert!`

# `insert_all`

# `insert_or_update`

# `insert_or_update!`

# `load`

# `lock_rows`

```elixir
@spec lock_rows(Ecto.Queryable.t(), :update | :no_key_update | :share) ::
  Ecto.Queryable.t()
```

Locks the rows `query` reads until the transaction ends: `:update` against
every other locker and writer, `:share` against writers only, so holders of
`:share` run side by side.

`:no_key_update` is the lock an `UPDATE` of non-key columns takes: it
excludes other writers and lockers, but not the `FOR KEY SHARE` a foreign
key check takes on the row it points at. Use it to read a row you are
about to update in a transaction that may also insert a row referencing
it. `:update` there deadlocks: two such transactions each hold the other's
key share and wait for it.

Postgres only. SQLite has no row locks (`FOR UPDATE` raises there), and its
single writer under `default_transaction_mode: :immediate` already runs every
write transaction alone, so there the query comes back unchanged.

# `one`

# `one!`

# `preload`

# `prepare_query`

# `prepare_transaction`

# `put_dynamic_repo`

# `query`

```elixir
@spec query(iodata(), Ecto.Adapters.SQL.query_params(), Keyword.t()) ::
  {:ok, Ecto.Adapters.SQL.query_result()} | {:error, Exception.t()}
```

Runs a custom SQL query.

If the query was successful, it will return an `:ok` tuple containing
a map with at least two keys:

  * `:num_rows` - the number of rows affected
  * `:rows` - the result set as a list. `nil` may be returned
    instead of the list if the command does not yield any row
    as result (but still yields the number of affected rows,
    like a `delete` command without returning would)

## Options

  * `:log` - When false, does not log the query
  * `:timeout` - Execute request timeout, accepts: `:infinity` (default: `15000`);

## Examples

    iex> MyRepo.query("SELECT $1::integer + $2", [40, 2])
    {:ok, %{rows: [[42]], num_rows: 1}}

    iex> Ecto.Adapters.SQL.query(MyRepo, "SELECT $1::integer + $2", [40, 2])
    {:ok, %{rows: [[42]], num_rows: 1}}

# `query!`

```elixir
@spec query!(iodata(), Ecto.Adapters.SQL.query_params(), Keyword.t()) ::
  Ecto.Adapters.SQL.query_result()
```

Same as `query/3` but returns result directly without `:ok` tuple
and raises on invalid queries

# `query_many`

```elixir
@spec query_many(iodata(), Ecto.Adapters.SQL.query_params(), Keyword.t()) ::
  {:ok, [Ecto.Adapters.SQL.query_result()]} | {:error, Exception.t()}
```

Runs a custom SQL query that returns multiple results on the given repo.

In case of success, it must return an `:ok` tuple containing a list of
maps with at least two keys:

  * `:num_rows` - the number of rows affected

  * `:rows` - the result set as a list. `nil` may be returned
    instead of the list if the command does not yield any row
    as result (but still yields the number of affected rows,
    like a `delete` command without returning would)

## Options

  * `:log` - When false, does not log the query
  * `:timeout` - Execute request timeout, accepts: `:infinity` (default: `15000`);

## Examples

    iex> MyRepo.query_many("SELECT $1; SELECT $2;", [40, 2])
    {:ok, [%{rows: [[40]], num_rows: 1}, %{rows: [[2]], num_rows: 1}]}

    iex> Ecto.Adapters.SQL.query_many(MyRepo, "SELECT $1; SELECT $2;", [40, 2])
    {:ok, [%{rows: [[40]], num_rows: 1}, %{rows: [[2]], num_rows: 1}]}

# `query_many!`

```elixir
@spec query_many!(iodata(), Ecto.Adapters.SQL.query_params(), Keyword.t()) :: [
  Ecto.Adapters.SQL.query_result()
]
```

Same as `query_many/4` but returns result directly without `:ok` tuple
and raises on invalid queries

# `reload`

# `reload!`

# `rescue_foreign_key`

```elixir
@spec rescue_foreign_key(term(), (-&gt; result)) :: result | {:error, term()}
when result: term()
```

Runs `fun`, answering `{:error, reason}` when it violates a foreign key --
however the adapter reports it.

The contexts check the referenced row exists first
(`Gamend.Accounts.user_exists?/1`), but the row can still be deleted between
that check and the write. This closes that window: the race answers like the
check would have, instead of a 500 or a changeset.

The adapters report the violation differently, which is why both forms are
handled here:

  * SQLite, the default, does not say *which* constraint an INSERT violated,
    so `Ecto.Changeset.foreign_key_constraint/2` cannot match and Ecto raises
    `Ecto.ConstraintError`.
  * Postgres names the constraint, so the changeset declaration matches and
    `fun` returns `{:error, changeset}` -- or `{:error, {tag, changeset}}`
    from a context that tags its failures -- with a `constraint: :foreign`
    error on the key.

Handling only the first answered `:user_not_found` on SQLite and a
validation changeset on Postgres for the same race. Any other constraint
error is re-raised, and any other error result is returned as it was.

# `rescue_stale`

```elixir
@spec rescue_stale(term(), (-&gt; result)) :: result | {:error, term()}
when result: term()
```

Runs `fun`, answering `{:error, reason}` when the row it updates or deletes
was deleted first.

A struct read before a concurrent delete still names its row, and
`Repo.update/2` or `Repo.delete/2` on it raises `Ecto.StaleEntryError`. This
is the companion to `rescue_foreign_key/2` for that window: the race answers
as a read after the delete would have, instead of a 500. Both adapters raise
the same error, so there is one form to handle.

# `rollback`

```elixir
@spec rollback(term()) :: no_return()
```

# `search_pattern`

```elixir
@spec search_pattern(term()) :: String.t() | nil
```

Builds a case-insensitive "contains" `LIKE` pattern from user search input,
or `nil` when the input is blank and the caller should not filter at all.

Pair it with a lowercased column so both adapters agree on case:

    fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.username, ^pattern)

# `start_link`

# `stop`

# `stream`

# `to_sql`

```elixir
@spec to_sql(:all | :update_all | :delete_all, Ecto.Queryable.t(), Keyword.t()) ::
  {String.t(), Ecto.Adapters.SQL.query_params()}
```

Converts the given query to SQL according to its kind and the
adapter in the given repository.

## Examples

The examples below are meant for reference. Each adapter will
return a different result:

    iex> MyRepo.to_sql(:all, Post)
    {"SELECT p.id, p.title, p.inserted_at, p.created_at FROM posts as p", []}

    iex> MyRepo.to_sql(:update_all, from(p in Post, update: [set: [title: ^"hello"]]))
    {"UPDATE posts AS p SET title = $1", ["hello"]}

    iex> Ecto.Adapters.SQL.to_sql(:all, MyRepo, Post)
    {"SELECT p.id, p.title, p.inserted_at, p.created_at FROM posts as p", []}

# `transact`

# `transaction`

# `update`

# `update!`

# `update_all`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
