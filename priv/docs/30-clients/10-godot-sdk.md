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

## Authentication

The SDK captures tokens for you: after any login or OAuth call it stores the
access and refresh tokens, calls `authorize()` itself, and schedules a refresh
before expiry. You never pass a token to a later call.

```gdscript
func do_discord_auth() -> void:
	var response = await gamend_api.authenticate_oauth_request(
		GamendApi.PROVIDER_DISCORD
	).finished
	print_error_or_result(response)

	var authorization_url: String = response.response.data.authorization_url
	var session_id: String = response.response.data.session_id

	OS.shell_open(authorization_url)

	# Poll until the browser half of the flow completes.
	for i in 60:
		response = await gamend_api.authenticate_oauth_session_status(session_id).finished
		if response.response.data.status == "completed":
			break
		await get_tree().create_timer(1.0).timeout
```

Once that returns, authenticated calls just work:

```gdscript
func _ready() -> void:
	await do_discord_auth()

	var me = await gamend_api.users_get_current_user().finished
	print_error_or_result(me)

	var call_hook := CallHookRequest.new()
	call_hook.plugin = "polyglot_hook"
	call_hook.fn = "hello"
	call_hook.args = ["1"]
	print_error_or_result(await gamend_api.hooks_call_hook(call_hook).finished)
```

## Realtime

`GamendRealtime` wraps the Phoenix socket and takes its token from the same
API instance, so it reconnects with a refreshed token automatically. Topics,
events and payloads are in the Realtime guide.
