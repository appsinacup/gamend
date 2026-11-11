---
icon: hero-cube-transparent-solid
---

# Unreal Plugin

[Download](https://github.com/appsinacup/gamend/releases/download/latest/gamend-unreal-plugin.zip) ·
[View the source](https://github.com/appsinacup/gamend/tree/main/clients/unreal_template)

An Unreal Engine 5 plugin on the [C++ SDK](/docs/cpp-sdk): a game instance
subsystem that holds the client and ticks it, Blueprint nodes for signing in
and the calls most games make first, an event for everything the realtime
connection hears, and the whole C++ API for the rest. HTTP and WebSockets go
through Unreal's own modules.

**Beta.** CI builds and tests the SDK as the plugin compiles it, in C++17 and
C++20 with the engine's rules. It cannot run Unreal, so the plugin's own
Unreal code is not built there: tell us what breaks on your engine version.

## Add it

Every change to Gamend puts the plugin on the `latest` release as
`gamend-unreal-plugin.zip`. Unzip it into your project's `Plugins/` folder,
so that you have `Plugins/Gamend/Gamend.uplugin`, and open the project.
Unreal builds the plugin with your game; a Blueprint-only project asks to
build it once, which needs the compiler Unreal uses on your platform.

Set the server in **Project Settings > Plugins > Gamend**:

| Setting | Default | |
|---|---|---|
| Base Url | `http://127.0.0.1:4000` | The server root |
| Http Timeout Seconds | 10 | How long a REST call waits |
| Keep Session | on | Keep the session in a save game slot, so the player stays signed in |
| Save Slot | `Gamend` | The slot for the session and the device id |
| Connect On Sign In | on | Open the realtime connection once a player is signed in |
| Realtime Format | Json | `Protobuf` for binary frames |

## Blueprints

Each call is an async node named **Gamend ...**, with On Success and On
Failure pins. Both carry an `FGamendResult`: `Data` is the answer as JSON,
`Error` the server's code (`invalid_credentials`, `not_found`, ...).

| Node | Does |
|---|---|
| Gamend Login Device | Signs in with a device id; given none, one the plugin makes and keeps |
| Gamend Login Email, Login Steam, Sign In | An email and password, a Steam ticket, or a provider's page (`google`, `discord`, ...) in the browser |
| Gamend Register Email, Confirm Registration | A new account, then the six-digit code from its email and a password |
| Gamend Logout | Revokes the session |
| Gamend Get Me | The player's account |
| Gamend Quick Join Lobby, Create Lobby, List Lobbies, Join Lobby, Leave Lobby | Lobbies |
| Gamend List Leaderboard Records | A leaderboard, a page at a time |
| Gamend Get Key Value | A key-value row |
| Gamend Call Hook | A server hook, over the realtime connection |
| Gamend Push | An event to a joined channel, and its reply |
| Gamend Call API | Any other operation, by method and path |

The **Gamend Json** nodes read and build that JSON: **Get String**, **Get
Integer**, **Get Items** and the rest take a dotted path
(`members.0.username`); **Set String** and the rest make a body.

On the subsystem (**Get GamendSubsystem**), bind **On Event**: each
`FGamendEvent` has the channel's `Topic`, its `Kind` as every SDK names it
(`lobby_updated`, `lobby_member_joined`, ..., see [realtime](/docs/realtime))
and its `Payload`. After joining a lobby, **Join Lobby Channel** hears it;
**Join Channel** takes any topic. **On Realtime State Changed** and **On
Session Changed** report the rest.

## C++

List `Gamend` and `GamendSDK` in your module's `.Build.cs` dependencies.
`GetClient()` is the C++ SDK's `gamend::Client`, every REST operation
included:

```cpp
#include "GamendSubsystem.h"
#include "GamendSDK.h"

TWeakObjectPtr<AMyHud> Hud(this);
UGamendSubsystem::Get(this)->GetClient().api().leaderboards_list_leaderboard_records(
  "weekly", {{"page_size", 10}}, [Hud](const gamend::Response& r) {
    auto page = r.page<gamend::models::LeaderboardRecord>();
    if (page && Hud.IsValid()) Hud->ShowRecords(page->data);
  });
```

Callbacks run on the game thread, in the subsystem's tick. The reply may come
after the actor is gone, so hold it weakly. The subsystem keeps the session
through `auth().on_session_changed`, which takes one listener: use its
`OnSessionChanged` instead. `realtime().on_event` takes any number.

## Sessions

With Keep Session on, the session goes into the save slot, refresh token
included and unencrypted, and comes back on the next run. To keep it
somewhere safer, turn Keep Session off, store `GetSessionJson()` and hand it
back to `RestoreSession`. Each extra player of a multiplayer PIE session gets
a slot of its own, so it signs in as someone else.

WebRTC is not in the plugin: Unreal has no DataChannel module to build it on.
Hooks go over the realtime connection.
