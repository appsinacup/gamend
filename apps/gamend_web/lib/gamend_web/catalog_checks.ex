defmodule GamendWeb.CatalogChecks do
  @moduledoc """
  Two rules every catalogue on a Gamend site keeps, as functions that core's
  tests and a host's run on their own `priv/gettext` (core's
  `register_test.exs` and `spelling_test.exs`, Forge's and Gamend Cloud's
  `translations_test.exs`):

    * translations speak to the reader informally, in every language that
      has the choice (`formal_address/1`): French `tu`, German `du`,
      Russian `ты`, Turkish `sen`, Chinese `你` (2026-10-10). A host renders
      core's pages beside its own, and one page saying `vous` next to
      another saying `tu` reads as two sites. Each rule finds the FORMAL
      form in one locale, with the few real words it lets through;
    * msgids are American English (`british_spellings/1`): `canceled`,
      `color`, `organize`, `license`;
    * a translation keeps its msgid's placeholders (`placeholder_mismatches/1`):
      a `%{name}` left out or misspelled renders as nothing, or raises.
  """

  defp w(pattern, opts \\ "iu"), do: Regex.compile!("(?<!\\w)(?:#{pattern})(?!\\w)", opts)
  defp mid(pattern), do: Regex.compile!("(?<=[\\w,] )(?:#{pattern})(?!\\w)", "u")

  @doc "The formal forms of address, by locale: `{regex, words it lets through}`."
  @spec rules() :: %{String.t() => [{Regex.t(), [String.t()]}]}
  def rules do
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

  defp translations(roots, locale) do
    for root <- roots,
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

  @doc "The words of `text` a locale's rules find formal."
  @spec formal_words(String.t(), [{Regex.t(), [String.t()]}]) :: [String.t()]
  def formal_words(text, rules) do
    for {regex, allowed} <- rules,
        [word | _] <- Regex.scan(regex, text),
        String.downcase(word) not in allowed,
        do: word
  end

  @doc """
  Every translation under `roots` (each a `priv/gettext`) that addresses
  the reader formally, as `"locale/domain [words]: msgid"`.
  """
  @spec formal_address([Path.t()]) :: [String.t()]
  def formal_address(roots) do
    for {locale, rules} <- rules(),
        {domain, msgid, text} <- translations(roots, locale),
        # A placeholder is a value, read as a number: Dutch `u` is formal,
        # `%{u}` is not, and `%{count}u` stays hours (`uur`).
        words = formal_words(Regex.replace(~r/%\{[a-z_]+\}/, text, "0"), rules),
        words != [],
        do: "#{locale}/#{domain} #{inspect(Enum.uniq(words))}: #{String.slice(msgid, 0, 70)}"
  end

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

  @doc "The British spellings in `text`, each `\"name: word -> suggestion\"`."
  @spec british_words(String.t(), String.t()) :: [String.t()]
  def british_words(name, text) do
    text = Regex.replace(~r/`[^`\n]*`/u, text, "")

    for [word] <- Regex.scan(regex(), text),
        uniq: true,
        do: "#{name}: #{word} -> #{suggestion(word)}"
  end

  defp msgids(%Expo.Message.Plural{msgid: id, msgid_plural: plural}),
    do: [IO.iodata_to_binary(id), IO.iodata_to_binary(plural)]

  defp msgids(%Expo.Message.Singular{msgid: id}), do: [IO.iodata_to_binary(id)]

  @doc "Every British spelling in a msgid of the templates (`*.pot`) under `roots`."
  @spec british_spellings([Path.t()]) :: [String.t()]
  def british_spellings(roots) do
    for root <- roots,
        path <- Path.wildcard(Path.join(root, "*.pot")),
        message <- Expo.PO.parse_file!(path).messages,
        text <- msgids(message),
        hit <- british_words(String.slice(text, 0, 60), text),
        do: hit
  end

  @placeholder ~r/%\{[a-z_]+\}/

  @doc """
  Every translation under `roots` whose placeholders are not its msgid's,
  as `"locale/domain: msgid -> translation"`. A plural form may leave out
  `%{count}` (a language's "one" form often does), nothing else.
  """
  @spec placeholder_mismatches([Path.t()]) :: [String.t()]
  def placeholder_mismatches(roots) do
    for root <- roots,
        path <- Path.wildcard(Path.join([root, "*", "LC_MESSAGES", "*.po"])),
        message <- Expo.PO.parse_file!(path).messages,
        not message.obsolete,
        wanted = placeholders(Enum.join(msgids(message), " ")),
        text <- translated(message),
        have = placeholders(text),
        not MapSet.subset?(have, wanted) or
          not MapSet.subset?(MapSet.delete(wanted, "%{count}"), have),
        do:
          "#{path |> Path.dirname() |> Path.dirname() |> Path.basename()}/" <>
            "#{Path.basename(path, ".po")}: #{String.slice(hd(msgids(message)), 0, 50)} -> #{text}"
  end

  defp placeholders(text), do: @placeholder |> Regex.scan(text) |> List.flatten() |> MapSet.new()

  defp translated(%Expo.Message.Singular{msgstr: s}),
    do: Enum.reject([IO.iodata_to_binary(s)], &(&1 == ""))

  defp translated(%Expo.Message.Plural{msgstr: forms}),
    do: forms |> Map.values() |> Enum.map(&IO.iodata_to_binary/1) |> Enum.reject(&(&1 == ""))
end
