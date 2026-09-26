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

# `list`

```elixir
@spec list() :: [Gamend.Hooks.PluginManager.Plugin.t()]
```

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

# `start_link`

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
