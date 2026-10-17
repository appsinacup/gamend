defmodule Gamend.Theme.JSONConfig do
  @moduledoc """
  JSON-backed Theme provider. Reads **one** config file — from the
  `GAMEND_CONTENT_THEME_CONFIG` setting or the host-owned default path — and
  translates its text through gettext at read time.

  There used to be one whole JSON file per locale. Two thirds of each copy was
  structure (urls, icons, layout) rather than text, and they drifted: a
  `theme_color` added to English never reached the other 29, so non-English
  visitors silently got the fallback colour. Structure now lives once, and only
  the leaves `Gamend.Theme.Translatable` names as text vary by locale —
  through the `theme` gettext domain, like every other string in the UI.

  A missing translation falls back to the source string, so a config with no
  `.po` at all still renders exactly as written.

  The decoded file is cached in `:persistent_term`; translation happens per
  read, against the caller's current locale. Call `reload/0` after editing the
  file at runtime.

  `reload/0` emits the telemetry event `[:gamend, :theme, :reload]` once the
  cache is cleared, so work derived from the file can follow it without core
  knowing who does it: the web app cuts the responsive image variants a new
  config asks for (`GamendWeb.ResponsiveImages`).
  """

  @behaviour Gamend.Theme

  alias Gamend.Theme.Translatable

  @theme_key {__MODULE__, :theme_cache}
  @generation_key {__MODULE__, :generation}

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
    case cached_theme() do
      {_generation, config} when map_size(config) == 0 -> config
      {generation, config} -> translate(config, generation, locale)
    end
  end

  @doc """
  The config exactly as written, untranslated.

  For the extractor and for admin diagnostics, which must show what is on
  disk rather than what a viewer would see.
  """
  @spec raw_theme() :: map()
  def raw_theme do
    {_generation, config} = cached_theme()
    config
  end

  # Every cached entry carries the `reload/0` generation it was read under. A
  # read that began before a reload can finish after it: the reload's own
  # telemetry has `GamendWeb.ResponsiveImages` read the file in its process
  # while the caller moves on. Its write then lands on top of the fresh entry,
  # and untagged it would serve the old file until the next reload; tagged, it
  # is a miss.
  defp cached_theme do
    generation = :persistent_term.get(@generation_key, :initial)

    case :persistent_term.get(@theme_key, :not_cached) do
      {^generation, _config} = cached ->
        cached

      _missing_or_stale ->
        result = do_get_theme()

        # Only cache a non-empty result, or an empty one when nothing is
        # configured at all: at startup the file may not be readable yet, and
        # caching empty would keep it empty forever.
        if result != %{} or config_path() == nil do
          :persistent_term.put(@theme_key, {generation, result})
        end

        {generation, result}
    end
  end

  # Memoised per locale, because the walk is not cheap and its result cannot
  # change between two reads of the same locale: `raw_theme/0` is already
  # cached, and the only other input is the compiled `.po`. Uncached, every
  # page render walked the whole config, ran a regex and a gettext lookup on
  # every text leaf, and rebuilt a map identical to the one the previous
  # request built -- roughly 500 lookups and 400 regex runs per page, all of
  # it re-deriving a constant.
  #
  # `locale` is resolved before it becomes the key: a nil locale means "use
  # the caller's", which is a different answer per process, and keying on nil
  # would serve the first caller's language to everyone.
  #
  # Tagged with the generation of the config it was built from, for the same
  # late-write race `cached_theme/0` guards.
  defp translate(config, generation, locale) do
    case gettext_backend() do
      nil -> config
      backend -> translate_with(config, generation, backend, locale)
    end
  end

  defp translate_with(config, generation, backend, locale) do
    resolved = locale || Gettext.get_locale(backend)
    key = {__MODULE__, :translated, backend, resolved}

    case :persistent_term.get(key, :not_cached) do
      {^generation, result} ->
        result

      _missing_or_stale ->
        result = do_translate(config, backend, resolved)
        :persistent_term.put(key, {generation, result})
        result
    end
  end

  defp do_translate(config, backend, locale) do
    translator = fn source ->
      Gettext.with_locale(backend, locale, fn ->
        Gettext.dgettext(backend, "theme", source)
      end)
    end

    Translatable.walk(config, translator)
  end

  # Resolved at runtime so a host can point the theme at its own backend, the
  # same one GettextSync drives for the rest of the UI.
  #
  # The last resort is `GamendWeb.Gettext`, which is the only place core reaches
  # up into gamend_web — and gamend_core does not depend on gamend_web, so for a
  # bare-core consumer that module does not exist. Resolved by name rather than
  # referenced directly, so the theme is served untranslated there instead of
  # raising UndefinedFunctionError.
  defp gettext_backend do
    Application.get_env(:gamend_core, :theme_gettext_backend) ||
      Application.get_env(:gamend_web, :host_gettext_backend) ||
      default_backend()
  end

  defp default_backend do
    backend = Module.concat([:GamendWeb, :Gettext])
    if Code.ensure_loaded?(backend), do: backend
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
    # A new generation first: whatever was read before this line is stale,
    # even when it is written after it. A ref, so two reloads never share one.
    :persistent_term.put(@generation_key, make_ref())

    # Reset the cache so the next read comes from disk.
    :persistent_term.erase(@theme_key)

    # And every translation derived from it, keyed per locale rather than per
    # generation so old ones are not stranded in a table that is never garbage
    # collected. Scanning the whole table is fine: reload is a rare admin action.
    for {{mod, :translated, _backend, _locale} = key, _value} <- :persistent_term.get(),
        mod == __MODULE__,
        do: :persistent_term.erase(key)

    :telemetry.execute([:gamend, :theme, :reload], %{system_time: System.system_time()}, %{
      path: config_path()
    })

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
    normalize_path_env(Gamend.Settings.get(Gamend.ContentSettings, :theme_config))
  end

  @doc """
  Returns the effective theme config path, preferring GAMEND_CONTENT_THEME_CONFIG when set and
  otherwise falling back to the host-owned default path.
  """
  def active_path do
    config_path()
  end

  defp default_path do
    :gamend_core
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:default_config_path)
    |> normalize_path_env()
  end

  defp normalize_path_env(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp normalize_path_env(_value), do: nil

  # The web app ships the default theme files, but the core runs without it
  # (its own suite, a host that only uses the contexts), where `priv_dir/1`
  # answers `{:error, :bad_name}` rather than a path.
  defp web_priv_candidate(path) do
    case :code.priv_dir(:gamend_web) do
      dir when is_list(dir) -> [Path.join(dir, path)]
      {:error, _not_loaded} -> []
    end
  end

  defp read_json(path) when is_binary(path) do
    # If the path is relative to the project root, check it directly.
    candidates = [path, Path.join(File.cwd!(), path)] ++ web_priv_candidate(path)

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
    Enum.reduce(["css", "logo", "logo_dark", "banner", "favicon"], map, fn key, acc ->
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
