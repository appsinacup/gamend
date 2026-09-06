---
icon: hero-document-text
---

# Client Logs & Sessions

Game clients upload batches of log entries over plain HTTP; the server re-emits each line into its own log stream and keeps one `client_sessions` row per run as an index. Client and server lines land in the same place under the same session id, so one search returns both halves of a failure: what the client thought it asked for, and what the server actually did.

## What a client session is

A session is one run of the game. The client generates the id itself (the Godot SDK uses 16 crypto-random bytes, hex-encoded) and never reuses it across runs. Three things carry it:

- `x-gamend-session`: a header on every HTTP request
- `client_session`: a WebSocket connect param
- the uploaded log batches themselves

The durable row records the run (who, which platform and build, which lobbies, how many warnings and errors), not the lines. Those leave through `Logger` to whatever the host already runs: stdout, the rotating file, an aggregator.

Uploading works without authentication, deliberately: the failures most worth capturing happen before a client has a token. An anonymous session is adopted by the user the first time the same run uploads with a bearer token, and from then on the id is owner-bound: a batch for someone else's session is refused with `403`.

## One timeline, not two

Every re-emitted client line carries a logfmt prefix naming its session:

```text
[client] session=0f1e2d3c user=9ab3 level=info cat=game lobby=77c1 screen=boat seq=42 | Game starting
```

`GamendWeb.Plugs.ClientSession` stamps the same id into `Logger` metadata for every server line produced while serving that client: HTTP requests via the header, channels via the connect param. A search for `session=<id>` in your log store (or on `/admin/logs`) returns the client's lines and the server lines written while serving it, interleaved.

## Enabling it

Collection is off by default, and the server decides what is collected: clients fetch a policy at startup (`GET /api/v1/client_logs/policy`) and discard everything below the floor on the device, so unused verbosity costs nothing.

```json
{"enabled": true, "level": "info", "categories": {"perf": "off"},
 "batch_max": 200, "message_max_bytes": 2000}
```

The knobs live in the `client_logs` settings group: `GAMEND_CLIENT_LOGS_ENABLED`, `GAMEND_CLIENT_LOGS_LEVEL`, and per-category overrides in `GAMEND_CLIENT_LOGS_CATEGORY_LEVELS` (`perf:off,network:warn`). See the [Settings](/docs/settings) guide. Changes take effect on each client's next policy fetch, no new build. One interaction worth knowing: client lines re-enter the server's own `Logger` (only client `warn`/`error` map to those levels; everything lower is emitted at `info`), so a host whose `Logger` runs at `:warning` drops client `info` no matter what the policy says. The admin page warns about this rather than showing an empty list.

In Godot, enabling is two lines. The SDK owns the id, the header, the socket param, batching, retry and crash spooling:

```gdscript
gamend_api.start_logs()
DebugLog.log_added.connect(gamend_api.logs.submit)
```

`gamend_api.logs` is a `GamendLogs` node whose `submit(entry)` takes any dictionary with a `message`, plus optional `severity` (0–4, trace to error), `category`, `lobby_id` and `screen`. See the [Godot SDK](/docs/godot-sdk) guide for what each session records about the device.

## Batch upload from any client

The endpoint itself is language-agnostic: `POST /api/v1/client_logs` with a `session` map describing the run and up to 200 `entries`:

```json
{"session": {"client_session_id": "0f1e2d3c...", "platform": "windows",
             "app_version": "1.4.2", "build": "release"},
 "entries": [{"seq": 42, "at": 1756200000.5, "level": "info",
              "category": "game", "message": "Game starting",
              "lobby_id": "", "screen": "boat"}]}
```

- `client_session_id` is required, 8–128 bytes. The rest of the session description is only read when the row is first created, so send it on the first batch and just the id afterwards.
- `seq` is a per-session counter. The server keeps the high-water mark; a gap means entries were lost (ring-buffer overrun, a batch that never arrived) and shows up in the session's `dropped` count. A lossy session that reports itself as lossy is recoverable, one that looks quiet is not.
- `level` is `trace`, `debug`, `info`, `warn` or `error`; `at` is unix seconds by the client's clock, kept as sent.
- Messages are clamped to 2000 bytes, folded onto one line, and unmistakable secrets (JWTs, `token=...` assignments) are redacted on arrival.

Success is `202` with `{"accepted": 12, "dropped": 0, "errors": 1, "client_session_id": "0f1e2d3c..."}`. A `503` means collection is disabled: back off and retry later; `403` means the session belongs to another user; `400` a malformed batch.

## Reading them: Admin → Logs

The **Client sessions** tab of `/admin/logs` lists sessions newest-activity-first, filterable by user, lobby, platform, app version, date range, errors-only, or a text search over session and device ids. Picking a session shows its recent timeline (from the in-memory ring buffer) and hands over the exact `session=` search string to paste into the host's log store for anything older; the lobbies the session was in link to the server's own record of those runs. The **Server** tab has the inverse filters: a client-session and a user filter over the live tail.

A **Flag** button on the session detail exempts it from the ordinary retention window; any session that logged an error is flagged automatically.

## Retention

`GAMEND_CLIENT_LOGS_RETENTION_DAYS` (default 14; `0` keeps forever) deletes sessions after that many days without activity, measured from `last_seen_at`, so a long run does not start expiring the moment it began. Flagged sessions live under the longer `GAMEND_CLIENT_LOGS_RETENTION_FLAGGED_DAYS` (default 90, never shorter than the ordinary window). This prunes the *index*, not the lines: those live in the host's log store on its own retention, so an expired session loses findability here, not the ability to read lines whose id you already have.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - the Client logs endpoints (policy and upload), generated from the spec.
- **Elixir API:** [`Gamend.ClientLogs`](https://docs.gamend.org/Gamend.ClientLogs.html) - ingest, session queries, flagging and the capture policy.
