# Translations (gitignored)

Local working directory for translation CSV files.
These files are **not committed** — they are working files for translators.

| Strings | Domains | Languages |
|---------|---------|-----------|
| 352 | default (242), theme (55), errors (30), content (20), notifications (5) | 30 |

Both gettext trees are exported into the one CSV: the host's `priv/gettext`
(which owns `theme` and `content`) and the library's
`apps/game_server_web/priv/gettext`. A msgid that appears in both is one row,
and importing writes it back to both.

`theme` is the site copy from `theme/config.json` — refresh it with
`mix gamend.theme.extract`. `content` is quest, leaderboard and tournament
text read straight from the database — refresh it with
`mix gamend.content.extract`. Run either before exporting if the source
changed; configuration (colours, hrefs, icons, slugs) is never extracted, so a
translator cannot break the site's layout.

## CSV export / import

```bash
# Export English strings to CSV
mix gettext.export_csv en --output translations/en.csv

# Export any language
mix gettext.export_csv es --output translations/es.csv

# Import translated CSV back into PO files
mix gettext.import_csv es translations/es.csv

# Dry-run import (preview only)
mix gettext.import_csv es translations/es.csv --dry-run
```
