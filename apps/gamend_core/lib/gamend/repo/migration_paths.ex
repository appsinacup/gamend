defmodule Gamend.Repo.MigrationPaths do
  @moduledoc """
  Resolves every migration directory that belongs to a gamend deployment.

  A host application (the umbrella's `gamend_host`, or a downstream game) runs
  **core migrations plus its own**, and core can be present either as an
  umbrella app or as a dependency. Anything that walks
  migrations — the `host.*` mix tasks, `Gamend.Release`, the admin runtime
  page — must consider the same set, so the list lives here rather than being
  copied per caller.

  Mix and releases locate that set differently, so `all/1` picks one strategy
  or the other rather than merging them: under Mix the directories are paths in
  the project tree, in a release they live inside each application's own
  `lib/<app>-<vsn>/priv`. Returning both would hand Ecto the same migration
  file under two names, and duplicate versions are a hard error.
  """

  @priv "priv"

  @project_candidates [
    "apps/gamend_core/priv/repo/migrations",
    "deps/gamend_core/priv/repo/migrations",
    "deps/gamend_core/apps/gamend_core/priv/repo/migrations",
    "priv/repo/migrations"
  ]

  @doc """
  Existing migration directories, absolute and de-duplicated.

  Pass `ensure_host: true` (the mix tasks do) to create the host's own
  `priv/repo/migrations` first, so Ecto does not fail on a missing path in a
  project that has not written a migration yet.
  """
  @spec all(keyword()) :: [String.t()]
  def all(opts \\ []) do
    if Keyword.get(opts, :ensure_host, false), do: File.mkdir_p!("priv/repo/migrations")

    if mix_project?(), do: project_paths(), else: release_paths()
  end

  @doc "The paths as `--migrations-path <dir>` arguments for the Ecto mix tasks."
  @spec as_args(keyword()) :: [String.t()]
  def as_args(opts \\ []) do
    opts |> all() |> Enum.flat_map(&["--migrations-path", &1])
  end

  defp project_paths do
    existing([core_dep_path() | @project_candidates])
  end

  # A release has no project tree, so every entry in @project_candidates misses
  # and this module would hand back nothing but a stray `priv/repo/migrations`
  # next to the release root. That is the dangerous failure rather than a loud
  # one: `Ecto.Migrator` given no paths runs no migrations and reports success,
  # so the node would boot against an un-migrated database and the admin
  # runtime page would list zero migrations. Ask the code server instead, which
  # is where a release actually keeps each application's priv dir.
  defp release_paths do
    [:gamend_core | host_app()]
    |> Enum.map(&app_migrations_dir/1)
    |> existing()
  end

  # `Application.app_dir/2` raises for an application the code server does not
  # know. An error tuple is the better shape here, because core is a plain
  # dependency under Mix and only becomes a loaded application in a release.
  defp app_migrations_dir(app) do
    case :code.lib_dir(app) do
      {:error, _unknown_app} -> nil
      lib_dir -> Path.join([List.to_string(lib_dir), @priv, "repo", "migrations"])
    end
  end

  # Core cannot know the host application's name — `gamend_host` here,
  # something else in a downstream game. A release's boot script exports
  # RELEASE_NAME, which for every host built on this stack is also its
  # top-level application. Unset under Mix, where the relative candidates
  # already cover the host.
  defp host_app do
    with name when is_binary(name) <- System.get_env("RELEASE_NAME"),
         {:ok, app} <- existing_atom(name) do
      [app]
    else
      _no_release_name -> []
    end
  end

  # An unknown name means no such application was loaded, so there is nothing
  # to resolve — and minting the atom anyway would leak one per boot.
  defp existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end

  defp existing(paths) do
    paths
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.filter(&File.dir?/1)
    |> Enum.uniq()
  end

  # Only available under Mix (not in a release), so guard on the module.
  defp core_dep_path do
    with true <- mix_project?(),
         dep_path when is_binary(dep_path) <- Mix.Project.deps_paths()[:gamend_core] do
      Path.join(dep_path, "priv/repo/migrations")
    else
      _ -> nil
    end
  end

  defp mix_project?, do: Code.ensure_loaded?(Mix.Project)
end
