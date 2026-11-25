# `mix gamend.settings.guide`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.settings.guide.ex#L1)

Writes the public Settings guide from `Gamend.Settings.all/0`.

    mix gamend.settings.guide          # write the guide
    mix gamend.settings.guide --check  # fail if it is out of date
    mix gamend.settings.guide -o PATH  # write somewhere else

Sibling of `mix gamend.settings.env_example`, for the same reason: a
declared setting is documented for readers of the docs site the moment it
exists, and a renamed one leaves no stale variable behind.

**Only for hosts that have a docs site.** When `priv/docs/60-operations`
does not exist the task says so and does nothing, including under `--check`
— a game built on this server has its own docs, or none, and should not have
a `priv/docs` tree conjured for it. Pass `-o PATH` to write somewhere else
deliberately; an explicit path is always honoured.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
