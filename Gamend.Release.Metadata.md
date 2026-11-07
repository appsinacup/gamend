# `Gamend.Release.Metadata`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/release/metadata.ex#L1)

What a release declares, written into its image as it is built, so a host
that runs the image from outside reads it without booting it. Gamend Cloud
reads a server's after each build, where it asked the running server over
`bin/<release> rpc`.

The file is `gamend-metadata.json` in the release's directory, which is the
image's working directory. Gamend's builder image writes it as the last
step of staging a release (`gamend-stage-release`, which the generated
Dockerfile runs after `mix release`), from the staged directory:

    bin/gamend_host eval 'Gamend.Release.Metadata.write()'

An image built otherwise has none unless its build runs that line, and a
host says so rather than guess (Gamend Cloud's Settings tab).

It is JSON:

  * `format`: 1, raised only by a change a reader of an older one would
    misread;
  * `gamend_version`: core's version;
  * `settings`: `Gamend.Settings.declared/0`, with every plugin in the
    plugins directory loaded and none started
    (`Gamend.Hooks.PluginManager.load_declarations/0`).

A host reads it with `decode/1`. Nothing in it is secret: a setting's
declared default, never a value an environment sets.

# `build`

```elixir
@spec build() :: map()
```

The metadata of the release this node runs, as a map with string keys.
Loads the plugins' code (none started), so it is for a node that only
reads declarations: an `eval`, never a running server.

# `decode`

```elixir
@spec decode(binary()) ::
  {:ok, %{version: String.t() | nil, settings: [map()]}}
  | {:error, :invalid_metadata}
```

Read a metadata file's content: core's version (nil when blank) and the
declared settings, each a map with string keys as `Gamend.Settings.declared/0`
describes them. `{:error, :invalid_metadata}` for anything else, a newer
`format` included.

# `file_name`

```elixir
@spec file_name() :: String.t()
```

The file's name, in the release's directory.

# `write`

```elixir
@spec write(Path.t()) :: :ok
```

Write `build/0` as JSON to `path`, the release's directory's `gamend-metadata.json` by default.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
