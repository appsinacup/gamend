defmodule Mix.Tasks.Gettext.ImportCsv do
  @moduledoc """
  Imports reviewed translations from a CSV back into the PO files.

  ## Usage

      mix gettext.import_csv LOCALE FILE [--dry-run]

  ## Examples

      mix gettext.import_csv es translations/es.csv
      mix gettext.import_csv es translations/es.csv --dry-run

  The CSV must have at minimum the columns: `domain`, `msgid`, `translation`.
  Optional columns: `source`, `fuzzy`.

  Rows are matched by `(domain, msgid)` and only the `msgstr` is updated; a
  filled-in translation also clears the `fuzzy` flag. New msgids are never
  added — those come from `mix gettext.extract --merge`.

  Both gettext trees are searched, so a msgid that renders from the host
  (`priv/gettext`) and from the library
  (`apps/game_server_web/priv/gettext`) is updated in both.

  Use `--dry-run` to preview changes without writing files.
  """
  use Mix.Task

  @shortdoc "Import reviewed translations from CSV into PO files"

  @gettext_dirs [
    "priv/gettext",
    "apps/game_server_web/priv/gettext"
  ]

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, strict: [dry_run: :boolean])

    dry_run? = opts[:dry_run] || false

    case positional do
      [locale, csv_path] -> do_import(locale, csv_path, dry_run?)
      _ -> raise_usage!()
    end
  end

  defp do_import(locale, csv_path, dry_run?) do
    locale_dirs =
      @gettext_dirs
      |> Enum.map(&Path.join([&1, locale, "LC_MESSAGES"]))
      |> Enum.filter(&File.dir?/1)

    if locale_dirs == [] do
      Mix.raise("Locale not found in any gettext tree: #{locale}")
    end

    unless File.exists?(csv_path) do
      Mix.raise("CSV file not found: #{csv_path}")
    end

    translations = parse_csv(csv_path)

    {stats, files_written} =
      for locale_dir <- locale_dirs,
          {domain, entries} <- Enum.sort_by(translations, &elem(&1, 0)),
          reduce: {%{updated: 0, skipped: 0, not_found: 0}, 0} do
        {acc_stats, acc_files} ->
          po_path = Path.join(locale_dir, "#{domain}.po")

          if File.exists?(po_path) do
            {domain_stats, written?} = update_po_file(po_path, entries, dry_run?)

            {merge_stats(acc_stats, domain_stats), acc_files + if(written?, do: 1, else: 0)}
          else
            {acc_stats, acc_files}
          end
      end

    unmatched = unmatched_count(translations, locale_dirs)
    prefix = if dry_run?, do: "[DRY RUN] ", else: ""

    Mix.shell().info("""

    #{prefix}Import complete:
      Updated: #{stats.updated}
      Unchanged: #{stats.skipped}
      No such msgid in any domain: #{unmatched}
      Files written: #{files_written}
    """)
  end

  defp merge_stats(a, b) do
    %{updated: a.updated + b.updated, skipped: a.skipped + b.skipped, not_found: 0}
  end

  # A CSV row can legitimately match nothing in one tree while matching in the
  # other, so "not found" is only meaningful across all of them at once.
  defp unmatched_count(translations, locale_dirs) do
    present =
      for locale_dir <- locale_dirs,
          filename <- File.ls!(locale_dir),
          String.ends_with?(filename, ".po"),
          {:ok, po} = Expo.PO.parse_file(Path.join(locale_dir, filename)),
          message <- po.messages,
          into: MapSet.new() do
        {String.replace_suffix(filename, ".po", ""), extract_msgid(message)}
      end

    for({domain, entries} <- translations, msgid <- Map.keys(entries), do: {domain, msgid})
    |> Enum.count(&(&1 not in present))
  end

  defp update_po_file(po_path, entries, dry_run?) do
    {:ok, po} = Expo.PO.parse_file(po_path)

    {updated_messages, stats} =
      Enum.map_reduce(po.messages, %{updated: 0, skipped: 0, not_found: 0}, fn msg, acc ->
        msgid_key = extract_msgid(msg)

        case Map.get(entries, msgid_key) do
          nil ->
            {msg, acc}

          row ->
            case apply_translation(msg, row) do
              {:changed, new_msg} ->
                {new_msg, %{acc | updated: acc.updated + 1}}

              :unchanged ->
                {msg, %{acc | skipped: acc.skipped + 1}}
            end
        end
      end)

    written? =
      if stats.updated > 0 and not dry_run? do
        updated_po = %{po | messages: updated_messages}
        content = Expo.PO.compose(updated_po) |> IO.iodata_to_binary()
        File.write!(po_path, content)
        domain = Path.basename(po_path, ".po")
        Mix.shell().info("  Wrote #{stats.updated} updates to #{domain}.po")
        true
      else
        if stats.updated > 0 do
          domain = Path.basename(po_path, ".po")
          Mix.shell().info("  [DRY RUN] Would update #{stats.updated} entries in #{domain}.po")
        end

        false
      end

    {stats, written?}
  end

  defp extract_msgid(%Expo.Message.Singular{msgid: msgid}),
    do: IO.iodata_to_binary(msgid)

  defp extract_msgid(%Expo.Message.Plural{msgid: msgid}),
    do: IO.iodata_to_binary(msgid)

  defp apply_translation(%Expo.Message.Singular{} = msg, row) do
    new_translation = row[:translation] || ""
    current = IO.iodata_to_binary(msg.msgstr)

    if new_translation != "" and new_translation != current do
      new_msg = %{msg | msgstr: [new_translation]}
      # Remove fuzzy flag if translation is filled
      new_msg = remove_fuzzy(new_msg)
      {:changed, new_msg}
    else
      :unchanged
    end
  end

  defp apply_translation(%Expo.Message.Plural{} = msg, row) do
    new_0 = row[:translation] || ""
    current_0 = IO.iodata_to_binary(Map.get(msg.msgstr, 0, []))

    if new_0 != "" and new_0 != current_0 do
      new_msgstr = Map.put(msg.msgstr, 0, [new_0])
      new_msg = %{msg | msgstr: new_msgstr}
      new_msg = remove_fuzzy(new_msg)
      {:changed, new_msg}
    else
      :unchanged
    end
  end

  defp remove_fuzzy(%{flags: flags} = msg) do
    new_flags =
      Enum.map(flags, fn flag_list ->
        flag_list
        |> List.wrap()
        |> Enum.reject(&(&1 == "fuzzy"))
      end)
      |> Enum.reject(&(&1 == []))

    %{msg | flags: new_flags}
  end

  # ------------------------------------------------------------------
  # Minimal CSV parser — handles quoted fields, commas, newlines in
  # quoted values. No external dependency needed.
  # ------------------------------------------------------------------

  defp parse_csv(path) do
    content = File.read!(path)
    [header_line | data_lines] = csv_split_rows(content)
    headers = csv_split_fields(header_line)

    col_index = fn name ->
      Enum.find_index(headers, &(String.trim(&1) == name))
    end

    domain_idx = col_index.("domain") || raise_csv_error!("domain")
    msgid_idx = col_index.("msgid") || raise_csv_error!("msgid")
    translation_idx = col_index.("translation") || raise_csv_error!("translation")
    source_idx = col_index.("source") || col_index.("msgid_plural")

    data_lines
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.reduce(%{}, fn line, acc ->
      fields = csv_split_fields(line)
      get = fn idx -> if idx, do: Enum.at(fields, idx, ""), else: "" end

      domain = String.trim(get.(domain_idx))
      msgid = get.(msgid_idx)

      if domain == "" or msgid == "" do
        acc
      else
        row = %{
          msgid: msgid,
          source: get.(source_idx),
          translation: get.(translation_idx)
        }

        domain_map = Map.get(acc, domain, %{})
        Map.put(acc, domain, Map.put(domain_map, msgid, row))
      end
    end)
  end

  # Split CSV content into rows, respecting quoted fields that span
  # multiple lines.
  defp csv_split_rows(content) do
    content
    |> String.split("\n")
    |> merge_quoted_rows([])
    |> Enum.reverse()
  end

  defp merge_quoted_rows([], acc), do: acc

  defp merge_quoted_rows([line | rest], acc) do
    if balanced_quotes?(line) do
      merge_quoted_rows(rest, [line | acc])
    else
      # Line has unclosed quote — merge with next lines until balanced
      {merged, remaining} = consume_until_balanced(rest, line)
      merge_quoted_rows(remaining, [merged | acc])
    end
  end

  defp consume_until_balanced([], accumulated), do: {accumulated, []}

  defp consume_until_balanced([line | rest], accumulated) do
    merged = accumulated <> "\n" <> line

    if balanced_quotes?(merged) do
      {merged, rest}
    else
      consume_until_balanced(rest, merged)
    end
  end

  defp balanced_quotes?(str) do
    str
    |> String.graphemes()
    |> Enum.count(&(&1 == "\""))
    |> rem(2) == 0
  end

  # Split a single CSV row into fields, respecting quoted values.
  defp csv_split_fields(line) do
    do_split_fields(String.trim_trailing(line, "\r"), [], "", false)
  end

  defp do_split_fields("", acc, current, _in_quote) do
    Enum.reverse([current | acc])
  end

  defp do_split_fields(<<"\"\"", rest::binary>>, acc, current, true) do
    # Escaped quote inside quoted field
    do_split_fields(rest, acc, current <> "\"", true)
  end

  defp do_split_fields(<<"\"", rest::binary>>, acc, current, false) do
    # Start of quoted field
    do_split_fields(rest, acc, current, true)
  end

  defp do_split_fields(<<"\"", rest::binary>>, acc, current, true) do
    # End of quoted field
    do_split_fields(rest, acc, current, false)
  end

  defp do_split_fields(<<",", rest::binary>>, acc, current, false) do
    # Field separator (not inside quotes)
    do_split_fields(rest, [current | acc], "", false)
  end

  defp do_split_fields(<<ch::utf8, rest::binary>>, acc, current, in_quote) do
    do_split_fields(rest, acc, current <> <<ch::utf8>>, in_quote)
  end

  @spec raise_csv_error!(String.t()) :: no_return()
  defp raise_csv_error!(column) do
    Mix.raise("CSV file must have a '#{column}' column header")
  end

  @spec raise_usage!() :: no_return()
  defp raise_usage! do
    Mix.raise("""
    Usage: mix gettext.import_csv LOCALE FILE [--dry-run]

    Examples:
             mix gettext.import_csv es translations/es.csv
             mix gettext.import_csv es translations/es.csv --dry-run
    """)
  end
end
