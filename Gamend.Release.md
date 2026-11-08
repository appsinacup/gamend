# `Gamend.Release`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/release.ex#L1)

Release-time equivalents of the `host.*` mix tasks.

A release ships compiled `.beam` files and nothing else — no Mix, no project
tree, no `mix` binary — so `mix db.migrate` cannot run inside an image built
from `Dockerfile.release`. These functions are what the release's own
entrypoint calls instead, usually through `bin/gamend db.migrate` and its
siblings (`GamendWeb.CLI`):

    bin/gamend_host eval "Gamend.Release.createdb()"
    bin/gamend_host eval "Gamend.Release.migrate()"

Under Mix the `host.*` tasks stay the entry point. Both funnel through
`Gamend.Repo.MigrationPaths`, so the two cannot drift on which migrations
they consider.

`eval` starts a fresh node, applies `config/runtime.exs` and runs the
expression **without starting the application**, which is the point: a
migration that fails takes the command down instead of half-booting an
endpoint against a database it does not match.

# `createdb`

```elixir
@spec createdb() :: :ok
```

Creates the database when it does not exist yet, mirroring `mix ecto.create`.

Idempotent: an existing database is left alone. Postgres deployments where
the server provisions the database already can skip this entirely.

# `dropdb`

```elixir
@spec dropdb() :: :ok
```

Drops the database, mirroring `mix ecto.drop`. A database that does not
exist is not an error.

# `export`

```elixir
@spec export(Path.t(), keyword()) :: [String.t()]
```

Copies what only the application can into `dir` (`Gamend.Export`): a SQLite
database and the stored files, or just the database with `files: false`.
Prints what it wrote and raises when it cannot. A running server goes on
serving, so it can run beside one:

    bin/gamend_host eval 'Gamend.Release.export("/tmp/export")'

# `migrate`

```elixir
@spec migrate() :: :ok
```

Runs every pending migration — core's and the host's — on each repo.

# `prepare`

```elixir
@spec prepare() :: :ok
```

What a release runs before it starts serving: create the database when it
can, then migrate. Creating may fail (a provisioned Postgres already has the
database, and its role may not be allowed to create one), which is reported
and passed over; a failed migration raises. `bin/gamend start` and the Docker
image's command both run this.

# `rollback`

```elixir
@spec rollback(keyword()) :: :ok
```

Rolls every repo back, the way `mix db.rollback` does: `step: n` (the last
`n` migrations, 1 when no option is given), `to: version` or `all: true`.

# `rollback`

```elixir
@spec rollback(module(), integer()) :: :ok
```

Rolls `repo` back down to `version`.

# `seeds_file`

```elixir
@spec seeds_file() :: String.t() | nil
```

The project's seeds script, `priv/repo/seeds.exs` in the working directory,
or `nil` when there is none. `mix host.seed` and `gamend db.seed` both run it.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
