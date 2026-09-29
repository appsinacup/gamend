defmodule GamendWeb.CLI do
  @moduledoc """
  The commands behind a release's `bin/gamend`.

  A release has no Mix, so each command here is the release twin of the mix
  task with the same name, and runs the same code: `gamend db.migrate` is
  `mix db.migrate`, `gamend demo.seed --count 50` is `mix demo.seed --count 50`.
  `bin/gamend` runs the server itself (`start`, `daemon`, `stop`, `remote`);
  everything else reaches this module through the release's `eval`:

      bin/gamend_host eval "GamendWeb.CLI.main(System.argv())" -- db.migrate

  Every path is relative to the working directory, the project folder the
  release serves: its `.env`, `priv/repo/seeds.exs` and `modules/plugins`.
  `eval` starts no application, so the database commands run against a node
  that serves nothing; the ones that need the application (`db.seed`,
  `demo.seed`) start it with the HTTP listener and the job queues off, so they
  can run beside a server that is already up.
  """

  alias Gamend.Hooks.PluginBuilder
  alias Gamend.Release
  alias GamendWeb.CLI.Starter

  @usage """
  Usage: gamend COMMAND [ARGS]

  Server:
    start               Create and migrate the database, then run the server
    daemon              The same, in the background
    stop | restart      Stop or restart a running server
    reload              Re-read theme/config.json and the markdown on a
                        running server
    remote              Open a shell on the running server
    version             Print the release version

  Database (the same names as the mix tasks):
    db.setup            Create the database, migrate, then run priv/repo/seeds.exs
    db.migrate          Run pending migrations
    db.rollback         Roll back: --step N (default 1), --to VERSION or --all
    db.reset            Drop the database and set it up again
    db.seed             Run priv/repo/seeds.exs
    demo.seed           Seed demo data: --count N, --only SETS, --clean

  Project:
    starter [TEMPLATE]  Copy a starter project into this folder; never
                        overwrites a file unless --force. TEMPLATE is a name
                        (default: "default", "website"), a .tar.gz path or URL
    plugin.bundle [NAME...]
                        Build the plugins under modules/plugins (all when no
                        name is given)

  Every path is relative to the current directory. Settings come from the
  environment and ./.env; the full list is in .env.example.
  """

  @doc """
  Runs `argv` and halts the VM with its exit status.
  """
  @spec main([String.t()]) :: no_return()
  def main(argv) do
    # `eval` runs without a shell, whose stdio is latin1 until told otherwise.
    :io.setopts(:standard_io, encoding: :unicode)
    :io.setopts(:standard_error, encoding: :unicode)

    # `eval EXPR -- args` hands the separator through to System.argv/0.
    argv =
      case argv do
        ["--" | rest] -> rest
        argv -> argv
      end

    status =
      try do
        run(argv)
      rescue
        error ->
          IO.puts(:stderr, "error: " <> Exception.message(error))
          1
      end

    System.halt(status)
  end

  @doc """
  Runs `argv` and returns the exit status, without halting.
  """
  @spec run([String.t()]) :: non_neg_integer()
  def run(argv)

  def run(["db.setup" | _args]) do
    Release.createdb()
    Release.migrate()
    seed_file()
  end

  def run(["db.migrate" | _args]) do
    Release.migrate()
    0
  end

  def run(["db.rollback" | args]) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [step: :integer, to: :integer, all: :boolean])

    Release.rollback(opts)
    0
  end

  def run(["db.reset" | args]) do
    Release.dropdb()
    run(["db.setup" | args])
  end

  def run(["db.seed" | _args]), do: seed_file()

  def run(["demo.seed" | args]) do
    with_app(fn -> Gamend.DemoSeed.run(args) end)
    0
  end

  def run(["plugin.bundle" | names]), do: bundle_plugins(names)

  def run(["starter" | args]), do: Starter.run(args)

  def run([help]) when help in ["help", "--help", "-h"] do
    IO.write(@usage)
    0
  end

  def run([]) do
    IO.write(@usage)
    0
  end

  def run([command | _args]) do
    IO.puts(:stderr, "unknown command: #{command}\n")
    IO.write(:stderr, @usage)
    1
  end

  @doc false
  def usage, do: @usage

  # `mix host.seed` runs the same file with the application up; so does this.
  defp seed_file do
    case Release.seeds_file() do
      nil ->
        IO.puts("No seeds file at priv/repo/seeds.exs, skipping")

      path ->
        with_app(fn -> Code.eval_file(path) end)
        IO.puts("Seeded from #{Path.relative_to_cwd(path)}")
    end

    0
  end

  defp bundle_plugins(names) do
    names =
      case names do
        [] -> PluginBuilder.list_buildable_plugins()
        names -> names
      end

    if names == [] do
      IO.puts("No plugins to build under #{PluginBuilder.sources_dir()}")
      0
    else
      names
      |> Enum.map(&bundle_plugin/1)
      |> Enum.max()
    end
  end

  defp bundle_plugin(name) do
    case PluginBuilder.build(name) do
      {:ok, %{ok?: true}} ->
        IO.puts("Built #{name}")
        0

      {:ok, result} ->
        IO.puts(:stderr, "Failed to build #{name}")
        Enum.each(Map.get(result, :steps, []), &IO.puts(:stderr, &1.output))
        1

      {:error, reason} ->
        IO.puts(:stderr, "Failed to build #{name}: #{inspect(reason)}")
        1
    end
  end

  # Starts the host application the way `mix run` does, minus the parts that
  # would fight a server already running from the same folder: the HTTP
  # listener and the job queues.
  defp with_app(fun) do
    app = GamendWeb.host_app()

    for loaded <- [:gamend_core, :gamend_web, app], do: Application.load(loaded)

    update_env(:gamend_web, GamendWeb.Endpoint, server: false)
    update_env(:gamend_core, Oban, queues: false, plugins: false)

    # A one-off command prints its own result; the boot log (the resource
    # banner, os_mon's alarms) is the server's business.
    Logger.configure(level: :error)

    {:ok, _started} = Application.ensure_all_started(app)

    try do
      fun.()
    after
      # The host starts :os_mon, whose port programs report the halt that
      # follows as a crash unless it stops first.
      Application.stop(:os_mon)
    end
  end

  defp update_env(app, key, overrides) do
    current = Application.get_env(app, key, [])
    Application.put_env(app, key, Keyword.merge(current, overrides))
  end
end
