---
icon: hero-key
---

# Personal API tokens

An access token from `POST /api/v1/login` lasts fifteen minutes and needs a
password. That suits a game client, not a script that runs unattended, and an
account made with a social login has no password at all. A **personal API
token** is made once on the settings page and lasts until it expires or is
revoked.

## Make one

Settings → **API tokens**: give it a name and a lifetime (30, 90 or 365 days,
or never), then **Create token**. With `GAMEND_AUTH_API_TOKEN_MAX_DAYS` set,
the lifetimes stop at that many days and "never" is gone; the cap also ends
tokens made before it, that many days after their creation. The token is shown once:

```text
gamend_pat_Qm9x…
```

Copy it into the secret store of whatever will use it. Gamend keeps only a
SHA-256 of it, so it cannot be shown again; the list shows its first
characters so you can tell which secret holds which token.

## Use it

Anywhere an access token works, as a Bearer token:

```sh
curl https://your-server/api/v1/me \
  -H "authorization: Bearer gamend_pat_Qm9x…"
```

It acts as you, on every API route an access token reaches. It does not work
on the realtime socket, and it cannot create another token: tokens are made on
the settings page only, so a leaked one cannot mint its replacements.

## When it stops working

- It reaches its expiry, or you press **Revoke**. The next request is a 401
  with `"error": "invalid_token"`.
- You change your password or email, or sign out everywhere. Each of those
  revokes every token made before it, for the same reason it ends every
  session: if someone else had your account, their token should not outlive
  the reset that locks them out.
- The account is deactivated.

Tokens that can never work again are deleted by retention
(`dead_api_tokens`).

## Limits

`GAMEND_LIMITS_MAX_API_TOKENS_PER_USER` (default 10) caps how many one account
may hold. Revoke one to make room.
