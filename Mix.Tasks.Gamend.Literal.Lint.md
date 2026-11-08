# `mix gamend.literal.lint`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.literal.lint.ex#L1)

Flags a string that is really a name (a status, an action, a kind) typed out
across modules. See `Gamend.LiteralLint` for what counts and for the
`# literal-ok: <reason>` marker that accepts one.

    mix gamend.literal.lint                    # fail on anything beyond the baseline
    mix gamend.literal.lint --all              # every offender, the known ones too
    mix gamend.literal.lint --update-baseline  # record the counts as they stand now

Run from the repository root, in the engine or in a host built on it. Only
this repository's own code is read, never a dependency's. `--update-baseline`
is for after a migration, when counts have fallen.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
