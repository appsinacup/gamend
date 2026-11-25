# `mix gamend.settings.env_example`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.settings.env_example.ex#L1)

Writes `.env.example` from `Gamend.Settings.all/0`, grouped and
commented from each setting's declaration.

    mix gamend.settings.env_example          # write .env.example
    mix gamend.settings.env_example --check  # fail if it is out of date
    mix gamend.settings.env_example -o PATH  # write somewhere else

Generating it means a setting is documented the moment it is declared, and
`--check` keeps it that way in CI.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
