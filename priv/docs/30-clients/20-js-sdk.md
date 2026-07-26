---
icon: hero-code-bracket
---

# JavaScript Client SDK

[View on NPM](https://www.npmjs.com/package/@ughuuu/game_server)

The REST client is generated from the OpenAPI spec, so every endpoint has a
method and every method matches the [API reference](/api/docs). This guide
covers what the generated docs cannot tell you: setup, the auth flows, and
realtime.

```bash
npm install @ughuuu/game_server
```

## Connect

```javascript
const { ApiClient, HealthApi } = require('@ughuuu/game_server');

const apiClient = new ApiClient();
apiClient.basePath = 'http://localhost:4000';

await new HealthApi(apiClient).index();
```

Every other API class takes the same `apiClient`, so configuring it once is
enough: `new LobbiesApi(apiClient)`, `new LeaderboardsApi(apiClient)`, and so on.

## Authenticate

All authenticated calls use a JWT access token. Set it once on the client:

```javascript
const authApi = new AuthenticationApi(apiClient);

const { access_token, refresh_token, user_id } = (await authApi.login({
  loginRequest: { email: 'user@example.com', password: 'password123' }
})).data;

apiClient.defaultHeaders = { Authorization: `Bearer ${access_token}` };
```

Access tokens last 15 minutes, refresh tokens 30 days. Refresh before the
access token expires, or retry once on a `401`:

```javascript
const refreshed = await authApi.refresh({ refreshRequest: { refresh_token } });
apiClient.defaultHeaders = { Authorization: `Bearer ${refreshed.access_token}` };
```

### OAuth

The browser flow hands off to the provider and polls for the result, so it
works from a game client with no redirect handler of its own:

```javascript
const { authorization_url, session_id } = await authApi.oauthRequest('discord');
window.open(authorization_url, '_blank');

let session;
do {
  await new Promise(r => setTimeout(r, 1000));
  session = await authApi.oauthSessionStatus(session_id);
} while (session.status === 'pending');

if (session.status === 'completed') {
  const { access_token, refresh_token, user_id } = session.data;
}
```

If your client can receive the provider's redirect itself, exchange the code
directly instead — see the Authentication guide.

## Errors

Generated methods reject with an error carrying the HTTP status and the
server's JSON body:

```javascript
try {
  await lobbiesApi.joinLobby({ joinLobbyRequest: { lobby_id: id } });
} catch (e) {
  switch (e.status) {
    case 401: /* token expired - refresh and retry */ break;
    case 403: /* not permitted, e.g. not the host */ break;
    case 404: /* gone */ break;
    case 422: console.error(e.body.errors); break;   // validation
    case 429: /* rate limited - back off */ break;
  }
}
```

## Realtime

The package bundles `GameRealtime`, a thin wrapper over Phoenix channels that
handles the socket URL, the token and protobuf decoding:

```javascript
import { GameRealtime } from '@ughuuu/game_server';

const realtime = new GameRealtime('https://your-server.com', access_token);

const user = realtime.joinUserChannel(userId);
user.on('notification_created', payload => console.log('notification', payload));

const lobby = realtime.joinLobbyChannel(lobbyId);
lobby.on('updated', lobbyPayload => console.log('lobby changed', lobbyPayload));

realtime.disconnect();
```

Pass `{ format: 'protobuf' }` as the third argument to receive binary frames;
channels from the join helpers decode them transparently, with timestamps as
unix-ms numbers.

`updated` carries the **full** object rather than a delta, so diff against your
last copy if you need to know which field moved. The complete topic and event
list is in the Realtime guide.
