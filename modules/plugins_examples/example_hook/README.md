# Example hook plugin

This is a minimal OTP hook plugin example.

## Build

From the repo root:

- `cd modules/plugins_examples/example_hook`
- `mix deps.get`
- `mix compile`

This compiles the plugin into `_build/dev/lib/example_hook/ebin/` (and generates the `.app` file with `hooks_module`).

## Package (plugin bundle)

The server loads plugins from a directory containing an `ebin/` folder.
To create a bundle directory you can drop into `modules/plugins/`:

- `mix plugin.bundle`

This also copies transitive runtime dependencies, including:

- compiled dependency BEAMs into `deps/<dep>/ebin`
- plugin/runtime `priv/` directories into `priv` and `deps/<dep>/priv`

The `priv/` copy is important for dependencies that ship NIFs or other runtime assets.

## Run locally

- Set `GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples` (or copy the built bundle into `modules/plugins/example_hook`)
- Open the Admin Config page and click **Reload plugins**
- Call a function via the “Hooks - Test RPC” form using:
  - `plugin`: `example_hook`
  - `fn`: `hello` (or `set_current_user_meta`)
