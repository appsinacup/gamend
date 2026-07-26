defmodule Mix.Tasks.Gamend.Theme.MigrateLocales do
  @shortdoc "Harvests per-locale theme JSON files into gettext PO translations"

  @moduledoc """
  One-shot migration off one-JSON-file-per-locale.

      mix gamend.theme.migrate_locales theme/config.json
      mix gamend.theme.migrate_locales theme/config.json --dry-run

  For each `<base>.<locale>.json` sitting next to the base config, pairs every
  translatable leaf with the same leaf in the base by **path**, and writes
  `msgid <base text> / msgstr <localised text>` into that locale's `theme.po`.

  Path-pairing is safe here and only here: the locale files were copies of the
  base, so identical paths held corresponding text. Ongoing translation keys on
  the source string instead, which is what survives a section being reordered.

  Reports anything it could not pair rather than guessing — a path present in a
  locale but not the base means the two drifted, and a human should look.

  Delete the locale files once this has run; nothing reads them any more.
  """

  use Mix.Task

  alias GameServer.Theme.Translatable

  @gettext_dir "priv/gettext"

  @impl true
  def run(argv) do
    Mix.Task.run("app.config")

    {opts, rest} = OptionParser.parse!(argv, strict: [dry_run: :boolean, gettext: :string])

    base_path =
      case rest do
        [path | _] -> path
        [] -> Mix.raise("usage: mix gamend.theme.migrate_locales <base config path>")
      end

    base = decode!(base_path)
    base_paths = flatten(base)

    locales = locale_files(base_path)

    if locales == [] do
      Mix.shell().info("no <base>.<locale>.json files next to #{base_path} - nothing to migrate")
    else
      Enum.each(locales, &migrate_locale(&1, base_paths, opts))

      Mix.shell().info(
        "\n#{length(locales)} locales processed. Delete the locale files once you are happy:\n" <>
          "  git rm #{Path.rootname(base_path)}.*.json"
      )
    end
  end

  defp migrate_locale({locale, path}, base_paths, opts) do
    translated = path |> decode!() |> flatten()

    {pairs, unmatched} =
      Enum.reduce(translated, {[], []}, fn {leaf_path, value}, {pairs, unmatched} ->
        case Map.fetch(base_paths, leaf_path) do
          # Untranslated in the source file; gettext falls back to it anyway.
          {:ok, ^value} -> {pairs, unmatched}
          {:ok, source} -> {[{source, value} | pairs], unmatched}
          :error -> {pairs, [leaf_path | unmatched]}
        end
      end)

    pairs = pairs |> Enum.reverse() |> Enum.uniq_by(&elem(&1, 0))

    po_path =
      Path.join([Keyword.get(opts, :gettext, @gettext_dir), locale, "LC_MESSAGES/theme.po"])

    if Keyword.get(opts, :dry_run, false) do
      Mix.shell().info("#{locale}: #{length(pairs)} translations -> #{po_path} (dry run)")
    else
      File.mkdir_p!(Path.dirname(po_path))
      File.write!(po_path, render_po(locale, pairs))
      Mix.shell().info("#{locale}: #{length(pairs)} translations -> #{po_path}")
    end

    if unmatched != [] do
      Mix.shell().info(
        "  #{length(unmatched)} path(s) not in the base config, skipped: " <>
          Enum.join(Enum.take(unmatched, 3), ", ")
      )
    end
  end

  defp locale_files(base_path) do
    root = Path.rootname(base_path)
    ext = Path.extname(base_path)

    (root <> ".*" <> ext)
    |> Path.wildcard()
    |> Enum.map(fn path ->
      locale = path |> Path.basename(ext) |> String.split(".") |> List.last()
      {locale, path}
    end)
    # The base's own language needs no PO: it is the msgid.
    |> Enum.reject(fn {locale, _path} -> locale in ["en", Path.basename(root)] end)
    |> Enum.sort()
  end

  # Path -> text, for translatable leaves only. Keys mirror the CSV exporter's
  # (`navigation.primary_links[0].label`) so the two stay legible together.
  defp flatten(config), do: do_flatten(config, "", nil, %{})

  defp do_flatten(map, prefix, _key, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {key, value}, acc ->
      do_flatten(value, "#{prefix}.#{key}", key, acc)
    end)
  end

  defp do_flatten(list, prefix, key, acc) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {value, index}, acc ->
      do_flatten(value, "#{prefix}[#{index}]", key, acc)
    end)
  end

  defp do_flatten(value, prefix, key, acc) when is_binary(value) do
    if Translatable.text?(key) and String.trim(value) != "",
      do: Map.put(acc, prefix, value),
      else: acc
  end

  defp do_flatten(_value, _prefix, _key, acc), do: acc

  defp decode!(path) do
    case File.read(path) do
      {:ok, content} -> Jason.decode!(content)
      {:error, reason} -> Mix.raise("cannot read #{path}: #{inspect(reason)}")
    end
  end

  defp render_po(locale, pairs) do
    header = """
    ## Migrated from the per-locale theme JSON by
    ## `mix gamend.theme.migrate_locales`. Maintain with `mix gettext.merge`.
    msgid ""
    msgstr ""
    "Language: #{locale}\\n"
    """

    header <> Enum.map_join(pairs, "", fn {source, target} -> entry(source, target) end)
  end

  defp entry(source, target) do
    """

    msgid #{quote_po(source)}
    msgstr #{quote_po(target)}
    """
  end

  defp quote_po(string) do
    escaped = string |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")

    case String.split(escaped, "\n") do
      [single] ->
        ~s("#{single}")

      lines ->
        body =
          lines
          |> Enum.with_index()
          |> Enum.map_join("\n", fn {line, index} ->
            suffix = if index == length(lines) - 1, do: "", else: "\\n"
            ~s("#{line}#{suffix}")
          end)

        ~s("") <> "\n" <> body
    end
  end
end
