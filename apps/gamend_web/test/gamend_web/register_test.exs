defmodule GamendWeb.RegisterTest do
  @moduledoc """
  Core's translations speak to the reader informally in every language that
  has the choice: French `tu`, German `du`, Russian `ты`, Turkish `sen`,
  Chinese `你` (2026-10-10). A host renders core's pages (login, settings,
  notifications, quests) beside its own, and one page saying `vous` next to
  another saying `tu` reads as two sites.

  Each rule finds the FORMAL form in one locale: the polite pronouns, and
  where a language marks the register on the verb, the polite verb endings.
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

  defp w(pattern, opts \\ "iu"), do: Regex.compile!("(?<!\\w)(?:#{pattern})(?!\\w)", opts)
  defp mid(pattern), do: Regex.compile!("(?<=[\\w,] )(?:#{pattern})(?!\\w)", "u")

  defp rules do
    %{
      "fr" => [
        {w("vous|votre|vos"), []},
        {w("\\w+ez"), ~w(chez assez nez rez)}
      ],
      "ru" => [
        {w("вы|вас|вам|ваш\\w*|вами"), []},
        {w(
           "\\w+(?:йтесь|итесь|ьтесь|етесь|ётесь|аете|яете|еете|уете|юете|шете|чете|щете)|можете|сможете|поможете|хотите"
         ), []},
        {w("\\w+(?:йте|ьте|ите)"),
         ~w(сайте алфавите лимите кредите ките пресс-ките бите сюите визите транзите граните аппетите)}
      ],
      "uk" => [
        {w("ви|вас|вам|ваш\\w*|вами"), []},
        {w("\\w+[бвгґджзклмнпрсфхцчшщ]те"), ~w(просте чисте пусте густе місте тексте сайте)},
        {w(
           "\\w+(?:іть|йте|ьте|йтеся|йтесь|іться|ітеся|ітесь|ете|єте|ите|їте|етеся|єтеся|итеся|етесь|єтесь|итесь)"
         ), ~w(навіть повіть кість вість мідь сайті)}
      ],
      "bg" => [
        {w("вие|вас|ваш\\w*|ви"), []},
        {w("\\w+(?:ате|яте)|сте|\\w+[бвгджзклмнпрсфхцчшщ]те"), ~w(тесте чете)},
        {w("\\w+йте"), []},
        # -ете is the 2pl ending, and also a plural noun's (`детете`, `ловове`).
        {Regex.compile!("(?<!\\w)\\w+(?<!ов)(?<!ев)ете(?!\\w)", "iu"), ~w(детете дете двете чете)}
      ],
      "cs" => [
        {w("vy|vás|vám|váš|vaš\\w+|vámi"), []},
        {w("\\w+(?:áte|íte|ete|ěte|ejte|ijte|ujte|yjte|ste|[bcčdďfghjklmnňprřsštťvzž]te)"),
         ~w(dítěte ještě)}
      ],
      "el" => [
        {w("εσείς|σας"), []},
        # -τε is the 2pl ending, and the ending of a handful of adverbs.
        {w("\\w+τε(?<!δήποτε)(?<!μαστε)"),
         ~w(τότε πότε ποτέ όποτε κάποτε ώστε ούτε μήτε είτε πάντοτε οπότε ουδέποτε πώποτε ορίστε πέντε)}
      ],
      "fi" => [
        {w("te|teidän|teitä|teille|teiltä|teillä|teissä"), []},
        {w("\\w+(?:tkaa|tkää|tte)"), ~w(matkaa jatkaa)}
      ],
      "tr" => [
        {w("siz|sizin|size|sizi|sizden|sizinle"), []},
        {w("\\w+(?:siniz|sınız|sunuz|sünüz)"), []},
        {w("kendiniz\\w*|\\w+(?:[dt][ıiuü][ğk][ıiuü]n[ıiuü]z|sanız|seniz)\\w*"), []},
        # The polite imperative (-in) is also a noun's genitive, so it is
        # listed by verb rather than matched by ending. `sorun` is left out:
        # it is also "problem".
        {w(
           "seçin|deneyin|girin|yazın|tıklayın|kullanın|indirin|oynayın|öğrenin|bakın|bulun|başlayın|ekleyin|edin|olun|yapın|alın|verin|gönderin|açın|bekleyin|ulaşın|belirtin|kaydolun|tutun|değiştirmeyin|kullanmayın|söyleyin|geçin"
         ), []}
      ],
      "ro" => [
        {w("dumneavoastră|dvs|voastră|vostru|voștri|voastre|vă"), []},
        {Regex.compile!("(?<!\\w)v-", "u"), []},
        # -ați/-eți is the 2pl ending, and a plural noun's or participle's.
        {w("\\w+(?:ați|eți)"),
         ~w(înveți vieți băieți poeți atleți profeți frați cumnați soldați avocați candidați delegați
            împărați salariați bărbați ați piloți unități noutăți plăți abilități calități
            activități posibilități navigați blocați conectați)}
      ],
      "de" => [
        {Regex.compile!(
           "(?<=[\\wäöüß,] )(?:Sie|Ihr|Ihre|Ihren|Ihrem|Ihrer|Ihres|Ihnen)(?!\\w)",
           "u"
         ), []}
      ],
      "it" => [{mid("Lei|Suo|Sua|Suoi|Sue"), []}],
      "pl" => [{mid("Pan|Pani|Pana|Panu|Państwo|Państwa"), []}],
      "da" => [{mid("De|Dem|Deres"), []}],
      "no" => [{mid("De|Dem|Deres"), []}],
      "sv" => [{w("Ni|Er|Era|Ert", "u"), []}],
      # `u` after a number is "uur", hours (`%{n}u`, `24 u`).
      "nl" => [{Regex.compile!("(?<![\\w}])(?<!\\d )(?<!\\} )(?:u|uw|U|Uw)(?!\\w)", "u"), []}],
      "es" => [{w("usted|ustedes"), []}],
      "pt" => [
        {w("você|vocês"), []},
        # European Portuguese tu: the third-person imperative is the polite one.
        # `Escolha` is also the noun "choice".
        {w(
           "Escolha|Tente|Selecione|Insira|Clique|Faça|Veja|Adicione|Verifique|Digite|Escreva|Abra|Jogue|Aprenda|Descarregue|Baixe|Experimente|Encontre|Crie|Leia|Adivinhe|Registe-se|Inicie",
           "u"
         ), ~w(escolha)}
      ],
      # Brazilian Portuguese: você IS the informal form; tu reads as regional.
      "pt_BR" => [{w("tu|teu|tua|teus|tuas|contigo"), []}],
      "hu" => [
        {w("Ön|Önök|Önnek|Önt|Önnel|Öntől|Önhöz|Öné|Önre", "u"), []},
        {w(
           "Válasszon|Kattintson|Próbálja|Adja|Írja|Nyomja|Töltse|Jelentkezzen|Lépjen|Játsszon|Tanuljon|Nézze|Keressen|Töltsön|Ellenőrizze|Hozzon|Olvassa|Találja|Regisztráljon",
           "u"
         ), []}
      ],
      "id" => [{w("Anda", "u"), []}],
      "zh_CN" => [{~r/您/u, []}],
      "zh_TW" => [{~r/您/u, []}]
    }
  end

  defp translations(locale) do
    for root <- @catalogues,
        path <- Path.wildcard(Path.join([root, locale, "LC_MESSAGES", "*.po"])),
        message <- Expo.PO.parse_file!(path).messages,
        not message.obsolete,
        text = msgstr(message),
        text != "",
        do: {Path.basename(path, ".po"), IO.iodata_to_binary(message.msgid), text}
  end

  defp msgstr(%Expo.Message.Singular{msgstr: s}), do: IO.iodata_to_binary(s)

  defp msgstr(%Expo.Message.Plural{msgstr: forms}),
    do: forms |> Map.values() |> Enum.map_join(" || ", &IO.iodata_to_binary/1)

  defp formal_words(text, rules) do
    for {regex, allowed} <- rules,
        [word | _] <- Regex.scan(regex, text),
        String.downcase(word) not in allowed,
        do: word
  end

  test "every catalogue addresses the reader informally" do
    offenders =
      for {locale, rules} <- rules(),
          {domain, msgid, text} <- translations(locale),
          words = formal_words(text, rules),
          words != [],
          do: "#{locale}/#{domain} #{inspect(Enum.uniq(words))}: #{String.slice(msgid, 0, 70)}"

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

    assert Map.keys(samples) |> Enum.sort() == rules() |> Map.keys() |> Enum.sort()

    for {locale, text} <- samples do
      assert formal_words(text, rules()[locale]) != [], "#{locale} rule misses #{inspect(text)}"
    end
  end
end
