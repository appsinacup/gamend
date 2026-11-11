# Generate Clients

To generate the Godot client, simply run:

```sh
./generate_godot.sh
```

It runs openapi-generator in Docker. Without Docker, point it at a local
openapi-generator-cli jar instead:

```sh
OPENAPI_GENERATOR_JAR=/path/to/openapi-generator-cli.jar ./generate_godot.sh
```

Then check it in a headless Godot 4 (`GODOT_BIN`, or `godot` on PATH): every
addon script must compile, and with a server URL a set of live calls must land
in their named model classes (`GamendLobby`, `GamendSession`, …):

```sh
./check_godot.sh
./check_godot.sh http://127.0.0.1:4000
```

To generate the Javascript client, simply run:

```sh
npm run openapi
npm run generate
```

and check it against a running server: every call must answer with its named
model class (`Lobby`, `SessionResponse`, …):

```sh
node check_js.js http://127.0.0.1:4000
```

`npm run generate` ends by writing the package's TypeScript declarations,
`javascript/dist/index.d.ts`, with `python3 sdkgen ts`. The realtime classes
are declared by hand in `gamend_client.d.ts`. `npm run check:types` compiles
`check_ts.ts` against them.

## One source for the realtime events

Every server→client event is declared once, in `GamendWeb.RealtimeEvents`
(its channel, its SDK signal name, its payload). The channel code is held to
it by `realtime_events_drift_test.exs`, the protobuf codec by
`event_codec_coverage_test.exs`. From it:

- `mix gamend.gen.events` writes `clients/events.json` (channel, event,
  signal, protobuf message), which the Balaur and C++ SDKs are generated
  from. `precommit` runs it; CI runs `--check`.
- `sdk_events_drift_test.exs` holds the hand-written halves to it: Godot's
  routing (`GamendApi.gd`, `GamendWebRTC.gd`, `GamendSignalingClient.gd`)
  and the Godot and JavaScript protobuf decoders (`GamendProto.gd`,
  `gamend_proto.js`). A new event fails there until each client has it.
- The protobuf schema (`proto/gamend_realtime.proto`) gives the Elixir,
  JavaScript and Godot bindings through `mix host.proto.gen` (pbjs pinned).

A new event: add its row to the registry (and its message to the codec and
the schema when it is protobuf), run `mix gamend.gen.events` and
`mix host.proto.gen`, then let the drift test name what each client lacks.

## One source for what a client sends

Every event a channel answers is declared once, in
`GamendWeb.RealtimeCommands`, which `realtime_events_drift_test.exs` holds to
the channels' `handle_in` clauses. `mix gamend.gen.events` writes it to
`clients/commands.json`, and the C++ (`gamend::commands`) and Balaur
(`commands.bs`) SDKs get one function per row from it. The Godot and
JavaScript clients have theirs by hand.

## Build and test them all

`clients/check_sdks.sh` generates the C++, C# and Rust SDKs and builds and tests
each of them at once, with the TypeScript and Godot checks, skipping any whose
tool is not installed. With a server URL it then runs each one's live
conformance, one at a time. CI does the same in separate jobs.

## Where each SDK is published

Every push to `main` publishes each SDK at the server's version,
`<VERSION>.<commit count>` (`1.1.1429`), from `.github/workflows/build-and-check.yml`:

| SDK | Where | How CI signs in |
|---|---|---|
| JavaScript | npm, [`@ughuuu/gamend`](https://www.npmjs.com/package/@ughuuu/gamend) | trusted publishing (OIDC) |
| C# | NuGet, [`Gamend`](https://www.nuget.org/packages/Gamend) | trusted publishing: nuget.org's policy names this repository and `build-and-check.yml`; the `NUGET_USER` secret is the profile it belongs to |
| Rust | crates.io, [`gamend`](https://crates.io/crates/gamend); reference on docs.rs | the `CARGO_REGISTRY_TOKEN` secret |
| C++, C#, Rust, Godot, Unreal | the [`latest` release](https://github.com/appsinacup/gamend/releases/tag/latest): a tarball each, `godot_addons.zip`, `gamend-unreal-plugin.zip` | the workflow's own token |

The NuGet, crates.io and release jobs wait for the SDK's build, its tests and
the live conformance run. A version already on a registry is skipped, so a
re-run passes. Without `NUGET_USER` or `CARGO_REGISTRY_TOKEN`, that job says so
and passes.

## Does every SDK have everything

`python3 clients/sdkgen lint` prints each SDK against the operations and
schemas of the OpenAPI document, the events the socket sends and the events it
answers, and fails on anything missing. `precommit` runs it. CI runs it with
`--generated`, which also reads what openapi-generator wrote.

A new operation fails there until `GamendApi.gd` has its function, a removed
one until it is gone. A new socket event fails until the Godot and JavaScript
clients send it. An API schema whose Godot model would take the name of a
hand-written class (`GamendResult`) fails too, since two scripts cannot share a
`class_name`.

The lint says an SDK can call a thing, not that it does anything more with it:
Balaur has `webrtc_offer` and no WebRTC peer behind it, and only Godot has a
peer-to-peer client over the `signaling:*` commands.

## Unity

The Unity package (`org.gamend.sdk`) is the C# SDK copied into
`unity_template/` with a `GamendBehaviour`, `UnityWebRequest` HTTP and a WebGL
socket (`GamendWebSocket.jslib`). It writes `unity_sdk/`, not committed, and
`--pack` the tarball CI puts on the `latest` release:

```sh
./generate_unity.sh --pack
./check_unity.sh
```

There is no Unity in CI, so `check_unity.sh` compiles the package against
UnityEngine stubs (`unity_check/`), for players and for WebGL, and runs the
jslib in node. A file added to `unity_template/` needs its `.meta`:
`python3 unity_package.py unity_template` writes the missing ones, and
`precommit` fails without them.

## Balaur and C++

The Balaur and C++ SDKs come from our own generator, `sdkgen/`: one model of
the document and the realtime table, one emitter per target. Each script
refreshes the document first; `--check` fails when the output on disk is
stale, without writing anything:

```sh
./generate_balaur.sh          # balaur_addons/addons/gamend, committed
./generate_balaur.sh --check
./generate_cpp.sh             # cpp_sdk/, not committed
```

The hand-written halves are `balaur_template/` and `cpp_template/`, copied
over the generated files. `cpp_sdk/` is ignored by git, as `godot_addons/` is:
CI generates it and puts it on the `latest` release as
`gamend-cpp-sdk.tar.gz`. Build and test it, install it and build a game
against the installed package, and run it against a server:

```sh
cmake -S ../cpp_sdk -B ../cpp_sdk/build -DGAMEND_WARNINGS_AS_ERRORS=ON
cmake --build ../cpp_sdk/build && ctest --test-dir ../cpp_sdk/build
cmake --install ../cpp_sdk/build --prefix /tmp/gamend
cmake -S ../cpp_sdk/tests/package -B /tmp/gamend-package -DCMAKE_PREFIX_PATH=/tmp/gamend
cmake --build /tmp/gamend-package
../cpp_sdk/build/gamend_conformance http://127.0.0.1:4000
```

## Unreal

The Unreal plugin is the C++ SDK in a module of its own (`GamendSDK`) and
`unreal_template/` around it: the subsystem, the transports over Unreal's
HTTP and WebSocket modules, the Blueprint nodes. `generate_unreal.sh` writes
it to `unreal_plugin/Gamend/` (ignored by git; CI puts it on the `latest`
release as `gamend-unreal-plugin.zip`), copying the SDK in without its own
transports and fetching the nlohmann/json the SDK's CMake build pins.

CI cannot run Unreal. `check_unreal.sh` builds what it can: the `GamendSDK`
module, in C++17 and C++20 with the engine's rules, into a shared library
that hides every symbol `GAMEND_EXPORT` does not mark, as an editor build
links it, then links and runs `unreal_check/sdk_check.cpp` against it. A class
a game can call that is not exported fails there.

```sh
./generate_unreal.sh            # regenerates cpp_sdk/ too
./generate_unreal.sh --no-cpp   # from the cpp_sdk/ on disk
./check_unreal.sh
```
