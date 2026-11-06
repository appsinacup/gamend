# `Gamend.Hooks.Declarations`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/hooks/declarations.ex#L1)

Registry of what a plugin *declares* it contributes, for observability and
validation.

Three optional callbacks, registered the same convention-based way as
`Gamend.Hooks.KvSchemas` — export them from the plugin's hooks module and
they are picked up at load:

    def notification_types do
      %{"rival_online" => "A rival the player follows came online"}
    end

    def realtime_events do
      %{"quest_progress" => "Objective counter moved"}
    end

    def env_vars do
      [%{name: "MYGAME_DIFFICULTY", default: "normal", description: "Global difficulty"}]
    end

`notification_types/0` is **enforced**: `Gamend.Notifications` rejects a
notification whose `metadata["type"]` is not declared by core or a plugin, so
a client is never sent a code nobody documented. The other two are
declarations only — a plugin can always read an env var directly, and events
are validated at the push site — but they make the admin runtime page tell
the whole truth instead of only core's half.

# `all`

```elixir
@spec all() :: %{
  notification_types: %{required(String.t()) =&gt; String.t()},
  realtime_events: %{required(String.t()) =&gt; String.t()},
  env_vars: [map()]
}
```

The merged registry: `%{notification_types:, realtime_events:, env_vars:}`.

# `env_vars`

```elixir
@spec env_vars() :: [map()]
```

Env vars declared by plugins, each `%{name:, default:, type:, description:,
secret:, plugin:}`. `secret` is the plugin's `secret: true`, false otherwise.

# `notification_types`

```elixir
@spec notification_types() :: %{required(String.t()) =&gt; String.t()}
```

Notification codes declared by plugins, mapped to their description.

# `realtime_events`

```elixir
@spec realtime_events() :: %{required(String.t()) =&gt; String.t()}
```

Realtime event names declared by plugins, mapped to their description.

# `refresh`

```elixir
@spec refresh([struct()]) :: :ok
```

Rebuilds the registry from the loaded plugin list.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
