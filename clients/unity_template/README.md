# Gamend for Unity

The client SDK for [Gamend](https://gamend.org), the open-source game backend,
as a Unity package: sign-in, every player API call, realtime channels and
server hooks, live key-value rows and presence. Unity 2021.3 or newer, on every
platform Unity builds for, WebGL included.

The guide: [gamend.org/docs/unity-sdk](https://gamend.org/docs/unity-sdk).

## Install

In Unity, open **Window > Package Manager**, then **+ > Add package from git
URL...**, and paste this repository's URL with the newest of its
[tags](https://github.com/appsinacup/gamend-unity/tags) in place of `<version>`:

```
https://github.com/appsinacup/gamend-unity.git#<version>
```

The Package Manager runs git for it. Without git, take `gamend-unity-sdk.tgz`
from Gamend's [`latest` release](https://github.com/appsinacup/gamend/releases/tag/latest)
and add it with **Add package from tarball...**.

## Use

```csharp
using Gamend.Unity;

var client = GamendBehaviour.Instance.Client;
var signedIn = await client.Auth.LoginDevice(deviceId);
if (signedIn.Ok) client.Realtime.Connect();
```

- `Runtime/Sdk` is the C# SDK (assembly `Gamend`), the same code as the
  [`Gamend` NuGet package](https://www.nuget.org/packages/Gamend), generated from
  the server's API.
- `Runtime/Unity` (assembly `Gamend.Unity`) is what Unity adds:
  `GamendBehaviour`, which builds the client and polls it every frame, and
  transports over `UnityWebRequest` and, on WebGL, the browser's WebSocket.
- The Quick Start sample, imported from the Package Manager, signs in, connects
  and quick-joins a lobby.

This package is generated from
[clients/unity_template](https://github.com/appsinacup/gamend/tree/main/clients/unity_template)
on every change to Gamend, and [appsinacup/gamend-unity](https://github.com/appsinacup/gamend-unity)
is what CI writes from it: change it in Gamend, and report issues
[there](https://github.com/appsinacup/gamend/issues).
