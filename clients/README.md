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

`check_realtime.mjs` needs no generated client: it drives `GameRealtime`
(`realtime.js`) through a token that stops being valid, and checks the socket
comes back with the renewed one. By default it revokes the token, which takes
seconds; `--expiry` waits for it to expire and refreshes it, against a server
started with `GAMEND_AUTH_ACCESS_TOKEN_TTL_MINUTES=1`:

```sh
npm install
node check_realtime.mjs http://127.0.0.1:4000
node check_realtime.mjs http://127.0.0.1:4000 --expiry
```

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
