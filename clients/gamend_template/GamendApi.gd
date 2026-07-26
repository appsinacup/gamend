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
var _realtime: GamendRealtime
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
	_config.log_level = ApiApiConfigClient.LogLevel.INFO
	_config.port = port
	_config.polling_interval_ms = 1
	_config.headers_override["Connection"] = "keep-alive"
	_ensure_http_client_pool()
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
	if data && method_name in ["oauth_session_status", "oauth_api_callback", "login", "device_login", "refresh_token", "oauth_callback_api_apple_ios"]:
		data = data.bzz_normalize().get("data").bzz_normalize()
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
	_realtime = GamendRealtime.new(_get_realtime_access_token, protocol + _config.host + ":" + str(_config.port) + "/socket", realtime_format)
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
		"GamendRealtime.start timed out after %.1fs" % http_request_timeout_sec,
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

### HEALTH

## Health check
func health_index() -> GamendResult:
	return await _call_api(HealthApi.new(_config), "index")

### HOOKS

## Invoke a hook function via HTTP
func hooks_call_hook(hook_request: CallHookRequest) -> GamendResult:
	return await _call_api(HooksApi.new(_config), "call_hook", [hook_request])

## Invoke a hook function via WebSocket push. Fire-and-forget.
## If topic is empty, pushes on the user channel.
func hooks_call_hook_ws(plugin: String, fn_name: String, args: Array = [], topic: String = "") -> bool:
	if not _realtime:
		return false
	return _realtime.call_hook(plugin, fn_name, args, topic)

## List available hook functions
func hooks_list_hooks() -> GamendResult:
	return await _call_api(HooksApi.new(_config), "list_hooks", [])

### USERS

## Delete current user
func user_delete_current_user() -> GamendResult:
	return await _call_api(UsersApi.new(_config), "delete_current_user")

## Get current user info
func users_get_current_user() -> GamendResult:
	return await _call_api(UsersApi.new(_config), "get_current_user")

## Update current user's display name
func user_update_current_user_display_name(display_name: String) -> GamendResult:
	var request := UpdateCurrentUserDisplayNameRequest.new()
	request.display_name = display_name
	return await _call_api(UsersApi.new(_config), "update_current_user_display_name", [request])

## Update current user's unique username handle (lowercased on save; 3-32 chars
## of a-z, 0-9 and non-consecutive . _ - separators). Fails when taken/invalid.
func user_update_current_user_username(username: String) -> GamendResult:
	var request := UpdateCurrentUserUsernameRequest.new()
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
func authenticate_oauth_api_callback(provider: String, callback_request: OauthApiCallbackRequest) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "oauth_api_callback", [provider, callback_request])

## Apple Callback (native iOS)
func authenticate_oauth_callback_api_apple_ios(ios_request: OauthCallbackApiAppleIosRequest) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "oauth_callback_api_apple_ios", [ios_request])

## Login
func authenticate_login(login_request: LoginRequest) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "login", [login_request])

## Device login
func authenticate_device_login(device_id: String) -> GamendResult:
	var device_login := DeviceLoginRequest.new()
	device_login.device_id = device_id
	return await _call_api(AuthenticationApi.new(_config), "device_login", [device_login])

## Logout
func authenticate_logout() -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "logout")

## Unlink OAuth provider
func authenticate_unlink_provider(provider: String) -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "unlink_provider", [provider])

## Unlink device
func authenticate_unlink_device() -> GamendResult:
	return await _call_api(AuthenticationApi.new(_config), "unlink_device", [])

## Link device
func authenticate_link_device(device_id: String) -> GamendResult:
	var linkDeviceRequest:= LinkDeviceRequest.new()
	linkDeviceRequest.device_id = device_id
	return await _call_api(AuthenticationApi.new(_config), "link_device", [linkDeviceRequest])

## Refresh access token
func authenticate_refresh_token(refresh_token: String) -> GamendResult:
	var refresh_param:= RefreshTokenRequest.new()
	refresh_param.refresh_token = refresh_token
	return await _call_api(AuthenticationApi.new(_config), "refresh_token", [refresh_param])

### FRIENDS

## Send a friend request
func friends_create_friend_request(friend_request: CreateFriendRequestRequest) -> GamendResult:
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
func lobbies_update_lobby(update_request: UpdateLobbyRequest) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "update_lobby", [update_request])

## Create a lobby
func lobbies_create_lobby(create_request: CreateLobbyRequest) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "create_lobby", [create_request])

## Kick a user from the lobby (host only)
func lobbies_kick_user(kick_request: KickPartyMemberRequest) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "kick_user", [kick_request])

## Leave the current lobby
func lobbies_leave_lobby() -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "leave_lobby")

## Quick-join or create a lobby
func lobbies_quick_join(quick_request: QuickJoinRequest) -> GamendResult:
	return await _call_api(LobbiesApi.new(_config), "quick_join", [quick_request])

## Join a lobby
func lobbies_join_lobby(id: String, join_request: PartyJoinLobbyRequest = null) -> GamendResult:
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
	var request = ResolveLeaderboardSlugsRequest.new()
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
		if result.error.response_code not in [
			HTTPClient.RESPONSE_BAD_REQUEST,
			HTTPClient.RESPONSE_FORBIDDEN,
			HTTPClient.RESPONSE_NOT_FOUND,
		]:
			network_request_failed.emit(result.error.message)
	return result

### QUESTS

## List my quests with progress and claimable flag (auth required)
func quests_my_quests(kind = "", page = 1, page_size = 25) -> GamendResult:
	return await _call_api(QuestsApi.new(_config), "my_quests", [kind, page, page_size])

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
func chat_send_chat_message(sendChatMessageRequest: SendChatMessageRequest) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "send_chat_message", [sendChatMessageRequest])

## Update (edit) a chat message by ID
func chat_update_chat_message(id: String, content: String, metadata: Dictionary = {}) -> GamendResult:
	var request = UpdateChatMessageRequest.new()
	request.content = content
	if not metadata.is_empty():
		request.metadata = metadata
	return await _call_api(ChatApi.new(_config), "update_chat_message", [id, request])

## Delete a chat message by ID
func chat_delete_chat_message(id: String) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "delete_chat_message", [id])

## Mark a chat conversation as read up to a given message ID
func chat_mark_chat_read(markChatReadRequest: MarkChatReadRequest) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "mark_chat_read", [markChatReadRequest])

## Get unread message count for a chat conversation
func chat_chat_unread_count(chat_type: String, chat_ref_id: String) -> GamendResult:
	return await _call_api(ChatApi.new(_config), "chat_unread_count", [chat_type, chat_ref_id])

## NOTIFICATIONS

## Delete notifications by IDs
func notifications_delete_notifications(deleteNotificationsRequest: DeleteNotificationsRequest) -> GamendResult:
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
func notifications_send_notification(sendNotificationRequest: SendNotificationRequest) -> GamendResult:
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
func groups_create_group(createGroupRequest: CreateGroupRequest):
	return await _call_api(GroupsApi.new(_config), "create_group", [createGroupRequest])

## Demote admin to member
func groups_demote_group_member(
	# id: int   Eg: 56
	# Group ID
	id: String,
	# demoteGroupMemberRequest: DemoteGroupMemberRequest
	# Demote parameters
	demoteGroupMemberRequest: DemoteGroupMemberRequest,):
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
	inviteToGroupRequest: InviteToGroupRequest):
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
	kickGroupMemberRequest: KickGroupMemberRequest):
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

## Send a notification to all group members
func groups_notify_group(
	# id: int   Eg: 56
	# Group ID
	id: String,
	notifyGroupRequest: NotifyGroupRequest):
	return await _call_api(GroupsApi.new(_config), "notify_group", [id, notifyGroupRequest])

## Promote member to admin
func groups_promote_group_member(
	# id: int   Eg: 56
	# Group ID
	id: String,
	promoteGroupMemberRequest: PromoteGroupMemberRequest):
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
	updateGroupRequest: UpdateGroupRequest):
	return await _call_api(GroupsApi.new(_config), "update_group", [id, updateGroupRequest])

## READY CHECKS

## The caller's open ready checks, one per lane: {lobby: check|null, party: check|null}
func ready_checks_get_mine() -> GamendResult:
	return await _call_api(ReadyChecksApi.new(_config), "get_my_ready_check", [])

## Answer the open check in one lane ("lobby" also answers a matchmaking accept)
func ready_checks_respond(ready: bool, scope: String = "lobby") -> GamendResult:
	var request := RespondReadyCheckRequest.new()
	request.ready = ready
	request.scope = scope
	return await _call_api(ReadyChecksApi.new(_config), "respond_ready_check", [request])

## Open (or reset) the lobby board — host only; pass timeout_ms to force ready
func ready_checks_open_lobby(request: OpenLobbyReadyCheckRequest = null) -> GamendResult:
	return await _call_api(ReadyChecksApi.new(_config), "open_lobby_ready_check", [request])

## Call off the lobby board — host only
func ready_checks_cancel_lobby() -> GamendResult:
	return await _call_api(ReadyChecksApi.new(_config), "cancel_lobby_ready_check", [])

## Open (or reset) the party board — leader only; pass timeout_ms to force ready
## (the request schema is shared with the lobby variant)
func ready_checks_open_party(request: OpenLobbyReadyCheckRequest = null) -> GamendResult:
	return await _call_api(ReadyChecksApi.new(_config), "open_party_ready_check", [request])

## Call off the party board — leader only
func ready_checks_cancel_party() -> GamendResult:
	return await _call_api(ReadyChecksApi.new(_config), "cancel_party_ready_check", [])

## PARTIES

## Create a party
func parties_create_party(createPartyRequest: CreatePartyRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "create_party", [createPartyRequest])

## Invite a user to the party (leader only)
func parties_invite_to_party(inviteToPartyRequest: InviteToPartyRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "invite_to_party", [inviteToPartyRequest])

## Cancel a pending party invite (leader only)
func parties_cancel_party_invite(cancelPartyInviteRequest: CancelPartyInviteRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "cancel_party_invite", [cancelPartyInviteRequest])

## Accept a party invite
func parties_accept_party_invite(acceptPartyInviteRequest: AcceptPartyInviteRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "accept_party_invite", [acceptPartyInviteRequest])

## Decline a party invite
func parties_decline_party_invite(declinePartyInviteRequest: DeclinePartyInviteRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "decline_party_invite", [declinePartyInviteRequest])

## List pending party invites for the current user
func parties_list_party_invitations() -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "list_party_invitations", [])

## List pending party invites sent by the current leader
func parties_list_sent_party_invitations() -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "list_sent_party_invitations", [])

## Kick a member from the party (leader only)
func parties_kick_party_member(kickUserRequest: KickPartyMemberRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "kick_party_member", [kickUserRequest])

## Leave the current party
func parties_leave_party() -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "leave_party", [])

## Create a lobby with the party (leader only)
func parties_party_create_lobby(partyCreateLobbyRequest: PartyCreateLobbyRequest) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "party_create_lobby", [partyCreateLobbyRequest])

## Join a lobby with the party (leader only)
func parties_party_join_lobby(
	# id: int   Eg: 56
	# Lobby ID
	id: String,
	partyJoinLobbyRequest: PartyJoinLobbyRequest,) -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "party_join_lobby", [id, partyJoinLobbyRequest])

## Get current party
func parties_show_party() -> GamendResult:
	return await _call_api(PartiesApi.new(_config), "show_party", [])

## Update party settings (leader only)
func parties_update_party(updatePartyRequest: UpdatePartyRequest) -> GamendResult:
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
func admin_users_admin_update_user(id: String, admin_update_user_request: AdminUpdateUserRequest) -> GamendResult:
	return await _call_api(AdminUsersApi.new(_config), "admin_update_user", [id, admin_update_user_request])

## ADMIN LOBBIES

# List all lobbies (admin)
func admin_lobbies_admin_list_lobbies(title = "", isHidden = null, isLocked = null, hasPassword = null, minUsers = null, maxUsers = null, page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminLobbiesApi.new(_config), "admin_list_lobbies", [title, isHidden, isLocked, hasPassword, minUsers, maxUsers, page, pageSize])

# Delete lobby (admin)
func admin_lobbies_admin_delete_lobby(id: String) -> GamendResult:
	return await _call_api(AdminLobbiesApi.new(_config), "admin_delete_lobby", [id])

# Update lobby (admin)
func admin_lobbies_admin_update_lobby(id: String, adminUpdateLobbyRequest: AdminUpdateLobbyRequest) -> GamendResult:
	return await _call_api(AdminLobbiesApi.new(_config), "admin_update_lobby", [id, adminUpdateLobbyRequest])

## ADMIN LEADERBOARDS

## End leaderboard (admin)
func admin_leaderboards_admin_end_leaderboard(id: String) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_end_leaderboard", [id])

## Submit score (admin)
func admin_leaderboards_admin_submit_leaderboard_score(id: String, adminSubmitLeaderboardScoreRequest: AdminSubmitLeaderboardScoreRequest) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_submit_leaderboard_score", [id, adminSubmitLeaderboardScoreRequest])

## Delete leaderboard record (admin)
func admin_leaderboards_admin_delete_leaderboard_record(id: String, recordId: String) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_delete_leaderboard_record", [id, recordId])

## Update leaderboard record (admin)
func admin_leaderboards_admin_update_leaderboard_record(id: String, recordId: String, adminUpdateLeaderboardRecordRequest: AdminUpdateLeaderboardRecordRequest) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_update_leaderboard_record", [id, recordId, adminUpdateLeaderboardRecordRequest])

## Create leaderboard (admin)
func admin_leaderboards_admin_create_leaderboard(adminCreateLeaderboardRequest: AdminCreateLeaderboardRequest) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_create_leaderboard", [adminCreateLeaderboardRequest])

## Delete a user's record (admin)
func admin_leaderboards_admin_delete_leaderboard_user_record(id: String, userId: String) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_delete_leaderboard_user_record", [id, userId])
	
## Delete leaderboard (admin)
func admin_leaderboards_admin_delete_leaderboard(id: String) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_delete_leaderboard", [id])

## Update leaderboard (admin)
func admin_leaderboards_admin_update_leaderboard(id: String, adminUpdateLeaderboardRequest: AdminUpdateLeaderboardRequest) -> GamendResult:
	return await _call_api(AdminLeaderboardsApi.new(_config), "admin_update_leaderboard", [id, adminUpdateLeaderboardRequest])

## ADMIN KV

## List KV entries (admin)
func admin_kv_admin_list_kv_entries(page = 1, pageSize = 25, key = "", userId = null, lobbyId = null, globalOnly = null) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_list_kv_entries", [page, pageSize, key, userId, lobbyId, globalOnly])

## Create KV entry (admin)
func admin_kv_admin_create_kv_entry(adminCreateKvEntryRequest: AdminUpsertKvRequest) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_create_kv_entry", [adminCreateKvEntryRequest])

## Delete KV entry by id (admin)
func admin_kv_admin_delete_kv_entry(id: String) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_delete_kv_entry", [id])

## Update KV entry by id (admin)
func admin_kv_admin_update_kv_entry(id: String, adminUpdateKvEntryRequest: AdminUpdateKvEntryRequest) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_update_kv_entry", [id, adminUpdateKvEntryRequest])

## Delete KV by key (admin)
func admin_kv_admin_delete_kv(key: String, user_id = null, lobby_id = null) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_delete_kv", [key, user_id, lobby_id])

## Upsert KV by key (admin)
func admin_kv_admin_upsert_kv(adminCreateKvEntryRequest: AdminUpsertKvRequest) -> GamendResult:
	return await _call_api(AdminKVApi.new(_config), "admin_upsert_kv", [adminCreateKvEntryRequest])

## ADMIN NOTIFICATIONS

## Create a notification (admin)
func admin_notifications_admin_create_notification(adminCreateNotificationRequest: AdminCreateNotificationRequest) -> GamendResult:
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
func admin_groups_admin_update_group(id: String, adminUpdateGroupRequest: AdminUpdateGroupRequest) -> GamendResult:
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
func admin_quests_admin_create_quest(request: AdminCreateQuestRequest) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_create_quest", [request])

## Update a quest (admin)
func admin_quests_admin_update_quest(id: String, request: AdminUpdateQuestRequest) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_update_quest", [id, request])

## Delete a quest and all user progress (admin)
func admin_quests_admin_delete_quest(id: String) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_delete_quest", [id])

## List quest progress rows (admin)
func admin_quests_admin_list_quest_progress(page = 1, pageSize = 25) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_list_quest_progress", [page, pageSize])

## Force-complete a quest for a user (admin)
func admin_quests_admin_grant_quest(request: AdminGrantQuestRequest) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_grant_quest", [request])

## Reset a user's current-period quest progress (admin)
func admin_quests_admin_reset_quest(request: AdminResetQuestRequest) -> GamendResult:
	return await _call_api(AdminQuestsApi.new(_config), "admin_reset_quest", [request])

## Claim a completed quest on a user's behalf (admin)
func admin_quests_admin_claim_quest(request: AdminClaimQuestRequest) -> GamendResult:
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
	var request = MatchmakingJoinRequest.new()
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
