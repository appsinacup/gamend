# `Gamend.Export`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/export.ex#L1)

A host's data as files another host can start from: what only the
application can copy.

  * `gamend.db`: a SQLite database, whole and consistent while the server
    runs (`VACUUM INTO`).
  * `files.tar`: what the local storage adapter holds, `storage/` inside.

Nothing else, on purpose. A Postgres database needs `pg_dump` of the
server's major, which the database's container has and the application's
image does not. Objects on S3 are already off the host. `.env` is a file
on the host, which a running application does not have.
`./rebuild.sh --export DIR` (`deploy/gamend-deploy`) gets those and calls
this for the rest. `Gamend.Release.export/2` is the way in from a shell.

# `database?`

```elixir
@spec database?() :: boolean()
```

Whether this host's database is one `write/2` copies: SQLite.

# `write`

```elixir
@spec write(Path.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
```

Writes the files into `dir`, made if missing and private to this user, and
answers the names it wrote. `files: false` leaves the stored files out, for
a host whose folders move with it. A running server goes on serving.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
