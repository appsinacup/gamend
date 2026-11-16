# `mix gamend.time.lint`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.time.lint.ex#L1)

Flags a date, an instant or a relative phrase a page writes out by hand
instead of through `<.timestamp>`, `<.duration>` or `GamendWeb.TimeText`.
See `Gamend.TimeLint` for what counts and for the `# time-ok: <reason>`
marker that accepts one.

Run from the repository root, in the engine or in a host built on it. Only
this repository's own code is read, never a dependency's.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
