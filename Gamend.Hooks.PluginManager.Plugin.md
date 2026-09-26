# `Gamend.Hooks.PluginManager.Plugin`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/hooks/plugin_manager.ex#L77)

A loaded plugin descriptor.

This is a runtime struct used by `Gamend.Hooks.PluginManager` to report which
plugins were discovered and whether they successfully loaded and started.

# `t`

```elixir
@type t() :: %Gamend.Hooks.PluginManager.Plugin{
  app: atom(),
  ebin_paths: [String.t()],
  hooks_module: module() | nil,
  loaded_at: DateTime.t() | nil,
  modules: [module()],
  name: String.t(),
  status: :ok | {:error, term()},
  vsn: String.t() | nil
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
