defmodule GamendWeb.SpellingTest do
  @moduledoc """
  Core's English is American (2026-10-10): `canceled`, `color`, `organize`,
  `license`. Hosts render core's pages beside their own, and the Polyglot
  Pirates host holds its own msgids to the same list
  (`test/gamend_host/spelling_test.exs` there), so a British spelling here
  shows up as the odd one out on the same site.

  Checked: every msgid core's catalogues hold (`priv/gettext/*.pot`).
  """
  use ExUnit.Case, async: true

  @gettext Path.expand("../../priv/gettext", __DIR__)

  # British spelling => the one to use. Stems, matched at the start of a word,
  # so `practise` also finds `practised` and `Practising`. Listed one by one
  # rather than as an `-ise` rule: `exercise`, `advise` and `surprise` are
  # American too.
  @british %{
    "practis" => "practic",
    "colour" => "color",
    "favourite" => "favorite",
    "kilometre" => "kilometer",
    "centimetre" => "centimeter",
    "centre" => "center",
    "organis" => "organiz",
    "recognis" => "recogniz",
    "customis" => "customiz",
    "personalis" => "personaliz",
    "memoris" => "memoriz",
    "categoris" => "categoriz",
    "realis" => "realiz",
    "apologis" => "apologiz",
    "licence" => "license",
    "cancelled" => "canceled",
    "cancelling" => "canceling",
    "travelled" => "traveled",
    "travelling" => "traveling",
    "labelled" => "labeled",
    "behaviour" => "behavior",
    "honour" => "honor",
    "neighbour" => "neighbor",
    "harbour" => "harbor",
    "catalogue" => "catalog",
    "analyse" => "analyze",
    "grey" => "gray",
    "spelt" => "spelled",
    "learnt" => "learned",
    "towards" => "toward",
    "whilst" => "while",
    "amongst" => "among",
    "enrol" => "enroll",
    "jewellery" => "jewelry",
    "programme" => "program"
  }

  # Whole words only where a stem would catch an American word too.
  @whole_word ~w(grey spelt learnt towards whilst amongst enrol programme)

  # An `-is` stem only before what makes it the verb: `realis` alone would
  # find `realistic`, `organis` `organism`.
  @is_stems ~w(organis recognis customis personalis memoris categoris realis apologis)

  defp regex do
    stems =
      @british
      |> Map.keys()
      |> Enum.reject(&(&1 in @whole_word))
      |> Enum.map(&if(&1 in @is_stems, do: &1 <> "(?=e|ing|ation|ab)", else: &1))

    Regex.compile!(
      "\\b(?:(?:#{Enum.join(stems, "|")})\\w*|(?:#{Enum.join(@whole_word, "|")})\\b)",
      "iu"
    )
  end

  defp suggestion(word) do
    lower = String.downcase(word)

    case Enum.find(@british, fn {uk, _us} -> String.starts_with?(lower, uk) end) do
      {uk, us} -> us <> String.replace_prefix(lower, uk, "")
      nil -> "?"
    end
  end

  defp offenders(name, text) do
    text = Regex.replace(~r/`[^`\n]*`/u, text, "")

    for [word] <- Regex.scan(regex(), text),
        uniq: true,
        do: "#{name}: #{word} -> #{suggestion(word)}"
  end

  defp msgids(%Expo.Message.Plural{msgid: id, msgid_plural: plural}),
    do: [IO.iodata_to_binary(id), IO.iodata_to_binary(plural)]

  defp msgids(%Expo.Message.Singular{msgid: id}), do: [IO.iodata_to_binary(id)]

  test "msgids use American spelling" do
    found =
      for path <- Path.wildcard(Path.join(@gettext, "*.pot")),
          message <- Expo.PO.parse_file!(path).messages,
          text <- msgids(message),
          hit <- offenders(String.slice(text, 0, 60), text),
          do: hit

    assert found == [], "British spelling in a msgid:\n  " <> Enum.join(found, "\n  ")
  end

  test "the list finds what it is written for, and spares American words" do
    assert offenders("x", "Practise your colours, organised by kilometre.") != []

    assert offenders("x", "Exercise, advise, surprise, practice, analysis, realistic, `analyse`") ==
             []
  end
end
