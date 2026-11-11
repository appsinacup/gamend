# Unreal plugin

Goal: Gamend in Unreal Engine 5 without a second client. The plugin is the
[C++ SDK](cpp-sdk.md) as it is, Unreal transports under it, and a Blueprint
surface over it ([#28](https://github.com/appsinacup/gamend/issues/28)).

Part of [client-sdks.md](client-sdks.md). Built, in beta; the guide is
`priv/docs/30-clients/26-unreal-sdk.md`.

## Shape

`clients/generate_unreal.sh` writes `unreal_plugin/Gamend/` (not committed)
from `clients/unreal_template/` and `cpp_sdk/`. CI zips it as
`gamend-unreal-plugin.zip` on the `latest` release.

| Module | Holds |
|---|---|
| `GamendSDK` | `cpp_sdk/include` in `Public/`, `cpp_sdk/src` in `Private/`, minus the curl, IXWebSocket and libdatachannel transports; nlohmann/json in `ThirdParty/`, the release the SDK's CMake build pins. No PCH, no unity build, no engine header |
| `Gamend` | `UGamendSubsystem`, the transports (`GamendTransports.cpp`), `UGamendSettings`, `UGamendAsyncAction`, `UGamendJsonLibrary` |

- **Transports.** `HttpTransport` over `FHttpModule`, `WebSocketTransport`
  over `FWebSocketsModule` (text frames as `OnMessage`, binary as fragments
  of `OnBinaryMessage`, sent as raw UTF-8). No `PeerTransport`: Unreal has no
  DataChannel module.
- **Ticking.** `FTSTicker` calls `poll()` every frame, paused or not, so every
  callback runs on the game thread.
- **Session.** `on_session_changed` writes the session to a `USaveGame` slot,
  restored at start (`bKeepSession`), as Godot keeps it in `user://`. Each
  extra multiplayer PIE player gets its own slot.
- **Blueprints.** One `UBlueprintAsyncActionBase` with a static factory per
  node (sign-in, lobbies, leaderboards, KV, hooks, push, any call by path);
  results and events carry JSON as text, read with the JSON library.

## Exports

An editor build links each module as a shared library with hidden symbols,
so a game module calling `gamend::Client` needs the SDK's classes exported.
`gamend/export.hpp` defines `GAMEND_EXPORT`: empty for the CMake build,
export or import when `GAMEND_BUILDING` / `GAMEND_SHARED` are set, which
`GamendSDK.Build.cs` does for a modular build. The emitter marks `Api` and
each `Codec<models::T>`; the template marks `Client`, `Auth`, `Rest`,
`Realtime`, `Kv`, `Presence`, `WebRtc` and `Session`.

## Verified, and not

`clients/check_unreal.sh`, in CI's `unreal-plugin` job: the `GamendSDK`
module in C++17 and C++20 (`-fno-exceptions -fno-rtti -Wshadow -Wundef
-Werror`), every public header alone, built into a hidden-visibility shared
library that `unreal_check/sdk_check.cpp` links against and runs. Without the
exports, that link misses 36 symbols. It found C++20's deprecated implicit
`this` capture in `webrtc.cpp`, now fixed.

Not verified: anything that needs the engine. The `Gamend` module has never
been compiled; MSVC has never compiled `GamendSDK` with exceptions off and
`dllexport`; the transports have never carried a request.

## Open

- Build it in an engine: a project with the plugin, a Blueprint that signs in
  and hears a lobby event, on Windows (MSVC) and macOS.
- Run the conformance scenario through the Unreal transports.
- Fab (Marketplace) listing, which wants per-engine-version builds.

## Definition of done

- [x] Template, `generate_unreal.sh`, CI job and release zip.
- [x] Guide, README, CHANGELOG.
- [ ] Builds and runs in Unreal 5.3+ on Windows and macOS; out of beta.
