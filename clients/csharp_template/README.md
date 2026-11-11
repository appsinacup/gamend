# Gamend C# SDK

A C# client for [Gamend](https://gamend.org): every player-facing REST
operation, typed models, sign-in and a session that stays fresh, the realtime
connection with server hooks, live key-value rows and presence, protobuf events,
and WebRTC DataChannels, over transports you choose. It targets
`netstandard2.1` and C# 9, starts no threads and uses no reflection, so a Unity
package, IL2CPP and WebGL included, can sit on it as it is.

This directory is generated: `src/Gamend/Generated/*.g.cs` and `REFERENCE.md` by
`clients/sdkgen` from the OpenAPI document, `clients/events.json`,
`clients/commands.json` and `proto/gamend_realtime.proto`; the rest is copied
from `clients/csharp_template/`. Edit those, not this, and run
`clients/generate_csharp.sh`. A game never holds an admin token, so the admin
API is left out; `client.Rest.Send` reaches it for a tool that needs it.

## Add it

`dotnet add package Gamend` from NuGet, or reference `src/Gamend/Gamend.csproj`,
or take `src/Gamend` as source. The one
dependency is [Newtonsoft.Json](https://www.newtonsoft.com/json), which Unity
has as `com.unity.nuget.newtonsoft-json`.

Every network library sits behind an interface in `Transport.cs`:
`IHttpTransport`, `IWebSocketTransport` and `IPeerTransport`, a page each.
`Gamend.Net` has `HttpClientTransport` and `ClientWebSocketTransport`. An engine
with its own stack (`UnityWebRequest`, a jslib socket on WebGL) implements those
instead. No peer connection ships yet; `WebRtc` runs over one you bring.

## Use it

```csharp
using Gamend;
using Gamend.Net;
using Newtonsoft.Json.Linq;
using Models = Gamend.Models;    // the API's types, as Models.Lobby

var client = new Client(new Config
{
    BaseUrl = "https://game.example.com",
    Http = new HttpClientTransport(),
    WebSocket = new ClientWebSocketTransport(),
    OpenUrl = url => OpenInBrowser(url),
});

client.Realtime.OnEvent(e =>
{
    if (e.Kind == Events.LobbyUpdated) RefreshLobby(e.Payload);
});

var signedIn = await client.Auth.LoginDevice(DeviceId());
if (!signedIn.Ok) { ShowError(signedIn.Error); return; }
client.Realtime.Connect();                         // joins user:<id> itself

var reply = await client.Api.LobbiesQuickJoin(new JObject { ["title"] = "duel", ["max_users"] = 2 });
var lobby = reply.As<Models.Lobby>();
if (lobby != null) await client.Realtime.JoinLobby(lobby.Id);

// Once per frame, on the game thread:
client.Poll();
```

**Everything completes in `Poll()`.** Transports may finish on any thread and
hand their results to an inbox; `Poll()` runs them on the thread that calls it,
in the order they arrived, then the timers that are due (token refresh, sign-in
polling, heartbeats, reconnects). A task never completes inside the call that
started it, and an `await` continues inline on the polling thread. Do not add
`ConfigureAwait(false)`: under a game loop's context that sends the continuation
to the thread pool. The SDK's methods are safe to call from any thread. An
exception a listener throws does not stop the frame's work; `Poll()` rethrows
the first one at the end.

## REST

**Every method is one operation**, named as the Godot SDK names it, in
PascalCase: the path's parameters, then `body`, then `options` for the query,
and a form without `options` when no query key is required. `REFERENCE.md` lists
them by tag and `Api.g.cs` lists each one's fields. A missing required field is
not sent: the task gets ``<Method> needs `<field>` ``.

**A `Response`** is the `Status`, the decoded `Body`, the raw `Text` and `Bytes`,
and an `Error` that is empty on success. Gamend answers one of four shapes, and
the accessors read them: `Data`, `Meta` for a page, `Code` and `Message` for an
error, `Errors` for `validation_failed`.

**Typed models.** `Gamend.Models` has a class for every schema the API answers
with. `r.As<Models.Lobby>()` reads `Data`, `r.Page<Models.Lobby>()` a page with
its `Meta`, and `r.As<List<string>>()` a list. Reads are lenient: a field that is
missing or mistyped keeps its default, a nullable value is `T?`, a map is a
`Dictionary`, and a free-form object stays `JToken`. `Codec.WriteLobby` turns a
model back into JSON.

**Reading JSON.** `JToken`'s indexer throws on a value that is not a container.
Read replies with the models, or with `Json.Text(obj, "key")`,
`Json.Number(obj, "key")` and `Json.Field(obj, "key")`, which cannot fail.

## Sessions

`Auth` signs in and keeps the session: `LoginDevice`, `LoginEmail`, `LoginSteam`
(a `GetAuthTicketForWebApi` ticket), and `SignIn(provider)`, which opens the
provider's page through `Config.OpenUrl` and polls until the player finishes.
Every call after that carries the access token. It is refreshed when three
quarters of its 15 minutes have passed, and once more on a `401`; a refresh the
server refuses signs out.

Signing in never links: `Link(provider)` and `LinkSteam(ticket)` add a provider
to the signed-in account. Registering is not a sign-in either, and takes no
password: `RegisterEmail(email)` makes the account, and
`ConfirmRegistration(email, code, password)` takes the emailed code, sets the
password and signs in.

Keep the session between runs where your platform keeps secrets:

```csharp
client.Auth.OnSessionChanged(s =>
{
    if (s != null) SecureStore.Write("gamend", Json.Dump(s.ToJson()));
    else SecureStore.Erase("gamend");
});

var kept = Session.FromJson(Json.Parse(SecureStore.Read("gamend")));
if (kept != null) client.Auth.Restore(kept);  // refreshed on the next Poll if it lapsed
```

## Realtime

`Realtime.Connect()` opens the Phoenix socket (`vsn=2.0.0`) as the signed-in
player and joins `user:<id>`. `Join(topic)` (and `JoinLobby`, `JoinLobbies`,
`JoinGroup`, `JoinGroups`, `JoinParty`) joins now or as soon as the socket opens;
`Push(topic, eventName, payload)` answers the server's reply or `timeout`;
`CallHook(plugin, fn, args)` calls a server hook over the user channel.
`Commands` has a method for each event a channel answers.

A dropped connection reconnects on its own, backing off (0.1 s, 0.5 s, 1 s, 2 s,
5 s, then every 10 s: `Config.ReconnectDelays`), refreshing the token first when
the last attempt never opened, and rejoins every topic it had, in order;
`OnState` says when. A missed heartbeat counts as a drop. A channel the server
errors is joined again after a second; one it closes (a kick) is not. A join
refused as `unauthorized`, `forbidden` or `not_found` is dropped. Signing out
disconnects.

Events arrive named: `Event.Kind` is one of `Events`, or `Events.Message` for one
the table does not name.

**Protobuf.** `Config.RealtimeFormat = RealtimeFormat.Protobuf` asks the server
for binary frames; they are decoded before `OnEvent`, into the same payload as
JSON mode except that timestamps are unix milliseconds (`*_ms`). No protobuf
library is involved. Metadata or KV data the game plugin sends in its own schema
is read by the decoder you register: `RegisterMetadataDecoder("lobby", fn)`,
`RegisterKvDecoder("match:*", fn)`. Unread, it stays base64.

## Live rows and presence

`Kv.Subscribe(new KvKey("progress", userId))` subscribes to a key-value row over
the socket, again after every rejoin; `Kv.Row(key)` is the latest value from
subscribe replies, pushes and `Kv.Fetch(key)` (REST, cache first). `Kv.OnChange`
hears every change.

`Presence` keeps merged user profiles, lobbies and online state from the realtime
events: `User(id)`, `Lobby(id)`, `Online(id)`, `LastSeen(id)`, `OnUserChanged`.
Metadata merges one section deep, so a sparse update never wipes the rest; the
player's own push replaces theirs whole.

## WebRTC

With `Config.WebRtc` set and the realtime connection up, `WebRtc.Connect()` opens
a DataChannel to the server, signaled over the user channel. `WebRtc.CallHook`
calls hooks over it, as JSON messages or, with `Config.WebRtcFormat` set to
protobuf, envelopes with request ids, where `CallHookRaw` sends a typed hook the
game's own encoded request and hands back the reply's bytes. `Send` and `OnData`
carry the game's own messages. Losing the socket closes it.

## Test with it

`Gamend.Testing` has `FakeHttp`, `FakeWebSocket`, `FakePeer` and `FakeClock`:
answer requests, play the server's frames, drive the peer and move time by hand,
then `Poll()`.

```sh
dotnet build
dotnet test
dotnet run --project examples/Conformance -- http://127.0.0.1:4000             # live, JSON
dotnet run --project examples/Conformance -- http://127.0.0.1:4000 --protobuf  # live, protobuf
```

The conformance program runs the scenario every Gamend SDK passes: sign in,
`/me`, refresh, connect and join, a lobby and its update, a hook and a failing
one, a KV subscription hearing a write, a dropped socket reconnecting and
rejoining, a clean disconnect, and, with a peer transport, a hook over the
DataChannel. The KV step writes as an admin: set `GAMEND_ADMIN_EMAIL` and
`GAMEND_ADMIN_PASSWORD`, or it is skipped. The hooks need the example plugins
(`GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples`).

MIT, as Gamend is.
