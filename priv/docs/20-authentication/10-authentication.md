---
icon: hero-finger-print
---

# Authentication

The platform supports multiple authentication methods. All API authentication uses JWT tokens (access + refresh). Browser sessions use cookie-based session tokens.

## Supported methods

- **Email / Password** — traditional registration with confirmation emails
- **Magic link** — passwordless login via email link
- **Device token** — anonymous / guest authentication via unique device IDs
- **OAuth** — Discord, Google, Apple, Facebook, Steam

## JWT token flow (Email / Password / Device)

```text
  1. LOGIN
     Client ──► POST /api/v1/login         ──►   Verify credentials
                (email + password)                 │
                                                   ▼
            ◄── { access_token, refresh_token } ◄─ Guardian signs JWT

  2. AUTHENTICATED REQUEST
     Client ──► GET /api/v1/me              ──► Guardian verifies token
                Authorization: Bearer {token}      │
                                                   ▼
            ◄── { user data }                 ◄── Load user from claims

  3. TOKEN REFRESH
     Client ──► POST /api/v1/refresh         ──► Guardian exchanges token
                { refresh_token }                  │
                                                   ▼
            ◄── { access_token, refresh_token } ◄─ New token pair
```

Access tokens are short-lived (15 min). Refresh tokens last 30 days. Both are stateless JWTs — no database lookup on each request.

## OAuth — browser redirect (polling)

For game clients that can't handle OAuth natively. The client opens a browser, then polls for the result.

```text
  Client ──► GET /api/v1/auth/{provider}
         ◄── { session_id, auth_url }

  Client ──► Opens auth_url in browser
             Browser ──► OAuth Provider ──► User authenticates
             Provider ──► Callback to server
             Server stores result in DB

  Client ──► GET /api/v1/auth/session/{session_id}   (poll)
         ◄── { status: "pending" }                   (repeat)
         ◄── { status: "completed", access_token, refresh_token }
```

## OAuth — direct code exchange

For clients that handle OAuth natively (mobile SDKs, Steam auth tickets). No browser or polling needed.

```text
  Client ──► Initiates OAuth via native SDK
  Provider ──► Returns authorization code to client

  Client ──► POST /api/v1/auth/{provider}/callback  { code: "..." }
         ◄── { access_token, refresh_token, user }
```

## Provider linking

Users can link multiple OAuth providers to a single account and unlink them later. The user table stores provider IDs as nullable fields (discord_id, google_id, apple_id, facebook_id, steam_id, device_id).

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`GameServer.Accounts`](https://appsinacup.com/game_server/GameServer.Accounts.html) - the functions a plugin calls, with their
  signatures and docs.
