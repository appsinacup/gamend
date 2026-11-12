defmodule GamendWeb.DevWatch do
  @moduledoc """
  What changed on disk since the dev server last looked, so a dev request
  checks only when there is something to check (2026-11-12).

  In dev every request that is not a static file ran Mix's staleness check
  for the reloadable apps (`Phoenix.CodeReloader`), the pending-migrations
  check (`Phoenix.Ecto.CheckRepoStatus`) and, in the root layout, a SHA-384
  of the whole stylesheet and script (`GamendWeb.SRI`). On a quiet machine
  that is ~50 ms a request; on a busy one each file stat costs 40x more and
  the reloader runs one check at a time, so ten requests at once took 2.3 s
  each.

  This process watches the reloadable apps' `lib`, `priv/gettext` and
  `config` folders and the repos' migration folders (`FileSystem`, the
  watcher `phoenix_live_reload` already brings), and counts each folder
  set's changes. `GamendWeb.Plugs.DevCodeReloader` and
  `GamendWeb.Plugs.DevRepoStatus` run their check only when the count moved
  since the last check that passed; a failed check (a compile error, a
  pending migration) is not marked, so the next request shows it again.

  Started only where the endpoint reloads code and `FileSystem` is loaded;
  anywhere else, or if the watcher stops, there is no table and every
  request checks, as Phoenix does.
  """

  use GenServer

  require Logger

  # `FileSystem` comes with `phoenix_live_reload`, a host's dev dependency:
  # absent from a production build, which never starts this process.
  @compile {:no_warn_undefined, FileSystem}

  @table :gamend_dev_watch
  @code_folders ["lib", "priv/gettext", "config"]

  @doc false
  def start_link(opts \\ []) do
    if enabled?(), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__), else: :ignore
  end

  @doc """
  `{:stale, count}` when `kind` (`:code` or `:repo`) changed since its last
  passing check, or when nothing is watched (`count` nil); `:fresh` when not.
  """
  @spec stale(:code | :repo) :: {:stale, non_neg_integer() | nil} | :fresh
  def stale(kind) do
    case lookup(kind) do
      [{_, count}] ->
        if lookup({:checked, kind}) == [{{:checked, kind}, count}],
          do: :fresh,
          else: {:stale, count}

      _ ->
        {:stale, nil}
    end
  end

  @doc "Records that `kind`'s check passed at `count` (from `stale/1`)."
  @spec checked(:code | :repo, non_neg_integer() | nil) :: :ok
  def checked(_kind, nil), do: :ok

  def checked(kind, count) do
    _ = safe(fn -> :ets.insert(@table, {{:checked, kind}, count}) end)
    :ok
  end

  @doc """
  `fun`'s answer for `key` while `stamp` holds (a file's size and change
  time), computed again when it moves. Computed every call where nothing is
  watched.
  """
  @spec memo(term(), term(), (-> value)) :: value when value: term()
  def memo(key, stamp, fun) do
    case lookup({:memo, key}) do
      [{_, ^stamp, value}] ->
        value

      :none ->
        fun.()

      _missing_or_moved ->
        value = fun.()
        _ = safe(fn -> :ets.insert(@table, {{:memo, key}, stamp, value}) end)
        value
    end
  end

  @impl GenServer
  def init(_opts) do
    code = folders(code_roots(), @code_folders)
    repo = repo_folders()
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ets.insert(@table, [{:code, 0}, {:repo, 0}])

    {:ok, watcher} = FileSystem.start_link(dirs: code ++ repo)
    :ok = FileSystem.subscribe(watcher)

    {:ok, %{watcher: watcher, repo: repo}}
  end

  @impl GenServer
  def handle_info({:file_event, watcher, {path, _events}}, %{watcher: watcher} = state) do
    kind = if Enum.any?(state.repo, &String.starts_with?(path, &1)), do: :repo, else: :code
    :ets.update_counter(@table, kind, 1)
    {:noreply, state}
  end

  # Without a watcher no count can be trusted: the table goes, and every
  # request checks again.
  def handle_info({:file_event, watcher, :stop}, %{watcher: watcher} = state) do
    Logger.warning("dev watch: the file watcher stopped; every request checks again")
    :ets.delete(@table)
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp enabled? do
    endpoint = Application.get_env(:gamend_web, GamendWeb.Endpoint, [])

    Keyword.get(endpoint, :code_reloader, false) and Code.ensure_loaded?(FileSystem) and
      Code.ensure_loaded?(Mix.Project)
  end

  # Where Phoenix's reloader looks: the endpoint's `reloadable_apps`, else
  # the project's own app (every app of an umbrella).
  defp code_roots do
    endpoint = Application.get_env(:gamend_web, GamendWeb.Endpoint, [])

    apps =
      endpoint[:reloadable_apps] ||
        if Mix.Project.umbrella?(),
          do: Map.keys(Mix.Project.apps_paths()),
          else: [Mix.Project.config()[:app]]

    Enum.flat_map(apps, &source_root/1)
  end

  # The migration folders `CheckRepoStatus` (`otp_app: :gamend_web`) reads,
  # at their source: `Ecto.Migrator.migrations_path/1` answers the build's
  # `priv`, a link the file watcher reports by its real path.
  defp repo_folders do
    for repo <- Application.get_env(:gamend_web, :ecto_repos, []),
        root <- source_root(repo.config()[:otp_app]),
        path = Path.join(root, "priv/repo/migrations"),
        File.dir?(path),
        do: path
  end

  # An app's source folder: an umbrella app's, a path dependency's, or the
  # project's own. None for a Hex package: nothing is edited there.
  defp source_root(app) do
    umbrella = if Mix.Project.umbrella?(), do: Mix.Project.apps_paths(), else: %{}

    cond do
      path = umbrella[app] -> [Path.expand(path)]
      app == Mix.Project.config()[:app] -> [File.cwd!()]
      path = Mix.Project.deps_paths()[app] -> [Path.expand(path)]
      true -> []
    end
  end

  defp folders(roots, names) do
    for root <- Enum.uniq(roots),
        name <- names,
        dir = Path.join(root, name),
        File.dir?(dir),
        do: dir
  end

  defp lookup(key) do
    :ets.lookup(@table, key)
  rescue
    ArgumentError -> :none
  end

  defp safe(fun) do
    fun.()
  rescue
    ArgumentError -> :none
  end
end
