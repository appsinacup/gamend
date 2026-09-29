defmodule Gamend.Release do
  @moduledoc """
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
  """

  alias Gamend.Repo.MigrationPaths

  @otp_app :gamend_core

  @doc """
  Runs every pending migration — core's and the host's — on each repo.
  """
  @spec migrate() :: :ok
  def migrate, do: run_migrations(repos(), :up, all: true)

  @doc """
  Rolls `repo` back down to `version`.
  """
  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version), do: run_migrations([repo], :down, to: version)

  @doc """
  Rolls every repo back, the way `mix db.rollback` does: `step: n` (the last
  `n` migrations, 1 when no option is given), `to: version` or `all: true`.
  """
  @spec rollback(keyword()) :: :ok
  def rollback(opts) when is_list(opts) do
    run_migrations(repos(), :down, if(opts == [], do: [step: 1], else: opts))
  end

  @doc """
  Creates the database when it does not exist yet, mirroring `mix ecto.create`.

  Idempotent: an existing database is left alone. Postgres deployments where
  the server provisions the database already can skip this entirely.
  """
  @spec createdb() :: :ok
  def createdb, do: storage(:storage_up, :already_up, "create")

  @doc """
  Drops the database, mirroring `mix ecto.drop`. A database that does not
  exist is not an error.
  """
  @spec dropdb() :: :ok
  def dropdb, do: storage(:storage_down, :already_down, "drop")

  @doc """
  What a release runs before it starts serving: create the database when it
  can, then migrate. Creating may fail (a provisioned Postgres already has the
  database, and its role may not be allowed to create one), which is reported
  and passed over; a failed migration raises. `bin/gamend start` and the Docker
  image's command both run this.
  """
  @spec prepare() :: :ok
  def prepare do
    try do
      createdb()
    rescue
      error -> IO.puts(:stderr, "warning: " <> Exception.message(error))
    end

    migrate()
  end

  @doc """
  The project's seeds script, `priv/repo/seeds.exs` in the working directory,
  or `nil` when there is none. `mix host.seed` and `gamend db.seed` both run it.
  """
  @spec seeds_file() :: String.t() | nil
  def seeds_file do
    path = Path.expand("priv/repo/seeds.exs")
    if File.regular?(path), do: path
  end

  defp run_migrations(repos, direction, opts) do
    paths = migration_paths()

    for repo <- repos do
      {:ok, _versions, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, paths, direction, opts))
    end

    :ok
  end

  defp storage(fun, already, verb) do
    for repo <- repos() do
      start_driver(repo)

      case apply(repo.__adapter__(), fun, [repo.config()]) do
        :ok ->
          :ok

        {:error, ^already} ->
          :ok

        {:error, reason} ->
          raise "could not #{verb} storage for #{inspect(repo)}: #{inspect(reason)}"
      end
    end

    :ok
  end

  defp repos do
    Application.load(@otp_app)
    Application.fetch_env!(@otp_app, :ecto_repos)
  end

  # An empty path list is the one failure mode worth being loud about:
  # `Ecto.Migrator` given no paths runs nothing and returns success, so a
  # release whose priv dirs were resolved wrongly would report a clean
  # migration and then serve traffic against an un-migrated database. Crash
  # instead — a container that will not start is a far cheaper problem.
  defp migration_paths do
    case MigrationPaths.all() do
      [] ->
        raise """
        No migration directories found.

        Under a release these resolve through the code server, so this means
        neither :gamend_core nor the host application (RELEASE_NAME=#{System.get_env("RELEASE_NAME") || "<unset>"})
        ships a priv/repo/migrations. Refusing to report a successful migration
        that ran nothing.
        """

      paths ->
        paths
    end
  end

  # storage_up/1 opens its own connection before the repo is started, so the
  # driver application has to be running under its own steam.
  defp start_driver(repo) do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> {:ok, _} = Application.ensure_all_started(:postgrex)
      Ecto.Adapters.SQLite3 -> {:ok, _} = Application.ensure_all_started(:exqlite)
      _other_adapter -> :ok
    end

    :ok
  end
end
