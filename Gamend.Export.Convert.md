# `Gamend.Export.Convert`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/export/convert.ex#L1)

Another Gamend's rows, copied into this one's database: how a host moves
from a Postgres of its own to a SQLite file, or the other way.

The database adapter is chosen when a release is compiled, and a migration
branches on it, so the copy runs in a build of the adapter it copies *to*,
on a database that build has migrated and nothing has written to. The
source is read through a second repo (`Source`) of the other adapter: both
drivers are in every build.

## What is copied, and as what

Every table both databases have, row for row, each value loaded by the
source's adapter and dumped by this one's through the type its Ecto schema
declares. That is the whole point of going through the schemas: a
timestamp, a UUID, a map and a boolean are each stored differently by the
two, and only the type says how. A table no schema describes is copied by
its columns' own types, and named in the result.

Left out: `schema_migrations` (this database has its own, and the two
must agree before anything is copied) and Oban's tables, whose jobs belong
to the node that queued them. Stop the source's application first: a job
still queued there is not carried over.

## However it ends

One transaction on each side: the source is read as it was when the copy
began, and this database holds every row or none. Foreign keys are checked
once, at the end, since tables are copied in name order and a row may name
one not copied yet. Then each table's rows are counted on both sides.

# `summary`

```elixir
@type summary() :: %{
  tables: [{String.t(), non_neg_integer()}],
  by_column_type: [String.t()],
  not_in_schema: [{String.t(), [String.t()]}],
  gone_migrations: [String.t()]
}
```

# `run`

```elixir
@spec run(module(), keyword()) :: {:ok, summary()} | {:error, term()}
```

Copies every row of `source`, a started repo of another Gamend's database,
into this one's.

`skip:` names tables to leave behind. Answers what it copied:
`tables`, each with its rows; `by_column_type`, the tables no schema
describes; `not_in_schema`, columns of the source a schema has no field
for, which are left at their default; `gone_migrations`, versions the
source ran that this release no longer has.

Refuses, with nothing written:

  * `{:error, {:migrations_differ, only_source, only_here}}` — the source
    is behind this release's migrations, or ahead of them. Deploy this
    version on the source first.
  * `{:error, {:not_empty, table}}` — this database already has rows.
  * `{:error, {:no_table, table, rows}}` — the source has rows in a table
    this database does not have. `skip:` it to leave them.
  * `{:error, {:foreign_keys, violations}}` and
    `{:error, {:rows_differ, table, source, here}}` — the copy is not the
    source, and was rolled back.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
