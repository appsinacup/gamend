defmodule GamendWeb.ContentText do
  @moduledoc """
  Translates the user-facing text stored on quests, leaderboards and
  tournaments.

  The database stores **one** string per field — the source text, in English.
  It never stores a translation. Quests and leaderboards used to keep a
  per-locale copy in `metadata["titles"][locale]`, which drifted exactly like
  the per-locale theme files did: editing the title left 29 stale copies and
  nothing said which were stale. `mix gamend.content.migrate_metadata` lifts
  any of those into the PO files.

  Translations come from the `content` domain, whose msgids
  `mix gamend.content.extract` reads back out of the database. That covers
  both origins:

    * defined in code (a plugin's `after_startup`, a seed) — extraction picks
      the row up, and a translator fills it in like any other string. A plugin
      cannot use `dgettext_noop` even if it wanted to: it is a separate Mix
      project with no `:gettext` dependency, so the macro is not in scope;
    * typed in the admin UI — extractable too, but until someone translates it
      `dgettext` falls back to the stored string, so it renders in whatever
      language it was written in.

  The one thing never to do is translate on the way *in*:

      create_quest(title: gettext("Welcome aboard"))   # freezes one locale

  That stores whichever locale the server booted in, for every user. Store the
  source, translate on the way out — which is what this module is for.

  Applied where a player-facing LiveView assigns its records. **Admin pages
  deliberately do not use it**: an admin editing a quest has to see the string
  that is actually stored, or they will "fix" a translated title and overwrite
  the source.

  ## Placeholders

  A repeat quest's title carries `%{n}` (see `Gamend.Quests.resolve_counter/2`)
  and that has to survive until *here*, because the msgid is the string with
  the placeholder in it. So the number is passed to Gettext as a binding and
  interpolated into the **translation**. Substituting it earlier looked right
  in English and quietly broke every other locale: "Treasures x 3" matches no
  msgid, so the lookup missed and the card fell back to English — while the
  bare msgid reaching `dgettext/3` without bindings logged a
  `missing Gettext bindings: [:n]` error on every anonymous page view.
  """

  alias Gamend.Quests.Quest

  @domain "content"

  @translated_fields [:title, :description]

  @doc """
  Translates one stored string into the caller's locale, falling back to the
  string itself.

  `bindings` are interpolated into the translation. Pass them for any stored
  string that contains a `%{placeholder}`; Gettext logs an error and leaves the
  placeholder raw on the page when one is missing.
  """
  @spec t(String.t() | nil, map()) :: String.t() | nil
  def t(text, bindings \\ %{})
  def t(nil, _bindings), do: nil
  def t("", _bindings), do: ""

  def t(text, bindings) when is_binary(text) do
    Gettext.dgettext(backend(), @domain, text, bindings)
  end

  @doc """
  Translates `:title` and `:description` on a record, a list of records, or a
  map of them. Anything else is returned untouched, so this is safe to apply
  to a whole assign.
  """
  @spec translate(term()) :: term()
  def translate(records) when is_list(records), do: Enum.map(records, &translate/1)

  # A quest's counter is a binding, not a substitution — see "Placeholders".
  # An unresolved one is an anonymous visitor browsing the catalog: no row, so
  # the first run (`Gamend.Quests.counter/1`).
  def translate(%Quest{} = quest) do
    bindings = %{n: Gamend.Quests.counter(quest)}

    %{quest | title: t(quest.title, bindings), description: t(quest.description, bindings)}
  end

  def translate(%_struct{} = record) do
    Enum.reduce(@translated_fields, record, fn field, acc ->
      case Map.fetch(acc, field) do
        {:ok, value} when is_binary(value) -> Map.put(acc, field, t(value))
        _ -> acc
      end
    end)
  end

  # A player-facing list is usually entries wrapping the record
  # (`%{quest: %Quest{}, progress: …}`), so recurse rather than only handling a
  # bare struct. A plain map that carries the fields itself is treated as a
  # record; anything else is walked for nested ones.
  def translate(%{} = map) do
    if Enum.any?(@translated_fields, &Map.has_key?(map, &1)) do
      Enum.reduce(@translated_fields, map, fn field, acc ->
        case Map.fetch(acc, field) do
          {:ok, value} when is_binary(value) -> Map.put(acc, field, t(value))
          _ -> acc
        end
      end)
    else
      Map.new(map, fn {key, value} -> {key, translate(value)} end)
    end
  end

  def translate(other), do: other

  # The host's backend when it has one, so a game's own `content` translations
  # are found; the library's otherwise.
  defp backend do
    Application.get_env(:gamend_web, :host_gettext_backend, GamendWeb.Gettext)
  end
end
