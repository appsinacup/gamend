class_name GamendAuth
extends Node
## Game-agnostic authentication flows on top of GamendApi: session restore,
## device login (with a persistent web device id), the browser OAuth flow for
## any provider, Apple native sign-in, Discord embedded sign-in, and the
## post-login session save (token persist + realtime start + first profile).
##
## Owned by GamendClient (client.auth). Every method returns "" on success or
## an "Error: ..." string — no popups, no toasts; the game decides how errors
## surface. Platform integrations are dynamic: Apple uses ClassDB (present only
## when the iOS/macOS extension ships), Discord is an injected node — the SDK
## never hard-depends on either.
##
## The refresh token and web device id persist to a ConfigFile at
## auth_store_path by default — no configuration needed. A game with its own
## settings system (or a keychain) overrides secret_get/secret_set instead.

## "initial" | "online" | "offline"
signal state_changed(state: String)

## Seconds a native provider dialog (Apple) may take before failing.
var provider_timeout_sec := 60.0
## Seconds to wait for the first current-user profile push after login.
var user_update_timeout_sec := 10.0
## localStorage key for the persistent web device id.
var web_device_id_storage_key := "gamend_device_id"
## Override the id `device_auth()` logs in with. Empty means the real device.
##
## The device id is hardware-derived (`OS.get_unique_id()`), so every guest
## login from one machine lands in the SAME server-side account. Automated runs
## set a fresh id per run to get a genuinely new guest.
##
## Test seam only. Production leaves it empty and gets the real device.
var device_id_override := ""
## Default persistent storage for the refresh token / web device id.
var auth_store_path := "user://gamend_auth.cfg"
## Optional storage overrides — set BOTH to use your own settings system or a
## keychain: secret_get(key: String) -> String, secret_set(key, value) -> void.
var secret_get: Callable = Callable()
var secret_set: Callable = Callable()
## Injected Discord SDK node (embedded builds); untyped on purpose.
var discord_sdk = null
## Invoked at save_session start, after authentication but before realtime
## begins delivering events — the game seeds whatever state its event
## handlers write into (user tables, social caches).
var before_session_save: Callable = Callable()

## Full name captured from the last Apple credential ("" when none) — Apple
## sends it exactly once, so the game reads it after apple_native_auth to
## apply its own display-name policy.
var last_apple_full_name := ""
## The parts of that name, sent to the server with the code so the account is
## created with it (the name is not in Apple's token).
var _apple_given_name := ""
var _apple_family_name := ""

var _api: GamendApi
var _state := "initial"
var _apple_sign_in = null
var _apple_web = null
var _apple_login_result := ""
var _apple_login_error := ""
var _apple_auth_revision := 0
var _current_user_seen_revision := 0


func setup(api: GamendApi) -> void:
	_api = api
	_api.user_updated.connect(_on_api_user_updated)
	if DisplayServer.get_name() != "headless" and ClassDB.class_exists("ASAuthorizationController"):
		_apple_sign_in = ClassDB.instantiate("ASAuthorizationController")
		_apple_sign_in.authorization_completed.connect(_on_apple_authorization_completed)
		_apple_sign_in.authorization_failed.connect(_on_apple_authorization_failed)
		_apple_web = ClassDB.instantiate("ASWebAuthenticationSession")


func _exit_tree() -> void:
	if _apple_web:
		_apple_web.cancel()
		_apple_web = null
	if _apple_sign_in:
		_apple_sign_in.authorization_completed.disconnect(_on_apple_authorization_completed)
		_apple_sign_in.authorization_failed.disconnect(_on_apple_authorization_failed)
		_apple_sign_in = null


func state() -> String:
	return _state


func is_online() -> bool:
	return _state == "online"


func is_offline() -> bool:
	return _state == "offline"


func go_offline() -> void:
	_set_state("offline")


## Back to the logged-out state (logout, forced session reset).
func reset() -> void:
	_set_state("initial")


## Try to resume the previous session from the stored refresh token (on web,
## the token the site's own session left in localStorage). Returns "" when
## there was nothing to restore or the restore worked; an error string only on
## a real failure (a 401 just means the session is gone — not an error).
func restore_session() -> String:
	var refresh_token := _secret("refresh_token")
	if OS.get_name() == "Web":
		refresh_token = str(JavaScriptBridge.eval("localStorage.getItem('gamend_refresh_token') || ''"))
	if refresh_token.is_empty():
		return ""
	var response = await _api.authenticate_refresh_token(refresh_token)
	if response.error and response.error.response_code != 401:
		return "Error: " + str(response.error.message)
	return ""


## Log in with this device's stable id (web: a generated id persisted to both
## the injected store and localStorage, so clearing one still finds the other).
func device_auth() -> String:
	var unique_id := _device_id()
	var response = await _api.authenticate_device_login(unique_id)
	if response.error:
		return "Error: " + str(response.error.message)
	return await save_session()


## This device's login id: `device_id_override` when one is set, otherwise the
## real device (web keeps a generated id in both stores; native uses the OS id).
func _device_id() -> String:
	if not device_id_override.is_empty():
		return device_id_override
	return _get_or_create_web_device_id() if OS.get_name() == "Web" else OS.get_unique_id()


## Browser OAuth for any provider (GamendApi.PROVIDER_*): request the URL,
## open it (web popup / Apple web session / system browser), poll the session
## until the site completes it, then save the session. Always a sign-in, even
## when a player is signed in already; provider_link adds a provider instead.
func provider_auth(provider: String) -> String:
	var error := await _provider_page(
		func() -> GamendResult: return await _api.authenticate_oauth_request(provider),
		func(session_id: String) -> GamendResult: return await _api.authenticate_oauth_session_status(session_id)
	)
	if not error.is_empty():
		return error
	return await save_session()


## Link a provider to the signed-in account through its page, as provider_auth
## signs in through it. The session does not change; the user channel's
## user_updated carries the new linked_providers.
func provider_link(provider: String) -> String:
	return await _provider_page(
		func() -> GamendResult: return await _api.authenticate_link_provider_request(provider),
		func(session_id: String) -> GamendResult: return await _api.authenticate_link_session_status(session_id)
	)


## Open the page `start` answers and poll `status` until the player is done
## there. "" once it completed, else the error to show.
func _provider_page(start: Callable, status: Callable) -> String:
	# On web, pre-open a blank popup BEFORE the async call. Browsers block
	# window.open() if called after an await (the user gesture has expired).
	var auth_popup: JavaScriptObject = null
	if OS.has_feature("web") and not _apple_web:
		auth_popup = JavaScriptBridge.eval("window.open('about:blank', '_blank')", true)
	var response: GamendResult = await start.call()
	if response.error:
		if auth_popup:
			auth_popup.close()
		return "Error: " + str(response.error.message)
	var result: GamendOAuthAuthorization = response.response.data.data
	var session_id = result.session_id
	var open_error = null
	if _apple_web:
		_apple_web.start(result.authorization_url, "", false)
	elif auth_popup:
		auth_popup.location.href = result.authorization_url
	else:
		open_error = OS.shell_open(result.authorization_url)
	if open_error:
		return "Error: Cannot open url to login. " + str(open_error)
	for i in 30:
		response = await status.call(session_id)
		if response.response:
			# GamendOAuthSessionStatus or GamendProviderLinkStatus: both say
			# status, error and message.
			var state = response.response.data.data
			if state.status == "completed":
				_cancel_apple_web()
				return ""
			if state.status != "pending":
				_cancel_apple_web()
				return "Error: " + str(state.message if state.message else state.error)
		await get_tree().create_timer(2.0).timeout
	_cancel_apple_web()
	if auth_popup:
		auth_popup.close()
	if response.error:
		return "Error: " + str(response.error)
	return "Error: Timeout"


## Native Apple sign-in (iOS/macOS extension). No-op success on platforms
## without the extension. The captured name lands in last_apple_full_name.
func apple_native_auth() -> String:
	var got: Array = await _apple_native_code()
	if got[1] or got[0].is_empty():
		return got[1]
	var request = GamendOauthCallbackApiAppleIosRequest.new()
	request.code = got[0]
	request.given_name = _apple_given_name
	request.family_name = _apple_family_name
	var response = await _api.authenticate_oauth_callback_api_apple_ios(request)
	if response.error:
		return str(response.error.message)
	return await save_session()


## Link Apple to the signed-in account with the native flow.
func apple_native_link() -> String:
	var got: Array = await _apple_native_code()
	if got[1] or got[0].is_empty():
		return got[1]
	var response = await _api.authenticate_link_apple_ios(got[0], _apple_given_name, _apple_family_name)
	if response.error:
		return "Error: " + str(response.error.message)
	return ""


## [code, error] from the native Apple sheet: ["", ""] where there is no
## extension, as a no-op success.
func _apple_native_code() -> Array:
	_apple_login_result = ""
	_apple_login_error = ""
	last_apple_full_name = ""
	_apple_given_name = ""
	_apple_family_name = ""
	if not ClassDB.class_exists("ASAuthorizationController"):
		return ["", ""]
	_apple_sign_in.signin_with_scopes(["full_name", "email"])
	if not await _wait_for_apple_auth_or_timeout(provider_timeout_sec):
		return ["", "Error: Apple Authorization timed out"]
	if _apple_login_error:
		return ["", _apple_login_error]
	return [_apple_login_result, ""]


## Native Discord sign-in for embedded builds, via the injected discord_sdk.
func discord_native_auth() -> String:
	var code := await _discord_native_code()
	if code.begins_with("Error"):
		return code
	var request = GamendOauthApiCallbackRequest.new()
	request.code = code
	var response = await _api.authenticate_oauth_api_callback(GamendApi.PROVIDER_DISCORD, request)
	if response.error:
		return "Error: " + str(response.error.message)
	return await save_session()


## Link Discord to the signed-in account with the embedded Discord SDK.
func discord_native_link() -> String:
	var code := await _discord_native_code()
	if code.begins_with("Error"):
		return code
	var response = await _api.authenticate_link_provider(GamendApi.PROVIDER_DISCORD, code)
	if response.error:
		return "Error: " + str(response.error.message)
	return ""


func _discord_native_code() -> String:
	if discord_sdk == null:
		return "Error: No Discord SDK configured"
	var auth = await discord_sdk.command_authorize("code", ["identify"], "")
	if str(auth.get("code", "")).is_empty():
		return "Error: Discord login failed"
	return str(auth["code"])


## Post-login: persist the refresh token, start realtime, join the user
## channel, and wait for the first current-user profile push — only then is
## the session "online". The game hooks its own side effects (seed caches,
## post-login fetches) around this via its wrapper.
func save_session() -> String:
	if _api._refresh_token:
		_set_secret("refresh_token", _api._refresh_token)
	if _api._user_id == "":
		return "Error: No user id after authentication"
	if before_session_save.is_valid():
		before_session_save.call()
	var realtime_result = await _api.realtime_start()
	if realtime_result.error:
		return "Error: " + str(realtime_result.error.message)
	_api.listen_to_user()
	if not await _wait_for_current_user_update_or_timeout(user_update_timeout_sec):
		_api.realtime_stop()
		return "Error: Could not load user profile. Please try again."
	_set_state("online")
	return ""


func _set_state(new_state: String) -> void:
	if _state == new_state:
		return
	_state = new_state
	state_changed.emit(_state)


func _on_api_user_updated(user: Dictionary) -> void:
	if str(user.get("id", "")) == _api._user_id and _api._user_id != "":
		_current_user_seen_revision += 1


func _on_apple_authorization_completed(credential: RefCounted) -> void:
	if credential.is_class("ASAuthorizationAppleIDCredential"):
		_apple_login_result = credential.authorization_code.get_string_from_utf8()
		_apple_given_name = str(credential.full_name.get("given_name", "")).strip_edges()
		_apple_family_name = str(credential.full_name.get("family_name", "")).strip_edges()
		last_apple_full_name = (_apple_given_name + " " + _apple_family_name).strip_edges()
		if last_apple_full_name.is_empty():
			last_apple_full_name = str(credential.full_name.get("nickname", "")).strip_edges()
			_apple_given_name = last_apple_full_name
	else:
		_apple_login_error = "Error: Failed to login with Apple. Wrong credential type."
	_apple_auth_revision += 1


func _on_apple_authorization_failed(error: String) -> void:
	_apple_login_error = "Error: Apple Authorization failed: " + error
	_apple_auth_revision += 1


func _cancel_apple_web() -> void:
	if _apple_web:
		_apple_web.cancel()


func _wait_for_apple_auth_or_timeout(timeout_sec: float) -> bool:
	var start_revision := _apple_auth_revision
	var deadline_ms := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while _apple_auth_revision == start_revision and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
	return _apple_auth_revision != start_revision


func _wait_for_current_user_update_or_timeout(timeout_sec: float) -> bool:
	var start_revision := _current_user_seen_revision
	var deadline_ms := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while _current_user_seen_revision == start_revision and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
	return _current_user_seen_revision != start_revision


func _get_or_create_web_device_id() -> String:
	var stored_device_id := _secret("web_device_id")
	if not stored_device_id.is_empty():
		return stored_device_id
	if JavaScriptBridge:
		var js_device_id = JavaScriptBridge.eval(
			(
				"(function(){const k='"
				+ web_device_id_storage_key
				+ "';let v=localStorage.getItem(k);"
				+ "if(!v){v=(self.crypto&&crypto.randomUUID)?crypto.randomUUID()"
				+ ":('w_'+Date.now().toString(36)+Math.random().toString(36).slice(2));"
				+ "localStorage.setItem(k,v);}return v;})()"
			),
			true
		)
		if js_device_id:
			stored_device_id = str(js_device_id)
			_set_secret("web_device_id", stored_device_id)
			return stored_device_id
	stored_device_id = "w_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())
	_set_secret("web_device_id", stored_device_id)
	return stored_device_id


var _auth_store: ConfigFile


func _secret(key: String) -> String:
	var value := ""
	if secret_get.is_valid():
		value = str(secret_get.call(key))
	else:
		value = str(_ensure_auth_store().get_value("auth", key, ""))
	if value == "null" or value == "<null>":
		return ""
	return value


func _set_secret(key: String, value: String) -> void:
	if secret_set.is_valid():
		secret_set.call(key, value)
		return
	var store := _ensure_auth_store()
	store.set_value("auth", key, value)
	store.save(auth_store_path)


func _ensure_auth_store() -> ConfigFile:
	if _auth_store == null:
		_auth_store = ConfigFile.new()
		_auth_store.load(auth_store_path)
	return _auth_store
