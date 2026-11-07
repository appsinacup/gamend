# `mix host.proto.gen`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/host.proto.gen.ex#L1)

Generates protobuf bindings for every target from a `.proto` file.

A gamend protobuf schema is consumed by three runtimes — the Elixir plugin,
the JavaScript client and the Godot client — each with its own generator.
Running them by hand means three commands with different flag conventions,
and a downstream game has no copy of this repo's shell scripts. This task
ships with `gamend_core`, so any host application or plugin can run it.

## Usage

    mix host.proto.gen                    # every discovered .proto
    mix host.proto.gen path/to/my.proto   # just this one

## Options

    --only elixir,js,godot   Restrict targets (default: all available)
    --elixir-out DIR         Elixir output dir     (default: <plugin>/lib)
    --js-out FILE            JavaScript output     (default: <plugin>/clients/<name>.pb.js)
    --godot-out FILE         Godot output          (default: <plugin>/godot/<name>_pb.gd)

## Requirements

Each target is skipped with a note when its toolchain is absent, so a project
that only ships an Elixir plugin needs nothing extra:

  * Elixir — `protoc` plus `protoc-gen-elixir` (`mix escript.install hex protobuf`)
  * JavaScript — `npx` (fetches the pinned `protobufjs-cli` on demand)
  * Godot — `GODOT_BIN` and `GODOBUF_DIR` environment variables

Discovery looks in `proto/`, `modules/plugins/*/proto/` and
`modules/plugins_examples/*/proto/`, which covers the server itself and the
plugin layout used by gamend games.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
