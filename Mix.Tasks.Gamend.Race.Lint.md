# `mix gamend.race.lint`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.race.lint.ex#L1)

Flags functions that keep a rule with a write only an earlier read made
safe: a state column written on a struct, a count then an insert, a cached
read deciding a write. See `Gamend.RaceLint` for each check and for the
`# race-safe: <reason>` marker that accepts one.

    mix gamend.race.lint          # report violations, exit 1 if any
    mix gamend.race.lint --list   # list the checks and exit

Run from the repository root, in the engine or in a host built on it (a
host's `lib/` and `modules/` are scanned, and core/web under deps). A host
registers its own lock helpers as guards:

    config :gamend_core, Gamend.RaceLint, guards: [{:GameCommon, :with_user_lock}]

---

*Consult [api-reference.md](api-reference.md) for complete listing*
