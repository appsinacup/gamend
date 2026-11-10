---
icon: hero-code-bracket-square-solid
---

# C# Client SDK

[Download](https://github.com/appsinacup/gamend/releases/download/latest/gamend-csharp-sdk.tar.gz) ·
[View the source](https://github.com/appsinacup/gamend/tree/main/clients/csharp_template)

A `netstandard2.1` client for .NET games and tools (MonoGame, Stride, Godot
.NET), and the core a Unity package builds on. Every player-facing operation is
a method, generated from the same OpenAPI document as the other SDKs and named
as the Godot SDK names it, in PascalCase. It starts no threads and uses no
reflection.

## Add it

Unpack the download and reference `src/Gamend/Gamend.csproj`, or copy `src/Gamend`
into your project. The one dependency is
[Newtonsoft.Json](https://www.newtonsoft.com/json).

## Connect and sign in

```csharp
using Gamend;
using Gamend.Net;
using Newtonsoft.Json.Linq;

var client = new Client(new Config
{
    BaseUrl = "https://game.example.com",
    Http = new HttpClientTransport(),
    WebSocket = new ClientWebSocketTransport(),
});

var signedIn = await client.Auth.LoginDevice(deviceId);
if (!signedIn.Ok) { ShowError(signedIn.Error); return; }
client.Realtime.Connect();
```

Call `client.Poll()` once per frame on the game thread. Every task completes
there, so an `await` continues on that thread and can touch game state. Do not
add `ConfigureAwait(false)`, which sends the continuation elsewhere.

The session refreshes itself. Save `client.Auth.Session` where your platform
keeps secrets and hand it to `client.Auth.Restore` on the next run.

## Calls and replies

```csharp
var reply = await client.Api.LobbiesQuickJoin(new JObject { ["title"] = "duel", ["max_users"] = 2 });
var lobby = reply.As<Models.Lobby>();

var page = await client.Api.LobbiesListLobbies();
foreach (var row in page.Page<Models.Lobby>().Data) Show(row.Title);
```

A method takes the path's parameters, then `body`, then `options` for the query.
A missing required field is not sent: the reply's `Error` names it. The admin API
is left out, since a game never holds an admin token.

## Realtime

```csharp
client.Realtime.OnEvent(e =>
{
    if (e.Kind == Events.LobbyUpdated) Refresh(e.Payload);
});
await client.Realtime.JoinLobby(lobby.Id);
var hook = await client.Realtime.CallHook("arena", "start", new JArray());
```

A dropped connection reconnects, refreshes its token and rejoins its topics.
`Commands` has a method for each event a channel answers, such as
`Commands.ResultsList(client.Realtime, parameters)`. Set
`RealtimeFormat = RealtimeFormat.Protobuf` for binary frames. Live key-value rows
are `client.Kv`, merged profiles and online state `client.Presence`.

## WebRTC

`client.WebRtc` runs the server's DataChannels over any `IPeerTransport`. None
ships yet, so bring one that wraps your engine's WebRTC library.
