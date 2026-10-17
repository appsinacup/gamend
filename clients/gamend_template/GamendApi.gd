## Open source Elixir game server with authentication, users, lobbies, groups, parties, friends, chat, notifications, quests, leaderboards, tournaments, server scripting and an admin portal with HTTP, WebSocket, and WebRTC support and SDK for JS and Godot.
##
## Game + Backend = Gamend
class_name GamendApi
extends Node

signal notification_emitted(notification: Dictionary)
signal user_updated(user: Dictionary)
signal kv_updated(payload: Dictionary)
signal kv_deleted(payload: Dictionary)

## Network request lifecycle (emitted around every HTTP/WS API call).
signal network_request_succeeded()
signal network_request_failed(message: String)

## Lobby realtime events
signal lobby_updated(lobby: Dictionary)
signal lobby_state_changed(payload: Dictionary)  ## {from, to, lobby_id, state_changed_at}
signal lobby_member_joined(payload: Dictionary)   ## {user_id}
signal lobby_member_left(payload: Dictionary)     ## {user_id}
signal lobby_member_kicked(payload: Dictionary)   ## {user_id}
signal lobby_member_online(payload: Dictionary)   ## user came online while in lobby
signal lobby_member_offline(payload: Dictionary)  ## user went offline while in lobby
signal lobby_member_updated(payload: Dictionary)  ## member updated while in lobby
signal lobby_host_changed(payload: Dictionary)    ## {new_host_id}
signal lobby_chat_message(message: Dictionary)         ## chat_message_created
signal lobby_chat_message_updated(message: Dictionary) ## chat_message_updated
signal lobby_chat_message_deleted(payload: Dictionary) ## chat_message_deleted {id}

## Lobbies collection events (lobby browser)
signal lobby_created(lobby: Dictionary)    ## new lobby created
signal lobby_deleted(payload: Dictionary)   ## {id} lobby deleted
signal lobby_list_updated(lobby: Dictionary)    ## existing lobby updated
signal lobby_membership_changed(payload: Dictionary) ## {id} member count changed

## Party realtime events
signal party_updated(party: Dictionary)
signal party_member_joined(payload: Dictionary)   ## {user_id}
signal party_member_left(payload: Dictionary)     ## {user_id}
signal party_member_online(payload: Dictionary)   ## user came online while in party
signal party_member_offline(payload: Dictionary)  ## user went offline while in party
signal party_member_updated(payload: Dictionary)  ## member updated while in party
signal party_disbanded(payload: Dictionary)       ## {party_id}
signal party_invite_accepted(payload: Dictionary)  ## {party_id, user_id} via user channel
signal party_invite_declined(payload: Dictionary)  ## {party_id, user_id} via user channel
signal party_invite_cancelled(payload: Dictionary) ## {party_id, user_id} via user channel

## Ready check realtime events. Fired for both the lobby board and the party
## board — the payload's lobby_id/party_id says which one it is.
signal ready_check_started(check: Dictionary)
signal ready_check_updated(check: Dictionary)
signal ready_check_passed(check: Dictionary)
signal ready_check_failed(check: Dictionary)
signal party_chat_message(message: Dictionary)
signal party_chat_message_updated(message: Dictionary)
signal party_chat_message_deleted(payload: Dictionary)

## Accepted friend initial state and public data diffs
signal friend_updated(payload: Dictionary)
## Friend requests
signal friend_request_outgoing(payload: Dictionary)   ## {id, requester_id, target_id, status}
signal friend_request_incoming(payload: Dictionary)   ## {id, requester_id, target_id, status}
signal friend_added(payload: Dictionary)              ## friend accepted / new friendship created
signal friend_rejected(payload: Dictionary)           ## friend request rejected
signal friend_request_cancelled(payload: Dictionary)  ## sender cancelled a pending request
signal friend_removed(payload: Dictionary)            ## an existing friendship was removed
signal friend_blocked(payload: Dictionary)            ## user blocked
signal friend_unblocked(payload: Dictionary)          ## user unblocked
## Friend DM chat (via user channel)
signal friend_chat_message(message: Dictionary)
signal friend_chat_message_updated(message: Dictionary)
signal friend_chat_message_deleted(payload: Dictionary)

## Group realtime events
signal group_updated(group: Dictionary)
signal group_member_joined(payload: Dictionary)
signal group_member_left(payload: Dictionary)
signal group_member_kicked(payload: Dictionary)
signal group_member_promoted(payload: Dictionary)
signal group_member_demoted(payload: Dictionary)
signal group_member_online(payload: Dictionary)
signal group_member_offline(payload: Dictionary)
signal group_member_updated(payload: Dictionary)
signal group_join_request_approved(payload: Dictionary)  ## A join request was approved (group channel: for admins; user channel: my request)
signal group_join_request_rejected(payload: Dictionary)  ## A join request was rejected (group channel: for admins; user channel: my request)
signal group_invite_accepted(payload: Dictionary)        ## {group_id} via user channel
signal group_invite_cancelled(payload: Dictionary)       ## {group_id, group_name} via user channel
signal group_chat_message(message: Dictionary)
signal group_chat_message_updated(message: Dictionary)
signal group_chat_message_deleted(payload: Dictionary)

## Quest events (achievements are quests of kind "achievement")
signal wallet_updated(change: Dictionary)     ## currency + balance + delta
signal inventory_updated(change: Dictionary)  ## item + quantity + delta
signal quest_progress(progress: Dictionary)   ## a quest objective advanced
signal quest_completed(progress: Dictionary)  ## every objective met — claim or auto-claim next
signal quest_claimed(progress: Dictionary)    ## the quest's rewards were granted

## Groups collection events (group browser)
signal group_created(group: Dictionary)   ## new group created (excludes hidden)
signal group_deleted(payload: Dictionary)  ## {id} group deleted
signal group_list_updated(group: Dictionary)  ## existing group updated (excludes hidden)

## Network latency
signal latency_updated(latency_ms: int)
signal auth_failed()  ## Refresh token expired or 403 — controller should force logout
signal token_refreshed()  ## Access token was refreshed — controller should re-persist
signal debug_message(severity: String, category: String, message: String)
signal socket_connected()   ## WebSocket opened (or re-opened after reconnect)
signal socket_disconnected()  ## WebSocket closed or errored
signal user_channel_joined()  ## User channel joined (or rejoined after reconnect)
signal user_channel_disconnected()  ## User channel closed or errored
signal lobby_channel_join_failed(lobby_id: String, reason: String)

var _config := ApiApiConfigClient.new()
var _realtime: GamendWebSocket
## Realtime payload format: "json" (default) or "protobuf" — with
## "protobuf" the server pushes events as binary frames decoded via
## GamendProto (see register_meta_schema / register_kv_schema for your
## game's own schemas). Set before realtime_start().
var realtime_format := "json"
var _realtime_start_result: GamendResult
var _realtime_start_finished := false
var _realtime_start_revision := 0
var _shutting_down := false
var enable_logs := false
var enable_ssl := false
var TIME_TO_WAIT_RECONNECT = 5000
@export var http_client_pool_size := 4
@export var http_request_timeout_sec := 15.0
@export var http_client_pool_timeout_sec := 5.0

const PROVIDER_DISCORD = "discord"
const PROVIDER_APPLE = "apple"
const PROVIDER_FACEBOOK = "facebook"
const PROVIDER_GITHUB = "github"
const PROVIDER_GOOGLE = "google"
const PROVIDER_STEAM = "steam"
const LOG_REDACTED := "[redacted]"
const SENSITIVE_LOG_KEYS := {
	"access_token": true,
	"authorization": true,
	"cookie": true,
	"password": true,
	"refresh_token": true,
	"set-cookie": true,
	"token": true,
}

var _access_token := ""
var _client_session_id := ""

## Client log upload. Reachable as `gamend_api.logs`; call
## [method start_logs] to begin, then feed it entries with
## `logs.submit`. Created here rather than on demand because its
## session id tags every request this api makes.
var logs := GamendLogs.new()
var _refresh_token := ""
var _expires_at_ms := -1
var _user_id = ""
var _lobby_id = ""
var _party_id = ""

## Ids are UUID strings; absent ids arrive as "" (or null from older payloads).
static func _id_str(value) -> String:
	return "" if value == null else str(value)
var _refreshing_token = false
var _has_reloaded_for_auth := false
var _http_clients: Array = []
var _http_clients_in_flight: Array = []
var _http_client_pool_index := 0
var _refresh_timer: Timer

func _init(host: String = "127.0.0.1", port: int = 4000, enable_ssl := false):
	_config.host = host
	_config.tls_enabled = enable_ssl
	# INFO prints a line per request AND per response. That is a debugging aid, not
	# something a shipped build should be doing on every call — on web those go
	# straight to the browser console.
	_config.log_level = ApiApiConfigClient.LogLevel.INFO if OS.is_debug_build() else ApiApiConfigClient.LogLevel.WARNING
	_config.port = port
	_config.polling_interval_ms = 1
	_config.headers_override["Connection"] = "keep-alive"
	_ensure_http_client_pool()
	logs.name = "GamendLogs"
	add_child.call_deferred(logs)
	set_client_session(logs.session_id)
	_refresh_timer = Timer.new()
	_refresh_timer.one_shot = true
	_refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	add_child.call_deferred(_refresh_timer)

func _ensure_http_client_pool() -> void:
	var desired := max(1, int(http_client_pool_size))
	if _http_clients.size() != desired:
		_http_clients.clear()
		_http_clients_in_flight.clear()
		for i in range(desired):
			_http_clients.append(HTTPClient.new())
			_http_clients_in_flight.append(false)
		_http_client_pool_index = 0

func _acquire_http_client() -> int:
	_ensure_http_client_pool()
	var size := _http_clients.size()
	var wait_start := Time.get_ticks_msec()
	var timeout_ms := int(max(0.1, http_client_pool_timeout_sec) * 1000.0)
	while Time.get_ticks_msec() - wait_start < timeout_ms:
		for offset in range(size):
			var idx := (_http_client_pool_index + offset) % size
			if not _http_clients_in_flight[idx]:
				_http_clients_in_flight[idx] = true
				_http_client_pool_index = (idx + 1) % size
				return idx
		await get_tree().process_frame
	push_warning("GamendApi: HTTP client pool exhausted after %.1fs" % http_client_pool_timeout_sec)
	return -1

func _release_http_client(idx: int) -> void:
	if idx >= 0 and idx < _http_clients_in_flight.size():
		_http_clients_in_flight[idx] = false

func _discard_http_client(idx: int) -> void:
	if idx < 0 or idx >= _http_clients.size():
		return
	_http_clients[idx].close()
	_http_clients[idx] = HTTPClient.new()
	_release_http_client(idx)

func _verify_token_expired():
	# Only one refreshes at a time
	var started_wait = Time.get_ticks_msec()
	while _refreshing_token && Time.get_ticks_msec() - started_wait < TIME_TO_WAIT_RECONNECT:
		await get_tree().create_timer(0.5).timeout
	# If the access token expired, refresh it
	if _refresh_token && Time.get_ticks_msec() > _expires_at_ms:
		_refreshing_token = true
		var result :GamendResult= await authenticate_refresh_token(_refresh_token)
		if result.error:
			debug_message.emit("err", "auth", "Token refresh failed (verify): %s" % _redact_text_for_log(str(result.error)))
			auth_failed.emit()
		else:
			_has_reloaded_for_auth = false
			token_refreshed.emit()
			debug_message.emit("info", "auth", "Token refreshed (verify path)")
		_refreshing_token = false

## Attempt to refresh the token in the background. If refresh fails, emit auth_failed.
func _try_refresh_or_logout() -> void:
	if _refreshing_token or _refresh_token.is_empty():
		return
	_refreshing_token = true
	var refresh_result := await authenticate_refresh_token(_refresh_token)
	_refreshing_token = false
	if refresh_result.error:
		debug_message.emit("err", "auth", "Token refresh failed (background): %s" % _redact_text_for_log(str(refresh_result.error)))
		auth_failed.emit()
	else:
		_has_reloaded_for_auth = false
		token_refreshed.emit()
		debug_message.emit("info", "auth", "Token refreshed (background refresh)")
		_reconnect_socket_if_needed()

func _call_api(api: ApiApiBeeClient, method_name: String, params: Array = []) -> GamendResult:
	# Check if it's close to expiring first, if so make a refresh_call if we already have access token
	var start_request_time = Time.get_ticks_msec()
	if enable_logs:
		print("Requesting: ", api._bzz_name, " ", method_name, " ", _redact_for_log(params))
	if method_name != "refresh_token":
		await _verify_token_expired()
	api._bzz_keep_alive = true
	var client_idx := await _acquire_http_client()
	var result = GamendResult.new()
	if client_idx < 0:
		result.error = _make_api_error(
			"gamend.client_pool.timeout",
			"%s.%s could not acquire an HTTP client after %.1fs" % [api._bzz_name, method_name, http_client_pool_timeout_sec],
			ERR_TIMEOUT
		)
		debug_message.emit("err", "network", result.error.message)
		return result
	api._bzz_client = _http_clients[client_idx]
	var request_state := {"finished": false}
	var finish_timeout := func() -> void:
		if bool(request_state["finished"]):
			return
		request_state["finished"] = true
		_discard_http_client(client_idx)
		result.error = _make_api_error(
			"gamend.request.timeout",
			"%s.%s timed out after %.1fs" % [api._bzz_name, method_name, http_request_timeout_sec],
			ERR_TIMEOUT
		)
		debug_message.emit("err", "network", result.error.message)
		network_request_failed.emit(result.error.message)
		result.finished.emit(result)
	if http_request_timeout_sec > 0.0:
		var timeout_timer := _create_request_timeout_timer(http_request_timeout_sec)
		if timeout_timer:
			timeout_timer.timeout.connect(finish_timeout)
		else:
			push_warning("GamendApi: cannot create timeout timer for %s.%s" % [api._bzz_name, method_name])
	var callables = [
		func(response: ApiApiResponseClient):
			if bool(request_state["finished"]):
				return
			request_state["finished"] = true
			_release_http_client(client_idx)
			result.response = response
			_verify_login_result(method_name, response.data)
			network_request_succeeded.emit()
			if enable_logs:
				print(api._bzz_name, " ", method_name, " ", _format_log_body(response.body), " t: ", (Time.get_ticks_msec() - start_request_time) / 1000.0)
			result.finished.emit(result)
			,
		func(error):
			if bool(request_state["finished"]):
				return
			request_state["finished"] = true
			_release_http_client(client_idx)
			if error.response_code in [401, 403] and method_name != "refresh_token":
				_expires_at_ms = -1
				_try_refresh_or_logout()
			result.error = error
			if error.response_code not in [400, 404]:
				debug_message.emit("err", "network", "API error %s.%s code=%d: %s" % [api._bzz_name, method_name, error.response_code, _redact_text_for_log(str(error))])
			if _is_connectivity_error(error):
				network_request_failed.emit(str(error.message))
			if enable_logs:
				print(api._bzz_name, " ", method_name, " ", _redact_for_log(result.error), " t: ", (Time.get_ticks_msec() - start_request_time) / 1000.0)
			result.finished.emit(result)]
	params.append_array(callables)
	api.callv(method_name, params)
	return await result.finished

func _format_log_body(body: Variant) -> String:
	var safe := _redact_for_log(body)
	var body_str := safe if safe is String else JSON.stringify(safe)
	return body_str if body_str.length() <= 256 else body_str.left(256) + "... (%d chars truncated)" % (body_str.length() - 256)

func _redact_for_log(value: Variant, depth: int = 0) -> Variant:
	if depth > 8:
		return "<max-depth>"
	match typeof(value):
		TYPE_DICTIONARY:
			var redacted := {}
			for key in value:
				if _is_sensitive_log_key(str(key)):
					redacted[key] = LOG_REDACTED
				else:
					redacted[key] = _redact_for_log(value[key], depth + 1)
			return redacted
		TYPE_ARRAY:
			var redacted_array := []
			for item in value:
				redacted_array.append(_redact_for_log(item, depth + 1))
			return redacted_array
		TYPE_OBJECT:
			if value == null:
				return null
			if value.has_method("bzz_normalize"):
				return _redact_for_log(value.bzz_normalize(), depth + 1)
			return _redact_text_for_log(str(value))
		TYPE_STRING:
			return _redact_text_for_log(value)
		_:
			return value

func _redact_text_for_log(text: String) -> String:
	var stripped := text.strip_edges()
	if stripped.begins_with("{") or stripped.begins_with("["):
		var parsed := JSON.parse_string(stripped)
		if parsed != null:
			return JSON.stringify(_redact_for_log(parsed, 1))
	if stripped.begins_with("Bearer "):
		return "Bearer " + LOG_REDACTED
	return text

func _is_sensitive_log_key(key: String) -> bool:
	var normalized := key.to_lower()
	if SENSITIVE_LOG_KEYS.has(normalized):
		return true
	return normalized.ends_with("_token") or normalized.contains("password")

func _make_api_error(identifier: String, message: String, internal_code: int) -> ApiApiErrorClient:
	var error := ApiApiErrorClient.new()
	error.identifier = identifier
	error.message = message
	error.internal_code = internal_code
	error.response_code = 0
	return error

func _make_ws_api_error(identifier: String, payload: Dictionary, internal_code: int) -> ApiApiErrorClient:
	var error_name := str(payload.get("error", "websocket_error"))
	var message := str(payload.get("message", error_name))
	var error := _make_api_error(identifier, message, internal_code)
	error.response_code = _websocket_error_response_code(error_name)
	var response := ApiApiResponseClient.new()
	response.code = error.response_code
	response.body = JSON.stringify(payload)
	response.data = payload
	error.response = response
	return error

func _websocket_error_response_code(error_name: String) -> int:
	match error_name:
		"invalid_key":
			return HTTPClient.RESPONSE_BAD_REQUEST
		"forbidden":
			return HTTPClient.RESPONSE_FORBIDDEN
		"not_found":
			return HTTPClient.RESPONSE_NOT_FOUND
		_:
			return 0

func _is_connectivity_error(error) -> bool:
	return int(error.response_code) == 0 or int(error.internal_code) == ERR_TIMEOUT

func _create_request_timeout_timer(timeout_sec: float) -> SceneTreeTimer:
	var tree := get_tree()
	if tree == null and Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop()
	if tree == null:
		return null
	return tree.create_timer(timeout_sec)

func is_authenticated():
	return _access_token != ""

func _notification(what: int) -> void:
	if _shutting_down:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# Refresh the token on focus-in if it is expired or near expiry,
		# then reconnect the socket. If the token is still valid, reconnect
		# the socket immediately.
		if not _refresh_token.is_empty() and _expires_at_ms > 0:
			var remaining_ms := _expires_at_ms - Time.get_ticks_msec()
			if remaining_ms < 60_000:
				# Token expired or about to — refresh first, then reconnect.
				# _try_refresh_or_logout emits token_refreshed which triggers
				# _reconnect_socket_if_needed.
				_try_refresh_or_logout()
				return
		# Token is still valid — reconnect immediately.
		_reconnect_socket_if_needed()

func _exit_tree() -> void:
	_shutting_down = true
	realtime_stop()
	if _refresh_timer != null:
		_refresh_timer.stop()
	for client: HTTPClient in _http_clients:
		client.close()
	_http_clients.clear()
	_http_clients_in_flight.clear()

func _on_refresh_timer_timeout() -> void:
	_try_refresh_or_logout()

func _refresh_token_if_expired() -> void:
	if not _refresh_token.is_empty() and _expires_at_ms > 0:
		var remaining_ms := _expires_at_ms - Time.get_ticks_msec()
		if remaining_ms < 60_000:
			_try_refresh_or_logout()

func _reconnect_socket_if_needed() -> void:
	if _realtime and _realtime.socket:
		if not _realtime.socket.is_connected and not _realtime.socket.is_connecting:
			# Reset reconnect backoff so the attempt happens immediately.
			_realtime.socket._last_reconnect_try_at = -1
			_realtime.socket._reconnect_after_pos = 0
			_realtime.socket.connect_socket()

func _schedule_token_refresh() -> void:
	if not _refresh_timer or not _refresh_timer.is_inside_tree():
		return
	_refresh_timer.stop()
	if _expires_at_ms > 0:
		var remaining_s := (_expires_at_ms - Time.get_ticks_msec()) / 1000.0
		var refresh_in_s := remaining_s * 0.75  # Refresh at 75% of remaining time
		if refresh_in_s > 1.0:
			_refresh_timer.wait_time = refresh_in_s
			_refresh_timer.start()

func _verify_login_result(method_name: String, data):
	# Not "register": registering answers the new account, never a session.
	# Its code does ("confirm_registration").
	if data && method_name in ["oauth_session_status", "oauth_api_callback", "login", "device_login", "refresh_token", "oauth_callback_api_apple_ios", "oauth_google_id_token", "confirm_registration"]:
		# Every answer is {data: ...}; a polled OAuth sign-in carries its tokens
		# one level further in, under data.session (null until it completes).
		var inner = data.bzz_normalize().get("data")
		if method_name == "oauth_session_status" and inner != null:
			inner = inner.bzz_normalize().get("session")
		if inner == null:
			return
		data = inner.bzz_normalize() if inner is Object else inner
		if data.get("access_token"):
			_access_token = data["access_token"]
		if data.get("refresh_token"):
			_refresh_token = data["refresh_token"]
		if data.get("expires_in"):
			_expires_at_ms = Time.get_ticks_msec() + data.get("expires_in") * 1000
			_schedule_token_refresh()
		if data.get("user_id"):
			_user_id = data["user_id"]
		authorize()
	if method_name == "logout":
		_access_token = ""
		_refresh_token = ""
		_user_id = ""
		authorize()

func realtime_start():
	realtime_stop()
	_realtime_start_revision += 1
	_realtime_start_result = GamendResult.new()
	_realtime_start_finished = false
	var protocol = "ws://"
	if _config.tls_enabled:
		protocol = "wss://"
	_realtime = GamendWebSocket.new(_get_realtime_access_token, protocol + _config.host + ":" + str(_config.port) + "/socket", realtime_format)
	_realtime.client_session_id = _client_session_id
	_realtime.enable_logs = enable_logs
	_realtime.socket_opened.connect(_on_realtime_socket_opened)
	_realtime.socket_closed.connect(_on_realtime_socket_closed)
	_realtime.socket_errored.connect(_on_realtime_socket_errored)
	_realtime.channel_event.connect(_on_channel_event)
	_realtime.channel_join_failed.connect(_on_channel_join_failed)
	_realtime.latency_updated.connect(_on_realtime_latency_updated)
	_realtime.debug_message.connect(_on_realtime_debug_message)
	_realtime.user_channel_joined.connect(_on_realtime_user_channel_joined)
	_realtime.user_channel_closed.connect(_on_realtime_user_channel_disconnected)
	_realtime.user_channel_error.connect(_on_realtime_user_channel_disconnected)
	add_child(_realtime)
	if http_request_timeout_sec > 0.0:
		var timeout_timer := _create_request_timeout_timer(http_request_timeout_sec)
		if timeout_timer:
			timeout_timer.timeout.connect(_on_realtime_start_timeout.bind(_realtime_start_revision))
	return await _realtime_start_result.finished

func realtime_stop():
	if _realtime:
		_realtime.shutdown()
		_realtime.queue_free()
	_realtime = null

func _get_realtime_access_token() -> String:
	return _access_token

func _finish_realtime_start(error = null) -> void:
	if _realtime_start_result == null:
		return
	if _realtime_start_finished:
		return
	_realtime_start_finished = true
	if error:
		_realtime_start_result.error = error
	_realtime_start_result.finished.emit(_realtime_start_result)

func _on_realtime_socket_opened() -> void:
	_finish_realtime_start()
	socket_connected.emit()

func _on_realtime_socket_closed() -> void:
	_finish_realtime_start()
	socket_disconnected.emit()
	if not _shutting_down:
		_refresh_token_if_expired()

func _on_realtime_socket_errored() -> void:
	_finish_realtime_start()
	socket_disconnected.emit()
	if not _shutting_down:
		_refresh_token_if_expired()

func _on_realtime_latency_updated(ms: int) -> void:
	latency_updated.emit(ms)

func _on_realtime_debug_message(severity: String, category: String, message: String) -> void:
	debug_message.emit(severity, category, message)

func _on_realtime_user_channel_joined() -> void:
	user_channel_joined.emit()

func _on_realtime_user_channel_disconnected() -> void:
	user_channel_disconnected.emit()

func _on_realtime_start_timeout(revision: int) -> void:
	if revision != _realtime_start_revision:
		return
	if _realtime_start_finished:
		return
	var error := _make_api_error(
		"gamend.realtime.timeout",
		"GamendWebSocket.start timed out after %.1fs" % http_request_timeout_sec,
		ERR_TIMEOUT
	)
	_finish_realtime_start(error)
	debug_message.emit("err", "network", error.message)
	network_request_failed.emit(error.message)

func is_realtime_connected() -> bool:
	return _realtime != null and _realtime.socket != null and _realtime.socket.is_connected

func listen_to_user():
	_realtime.add_channel("user:" + str(_user_id))

## The current user's realtime channel (joined on first call). Used for
## WebRTC signaling (see GamendWebRTC).
func get_user_channel() -> PhoenixChannel:
	return _realtime.add_channel("user:" + str(_user_id))

func listen_to_lobby():
	_realtime.add_channel("lobby:" + str(_lobby_id))

func listen_to_party():
	if _party_id != "":
		_realtime.add_channel("party:" + str(_party_id))

## Unsubscribe from the party channel so it stops trying to rejoin.
func stop_listening_to_party():
	if _party_id != "":
		_realtime.remove_channel("party:" + str(_party_id))

## Unsubscribe from the lobby channel so it stops trying to rejoin.
func stop_listening_to_lobby():
	if _lobby_id != "":
		_realtime.remove_channel("lobby:" + str(_lobby_id))

## Subscribe to a group channel to receive group realtime events.
func listen_to_group(group_id: String):
	_realtime.add_channel("group:" + str(group_id))

## Subscribe to the lobbies collection channel (lobby browser: lobby_created, lobby_updated, etc.)
func listen_to_lobbies():
	_realtime.add_channel("lobbies")

## Subscribe to the groups collection channel (group browser: group_created, group_updated, etc.)
func listen_to_groups():
	_realtime.add_channel("groups")

func _on_channel_event(event: String, payload: Dictionary, status, topic: String):
	if topic.begins_with("user:"):
		_handle_user_event(event, payload)
	elif topic == "lobbies":
		_handle_lobbies_event(event, payload)
	elif topic == "groups":
		_handle_groups_event(event, payload)
	elif topic.begins_with("lobby:"):
		payload["lobby_id"] = topic.substr(6)
		_handle_lobby_event(event, payload)
	elif topic.begins_with("party:"):
		payload["party_id"] = topic.substr(6)
		_handle_party_event(event, payload)
	elif topic.begins_with("group:"):
		payload["group_id"] = topic.substr(6)
		_handle_group_event(event, payload)

func _on_channel_join_failed(topic: String, reason: String, _payload: Dictionary) -> void:
	if not topic.begins_with("lobby:"):
		return
	var failed_lobby_id := topic.substr(6)
	if _realtime:
		_realtime.remove_channel(topic)
	if failed_lobby_id == str(_lobby_id):
		_lobby_id = ""
	lobby_channel_join_failed.emit(failed_lobby_id, reason)

func _handle_user_event(event: String, payload: Dictionary):
	match event:
		"updated":
			if payload.has("lobby_id"):
				var lobby_id = _id_str(payload["lobby_id"])
				if lobby_id != _lobby_id:
					stop_listening_to_lobby()
					_lobby_id = lobby_id
					if lobby_id != "":
						listen_to_lobby()
			if payload.has("party_id"):
				var party_id = _id_str(payload["party_id"])
				if party_id != _party_id:
					stop_listening_to_party()
					_party_id = party_id
					if party_id != "":
						listen_to_party()
			user_updated.emit(payload)
		"notification_created":
			notification_emitted.emit(payload)
		# Sent as JSON — neither has a protobuf mapping, so decode_event returns
		# null for them and the raw payload arrives here unchanged.
		"wallet_updated":
			wallet_updated.emit(payload)
		"inventory_updated":
			inventory_updated.emit(payload)
		"kv_updated":
			kv_updated.emit(payload)
		"kv_deleted":
			kv_deleted.emit(payload)
		"friend_updated":
			friend_updated.emit(payload)
		"outgoing_request":
			if payload.get("status", "") == "accepted":
				# Emit friend_added only — don't also emit friend_request_outgoing,
				# which would race _reload_requests_only against the friends-list fetch.
				friend_added.emit(payload)
			else:
				friend_request_outgoing.emit(payload)
		"incoming_request":
			if payload.get("status", "") == "accepted":
				friend_added.emit(payload)
			else:
				friend_request_incoming.emit(payload)
		"request_accepted":
			friend_added.emit(payload)
		"friend_accepted":
			friend_added.emit(payload)
		"friend_added":
			friend_added.emit(payload)
		"request_cancelled":
			friend_request_cancelled.emit(payload)
		"friend_removed":
			friend_removed.emit(payload)
		"chat_message_created":
			friend_chat_message.emit(payload)
		"chat_message_updated":
			friend_chat_message_updated.emit(payload)
		"chat_message_deleted":
			friend_chat_message_deleted.emit(payload)
		"group_invite_accepted":
			group_invite_accepted.emit(payload)
		"group_invite_cancelled":
			group_invite_cancelled.emit(payload)
		"group_join_request_approved":
			group_join_request_approved.emit(payload)
		"group_join_request_rejected":
			group_join_request_rejected.emit(payload)
		"party_invite_accepted":
			party_invite_accepted.emit(payload)
		"party_invite_declined":
			party_invite_declined.emit(payload)
		"party_invite_cancelled":
			party_invite_cancelled.emit(payload)
		"friend_blocked":
			friend_blocked.emit(payload)
		"friend_unblocked":
			friend_unblocked.emit(payload)
		"friend_rejected":
			friend_rejected.emit(payload)
		"quest_progress":
			quest_progress.emit(payload)
		"quest_completed":
			quest_completed.emit(payload)
		"quest_claimed":
			quest_claimed.emit(payload)

func _handle_lobby_event(event: String, payload: Dictionary):
	match event:
		"updated":
			lobby_updated.emit(payload)
		"state_changed":
			lobby_state_changed.emit(payload)
		"user_joined":
			lobby_member_joined.emit(payload)
		"user_left":
			lobby_member_left.emit(payload)
		"user_kicked":
			lobby_member_kicked.emit(payload)
		"user_online":
			lobby_member_online.emit(payload)
		"user_offline":
			lobby_member_offline.emit(payload)
		"user_updated":
			lobby_member_updated.emit(payload)
		"host_changed":
			lobby_host_changed.emit(payload)
		"chat_message_created":
			lobby_chat_message.emit(payload)
		"chat_message_updated":
			lobby_chat_message_updated.emit(payload)
		"chat_message_deleted":
			lobby_chat_message_deleted.emit(payload)
		"ready_check_started":
			ready_check_started.emit(payload)
		"ready_check_updated":
			ready_check_updated.emit(payload)
		"ready_check_passed":
			ready_check_passed.emit(payload)
		"ready_check_failed":
			ready_check_failed.emit(payload)
		_:
			# Reached the end without a case: the server sent something this
			# client has no handler for. Harmless, but it is exactly how a new
			# event goes unnoticed for a release.
			push_warning("[gamend] Unhandled user event: %s" % event)

func _handle_lobbies_event(event: String, payload: Dictionary):
	match event:
		"lobby_created":
			lobby_created.emit(payload)
		"lobby_updated":
			lobby_list_updated.emit(payload)
		"lobby_deleted":
			lobby_deleted.emit(payload)
		"lobby_membership_changed":
			lobby_membership_changed.emit(payload)

func _handle_party_event(event: String, payload: Dictionary):
	match event:
		"updated":
			party_updated.emit(payload)
		"member_joined":
			party_member_joined.emit(payload)
		"member_left":
			party_member_left.emit(payload)
		"member_online":
			party_member_online.emit(payload)
		"member_offline":
			party_member_offline.emit(payload)
		"member_updated":
			party_member_updated.emit(payload)
		"disbanded":
			party_disbanded.emit(payload)
		"chat_message_created":
			party_chat_message.emit(payload)
		"chat_message_updated":
			party_chat_message_updated.emit(payload)
		"chat_message_deleted":
			party_chat_message_deleted.emit(payload)
		"ready_check_started":
			ready_check_started.emit(payload)
		"ready_check_updated":
			ready_check_updated.emit(payload)
		"ready_check_passed":
			ready_check_passed.emit(payload)
		"ready_check_failed":
			ready_check_failed.emit(payload)

func _handle_group_event(event: String, payload: Dictionary):
	match event:
		"updated":
			group_updated.emit(payload)
		"member_joined":
			group_member_joined.emit(payload)
		"member_left":
			group_member_left.emit(payload)
		"member_kicked":
			group_member_kicked.emit(payload)
		"member_promoted":
			group_member_promoted.emit(payload)
		"member_demoted":
			group_member_demoted.emit(payload)
		"member_online":
			group_member_online.emit(payload)
		"member_offline":
			group_member_offline.emit(payload)
		"member_updated":
			group_member_updated.emit(payload)
		"join_request_approved":
			group_join_request_approved.emit(payload)
		"join_request_rejected":
			group_join_request_rejected.emit(payload)
		"chat_message_created":
			group_chat_message.emit(payload)
		"chat_message_updated":
			group_chat_message_updated.emit(payload)
		"chat_message_deleted":
			group_chat_message_deleted.emit(payload)

func _handle_groups_event(event: String, payload: Dictionary):
	match event:
		"group_created":
			group_created.emit(payload)
		"group_updated":
			group_list_updated.emit(payload)
		"group_deleted":
			group_deleted.emit(payload)
		
## Authorize with access token
func authorize():
	_config.headers_base["Authorization"] = "Bearer " + _access_token

## Start uploading client logs to this server. Address and bearer token come
## from this instance, so there is nothing to keep in sync by hand:
##
##     gamend_api.start_logs()
##     DebugLog.log_added.connect(gamend_api.logs.submit)
##
## Collection is off until the server says otherwise, so calling this in a build
## whose server has client logs disabled costs one request and nothing else.
func start_logs() -> void:
	var scheme := "https://" if _config.tls_enabled else "http://"
	logs.setup(scheme + _config.host + ":" + str(_config.port), get_access_token)

## The client log session id, sent on every request and socket connect so the
## server can tag its own log lines with it. One search for that id then returns
## both what this client reported and what the server did about it, instead of
## two lists to line up by timestamp. See GamendLogs.
func set_client_session(session_id: String) -> void:
	_client_session_id = session_id
	if session_id.is_empty():
		_config.headers_base.erase("x-gamend-session")
	else:
		_config.headers_base["x-gamend-session"] = session_id

func get_client_session() -> String:
	return _client_session_id

## The current bearer token, or "" when not signed in. Public so callers that
## need to authenticate a request themselves (GamendLogs uploads outside the
## generated API layer) do not reach into a private field.
func get_access_token() -> String:
	return _access_token

### HEALTH

## Health check
func health_index() -> GamendResult:
	return await _call_api(HealthApi.new(_config), "index")

## Server clock, for rendering in server-time space.
## Sample a few times and average to estimate the offset; never trust a single
## reading, since it includes one-way network latency.
func time_get_server_time() -> GamendResult:
	return await _call_api(TimeApi.new(_config), "get_server_time")

### HOOKS

## Invoke a hook function via HTTP
func hooks_call_hook(hook_request: GamendCallHookRequest) -> GamendResult:
	return await _call_api(HooksApi.new(_config), "call_hook", [hook_request])

## Invoke a hook function via WebSocket push. Fire-and-forget.
## If topic is empty, pushes on the user channel.
func hooks_call_hook_ws(plugin: String, fn_name: String, args: Array = [], topic: String = "") -> bool:
	if not _realtime:
		return false
	return _realtime.call_hook(plugin, fn_name, args, topic)

## List available hook functions
func hooks_list_hooks(page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(HooksApi.new(_config), "list_hooks", [page, pageSize])

### USERS

## Delete current user
func user_delete_current_user() -> GamendResult:
	return await _call_api(UsersApi.new(_config), "delete_current_user")

## Get current user info
func users_get_current_user() -> GamendResult:
	return await _call_api(UsersApi.new(_config), "get_current_user")

## Update current user's display name
func user_update_current_user_display_name(display_name: String) -> GamendResult:
	var request := GamendUpdateCurrentUserDisplayNameRequest.new()
	request.display_name = display_name
	return await _call_api(UsersApi.new(_config), "update_current_user_display_name", [request])

## Update current user's unique username handle (lowercased on save; 3-32
## letters or digits, with non-consecutive . _ - separators; letters keep to
## one script, except Latin mixes with Chinese, Japanese or Korean).
## Fails when taken/invalid.
func user_update_current_user_username(username: String) -> GamendResult:
	var request := GamendUpdateCurrentUserUsernameRequest.new()
	request.username = username
	return await _call_api(UsersApi.new(_config), "update_current_user_username", [request])

## Update current user's password
func user_update_current_user_password(password: String) -> GamendResult:
	return await _call_api(UsersApi.new(_config), "update_current_user_password", [password])

## Search users by id, username, or display_name
func users_search_users(query = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(UsersApi.new(_config), "search_users", [query, page, pageSize])

## Get a user by id
func users_get_user(id: String) -> GamendResult:
	return await _call_api(UsersApi.new(_config), "get_user", [id])


### AUTHENTICATION

## Get OAuth session status
func authenticate_oauth_session_status(session_id: String) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "oauth_session_status", [session_id])

## Initiate API OAuth
func authenticate_oauth_request(provider: String) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "oauth_request", [provider])

## API Callback / Code Exchange
func authenticate_oauth_api_callback(provider: String, callback_request: GamendOauthApiCallbackRequest) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "oauth_api_callback", [provider, callback_request])

## Apple Callback (native iOS)
func authenticate_oauth_callback_api_apple_ios(ios_request: GamendOauthCallbackApiAppleIosRequest) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "oauth_callback_api_apple_ios", [ios_request])

## Login
func authenticate_login(login_request: GamendLoginRequest) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "login", [login_request])

## Device login
func authenticate_device_login(device_id: String) -> GamendResult:
	var device_login := GamendDeviceLoginRequest.new()
	device_login.device_id = device_id
	return await _call_api(AuthenticationApi.new(_config), "device_login", [device_login])

## Logout
func authenticate_logout() -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "logout")

## Unlink OAuth provider
func authenticate_unlink_provider(provider: String) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "unlink_provider", [provider])

## Link a provider to the signed-in account with a code (for Steam, a session
## ticket). Signing in with one is authenticate_oauth_api_callback.
func authenticate_link_provider(provider: String, code: String) -> GamendResult:
	var link_request := GamendLinkProviderRequest.new()
	link_request.code = code
	return await _call_api(AuthenticationApi.new(_config), "link_provider", [provider, link_request])

## Link Google to the signed-in account with a Google ID token
func authenticate_link_google_id_token(id_token: String) -> GamendResult:
	var link_request := GamendLinkGoogleIdTokenRequest.new()
	link_request.id_token = id_token
	return await _call_api(AuthenticationApi.new(_config), "link_google_id_token", [link_request])

## Link Apple to the signed-in account with a native Sign in with Apple code.
## given_name/family_name come from the credential (Apple sends them only on
## the first authorization) and fill a blank display name.
func authenticate_link_apple_ios(code: String, given_name := "", family_name := "") -> GamendResult:
	var link_request := GamendLinkAppleIosRequest.new()
	link_request.code = code
	link_request.given_name = given_name
	link_request.family_name = family_name
	return await _call_api(AuthenticationApi.new(_config), "link_apple_ios", [link_request])

## Start linking a provider through its page: answers the URL to open and a
## session to poll with authenticate_link_session_status
func authenticate_link_provider_request(provider: String) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "link_provider_request", [provider])

## Poll a provider link started with authenticate_link_provider_request
func authenticate_link_session_status(session_id: String) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "link_session_status", [session_id])

## Unlink device
func authenticate_unlink_device() -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "unlink_device", [])

## Link device
func authenticate_link_device(device_id: String) -> GamendResult:
	var linkDeviceRequest:= GamendLinkDeviceRequest.new()
	linkDeviceRequest.device_id = device_id
	return await _call_api(AuthenticationApi.new(_config), "link_device", [linkDeviceRequest])

## Refresh access token
func authenticate_refresh_token(refresh_token: String) -> GamendResult:
	var refresh_param:= GamendRefreshTokenRequest.new()
	refresh_param.refresh_token = refresh_token
	return await _call_api(AuthenticationApi.new(_config), "refresh_token", [refresh_param])

## Register: a new account with an email, and no password yet. Not a sign-in,
## as device login is: the answer is the account (`GamendRegistration`), and no
## session is kept. The server emails a link and a six-digit code; pass the code
## and the password the player chooses to `authenticate_confirm_registration`,
## which signs in. The server generates a username when none is given.
## (It replaces `authenticate_register(email, password)`, under a new name so an
## old call fails instead of sending the password as the username.)
func authenticate_register_email(email: String, username := "") -> GamendResult:
	var register_request := GamendRegisterRequest.new()
	register_request.email = email
	if username != "":
		register_request.username = username
	return await _call_api(AuthenticationApi.new(_config), "register", [register_request])

## Confirm a registration with the code from its email, set the account's
## password, and sign in (the session is kept, as `authenticate_login` does).
## Errors: `invalid_code` (wrong, spent or expired), `account_locked` (too many
## wrong codes; the code is void, ask for a new one), `validation_failed` (the
## password is refused; that costs no attempt).
func authenticate_confirm_registration(email: String, code: String, password: String) -> GamendResult:
	var confirm_request := GamendConfirmRegistrationRequest.new()
	confirm_request.email = email
	confirm_request.code = code
	confirm_request.password = password
	return await _call_api(AuthenticationApi.new(_config), "confirm_registration", [confirm_request])

## Email a registration a new code; only the newest works. Succeeds whether or
## not the address has an account waiting.
func authenticate_resend_confirmation(email: String) -> GamendResult:
	var resend_request := GamendResendConfirmationRequest.new()
	resend_request.email = email
	return await _call_api(AuthenticationApi.new(_config), "resend_confirmation", [resend_request])

### FRIENDS

## Send a friend request
func friends_create_friend_request(friend_request: GamendCreateFriendRequestRequest) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "create_friend_request", [friend_request])

## Remove/cancel a friendship or request
func friends_remove_friendship(id: String) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "remove_friendship", [id])

## Accept a friend request
func friends_accept_friend_request(id: String) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "accept_friend_request", [id])

## Block a friend request / user
func friends_block_friend_request(id: String) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "block_friend_request", [id])

## Reject a friend request
func friends_reject_friend_request(id: String) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "reject_friend_request", [id])

## Unblock a previously-blocked friendship
func friends_unblock_friend(id: String) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "unblock_friend", [id])

## List users you've blocked
func friends_list_blocked_friends(page = 1, page_size = 25) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "list_blocked_friends", [page, page_size])

## List pending friend requests (incoming and outgoing)
func friends_list_friend_requests(page = 1, page_size = 25) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "list_friend_requests", [page, page_size])

## List current user's friends (returns a paginated set of user objects)
func friends_list_friends(page = 1, page_size = 25) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "list_friends", [page, page_size])

### LOBBIES

## List lobbies

func lobbies_list_lobbies(
	title = "",
	isPassworded = null,
	isLocked = null,
	minUsers = null,
	maxUsers = null,
	page = null,
	pageSize = null,
	metadataKey = "",
	metadataValue = "") -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "list_lobbies", [title, isPassworded, isLocked, minUsers, maxUsers, page, pageSize, metadataKey, metadataValue])

## Update lobby (host only)
func lobbies_update_lobby(update_request: GamendUpdateLobbyRequest) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "update_lobby", [update_request])

## Create a lobby
func lobbies_create_lobby(create_request: GamendCreateLobbyRequest) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "create_lobby", [create_request])

## Kick a user from the lobby (host only)
func lobbies_kick_user(kick_request: GamendKickUserRequest) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "kick_user", [kick_request])

## Leave the current lobby
func lobbies_leave_lobby() -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "leave_lobby")

## End the lobby for everyone (host only). Leaving hands the lobby to the next
## member; this ends it outright, so only the host may call it.
func lobbies_disband_lobby() -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "disband_lobby")

## Move the lobby to another lifecycle state (created / starting / playing /
## ended, plus whatever the game's own before_lobby_state_change hook allows).
## Host of a host-managed lobby, or the lobby's pinned WebRTC host; a hostless
## matchmaking lobby with no pinned host belongs to the server, so nobody may
## move it. Targets the caller's own lobby unless the request names another.
func lobbies_set_lobby_state(state_request: GamendSetLobbyStateRequest) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "set_lobby_state", [state_request])

## Quick-join or create a lobby
func lobbies_quick_join(quick_request: GamendQuickJoinRequest) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "quick_join", [quick_request])

## Join a lobby
func lobbies_join_lobby(id: String, join_request: GamendJoinLobbyRequest = null) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "join_lobby", [id, join_request])

## Get a lobby by ID
func lobbies_get_lobby(id: String) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "get_lobby", [id])

### LEADERBOARDS

## List leaderboard records
func leaderboards_list_leaderboard_records(id: String, page = 1, page_size = 25) -> GamendResult:
	return await _call_api(LeaderboardsApi.new(_config), "list_leaderboard_records", [id, page, page_size])

## List leaderboards
func leaderboards_list_leaderboards(slug = "", active = null, orderBy = "ends_at", startsAfter = null, startsBefore = null, endsAfter = null, endsBefore = null, page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(LeaderboardsApi.new(_config), "list_leaderboards", [slug, active, orderBy, startsAfter, startsBefore, endsAfter, endsBefore, page, pageSize])

## Get current user's record
func leaderboards_get_my_record(id: String) -> GamendResult:
	return await _call_api(LeaderboardsApi.new(_config), "get_my_record", [id])

## List records around a user
func leaderboards_list_records_around_user(id: String, user_id: String, limit = 11) -> GamendResult:
	return await _call_api(LeaderboardsApi.new(_config), "list_records_around_user", [id, user_id, limit])

## Get a leaderboard by ID
func leaderboards_get_leaderboard(id: String) -> GamendResult:
	return await _call_api(LeaderboardsApi.new(_config), "get_leaderboard", [id])

## Resolve multiple slugs to their active leaderboards
## Returns a map of slug -> leaderboard for each slug that has an active leaderboard
func leaderboards_resolve_slugs(slugs: Array) -> GamendResult:
	var request = GamendResolveLeaderboardSlugsRequest.new()
	request.slugs = slugs
	return await _call_api(LeaderboardsApi.new(_config), "resolve_leaderboard_slugs", [request])

## KV

## Get a key/value entry 
func kv_get_kv(key: String, user_id = null, lobby_id = null) -> GamendResult:
	return await _call_api(KVApi.new(_config), "get_kv", [key, user_id, lobby_id])

## Subscribe to a key/value entry via the user WebSocket channel.
func kv_subscribe_ws(key: String, user_id = null, lobby_id = null) -> GamendResult:
	return await _kv_subscription_request_ws("kv:subscribe", key, user_id, lobby_id)

## Unsubscribe from a key/value entry via the user WebSocket channel.
func kv_unsubscribe_ws(key: String, user_id = null, lobby_id = null) -> GamendResult:
	return await _kv_subscription_request_ws("kv:unsubscribe", key, user_id, lobby_id)

func _kv_subscription_request_ws(event: String, key: String, user_id = null, lobby_id = null) -> GamendResult:
	var result := GamendResult.new()
	var error_prefix := event.replace(":", ".") + ".websocket"
	if not _realtime:
		result.error = _make_api_error(error_prefix + ".no_realtime", "Realtime socket is not started.", FAILED)
		return result

	var payload := {"key": key}
	if user_id != null:
		payload["user_id"] = user_id
	if lobby_id != null:
		payload["lobby_id"] = lobby_id

	var reply: Dictionary = await _realtime.request(event, payload, "", http_request_timeout_sec)
	var response_payload: Dictionary = {}
	if reply.get("payload", {}) is Dictionary:
		response_payload = (reply["payload"] as Dictionary).duplicate(true)
	response_payload.erase("_request_id")

	if str(reply.get("status", "error")) == "ok":
		var response := ApiApiResponseClient.new()
		response.code = HTTPClient.RESPONSE_OK
		response.body = JSON.stringify(response_payload)
		response.data = response_payload
		result.response = response
		network_request_succeeded.emit()
	else:
		result.error = _make_ws_api_error(error_prefix, response_payload, FAILED)
		# no_channel / push_failed / no_scene_tree mean OUR transport was not
		# ready to send — not that the network is down. Escalating them turned a
		# reconnect blip into a dead session: the first failed re-subscribe fired
		# network_request_failed -> fail_network -> realtime_stop(), which nulled
		# the socket, so every remaining re-subscribe failed too and the watchdog
		# then skipped recovery because the state was already "failed". The
		# reconnect path owns transport readiness; the request watchdog does not.
		var transport_error: bool = (
			str(response_payload.get("error", "")) in ["no_channel", "push_failed", "no_scene_tree"]
		)
		if (
			not transport_error
			and result.error.response_code
			not in [
				HTTPClient.RESPONSE_BAD_REQUEST,
				HTTPClient.RESPONSE_FORBIDDEN,
				HTTPClient.RESPONSE_NOT_FOUND,
			]
		):
			network_request_failed.emit(result.error.message)
	return result

### QUESTS

## List my quests with progress and claimable flag (auth required)
func quests_my_quests(kind = "", group = "", page = 1, page_size = 25) -> GamendResult:
	return await _call_api(QuestsApi.new(_config), "my_quests", [kind, group, page, page_size])

## Claim a completed quest's rewards (auth required)
func quests_claim_quest(key: String) -> GamendResult:
	return await _call_api(QuestsApi.new(_config), "claim_quest", [key])

## List the public quest catalog (includes user progress if authenticated)
func quests_list_quests(kind = "", page = 1, page_size = 25) -> GamendResult:
	return await _call_api(QuestsApi.new(_config), "list_quests", [kind, page, page_size])

## List a user's completed quests (defaults to kind "achievement")
func quests_user_quests(user_id: String, kind = "achievement", page = 1, page_size = 25) -> GamendResult:
	return await _call_api(QuestsApi.new(_config), "user_quests", [user_id, kind, page, page_size])

## CHAT

## List messages in a lobby, group, party, or friend conversation
func chat_list_chat_messages(chat_type: String, chat_ref_id: String, page = 1, page_size = 25) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "list_chat_messages", [chat_type, chat_ref_id, page, page_size])

## Get a single chat message by ID
func chat_get_chat_message(id: String) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "get_chat_message", [id])

## Send a message to a lobby, group, party, or friend conversation
func chat_send_chat_message(sendChatMessageRequest: GamendSendChatMessageRequest) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "send_chat_message", [sendChatMessageRequest])

## Update (edit) a chat message by ID
func chat_update_chat_message(id: String, content: String, metadata: Dictionary = {}) -> GamendResult:
	var request = GamendUpdateChatMessageRequest.new()
	request.content = content
	if not metadata.is_empty():
		request.metadata = metadata
	return await _call_api(ChatApi.new(_config), "update_chat_message", [id, request])

## Delete a chat message by ID
func chat_delete_chat_message(id: String) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "delete_chat_message", [id])

## Mark a chat conversation as read up to a given message ID
func chat_mark_chat_read(markChatReadRequest: GamendMarkChatReadRequest) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "mark_chat_read", [markChatReadRequest])

## Get unread message count for a chat conversation
func chat_chat_unread_count(chat_type: String, chat_ref_id: String) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "chat_unread_count", [chat_type, chat_ref_id])

## NOTIFICATIONS

## Delete notifications by IDs
func notifications_delete_notifications(deleteNotificationsRequest: GamendDeleteNotificationsRequest) -> GamendResult:
	return await _call_api(NotificationsApi.new(_config), "delete_notifications", [deleteNotificationsRequest])

## List own notifications
func notifications_list_notifications(
	# page: int   Eg: 56
	# Page number (1-based)
	page = null,
	# pageSize: int   Eg: 56
	# Page size (max results per page)
	pageSize = null) -> GamendResult:
	return await _call_api(NotificationsApi.new(_config), "list_notifications", [page, pageSize])

## Send a notification to a friend
func notifications_send_notification(sendNotificationRequest: GamendSendNotificationRequest) -> GamendResult:
	return await _call_api(NotificationsApi.new(_config), "send_notification", [sendNotificationRequest])

## GROUPS

## Accept a group invitation by invite_id
func groups_accept_group_invite(inviteId: String):
	return await _call_api(GroupsApi.new(_config), "accept_group_invite", [inviteId])

## Decline a group invitation by invite_id
func groups_decline_group_invite(inviteId: String):
	return await _call_api(GroupsApi.new(_config), "decline_group_invite", [inviteId])

## Approve a join request (admin only)
func groups_approve_join_request(
	# id: int   Eg: 56
	# Group ID
	id: String,
	# requestId: int   Eg: 56
	# Join request ID
	requestId: String,):
	return await _call_api(GroupsApi.new(_config), "approve_join_request", [id, requestId])

## Cancel a sent group invitation
func groups_cancel_group_invite(inviteId: String):
	return await _call_api(GroupsApi.new(_config), "cancel_group_invite", [inviteId])

## Cancel your own pending join request
func groups_cancel_join_request(
	# id: int   Eg: 56
	# Group ID
	id: String,
	# requestId: int   Eg: 56
	# Join request ID
	requestId: String,):
	return await _call_api(GroupsApi.new(_config), "cancel_join_request", [id, requestId])

## Create a group
func groups_create_group(createGroupRequest: GamendCreateGroupRequest):
	return await _call_api(GroupsApi.new(_config), "create_group", [createGroupRequest])

## Delete a group with everyone in it (admin only)
func groups_delete_group(
	# id: int   Eg: 56
	# Group ID
	id: String,):
	return await _call_api(GroupsApi.new(_config), "delete_group", [id])

## Demote admin to member
func groups_demote_group_member(
	# id: int   Eg: 56
	# Group ID
	id: String,
	# demoteGroupMemberRequest: GamendDemoteGroupMemberRequest
	# Demote parameters
	demoteGroupMemberRequest: GamendDemoteGroupMemberRequest,):
	return await _call_api(GroupsApi.new(_config), "demote_group_member", [id, demoteGroupMemberRequest])

## Get group details
func groups_get_group(
	# id: int   Eg: 56
	# Group ID
	id: String,):
	return await _call_api(GroupsApi.new(_config), "get_group", [id])

## Invite a user to a group (admin only). If the target has a pending join request, it is auto-approved.
func groups_invite_to_group(
	# id: int   Eg: 56
	# Group ID
	id: String,
	inviteToGroupRequest: GamendInviteToGroupRequest):
	return await _call_api(GroupsApi.new(_config), "invite_to_group", [id, inviteToGroupRequest])

## Join a group
func groups_join_group(
	# id: int   Eg: 56
	# Group ID
	id: String,):
	return await _call_api(GroupsApi.new(_config), "join_group", [id])

## Kick a member (admin only)
func groups_kick_group_member(
	# id: int   Eg: 56
	# Group ID
	id: String,
	kickGroupMemberRequest: GamendKickGroupMemberRequest):
	return await _call_api(GroupsApi.new(_config), "kick_group_member", [id, kickGroupMemberRequest])

## Leave a group
func groups_leave_group(
	# id: int   Eg: 56
	# Group ID
	id: String,):
	return await _call_api(GroupsApi.new(_config), "leave_group", [id])

## List my group invitations
func groups_list_group_invitations(
	# page: int   Eg: 56
	# Page number (default: 1)
	page = null,
	# pageSize: int   Eg: 56
	# Items per page (default: 25)
	pageSize = null,):
	return await _call_api(GroupsApi.new(_config), "list_group_invitations", [page, pageSize])

## List group members
func groups_list_group_members(
	# id: int   Eg: 56
	# Group ID
	id: String,
	# page: int   Eg: 56
	# Page number (default: 1)
	page = null,
	# pageSize: int   Eg: 56
	# Items per page (default: 25)
	pageSize = null,):
	return await _call_api(GroupsApi.new(_config), "list_group_members", [id, page, pageSize])

## List groups
func groups_list_groups(
	# title: String = ""   Eg: title_example
	# Search by title (prefix)
	title = "",
	# type: String = ""   Eg: type_example
	# Filter by group type
	type = "",
	# minMembers: int   Eg: 56
	# Minimum max_members to include
	minMembers = null,
	# maxMembers: int   Eg: 56
	# Maximum max_members to include
	maxMembers = null,
	# metadataKey: String = ""   Eg: metadataKey_example
	# Metadata key to filter by
	metadataKey = "",
	# metadataValue: String = ""   Eg: metadataValue_example
	# Metadata value to match (with metadata_key)
	metadataValue = "",
	# page: int   Eg: 56
	# Page number
	page = null,
	# pageSize: int   Eg: 56
	# Page size
	pageSize = null,):
	return await _call_api(GroupsApi.new(_config), "list_groups", [title, type, minMembers, maxMembers, metadataKey, metadataValue, page, pageSize])

## List pending join requests (admin only)
func groups_list_join_requests(
	# id: int   Eg: 56
	# Group ID
	id: String,
	# page: int   Eg: 56
	# Page number
	page = null,
	# pageSize: int   Eg: 56
	# Page size
	pageSize = null,):
	return await _call_api(GroupsApi.new(_config), "list_join_requests", [id, page, pageSize])

## List groups I belong to
func groups_list_my_groups(
	# page: int   Eg: 56
	# Page number (default: 1)
	page = null,
	# pageSize: int   Eg: 56
	# Items per page (default: 25)
	pageSize = null,):
	return await _call_api(GroupsApi.new(_config), "list_my_groups", [page, pageSize])

## List group invitations I have sent
func groups_list_sent_invitations(
	# page: int   Eg: 56
	# Page number (default: 1)
	page = null,
	# pageSize: int   Eg: 56
	# Items per page (default: 25)
	pageSize = null,):
	return await _call_api(GroupsApi.new(_config), "list_sent_invitations", [page, pageSize])

## Promote member to admin
func groups_promote_group_member(
	# id: int   Eg: 56
	# Group ID
	id: String,
	promoteGroupMemberRequest: GamendPromoteGroupMemberRequest):
	return await _call_api(GroupsApi.new(_config), "promote_group_member", [id, promoteGroupMemberRequest])

## Reject a join request (admin only)
func groups_reject_join_request(
	# id: int   Eg: 56
	# Group ID
	id: String,
	# requestId: int   Eg: 56
	# Join request ID
	requestId: String,):
	return await _call_api(GroupsApi.new(_config), "reject_join_request", [id, requestId])

## Update a group (admin only)
func groups_update_group(
	# id: int   Eg: 56
	# Group ID
	id: String,
	updateGroupRequest: GamendUpdateGroupRequest):
	return await _call_api(GroupsApi.new(_config), "update_group", [id, updateGroupRequest])

## READY CHECKS

## The caller's open ready checks, one per lane: {lobby: check|null, party: check|null}
func ready_checks_get_mine() -> GamendResult:
	return await _call_api(ReadyChecksApi.new(_config), "get_my_ready_check", [])

## Answer the open check in one lane ("lobby" also answers a matchmaking accept)
func ready_checks_respond(ready: bool, scope: String = "lobby") -> GamendResult:
	var request := GamendRespondReadyCheckRequest.new()
	request.ready = ready
	request.scope = scope
	return await _call_api(ReadyChecksApi.new(_config), "respond_ready_check", [request])

## Open (or reset) the lobby board — host only; pass timeout_ms to force ready
func ready_checks_open_lobby(request: GamendOpenLobbyReadyCheckRequest = null) -> GamendResult:
	return await _call_api(ReadyChecksApi.new(_config), "open_lobby_ready_check", [request])

## Call off the lobby board — host only
func ready_checks_cancel_lobby() -> GamendResult:
	return await _call_api(ReadyChecksApi.new(_config), "cancel_lobby_ready_check", [])

## Open (or reset) the party board — leader only; pass timeout_ms to force ready
## (the request schema is shared with the lobby variant)
func ready_checks_open_party(request: GamendOpenPartyReadyCheckRequest = null) -> GamendResult:
	return await _call_api(ReadyChecksApi.new(_config), "open_party_ready_check", [request])

## Call off the party board — leader only
func ready_checks_cancel_party() -> GamendResult:
	return await _call_api(ReadyChecksApi.new(_config), "cancel_party_ready_check", [])

## PARTIES

## Create a party
func parties_create_party(createPartyRequest: GamendCreatePartyRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "create_party", [createPartyRequest])

## Invite a user to the party (leader only)
func parties_invite_to_party(inviteToPartyRequest: GamendInviteToPartyRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "invite_to_party", [inviteToPartyRequest])

## Cancel a pending party invite (leader only)
func parties_cancel_party_invite(cancelPartyInviteRequest: GamendCancelPartyInviteRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "cancel_party_invite", [cancelPartyInviteRequest])

## Accept a party invite
func parties_accept_party_invite(acceptPartyInviteRequest: GamendAcceptPartyInviteRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "accept_party_invite", [acceptPartyInviteRequest])

## Decline a party invite
func parties_decline_party_invite(declinePartyInviteRequest: GamendDeclinePartyInviteRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "decline_party_invite", [declinePartyInviteRequest])

## List pending party invites for the current user
func parties_list_party_invitations() -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "list_party_invitations", [])

## List pending party invites sent by the current leader
func parties_list_sent_party_invitations() -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "list_sent_party_invitations", [])

## Kick a member from the party (leader only)
func parties_kick_party_member(kickPartyMemberRequest: GamendKickPartyMemberRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "kick_party_member", [kickPartyMemberRequest])

## Leave the current party
func parties_leave_party() -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "leave_party", [])

## End the party for everyone (leader only). Leaving hands the party to the next
## member; this ends it outright, so only the leader may call it.
func parties_disband_party() -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "disband_party", [])

## Create a lobby with the party (leader only)
func parties_party_create_lobby(partyCreateLobbyRequest: GamendPartyCreateLobbyRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "party_create_lobby", [partyCreateLobbyRequest])

## Join a lobby with the party (leader only)
func parties_party_join_lobby(
	# id: int   Eg: 56
	# Lobby ID
	id: String,
	partyJoinLobbyRequest: GamendPartyJoinLobbyRequest,) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "party_join_lobby", [id, partyJoinLobbyRequest])

## Get current party
func parties_show_party() -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "show_party", [])

## Update party settings (leader only)
func parties_update_party(updatePartyRequest: GamendUpdatePartyRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "update_party", [updatePartyRequest])

## ADMIN SESSIONS

## Delete session token by id (admin)
func admin_sessions_admin_delete_session(id: String) -> GamendResult:
	return await _call_api(AdminSessionsApi.new(_config), "admin_delete_session", [id])

## List sessions (admin)
func admin_sessions_admin_list_sessions(page = 1, page_size = 25) -> GamendResult:
	return await _call_api(AdminSessionsApi.new(_config), "admin_list_sessions", [page, page_size])

## Delete all session tokens for a user (admin)
func admin_sessions_admin_delete_user_sessions(user_id) -> GamendResult:
	return await _call_api(AdminSessionsApi.new(_config), "admin_delete_user_sessions", [user_id])

## ADMIN USERS

# Delete user (admin)
func admin_users_admin_delete_user(id: String) -> GamendResult:
	return await _call_api(AdminUsersApi.new(_config), "admin_delete_user", [id])
	
# Update user (admin)
func admin_users_admin_update_user(id: String, admin_update_user_request: GamendAdminUpdateUserRequest) -> GamendResult:
	return await _call_api(AdminUsersApi.new(_config), "admin_update_user", [id, admin_update_user_request])

## ADMIN LOBBIES

# List all lobbies (admin)
func admin_lobbies_admin_list_lobbies(title = "", isHidden = null, isLocked = null, hasPassword = null, minUsers = null, maxUsers = null, page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminLobbiesApi.new(_config), "admin_list_lobbies", [title, isHidden, isLocked, hasPassword, minUsers, maxUsers, page, pageSize])

# Delete lobby (admin)
func admin_lobbies_admin_delete_lobby(id: String) -> GamendResult:
	return await _call_api(AdminLobbiesApi.new(_config), "admin_delete_lobby", [id])

# Update lobby (admin)
func admin_lobbies_admin_update_lobby(id: String, adminUpdateLobbyRequest: GamendAdminUpdateLobbyRequest) -> GamendResult:
	return await _call_api(AdminLobbiesApi.new(_config), "admin_update_lobby", [id, adminUpdateLobbyRequest])

## ADMIN LEADERBOARDS

## End leaderboard (admin)
func admin_leaderboards_admin_end_leaderboard(id: String) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_end_leaderboard", [id])

## Submit score (admin)
func admin_leaderboards_admin_submit_leaderboard_score(id: String, adminSubmitLeaderboardScoreRequest: GamendAdminSubmitLeaderboardScoreRequest) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_submit_leaderboard_score", [id, adminSubmitLeaderboardScoreRequest])

## Delete leaderboard record (admin)
func admin_leaderboards_admin_delete_leaderboard_record(id: String, recordId: String) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_delete_leaderboard_record", [id, recordId])

## Update leaderboard record (admin)
func admin_leaderboards_admin_update_leaderboard_record(id: String, recordId: String, adminUpdateLeaderboardRecordRequest: GamendAdminUpdateLeaderboardRecordRequest) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_update_leaderboard_record", [id, recordId, adminUpdateLeaderboardRecordRequest])

## Create leaderboard (admin)
func admin_leaderboards_admin_create_leaderboard(adminCreateLeaderboardRequest: GamendAdminCreateLeaderboardRequest) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_create_leaderboard", [adminCreateLeaderboardRequest])

## Delete a user's record (admin)
func admin_leaderboards_admin_delete_leaderboard_user_record(id: String, userId: String) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_delete_leaderboard_user_record", [id, userId])
	
## Delete leaderboard (admin)
func admin_leaderboards_admin_delete_leaderboard(id: String) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_delete_leaderboard", [id])

## Update leaderboard (admin)
func admin_leaderboards_admin_update_leaderboard(id: String, adminUpdateLeaderboardRequest: GamendAdminUpdateLeaderboardRequest) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_update_leaderboard", [id, adminUpdateLeaderboardRequest])

## ADMIN KV

## List KV entries (admin)
func admin_kv_admin_list_kv_entries(page = 1, pageSize = 25, key = "", userId = null, lobbyId = null, globalOnly = null) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_list_kv_entries", [page, pageSize, key, userId, lobbyId, globalOnly])

## Create KV entry (admin)
func admin_kv_admin_create_kv_entry(adminCreateKvEntryRequest: GamendAdminCreateKvEntryRequest) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_create_kv_entry", [adminCreateKvEntryRequest])

## Delete KV entry by id (admin)
func admin_kv_admin_delete_kv_entry(id: String) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_delete_kv_entry", [id])

## Update KV entry by id (admin)
func admin_kv_admin_update_kv_entry(id: String, adminUpdateKvEntryRequest: GamendAdminUpdateKvEntryRequest) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_update_kv_entry", [id, adminUpdateKvEntryRequest])

## Delete KV by key (admin)
func admin_kv_admin_delete_kv(key: String, user_id = null, lobby_id = null) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_delete_kv", [key, user_id, lobby_id])

## Upsert KV by key (admin)
func admin_kv_admin_upsert_kv(adminUpsertKvRequest: GamendAdminUpsertKvRequest) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_upsert_kv", [adminUpsertKvRequest])

## ADMIN NOTIFICATIONS

## Create a notification (admin)
func admin_notifications_admin_create_notification(adminCreateNotificationRequest: GamendAdminCreateNotificationRequest) -> GamendResult:
	return await _call_api(AdminNotificationsApi.new(_config), "admin_create_notification", [adminCreateNotificationRequest])

## Delete a notification (admin)
func admin_notifications_admin_delete_notification(id: String) -> GamendResult:
	return await _call_api(AdminNotificationsApi.new(_config), "admin_delete_notification", [id])

## List all notifications (admin)
func admin_notifications_admin_list_notifications(
	# userId: String   Eg: 56
	# Filter by recipient user ID
	userId = null,
	# senderId: int   Eg: 56
	# Filter by sender user ID
	senderId = null,
	# title: String = ""   Eg: title_example
	# Filter by title (partial match)
	title = "",
	# page: int   Eg: 56
	# Page number (1-based)
	page = null,
	# pageSize: int   Eg: 56
	# Page size
	pageSize = null,) -> GamendResult:
	return await _call_api(AdminNotificationsApi.new(_config), "admin_list_notifications", [userId, senderId, title, page, pageSize])

## ADMIN GROUPS

## Delete a group (admin)
func admin_groups_admin_delete_group(id: String) -> GamendResult:
	return await _call_api(AdminGroupsApi.new(_config), "admin_delete_group", [id])

## Update a group (admin)
func admin_groups_admin_update_group(id: String, adminUpdateGroupRequest: GamendAdminUpdateGroupRequest) -> GamendResult:
	return await _call_api(AdminGroupsApi.new(_config), "admin_update_group", [id, adminUpdateGroupRequest])

## List all groups (admin)
func admin_groups_admin_list_groups(
	# title: String = ""   Eg: title_example
	title = "",
	# type: String = ""   Eg: type_example
	type = "",
	# minMembers: int   Eg: 56
	minMembers = null,
	# maxMembers: int   Eg: 56
	maxMembers = null,
	# sortBy: String = ""   Eg: sortBy_example
	sortBy = "",
	# page: int   Eg: 56
	page = null,
	# pageSize: int   Eg: 56
	pageSize = null,) -> GamendResult:
	return await _call_api(AdminGroupsApi.new(_config), "admin_list_groups", [title, type, minMembers, maxMembers, sortBy, page, pageSize])

## ADMIN CHAT

## List all chat messages (admin)
func admin_chat_admin_list_chat_messages(sender_id = null, chat_type = null, chat_ref_id = null, content = null, sort_by = null, page = 1, page_size = 25) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_list_chat_messages", [sender_id, chat_type, chat_ref_id, content, sort_by, page, page_size])

## Delete a chat message (admin)
func admin_chat_admin_delete_chat_message(id: String) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_delete_chat_message", [id])

## Delete all messages in a conversation (admin)
func admin_chat_admin_delete_chat_conversation(chat_type: String, chat_ref_id: String) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_delete_chat_conversation", [chat_type, chat_ref_id])

## ADMIN QUESTS

## List all quest definitions (admin)
func admin_quests_admin_list_quests(page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_list_quests", [page, pageSize])

## Create a quest (admin)
func admin_quests_admin_create_quest(request: GamendAdminCreateQuestRequest) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_create_quest", [request])

## Update a quest (admin)
func admin_quests_admin_update_quest(id: String, request: GamendAdminUpdateQuestRequest) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_update_quest", [id, request])

## Delete a quest and all user progress (admin)
func admin_quests_admin_delete_quest(id: String) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_delete_quest", [id])

## List quest progress rows (admin)
func admin_quests_admin_list_quest_progress(page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_list_quest_progress", [page, pageSize])

## Force-complete a quest for a user (admin)
func admin_quests_admin_grant_quest(request: GamendAdminGrantQuestRequest) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_grant_quest", [request])

## Reset a user's current-period quest progress (admin)
func admin_quests_admin_reset_quest(request: GamendAdminResetQuestRequest) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_reset_quest", [request])

## Claim a completed quest on a user's behalf (admin)
func admin_quests_admin_claim_quest(request: GamendAdminClaimQuestRequest) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_claim_quest", [request])

## Per-status progress counts for one quest (admin)
func admin_quests_admin_quest_funnel(key: String) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_quest_funnel", [key])

# --- Matchmaking ---------------------------------------------------------------

## Join the matchmaking queue.
## match_params is the bucket key — tickets only group when it matches exactly,
## so keep it coarse (mode, region, skill band). A before_matchmaking_join hook
## may rewrite or reject it server-side, so the stored ticket can differ from
## what was sent. Keep the realtime socket connected while queued: tickets of
## users that go offline are cancelled by the sweep.
## The match itself arrives as a `match_found` event on the user channel.
func matchmaking_join(match_params: Dictionary = {}, min_players = null, max_players = null) -> GamendResult:
	var request = GamendMatchmakingJoinRequest.new()
	request.match_params = match_params
	if min_players != null:
		request.min_players = min_players
	if max_players != null:
		request.max_players = max_players
	return await _call_api(MatchmakingApi.new(_config), "matchmaking_join", [request])

## Cancel all of the current user's queued tickets
func matchmaking_cancel() -> GamendResult:
	return await _call_api(MatchmakingApi.new(_config), "matchmaking_cancel", [])

## The current user's queued ticket, or null data when not queued
func matchmaking_my_ticket() -> GamendResult:
	return await _call_api(MatchmakingApi.new(_config), "matchmaking_my_ticket", [])

## Queue depth per match_params (gated by LIST_MATCHMAKING_ENABLED)
func matchmaking_stats() -> GamendResult:
	return await _call_api(MatchmakingApi.new(_config), "matchmaking_stats", [])

## List matchmaking tickets (admin)
func admin_matchmaking_admin_list_matchmaking_tickets(status = null, user_id = null, page = 1, page_size = 25) -> GamendResult:
	return await _call_api(AdminMatchmakingApi.new(_config), "admin_list_matchmaking_tickets", [status, user_id, page, page_size])

## Force-cancel a matchmaking ticket (admin)
func admin_matchmaking_admin_cancel_matchmaking_ticket(id: String) -> GamendResult:
	return await _call_api(AdminMatchmakingApi.new(_config), "admin_cancel_matchmaking_ticket", [id])

## Matchmaking queue statistics (admin)
func admin_matchmaking_admin_matchmaking_stats() -> GamendResult:
	return await _call_api(AdminMatchmakingApi.new(_config), "admin_matchmaking_stats", [])

# --- Metadata / time utilities -------------------------------------------------

## Deep-merge a metadata patch onto existing metadata. Dictionary sections are
## merged one level deep (per-section keys are overwritten); scalars replace.
static func merge_metadata(existing_metadata: Dictionary, patch_metadata: Dictionary) -> Dictionary:
	var merged := existing_metadata.duplicate(true)
	for key in patch_metadata:
		var patch_value = patch_metadata[key]
		var existing_value = merged.get(key, {})
		if patch_value is Dictionary and existing_value is Dictionary:
			var section := (existing_value as Dictionary).duplicate(true)
			for section_key in patch_value:
				section[section_key] = patch_value[section_key]
			merged[key] = section
		else:
			merged[key] = patch_value
	return merged

## Safely read a Dictionary sub-section from metadata; returns {} if absent or
## the value is not a Dictionary.
static func metadata_section(metadata: Dictionary, section_key: String) -> Dictionary:
	var section = metadata.get(section_key, {})
	if section is Dictionary:
		return section
	return {}

## Parse an ISO datetime string (e.g. a user's last_seen_at) to a unix timestamp.
## Returns 0.0 for empty or unparseable input.
static func parse_last_seen(last_seen_str: String) -> float:
	if last_seen_str.is_empty():
		return 0.0
	var dt := Time.get_datetime_dict_from_datetime_string(last_seen_str, false)
	if dt.is_empty():
		return 0.0
	return float(Time.get_unix_time_from_datetime_dict(dt))


# ─────────────────────────────────────────────────────────────────────────
# Everything else the generated APIs expose.
#
# The facade is what callers autocomplete against, so an endpoint missing a
# wrapper here reads as an endpoint that does not exist — which is exactly
# how `set_lobby_state` went unnoticed. Wrapper names are mechanical: the
# class's own prefix plus the generated method name, so any operation in the
# spec can be guessed rather than looked up. Classes whose methods already
# carry their domain (matchmaking_*, payments_*, signaling_*) take no prefix.
# ─────────────────────────────────────────────────────────────────────────


### ADMIN ANALYTICS
## DAU / WAU / MAU, D1 / D7 / D30 and payer conversion (admin)
## Operation adminGetAnalyticsSummary → GET /api/v1/admin/analytics
func admin_analytics_admin_get_analytics_summary() -> GamendResult:
	return await _call_api(AdminAnalyticsApi.new(_config), "admin_get_analytics_summary")


## Per-day active / new users and cohort retention (admin)
## Operation adminGetAnalyticsDaily → GET /api/v1/admin/analytics/daily
func admin_analytics_admin_get_analytics_daily(days = 30) -> GamendResult:
	return await _call_api(AdminAnalyticsApi.new(_config), "admin_get_analytics_daily", [days])


## Currency granted / spent per day per ledger reason (admin)
## Operation adminGetAnalyticsEconomy → GET /api/v1/admin/analytics/economy
func admin_analytics_admin_get_analytics_economy(days = 7, currency = "") -> GamendResult:
	return await _call_api(AdminAnalyticsApi.new(_config), "admin_get_analytics_economy", [days, currency])


## Daily counters by key or prefix (admin)
## Operation adminGetAnalyticsCounts → GET /api/v1/admin/analytics/counts
func admin_analytics_admin_get_analytics_counts(key = "*", days = 7) -> GamendResult:
	return await _call_api(AdminAnalyticsApi.new(_config), "admin_get_analytics_counts", [key, days])


## Live counters: players, lobbies, parties, quests, matchmaking, tournaments (admin)
## Operation adminGetAnalyticsSnapshot → GET /api/v1/admin/analytics/snapshot
func admin_analytics_admin_get_analytics_snapshot() -> GamendResult:
	return await _call_api(AdminAnalyticsApi.new(_config), "admin_get_analytics_snapshot")


### ADMIN CHAT
## Add a blocklist word (admin)
## Operation adminCreateChatFilterWord → POST /api/v1/admin/chat/filter_words
func admin_chat_admin_create_chat_filter_word(adminCreateChatFilterWordRequest = null) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_create_chat_filter_word", [adminCreateChatFilterWordRequest])


## Mute a player (admin)
## Operation adminCreateChatMute → POST /api/v1/admin/chat/mutes
func admin_chat_admin_create_chat_mute(adminCreateChatMuteRequest = null) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_create_chat_mute", [adminCreateChatMuteRequest])


## Remove a blocklist word (admin)
## Operation adminDeleteChatFilterWord → DELETE /api/v1/admin/chat/filter_words/{id}
func admin_chat_admin_delete_chat_filter_word(id: String) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_delete_chat_filter_word", [id])


## Remove an imported word list (admin)
## Operation adminDeleteChatFilterWordsByLang → DELETE /api/v1/admin/chat/filter_words
func admin_chat_admin_delete_chat_filter_words_by_lang(lang: String) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_delete_chat_filter_words_by_lang", [lang])


## Lift a mute (admin)
## Operation adminDeleteChatMute → DELETE /api/v1/admin/chat/mutes/{id}
func admin_chat_admin_delete_chat_mute(id: String) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_delete_chat_mute", [id])


## Delete a chat report (admin)
## Operation adminDeleteChatReport → DELETE /api/v1/admin/chat/reports/{id}
func admin_chat_admin_delete_chat_report(id: String) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_delete_chat_report", [id])


## Import a bundled word list (admin)
## Operation adminImportChatFilterWords → POST /api/v1/admin/chat/filter_words/import
func admin_chat_admin_import_chat_filter_words(adminImportChatFilterWordsRequest = null) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_import_chat_filter_words", [adminImportChatFilterWordsRequest])


## List blocklist words (admin)
## Operation adminListChatFilterWords → GET /api/v1/admin/chat/filter_words
func admin_chat_admin_list_chat_filter_words(word = "", severity = "", lang = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_list_chat_filter_words", [word, severity, lang, page, pageSize])


## Languages with a bundled word list (admin)
## Operation adminListChatFilterLanguages → GET /api/v1/admin/chat/filter_words/languages
func admin_chat_admin_list_chat_filter_languages() -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_list_chat_filter_languages")


## List chat mutes (admin)
## Operation adminListChatMutes → GET /api/v1/admin/chat/mutes
func admin_chat_admin_list_chat_mutes(userId = null, scope = "", scopeRefId = null, active = null, page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_list_chat_mutes", [userId, scope, scopeRefId, active, page, pageSize])


## List chat reports (admin)
## Operation adminListChatReports → GET /api/v1/admin/chat/reports
func admin_chat_admin_list_chat_reports(status = "", reportedUserId = null, reporterId = null, page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_list_chat_reports", [status, reportedUserId, reporterId, page, pageSize])


## Resolve a chat report (admin)
## Operation adminResolveChatReport → POST /api/v1/admin/chat/reports/{id}/resolve
func admin_chat_admin_resolve_chat_report(id: String, adminResolveChatReportRequest = null) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_resolve_chat_report", [id, adminResolveChatReportRequest])


## Test a phrase against the filter (admin)
## Operation adminTestChatPhrase → POST /api/v1/admin/chat/filter_words/test
func admin_chat_admin_test_chat_phrase(adminTestChatPhraseRequest = null) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_test_chat_phrase", [adminTestChatPhraseRequest])


## Update a blocklist word (admin)
## Operation adminUpdateChatFilterWord → PATCH /api/v1/admin/chat/filter_words/{id}
func admin_chat_admin_update_chat_filter_word(id: String, adminUpdateChatFilterWordRequest = null) -> GamendResult:
	return await _call_api(AdminChatApi.new(_config), "admin_update_chat_filter_word", [id, adminUpdateChatFilterWordRequest])


### ADMIN ECONOMY
## Consume items from a user (admin)
## Operation adminConsumeItem → POST /api/v1/admin/economy/consume_item
func admin_economy_admin_consume_item() -> GamendResult:
	return await _call_api(AdminEconomyApi.new(_config), "admin_consume_item")


## Grant currency to a user (admin)
## Operation adminGrantCurrency → POST /api/v1/admin/economy/grant
func admin_economy_admin_grant_currency(adminSpendCurrencyRequest = null) -> GamendResult:
	return await _call_api(AdminEconomyApi.new(_config), "admin_grant_currency", [adminSpendCurrencyRequest])


## Grant items to a user (admin)
## Operation adminGrantItem → POST /api/v1/admin/economy/grant_item
func admin_economy_admin_grant_item(adminGrantItemRequest = null) -> GamendResult:
	return await _call_api(AdminEconomyApi.new(_config), "admin_grant_item", [adminGrantItemRequest])


## List inventory item stacks (admin)
## Operation adminListInventory → GET /api/v1/admin/economy/items
func admin_economy_admin_list_inventory(userId = null, item = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminEconomyApi.new(_config), "admin_list_inventory", [userId, item, page, pageSize])


## List ledger entries (admin)
## Operation adminListLedger → GET /api/v1/admin/economy/ledger
func admin_economy_admin_list_ledger(userId = null, currency = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminEconomyApi.new(_config), "admin_list_ledger", [userId, currency, page, pageSize])


## List wallets (admin)
## Operation adminListWallets → GET /api/v1/admin/economy/wallets
func admin_economy_admin_list_wallets(userId = null, currency = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminEconomyApi.new(_config), "admin_list_wallets", [userId, currency, page, pageSize])


## Spend currency from a user (admin)
## Operation adminSpendCurrency → POST /api/v1/admin/economy/spend
func admin_economy_admin_spend_currency(adminSpendCurrencyRequest = null) -> GamendResult:
	return await _call_api(AdminEconomyApi.new(_config), "admin_spend_currency", [adminSpendCurrencyRequest])


### ADMIN LEADERBOARDS
## Request an upload ticket for a leaderboard icon (admin)
## Operation adminLeaderboardIconUploadUrl → POST /api/v1/admin/leaderboards/{id}/icon/upload_url
func admin_leaderboards_admin_leaderboard_icon_upload_url(id: String, request = null) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_leaderboard_icon_upload_url", [id, request])


## Confirm an uploaded leaderboard icon (admin)
## Operation adminSetLeaderboardIcon → POST /api/v1/admin/leaderboards/{id}/icon
func admin_leaderboards_admin_set_leaderboard_icon(id: String, request = null) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_set_leaderboard_icon", [id, request])


### ADMIN PUSH
## Delete a device push token (admin)
## Operation adminDeletePushToken → DELETE /api/v1/admin/push/tokens/{id}
func admin_push_admin_delete_push_token(id: String) -> GamendResult:
	return await _call_api(AdminPushApi.new(_config), "admin_delete_push_token", [id])


## List registered device push tokens (admin)
## Operation adminListPushTokens → GET /api/v1/admin/push/tokens
func admin_push_admin_list_push_tokens(userId = null, platform = "", provider = "", status = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminPushApi.new(_config), "admin_list_push_tokens", [userId, platform, provider, status, page, pageSize])


## Send a push notification to a user (admin)
## Operation adminSendPush → POST /api/v1/admin/push/send
func admin_push_admin_send_push(adminSendPushRequest = null) -> GamendResult:
	return await _call_api(AdminPushApi.new(_config), "admin_send_push", [adminSendPushRequest])


### ADMIN QUESTS
## Request an upload ticket for a quest icon (admin)
## Operation adminQuestIconUploadUrl → POST /api/v1/admin/quests/{id}/icon/upload_url
func admin_quests_admin_quest_icon_upload_url(id: String, request = null) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_quest_icon_upload_url", [id, request])


## Confirm an uploaded quest icon (admin)
## Operation adminSetQuestIcon → POST /api/v1/admin/quests/{id}/icon
func admin_quests_admin_set_quest_icon(id: String, request = null) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_set_quest_icon", [id, request])


### ADMIN READY CHECKS
## Force-cancel a pending ready check (admin)
## Operation adminCancelReadyCheck → DELETE /api/v1/admin/ready_checks/{id}
func admin_ready_checks_admin_cancel_ready_check(id: String) -> GamendResult:
	return await _call_api(AdminReadyChecksApi.new(_config), "admin_cancel_ready_check", [id])


## List ready checks (admin)
## Operation adminListReadyChecks → GET /api/v1/admin/ready_checks
func admin_ready_checks_admin_list_ready_checks(status = "", kind = "", lobbyId = null, page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminReadyChecksApi.new(_config), "admin_list_ready_checks", [status, kind, lobbyId, page, pageSize])


## Ready check outcomes over the last 24 hours (admin)
## Operation adminReadyCheckStats → GET /api/v1/admin/ready_checks/stats
func admin_ready_checks_admin_ready_check_stats() -> GamendResult:
	return await _call_api(AdminReadyChecksApi.new(_config), "admin_ready_check_stats")


### ADMIN RETENTION
## Last retention sweep (admin)
## Operation adminGetRetentionStatus → GET /api/v1/admin/retention
func admin_retention_admin_get_retention_status() -> GamendResult:
	return await _call_api(AdminRetentionApi.new(_config), "admin_get_retention_status")


## Run a retention sweep now (admin)
## Operation adminRunRetention → POST /api/v1/admin/retention/run
func admin_retention_admin_run_retention() -> GamendResult:
	return await _call_api(AdminRetentionApi.new(_config), "admin_run_retention")


### ADMIN STORAGE
## Delete a stored object (admin)
## Operation adminDeleteStorageObject → DELETE /api/v1/admin/storage
func admin_storage_admin_delete_storage_object(key: String) -> GamendResult:
	return await _call_api(AdminStorageApi.new(_config), "admin_delete_storage_object", [key])


## Download an object by key (admin)
## Operation adminDownloadStorageObject → GET /api/v1/admin/storage/object
func admin_storage_admin_download_storage_object(key: String) -> GamendResult:
	return await _call_api(AdminStorageApi.new(_config), "admin_download_storage_object", [key])


## List stored objects with usage (admin)
## Operation adminListStorageObjects → GET /api/v1/admin/storage
func admin_storage_admin_list_storage_objects(prefix = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminStorageApi.new(_config), "admin_list_storage_objects", [prefix, page, pageSize])


## Objects and bytes stored under a prefix (admin)
## Operation adminStorageUsage → GET /api/v1/admin/storage/usage
func admin_storage_admin_storage_usage(prefix = "") -> GamendResult:
	return await _call_api(AdminStorageApi.new(_config), "admin_storage_usage", [prefix])


## Upload or overwrite an object at any key (admin)
## Operation adminUploadStorageObject → PUT /api/v1/admin/storage/object
func admin_storage_admin_upload_storage_object(key: String, body = null) -> GamendResult:
	return await _call_api(AdminStorageApi.new(_config), "admin_upload_storage_object", [key, body])


### ADMIN TOURNAMENTS
## Cancel tournament (admin; terminal, no recurrence spawn)
## Operation adminCancelTournament → POST /api/v1/admin/tournaments/{id}/cancel
func admin_tournaments_admin_cancel_tournament(id: String) -> GamendResult:
	return await _call_api(AdminTournamentsApi.new(_config), "admin_cancel_tournament", [id])


## Create tournament (admin)
## Operation adminCreateTournament → POST /api/v1/admin/tournaments
func admin_tournaments_admin_create_tournament(adminUpdateTournamentRequest = null) -> GamendResult:
	return await _call_api(AdminTournamentsApi.new(_config), "admin_create_tournament", [adminUpdateTournamentRequest])


## Delete tournament and all its entries/matches (admin)
## Operation adminDeleteTournament → DELETE /api/v1/admin/tournaments/{id}
func admin_tournaments_admin_delete_tournament(id: String) -> GamendResult:
	return await _call_api(AdminTournamentsApi.new(_config), "admin_delete_tournament", [id])


## Draw the bracket now (admin; pulls starts_at to now)
## Operation adminDrawTournament → POST /api/v1/admin/tournaments/{id}/draw
func admin_tournaments_admin_draw_tournament(id: String) -> GamendResult:
	return await _call_api(AdminTournamentsApi.new(_config), "admin_draw_tournament", [id])


## Finish tournament now (admin; pulls ends_at to now)
## Operation adminFinishTournament → POST /api/v1/admin/tournaments/{id}/finish
func admin_tournaments_admin_finish_tournament(id: String) -> GamendResult:
	return await _call_api(AdminTournamentsApi.new(_config), "admin_finish_tournament", [id])


## Reopen a cancelled tournament (admin)
## Operation adminReopenTournament → POST /api/v1/admin/tournaments/{id}/reopen
func admin_tournaments_admin_reopen_tournament(id: String) -> GamendResult:
	return await _call_api(AdminTournamentsApi.new(_config), "admin_reopen_tournament", [id])


## Force a match verdict (admin)
## Operation adminResolveTournamentMatch → POST /api/v1/admin/tournaments/{id}/matches/{match_id}/resolve
func admin_tournaments_admin_resolve_tournament_match(id: String, matchId: String, adminResolveTournamentMatchRequest = null) -> GamendResult:
	return await _call_api(AdminTournamentsApi.new(_config), "admin_resolve_tournament_match", [id, matchId, adminResolveTournamentMatchRequest])


## Confirm an uploaded tournament icon (admin)
## Operation adminSetTournamentIcon → POST /api/v1/admin/tournaments/{id}/icon
func admin_tournaments_admin_set_tournament_icon(id: String, request = null) -> GamendResult:
	return await _call_api(AdminTournamentsApi.new(_config), "admin_set_tournament_icon", [id, request])


## Request an upload ticket for a tournament icon (admin)
## Operation adminTournamentIconUploadUrl → POST /api/v1/admin/tournaments/{id}/icon/upload_url
func admin_tournaments_admin_tournament_icon_upload_url(id: String, request = null) -> GamendResult:
	return await _call_api(AdminTournamentsApi.new(_config), "admin_tournament_icon_upload_url", [id, request])


## Update tournament (admin)
## Operation adminUpdateTournament → PATCH /api/v1/admin/tournaments/{id}
func admin_tournaments_admin_update_tournament(id: String, adminUpdateTournamentRequest = null) -> GamendResult:
	return await _call_api(AdminTournamentsApi.new(_config), "admin_update_tournament", [id, adminUpdateTournamentRequest])


### AUTHENTICATION
## List sign-in providers
## Operation listAuthProviders → GET /api/v1/auth/providers
func authenticate_list_auth_providers() -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "list_auth_providers")


## Google ID token login (native/mobile)
## Operation oauthGoogleIdToken → POST /api/v1/auth/google/id_token
func authenticate_oauth_google_id_token(oauthGoogleIdTokenRequest = null) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "oauth_google_id_token", [oauthGoogleIdTokenRequest])


### CHAT
## List active mutes in a group
## Operation listGroupMutes → GET /api/v1/groups/{id}/mutes
func chat_list_group_mutes(id: String, page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "list_group_mutes", [id, page, pageSize])


## List active mutes in your lobby
## Operation listLobbyMutes → GET /api/v1/lobbies/mutes
func chat_list_lobby_mutes(page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "list_lobby_mutes", [page, pageSize])


## List active mutes in your party
## Operation listPartyMutes → GET /api/v1/parties/mutes
func chat_list_party_mutes(page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "list_party_mutes", [page, pageSize])


## Mute a player in a group
## Operation muteGroupMember → POST /api/v1/groups/{id}/mute
func chat_mute_group_member(id: String, muteGroupMemberRequest = null) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "mute_group_member", [id, muteGroupMemberRequest])


## Mute a player in your lobby
## Operation muteLobbyMember → POST /api/v1/lobbies/mute
func chat_mute_lobby_member(muteGroupMemberRequest = null) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "mute_lobby_member", [muteGroupMemberRequest])


## Mute a player in your party
## Operation mutePartyMember → POST /api/v1/parties/mute
func chat_mute_party_member(muteGroupMemberRequest = null) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "mute_party_member", [muteGroupMemberRequest])


## Report a chat message
## Operation reportChatMessage → POST /api/v1/chat/messages/{id}/report
func chat_report_chat_message(id: String, reportChatMessageRequest = null) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "report_chat_message", [id, reportChatMessageRequest])


## Lift a mute in a group
## Operation unmuteGroupMember → POST /api/v1/groups/{id}/unmute
func chat_unmute_group_member(id: String, unmuteLobbyMemberRequest = null) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "unmute_group_member", [id, unmuteLobbyMemberRequest])


## Lift a mute in your lobby
## Operation unmuteLobbyMember → POST /api/v1/lobbies/unmute
func chat_unmute_lobby_member(unmuteLobbyMemberRequest = null) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "unmute_lobby_member", [unmuteLobbyMemberRequest])


## Lift a mute in your party
## Operation unmutePartyMember → POST /api/v1/parties/unmute
func chat_unmute_party_member(unmuteLobbyMemberRequest = null) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "unmute_party_member", [unmuteLobbyMemberRequest])


### ECONOMY
## Current user's item quantities
## Operation getCurrentUserInventory → GET /api/v1/me/inventory
func economy_get_current_user_inventory() -> GamendResult:
	return await _call_api(EconomyApi.new(_config), "get_current_user_inventory")


## Current user's currency balances
## Operation getCurrentUserWallet → GET /api/v1/me/wallet
func economy_get_current_user_wallet() -> GamendResult:
	return await _call_api(EconomyApi.new(_config), "get_current_user_wallet")


## Current user's ledger history
## Operation listCurrentUserLedger → GET /api/v1/me/wallet/ledger
func economy_list_current_user_ledger(currency = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(EconomyApi.new(_config), "list_current_user_ledger", [currency, page, pageSize])


### FRIENDS
## Blacklist a user, with or without an existing friendship
## Operation blockUser → POST /api/v1/users/{user_id}/block
func friends_block_user(userId: String) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "block_user", [userId])


## List the users you've blocked
## Operation listBlacklistedUsers → GET /api/v1/me/blacklist
func friends_list_blacklisted_users(page = null, pageSize = null) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "list_blacklisted_users", [page, pageSize])


## Remove a user from your blacklist
## Operation unblockUser → POST /api/v1/users/{user_id}/unblock
func friends_unblock_user(userId: String) -> GamendResult:
	return await _call_api(FriendsApi.new(_config), "unblock_user", [userId])


### GROUPS
## Request a group icon upload ticket (admin only)
## Operation createGroupIconUploadUrl → POST /api/v1/groups/{id}/icon/upload_url
func groups_create_group_icon_upload_url(id: String, request = null) -> GamendResult:
	return await _call_api(GroupsApi.new(_config), "create_group_icon_upload_url", [id, request])


## Confirm an uploaded group icon (admin only)
## Operation setGroupIcon → POST /api/v1/groups/{id}/icon
func groups_set_group_icon(id: String, request = null) -> GamendResult:
	return await _call_api(GroupsApi.new(_config), "set_group_icon", [id, request])


### LOBBIES
## Lobby counts
## Operation lobbyStats → GET /api/v1/lobbies/stats
func lobbies_lobby_stats() -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "lobby_stats")


### PARTIES
## Party counts
## Operation partyStats → GET /api/v1/parties/stats
func parties_party_stats() -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "party_stats")


### PAYMENTS
## The three provider webhooks below (apple / google / stripe) are wrapped for
## the same reason they are in the spec: every /api/v1 route is documented, and
## a self-hoster configuring a provider dashboard needs to know these URLs
## exist. No game client is the caller, though — Stripe, Google and Apple POST
## to them and the signature check is what authenticates, so calling one from
## here could only forge an event that gets thrown out.
## Receive App Store Server Notification v2 events
## Operation paymentsAppleWebhook → POST /api/v1/payments/webhooks/apple
func payments_apple_webhook(body = null) -> GamendResult:
	return await _call_api(PaymentsApi.new(_config), "payments_apple_webhook", [body])


## Receive Google Play Developer Notification events
## Operation paymentsGoogleWebhook → POST /api/v1/payments/webhooks/google
func payments_google_webhook(body = null) -> GamendResult:
	return await _call_api(PaymentsApi.new(_config), "payments_google_webhook", [body])


## Receive Stripe webhook events
## Operation paymentsStripeWebhook → POST /api/v1/payments/webhooks/stripe
func payments_stripe_webhook(body = null) -> GamendResult:
	return await _call_api(PaymentsApi.new(_config), "payments_stripe_webhook", [body])


## List active payment catalog entries
## Operation paymentsCatalog → GET /api/v1/payments/catalog
func payments_catalog(provider = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(PaymentsApi.new(_config), "payments_catalog", [provider, page, pageSize])


## List current user's active entitlements
## Operation paymentsEntitlements → GET /api/v1/payments/entitlements
func payments_entitlements(page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(PaymentsApi.new(_config), "payments_entitlements", [page, pageSize])


## Create a Steam MicroTxn transaction
## Operation paymentsSteamCheckout → POST /api/v1/payments/checkout/steam
func payments_steam_checkout(paymentsSteamCheckoutRequest = null) -> GamendResult:
	return await _call_api(PaymentsApi.new(_config), "payments_steam_checkout", [paymentsSteamCheckoutRequest])


## Finalize an authorized Steam MicroTxn transaction
## Operation paymentsSteamFinalize → POST /api/v1/payments/steam/finalize
func payments_steam_finalize(paymentsSteamFinalizeRequest = null) -> GamendResult:
	return await _call_api(PaymentsApi.new(_config), "payments_steam_finalize", [paymentsSteamFinalizeRequest])


## Create a Stripe Checkout Session
## Operation paymentsStripeCheckout → POST /api/v1/payments/checkout/stripe
func payments_stripe_checkout(paymentsStripeCheckoutRequest = null) -> GamendResult:
	return await _call_api(PaymentsApi.new(_config), "payments_stripe_checkout", [paymentsStripeCheckoutRequest])


## Validate an Apple, Google, or Steam purchase
## Operation paymentsValidateStorePurchase → POST /api/v1/payments/validate/{provider}
func payments_validate_store_purchase(provider: String, requestBody = null) -> GamendResult:
	return await _call_api(PaymentsApi.new(_config), "payments_validate_store_purchase", [provider, requestBody])


### PUSH
## Unregister one of the current user's devices
## Operation deletePushToken → DELETE /api/v1/me/push_tokens/{id}
func push_delete_push_token(id: String) -> GamendResult:
	return await _call_api(PushApi.new(_config), "delete_push_token", [id])


## List the current user's registered devices
## Operation listPushTokens → GET /api/v1/me/push_tokens
func push_list_push_tokens(page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(PushApi.new(_config), "list_push_tokens", [page, pageSize])


## Register a device push token
## Operation registerPushToken → POST /api/v1/me/push_tokens
func push_register_push_token(registerPushTokenRequest = null) -> GamendResult:
	return await _call_api(PushApi.new(_config), "register_push_token", [registerPushTokenRequest])


### QUESTS
## Quest progress counts
## Operation questStats → GET /api/v1/quests/stats
func quests_quest_stats() -> GamendResult:
	return await _call_api(QuestsApi.new(_config), "quest_stats")


### CLIENT LOGS
## Client log capture policy
## Operation getClientLogPolicy → GET /api/v1/client_logs/policy
func client_logs_get_client_log_policy() -> GamendResult:
	return await _call_api(ClientLogsApi.new(_config), "get_client_log_policy")


## Upload a batch of client log entries
## Operation uploadClientLogs → POST /api/v1/client_logs
func client_logs_upload_client_logs(client_log_batch: GamendClientLogBatch) -> GamendResult:
	return await _call_api(ClientLogsApi.new(_config), "upload_client_logs", [client_log_batch])


### STATS
## All public server counters in one call
## Operation getStats → GET /api/v1/stats
func stats_get_stats() -> GamendResult:
	return await _call_api(StatsApi.new(_config), "get_stats", [])


### SIGNALING
## WebRTC room counts
## Operation signalingStats → GET /api/v1/signaling/stats
func signaling_stats() -> GamendResult:
	return await _call_api(SignalingApi.new(_config), "signaling_stats")


### TOURNAMENTS
## Tournament details (with the caller's participation when authenticated)
## Operation getTournament → GET /api/v1/tournaments/{id}
func tournaments_get_tournament(id: String) -> GamendResult:
	return await _call_api(TournamentsApi.new(_config), "get_tournament", [id])


## Register as an entry leader
## Operation joinTournament → POST /api/v1/tournaments/{id}/join
func tournaments_join_tournament(id: String) -> GamendResult:
	return await _call_api(TournamentsApi.new(_config), "join_tournament", [id])


## Withdraw the caller's entry (before the draw)
## Operation leaveTournament → DELETE /api/v1/tournaments/{id}/join
func tournaments_leave_tournament(id: String) -> GamendResult:
	return await _call_api(TournamentsApi.new(_config), "leave_tournament", [id])


## List tournaments
## Operation listTournaments → GET /api/v1/tournaments
func tournaments_list_tournaments(state = "", slug = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(TournamentsApi.new(_config), "list_tournaments", [state, slug, page, pageSize])


## Brackets and their matches (paginated by bracket)
## Operation tournamentBracket → GET /api/v1/tournaments/{id}/bracket
func tournaments_tournament_bracket(id: String, index = null, page = 1, pageSize = 10) -> GamendResult:
	return await _call_api(TournamentsApi.new(_config), "tournament_bracket", [id, index, page, pageSize])


## Registered entries (paginated)
## Operation tournamentEntries → GET /api/v1/tournaments/{id}/entries
func tournaments_tournament_entries(id: String, state = "", page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(TournamentsApi.new(_config), "tournament_entries", [id, state, page, pageSize])


## The caller's current unresolved match, if any
## Operation tournamentMyMatch → GET /api/v1/tournaments/{id}/my_match
func tournaments_tournament_my_match(id: String) -> GamendResult:
	return await _call_api(TournamentsApi.new(_config), "tournament_my_match", [id])


## Placements, wins and champions
## Operation tournamentStandings → GET /api/v1/tournaments/{id}/standings
func tournaments_tournament_standings(id: String) -> GamendResult:
	return await _call_api(TournamentsApi.new(_config), "tournament_standings", [id])


### USERS
## Request an avatar upload ticket
## Operation createCurrentUserAvatarUploadUrl → POST /api/v1/me/avatar/upload_url
func user_create_current_user_avatar_upload_url(createCurrentUserAvatarUploadUrlRequest = null) -> GamendResult:
	return await _call_api(UsersApi.new(_config), "create_current_user_avatar_upload_url", [createCurrentUserAvatarUploadUrlRequest])


## Confirm an uploaded avatar
## Operation setCurrentUserAvatar → POST /api/v1/me/avatar
func user_set_current_user_avatar(request = null) -> GamendResult:
	return await _call_api(UsersApi.new(_config), "set_current_user_avatar", [request])


## Player counts
## Operation userStats → GET /api/v1/users/stats
func user_user_stats() -> GamendResult:
	return await _call_api(UsersApi.new(_config), "user_stats")
