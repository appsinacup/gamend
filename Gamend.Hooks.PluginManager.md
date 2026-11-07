# `Gamend.Hooks.PluginManager`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/hooks/plugin_manager.ex#L1)

Loads and manages hook plugins shipped as OTP applications under `modules/plugins/*`.

Each plugin is expected to be a directory named after the OTP app name (e.g. `my_game_hook`)
containing:

    modules/plugins/my_game_hook/
      ebin/my_game_hook.app
      ebin/Elixir.Gamend.Modules.MyGameHook.beam
      priv/**
      deps/*/ebin/*.beam
      deps/*/priv/**

The plugin's `.app` env must include the key `:hooks_module`, whose value is either a
charlist or string module name like `'Elixir.Gamend.Modules.MyGameHook'`.

This manager is intentionally dependency-free: it only adds `ebin` directories to the code
path and uses `Application.load/1` + `Application.ensure_all_started/1`.

# `plugin_app`

```elixir
@type plugin_app() :: atom()
```

# `plugin_name`

```elixir
@type plugin_name() :: String.t()
```

# `call_rpc`

```elixir
@spec call_rpc(plugin_name(), String.t(), list(), keyword()) ::
  {:ok, any()} | {:error, term()}
```

# `call_timeout_ms`

```elixir
@spec call_timeout_ms() :: pos_integer()
```

How long a hook call may run, in ms: `call_timeout_in_transaction_ms` inside a
`Repo` transaction, `call_timeout_ms` otherwise.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `hook_modules`

```elixir
@spec hook_modules() :: [{plugin_name(), module()}]
```

# `host_rpc_modules`

```elixir
@spec host_rpc_modules() :: [{plugin_name(), module()}]
```

The host's modules that answer client calls, by the name a client calls
them under: `config :gamend_core, :host_rpc_modules, %{"word_games" =>
MyApp.WordGamesRpc}`. A host serves a call the way a plugin does
(`call_rpc/4`: every public function, the caller in the process, the same
limits and reserved names), from code that is the host's own. A name a
loaded plugin also has is the plugin's; the host's is dropped with a
warning when the plugins load. Host calls take JSON arguments and reply
JSON: there are no typed schemas for them.

# `list`

```elixir
@spec list() :: [Gamend.Hooks.PluginManager.Plugin.t()]
```

# `load_declarations`

```elixir
@spec load_declarations() :: [Gamend.Hooks.PluginManager.Plugin.t()]
```

Loads every plugin's code from the plugins directory without starting any,
and registers what they declare (`Gamend.Hooks.Declarations`, their
settings), with no manager running: for a node that reads what the plugins
declare and runs none of them, `Gamend.Release.Metadata` at an image's
build. A plugin that fails to load is listed with its error, as `list/0`
does.

# `lookup`

```elixir
@spec lookup(plugin_name()) ::
  {:ok, Gamend.Hooks.PluginManager.Plugin.t()} | {:error, term()}
```

# `plugins_dir`

```elixir
@spec plugins_dir() :: String.t()
```

# `reload`

```elixir
@spec reload() :: [Gamend.Hooks.PluginManager.Plugin.t()]
```

# `reload_and_after_startup`

```elixir
@spec reload_and_after_startup() :: %{
  plugins: [Gamend.Hooks.PluginManager.Plugin.t()],
  after_startup: map()
}
```

# `resume`

```elixir
@spec resume(plugin_name()) :: Gamend.Hooks.PluginManager.Plugin.t() | nil
```

Loads one plugin from disk again and runs its `after_startup/0`, the
counterpart of `suspend/1`. Returns the plugin (its `status` says whether it
started), or `nil` when the manager is not running or skips the name.

# `rpc_modules`

```elixir
@spec rpc_modules() :: [{plugin_name(), module()}]
```

Every module a client can call, plugins first, then the host's (`host_rpc_modules/0`).

# `start_link`

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

# `suspend`

```elixir
@spec suspend(plugin_name()) :: boolean()
```

Stops and unloads one plugin, leaving the others running. Returns `true`
when the manager had it (loaded or failed), `false` when it did not or the
manager is not running.

The in-process build (`Gamend.Hooks.PluginBuilder`) calls this before it
compiles the plugin in this VM. The compiler treats a module that is already
loaded as available, so a module compiled against a sibling that is still
loaded would take that sibling's *old* macros and structs; unloading the
plugin first makes the build see only its own new code. `resume/1` loads it
back.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
