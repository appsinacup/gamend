# Client SDKs

Goal: official clients beyond Godot, JavaScript and Balaur — C++ first, since
it is the core an Unreal plugin builds on, then C#/Unity and the lighter
targets — without writing the realtime layer from scratch each time or
shipping generator-invented type names.

This replaces the roadmap's "Unity and Unreal, driven by demand" with an
order and a method. Each SDK gets its own spec when it starts;
[cpp-sdk.md](cpp-sdk.md) is the first.

## What every SDK speaks

| Layer | Contract | Source of truth |
|---|---|---|
| REST | 251 operations, JSON in and out (one octet-stream upload) | `GamendWeb.ApiSpec` → `openapi.json` |
| Auth | `access_token` (15 min) + `refresh_token` (30 days); device, email, OAuth session polling, Steam ticket via `POST /auth/steam/callback` | the same document |
| Realtime | Phoenix channels, V2 serializer (`vsn=2.0.0`), `/socket/websocket?token=…`; 7 topic families; `call_hook` over `user:<id>` | `GamendWeb.UserSocket`, [clients/events.json](../../clients/events.json) |
| Protobuf (opt-in) | `format=protobuf`: server → client events as binary frames; client → server stays JSON | [proto/gamend_realtime.proto](../../proto/gamend_realtime.proto) |
| WebRTC (opt-in) | DataChannels, signaled over the user channel (`webrtc:offer` / `webrtc:ice`) | `GamendWeb.WebRTCPeer` |

The REST layer is generated. The realtime layer is hand-written per SDK, and
it is the real cost — ~400 lines of protocol in the Rust client
(`balaur/crates/balaur_gamend/src/client/phoenix.rs`), ~320 in GDScript
(`GamendWebSocket.gd`), plus reconnect, token refresh and hook replies around
it.

## Generation: both generators, by target

[named-api-schemas.md](named-api-schemas.md) comes first. With named schemas,
openapi-generator's output becomes good enough for typed languages it already
targets well; for targets it serves badly or not at all, our own generator
keeps doing what `generate_balaur.py` does.

| Target | REST layer from | Why |
|---|---|---|
| JavaScript / TypeScript | openapi-generator (`typescript-fetch` for types) | Mature target; named schemas fix its only real problem |
| C# (.NET, Unity) | openapi-generator (`csharp`, `unityWebRequest` library for Unity) | Same |
| Godot | openapi-generator (`gdscript`), as today | Existing; fixups shrink once names exist |
| Python, Go | openapi-generator | Tools, bots, load tests — generated code is fine there |
| C++ | our generator | The C++ targets bind a transport (`cpp-restsdk` needs cpprestsdk, in maintenance mode) — ours must be pluggable |
| Rune (Balaur), Lua, GML | our generator | No target exists, or it is untyped and a thin table-in/table-out layer is the idiom |

**Our generator is one tool with several emitters.** `clients/sdkgen/` reads
the document and the events table into a shared model (`model.py`:
operations, events, names; `schemas` when typed models land) with one emitter
per target (`balaur.py`, `cpp.py`, later `lua.py`, `gml.py`), each keeping
`--check` for CI. It was `generate_balaur.py` until C++ became the second
emitter.

## Order

| # | SDK | Realtime | Notes |
|---|---|---|---|
| 0 | Named API schemas | — | Prerequisite for the typed targets |
| 1 | **C++** → Unreal plugin | Hand-written, ported from the Rust client | [cpp-sdk.md](cpp-sdk.md). Pluggable transports so Unreal uses its own HTTP/WebSocket modules |
| 2 | **C#**: .NET package + Unity package | Hand-written, or PhoenixSharp | Also serves Godot .NET, MonoGame, Stride. Unity WebGL needs `UnityWebRequest` and a jslib WebSocket |
| 3 | TypeScript types for the JS SDK | — | `typescript-fetch`, or `.d.ts` over the current output |
| 4 | Rust crate | Extract `balaur_gamend::client` | Already engine-free (serde_json, ureq, tungstenite); serves Bevy, Fyrox, macroquad |
| 5 | Lua (Defold, LÖVE) | Hand-written | The Balaur emitter is nearly a Lua emitter |
| 6 | GameMaker (GML) | Hand-written over `network_create_socket_ext` | |
| 7 | Python / Go | Optional | Bots, tools, load tests |

Swift, Kotlin and Dart wait for someone to ask: mobile games overwhelmingly
ship through an engine.

## One conformance scenario for every SDK

Each SDK proves itself the same way: a live test against `mix dev.start`
running one scenario, so "works" means the same thing everywhere.

1. `POST /login/device` → session; `GET /me` with the access token.
2. Refresh: `POST /refresh`, and the next call uses the new token.
3. Connect the socket (`vsn=2.0.0`), join `user:<id>`.
4. Create a lobby; join `lobby:<id>`; receive `updated`.
5. `call_hook` on the example plugin; get a reply. Then a failing hook; get
   the error.
6. KV: subscribe, write through the API, receive `kv_updated`.
7. Drop the socket; it reconnects, rejoins its topics, and events resume.
8. Leave the lobby; disconnect cleanly.

[clients/test_js.js](../../clients/test_js.js) already covers most of this
for JavaScript. The C++ SDK's `gamend_conformance` runs all eight (plus a
WebRTC hook call) in CI against a booted server, in JSON and protobuf; it is
the reference implementation of the list.

## Shared conventions

- **Names follow Godot's façade** (`GamendApi.gd`, mapped in
  `clients/balaur_names.json`), so a game ported between engines calls the
  same thing. Balaur is the exception: its modules are called by path, one
  per tag, so a name drops the tag the path already carries
  (`gamend::lobbies::create_lobby` for `lobbies_create_lobby`).
- **Events come from `events.json`**, and what a client sends from
  `commands.json`, never a hand-kept list per SDK.
- **Callbacks arrive on the game's thread.** I/O runs off it; results queue
  and are delivered when the game pumps the client (`poll()` / per-tick).
  Engines are single-threaded at the script layer, and a callback on a socket
  thread is a race in every game that touches scene state from it.
- **JSON first.** Protobuf and WebRTC are opt-in layers added after an SDK's
  JSON path passes the conformance scenario.
- **Version stamping** as Godot and Balaur do: CI writes `GAMEND_VERSION`
  into the package.

## Definition of done (per SDK)

- [ ] Own spec in `docs/specs/`, grounded like [cpp-sdk.md](cpp-sdk.md).
- [ ] Generated REST layer in CI (`--check` or regenerate-on-release), no
      hand edits to generated files.
- [ ] Conformance scenario passing against a booted server in CI.
- [ ] A column of its own in `python3 clients/sdkgen lint`, passing.
- [ ] Guide page in `priv/docs/30-clients/`; README's *Client SDKs* list.
- [ ] CHANGELOG `[added]`.
