# `mix gamend.gen.dockerfile`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.gen.dockerfile.ex#L1)

Writes `Dockerfile` from Gamend's one template, filled in from the app's
own `mix.exs`, so Gamend, the starter and every host build the same way.

    mix gamend.gen.dockerfile          # write Dockerfile
    mix gamend.gen.dockerfile --check  # fail if it is out of date
    mix gamend.gen.dockerfile -o PATH  # write somewhere else

What differs between apps comes from the project, never from a hand edit:

  * the path dependencies inside the repository (an umbrella's `apps/*`, a
    plugin the host compiles as a dependency), whose `mix.exs` the
    dependency layer needs before the rest of the source;
  * the config read at compile time: every `config/*.exs` but
    `runtime.exs` and `host_runtime.exs`, read at boot, so an edit to them
    does not compile every dependency again;
  * the release: the one `releases:` names, or the app's own.

And from `gamend_dockerfile:` in the project, all optional:

    gamend_dockerfile: [
      db_adapter: "postgres",                  # default "sqlite"
      plugins_dir: "modules/plugins_examples", # default "modules/plugins"
      build_args: ["ENGINE_TAG=nightly"]       # ARGs the asset step reads
    ]

A build step of the app's own (fetching an engine build, the docs) goes in
its `assets.deploy` alias. A new `SYNC` build arg runs that step again
(`deploy.conf`'s `BUILD_ARGS`), so whatever it fetches is fresh on every
deploy without rebuilding the dependencies.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
