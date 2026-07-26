defmodule Mix.Tasks.Gamend.Content.MigrateMetadata do
  @shortdoc "Moves per-locale quest/leaderboard text out of metadata into content.po"

  @moduledoc """
  One-shot migration for instances that stored translations in the database.

      mix gamend.content.migrate_metadata            # write them into the PO files
      mix gamend.content.migrate_metadata --dry-run  # report only
      mix gamend.content.migrate_metadata --prune    # also clear the metadata keys

  Quests and leaderboards used to carry a second, per-locale copy of their text
  in `metadata["titles"][locale]` and `metadata["descriptions"][locale]`, edited
  through the admin. That is the same duplicate-store problem the theme had: a
  title edited in the admin left 29 stale copies behind it, and nothing could
  tell you which were stale.

  Translations now live in the `content` gettext domain, keyed by the source
  string. This lifts whatever is in the database into
  `priv/gettext/<locale>/LC_MESSAGES/content.po` so that curated work is not
  lost, **merging** rather than overwriting: an existing translation is never
  replaced, and a msgid that is not in the PO yet is appended.

  Run it once, check the diff, then re-run with `--prune` to clear the now-dead
  metadata keys. Without `--prune` the keys stay behind, inert - nothing reads
  them any more.
  """

  use Mix.Task

  import Ecto.Query

  alias GameServer.Repo

  @gettext_dir "priv/gettext"

  @sources [
    {GameServer.Quests.Quest, "quests"},
    {GameServer.Leaderboards.Leaderboard, "leaderboards"}
  ]

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _rest} =
      OptionParser.parse!(argv, strict: [dry_run: :boolean, prune: :boolean, gettext: :string])

    rows = Enum.flat_map(@sources, &load/1)
    by_locale = pairs_by_locale(rows)

    if by_locale == %{} do
      Mix.shell().info("no per-locale text in quest/leaderboard metadata - nothing to migrate")
    else
      Enum.each(Enum.sort(by_locale), &merge_locale(&1, opts))
      if Keyword.get(opts, :prune, false), do: prune(rows, opts)
    end
  end

  defp load({schema, label}) do
    schema
    |> from(select: [:id, :title, :description, :metadata])
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :__label__, label))
    |> Enum.map(&Map.put(&1, :__schema__module, schema))
  rescue
    error -> Mix.raise("could not read content: #{Exception.message(error)}")
  end

  # %{locale => [{source, translation}]} — the source string is the msgid, so a
  # row whose translation equals its source contributes nothing.
  defp pairs_by_locale(rows) do
    for row <- rows,
        {field, blob} <- [{:title, "titles"}, {:description, "descriptions"}],
        source = Map.get(row, field),
        is_binary(source) and String.trim(source) != "",
        {locale, translated} <- Map.get(row.metadata || %{}, blob, %{}),
        is_binary(translated),
        String.trim(translated) != "",
        translated != source,
        reduce: %{} do
      acc -> Map.update(acc, locale, [{source, translated}], &[{source, translated} | &1])
    end
    |> Map.new(fn {locale, pairs} ->
      {locale, pairs |> Enum.reverse() |> Enum.uniq_by(&elem(&1, 0))}
    end)
  end

  defp merge_locale({locale, pairs}, opts) do
    path =
      Path.join([Keyword.get(opts, :gettext, @gettext_dir), locale, "LC_MESSAGES/content.po"])

    po =
      case File.exists?(path) && Expo.PO.parse_file(path) do
        {:ok, parsed} -> parsed
        _ -> %Expo.Messages{messages: [], headers: ["Language: #{locale}\n"]}
      end

    existing = Map.new(po.messages, &{msgid(&1), &1})

    {updated, filled} =
      Enum.reduce(pairs, {0, po.messages}, fn {source, translated}, {up, msgs} ->
        case Map.get(existing, source) do
          %Expo.Message.Singular{msgstr: msgstr} = message ->
            if IO.iodata_to_binary(msgstr) == "" do
              {up + 1, replace(msgs, message, %{message | msgstr: [translated]})}
            else
              {up, msgs}
            end

          _absent_or_plural ->
            {up, msgs}
        end
      end)

    new_messages =
      for {source, translated} <- pairs,
          not Map.has_key?(existing, source),
          do: new_message(source, translated)

    added = length(new_messages)
    messages = filled ++ new_messages

    if Keyword.get(opts, :dry_run, false) do
      Mix.shell().info("#{locale}: would fill #{updated}, add #{added} -> #{path} (dry run)")
    else
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, IO.iodata_to_binary(Expo.PO.compose(%{po | messages: messages})))
      Mix.shell().info("#{locale}: filled #{updated}, added #{added} -> #{path}")
    end
  end

  defp prune(rows, opts) do
    rows
    |> Enum.filter(&stale?/1)
    |> case do
      [] ->
        Mix.shell().info("nothing to prune")

      stale ->
        if Keyword.get(opts, :dry_run, false) do
          Mix.shell().info("would clear metadata translations on #{length(stale)} row(s)")
        else
          Enum.each(stale, fn row ->
            metadata = row.metadata |> Map.delete("titles") |> Map.delete("descriptions")

            row.__schema__module
            |> from(where: [id: ^row.id])
            |> Repo.update_all(set: [metadata: metadata])
          end)

          Mix.shell().info("cleared metadata translations on #{length(stale)} row(s)")
        end
    end
  end

  defp stale?(row) do
    metadata = row.metadata || %{}
    Map.has_key?(metadata, "titles") or Map.has_key?(metadata, "descriptions")
  end

  defp msgid(%{msgid: msgid}), do: IO.iodata_to_binary(msgid)

  defp new_message(source, translated) do
    %Expo.Message.Singular{msgid: [source], msgstr: [translated]}
  end

  defp replace(messages, old, new), do: Enum.map(messages, &if(&1 == old, do: new, else: &1))
end
