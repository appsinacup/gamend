---
icon: hero-language
---

# Localization

The site ships translated into 30 languages through ordinary gettext catalogs: the database and the code hold exactly one English source string per text, and per-locale `.po` files hold the translations. Everything goes through the same pipeline (UI chrome, error messages, the theme JSON, even quest titles typed into the admin), and [/admin/translations](/admin/translations) shows how complete each locale is.

## Two catalog trees

Translations live in two gettext trees, one per owner:

- **The library's** (`apps/gamend_web/priv/gettext`) — strings gamend itself renders, in the domains `auth`, `default`, `errors`, `groups`, `leaderboards`, `lobbies`, `notifications` and `settings`.
- **The host's** (`priv/gettext`) — your game's strings: its own `default` domain, plus `theme` (text from the theme JSON) and `content` (quest, leaderboard and tournament text).

The host tree is served by its own backend, wired in with one line of config:

```elixir
config :gamend_web, host_gettext_backend: GamendHost.Gettext
```

`GamendWeb.GettextSync.put_locale/1` sets the locale on both backends at once, so a request is never half-translated.

## How a page picks its locale

Content pages worth indexing per language (about, blog index, privacy, ...) are served *at* prefixed URLs: `/es/about` renders with a 200, which is what makes the Spanish page separately indexable. App pages (the LiveViews) instead store the locale in the session and redirect to the clean path, since a LiveView reconnecting at a prefixed URL would hit an unmatched route. The default locale, `en`, is never served under a prefix, the language switcher works through a `?setlang=` parameter, URLs use the BCP-47 form (`pt-BR`) while catalogs use `pt_BR`, and right-to-left locales (`ar`, `he`, `fa`, `ur`) get `dir="rtl"`.

Two knobs tune this per host: `config :gamend_web, :localized_paths, [...]` sets which paths get indexable per-locale URLs, and `config :gamend_web, :hreflang_locales, [...]` narrows the alternates advertised to search engines when some translations are too thin to be worth pointing crawlers at.

## Adding a locale

Known locales are derived from `Gettext.known_locales/1` at **compile time**: a locale exists once its directory does, and adding one means recompiling. Create it with the standard merge task, in both trees:

```bash
mix gettext.merge priv/gettext --locale nb
mix gettext.merge apps/gamend_web/priv/gettext --locale nb
```

That writes `nb/LC_MESSAGES/*.po` files with every msgid and empty translations. Overriding an existing locale's wording is the same operation minus the flag: edit the `.po`, recompile. A missing translation always falls back to the English source, so a partly translated locale still renders.

## The CSV round-trip

Translators do not want `.po` files; they want a spreadsheet. One task exports a locale, one imports it back:

```bash
mix gettext.export_csv es                       # -> translations/es.csv
mix gettext.import_csv es translations/es.csv --dry-run
mix gettext.import_csv es translations/es.csv
```

The CSV has columns `domain`, `msgid`, `source`, `translation`, `fuzzy`. The msgid *is* the English source, an empty `translation` cell is untranslated work, and `fuzzy` marks entries needing a re-check after the source changed. Both trees are merged into the one file: a `(domain, msgid)` present in both is a single row, and the import writes it back to both, so the same English string gets the same translation wherever it renders. The import only ever updates `msgstr` (a filled-in translation also clears the fuzzy flag); new msgids never come from a CSV; those come from `mix gettext.extract --merge`.

## Theme and game content

The theme JSON is written once, in English; its text keys are translated through the `theme` domain via `mix gamend.theme.extract`. The details (which keys are translatable, and why colours and layout can never vary by locale) are in the [Theme](/docs/theme) guide's "Translating the theme" section.

Game content works the same way, extracted from the database rather than the code: `mix gamend.content.extract` writes `content.pot` from the titles and descriptions stored on quests, leaderboards and tournaments, which covers both content defined by a plugin and content typed into the admin. The row always stores the English source (never wrap a title in `gettext/1` at creation, or you freeze one locale in for every user), and `GamendWeb.ContentText` translates per viewer at render, falling back to the stored string until someone translates it.

## Tracking completeness

[/admin/translations](/admin/translations) shows a card per locale with its translated/total count and percentage, and clicking one opens a browser over every string in that locale, filterable by domain, translation status and text search. It is the page to check before announcing a language: 97% translated means someone will meet the missing 3% mid-game.

## Reference

- **Admin:** [/admin/translations](/admin/translations) - per-locale completeness and the string browser.
- **Theme text:** [Theme](/docs/theme) - the "Translating the theme" section.
- **Settings:** [Settings](/docs/settings) - `GAMEND_CONTENT_THEME_CONFIG` and friends; one theme file serves every locale.
- **Mix tasks:** `mix gettext.export_csv`, `mix gettext.import_csv`, `mix gamend.theme.extract`, `mix gamend.content.extract` - each documents itself under `mix help`.
