## GamendWebRTC — Godot WebRTC DataChannel client for gamend.
##
## Uses an existing PhoenixChannel (UserChannel) for SDP/ICE signaling.
## Once connected, named DataChannels carry game data alongside the WebSocket.
##
## Usage:
##   var realtime = GamendWebSocket.new(token)
##   var user_channel = realtime.add_channel("user:123")
##   # wait for channel join...
##
##   var webrtc = GamendWebRTC.new(user_channel)
##   webrtc.data_received.connect(_on_data_received)
##   webrtc.channel_opened.connect(_on_channel_opened)
##   webrtc.connection_state_changed.connect(_on_state_changed)
##   add_child(webrtc)
##   webrtc.connect_webrtc()
##
##   webrtc.send_data("events", "hello".to_utf8_buffer())
##
##   func _on_data_received(label: String, data: PackedByteArray):
##       print("Received on %s: %s" % [label, data.get_string_from_utf8()])
##

class_name GamendWebRTC
extends Node

## Emitted when data arrives on a DataChannel.
signal data_received(label: String, data: PackedByteArray)
## Emitted when a DataChannel opens.
signal channel_opened(label: String)
## Emitted when a DataChannel closes.
signal channel_closed(label: String)
## Emitted when the WebRTC connection state changes.
signal connection_state_changed(state: String)
## Emitted when the WebRTC connection is fully established.
signal connected()
## Emitted on error.
signal errored(message: String)

## The Phoenix channel used for signaling (must be joined already).
var _channel: PhoenixChannel
## The peer connection wrapper (shared with GamendSignalingClient).
var _peer: GamendWebRTCPeer
## ICE servers configuration.
var _ice_servers: Array = [{"urls": ["stun:stun.l.google.com:19302"]}]
## DataChannel definitions: Array of {label, ordered, max_retransmits}.
var _channel_defs: Array = [
	{"label": "events", "ordered": true},
	{"label": "state", "ordered": false, "maxRetransmits": 0},
]
## Enable debug logging.
var enable_logs: bool = false
## RPC payload format: "json" or "protobuf" (negotiated via the DataChannel
## protocol field; protobuf replies are correlated by request id).
var _format: String = "json"
## Pending call_hook requests: key (int id or "plugin fn") -> awaitable state.
var _pending_calls: Dictionary = {}
var _next_call_id: int = 0

## Emitted when a call_hook reply arrives; used internally for await.
signal _rpc_settled(key: Variant, result: Dictionary)


func _init(channel: PhoenixChannel, opts: Dictionary = {}) -> void:
	_channel = channel
	if opts.has("ice_servers"):
		_ice_servers = opts["ice_servers"]
	if opts.has("data_channels"):
		_channel_defs = opts["data_channels"]
	if opts.has("enable_logs"):
		enable_logs = opts["enable_logs"]
	if opts.get("format", "json") == "protobuf":
		_format = "protobuf"


func _ready() -> void:
	# Listen for signaling events from the server via the Phoenix channel
	_channel.on_event.connect(_on_channel_event)


## Start the WebRTC connection negotiation.
func connect_webrtc() -> void:
	# Create GamendWebRTCPeer
	_peer = GamendWebRTCPeer.new()
	var err := _peer.initialize(_ice_servers)
	if err != OK:
		_log("Failed to initialize WebRTCPeerConnection: %s" % err)
		errored.emit("Failed to initialize WebRTCPeerConnection")
		_peer = null
		return

	# Connect signals
	_peer.session_description_created.connect(_on_session_description_created)
	_peer.ice_candidate_created.connect(_on_ice_candidate_created)
	_peer.connected.connect(_on_peer_connected)
	_peer.failed.connect(_on_peer_failed)
	_peer.closed.connect(_on_peer_closed)
	# Channel open/close is detected locally by polling in GamendWebRTCPeer.
	_peer.channel_opened.connect(channel_opened.emit)
	_peer.channel_closed.connect(channel_closed.emit)
	_peer.data_received.connect(_on_peer_data_received)

	# Create DataChannels (client-initiated)
	var protocol := "protobuf" if _format == "protobuf" else ""
	for label in _peer.create_channels(_channel_defs, protocol):
		_log("Failed to create DataChannel: %s" % label)
		errored.emit("Failed to create DataChannel: %s" % label)

	# Create offer
	_peer.create_offer()


## Calls a server-side plugin hook over the "events" DataChannel and awaits
## the result. Returns {ok: bool, data / error}.
##
## In protobuf mode replies are correlated by request id, so concurrent
## calls (including to the same function) are safe. In JSON mode replies
## are matched by plugin+fn (legacy protocol), first pending call wins.
func call_hook(plugin: String, fn: String, args: Array = [], timeout_sec: float = 10.0) -> Dictionary:
	if not is_channel_open("events"):
		return {"ok": false, "error": "events DataChannel is not open"}

	var key: Variant
	if _format == "protobuf":
		_next_call_id += 1
		key = _next_call_id
		var err := send_data("events", GamendProto.encode_rpc_call(_next_call_id, plugin, fn, args))
		if err != OK:
			return {"ok": false, "error": "send failed: %s" % err}
	else:
		key = "%s %s" % [plugin, fn]
		var err := send_text("events", JSON.stringify({"type": "call_hook", "plugin": plugin, "fn": fn, "args": args}))
		if err != OK:
			return {"ok": false, "error": "send failed: %s" % err}

	_pending_calls[key] = true
	var timer := get_tree().create_timer(timeout_sec)
	timer.timeout.connect(func():
		if _pending_calls.has(key):
			_pending_calls.erase(key)
			_rpc_settled.emit(key, {"ok": false, "error": "timeout"}))

	while true:
		var settled = await _rpc_settled
		if settled[0] == key:
			return settled[1]
	return {"ok": false, "error": "unreachable"}


## Calls a typed (protobuf) plugin hook over the "events" DataChannel and
## awaits the result: {ok: true, data: PackedByteArray} / {ok: false, error}.
## Encode the bytes with the game's schema (registered by the plugin as
## <FnName>Request / <FnName>Reply); hooks without a registered schema error
## with hook_schema_missing. Requires format "protobuf".
func call_hook_raw(plugin: String, fn: String, bytes: PackedByteArray, timeout_sec: float = 10.0) -> Dictionary:
	if _format != "protobuf":
		return {"ok": false, "error": "call_hook_raw requires format \"protobuf\""}
	if not is_channel_open("events"):
		return {"ok": false, "error": "events DataChannel is not open"}

	_next_call_id += 1
	var key: Variant = _next_call_id
	var err := send_data("events", GamendProto.encode_rpc_call_raw(_next_call_id, plugin, fn, bytes))
	if err != OK:
		return {"ok": false, "error": "send failed: %s" % err}

	_pending_calls[key] = true
	var timer := get_tree().create_timer(timeout_sec)
	timer.timeout.connect(func():
		if _pending_calls.has(key):
			_pending_calls.erase(key)
			_rpc_settled.emit(key, {"ok": false, "error": "timeout"}))

	while true:
		var settled = await _rpc_settled
		if settled[0] == key:
			return settled[1]
	return {"ok": false, "error": "unreachable"}


# Routes an incoming "events" frame to a pending call_hook. Returns true if
# the frame was an RPC reply and has been consumed.
func _handle_rpc_reply(data: PackedByteArray) -> bool:
	if _format == "protobuf":
		var reply = GamendProto.decode_rpc_reply(data)
		if reply == null:
			return false
		var key = reply["id"]
		if not _pending_calls.has(key):
			return true
		_pending_calls.erase(key)
		_rpc_settled.emit(key, {"ok": reply["ok"], "data": reply.get("data"), "error": reply.get("error", "")})
		return true

	var text := data.get_string_from_utf8()
	if text.is_empty():
		return false
	var msg = JSON.parse_string(text)
	if msg == null or not (msg is Dictionary) or not msg.has("type"):
		return false
	if msg["type"] != "hook_reply" and msg["type"] != "hook_error":
		return false
	var key := "%s %s" % [msg.get("plugin", ""), msg.get("fn", "")]
	if not _pending_calls.has(key):
		return false
	_pending_calls.erase(key)
	if msg["type"] == "hook_reply":
		_rpc_settled.emit(key, {"ok": true, "data": msg.get("data")})
	else:
		_rpc_settled.emit(key, {"ok": false, "error": str(msg.get("error", "unknown"))})
	return true


## Send data over a named DataChannel.
func send_data(label: String, data: PackedByteArray) -> Error:
	if _peer == null:
		return ERR_UNCONFIGURED
	return _peer.send_data(label, data)


## Send a string over a named DataChannel.
func send_text(label: String, text: String) -> Error:
	return send_data(label, text.to_utf8_buffer())


## Check if a specific DataChannel is open.
func is_channel_open(label: String) -> bool:
	return _peer != null and _peer.is_channel_open(label)


## Check if the WebRTC connection is established.
func is_connected_webrtc() -> bool:
	return _peer != null and _peer.is_connected_webrtc()


## Close the WebRTC connection and all DataChannels.
func close_webrtc() -> void:
	if _peer:
		_peer.close()
		_peer = null

	# Notify server
	_channel.push("webrtc:close", {})
	connection_state_changed.emit("closed")


func _process(_delta: float) -> void:
	if _peer:
		# Poll the peer connection
		_peer.poll()


## Handle signaling events from the server via the Phoenix channel.
# PhoenixChannel.on_event emits (event, payload, status) — connecting a
# 4-arg handler to it errors at emit time.
func _on_channel_event(event: String, payload: Dictionary, _status) -> void:
	match event:
		"webrtc:answer":
			if _peer and payload.has("sdp") and payload.has("type"):
				_log("Received SDP answer")
				_peer.set_remote_description(payload["type"], payload["sdp"])

		"webrtc:ice":
			if _peer and payload.has("candidate"):
				var mid: String = payload.get("sdpMid", "")
				var idx: int = payload.get("sdpMLineIndex", 0)
				var candidate: String = payload["candidate"]
				_log("Received ICE candidate: %s" % candidate.substr(0, 40))
				_peer.add_ice_candidate(mid, idx, candidate)

		"webrtc:state":
			var state_str: String = payload.get("state", "unknown")
			_log("Server reports state: %s" % state_str)
			# We track this locally via polling, but log the server perspective

		"webrtc:channel_open":
			# channel_opened is emitted from local polling in GamendWebRTCPeer;
			# this is the server-side confirmation.
			var label: String = payload.get("channel", "")
			_log("Server confirms channel open: %s" % label)

		"webrtc:channel_closed":
			_log("Server reports channel closed")


func _on_peer_connected() -> void:
	_log("WebRTC connected")
	connection_state_changed.emit("connected")
	connected.emit()


func _on_peer_failed() -> void:
	_log("WebRTC connection failed")
	connection_state_changed.emit("failed")
	errored.emit("WebRTC connection failed")
	close_webrtc()


func _on_peer_closed() -> void:
	_log("WebRTC connection closed")
	_peer = null
	connection_state_changed.emit("closed")


func _on_peer_data_received(label: String, data: PackedByteArray) -> void:
	if label == "events" and _handle_rpc_reply(data):
		return
	data_received.emit(label, data)


## Called when the PeerConnection generates an ICE candidate.
func _on_ice_candidate_created(mid: String, index: int, candidate: String) -> void:
	_log("Sending ICE candidate")
	_channel.push("webrtc:ice", {
		"candidate": candidate,
		"sdpMid": mid,
		"sdpMLineIndex": index,
	})


## Called when the PeerConnection generates a session description (offer/answer).
## The local description is already applied by GamendWebRTCPeer.
func _on_session_description_created(type: String, sdp: String) -> void:
	_log("SDP created: %s" % type)
	if type == "offer":
		_channel.push("webrtc:offer", {
			"sdp": sdp,
			"type": type,
		})


func _log(msg: String) -> void:
	if enable_logs:
		print("[GamendWebRTC] ", msg)


func _exit_tree() -> void:
	if _peer:
		close_webrtc()
	if _channel and _channel.on_event.is_connected(_on_channel_event):
		_channel.on_event.disconnect(_on_channel_event)
