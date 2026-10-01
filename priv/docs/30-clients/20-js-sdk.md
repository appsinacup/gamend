---
icon: hero-code-bracket
---

# JavaScript Client SDK

[View on NPM](https://www.npmjs.com/package/@ughuuu/gamend)

The REST client is generated from the OpenAPI spec, so every endpoint has a
method and every method matches the [API reference](/api/docs). This guide
covers what the generated docs cannot tell you: setup, the auth flows, and
realtime.

```bash
npm install @ughuuu/gamend
```

That is the whole install. The HTTP client, the Phoenix channel wrapper and the
protobuf codec all arrive with the package, so there is nothing else to add.

## Connect

```javascript
const { GamendSession, HealthApi } = require('@ughuuu/gamend');

const gamend = new GamendSession('http://localhost:4000');

await new HealthApi(gamend.client).index();
```

`GamendSession` keeps the player signed in, and `gamend.client` is the client
every generated API class takes: `new LobbiesApi(gamend.client)`,
`new LeaderboardsApi(gamend.client)`, and so on.

## Authenticate

Sign in through `gamend.client` and the session keeps what the answer carries:

```javascript
const authApi = new AuthenticationApi(gamend.client);

await authApi.login({
  loginRequest: { email: 'user@example.com', password: 'password123' }
});

gamend.userId; // the signed-in player
```

Every sign-in (email, device, a provider) answers an access token, which lasts
15 minutes, and a refresh token, which lasts 30 days. The session sends the
access token with every call made through `gamend.client`, refreshes it a
minute before it expires, and after a `401` refreshes it and retries the call
once. Concurrent calls share one refresh.

### Keep the session

To stay signed in across reloads, save the session whenever it changes and
restore it at start-up:

```javascript
gamend.on('session', session => session
  ? localStorage.setItem('gamend', JSON.stringify(session))
  : localStorage.removeItem('gamend'));
gamend.on('authFailed', () => showSignIn());

gamend.restore(JSON.parse(localStorage.getItem('gamend')));
```

`session` fires on sign-in, on every refresh and on sign-out, with `null`.
`authFailed` fires when the server refuses the refresh token: it expired, or
the player signed out on another device or changed their password. The session
is gone by then, so show the sign-in screen. The refresh token signs in for 30
days, so keep it where you would keep a password: any script on the page can
read `localStorage`.

`await gamend.signOut()` revokes the player's tokens on every device, drops the
session and disconnects its sockets. It drops the session even when the server
cannot be reached.

### OAuth

The browser flow hands off to the provider and polls for the result, so it
works from a game client with no redirect handler of its own:

```javascript
const { authorization_url, session_id } = (await authApi.oauthRequest('discord')).data;
window.open(authorization_url, '_blank');

let status;
do {
  await new Promise(r => setTimeout(r, 1000));
  status = (await authApi.oauthSessionStatus(session_id)).data;
} while (status.status === 'pending');

if (status.status === 'completed') {
  // gamend took the session from the answer: gamend.signedIn is true
}
```

If your client can receive the provider's redirect itself, exchange the code
directly instead; see the Authentication guide.

## Errors

Generated methods reject with an error carrying the HTTP status and the
server's JSON body:

```javascript
try {
  await lobbiesApi.joinLobby(id);
} catch (e) {
  switch (e.status) {
    case 401: /* signed out: the session already tried a refresh */ break;
    case 403: /* not permitted, e.g. not the host */ break;
    case 404: /* gone */ break;
    case 422: console.error(e.body.errors); break;   // validation
    case 429: /* rate limited - back off */ break;
  }
}
```

## Realtime

The package bundles `GameRealtime`, a thin wrapper over Phoenix channels that
handles the socket URL, the token and protobuf decoding. Open one from the
session:

```javascript
const realtime = gamend.realtime();

const user = realtime.joinUserChannel(gamend.userId);
user.on('notification_created', payload => console.log('notification', payload));

const lobby = realtime.joinLobbyChannel(lobbyId);
lobby.on('updated', lobbyPayload => console.log('lobby changed', lobbyPayload));

realtime.disconnect();
```

The server checks the token only when the socket connects, and Phoenix
reconnects on its own after a dropped network, a sleeping laptop or a tab back
from the background, often long after the token it started with expired. So the
socket asks the session for a token before it connects and again after every
failed connect, and the next retry carries a valid one. Signing out disconnects
it.

Pass `{ format: 'protobuf' }` to `gamend.realtime` to receive binary frames;
channels from the join helpers decode them transparently, with timestamps as
unix-ms numbers.

`updated` carries the **full** object rather than a delta, so diff against your
last copy if you need to know which field moved. The complete topic and event
list is in the Realtime guide.

### Without GamendSession

An app that keeps its tokens elsewhere passes `GameRealtime` a function that
returns a valid access token, or a promise of one, and sets the token on its own
`ApiClient`:

```javascript
apiClient.authentications.authorization.accessToken = accessToken;

const realtime = new GameRealtime('https://your-server.com', getAccessToken, { format: 'protobuf' });
```

The function runs before the first connect and after every failed one,
including while the server is unreachable, as often as every 5 seconds. Return
the cached token while it is valid and refresh only when it is about to expire.
