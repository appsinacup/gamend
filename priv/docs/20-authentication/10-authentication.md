---
icon: hero-finger-print
---

# Authentication

The platform supports multiple authentication methods. All API authentication uses JWT tokens (access + refresh). Browser sessions use cookie-based session tokens.

## Supported methods

- **Email / Password** — registration in the browser with a confirmation email,
  or from a game client with `POST /api/v1/register`
- **Magic link** — passwordless login via email link
- **Device token** — anonymous / guest authentication via unique device IDs
- **OAuth** — Discord, Google, Apple, Facebook, GitHub, Steam

A provider goes live once its credentials are set (see its setup page in this
section); its sign-in buttons, `/auth/<provider>` routes, and the
`GET /api/v1/auth/providers` listing follow automatically. Set
`GAMEND_OAUTH_<PROVIDER>_ENABLED=false` to switch one off while keeping its
credentials.

An optional **captcha** (see below) protects the browser registration and
magic-link forms; it does not apply to any of the game-client flows.

## JWT token flow (Email / Password / Device)

A game client signs a player up with `POST /api/v1/register` (`email`,
`password`, optional `username`). It answers `201` with the same tokens as
login without waiting on the mail server: the confirmation email is queued,
as for the browser form, and sent and retried in the background. A taken
email or username is `409`, and a plugin that refuses the sign-up is
`403 registration_refused`.
Deleting an account (`DELETE /api/v1/me`) sends `current_password` when the
account has one.

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
            ◄── { access_token, refresh_token } ◄─ New access token
```

Access tokens are short-lived: 15 minutes by default, set with `GAMEND_AUTH_ACCESS_TOKEN_TTL_MINUTES`. Refresh tokens last 30 days by default, set with `GAMEND_AUTH_REFRESH_TOKEN_TTL_DAYS`. Every login and refresh answers `expires_in`, the access token's lifetime in seconds; schedule the refresh from it rather than from a fixed interval. A changed setting applies to tokens issued after it. Both are signed JWTs, but each authenticated request still loads the user from the database. So a token stops working once the account is deactivated or its tokens are revoked (logout, password or email change).

Refresh returns a new access token and sends back the same refresh token; it does not issue a new one. Log in again before the refresh token runs out.

Token responses wrap their fields in a `data` object (`{"data": {"access_token": "..."}}`); the diagrams leave that wrapper out.

## Browser sessions and emailed links

The website signs in with a session cookie rather than JWTs. The windows are settings on the `auth` group:

| Setting | Default | What it bounds |
|---|---|---|
| `GAMEND_AUTH_SESSION_DAYS` | `14` | A browser session and its remember-me cookie. An active session is renewed once it is half this old, so only an idle one runs out. |
| `GAMEND_AUTH_MAGIC_LINK_MINUTES` | `15` | An emailed login link. Capped at 60: whoever can read the email can sign in while it lives. |
| `GAMEND_AUTH_CONFIRM_EMAIL_DAYS` | `7` | The link that confirms a new account's email. |
| `GAMEND_AUTH_CHANGE_EMAIL_DAYS` | `7` | The link that confirms a changed email address. |
| `GAMEND_AUTH_SUDO_MODE_MINUTES` | `10` | How recently a user must have signed in to open the settings that change their password or email. Submitting the form is allowed ten minutes more. |

## Failed password lockout

The per-IP auth rate limit caps how fast one machine can guess, not guesses spread across many machines at one account. So failed passwords are also counted per email address: `GAMEND_AUTH_LOCKOUT_ATTEMPTS` failures (default `10`, `0` turns it off) within `GAMEND_AUTH_LOCKOUT_WINDOW_MINUTES` (default `15`) lock password sign-in for that address for `GAMEND_AUTH_LOCKOUT_MINUTES` (default `15`). The count lives in the database, so it holds across instances, and a correct password clears it.

While locked, the password is not checked at all: `POST /api/v1/login` answers `429 account_locked` with a `Retry-After` header, and the browser form says to try again later. An address with no account counts and locks exactly like one with an account, so the lock never reveals which addresses are registered. Only password sign-in is locked. An emailed login link and provider sign-ins still work, so someone failing at a player's password cannot shut the player out. An admin can lift a lock from the user's page in **Admin → Users**.

## Deleting an account

`DELETE /api/v1/me` and **Delete account** on the settings page delete the account at once by default. With `GAMEND_AUTH_DELETION_GRACE_DAYS` set, they schedule it that many days out instead, and sign the account out everywhere (sessions, access, refresh and personal API tokens). Until the date:

- **API sign-ins are refused** with `403 deletion_scheduled`: password, device and provider logins alike. A game client may sign in on its own, from a stored device id or a silent provider login, and that must not undo a deletion the player asked for.
- **Signing in on the website keeps the account**, with a message saying so. A person is at the keyboard there.
- **An admin can keep it** from the user's page in **Admin → Users**, where a scheduled account is marked **Deleting**.

On the date, the retention sweep deletes the account with `Gamend.Accounts.delete_user/1`, so every cleanup and the `after_user_deleted` hook run as for an immediate deletion. Admin deletions and the retention sweeps of inactive accounts never wait.

## OAuth: browser redirect (polling)

For game clients that can't handle OAuth natively. The client opens a browser, then polls for the result.

```text
  Client ──► GET /api/v1/auth/{provider}
         ◄── { session_id, authorization_url }

  Client ──► Opens authorization_url in browser
             Browser ──► OAuth Provider ──► User authenticates
             Provider ──► Callback to server
             Server stores result in DB

  Client ──► GET /api/v1/auth/session/{session_id}   (poll)
         ◄── { status: "pending", session: null }    (repeat)
         ◄── { status: "completed", session: { access_token, refresh_token, ... } }
```

`session` is the same `Session` email login answers, served once: later polls
say `completed` with `session: null`. A sign-in the server refuses ends as
`status: "error"` with a code in `error` (`account_not_activated`,
`sign_in_failed`, `authentication_failed`) and prose in `message`.

## OAuth: direct code exchange

For clients that handle OAuth natively (mobile SDKs, Steam auth tickets). No browser or polling needed.

```text
  Client ──► Initiates OAuth via native SDK
  Provider ──► Returns authorization code to client

  Client ──► POST /api/v1/auth/{provider}/callback  { code: "..." }
         ◄── { access_token, refresh_token, user_id, username, display_name }
```

Native Google (`POST /api/v1/auth/google/id_token`, `{id_token}`) and native
Apple (`POST /api/v1/auth/apple/ios/callback`, `{code}`) answer the same. For
Steam, `code` is the hex ticket from `ISteamUser::GetAuthTicketForWebApi`.

Every one of these signs in, finding or creating the account. A bearer token
on the request changes nothing; linking is its own endpoint.

## Usernames

Every account has a unique `username` handle: chosen at sign-up (`username` on
`POST /api/v1/register`) or generated from the display name, and changed with
`PATCH /api/v1/me/username`. It is 3-32 letters or digits of any language,
joined by single `.` `_` `-` separators. It is stored NFKC-normalized
([UAX #15](https://www.unicode.org/reports/tr15/)) and lowercased, so `Wang`,
`ＷＡＮＧ` and `wang` are one name.

Against impersonation it applies the two rules of Unicode's security standard
that browsers apply to international domain names, and nothing more:

| Rule | Allowed | Refused | Source |
| --- | --- | --- | --- |
| One script, or Latin with Chinese, Japanese or Korean | `дмитрий`, `王wang`, `小明abc`, `yamada太郎`, `김민준kim` | `pаypal` (Cyrillic `а`), `ivanиван` | [UTS #39](https://www.unicode.org/reports/tr39/#Restriction_Level_Detection) section 5.2, "Highly Restrictive" |
| Accents never repeated, at most four stacked | `nguyễn`, `tiệp` | `café` with the accent typed twice | [UTS #39](https://www.unicode.org/reports/tr39/#Optional_Detection) section 5.4 |

Latin, Cyrillic and Greek share dozens of identical letters, so mixing them
lets one handle pass for another; Chinese, Japanese and Korean share none
with Latin, so mixing those is safe. A CJK character that resembles a Latin
letter or separator (`丨`, `一`) is no more confusable than `1` and `-`, which
any ASCII handle holds, so `tom一号` is fine.

A refused handle answers `422 validation_failed` with the rule it broke in
`errors.username`. Display names have none of these rules.

For the GitHub and Discord model, ASCII handles and Unicode display names,
set `GAMEND_LIMITS_USERNAME_ASCII_ONLY=true`: a handle is then `a-z`, `0-9`
and the separators, input is still normalized first (`ＷＡＮＧ` is `wang`),
and a generated handle transliterates the name (`Drágoș` is `dragos`) or
picks a random word.

A plugin replaces these rules with the `validate_username/1` hook: it
receives the normalized handle and answers `:ok`, `{:error, message}` (shown
to the player) or `:default` for core's rules. Core keeps only length,
uniqueness and the absence of invisible characters. For a policy on top of
core's — banned words, reserved names — `before_user_update` refuses a
player's change with its own message and `before_user_register` swaps the
generated handle at sign-up; a sign-up always ends with a valid handle, so a
plugin bug never locks a player out. Details in the
[server scripting guide](/docs/server-scripting).

## Provider linking

A signed-in player can add providers to their account, and unlink them later.
The user table stores provider IDs as nullable fields (discord_id, google_id,
apple_id, facebook_id, github_id, steam_id, device_id). Linking mirrors signing in, under
`/api/v1/me` and with the player's bearer token:

| Sign in (`/api/v1/auth`) | Link (`/api/v1/me/providers`) |
| --- | --- |
| `POST /{provider}/callback` `{code}` | `POST /{provider}` `{code}` |
| `POST /google/id_token` `{id_token}` | `POST /google/id_token` `{id_token}` |
| `POST /apple/ios/callback` `{code}` | `POST /apple/ios` `{code}` |
| `GET /{provider}`, then poll `GET /session/{id}` | `POST /{provider}/authorize`, then poll `GET /sessions/{id}` |

A link answers the whole current user, whose `linked_providers` shows the new
one, and pushes `user_updated` on the user channel. A provider account that
already belongs to another player is `409 provider_already_linked`; a polled
link ends with that code in `error`. `DELETE /api/v1/me/providers/{provider}`
unlinks, refusing the last provider (`last_auth_method`); `POST` and
`DELETE /api/v1/me/device` do the same for the device id.

## Captcha

Optional human verification on the browser sign-up forms, using
[Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/). Off by
default.

It guards the two paths that send an email to an address the submitter chose:
**registration** and the **magic link**. Those are the spam-relay vector: an
attacker who cannot read the inbox can still make the server mail anyone, at
your domain's reputation.

Password login is deliberately **not** guarded. A captcha on every routine
sign-in is friction for returning players, and the credentials are their own
proof. Both forms already carry a per-IP rate limit; the captcha adds cover
against distributed abuse, where a botnet stays under the per-IP limit by
spreading itself across thousands of addresses.

**Game clients are unaffected by default.** The captcha guards the browser
forms only; `POST /api/v1/register` and device login take none, so turning it
on cannot break a shipped Godot or JS client. The API sign-up has the auth rate
limit. To guard it too, set `GAMEND_CAPTCHA_API_REGISTER=true`: the client
then sends a Turnstile token as `captcha_token` (from a web export or a
webview), and is answered `403 captcha_required` / `captcha_invalid` without
one. A client that cannot render the widget can then no longer register.

For a public server that takes email sign-ups from game clients, turn it on
if your clients can show the widget. The per-IP limit is 10 sign-ups a
minute, and IPv6 clients count per /64 network, but a botnet brings its own
addresses. Every sign-up it makes queues an email to an address it chose,
and bounces from made-up addresses cost your domain its reputation. Clients
that cannot show the widget can sign players in with device login, which
sends no email, and add an email later.

### Setup

Create a widget at
[dash.cloudflare.com](https://dash.cloudflare.com/?to=/:account/turnstile)
(free, no request cap, no card) and set:

```bash
GAMEND_CAPTCHA_ENABLED=true
GAMEND_CAPTCHA_SITE_KEY=0x4AAA...
GAMEND_CAPTCHA_SECRET_KEY=0x4AAA...
```

Development and test need none of it: with the keys unset the server falls back
to Cloudflare's published dummy pair, which passes on any host including
localhost. That keeps the widget on the page in development, so a form that only
breaks with a captcha in front of it breaks on your machine rather than in
production. To exercise the failure path, set `GAMEND_CAPTCHA_SECRET_KEY` to the
always-fails dummy `2x0000000000000000000000000000000AA`.

### Behaviour

- **Verification fails closed.** If Cloudflare cannot be reached, the submission
  is rejected rather than allowed through. Treating an unreachable verifier as a
  pass would let anyone able to sit between the server and Cloudflare switch the
  protection off, which is exactly the attacker.
- **Tokens are single-use** and expire after five minutes. A rejected submission
  resets the widget automatically, so the player can retry without reloading.
- **The Content-Security-Policy widens only while the captcha is enabled**, and
  only by naming `challenges.cloudflare.com` in `script-src` and `frame-src`. A
  deployment that never turns it on keeps the strict policy untouched.

Self-hosting behind a proxy that blocks Cloudflare, or deploying somewhere
Turnstile is unreachable, means leaving this off and relying on the rate limits.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Accounts`](https://docs.gamend.org/Gamend.Accounts.html) - the functions a plugin calls, with their
  signatures and docs.
