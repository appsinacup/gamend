# My Game

A [Gamend](https://gamend.org) project: the website and backend of a game,
from files in this folder.

    gamend start        # the server, on http://localhost:4000
    gamend help         # every command

| Path | What it is |
|---|---|
| `.env` | Settings and secrets (every setting: `.env.example`) |
| `theme/config.json` | Title, home page, menus, footer |
| `static/` | Pictures, `favicon.ico`, `theme.css`, a web build of the game in `static/game/` |
| `blog/`, `priv/docs/` | Posts and guides, in markdown |
| `CHANGELOG.md`, `ROADMAP.md` | The changelog and roadmap pages |
| `modules/plugins/` | Server plugins; `gamend plugin.bundle` builds them |
| `db/` | The SQLite database |

Guide: https://gamend.org/docs/standalone
