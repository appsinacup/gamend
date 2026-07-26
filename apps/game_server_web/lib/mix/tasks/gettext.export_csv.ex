defmodule Mix.Tasks.Gettext.ExportCsv do
  @moduledoc """
  Exports every translation for a locale to one CSV, for review in a
  spreadsheet.

  ## Usage

      mix gettext.export_csv LOCALE [--output FILE]

  ## Examples

      mix gettext.export_csv es
      mix gettext.export_csv es --output translations/es.csv

  The CSV has columns: `domain`, `msgid`, `source`, `translation`, `fuzzy`.

  - `source` is empty — the `msgid` *is* the English source text.
  - `translation` is the `msgstr`; an empty cell is untranslated work.
  - `fuzzy` is `"yes"` when the entry needs re-checking after a source change.

  Both gettext trees are exported: the host's (`priv/gettext`, which holds the
  `theme` and `content` domains) and the library's
  (`apps/game_server_web/priv/gettext`). A `(domain, msgid)` present in both is
  one row, and `mix gettext.import_csv` writes it back to both — the same
  English string gets the same translation wherever it renders.
  """
  use Mix.Task

  @shortdoc "Export a locale's translations to CSV"

  @gettext_dirs [
    "priv/gettext",
    "apps/game_server_web/priv/gettext"
  ]

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, strict: [output: :string])

    locale = List.first(positional) || raise_usage!()
    locale_dirs = locale_dirs(locale)

    if locale_dirs == [] do
      Mix.raise("Locale not found in any gettext tree: #{locale}")
    end

    output_path = opts[:output] || "translations/#{locale}.csv"
    rows = export_rows(locale_dirs)

    File.mkdir_p!(Path.dirname(output_path))
    File.write!(output_path, encode_csv([header_row() | rows]))

    translated = Enum.count(rows, fn [_, _, _, translation, _] -> translation != "" end)

    Mix.shell().info(
      "Exported #{length(rows)} strings (#{translated} translated) to #{output_path}"
    )
  end

  defp locale_dirs(locale) do
    @gettext_dirs
    |> Enum.map(&Path.join([&1, locale, "LC_MESSAGES"]))
    |> Enum.filter(&File.dir?/1)
  end

  # A msgid shared by both trees is one row, keeping whichever copy is already
  # translated — otherwise a stale empty msgstr in one tree would hide the work
  # already done in the other.
  defp export_rows(locale_dirs) do
    locale_dirs
    |> Enum.flat_map(&po_rows/1)
    |> Enum.reduce(%{}, fn [domain, msgid, _, _, _] = row, acc ->
      Map.update(acc, {domain, msgid}, row, &better_of(&1, row))
    end)
    |> Enum.sort_by(fn {key, _row} -> key end)
    |> Enum.map(fn {_key, row} -> row end)
  end

  defp better_of([_, _, _, "", _], candidate), do: candidate
  defp better_of(existing, _candidate), do: existing

  defp po_rows(locale_dir) do
    locale_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".po"))
    |> Enum.flat_map(fn filename ->
      domain = String.replace_suffix(filename, ".po", "")
      {:ok, po} = Expo.PO.parse_file(Path.join(locale_dir, filename))

      po.messages
      |> Enum.map(&message_to_row(domain, &1))
      |> Enum.reject(fn [_, msgid, _, _, _] -> msgid == "" end)
    end)
  end

  defp header_row do
    ["domain", "msgid", "source", "translation", "fuzzy"]
  end

  defp message_to_row(domain, %Expo.Message.Singular{} = msg) do
    [
      domain,
      IO.iodata_to_binary(msg.msgid),
      "",
      IO.iodata_to_binary(msg.msgstr),
      fuzzy_cell(msg)
    ]
  end

  defp message_to_row(domain, %Expo.Message.Plural{} = msg) do
    [
      domain,
      IO.iodata_to_binary(msg.msgid),
      "",
      IO.iodata_to_binary(Map.get(msg.msgstr, 0, [])),
      fuzzy_cell(msg)
    ]
  end

  defp fuzzy_cell(msg), do: if(fuzzy?(msg), do: "yes", else: "")

  defp fuzzy?(%{flags: flags}) do
    Enum.any?(flags, fn flag_list ->
      Enum.any?(List.wrap(flag_list), &(&1 == "fuzzy"))
    end)
  end

  # Simple CSV encoding — handles quoting fields that contain commas,
  # quotes, or newlines. No external dependency needed.
  defp encode_csv(rows) do
    rows
    |> Enum.map_join("\n", fn row ->
      Enum.map_join(row, ",", &csv_escape/1)
    end)
    |> Kernel.<>("\n")
  end

  defp csv_escape(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  defp csv_escape(value), do: csv_escape(to_string(value))

  defp raise_usage! do
    Mix.raise("""
    Usage: mix gettext.export_csv LOCALE [--output FILE]

    Examples:
             mix gettext.export_csv es
             mix gettext.export_csv es --output translations/es.csv
    """)
  end
end
