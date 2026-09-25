---
icon: hero-cpu-chip
---

# C++ Client SDK

[Download](https://github.com/appsinacup/gamend/releases/download/latest/gamend-cpp-sdk.tar.gz) |
[View the source](https://github.com/appsinacup/gamend/tree/main/clients/cpp_template)

A C++17 client for custom engines, Steamworks games and native tools, and the
core an Unreal plugin will wrap. Every REST operation is a method, generated
from the same OpenAPI document as the other SDKs and named as the
[Godot SDK](/docs/godot-sdk) names it, so a game ported between engines calls
the same thing. It covers sign-in, the realtime connection and server hooks,
live key-value rows, presence, protobuf events and WebRTC, and it builds
without exceptions and without RTTI.

## Add it

Every change to Gamend puts the SDK on the `latest` release as
`gamend-cpp-sdk.tar.gz`. Fetch it from CMake:

```cmake
include(FetchContent)
FetchContent_Declare(gamend
  URL https://github.com/appsinacup/gamend/releases/download/latest/gamend-cpp-sdk.tar.gz)
FetchContent_MakeAvailable(gamend)

target_link_libraries(my_game PRIVATE gamend::gamend)
```

`latest` moves with each change. To stay on one version, unpack the tarball
into your tree and `add_subdirectory(cpp_sdk)`, or build it once and
`cmake --install` it, then `find_package(gamend 1 CONFIG REQUIRED)`. The
install carries the libraries it fetched, so those are found too.
`GAMEND_VERSION` in `gamend/version.hpp` names the release.

It brings [nlohmann/json](https://github.com/nlohmann/json), and libcurl and
[IXWebSocket](https://github.com/machinezone/IXWebSocket) for the transports it
ships, each from your build when it already has them. IXWebSocket has no
Schannel backend, so on Windows `wss://` goes through OpenSSL when the build
has one and through an [mbedTLS](https://github.com/Mbed-TLS/mbedtls) built
alongside the SDK when it does not. WebRTC is opt-in
(`GAMEND_WITH_WEBRTC=ON`, through
[libdatachannel](https://github.com/paullouisageneau/libdatachannel)). An
engine with its own HTTP, WebSocket or WebRTC stack turns those off and
implements the matching interface instead.

## Connect and sign in

```cpp
#include <gamend/gamend.hpp>

gamend::Config config;
config.base_url = "https://game.example.com";
config.http = gamend::make_curl_transport();
config.websocket = gamend::make_ix_websocket_transport();
gamend::Client client(std::move(config));

client.auth().login_device(device_id(), [&](const gamend::AuthResult& r) {
  if (!r.ok) return show_error(r.error);
  client.realtime().connect();
});

// Once per frame, on the game thread:
client.poll();
```

Callbacks run inside `poll()`, on the thread that calls it, never on a
network thread. That is where your game can touch its own state safely.

Besides a device id, `Auth` signs in with an email and password
(`login_email`, `register_email`), a Steam session ticket (`login_steam`),
and any configured provider (`sign_in("google")`), which opens the provider's
page through `config.open_url` and waits for the player to finish. Signing in
never links: `link("google")` and `link_steam(ticket)` add a provider to the
signed-in account.

## Calls and replies

Each method takes the path's parameters, then the request body, then the
query, then the callback. Replies read as typed models:

```cpp
client.api().lobbies_list_lobbies({{"title", "duel"}, {"page_size", 10}},
  [](const gamend::Response& r) {
    if (!r.ok()) return log(r.error);                   // "not_found", ...
    if (auto page = r.page<gamend::models::Lobby>()) {
      for (const auto& lobby : page->data) show(lobby.title, lobby.max_users);
      log(page->meta.total_count);
    }
  });
```

`gamend/models.hpp` has a struct for every schema the API answers with. The
untyped `data()`, `meta()`, `code()`, `message()` and `errors()` read the four
[response shapes](/docs/api-conventions) too. A required field left out is not
sent: the callback gets an error naming it.

## Sessions

The access token lasts 15 minutes and the refresh token 30 days, unless the
server sets otherwise. The SDK reads the access token's lifetime from
`expires_in` and refreshes it before it lapses, and once more if a call answers
`401`. To stay signed in across runs, keep what `on_session_changed` hands you
and give it back to `restore`:

```cpp
client.auth().on_session_changed([](const std::optional<gamend::Session>& s) {
  if (s) save_secret("gamend", gamend::dump(s->to_json()));
});

if (auto kept = gamend::Session::from_json(gamend::parse(load_secret("gamend")))) {
  client.auth().restore(*kept);
}
```

## Realtime

`connect()` joins the player's `user:<id>` channel. Join others by topic and
listen to everything that arrives:

```cpp
client.realtime().join_lobby(lobby_id);
client.realtime().on_event([](const gamend::Event& e) {
  if (e.kind == gamend::events::LOBBY_MEMBER_JOINED) greet(e.payload);
});
client.realtime().call_hook("arena", "start", gamend::json::array(),
  [](const gamend::HookResult& r) { if (r.ok) begin(r.data); });
```

`Event::kind` names the event as `gamend::events` does (see
[realtime](/docs/realtime)). A dropped connection reconnects with backoff,
with a fresh token if the old one would not do, and rejoins every topic it
had; `on_state` reports each step. Set
`config.realtime_format = gamend::RealtimeFormat::Protobuf` for binary frames:
they are decoded before they reach you, with timestamps as unix milliseconds.
Metadata and KV data your plugin sends in its own schema reach a decoder you
register (`register_metadata_decoder`, `register_kv_decoder`).

## Live rows and presence

```cpp
client.kv().subscribe({"progress", user_id});
client.kv().on_change([](const gamend::KvKey& key, const gamend::KvRow& row) {
  if (key.key == "progress" && row.exists) show(row.data);
});
```

A subscription survives reconnects, and `kv().row(key)` is the latest value
from any source. `presence()` keeps merged player profiles, lobbies and who is
online, filled from the realtime events.

## WebRTC

With `config.webrtc = gamend::make_libdatachannel_transport()`,
`webrtc().connect()` opens a DataChannel to the server, signaled over the user
channel, and `webrtc().call_hook` calls hooks over it at lower latency than
the socket (see [WebRTC](/docs/webrtc)).

## Tests

The SDK ships fake transports and a fake clock
(`gamend/testing/fake_transport.hpp`), so your own tests can answer requests,
play the server's frames and move time by hand. `gamend_conformance <url>` runs
the scenario every Gamend SDK passes against a running server: sign-in,
refresh, the socket, a lobby, hooks, KV, a dropped connection, and WebRTC
when built with it. CI runs it on every change, in JSON and protobuf.
