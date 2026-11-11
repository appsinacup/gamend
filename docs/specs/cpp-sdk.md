# C++ SDK

Goal: a C++17 client for Gamend — REST, session, realtime channels and server
hooks, later WebRTC — that a custom engine, a Steamworks game or a dedicated
tool can drop in, and that an Unreal plugin wraps rather than rewrites.

Part of [client-sdks.md](client-sdks.md); read that first for the protocol
table, the generator split and the conformance scenario.

## Why C++ first

- **Unreal is C++.** An Unreal plugin is this core plus Unreal transport
  adapters and Blueprint exposure. Build the core engine-free and Unreal
  becomes a thin second step instead of a second implementation.
- **Steam auth is C++.** `ISteamUser::GetAuthTicketForWebApi` hands back a
  ticket; `POST /api/v1/auth/steam/callback {code: ticket}` turns it into a
  session. A native client makes that one call instead of a bridge.
- **Everything else can bind to it**: custom engines, native tools, bots,
  and — if it ever pays — a C ABI for other languages.

## Shape

```cpp
#include <gamend/gamend.hpp>

gamend::Config config;
config.base_url = "https://game.example.com";
config.http = gamend::make_curl_transport();         // or an engine adapter
config.websocket = gamend::make_ix_websocket_transport();

gamend::Client client(std::move(config));

client.auth().login_device("device-123", [&](const gamend::AuthResult& r) {
  if (!r.ok) { log(r.error); return; }
  client.realtime().connect();                      // joins user:<id> itself
});

client.api().lobbies_quick_join({{"title", "duel"}, {"max_users", 2}},
  [](const gamend::Response& r) {
    if (r.ok()) use(r.data());
  });

client.realtime().on_event([](const gamend::Event& e) {
  if (e.kind == gamend::events::LOBBY_UPDATED) refresh_lobby(e.payload);
});

client.realtime().call_hook("arena", "start", gamend::json::array(),
  [](const gamend::HookResult& r) { /* r.ok, r.data, r.error */ });

// Once per frame, on the game thread:
client.poll();
```

## Threading

I/O never runs on the game thread, and callbacks never run anywhere else.

- Transports do their work on their own threads (or the engine's) and hand
  completions to the client through a mutex-guarded inbox.
- `Client::poll()` drains the inbox on the caller's thread, in arrival order:
  HTTP completions, socket frames, reconnect timers, token-refresh timers. It
  is also where the Phoenix heartbeat is driven, from a clock the caller
  passes or the steady clock.
- `Config::dispatch = Dispatch::Immediate` runs callbacks on the I/O thread
  instead — for bots and tools with no frame loop. Opt-in, documented as
  racy for game code.

The Balaur plugin works exactly this way (worker threads, a per-tick drain);
this is that design without the engine.

## Transports

Two interfaces, the only place a network library appears:

```cpp
struct HttpRequest  { std::string method, url, body; Headers headers; };
struct HttpResponse { int status = 0; std::string body; std::string error; };

class HttpTransport {
 public:
  virtual ~HttpTransport() = default;
  virtual void send(HttpRequest request,
                    std::function<void(HttpResponse)> done) = 0;  // any thread
};

class WebSocketTransport {
 public:
  virtual ~WebSocketTransport() = default;
  virtual void open(const std::string& url, WebSocketHandlers handlers) = 0;
  virtual void send_text(std::string frame) = 0;
  virtual void close() = 0;
};
```

Shipped implementations, each behind a CMake option so a build links only
what it uses:

| Option | Implementation | For |
|---|---|---|
| `GAMEND_WITH_CURL` (default on) | libcurl, one worker thread per client | Desktop, servers |
| `GAMEND_WITH_IXWEBSOCKET` (default on) | IXWebSocket (BSD-3; OpenSSL / mbedTLS / Secure Transport) | Desktop, mobile |
| — | Unreal adapters (`FHttpModule`, `IWebSocket`) | The Unreal plugin, not this package |
| — | `FakeHttp` / `FakeWebSocket` | Unit tests |

libdatachannel also ships a WebSocket client; if the WebRTC phase adopts it,
one dependency covers both and IXWebSocket becomes optional.

## JSON, exceptions, RTTI

- **nlohmann/json** (MIT, header-only) is the public value type:
  `gamend::json`. JSON is the only wire format until the protobuf phase.
- **No exceptions required.** Unreal builds without them by default, so the
  core compiles under `-fno-exceptions`: errors are values (`Response::error`,
  `AuthResult::error`), and JSON is parsed with
  `json::parse(text, nullptr, false)` and checked for `is_discarded()`.
- **No RTTI required**, for the same reason: no `dynamic_cast`, no `typeid`.

## Layers

**Generated — `api.hpp` / `api.cpp` / `events.hpp`.** A C++ emitter in
`clients/sdkgen/` (the Balaur generator, split into a shared model and
per-target emitters — see [client-sdks.md](client-sdks.md)). One method per
operation, named as `GamendApi.gd` names it (the aliases in
`clients/balaur_names.json`). Arguments: path parameters as
`std::string_view`, then `const json& params` for a body, then
`const json& options` for the query, then the callback. Required body and
query fields are checked before sending, and a call that fails the check
completes with an error naming the field, as Balaur's `core.missing` does.
`events.hpp` is one `constexpr std::string_view` per signal in
`clients/events.json`, plus the table `decode()` uses.

**Hand-written — the template** (`clients/cpp_template/`):

| Unit | Does | Ported from |
|---|---|---|
| `Client` | Owns config, transports, inbox, `poll()` | Balaur `lib.rs` delivery model |
| `Session` / `Auth` | Device, email, Steam ticket, OAuth session polling; stores tokens; refreshes ahead of `expires_in`; `session()` / `restore()` so the game persists it where the platform wants | `client/auth.rs`, `GamendAuth.gd` |
| `Rest` | Base URL, bearer header, query encoding, `Response` | `client/rest.rs`, Balaur `core.rn` |
| `Phoenix` | V2 frames `[join_ref, ref, topic, event, payload]`, refs, 30 s heartbeat, reply correlation — no I/O | `client/phoenix.rs` (`Protocol`) |
| `Realtime` | Connect with `vsn=2.0.0&token=…`, join `user:<id>`, reconnect with backoff, rejoin topics, fresh token on reconnect, `push`, `call_hook`, `on_event` | `GamendWebSocket.gd`, Balaur `client.rn` |

**Typed models (after [named-api-schemas.md](named-api-schemas.md)).** The
emitter writes a struct per component with `from_json`/`to_json`, and
`Response::as<gamend::Lobby>()`. Additive: the JSON API stays.

## Layout and build

- Source: `clients/cpp_template/` (hand-written) + the emitter.
- Output: `cpp_sdk/`, not committed, as the Godot addon is not. CI generates
  it, builds and tests it, and puts it on the `latest` release as
  `gamend-cpp-sdk.tar.gz`, which a game fetches with `FetchContent` or
  installs for `find_package(gamend)`.
- CMake ≥ 3.20, C++17. Dependencies through `FetchContent` by default,
  `find_package` first when the host already has them; a vcpkg port later.
- CI: build and unit tests on Linux, macOS and Windows; iOS and Android
  compile-only. No platform code in the core, so a console build is a
  transport adapter away.
- MIT, as the repository and the Godot addon are.

## Tests

- **Unit**, with the fake transports and a fake clock: frame encoding and
  decoding, ref correlation, heartbeat timeout, reconnect and rejoin order,
  refresh scheduling, required-field refusal, query escaping. doctest (single
  header) to keep the dependency list short.
- **Conformance**, live: the scenario from
  [client-sdks.md](client-sdks.md) against a booted dev server in CI.

## Phases

All five are built; see *As built* for where they differ from the plan.

1. **REST.** Skeleton, both transports, `Session`/`Auth` with refresh, the
   emitter (and the `sdkgen/` split), unit tests. Conformance steps 1–2.
2. **Realtime.** `Phoenix`, `Realtime`, events, hooks, reconnect.
   Conformance steps 3–8.
3. **Helpers.** KV subscribe + row cache, presence, as `GamendClient.gd`
   offers them; typed models from the named schemas.
4. **WebRTC.** libdatachannel behind `GAMEND_WITH_WEBRTC`; hook calls over
   the `events` DataChannel in JSON and protobuf, like the JS client.
5. **Protobuf.** Binary event frames, decoded by a table generated from
   `proto/gamend_realtime.proto`: neither libprotobuf-lite nor nanopb.

The Unreal plugin has its own spec, [unreal-plugin.md](unreal-plugin.md):
adapters, `UGamendSubsystem`, Blueprint nodes, `poll()` from the subsystem's
tick.

## Open questions

- Distribution beyond the release tarball: a mirror repo with a tag per
  version, so a game can pin one, and a vcpkg port or Conan recipe. Not
  planned for now.
- Minimum platforms in CI for phase 1 (desktop only is the proposal).

## Definition of done

- [x] `clients/sdkgen/` with the Balaur emitter moved in, output unchanged
      (`generate_balaur.sh --check` clean). Byte-identical on the move; the
      banner and a `$ref` body's required fields changed after it, on purpose.
- [x] C++ emitter. CI generates `cpp_sdk/` in the Godot SDK job, which
      already writes the document, and hands it to the build jobs.
- [x] `Client`, `Session`/`Auth`, `Rest`, curl + IXWebSocket transports,
      fake transports.
- [x] Builds with `-fno-exceptions -fno-rtti`, warning-free under
      `-Wall -Wextra -Wpedantic` with Clang and GCC
      (`GAMEND_WARNINGS_AS_ERRORS=ON`); the unit tests are held to the same
      flags. The libdatachannel adapter alone compiles with exceptions and
      catches them all at its boundary.
- [x] `Realtime`, `Kv`, `Presence`, typed models, protobuf decoding, `WebRtc`.
- [ ] Unit tests green on Linux, macOS, Windows. macOS locally (Clang and
      GCC 15), also under ASan/UBSan and TSan; the CI matrix is written and
      has not run yet, and Windows (MSVC without exceptions) is the one never
      compiled.
- [x] Conformance live: steps 1–8, plus WebRTC as step 9, pass against a dev
      server in JSON and protobuf, and steps 1–8 again under ASan and TSan.
      The `cpp-conformance` CI job, which boots a server and runs both, is
      written and has not run yet.
- [x] Guide page `priv/docs/30-clients/25-cpp-sdk.md`; README *Client SDKs*;
      CHANGELOG.

### As built

Where the SDK differs from the shape above:

- `events.hpp` has `signal_of(topic, event)` and `channel_of(topic)`;
  `Event` carries `topic`, `event`, `kind` (the signal), `payload`, and for a
  binary frame `binary` and, when nothing decodes it, `bytes`.
- `Response` carries `data()`, `meta()`, `code()`, `message()` and
  `errors()` for the four response shapes, `text` for a download, and
  `as<T>()` / `page<T>()` for the typed models (`gamend::models`). Envelopes
  (`{data}`, `{data, meta}`) get no struct; `additionalProperties` schemas are
  `std::map`s. Reads never abort: a missing or mistyped field keeps its
  default.
- A method whose query keys are all optional also comes without `options`.
- `Auth::login_steam` signs in; `Auth::link` and `Auth::link_steam` link,
  since the server now keeps the two apart.
- Timers (refresh, sign-in polling, heartbeat, reconnect) run in `poll()`
  under both dispatch modes; `Dispatch::Immediate` only moves transport
  completions. Public methods take the loop's lock, so they are safe from any
  thread.
- Reconnect backs off 0.1 s → 10 s (`Config::reconnect_delays`) and
  refreshes the token first when the previous attempt never opened. A
  `phx_error` rejoins its topic after a second; a `phx_close` (a kick) does
  not; a join refused as `unauthorized`/`forbidden`/`not_found` is dropped.
- WebRTC is behind a third transport interface, `PeerTransport`, like HTTP
  and WebSocket, so an engine can bring its own. It opens one DataChannel,
  `events`, the only one the server reads. (The server held one per peer,
  which refused `events` whenever the JS and Godot clients' `state` opened
  first; it holds four now.)
- Protobuf needs no library: `sdkgen` turns the `.proto` into a field table
  (`src/proto_schema.cpp`) and a hand-written reader decodes against it,
  mirroring the server's `EventCodec` table. Game metadata or KV data sent
  as `*_pb` goes to a decoder the game registers
  (`register_metadata_decoder`, `register_kv_decoder`, as the JS client's
  `registerMetaSchema` / `registerKvSchema`), and stays base64 without one.
  `WebRtc::call_hook_raw` is the JS client's `callHookRaw`.
- `GAMEND_EXPORT` (`gamend/export.hpp`) marks the public classes for a
  shared build, empty in the CMake one; the Unreal plugin's editor build
  needs it.
- The Balaur and Godot names were reconciled first: all 259 operations are
  named alike in the Godot, Balaur and C++ SDKs.
