---
icon: hero-cube
---

# Godot Client SDK

[View on Godot Asset Library](https://godotengine.org/asset-library/asset/4510)

Install from the Asset Library inside Godot - search for **Gamend - Game
Server**. The addon is generated from the OpenAPI spec, so every endpoint has a
method; the [API reference](/api/docs) is the authoritative list.

## Calling the API

Every call returns a `GamendResult` you `await` through its `finished` signal:

```gdscript
var gamend_api := GamendApi.new()

func print_error_or_result(response: GamendResult) -> void:
	if response.error:
		print(response.error)
	else:
		print(response.response)

func _ready() -> void:
	var response: GamendResult = await gamend_api.health_index().finished
	print_error_or_result(response)
```

## Models

`response.response.data` is a generated class named after the API schema,
with a `Gamend` prefix, because GDScript class names are global and your game
may have its own `Lobby`:

| Call | `data` is |
|---|---|
| `lobbies_get_lobby(id)` | `GamendLobbyResponse`: `data`, a `GamendLobby` with its `members` and `spectator_count` |
| `lobbies_list_lobbies()` | `GamendLobbyPage`: `data` (`GamendLobby` rows), `meta` (a `GamendPageMeta`) |
| `users_get_current_user()` | `GamendCurrentUserResponse`: `data`, a `GamendCurrentUser` |
| `authenticate_device_login(id)` | `GamendSessionResponse`: `data`, a `GamendSession` |
| `tournaments_tournament_bracket(id)` | `GamendTournamentBracketPage`: `data` (`GamendTournamentBracket` rows, each with its `matches` and `entries`), `meta` |
| `lobbies_leave_lobby()` | `GamendOkResponse`: `ok` |

Every answer has the same four shapes (see API conventions): the resource
under `data`, a page under `data` with `meta`, `ok` for a write with nothing
to return, or an error.

Request bodies follow the operation: `GamendCreateLobbyRequest`,
`GamendCallHookRequest`. A failed call sets `response.error` instead.

## Authentication

The SDK captures tokens for you: after `authenticate_login`,
`authenticate_device_login`, `authenticate_refresh_token`,
`authenticate_oauth_session_status` (once it answers a `session`),
`authenticate_oauth_api_callback`, `authenticate_oauth_google_id_token`,
`authenticate_oauth_callback_api_apple_ios` or
`authenticate_confirm_registration` it stores the access and refresh
tokens, calls `authorize()` itself, and schedules a refresh before expiry. You
never pass a token to a later call.

`authenticate_register_email(email, username)` is not a sign-in and takes no
password: it answers the new account and keeps no session. The server emails
a link and a six-digit code. Ask the player for the code and a password, then
`authenticate_confirm_registration(email, code, password)` sets the password
and signs in; `authenticate_resend_confirmation(email)` sends a new code.
(`authenticate_register(email, password)` is gone, under a new name so an old
call fails rather than send the password as the username.)

Those always sign in, even when a player is signed in already. To add a
provider to the signed-in account, use the link calls instead:
`authenticate_link_provider`, `authenticate_link_google_id_token`,
`authenticate_link_apple_ios`, or `authenticate_link_provider_request` polled
with `authenticate_link_session_status`. `GamendAuth` wraps both:
`provider_auth` / `provider_link`, `apple_native_auth` / `apple_native_link`,
`discord_native_auth` / `discord_native_link`.

```gdscript
func do_discord_auth() -> void:
	var response = await gamend_api.authenticate_oauth_request(
		GamendApi.PROVIDER_DISCORD
	).finished
	print_error_or_result(response)

	var authorization_url: String = response.response.data.data.authorization_url
	var session_id: String = response.response.data.data.session_id

	OS.shell_open(authorization_url)

	# Poll until the browser half of the flow completes.
	for i in 60:
		response = await gamend_api.authenticate_oauth_session_status(session_id).finished
		if response.response.data.data.status == "completed":
			break
		await get_tree().create_timer(1.0).timeout
```

Once that returns, authenticated calls just work:

```gdscript
func _ready() -> void:
	await do_discord_auth()

	var me = await gamend_api.users_get_current_user().finished
	print_error_or_result(me)

	var call_hook := GamendCallHookRequest.new()
	call_hook.plugin = "my_game_hook"
	call_hook.fn = "hello"
	call_hook.args = ["1"]
	print_error_or_result(await gamend_api.hooks_call_hook(call_hook).finished)
```

## Realtime

`gamend_api.realtime_start()` opens a `GamendWebSocket`, which wraps the
Phoenix socket and takes its token from the same API instance, so it
reconnects with a refreshed token automatically. Set
`gamend_api.realtime_format = "protobuf"` before the call for binary frames.
Topics, events and payloads are in the Realtime guide.

## Client logs

Ship the game's own log lines to the server, where they land in the same stream
as the server's lines. One search for a session id then returns both halves of a
failure (what the client thought it asked for, and what the server did) instead
of two lists to line up by timestamp.

Two lines to enable it:

```gdscript
func _ready() -> void:
	gamend_api.start_logs()
	DebugLog.log_added.connect(gamend_api.logs.submit)
```

`start_logs()` takes the address and bearer token from the same API instance, so
there is nothing to keep in sync. `gamend_api.logs` is a `GamendLogs` node; feed
it any dictionary with `message`, and optionally `severity` (`0`-`4`, low to high),
`category`, `time`, `lobby_id` and `screen`:

```gdscript
gamend_api.logs.submit({"message": "Game starting", "severity": 2, "category": "game"})
```

Wiring it to your own logger instead is the same call: `submit` is what the
signal connects to, nothing about it is specific to `DebugLog`.

### The server decides what is collected

The client fetches a policy at startup and drops everything below it **on the
device**, so verbosity is a server-side decision and an unused level costs
nothing. Set it under `client_logs` in
[settings](/docs/settings):

| setting | default | what it does |
|---|---|---|
| `enabled` | `false` | Master switch. Off means clients send nothing. |
| `level` | `info` | Lowest level uploaded: `trace`, `debug`, `info`, `warn`, `error`. |
| `category_levels` | — | Per-category overrides, `perf:off,network:warn`. `off` drops a category. |
| `retention_days` | `14` | How long a session stays findable. |
| `retention_flagged_days` | `90` | Same, for sessions that logged an error. |

So `info` by default, `debug` for the noisy things (per-frame, per-message)
which upload only when someone asks for them, and a category turned `off`
entirely when it turns out to be chatty. Changing any of these takes effect on
each client's next policy fetch, with no new build.

### Correlating with server logs

`GamendApi` stamps every request with `x-gamend-session` and sends the same id
as the `client_session` socket connect param. It does this from the start, even
before `start_logs()`. The server puts it in its own `Logger` metadata, so
server lines carry it too. Client `error` and `warn` entries are logged at that
`Logger` level; every other client level is logged at `info`:

```text
12:00:01.120 client_session=0f1e2d3c [error] [client] session=0f1e2d3c level=error cat=auth | Refresh failed
12:00:01.180 client_session=0f1e2d3c [info] lobby join rejected: seat taken
```

Grep either your log store or `/admin/logs` for `session=<id>` and both sides
come back interleaved. Entries carrying a `lobby_id` also link the run to the
server's own record of it at `/admin/lobby_snapshots`, from both directions.

### What each session records about the device

Gathered once per run and sent with the first batch. Every field is here
because it answers a question a log line alone cannot: "only on Android 13",
"only on the compatibility renderer", "only in Safari", "only on the 3GB
devices":

| | |
|---|---|
| **System** | `os`, `os_version`, `distribution`, `arch`, `model`, `godot` |
| **Capacity** | `cpu`, `cpu_count`, `ram_mb` |
| **Graphics** | `gpu`, `gpu_vendor`, `gpu_api`, `rendering` (the method actually in use, which can differ from the configured one after a driver fallback) |
| **Display** | `screen`, `window`, `dpi`, `scale`, `refresh_hz` |
| **Web only** | `browser` (user agent), `browser_lang`, `browser_cores`, `heap_peak_mb` |

Alongside the session's own `platform`, `build`, `app_version`, `locale` and
`device_id`. A field that comes back empty is omitted rather than sent blank,
so a missing `gpu` means "not measurable here", not "no GPU".

`heap_peak_mb` is sent only when your web export's HTML shell sets
`window.__heapPeak = {mb: …}`. The SDK does not ship that shell: your custom
template must sample the WASM heap and keep the high-water mark in MB. That peak
is what gets a tab killed on iOS, and it is invisible from anywhere else.

All of these travel in the session's `meta`. The server takes it free-form,
capped at 32 keys and 256 characters per value, but the SDK fills it itself (up
to 22 keys) and `submit` has no `meta` field, so there is no public way to add
keys of your own. Per-line context goes in the entry instead:

```gdscript
gamend_api.logs.submit({"message": "Boss spawned", "category": "game", "screen": "boat", "lobby_id": lobby_id})
```

One thing to weigh before adding more: this set is already close to a device
fingerprint. It sits next to a `device_id` that identifies the install
outright, so the marginal privacy cost is small, but that stops being true if
you add location, contacts, or anything else tied to the person rather than
the hardware. Collect what explains a crash, not what identifies a player.

### Batching and cost

Entries are buffered and sent in batches rather than one request per line:

- flushed every 10s, or at 50 buffered entries, or **immediately on an error**;
  the line most likely to be followed by a crash is the one least worth holding
- at most 200 entries per request, one request in flight at a time
- an immediate repeat is collapsed to `message  (x140)` rather than sent 140
  times, which is the shape that actually fills a log store
- a failed batch goes back in the buffer and retries; a `4xx` is dropped rather
  than retried forever
- pending entries are mirrored to `user://` and uploaded on the next launch, so
  a crash does not take its own explanation with it
- the device description rides on the first batch only; later ones carry just
  the session id, since the server reads it only when creating the row

Gaps in the per-session sequence are reported as `dropped`, so a session that
lost entries says so instead of looking quiet.

### What is stored where

Only one row per session is stored in the database: who, which build, which
lobbies, how many errors. The lines themselves leave through `Logger` to
whatever log store the host runs. That keeps volume off the database and puts
client and server lines in one place; browse sessions at `/admin/logs`.

One thing worth checking if the page looks empty: the server's own `Logger`
level is applied to client entries too, so a host running at `:warning` drops
everything below `warn`. `/admin/logs` says so rather than showing an empty
list.
