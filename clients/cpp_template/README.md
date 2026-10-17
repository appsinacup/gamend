# Gamend C++ SDK

A C++17 client for [Gamend](https://gamend.org): every REST operation, typed
models, sign-in and a session that stays fresh, the realtime connection with
server hooks, live key-value rows and presence, protobuf events, and WebRTC
DataChannels, over transports you choose. It builds without exceptions and
without RTTI, so an Unreal module can take it as it is.

This directory is generated: `include/gamend/api.hpp`, `src/api.cpp`,
`include/gamend/events.hpp`, `include/gamend/models.hpp`, `src/models.cpp`,
`src/proto_schema.cpp` and `REFERENCE.md` by `clients/sdkgen` from the OpenAPI
document, `clients/events.json` and `proto/gamend_realtime.proto`; the rest is
copied from `clients/cpp_template/`. Edit those, not this, and run
`clients/generate_cpp.sh`.

## Add it

Each change to Gamend's `main` branch puts this directory on the `latest`
release as `gamend-cpp-sdk.tar.gz`. Fetch it from CMake:

```cmake
include(FetchContent)
FetchContent_Declare(gamend
  URL https://github.com/appsinacup/gamend/releases/download/latest/gamend-cpp-sdk.tar.gz)
FetchContent_MakeAvailable(gamend)

target_link_libraries(my_game PRIVATE gamend::gamend)
```

`latest` moves. To stay on one version, unpack the tarball into your tree and
`add_subdirectory(cpp_sdk)`, or install it once:

```sh
tar -xzf gamend-cpp-sdk.tar.gz
cmake -S cpp_sdk -B build -DCMAKE_BUILD_TYPE=Release -DGAMEND_BUILD_TESTS=OFF
cmake --build build && cmake --install build --prefix /opt/gamend
```

and find it (with `CMAKE_PREFIX_PATH=/opt/gamend`):

```cmake
find_package(gamend 1 CONFIG REQUIRED)
target_link_libraries(my_game PRIVATE gamend::gamend)
```

The install carries the dependencies it fetched, so `find_package(gamend)`
finds them too. `GAMEND_VERSION` in `gamend/version.hpp` names the release.

Dependencies come from `find_package` when your build already has them, and
from FetchContent otherwise: [nlohmann/json](https://github.com/nlohmann/json)
always, and for the transports that use them libcurl,
[IXWebSocket](https://github.com/machinezone/IXWebSocket) and
[libdatachannel](https://github.com/paullouisageneau/libdatachannel).

| Option | Default | |
| --- | --- | --- |
| `GAMEND_WITH_CURL` | `ON` | The libcurl HTTP transport, `make_curl_transport()` |
| `GAMEND_WITH_IXWEBSOCKET` | `ON` | The IXWebSocket transport, `make_ix_websocket_transport()` |
| `GAMEND_IXWEBSOCKET_TLS` | `ON` | `wss://` for it: Secure Transport on Apple, OpenSSL on Linux, and on Windows OpenSSL when the build has one, else an [mbedTLS](https://github.com/Mbed-TLS/mbedtls) built here |
| `GAMEND_WITH_WEBRTC` | `OFF` | The libdatachannel peer, `make_libdatachannel_transport()`; needs OpenSSL |
| `GAMEND_BUILD_TESTS` | top level only | The unit tests, `ctest` |
| `GAMEND_BUILD_EXAMPLES` | top level only | `gamend_conformance` |
| `GAMEND_WARNINGS_AS_ERRORS` | `OFF` | `-Werror` / `/WX` on the SDK's own code |
| `GAMEND_INSTALL` | top level only | `cmake --install` rules and the `find_package(gamend)` package |

Every network library sits behind an interface in `gamend/transport.hpp`:
`HttpTransport`, `WebSocketTransport` and `PeerTransport`, a page each. An
engine with its own stack (Unreal's `FHttpModule`, `IWebSocket`) turns the
shipped ones off and implements those instead.

## Use it

```cpp
#include <gamend/gamend.hpp>

gamend::Config config;
config.base_url = "https://game.example.com";
config.http = gamend::make_curl_transport();
config.websocket = gamend::make_ix_websocket_transport();
config.open_url = [](const std::string& url) { open_in_browser(url); };
gamend::Client client(std::move(config));

client.auth().login_device(device_id(), [&](const gamend::AuthResult& r) {
  if (!r.ok) return show_error(r.error);
  client.realtime().connect();                       // joins user:<id> itself
  client.api().lobbies_quick_join({{"title", "duel"}, {"max_users", 2}},
    [&](const gamend::Response& r) {
      if (auto lobby = r.as<gamend::models::Lobby>()) {
        client.realtime().join_lobby(lobby->id);
      }
    });
});

client.realtime().on_event([](const gamend::Event& e) {
  if (e.kind == gamend::events::LOBBY_UPDATED) refresh_lobby(e.payload);
});

// Once per frame, on the game thread:
client.poll();
```

**Callbacks run in `poll()`.** Transports work on their own threads and hand
their results to an inbox; `poll()` runs them on the thread that calls it, in
the order they arrived, then the timers that are due (token refresh, sign-in
polling, heartbeats, reconnects). A callback never runs inside the call that
started it, and the SDK's methods are safe to call from any thread. A bot or a
tool with no frame loop sets `config.dispatch = gamend::Dispatch::Immediate`
to have callbacks run on the transport's thread instead, one at a time; it
still calls `poll()` for the timers.

## REST

**Every method is one operation**, named as the Godot SDK names it: the path's
parameters, then `params` for the body, then `options` for the query, then the
callback. `REFERENCE.md` lists them by tag and `api.hpp` lists each one's
fields. A missing required field is not sent: the callback gets
`<method> needs `<field>``.

**A `Response`** is the status, the decoded `body`, the raw `text`, and an
`error` that is empty on success. Gamend answers one of four shapes, and the
accessors read them: `data()`, `meta()` for a page, `code()` and `message()`
for an error, `errors()` for `validation_failed`.

**Typed models.** `gamend/models.hpp` has a struct for every schema the API
answers with. `r.as<models::Lobby>()` reads `data()`, `r.page<models::Lobby>()`
a page with its `meta`, and `r.as<std::vector<std::string>>()` works for any
list. Reads are lenient: a field that is missing or mistyped keeps its
default, a nullable one is a `std::optional`, a map is a `std::map`, and a
free-form object stays `json`. `Codec<T>::write` turns a model back into JSON.

**Reading JSON without exceptions.** The core is built without them, and
nlohmann/json aborts where it would have thrown. Read replies with the models,
or with `gamend::text(obj, "key")`, `gamend::number(obj, "key")` and
`gamend::field(obj, "key")`; check `is_string()` before `get<std::string>()`,
and never `operator[]` on a *const* json with a key that may be missing.

## Sessions

`Auth` signs in and keeps the session: `login_device`, `login_email`,
`login_steam` (an `ISteamUser::GetAuthTicketForWebApi`
ticket), and `sign_in(provider)`, which opens the provider's page through
`config.open_url` and polls until the player finishes. Every call after that
carries the access token. It is refreshed when three quarters of its 15
minutes have passed, and once more on a `401`; a refresh the server refuses
signs out.

Signing in never links. To add a provider to the signed-in account,
`link(provider)` opens its page and polls as `sign_in` does, and
`link_steam(ticket)` links Steam directly; the session stays as it is.

Registering is not a sign-in either, and takes no password.
`register_email(email)` makes the account and answers it
(`models::Registration`); the server emails a link and a six-digit code.
`confirm_registration(email, code, password)` sets the password the player
chooses and signs in, failing with `invalid_code` for a wrong or spent code;
`resend_confirmation(email)` sends a new one. The password is chosen only
once the code proves the inbox: anyone can type any address, and a password
picked before that would let them into the account its owner confirms.

Keep the session between runs where your platform keeps secrets:

```cpp
client.auth().on_session_changed([](const std::optional<gamend::Session>& s) {
  if (s) keychain_write("gamend", gamend::dump(s->to_json()));
  else keychain_erase("gamend");
});

if (auto kept = gamend::Session::from_json(gamend::parse(keychain_read("gamend")))) {
  client.auth().restore(*kept);  // refreshed on the next poll if it lapsed
}
```

## Realtime

`realtime().connect()` opens the Phoenix socket (`vsn=2.0.0`) as the
signed-in player and joins `user:<id>`. `join(topic)` (and `join_lobby`,
`join_lobbies`, `join_group`, `join_groups`, `join_party`) joins now or as soon
as the socket opens; `push(topic, event, payload, done)` answers the server's
reply or `timeout`; `call_hook(plugin, fn, args, done)` calls a server hook
over the user channel.

A dropped connection reconnects on its own, backing off (0.1 s, 0.5 s, 1 s,
2 s, 5 s, then every 10 s: `Config::reconnect_delays`), refreshing the token
first when the last attempt never opened, and rejoins every topic it had, in
order; `on_state` says when (`Connecting`, `Connected`, `Reconnecting`,
`Disconnected`). A missed heartbeat counts as a drop. A channel the server
errors is joined again; one it closes (a kick) is not. Signing out
disconnects.

Events arrive named: `Event::kind` is one of `gamend::events` (from
`clients/events.json`), or `events::MESSAGE` for one the table does not name.

**Protobuf.** `config.realtime_format = RealtimeFormat::Protobuf` asks the
server for binary frames; they are decoded before `on_event`, into the same
payload as JSON mode except that timestamps are unix milliseconds (`*_ms`).
`Event::binary` says a frame really arrived as protobuf. The decoder is built
in, generated from `proto/gamend_realtime.proto`; no protobuf library.
Metadata or KV data the game plugin sends in its own schema (`metadata_pb`,
`data_pb`) is read by the decoder you register, usually with your protobuf
library: `realtime().register_metadata_decoder("lobby", fn)`,
`register_kv_decoder("match:*", fn)`. Unread, it stays base64.

## Live rows and presence

`kv().subscribe({"progress", user_id})` subscribes to a key-value row over the
socket, again after every rejoin; `kv().row(key)` is the latest value from
subscribe replies, `kv_updated` / `kv_deleted` pushes and `kv().fetch(key)`
(REST, cache first). `kv().on_change` hears every change.

`presence()` keeps merged user profiles, lobbies and online state from the
realtime events: `user(id)`, `lobby(id)`, `online(id)`, `last_seen(id)`,
`on_user_changed`. Metadata merges one section deep, so a sparse update never
wipes the rest; the player's own push replaces theirs whole.

## WebRTC

With `config.webrtc = gamend::make_libdatachannel_transport()` (built with
`GAMEND_WITH_WEBRTC`) and the realtime connection up, `webrtc().connect(done)`
opens a DataChannel to the server, signaled over the user channel.
`webrtc().call_hook` calls hooks over it, as JSON messages or, with
`config.webrtc_format = RealtimeFormat::Protobuf`, protobuf envelopes with
request ids, where `call_hook_raw` sends a typed hook the game's own encoded
request and hands back the reply's bytes; `send` and `on_data` carry the
game's own messages. It opens `events`, reliable and ordered, which hook
calls ride on; `Config::data_channels` adds more (the server holds up to
four). Losing the socket closes it.

## Test with it

`gamend/testing/fake_transport.hpp` has `FakeHttp`, `FakeWebSocket`,
`FakePeer` and `FakeClock`: answer requests, play the server's frames, drive
the peer and move time by hand, then `poll()`.

```sh
cmake -S . -B build -DGAMEND_WARNINGS_AS_ERRORS=ON
cmake --build build
ctest --test-dir build
build/gamend_conformance http://127.0.0.1:4000              # live, JSON
build/gamend_conformance http://127.0.0.1:4000 --protobuf   # live, protobuf
```

`gamend_conformance` runs the scenario every Gamend SDK passes: sign in, `/me`,
refresh, connect and join, a lobby and its update, a hook and a failing one,
a KV subscription hearing a write, a dropped socket reconnecting and
rejoining, a clean disconnect, and, built with WebRTC, a hook over the
DataChannel. The KV step writes as an admin: set `GAMEND_ADMIN_EMAIL` and
`GAMEND_ADMIN_PASSWORD`, or it is skipped. The hooks need the example plugins
(`GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples`).

MIT, as Gamend is.
