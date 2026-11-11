---
icon: hero-cube-solid
---

# Unity SDK

[Package repository](https://github.com/appsinacup/gamend-unity) ·
[Download](https://github.com/appsinacup/gamend/releases/download/latest/gamend-unity-sdk.tgz) ·
[View the source](https://github.com/appsinacup/gamend/tree/main/clients/unity_template)

The [C# SDK](/docs/csharp-sdk) as a Unity package, `org.gamend.sdk`, for Unity
2021.3 or newer. It adds what Unity needs around it: a component that builds the
client and polls it every frame, HTTP over `UnityWebRequest`, and on WebGL a
socket through the browser's own WebSocket. The calls, the realtime layer and
the models are the C# SDK's, so its guide holds for everything below the
component. It uses no reflection, so IL2CPP needs no `link.xml` for it.

## Install it

The package lives in a repository of its own,
[appsinacup/gamend-unity](https://github.com/appsinacup/gamend-unity), with a
tag for each version. In Unity, open **Window > Package Manager**, then **+ >
Add package from git URL...**, and paste the URL with the newest of its
[tags](https://github.com/appsinacup/gamend-unity/tags) in place of `<version>`:

```
https://github.com/appsinacup/gamend-unity.git#<version>
```

A version is the C# SDK's it carries, the same code as `Gamend` of that number
on NuGet, and a new one comes only when the SDK changes, so the numbers skip.
Unity writes the URL into `Packages/manifest.json`; to update, change the
version there:

```json
"org.gamend.sdk": "https://github.com/appsinacup/gamend-unity.git#<version>"
```

A URL without `#` takes what `main` holds when Unity first resolves it and
keeps that commit in `Packages/packages-lock.json`, so a teammate may get
another one; name the version. The Package Manager runs git for this, so
whoever opens the project needs git installed.

It installs [Newtonsoft Json](https://docs.unity3d.com/Packages/com.unity.nuget.newtonsoft-json@3.2/manual/index.html)
with it, Unity's own package of the one library the SDK depends on.

### Without git

Every change to Gamend also puts the package on the `latest` release as
`gamend-unity-sdk.tgz`. Download it into your project, next to `Assets/`,
commit it there, and pick it with **+ > Add package from tarball...**. Check the
line Unity writes into `Packages/manifest.json` reads as a path inside the
project, which a teammate's checkout has too:

```json
"org.gamend.sdk": "file:../gamend-unity-sdk.tgz"
```

To update, download the new tarball over the old one.

## Connect and sign in

Add **Gamend > Gamend Client** (`GamendBehaviour`) to a GameObject in your first
scene and set **Base Url** to your server. By default it keeps the object, and
its connection, when another scene loads; a copy in a scene loaded later removes
itself. Any script reaches it as `GamendBehaviour.Instance`:

```csharp
using Gamend;
using Gamend.Unity;
using UnityEngine;

public class SignIn : MonoBehaviour
{
    async void Start()
    {
        var client = GamendBehaviour.Instance.Client;
        var signedIn = await client.Auth.LoginDevice(DeviceId());
        if (!signedIn.Ok) { Debug.LogError(signedIn.Error); return; }
        client.Realtime.Connect();
    }
}
```

`GamendBehaviour` runs before your scripts and calls `Client.Poll()` in its
`Update`, so a reply or an event arrives on the main thread at the start of a
frame, and an `await` continues there and can touch the scene. The client is
built the first time `Client` is read, from the component's fields as they are
then; to change anything else (ICE servers, timeouts), subclass it and override
`Configure(Config config)`.

`DeviceId()` is yours to write. `SystemInfo.deviceUniqueIdentifier` is not one
on every platform (WebGL has none); the Quick Start sample keeps a random id in
`PlayerPrefs` instead.

## Calls and realtime

They are the [C# SDK](/docs/csharp-sdk)'s:

```csharp
var reply = await client.Api.LobbiesQuickJoin(new JObject { ["title"] = "duel", ["max_users"] = 2 });
if (!reply.Ok) { Debug.LogError(reply.Error); return; }
var lobby = reply.As<Models.Lobby>();

client.Realtime.OnEvent(e =>
{
    if (e.Kind == Events.LobbyUpdated) Refresh(e.Payload);
});
await client.Realtime.JoinLobby(lobby.Id);
```

A listener runs inside `Poll`, and what it throws reaches the Console from
`GamendBehaviour.Update` once the frame's other replies have run. Set
**Realtime Format** to Protobuf for binary frames.

## Keeping the session

The access token lasts 15 minutes and refreshes itself; the refresh token lasts
30 days. Keep the session for the next run with `OnSessionChanged`, and hand it
back with `Restore` before the first call:

```csharp
client.Auth.OnSessionChanged(session =>
    Store(session == null ? "" : session.ToJson().ToString()));

var kept = Load();
var session = kept.Length > 0 ? Session.FromJson(JObject.Parse(kept)) : null;
if (session != null) client.Auth.Restore(session);
```

`PlayerPrefs` is a plain file or registry entry anyone on the machine can read.
For anything worth taking, keep the refresh token where the platform keeps
secrets (the Keychain, Android's Keystore) through a plugin of your choice.

## WebGL

A WebGL player has no sockets of its own, so the package's socket there is the
browser's WebSocket, reached through a small `.jslib`, and its HTTP is the
browser's too. The SDK starts no threads, so nothing else changes.

- A page on another origin (itch.io, a CDN) can call the API and open the socket
  while `GAMEND_HTTP_ALLOWED_ORIGINS` is empty, the default. Once it names
  origins, add the page's.
- `Auth.SignIn` opens the provider's page with `Application.OpenURL` after a
  reply comes back, not inside a click, and a browser may block that tab.
  Device, email and Steam sign-in need no page.

## Without the component

Build the client in a script of your own, on the main thread, and poll it each
frame:

```csharp
client = new Client(new Config
{
    BaseUrl = "https://game.example.com",
    Http = new UnityHttpTransport(),
    WebSocket = new UnityWebSocketTransport(),
    OpenUrl = Application.OpenURL,
});

void Update() => client.Poll();
void OnDestroy() => client.Dispose();
```

## The Quick Start sample

In the Package Manager, select Gamend, open **Samples** and import **Quick
Start**. Put `QuickStart` on an empty GameObject (it adds a `GamendBehaviour`),
set Base Url, and press Play: it signs in with the device, connects, and
quick-joins a lobby, listing every event it hears.

## What CI checks

CI has no Unity. It compiles the package's two assemblies and the sample with
`dotnet`, Unity's C# version, against stand-ins for the UnityEngine types they
use (for the editor and players, and again for WebGL), and runs the WebGL
socket's `.jslib` in node against a fake browser. The C# SDK under it passes the
live conformance run against a server. Nothing yet opens the editor or builds a
player in CI, so report what goes wrong in either on
[GitHub](https://github.com/appsinacup/gamend/issues).
