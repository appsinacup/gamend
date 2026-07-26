# Discord notifications

Goal: one env var and your server talks to your Discord. Retried, rate-limit
aware, redacted by construction, and usable by plugins for their own messages.

This is deliberately **narrower** than
[webhooks-remote-config.md](webhooks-remote-config.md): no signing, no
per-subscription endpoints, no delivery-attempt table, no customer-facing
integration surface. One well-behaved sink for the one place every small game
studio already watches.

## Why this and not the general webhook system

The general spec is right and stays on the roadmap; it is also the larger build
(subscriptions, HMAC signing, per-endpoint retry state, an admin CRUD, a replay
tool). Discord is the concrete 80 % of what it would first be used for, at a
fraction of the size, and it is already being built badly downstream:
polyglot's `discord.ex` is 269 hand-rolled lines of `Req` + `Task.start` — and
its own security review found it **leaking user email addresses** into a chat
channel. That is the argument in one line: an ad-hoc notifier written per game
will get the redaction wrong.

Nothing here blocks the general system later — a `Discord` sink becomes one
delivery adapter under it.

## Configuration

One settings provider; every env name derives from the declaration:

```elixir
defmodule GameServer.Discord do
  use GameServer.Settings.Provider, app: :game_server_core, group: :discord

  setting :webhook_url, :string, secret: true,
    doc: "Channel webhook URL. Unset leaves the whole feature inert."
  setting :username, :string, default: "Gamend"
  setting :events, :list, default: [], doc: "Allow-list; empty means the defaults below."
  setting :min_level, :atom, default: :info, doc: "info | warning | error"
end
```

→ `GAMEND_DISCORD_WEBHOOK_URL` (masked everywhere it is displayed),
`GAMEND_DISCORD_USERNAME`, `GAMEND_DISCORD_EVENTS`, `GAMEND_DISCORD_MIN_LEVEL`.

This is also the shape [issue #29](https://github.com/appsinacup/game_server/issues/29)
asked for, and the settings system that shipped in July 2026 already delivers
it: the URL is `secret: true` and belongs in the environment, while the event
list, username and level are ordinary configuration a host can set in
`config/` and never touch an env var —

```elixir
config :game_server_core, GameServer.Discord, events: ["payment_succeeded", "plugin_crashed"]
```

## What core sends

Opt-in, off by default except the operational ones, each a one-line
`Discord.Event` definition so the admin page can list them:

| Event | Level | Default |
| --- | --- | --- |
| `plugin_crashed`, `job_discarded`, `migration_failed` | error | **on** |
| `payment_succeeded`, `payment_refunded` | info | off |
| `user_reported`, `user_banned`, `ip_banned` | warning | off |
| `leaderboard_top_entry` | info | off |
| `tournament_started`, `tournament_finished` | info | off |
| `quest_completed` | info | off |

Operational alerts default on because a self-hosted server with nobody watching
`journalctl` is the common case, and a crashed plugin is exactly what you want
to hear about. Everything player-facing defaults off.

## Redaction — the part that matters

One rule, enforced in the formatter rather than left to each call site:

> A Discord message may contain a user's **id** and **username**. Never an
> email, never an IP, never a token, never a receipt id, never `metadata`
> verbatim.

Implementation: messages are built from a `%Discord.Message{}` with a fixed
field set, and the only user-shaped input is a `User` struct rendered through a
single `format_user/1` that emits `username (id)`. There is no "pass a map and
we will interpolate it" path, because that is the path polyglot's email leak
came through. A plugin that wants a raw string still cannot smuggle a user in,
because it does not get an interpolation hook into the user rendering.

`Discord.send/2` for plugins takes a title, a body and an optional field list —
all plain strings the plugin already decided to expose, plus optional
`user: %User{}` rendered by core's formatter.

A test asserts that no rendered message for any core event contains `@` in an
email-shaped position or an IP-shaped token, run over a fixture user whose email
and last-known IP are both distinctive.

## Delivery

- One Oban worker on the existing `notifications` queue (no new queue), so
  delivery is durable, retried with backoff, and survives a restart — unlike a
  `Task.start`.
- **Rate limits**: Discord returns `429` with `Retry-After`. The worker honours
  it via `{:snooze, seconds}` rather than burning attempts. Discord's ~30
  messages/minute per webhook is also respected proactively with a token-bucket
  check (`Hammer`, already a dependency) so a chatty event storm queues instead
  of getting the webhook disabled.
- **Batching**: events of the same type within a short window (default 10 s)
  coalesce into one message with a count — a hundred `job_discarded` in a
  deploy gone wrong is one message, not a hundred.
- **Failure is never fatal.** Delivery errors log and discard after
  `max_attempts`; nothing in a request path waits on Discord, and no game logic
  depends on it. A hook that raises inside a Discord formatter kills only the
  job.
- **Payload**: a Discord embed (title, description, colour by level, timestamp,
  fields), since a bare content string cannot be scanned at a glance.

## Admin

A card on `/admin/config`: configured or not, allow-listed events, last delivery
time, last error, count delivered/failed in 24 h, and a **Send test message**
action (API parity). The test message is how a user verifies the URL without
waiting for a real event, and it is the single most-used button on a feature
like this.

## Plugin API

```elixir
Discord.send("Boss defeated", "First clear on Hard", user: user, level: :info)
Discord.send_event("quest_completed", %{quest: "…", user: user})
```

Both enqueue; neither blocks; both are RPC-blocked (a client cannot make the
server post to your Discord). `Discord.configured?/0` lets a plugin skip
building a message that would be dropped.

## Alternatives considered

- **Build the general webhook system instead.** Still the right end state; this
  is the cheap slice that removes the leaky per-game implementations now. When
  the general system lands, this becomes an adapter and the env vars keep
  working.
- **Slack too, behind one behaviour.** Tempting and nearly free — but the embed
  shape, rate-limit semantics and error codes differ enough that "one
  behaviour" quickly becomes two implementations with a shared name. Add Slack
  when someone asks; the formatter split is the only prep needed.
- **Let plugins keep doing it.** That is the status quo, and the status quo
  leaked emails.
- **Fire-and-forget `Task.start`** rather than Oban. Loses messages on restart,
  cannot back off on `429`, and has no visibility. Oban is already there.

## Definition of done (CONTRIBUTING)

- [ ] `GameServer.Discord` + `Discord.Worker` on the `notifications` queue; no
      new table, no new queue.
- [ ] Inert with `GAMEND_DISCORD_WEBHOOK_URL` unset — no jobs enqueued, no
      warnings.
- [ ] Event allow-list honoured; operational events default on, player events
      default off.
- [ ] Redaction: single `format_user/1` path; no interpolation hook for raw
      maps; test asserts no email/IP appears in any core event rendering.
- [ ] `429` honoured with `{:snooze, retry_after}`; proactive token bucket;
      same-type coalescing window.
- [ ] `Discord.send/2` and `send_event/2` are RPC-blocked and SDK-mirrored;
      `configured?/0` exposed.
- [ ] Admin card with status, last error, 24 h counts and a working test-send;
      API parity; `admin_pages_render_test`.
- [ ] Settings declared with `GameServer.Settings.Provider` (group `:discord`,
      URL `secret: true`), rendered on the admin Settings page; `.env.example`
      regenerated with `mix gamend.settings.env_example`; docs page section;
      `api_spec.ex`; CHANGELOG; i18n.
- [ ] Tests: allow-list filtering, coalescing, `429` snooze, redaction, and a
      booted end-to-end send against a stub endpoint.
- [ ] Polyglot's `discord.ex` deletes its transport and calls core (tracked in
      that repo).
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin warning-free.
