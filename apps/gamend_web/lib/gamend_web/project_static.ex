defmodule GamendWeb.ProjectStatic do
  @moduledoc """
  Static files a project supplies next to the engine: the overlay.

  A release carries its own `priv/static` (the host app's and `gamend_web`'s),
  which someone running the engine from a project folder cannot edit. The
  overlay is a directory in that folder whose files are served *before* the
  built-in ones, so a project adds its own images, a `game/` web export or a
  favicon, and replaces one the engine ships by putting a file at the same path.

  ## Which directories

  `GAMEND_CONTENT_STATIC_DIRS` (`Gamend.ContentSettings`, `:static_dirs`),
  `static,priv/static` by default: relative paths taken against the working
  directory, searched in that order, each used when it exists the first time
  the overlay is resolved. A directory created after that is picked up by
  `reload/0`, which a theme reload runs, or a restart.

  A directory that *is* one of the apps' own `priv/static` is skipped: under
  `mix phx.server` from the repository root, `priv/static` is the host app's
  priv, which the endpoint already serves.

  ## What it may serve

  Only the top-level entries of `:host_static_paths` (`images`, `game`,
  `favicon.ico`, `robots.txt`, `.well-known`, `theme.css`, ...), and never
  `assets/`: the engine's digested CSS and JS always win.

  ## Lookups

  `path_for/1` answers which file a URL path is served from: the overlay first,
  then the host app's `priv/static`, the asset app's, and `gamend_web`'s.
  Everything that reads a static file by its URL (image dimensions, srcset
  variants, the `?v=` content hash, the theme's `theme.css`) goes through it, so
  the page links what the endpoint serves.
  """

  @dirs_key {__MODULE__, :dirs}
  @roots_key {__MODULE__, :roots}
  @generation_key {__MODULE__, :generation}

  @default_host_static_paths ~w(images game favicon.ico robots.txt .well-known theme.css)

  @doc """
  The overlay directories, expanded, in the order they are searched.

  Resolved on first use and cached until `reset/0` or `reload/0`: this sits in
  front of every static request, and the answer only changes with the working
  directory, the setting, or a directory appearing.
  """
  @spec dirs() :: [String.t()]
  def dirs do
    case :persistent_term.get(@dirs_key, :miss) do
      :miss ->
        dirs = resolve_dirs()
        :persistent_term.put(@dirs_key, dirs)
        dirs

      dirs ->
        dirs
    end
  end

  @doc "Forgets the resolved directories, so the next call resolves them again."
  @spec reset() :: :ok
  def reset do
    :persistent_term.erase(@dirs_key)
    :persistent_term.erase(@roots_key)
    :ok
  end

  @doc """
  Takes in whatever changed on disk: resolves the directories again and bumps
  `generation/0`, so the `?v=` hashes, the `theme.css` link and the cached
  presentation pages are rebuilt from the files as they are now.

  Run on a theme reload (`GamendWeb.ResponsiveImages` follows
  `Gamend.Theme.JSONConfig.reload/0`), which is what makes a folder created or
  a file replaced after boot show without a restart.
  """
  @spec reload() :: :ok
  def reload do
    reset()
    bump_generation()
  end

  @doc """
  The top-level entries an overlay directory may answer: `:host_static_paths`
  without `assets`.
  """
  @spec overlay_paths() :: [String.t()]
  def overlay_paths, do: host_static_paths() -- ["assets"]

  @doc "The configured `:host_static_paths`: the top-level entries served from the host app."
  @spec host_static_paths() :: [String.t()]
  def host_static_paths do
    Application.get_env(:gamend_web, :host_static_paths, @default_host_static_paths)
  end

  @doc """
  The file on disk a URL path is served from, or `nil`.

  Takes the path as written in a page or the theme config: a leading slash, a
  query or a fragment are fine. An absolute URL, a `data:` URI or a path that
  climbs with `..` is never a local file.
  """
  @spec path_for(String.t() | nil) :: String.t() | nil
  def path_for(url_path) do
    case lookup(url_path) do
      {_root, file} -> file
      nil -> nil
    end
  end

  @doc """
  Like `path_for/1`, but answers `{static_dir, file}`: which directory the file
  comes from as well as where it is.
  """
  @spec lookup(String.t() | nil) :: {String.t(), String.t()} | nil
  def lookup(url_path) do
    case segments(url_path) do
      nil -> nil
      segments -> segments |> roots_for() |> find_file(segments)
    end
  end

  @doc "The file an overlay directory serves for a URL path, ignoring the built-in ones."
  @spec overlay_path_for(String.t() | nil) :: String.t() | nil
  def overlay_path_for(url_path) do
    with [first | _] = segments <- segments(url_path),
         true <- first in overlay_paths(),
         {_root, file} <- find_file(dirs(), segments) do
      file
    else
      _ -> nil
    end
  end

  @doc """
  Whether an overlay directory could answer this URL path: there is one, and
  the path's top-level entry is one it may serve.

  True whether or not the file exists there right now, which is the point: the
  endpoint checks the overlay on every request, so a file dropped in later is
  served at once.
  """
  @spec overlay_servable?(String.t() | nil) :: boolean()
  def overlay_servable?(url_path) do
    case segments(url_path) do
      [first | _] -> first in overlay_paths() and dirs() != []
      _ -> false
    end
  end

  @doc """
  Whether `derived_url`, a file made from `original_url` (`main-480.webp` cut
  from `main.webp`, `generated/logo.webp` from `logo.png`), is served from the
  same directory as the original.

  A derived file only describes the original it was made from. When a project
  replaces the engine's `/images/banner.webp`, the engine's `banner-480.webp`
  is a smaller copy of a different picture, and linking it would show the
  engine's art on the project's page. An original served from nowhere local
  accepts a derived file from anywhere, as before the overlay existed.
  """
  @spec derived_from?(String.t() | nil, String.t() | nil) :: boolean()
  def derived_from?(derived_url, original_url) do
    case lookup(derived_url) do
      nil ->
        false

      {root, _file} ->
        case lookup(original_url) do
          nil -> true
          {^root, _file} -> true
          _other -> false
        end
    end
  end

  @doc """
  A counter bumped whenever the files pages link may have changed at runtime:
  on `reload/0`, and when responsive image variants are cut after boot.
  Everything cached from those files keys on it: the `?v=` hashes
  (`GamendWeb.SRI`), whether a `theme.css` exists, and the cached presentation
  page bodies.
  """
  @spec generation() :: non_neg_integer()
  def generation, do: :persistent_term.get(@generation_key, 0)

  @doc "Bumps `generation/0`."
  @spec bump_generation() :: :ok
  def bump_generation do
    :persistent_term.put(@generation_key, generation() + 1)
  end

  defp find_file(roots, segments) do
    Enum.find_value(roots, fn root ->
      file = Path.join([root | segments])
      if File.regular?(file), do: {root, file}
    end)
  end

  defp roots_for([first | _]) do
    overlay = if first in overlay_paths(), do: dirs(), else: []
    overlay ++ app_roots(first)
  end

  # The app dirs are cached too: `Application.app_dir/2` is a round trip
  # through the code server, and this runs several times per page render.
  # Keyed on the config it is built from, so a host (or a test) that points
  # `:host_static_app` elsewhere is not served a stale list.
  defp app_roots(first) do
    config = {GamendWeb.host_app(), GamendWeb.asset_app()}

    roots =
      case :persistent_term.get(@roots_key, :miss) do
        {^config, roots} ->
          roots

        _ ->
          roots = build_app_roots(config)
          :persistent_term.put(@roots_key, {config, roots})
          roots
      end

    if first == "assets", do: roots.assets, else: roots.other
  end

  defp build_app_roots({host_app, asset_app}) do
    %{
      assets: app_dirs([asset_app, host_app, :gamend_web]),
      other: app_dirs([host_app, asset_app, :gamend_web])
    }
  end

  defp app_dirs(apps) do
    apps
    |> Enum.uniq()
    |> Enum.map(&app_static_dir/1)
    |> Enum.reject(&is_nil/1)
  end

  defp app_static_dir(app) when is_atom(app) do
    if Application.spec(app, :vsn), do: Application.app_dir(app, "priv/static")
  end

  defp app_static_dir(_app), do: nil

  defp resolve_dirs do
    own = [GamendWeb.host_app(), GamendWeb.asset_app(), :gamend_web] |> app_dirs()

    (Gamend.Settings.get(Gamend.ContentSettings, :static_dirs) || [])
    |> Enum.map(&Path.expand/1)
    |> Enum.filter(&File.dir?/1)
    |> Enum.reject(fn dir -> Enum.any?(own, &same_dir?(dir, &1)) end)
    |> Enum.uniq()
  end

  # By path first, then by identity: `_build/dev/lib/gamend_host/priv` is a
  # symlink to the repository's `priv`, so the two spellings of the host app's
  # static dir only compare equal once the link is followed, which `File.stat`
  # does. Windows reports every inode as 0, so identity is only trusted when
  # there is one.
  defp same_dir?(a, b) do
    a = Path.expand(a)
    b = Path.expand(b)

    a == b or
      case {File.stat(a), File.stat(b)} do
        {{:ok, %{inode: inode, major_device: dev}}, {:ok, %{inode: inode, major_device: dev}}}
        when inode != 0 ->
          true

        _ ->
          false
      end
  end

  defp segments(url_path) when is_binary(url_path) and url_path != "" do
    uri = URI.parse(url_path)

    with nil <- uri.scheme,
         nil <- uri.host,
         path when is_binary(path) <- uri.path,
         [_ | _] = segments <- path |> String.split("/", trim: true) |> Enum.map(&decode/1),
         true <- Enum.all?(segments, &safe_segment?/1) do
      segments
    else
      _ -> nil
    end
  end

  defp segments(_url_path), do: nil

  defp decode(segment) do
    URI.decode(segment)
  rescue
    ArgumentError -> segment
  end

  defp safe_segment?(segment) do
    segment not in [".", ".."] and not String.contains?(segment, ["/", "\\", ":", <<0>>])
  end
end
