# `Gamend.Settings.EnvFile`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/settings/env_file.ex#L1)

Every declared setting and plugin variable as a `.env` file, with the values
this server runs on: what `/admin/settings` hands an admin to move a
deployment or compare two.

Secrets are written in the clear. The file exists to bring a server back, and
whoever can download it is already an admin of this one.

A setting on its default is commented out, so the active lines are what this
server overrides and the rest keep following the defaults of later releases.
`config/dotenv.exs` reads a file written here back byte for byte, and
`Gamend.Settings.EnvFileTest` holds the two together.

# `render`

```elixir
@spec render() :: String.t()
```

The whole file.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
