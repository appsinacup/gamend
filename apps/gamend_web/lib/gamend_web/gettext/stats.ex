defmodule GamendWeb.Gettext.Stats do
  @moduledoc """
  Provides translation completeness statistics for a given locale.

  Parses PO files at runtime using `Expo` (a dependency of Gettext) to count
  total vs. translated strings per domain and overall.

  ## Example

      iex> GamendWeb.Gettext.Stats.completeness("es")
      %{
        locale: "es",
        domains: [
          %{domain: "auth", translated: 60, total: 60, percent: 100.0},
          ...
        ],
        translated: 366,
        total: 366,
        percent: 100.0
      }
  """

  require GamendWeb.Gettext.TranslationFilter, as: TranslationFilter
  require Gamend.LocaleCode, as: LocaleCode

  @priv_dir :code.priv_dir(:gamend_web) |> to_string()
  @gettext_dir Path.join(@priv_dir, "gettext")

  @doc """
  Returns a list of available non-default locale codes (e.g. `["es"]`).

  Discovers locales by listing directories in the gettext priv folder,
  excluding `"en"` (the default/source locale).
  """
  @spec locales() :: [String.t()]
  def locales do
    case File.ls(@gettext_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn entry ->
          entry != LocaleCode.en() and
            File.dir?(Path.join(@gettext_dir, entry)) and
            not String.ends_with?(entry, ".pot")
        end)
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  @doc """
  Returns completeness stats for all non-default locales.

  Returns a list of maps (one per locale), same shape as `completeness/1`.
  """
  @spec all_completeness() :: [map()]
  def all_completeness do
    Enum.map(locales(), &completeness/1)
  end

  @doc """
  Returns translation completeness stats for the given locale.

  Returns a map with `:locale`, `:domains` (list of per-domain stats),
  `:translated`, `:total`, and `:percent` keys.
  """
  @spec completeness(String.t()) :: map()
  def completeness(locale) when is_binary(locale) do
    po_dir = Path.join([@gettext_dir, locale, "LC_MESSAGES"])

    domains =
      case File.ls(po_dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".po"))
          |> Enum.sort()
          |> Enum.map(fn filename ->
            domain = String.trim_trailing(filename, ".po")
            path = Path.join(po_dir, filename)
            domain_stats(domain, path)
          end)

        {:error, _} ->
          []
      end

    total = Enum.reduce(domains, 0, fn d, acc -> acc + d.total end)
    translated = Enum.reduce(domains, 0, fn d, acc -> acc + d.translated end)

    %{
      locale: locale,
      domains: domains,
      translated: translated,
      total: total,
      percent: if(total > 0, do: Float.round(translated / total * 100, 1), else: 0.0)
    }
  end

  @doc """
  Returns a compact summary string like `"es: 366/373 (98.1%)"`.
  """
  @spec summary(String.t()) :: String.t()
  def summary(locale) do
    stats = completeness(locale)
    "#{locale}: #{stats.translated}/#{stats.total} (#{stats.percent}%)"
  end

  @doc """
  Returns all translation strings for a given locale.

  Each entry is a map with `:domain`, `:msgid`, `:msgstr`, and `:translated?` keys.
  Optionally filter by domain and/or search query.

  Options:
    - `:domain` - filter to a specific domain (e.g. `"auth"`)
    - `:search` - case-insensitive substring search on msgid or msgstr
    - `:status` - `"translated"`, `"untranslated"`, or `nil` for all
  """
  @spec list_strings(String.t(), keyword()) :: [map()]
  def list_strings(locale, opts \\ []) when is_binary(locale) do
    po_dir = Path.join([@gettext_dir, locale, "LC_MESSAGES"])
    domain_filter = Keyword.get(opts, :domain)
    search = Keyword.get(opts, :search)
    status_filter = Keyword.get(opts, :status)

    search_down = if search && search != "", do: String.downcase(search), else: nil

    case File.ls(po_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".po"))
        |> Enum.sort()
        |> Enum.flat_map(fn filename ->
          domain = String.trim_trailing(filename, ".po")

          if domain_filter && domain_filter != "" && domain != domain_filter do
            []
          else
            path = Path.join(po_dir, filename)
            parse_strings(domain, path)
          end
        end)
        |> maybe_filter_status(status_filter)
        |> maybe_filter_search(search_down)

      {:error, _} ->
        []
    end
  end

  @doc """
  Returns the list of available domains for a locale.
  """
  @spec domains(String.t()) :: [String.t()]
  def domains(locale) when is_binary(locale) do
    po_dir = Path.join([@gettext_dir, locale, "LC_MESSAGES"])

    case File.ls(po_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".po"))
        |> Enum.sort()
        |> Enum.map(&String.trim_trailing(&1, ".po"))

      {:error, _} ->
        []
    end
  end

  defp parse_strings(domain, path) do
    case Expo.PO.parse_file(path) do
      {:ok, %Expo.Messages{messages: messages}} ->
        messages
        |> Enum.reject(&header?/1)
        |> Enum.map(fn msg ->
          msgid = extract_msgid(msg)
          msgstr = extract_msgstr(msg)
          is_translated = translated?(msg)

          %{
            domain: domain,
            msgid: msgid,
            msgstr: msgstr,
            translated?: is_translated
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp extract_msgid(%Expo.Message.Singular{msgid: parts}), do: IO.iodata_to_binary(parts)
  defp extract_msgid(%Expo.Message.Plural{msgid: parts}), do: IO.iodata_to_binary(parts)

  defp extract_msgstr(%Expo.Message.Singular{msgstr: parts}), do: IO.iodata_to_binary(parts)

  defp extract_msgstr(%Expo.Message.Plural{msgstr: msgstr}) do
    msgstr
    |> Enum.sort_by(fn {idx, _} -> idx end)
    |> Enum.map_join(" | ", fn {_idx, parts} -> IO.iodata_to_binary(parts) end)
  end

  defp maybe_filter_status(strings, nil), do: strings
  defp maybe_filter_status(strings, ""), do: strings

  defp maybe_filter_status(strings, TranslationFilter.translated()),
    do: Enum.filter(strings, & &1.translated?)

  defp maybe_filter_status(strings, TranslationFilter.untranslated()),
    do: Enum.reject(strings, & &1.translated?)

  defp maybe_filter_status(strings, _), do: strings

  defp maybe_filter_search(strings, nil), do: strings

  defp maybe_filter_search(strings, search) do
    Enum.filter(strings, fn s ->
      String.contains?(String.downcase(s.msgid), search) ||
        String.contains?(String.downcase(s.msgstr), search)
    end)
  end

  defp domain_stats(domain, path) do
    case Expo.PO.parse_file(path) do
      {:ok, %Expo.Messages{messages: messages}} ->
        # Filter out the header entry (empty msgid)
        entries = Enum.reject(messages, &header?/1)
        total = length(entries)
        translated = Enum.count(entries, &translated?/1)

        %{
          domain: domain,
          translated: translated,
          total: total,
          percent: if(total > 0, do: Float.round(translated / total * 100, 1), else: 0.0)
        }

      {:error, _} ->
        %{domain: domain, translated: 0, total: 0, percent: 0.0}
    end
  end

  defp header?(%Expo.Message.Singular{msgid: [""]}), do: true
  defp header?(_), do: false

  defp translated?(%Expo.Message.Singular{msgstr: msgstr}) do
    msgstr != [""]
  end

  defp translated?(%Expo.Message.Plural{msgstr: msgstr}) do
    Enum.all?(msgstr, fn {_idx, strs} -> strs != [""] end)
  end
end
