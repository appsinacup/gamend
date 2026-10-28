# `mix gamend.content.extract`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.content.extract.ex#L1)

Writes `content.pot` from the titles and descriptions stored on quests,
leaderboards and tournaments, and the names a quest gives its item rewards
(`metadata["reward_names"]`).

    mix gamend.content.extract          # write the template
    mix gamend.content.extract --check  # fail if it is out of date
    mix gamend.content.extract -o PATH  # write somewhere else

## Why from the database rather than from source

The obvious approach is `dgettext_noop("content", "Welcome aboard")` at each
definition site, letting `mix gettext.extract` find it. That does not work
here, for two reasons:

  * **plugins cannot use it.** A plugin is its own Mix project and does not
    depend on `:gettext`, so the macro is not in scope — and plugins are
    where a game defines its content.
  * **it would miss everything an admin creates.** Admin-typed titles never
    appear in source at all.

Reading the rows covers both, and matches how the theme is extracted: from
the data, not from the code that produced it. Run it after seeding or after
an admin adds content, then `mix gettext.merge` and translate.

Text still reaches the database as the **source** string — never wrap a title
in `gettext/1` at creation, or you freeze one locale in for every user.
`GamendWeb.ContentText` translates per viewer at render.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
