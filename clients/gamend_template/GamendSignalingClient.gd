## GamendSignalingClient — Godot WebRTC peer-to-peer client for game_server.
##
## Uses an existing PhoenixChannel ("signaling:<lobby_id>", must be joined
## already) to relay SDP offers/answers and ICE candidates between peers.
## Supports both topologies exposed by the SignalingChannel:
##   - star: every client connects to a single host (e.g. a headless Godot
##     server); clients call connect_to_peer() with the host's user_id.
##   - mesh: every peer connects to every other peer, typically by calling
##     connect_to_peer() on each peer_joined event.
##
## This class is topology-agnostic: it emits peer events using the
## authenticated user_id from the server and lets the caller decide when to
## call connect_to_peer(user_id). Simultaneous offers (glare) are resolved
## deterministically on both sides: the offer sent by the lexicographically
## smaller user_id wins.
##
## Usage:
##   var realtime = GamendRealtime.new(token)
##   var signaling_channel = realtime.add_channel("signaling:lobby_1")
##   # wait for channel join...
##
##   var p2p = GamendSignalingClient.new(signaling_channel)
##   p2p.peer_joined.connect(func(user_id, _role): p2p.connect_to_peer(user_id))
##   p2p.peer_connected.connect(_on_peer_connected)
##   p2p.data_received.connect(_on_data_received)
##   add_child(p2p)
##
##   p2p.send_data(user_id, "events", "hello".to_utf8_buffer())
##
##   func _on_data_received(user_id: String, label: String, data: PackedByteArray):
##       print("Received from %s on %s: %s" % [user_id, label, data.get_string_from_utf8()])
##

class_name GamendSignalingClient
extends Node

## Emitted when a peer enters the signaling room (not connected via WebRTC yet).
signal peer_joined(user_id: String, role: String)
## Emitted when a peer leaves the signaling room.
signal peer_left(user_id: String)
## Emitted when a peer reconnects to the signaling room after a transient disconnect.
signal peer_rejoined(user_id: String, role: String)
## Emitted when the WebRTC connection to a peer is established.
signal peer_connected(user_id: String)
## Emitted when an established WebRTC connection to a peer drops.
signal peer_disconnected(user_id: String)
## Emitted when a DataChannel opens.
signal channel_opened(user_id: String, label: String)
## Emitted when a DataChannel closes.
signal channel_closed(user_id: String, label: String)
## Emitted when data arrives on a DataChannel.
signal data_received(user_id: String, label: String, data: PackedByteArray)
## Emitted on error.
signal errored(message: String)

## The Phoenix channel used for signaling (must be joined already).
var _channel: PhoenixChannel
## Authenticated user_id of this node. Seeded from opts.user_id (if given)
## and confirmed/overwritten by the server's join reply.
var _my_user_id: String = ""
## Role assigned by the server on join ("host" or "user").
var _my_role: String = ""
## Map of user_id → GamendWebRTCPeer.
var _peers: Dictionary = {}
## Map of user_id → last applied remote offer SDP, for duplicate detection.
var _last_remote_sdp: Dictionary = {}
## ICE servers configuration.
var _ice_servers: Array = [{"urls": ["stun:stun.l.google.com:19302"]}]
## DataChannel definitions: Array of {label, ordered, max_retransmits}.
var _channel_defs: Array = [
	{"label": "events", "ordered": true},
	{"label": "state", "ordered": false, "maxRetransmits": 0},
]
## Enable debug logging.
var enable_logs: bool = false


func _init(channel: PhoenixChannel, opts: Dictionary = {}) -> void:
	_channel = channel
	if opts.has("ice_servers"):
		_ice_servers = opts["ice_servers"]
	if opts.has("data_channels"):
		_channel_defs = opts["data_channels"]
	if opts.has("enable_logs"):
		enable_logs = opts["enable_logs"]
	if opts.has("user_id"):
		# Fallback identity from the auth layer. Presence broadcasts can
		# arrive before the join reply is processed, so glare resolution and
		# self-filtering must not depend on the reply having arrived yet.
		# Overwritten by the authoritative user_id from the join reply.
		_my_user_id = opts["user_id"]


func _ready() -> void:
	# Listen for signaling events relayed by the server via the Phoenix channel
	_channel.on_event.connect(_on_channel_event)


## Returns the authenticated user_id of this node (empty until joined).
func get_my_user_id() -> String:
	return _my_user_id


## Returns the role assigned by the server ("host" or "user").
func get_my_role() -> String:
	return _my_role


## Returns the user_ids of all peers currently being negotiated or connected.
func get_peer_ids() -> Array:
	return _peers.keys()


## Check if the WebRTC connection to a peer is established.
func is_peer_connected(user_id: String) -> bool:
	return _peers.has(user_id) and _peers[user_id].is_connected_webrtc()


## Check if a specific DataChannel to a peer is open.
func is_channel_open(user_id: String, label: String) -> bool:
	return _peers.has(user_id) and _peers[user_id].is_channel_open(label)


## Initiator side: creates a peer, adds DataChannels, and sends an offer.
func connect_to_peer(user_id: String) -> void:
	if _peers.has(user_id):
		_log("Already negotiating with peer %s" % user_id)
		return

	var peer := _create_peer(user_id)
	if peer == null:
		return

	# DataChannels must exist before the offer so they are negotiated in-band.
	for label in peer.create_channels(_channel_defs):
		_log("Failed to create DataChannel %s for peer %s" % [label, user_id])
		errored.emit("Failed to create DataChannel %s for peer %s" % [label, user_id])

	peer.create_offer()
	_log("Sent offer to peer %s" % user_id)


## Send data to one peer over a named DataChannel.
func send_data(user_id: String, label: String, data: PackedByteArray) -> Error:
	if not _peers.has(user_id):
		return ERR_DOES_NOT_EXIST
	return _peers[user_id].send_data(label, data)


## Send a string to one peer over a named DataChannel.
func send_text(user_id: String, label: String, text: String) -> Error:
	return send_data(user_id, label, text.to_utf8_buffer())


## Send data to all peers over a named DataChannel.
func broadcast_data(label: String, data: PackedByteArray) -> void:
	for user_id in _peers:
		send_data(user_id, label, data)


## Send a string to all peers over a named DataChannel.
func broadcast_text(label: String, text: String) -> void:
	broadcast_data(label, text.to_utf8_buffer())


## Close the connection to one peer.
func close_peer(user_id: String) -> void:
	_drop_peer(user_id)


## Close all peer connections.
func close_all() -> void:
	for user_id in _peers.keys():
		_drop_peer(user_id)


func _process(_delta: float) -> void:
	# keys() snapshot: peers may be dropped during poll (failed/closed).
	for user_id in _peers.keys():
		if _peers.has(user_id):
			_peers[user_id].poll()


## Creates and registers a GamendWebRTCPeer with its signals bound to user_id.
func _create_peer(user_id: String) -> GamendWebRTCPeer:
	var peer := GamendWebRTCPeer.new()
	var err := peer.initialize(_ice_servers)
	if err != OK:
		_log("Failed to initialize WebRTCPeerConnection for peer %s: %s" % [user_id, err])
		errored.emit("Failed to initialize WebRTCPeerConnection for peer %s" % user_id)
		return null

	peer.session_description_created.connect(_on_session_description_created.bind(user_id))
	peer.ice_candidate_created.connect(_on_ice_candidate_created.bind(user_id))
	peer.connected.connect(_on_peer_rtc_connected.bind(user_id))
	peer.failed.connect(_on_peer_rtc_failed.bind(user_id))
	peer.closed.connect(_on_peer_rtc_closed.bind(user_id))
	peer.channel_opened.connect(_on_peer_channel_opened.bind(user_id))
	peer.channel_closed.connect(_on_peer_channel_closed.bind(user_id))
	peer.data_received.connect(_on_peer_data_received.bind(user_id))

	_peers[user_id] = peer
	return peer


## Answerer side: applies a remote offer. Godot generates the answer
## automatically and fires session_description_created; DataChannels created
## by the initiator arrive via data_channel_received.
func _receive_offer(from_user_id: String, sdp: String) -> void:
	if _peers.has(from_user_id):
		# Exact duplicate offer (same SDP): ignore. Presence can broadcast
		# the same join multiple times before the peer list stabilizes.
		if sdp == _last_remote_sdp.get(from_user_id, ""):
			_log("Duplicate offer from peer %s ignored" % from_user_id)
			return
		
		var existing: GamendWebRTCPeer = _peers[from_user_id]
		if existing.is_connected_webrtc():
			# Fresh offer over an established link: the remote likely
			# restarted, so renegotiate from scratch.
			_log("Offer from connected peer %s, renegotiating" % from_user_id)
			_drop_peer(from_user_id)
		elif _my_user_id.is_empty() or from_user_id < _my_user_id:
			# Glare: both sides offered at once. Both apply the same rule
			# (smaller user_id wins), so exactly one negotiation survives.
			# If our own user_id is not known yet (join reply still in
			# flight and no opts.user_id fallback), we cannot evaluate the
			# tie-break, so we yield to the remote offer: the remote side
			# knows both ids and will have kept exactly one negotiation.
			_log("Glare with peer %s: remote offer wins" % from_user_id)
			_drop_peer(from_user_id)
		else:
			_log("Glare with peer %s: local offer wins, ignoring remote offer" % from_user_id)
			return

	var peer := _create_peer(from_user_id)
	if peer == null:
		return

	var err := peer.set_remote_description("offer", sdp)
	if err != OK:
		_log("set_remote_description failed for peer %s: %s" % [from_user_id, err])
		errored.emit("set_remote_description failed for peer %s" % from_user_id)
		_drop_peer(from_user_id)
		return

	_last_remote_sdp[from_user_id] = sdp


## Answerer side: applies a remote answer SDP. Called when a peer we offered
## to sends back an answer via the signaling relay.
##
## Idempotent: duplicate answers from the same peer (e.g. caused by a
## repeated presence event or a retransmission) are silently ignored,
## because libdatachannel rejects applying an answer in "stable" state.
## An answer from an unknown peer (negotiation already dropped) is also
## discarded safely.
func _receive_answer(from_user_id: String, sdp: String) -> void:
	if not _peers.has(from_user_id):
		_log("Answer from unknown peer %s, ignoring" % from_user_id)
		return
	var peer: GamendWebRTCPeer = _peers[from_user_id]
	if peer.has_remote_description():
		_log("Duplicate answer from peer %s ignored" % from_user_id)
		return
	var err := peer.set_remote_description("answer", sdp)
	if err != OK:
		_log("set_remote_description(answer) failed for peer %s: %s" % [from_user_id, err])
		errored.emit("set_remote_description(answer) failed for peer %s" % from_user_id)
		_drop_peer(from_user_id)


## Removes a peer and closes its connection. Emits peer_disconnected only if
## the WebRTC link had been established (not for aborted negotiations).
func _drop_peer(user_id: String) -> void:
	if not _peers.has(user_id):
		return

	var peer: GamendWebRTCPeer = _peers[user_id]
	_peers.erase(user_id)
	_last_remote_sdp.erase(user_id)

	var was_connected := peer.is_connected_webrtc()
	peer.close()

	if was_connected:
		peer_disconnected.emit(user_id)


## Handle signaling events relayed by the server via the Phoenix channel.
# PhoenixChannel.on_event emits (event, payload, status) — connecting a
# 4-arg handler to it errors at emit time.
func _on_channel_event(event: String, payload: Dictionary, _status) -> void:
	match event:
		"phx_join":
			# Join reply from the SignalingChannel: {user_id, role}.
			# Only overwrite the opts fallback if the reply carries a value.
			var joined_id: String = payload.get("user_id", "")
			if not joined_id.is_empty():
				_my_user_id = joined_id
			_my_role = payload.get("role", "")
			_log("Joined signaling room as user_id=%s role=%s" % [_my_user_id, _my_role])

		"user_joined":
			var user_id: String = payload.get("user_id", "")
			if user_id.is_empty() or user_id == _my_user_id:
				return
			if _peers.has(user_id):
				_log("Peer %s already known, skipping new negotiation" % user_id)
				return
			_log("Peer joined: %s" % user_id)
			peer_joined.emit(user_id, payload.get("role", ""))

		"user_rejoined":
			var user_id: String = payload.get("user_id", "")
			if user_id.is_empty() or user_id == _my_user_id:
				return
			# The previous WebRTC connection to this peer is likely stale;
			# drop it so listeners can start a fresh negotiation.
			_log("Peer rejoined: %s" % user_id)
			_drop_peer(user_id)
			peer_rejoined.emit(user_id, payload.get("role", ""))

		"user_left":
			var user_id: String = payload.get("user_id", "")
			if user_id.is_empty():
				return
			_log("Peer left: %s" % user_id)
			_drop_peer(user_id)
			peer_left.emit(user_id)

		"offer":
			var from: String = payload.get("from_user_id", "")
			if from.is_empty():
				return
			_log("Received offer from peer %s" % from)
			_receive_offer(from, payload.get("sdp", ""))

		"answer":
			var from: String = payload.get("from_user_id", "")
			if from.is_empty():
				return
			_log("Received answer from peer %s" % from)
			_receive_answer(from, payload.get("sdp", ""))

		"ice":
			var from: String = payload.get("from_user_id", "")
			if from.is_empty() or not _peers.has(from):
				return

			# The server relays the "candidate" field verbatim, so this SDK
			# nests sdpMid/sdpMLineIndex inside it (see _on_ice_candidate_created).
			var cand: Variant = payload.get("candidate")
			if cand is Dictionary:
				_peers[from].add_ice_candidate(
					cand.get("sdpMid", ""),
					int(cand.get("sdpMLineIndex", 0)),
					cand.get("candidate", ""),
					cand.get("ufrag", ""),
				)
			elif cand is String:
				# Fallback for clients sending the raw candidate string.
				_peers[from].add_ice_candidate("", 0, cand)

		"room_closed":
			_log("Room closed by server")
			close_all()


## Called when a peer generates a session description. The SignalingChannel
## relays only the "sdp" field and the receiving side infers the type from
## the event name, which matches the SDP type ("offer" / "answer").
func _on_session_description_created(type: String, sdp: String, user_id: String) -> void:
	_log("SDP %s created for peer %s" % [type, user_id])
	_channel.push(type, {
		"target": user_id,
		"sdp": sdp,
	})


## Called when a peer generates an ICE candidate. sdpMid/sdpMLineIndex are
## nested inside "candidate" because the server relays that field verbatim.
func _on_ice_candidate_created(mid: String, index: int, candidate: String, user_id: String) -> void:
	_log("Sending ICE candidate to peer %s" % user_id)
	if not _peers.has(user_id):
		_log("Peer %s gone, dropping candidate" % user_id)
		return
	
	var peer: GamendWebRTCPeer = _peers[user_id]
	_channel.push("ice", {
		"target": user_id,
		"candidate": {
			"candidate": candidate,
			"sdpMid": mid,
			"sdpMLineIndex": index,
			# Identifies our negotiation, so the peer can discard candidates
			# left over from a superseded offer (glare, renegotiation).
			"ufrag": peer.get_local_ufrag(),
		},
	})


func _on_peer_rtc_connected(user_id: String) -> void:
	_log("WebRTC connected to peer %s" % user_id)
	peer_connected.emit(user_id)


func _on_peer_rtc_failed(user_id: String) -> void:
	_log("WebRTC connection to peer %s failed" % user_id)
	errored.emit("WebRTC connection to peer %s failed" % user_id)
	_drop_peer(user_id)


func _on_peer_rtc_closed(user_id: String) -> void:
	_log("WebRTC connection to peer %s closed" % user_id)
	_drop_peer(user_id)


func _on_peer_channel_opened(label: String, user_id: String) -> void:
	_log("DataChannel %s open for peer %s" % [label, user_id])
	channel_opened.emit(user_id, label)


func _on_peer_channel_closed(label: String, user_id: String) -> void:
	_log("DataChannel %s closed for peer %s" % [label, user_id])
	channel_closed.emit(user_id, label)


func _on_peer_data_received(label: String, data: PackedByteArray, user_id: String) -> void:
	data_received.emit(user_id, label, data)


func _log(msg: String) -> void:
	if enable_logs:
		print("[GamendSignalingClient] ", msg)


func _exit_tree() -> void:
	close_all()
	if _channel and _channel.on_event.is_connected(_on_channel_event):
		_channel.on_event.disconnect(_on_channel_event)
