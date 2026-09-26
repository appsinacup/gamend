## What and why
<!-- The problem, what this changes, and a link to the issue. -->

## How it was tested
<!-- Commands run, manual checks, and anything you could not test. -->

## Checklist
- [ ] `mix precommit` passes
- [ ] `CHANGELOG.md` entry (new feature, or a config or public API change)
- [ ] Guide in `priv/docs/` added or updated if players or operators see the change
- [ ] Migrations and queries work on SQLite and Postgres
- [ ] New settings use `Gamend.Settings.Provider`; `.env.example` and the Settings guide regenerated
- [ ] New realtime events registered in `GamendWeb.RealtimeEvents` and the realtime guide
- [ ] SDK impact noted (JS, Godot, Balaur, C++)
