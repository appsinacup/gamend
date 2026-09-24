# `Gamend.Captcha`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/captcha.ex#L1)

Human verification for the unauthenticated browser forms, via
[Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/).

Off by default. It guards the two paths that mail an address the submitter
chose — registration and the magic link — where the abuse is not "too many
requests from one IP" (the rate limiter in `GamendWeb.LiveHelpers`
already answers that) but a botnet spending our mail reputation an address
at a time. Password login is deliberately *not* guarded: a captcha on every
routine sign-in is friction for returning players, and the credentials are
their own proof.

`POST /api/v1/register` mails an address too, but a game client often has no
browser to render the widget in, so turning the forms' captcha on leaves it
alone. `api_register` puts it in front of the endpoint as well: the client
then sends a Turnstile token as `captcha_token`, from a web export or a
webview. Device login is never guarded.

## Setup

Create a widget at <https://dash.cloudflare.com/?to=/:account/turnstile> —
it is free with no request cap and no card — then set:

    GAMEND_CAPTCHA_ENABLED=true
    GAMEND_CAPTCHA_SITE_KEY=0x4AAA...
    GAMEND_CAPTCHA_SECRET_KEY=0x4AAA...

Dev and test need none of that: with the keys unset we fall back to
Cloudflare's published dummy pair, which passes on any host including
localhost. That keeps the widget on the page in development, so a form that
only breaks once a captcha is in front of it breaks on the developer's
machine rather than in production. To exercise the failure path, set
`GAMEND_CAPTCHA_SECRET_KEY` to the always-fails dummy,
`2x0000000000000000000000000000000AA`.

# `error`

```elixir
@type error() :: :missing | :invalid | :unavailable
```

Why a token was rejected. `:missing` never reached Cloudflare.

# `api_register?`

```elixir
@spec api_register?() :: boolean()
```

Whether `POST /api/v1/register` requires a captcha token too.

# `enabled?`

```elixir
@spec enabled?() :: boolean()
```

Whether the register and magic-link forms require a captcha.

# `script_origin`

```elixir
@spec script_origin() :: String.t()
```

The host the widget script is served from, for the browser CSP.

# `site_key`

```elixir
@spec site_key() :: String.t()
```

The sitekey to render, falling back to the always-passes dummy.

# `verify`

```elixir
@spec verify(term(), String.t() | nil) :: :ok | {:error, error()}
```

Verifies a widget token with Cloudflare.

Returns `:ok` when the token is good, `{:error, reason}` otherwise. When
the captcha is disabled this is `:ok` without a network call, so callers can
gate unconditionally rather than branching on `enabled?/0` themselves.

`remote_ip` is passed through to Cloudflare when known; `"unknown"` (what
`GamendWeb.LiveHelpers.client_ip/2` returns with no known address) is
omitted rather than sent as a literal.

A token is single-use and expires after five minutes, so a rejected
submission needs a fresh one — the caller resets the widget.

# `verify_api_register`

```elixir
@spec verify_api_register(term(), String.t() | nil) :: :ok | {:error, error()}
```

`verify/2` for `POST /api/v1/register`: `:ok` without a call unless
`api_register?/0`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
