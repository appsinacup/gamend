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
| JavaScript + TypeScript | openapi-generator (`javascript`), `.d.ts` from our generator | One package; the runtime others already import does not change |
| C# (.NET, Unity) | our generator | openapi-generator's Unity library is experimental and ties the output to Unity; ours shares the Godot names and needs no reflection under IL2CPP |
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
| 1 | **C++** → Unreal plugin: built (beta) | Hand-written, ported from the Rust client | [cpp-sdk.md](cpp-sdk.md), [unreal-plugin.md](unreal-plugin.md). Pluggable transports so Unreal uses its own HTTP/WebSocket modules |
| 2 | **C#** and the Unity package: built | Hand-written, ported from the C++ SDK | Also serves Godot .NET, MonoGame, Stride. Unity WebGL needs `UnityWebRequest` and a jslib WebSocket |
| 3 | TypeScript types for the JS SDK: built | — | `.d.ts` over the current output, written by `sdkgen ts` |
| 4 | Rust crate: built | Ported from the C++ SDK, starting from `balaur_gamend::client` | Serves Bevy, Fyrox, macroquad. Balaur moving onto it is a later, optional step |
| 5 | Lua (Defold, LÖVE) | Hand-written | The Balaur emitter is nearly a Lua emitter |
| 6 | GameMaker (GML) | Hand-written over `network_create_socket_ext` | |
| 7 | Python / Go | Optional | Bots, tools, load tests |

Swift, Kotlin and Dart wait for someone to ask: mobile games overwhelmingly
ship through an engine.

## C#, as built

`clients/sdkgen/csharp.py` and `clients/csharp_template/`, output `csharp_sdk/`.
It ports the C++ SDK with these differences:

- `netstandard2.1`, C# 9, no threads and no reflection, so Unity IL2CPP and
  WebGL can take it. Readers are generated and looked up by type.
- Every call answers a `Task`, completed in `Client.Poll()`, so an `await`
  continues on the game thread. There is no `Dispatch::Immediate`.
- Game SDKs carry no admin API: `model.player()`, 181 operations of 285.
  `Rest.Send` reaches the rest for a tool that needs it.
- A null or empty path parameter refuses the call: the C++ `string_view` cannot
  be null, and `/lobbies/` would be another operation.
- `Event.Name` is C++'s `event.event`, since C# forbids a member named after its
  type. A timer cancelled by an earlier timer in the same drain no longer fires.
- No peer connection ships: `IPeerTransport` is the interface a Unity package or
  a game fills.

## Unity, as built

`clients/unity_template/` and `clients/generate_unity.sh`, output `unity_sdk/`
(the UPM package `org.gamend.sdk`, Unity 2021.3+). The C# SDK's sources are
copied into `Runtime/Sdk` (assembly `Gamend`, `noEngineReferences`) without
`HttpClientTransport` and the test fakes; `Runtime/Unity` (assembly
`Gamend.Unity`) is hand-written:

- `GamendBehaviour`: builds the client on first use from its inspector fields,
  polls it in `Update` at execution order -1000, disposes of it in `OnDestroy`,
  and by default survives scene loads as `GamendBehaviour.Instance`.
- `UnityHttpTransport` over `UnityWebRequest` on every platform: WebGL needs it,
  and `System.Net.Http` is not referenced under every API compatibility level.
  A send off the main thread is posted to Unity's `SynchronizationContext`.
- `UnityWebSocketTransport`: `ClientWebSocketTransport` outside WebGL; in a
  WebGL player, `GamendWebSocket.jslib`, with frames crossing as pointer and
  length (`makeDynCall`, so Unity 2021.2+).
- Newtonsoft comes from Unity's `com.unity.nuget.newtonsoft-json`, a package
  dependency. Every asset has a `.meta` (`clients/unity_package.py`): the
  template's are committed, the SDK's derived from their paths.

**Installing.** A git URL,
`https://github.com/appsinacup/gamend-unity.git#<version>`: the package at the
root of a repository of its own, since it is not committed in this one and
Unity would clone all of this one (hundreds of MB) for it. `publish-unity-sdk`
in CI replaces that repository's contents with each version and tags it
(`UNITY_UPM_REPO`, and `UNITY_UPM_DEPLOY_KEY`, the private half of a deploy key
with write access there). A commit that changes only the version stamped into
the package (`package.json`, `Version.cs`) is skipped, so every tag is a change.
`gamend-unity-sdk.tgz` on the `latest` release is for a machine without git.
OpenUPM can list the repository next.

**Checked without Unity.** `clients/check_unity.sh` checks the `.meta` files,
compiles both assemblies and the sample at C# 9 against UnityEngine stubs
(`clients/unity_check/UnityStubs.cs`) with and without `UNITY_WEBGL`, and runs
the jslib in node against a fake WebSocket and heap. No editor import, no IL2CPP
or WebGL player build, no live run: a Unity CI job (game-ci) needs a Unity
licence in the repository's secrets.

## Rust, as built

`clients/sdkgen/rust.py` and `clients/rust_template/`, output `rust_sdk/`.
Stable Rust, 181 player operations as C#. It differs from the C++ SDK in:

- No callbacks: a callback holding game state fights the borrow checker in every
  Rust engine. A call answers a `Ticket<T>` (`try_take`, or `.await`), completed
  in `Client::poll()`, and events are drained: `realtime().events()`.
- `Client` is `Send + Sync`, so it can be a Bevy `Resource`.
- The core has no threads and no clock. Those live behind the default `native`
  feature (`ureq`, `tungstenite`), and CI builds the core for wasm32 without it.
- Models are generated `Model` impls, not serde. No overloads: where every query
  key is optional, `<name>_with` takes the options.
- No peer connection ships: `PeerTransport` is the trait a game fills.

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
