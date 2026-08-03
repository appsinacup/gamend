## GamendWebRTCPeer — wraps a single WebRTCPeerConnection and its DataChannels.
##
## Shared by GamendWebRTC (client <-> server) and GamendSignalingClient
## (peer <-> peer). Owns DataChannel creation and tracking, connection and
## channel state detection (WebRTCDataChannel has no signals, so state is
## detected by polling), and packet delivery.
##
## It does NOT do signaling: the owner forwards session_description_created /
## ice_candidate_created to its transport and feeds remote descriptions and
## ICE candidates back in. The owner must call poll() every frame.
##
class_name GamendWebRTCPeer
extends RefCounted

## Emitted when a session description is generated (local description is
## already set); the owner sends it over its signaling transport.
signal session_description_created(type: String, sdp: String)
## Emitted when an ICE candidate is generated; the owner sends it over its
## signaling transport.
signal ice_candidate_created(mid: String, index: int, candidate: String)
## Emitted once when the connection reaches STATE_CONNECTED.
signal connected()
## Emitted once when the connection fails (STATE_FAILED).
signal failed()
## Emitted once when an established connection is closed remotely.
signal closed()
## Emitted when a DataChannel opens.
signal channel_opened(label: String)
## Emitted when a DataChannel closes.
signal channel_closed(label: String)
## Emitted when a packet arrives on an open DataChannel.
signal data_received(label: String, data: PackedByteArray)

## The underlying WebRTCPeerConnection (null after close()).
var _peer: WebRTCPeerConnection
## Map of label → WebRTCDataChannel.
var _data_channels: Dictionary = {}
## Labels seen open, so channel_opened / channel_closed fire once each.
var _opened: Dictionary = {}
## Whether the connection reached STATE_CONNECTED.
var _is_connected: bool = false

## Maximum number of ICE candidates buffered before a remote description
## arrives. Prevents unbounded growth if a negotiation never completes.
const MAX_PENDING_CANDIDATES: int = 128

## ICE ufrag of our own current negotiation, parsed from the local SDP.
var _local_ufrag: String = ""
## ICE ufrag of the remote side of the current negotiation.
var _remote_ufrag: String = ""
## True once a remote description has been applied.
var _remote_description_set: bool = false
## Candidates received before the remote description was available.
var _pending_candidates: Array[Dictionary] = []


## Create the underlying WebRTCPeerConnection.
func initialize(ice_servers: Array) -> Error:
	_peer = WebRTCPeerConnection.new()
	var err := _peer.initialize({"iceServers": ice_servers})
	if err != OK:
		_peer = null
		return err

	_peer.session_description_created.connect(_on_session_description_created)
	_peer.ice_candidate_created.connect(ice_candidate_created.emit)
	_peer.data_channel_received.connect(_on_data_channel_received)
	return OK


## Create DataChannels on the initiating side (must be called before
## create_offer so channels are negotiated in-band). Definitions:
## Array of {label, ordered, maxRetransmits, maxPacketLifeTime}.
## Returns the labels that failed to create, if any.
func create_channels(channel_defs: Array, protocol: String = "") -> Array:
	var failed_labels: Array = []

	for def in channel_defs:
		var label: String = def["label"]
		var opts := {}
		if def.has("ordered"):
			opts["ordered"] = def["ordered"]
		if def.has("maxRetransmits"):
			opts["maxRetransmits"] = def["maxRetransmits"]
		if def.has("maxPacketLifeTime"):
			opts["maxPacketLifeTime"] = def["maxPacketLifeTime"]
		if not protocol.is_empty():
			opts["protocol"] = protocol

		var dc := _peer.create_data_channel(label, opts)
		if dc == null:
			failed_labels.append(label)
			continue

		_data_channels[label] = dc

	return failed_labels


## Start negotiation as the initiator.
func create_offer() -> Error:
	if _peer == null:
		return ERR_UNCONFIGURED
	return _peer.create_offer()


## Apply a remote session description ("offer" or "answer").
func set_remote_description(type: String, sdp: String) -> Error:
	if _peer == null:
		return ERR_UNCONFIGURED
	var err: Error = _peer.set_remote_description(type, sdp)
	if err != OK:
		return err
	_remote_ufrag = _parse_ufrag(sdp)
	_remote_description_set = true
	_flush_pending_candidates()
	return OK


## Apply a remote ICE candidate.
## Candidates that arrive before the remote description are buffered instead
## of raising an engine error: with trickle ICE the remote starts sending
## candidates as soon as it sets its local description, which can be before
## its offer/answer has been applied here.
## When "ufrag" is provided it identifies the remote negotiation the candidate
## belongs to; candidates from a superseded negotiation are dropped.
func add_ice_candidate(mid: String, index: int, candidate: String, ufrag: String = "") -> Error:
	if _peer == null:
		return ERR_UNCONFIGURED
	if not _remote_description_set:
		if _pending_candidates.size() < MAX_PENDING_CANDIDATES:
			_pending_candidates.append({
				"mid": mid, "index": index, "candidate": candidate, "ufrag": ufrag,
			})
		return OK
	if not _matches_remote_session(ufrag):
		return OK
	return _peer.add_ice_candidate(mid, index, candidate)


## True when a candidate belongs to the currently applied remote negotiation.
## Unknown ufrags (older peers, missing field) are accepted for compatibility.
func _matches_remote_session(ufrag: String) -> bool:
	if ufrag.is_empty() or _remote_ufrag.is_empty():
		return true
	return ufrag == _remote_ufrag


## Apply candidates buffered while the remote description was missing.
func _flush_pending_candidates() -> void:
	var buffered: Array[Dictionary] = _pending_candidates
	_pending_candidates = []
	for item in buffered:
		if _matches_remote_session(item["ufrag"]):
			_peer.add_ice_candidate(item["mid"], item["index"], item["candidate"])


## Send data over a named DataChannel.
func send_data(label: String, data: PackedByteArray) -> Error:
	if not _data_channels.has(label):
		push_warning("send_data: channel '%s' does not exist" % label)
		return ERR_DOES_NOT_EXIST

	var dc: WebRTCDataChannel = _data_channels[label]
	if dc.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		push_warning("send_data: channel '%s' not open (state=%d)" % [label, dc.get_ready_state()])
		return ERR_UNAVAILABLE

	return dc.put_packet(data)


## Send a string over a named DataChannel.
func send_text(label: String, text: String) -> Error:
	return send_data(label, text.to_utf8_buffer())


## Check if a specific DataChannel is open.
func is_channel_open(label: String) -> bool:
	if not _data_channels.has(label):
		return false
	var dc: WebRTCDataChannel = _data_channels[label]
	return dc.get_ready_state() == WebRTCDataChannel.STATE_OPEN


## Check if the WebRTC connection is established.
func is_connected_webrtc() -> bool:
	return _is_connected


## Poll the connection and its DataChannels. Call every frame.
func poll() -> void:
	if _peer == null:
		return

	_peer.poll()

	var state := _peer.get_connection_state()
	if state == WebRTCPeerConnection.STATE_CONNECTED and not _is_connected:
		_is_connected = true
		connected.emit()
	elif state == WebRTCPeerConnection.STATE_FAILED:
		failed.emit()
		close()
		return
	elif state == WebRTCPeerConnection.STATE_CLOSED and _is_connected:
		# Emitted before close() so listeners still see is_connected_webrtc().
		closed.emit()
		close()
		return

	for label in _data_channels:
		var dc: WebRTCDataChannel = _data_channels[label]
		dc.poll()

		var dc_state := dc.get_ready_state()
		if dc_state == WebRTCDataChannel.STATE_OPEN:
			if not _opened.has(label):
				_opened[label] = true
				channel_opened.emit(label)

			while dc.get_available_packet_count() > 0:
				data_received.emit(label, dc.get_packet())
		elif dc_state == WebRTCDataChannel.STATE_CLOSED and _opened.has(label):
			_opened.erase(label)
			channel_closed.emit(label)


## Close the connection and all DataChannels. Idempotent.
func close() -> void:
	for label in _opened.keys():
		channel_closed.emit(label)
	_opened.clear()

	for label in _data_channels:
		var dc: WebRTCDataChannel = _data_channels[label]
		dc.close()
	_data_channels.clear()

	_is_connected = false

	if _peer:
		_peer.close()
		_peer = null

	_remote_description_set = false
	_remote_ufrag = ""
	_local_ufrag = ""
	_pending_candidates.clear()


## The local description must always be applied before relaying the SDP.
func _on_session_description_created(type: String, sdp: String) -> void:
	if _peer == null:
		return
	_local_ufrag = _parse_ufrag(sdp)
	_peer.set_local_description(type, sdp)
	session_description_created.emit(type, sdp)


## Called on the answering side when the initiator creates DataChannels.
func _on_data_channel_received(dc: WebRTCDataChannel) -> void:
	_data_channels[dc.get_label()] = dc


## Extract the "a=ice-ufrag:" value from an SDP blob, or "" when absent.
static func _parse_ufrag(sdp: String) -> String:
	const PREFIX: String = "a=ice-ufrag:"
	for line in sdp.split("\n", false):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with(PREFIX):
			return trimmed.substr(PREFIX.length())
	return ""


## ICE ufrag of the local description, used to tag outgoing candidates so the
## remote side can discard candidates from a superseded negotiation.
func get_local_ufrag() -> String:
	return _local_ufrag


## True once a remote description has been applied to this negotiation.
func has_remote_description() -> bool:
	return _remote_description_set
