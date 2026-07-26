defmodule GameServer.Theme.JSONConfig do
  @moduledoc """
  JSON-backed Theme provider. Reads **one** config file — from the
  `GAMEND_CONTENT_THEME_CONFIG` setting or the host-owned default path — and
  translates its text through gettext at read time.

  There used to be one whole JSON file per locale. Two thirds of each copy was
  structure (urls, icons, layout) rather than text, and they drifted: a
  `theme_color` added to English never reached the other 29, so non-English
  visitors silently got the fallback colour. Structure now lives once, and only
  the leaves `GameServer.Theme.Translatable` names as text vary by locale —
  through the `theme` gettext domain, like every other string in the UI.

  A missing translation falls back to the source string, so a config with no
  `.po` at all still renders exactly as written.

  The decoded file is cached in `:persistent_term`; translation happens per
  read, against the caller's current locale. Call `reload/0` after editing the
  file at runtime.
  """

  @behaviour GameServer.Theme

  alias GameServer.Theme.Translatable

  @impl true
  def get_theme do
    get_theme(nil)
  end

  @doc """
  The theme, with its text translated into `locale` (or the caller's current
  locale when `nil`).

  Locale fallback is gettext's, not ours: `es_ES` falls back to `es` and then
  to the source string, so this never has to hunt for a file that might exist.
  """
  @spec get_theme(String.t() | nil) :: map()
  def get_theme(locale) when is_binary(locale) or is_nil(locale) do
    case raw_theme() do
      config when map_size(config) == 0 -> config
      config -> translate(config, locale)
    end
  end

  @doc """
  The config exactly as written, untranslated.

  For the extractor and for admin diagnostics, which must show what is on
  disk rather than what a viewer would see.
  """
  @spec raw_theme() :: map()
  def raw_theme do
    case :persistent_term.get({__MODULE__, :theme_cache}, :not_cached) do
      :not_cached ->
        result = do_get_theme()

        # Only cache a non-empty result, or an empty one when nothing is
        # configured at all: at startup the file may not be readable yet, and
        # caching empty would keep it empty forever.
        if result != %{} or config_path() == nil do
          :persistent_term.put({__MODULE__, :theme_cache}, result)
        end

        result

      cached ->
        cached
    end
  end

  defp translate(config, locale) do
    backend = gettext_backend()

    translator = fn source ->
      if locale do
        Gettext.with_locale(backend, locale, fn ->
          Gettext.dgettext(backend, "theme", source)
        end)
      else
        Gettext.dgettext(backend, "theme", source)
      end
    end

    Translatable.walk(config, translator)
  end

  # Resolved at runtime so a host can point the theme at its own backend, the
  # same one GettextSync drives for the rest of the UI.
  defp gettext_backend do
    Application.get_env(:game_server_core, :theme_gettext_backend) ||
      Application.get_env(:game_server_web, :host_gettext_backend) ||
      GameServerWeb.Gettext
  end

  defp do_get_theme do
    case config_path() do
      nil ->
        %{}

      path ->
        case read_json(path) do
          {:ok, map} when is_map(map) -> normalize_asset_paths(map)
          _ -> %{}
        end
    end
  end

  @impl true
  def get_setting(key) when is_atom(key) do
    get_setting(Atom.to_string(key))
  end

  def get_setting(key) when is_binary(key) do
    Map.get(get_theme(), key)
  end

  @impl true
  def reload do
    # Reset the cache so the next read comes from disk.
    :persistent_term.erase({__MODULE__, :theme_cache})
    :ok
  end

  defp config_path do
    runtime_path() || default_path()
  end

  @doc """
  Returns the runtime GAMEND_CONTENT_THEME_CONFIG override if present and non-blank,
  otherwise nil. This intentionally excludes the host default path so admin
  diagnostics can distinguish explicit overrides from host defaults.
  """
  def runtime_path do
    normalize_path_env(GameServer.Settings.get(GameServer.ContentSettings, :theme_config))
  end

  @doc """
  Returns the effective theme config path, preferring GAMEND_CONTENT_THEME_CONFIG when set and
  otherwise falling back to the host-owned default path.
  """
  def active_path do
    config_path()
  end

  defp default_path do
    :game_server_core
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:default_config_path)
    |> normalize_path_env()
  end

  defp normalize_path_env(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp normalize_path_env(_value), do: nil

  defp read_json(path) when is_binary(path) do
    # If the path is relative to the project root, check it directly.
    candidates = [
      path,
      Path.join(File.cwd!(), path),
      Path.join(:code.priv_dir(:game_server_web), path)
    ]

    Enum.find_value(candidates, :error, fn p ->
      try_decode_file(p)
    end)
  end

  defp try_decode_file(path) when is_binary(path) do
    with true <- File.exists?(path),
         {:ok, content} <- File.read(path),
         {:ok, decoded} when is_map(decoded) <- Jason.decode(content) do
      {:ok, decoded}
    else
      _ -> :error
    end
  end

  defp normalize_asset_paths(map) when is_map(map) do
    Enum.reduce(["css", "logo", "banner", "favicon"], map, fn key, acc ->
      case Map.get(acc, key) do
        value when is_binary(value) -> Map.put(acc, key, normalize_path(value))
        _ -> acc
      end
    end)
  end

  defp normalize_path(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> trimmed
      String.starts_with?(trimmed, "/") -> trimmed
      String.starts_with?(trimmed, "data:") -> trimmed
      Regex.match?(~r/^https?:\/\//i, trimmed) -> trimmed
      true -> "/" <> trimmed
    end
  end
end
