# `Gamend.Settings`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/settings.ex#L1)

The declared configuration surface: every setting core, the host and its
plugins expose, with its type, default, group, env var name and required
level.

Settings are declared with `Gamend.Settings.Provider` and read with
`get/2`, which checks `Application.get_env(app, module)` and falls back to
the compiled default. That means a host configures the ordinary Elixir way:

    config :gamend_core, Gamend.Retention, chat_messages_days: 90

Environment variables are one *input method* into that, not a second source.
`GamendWeb.HostRuntime.config/2` folds `from_env/0` in with the Repo,
Endpoint and mailer derivations, so a host's runtime config loops over that
and nothing else. Looping over `from_env/0` alone leaves prod with no Repo or
Endpoint configuration — see the `GamendWeb.HostRuntime` moduledoc.

A host that prefers a JSON file, or plain Elixir, writes its own equivalent.
Every route ends at `Application` config, so no two sources compete.

## Discovery

Providers are found by scanning the modules of `apps/0` for `__settings__/0`
and cached in `:persistent_term`. Plugins load after config is resolved, so
`Gamend.Hooks.PluginManager` registers theirs on load via `add_app/1`.

# `definition`

```elixir
@type definition() :: %{
  key: atom(),
  module: module(),
  app: atom(),
  group: atom(),
  label: String.t(),
  section: String.t() | nil,
  type: atom(),
  default: term(),
  env: String.t(),
  doc: String.t(),
  secret: boolean(),
  external: boolean(),
  required: :prod | :warn | nil,
  when: {[atom()], term()} | nil,
  with: [atom()]
}
```

# `add_app`

```elixir
@spec add_app(atom()) :: :ok
```

Registers another app's providers — the host application, or a plugin loaded
after boot. Clears the cache so the next read picks them up.

# `add_provider`

```elixir
@spec add_provider(module()) :: :ok
```

Registers one provider module directly, for code that is not in a scanned
app's module list — a plugin compiled at runtime, or a test.

# `all`

```elixir
@spec all() :: [definition()]
```

Every declared setting, across every registered app.

# `apps`

```elixir
@spec apps() :: [atom()]
```

Apps scanned for providers.

Core's two, the host application, and anything `add_app/1` registered.

The host is derived rather than registered because the alternative is silence:
a host that declares settings and is never scanned gets no boot validation, no
row on the admin Settings page and nothing in `.env.example`, while `get/2`
keeps answering with the compiled default — so its env vars do nothing and say
nothing. Deriving it here rather than in the boot path also covers the mix
tasks, which run `app.config` without starting the application and so never
reach `GamendWeb.HostSupervision.init_runtime/1`; `mix gamend.settings.guide`
and `mix gamend.settings.env_example` would otherwise document core's settings
and quietly omit the host's.

`:host_static_app` is the key a host already sets to name its own OTP app, and
reading it is a lookup, not a dependency — core does not compile against
`gamend_web`. It defaults to `:gamend_web`, which is scanned anyway, so an
unconfigured deployment sees no change.

# `cast`

```elixir
@spec cast(String.t(), atom()) :: {:ok, term()} | :error
```

Casts a raw string to a declared type. Returns `:error` when it does not
parse, so the caller decides whether that is fatal.

`values` is the declared `:values` of an `:atom` setting. Pass it whenever
you have it — see `cast/3`.

# `cast`

```elixir
@spec cast(String.t(), atom(), [atom()]) :: {:ok, term()} | :error
```

Casts a raw string against a declared type and, for `:atom`, its allowed
`values`.

With `values` the choice is matched against the declaration itself, so a
legal value is accepted whether or not any other compiled code happens to
name that atom. Without it there is nothing to match against and the cast
falls back to `String.to_existing_atom/1`, which rejects exactly those atoms
nothing else mentions — `GAMEND_PAYMENTS_ENVIRONMENT=sandbox` was rejected
that way and silently became `:production`. Declare `:values` on every
`:atom` setting; the fallback exists for plugins compiled before it did.

# `declared`

```elixir
@spec declared() :: [map()]
```

Every declared setting, then every variable a loaded plugin declares that
is not one (`Gamend.Hooks.Declarations.env_vars/0`), as plain data a JSON
encoder takes: what a host that runs this server from outside, and cannot
load its code, reads to offer them. Gamend's builder writes it beside a
release it stages (`Gamend.Release.Metadata`), where Gamend Cloud's
Settings tab reads it from the image. It is never a client's: no route or
hook RPC answers it.

Each is `%{env:, app:, group:, label:, type:, default:, doc:, secret:,
values:, plugin:}`. `app`, `group` and `type` are strings; `default` is a
string, a number, a boolean or nil, a list joined with commas as its
variable is written, any other term `inspect/1`ed; `values` is the strings
an `:atom` takes. A plugin's variable has `app` and `group` nil and
`plugin` its plugin's name; a setting has `plugin` nil.

# `describe`

```elixir
@spec describe(definition()) :: map()
```

A setting's declaration, with its effective value and where that came from:
`:config` when the host set one, `:default` otherwise.

The admin viewer renders this; `:env` never appears as a source because env
vars are resolved into `Application` config at boot rather than read live.

# `env_name`

```elixir
@spec env_name(String.t(), atom(), atom()) :: String.t()
```

The env var name a group/key derives to. Exposed for docs and the
`.env.example` generator.

# `from_env`

```elixir
@spec from_env() :: [{atom(), module(), keyword()}]
```

Reads every declared setting from the environment, as `{app, module, opts}`
ready to splat into `config/2`.

Only variables that are actually set contribute; the rest fall through to
the compiled default. A value that does not parse as its declared type is
skipped with a warning rather than taking the boot down.

# `get`

```elixir
@spec get(module(), atom()) :: term()
```

The current value of a setting: the host's `Application` config if it set
one, otherwise the compiled default.

Raises for a key the module does not declare — an undeclared read is a bug,
not a runtime condition.

# `group`

```elixir
@spec group(atom()) :: [definition()]
```

Declared settings for one group.

# `groups`

```elixir
@spec groups() :: [{atom(), String.t()}]
```

Every group, as `{group, label}`, in display order.

# `providers`

```elixir
@spec providers() :: [module()]
```

Provider modules, discovered once and cached.

# `reload`

```elixir
@spec reload() :: :ok
```

Drops the cached provider list. Call after loading code that declares settings.

# `remove_provider`

```elixir
@spec remove_provider(module()) :: :ok
```

Undoes `add_provider/1`.

# `resolve`

```elixir
@spec resolve() :: %{required({module(), atom()}) =&gt; term()}
```

Every setting's resolved value, keyed by `{module, key}`: the environment
when it is set, the compiled default otherwise.

For `config/runtime.exs`, which needs values *while* it is still building the
configuration. `config/2` only applies after the whole file is evaluated, so
`get/2` cannot see what `from_env/0` just contributed — this can.

# `validate`

```elixir
@spec validate(atom()) :: {[String.t()], [String.t()]}
```

Checks every declared requirement against the resolved configuration.

Returns `{failures, warnings}`, each a list of human-readable lines. Nothing
is raised here — `validate!/1` decides what is fatal, so a caller that wants
to render the state instead (the admin viewer) can.

Severity by environment:

| Level | `:prod` | `:dev` | `:test` |
| --- | --- | --- | --- |
| `required: :prod` | failure | warning | silent |
| `required: :warn` | warning | silent | silent |

The dev warning on a prod requirement is deliberate: it says the deployment
will not boot in production while the developer is still at the keyboard.
Test is silent because the suite boots hundreds of times.

# `validate!`

```elixir
@spec validate!(atom()) :: :ok
```

Runs `validate/1`, logging warnings and raising on failures.

Called once at boot. Returns `:ok` when nothing is fatal.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
