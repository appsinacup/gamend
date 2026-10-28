defmodule GamendWeb.RegisterTest do
  @moduledoc """
  Core's translations speak to the reader informally in every language that
  has the choice: French `tu`, German `du`, Russian `ты`, Turkish `sen`,
  Chinese `你` (2026-10-10). A host renders core's pages (login, settings,
  notifications, quests) beside its own, and one page saying `vous` next to
  another saying `tu` reads as two sites.

  The rules are `GamendWeb.CatalogChecks`, which hosts run on their own
  catalogues too. Each rule finds the FORMAL form in one locale: the polite
  pronouns, and where a language marks the register on the verb, the polite
  verb endings.
  A verb ending also matches nouns and adjectives, so each rule carries the
  few real words it must let through (Russian `сайте`, Romanian `blocați` as
  in "utilizatori blocați"). When this test fails on a word that is not
  addressing the reader, add it to that rule's list; otherwise rewrite the
  translation informally. A plural "you" (`vous êtes déjà amis`) is reworded,
  not allowed.

  Read: core's catalogues and the example host's at the repository root.
  The same rules guard the Polyglot Pirates host (`test/gamend_host/
  register_test.exs` there).
  """
  use ExUnit.Case, async: true

  # Core's own catalogues, and the example host's at the repository root
  # (absent when core is a dependency, which reads as no files).
  @catalogues [
    Path.expand("../../priv/gettext", __DIR__),
    Path.expand("../../../../priv/gettext", __DIR__)
  ]

  alias GamendWeb.CatalogChecks

  test "every catalogue addresses the reader informally" do
    offenders = CatalogChecks.formal_address(@catalogues)

    assert offenders == [],
           "formal address (see the moduledoc for the rule):\n  " <> Enum.join(offenders, "\n  ")
  end

  test "each rule still finds the formal form it is written for" do
    samples = %{
      "fr" => "Choisissez votre langue",
      "ru" => "Выберите язык",
      "uk" => "Виберіть мову",
      "bg" => "Изберете език",
      "cs" => "Vyberte jazyk",
      "el" => "Επιλέξτε γλώσσα",
      "fi" => "Valitkaa kieli",
      "tr" => "Dili seçin",
      "ro" => "Alegeți limba",
      "de" => "Wählen Sie Ihre Sprache",
      "it" => "Scelga la Sua lingua",
      "pl" => "Proszę, niech Pan wybierze",
      "da" => "Vælg, hvad De vil",
      "no" => "Velg, hva De vil",
      "sv" => "Välj Ert språk",
      "nl" => "Kies uw taal",
      "es" => "Elija usted el idioma",
      "pt" => "Clique aqui",
      "pt_BR" => "Escolhe a tua língua",
      "hu" => "Válasszon nyelvet",
      "id" => "Pilih bahasa Anda",
      "zh_CN" => "请您选择语言",
      "zh_TW" => "請您選擇語言"
    }

    assert Map.keys(samples) |> Enum.sort() == CatalogChecks.rules() |> Map.keys() |> Enum.sort()

    for {locale, text} <- samples do
      assert CatalogChecks.formal_words(text, CatalogChecks.rules()[locale]) != [],
             "#{locale} rule misses #{inspect(text)}"
    end
  end
end
