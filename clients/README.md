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
