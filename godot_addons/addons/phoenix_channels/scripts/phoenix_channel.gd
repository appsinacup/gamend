class_name PhoenixChannel
extends Node

const DEFAULT_REJOIN_AFTER_SECONDS := [1, 2, 5, 10]

const TOPIC_PHOENIX := "phoenix"
const STATUS = {
	ok = "ok",
	error = "error",
	timeout = "timeout"
}
const PRESENCE_EVENTS := {
	diff = "presence_diff",
	state = "presence_state"
}
const CHANNEL_EVENTS := {
	close = "phx_close",
	error = "phx_error",
	join = "phx_join",
	reply = "phx_reply",
	leave = "phx_leave"
}

enum ChannelStates {CLOSED, ERRORED, JOINED, JOINING, LEAVING}

signal on_join_result(event, payload)
signal on_event(event, payload, status)
## The reply to one push: `ref` is the `last_push_ref` read just after it.
signal on_reply(ref, event, payload, status)
signal on_error(error)
signal on_close(params)	

var _state = ChannelStates.CLOSED
var _topic := "" : get = get_topic, set = set_topic
var _params := {}
var _joined_once := false
var _socket
var _join_ref := ""
var _pending_refs := {}
## The ref of the latest push, which names its reply in `on_reply`.
var last_push_ref := ""

var _rejoin_timer : Timer
var _should_rejoin_until_connected := false
var _rejoin_pos := -1

var _presence : PhoenixPresence
var _params_provider: Callable  ## If set, called to get fresh params dict before each join/rejoin

func _init(socket,topic : String,params : Dictionary = {},presence = null):
	assert(topic != TOPIC_PHOENIX)
	_socket = socket
	_topic = topic
	_params = params
	
	_presence = presence
	
	_rejoin_timer = Timer.new()
	_rejoin_timer.set_autostart(false)
	var _error = _rejoin_timer.connect("timeout",Callable(self,"_on_Timer_timeout"))
	add_child(_rejoin_timer)
	
func _exit_tree():
	var _success = leave()
	
	"""
	Leaving the channel with leave() leads to the chain of events that eventually call on_close,
	but then in this specific case of exiting the tree, the event is not called,
	so force call it from here.
	"""	
	emit_signal("on_close", {message = "exit tree"})

#
# Interface
#

func is_closed() -> bool: return _state == ChannelStates.CLOSED
func is_errored() -> bool: return _state == ChannelStates.ERRORED
func is_joined() -> bool: return _state == ChannelStates.JOINED
func is_joining() -> bool: return _state == ChannelStates.JOINING
func is_leaving() -> bool: return _state == ChannelStates.LEAVING

func set_topic(topic : String):
	assert(is_closed())		
	_topic = topic
	
func get_topic() -> String:
	return _topic

func leave() -> bool:
	if !is_leaving() and !is_closed():
		var _success = push(CHANNEL_EVENTS.leave, {})
		_state = ChannelStates.LEAVING
		return true
		
	return false

func join() -> bool:
	if not _joined_once:
		return _rejoin()
	
	return false

func close(params := {}, should_rejoin := false):
	_joined_once = false
	_state = ChannelStates.CLOSED
	_pending_refs.clear()
	if _presence: _presence.clear()
	emit_signal("on_close", params)
	
	if should_rejoin:
		_start_rejoin()
		
func push(event : String, payload : Dictionary = {}) -> bool:
	if not can_push(event):
		return false

	# todo: start timeout	
	
	var ref = _socket.make_ref()
	_pending_refs[ref] = event
	last_push_ref = ref
	_socket.push(_socket.compose_message(event, payload, _topic, ref, _join_ref))
	return true

func can_push(event : String) -> bool:
	return _socket.can_push(event) and is_joined()
	
## A message stamped with a join_ref belongs to THAT join and to no other, so a
## message for a join this channel has already replaced is dropped (phoenix.js
## does the same). The old guard read `topic == CHANNEL_EVENTS.close` — the
## TOPIC against the EVENT names — so it was never true and every stale message
## was delivered anyway. A close for a dead join then reached the live channel,
## failed the ref test in trigger(), and went out as an ordinary broadcast: that
## is what "[gamend] Unhandled user event: phx_close" is.
func is_member(topic, join_ref, event := "") -> bool:
	if topic != _topic:
		return false

	if join_ref != "" and _join_ref != "" and join_ref != _join_ref:
		if event == CHANNEL_EVENTS.close or event == CHANNEL_EVENTS.error:
			# Loud on purpose. Dropping this silently is what made the original
			# bug unreadable: you want to know a channel died for a join you are
			# no longer on, and not confuse it with the live one dying.
			push_warning(
				"[phoenix] Dropped %s on %s for a stale join (message join_ref=%s, current=%s)"
				% [event, _topic, join_ref, _join_ref]
			)
		return false

	return true

func raw_trigger(event : String, payload := {}):
	trigger(PhoenixMessage.new(_topic, event, PhoenixMessage.NO_REPLY_REF, _join_ref, payload))
			
func trigger(message : PhoenixMessage):
	var status : String = STATUS.ok
	# A protobuf push/broadcast payload is raw bytes and carries no status —
	# only JSON payloads and the decoded _BIN_REPLY wrapper are Dictionaries.
	var payload = message.get_payload()
	if payload is Dictionary and payload.has("status"):
		status = payload.status

	var event := message.get_event()

	# Close and error are bound by EVENT, the way phoenix.js binds them — NOT by
	# ref. Gating them on `ref == _join_ref` meant a close whose ref did not line
	# up was handed on as an ordinary broadcast, and nothing here ever learned
	# the channel was gone: the state stayed JOINED against a server process that
	# no longer exists, no rejoin was scheduled, and the registry kept the topic,
	# so add_channel() hands back the dead object instead of joining. On a
	# `lobby:` channel that failure is completely silent — the next level waits
	# out its whole start timeout for word data on a channel that will never
	# speak again. is_member() above is what keeps a STALE close from getting
	# this far; anything that reaches here is about the join we are on now.
	if event == CHANNEL_EVENTS.close:
		if _state == ChannelStates.LEAVING:
			close({reason = "leave"})
		else:
			# will_reconnect says the topic is coming back, so whoever holds the
			# channel registry has to keep it. Without it the two layers disagree
			# about lifetime: the rejoin succeeds while the registry has already
			# dropped the topic, and every request after that fails with
			# "No channel found".
			close({reason = "unexpected_close", will_reconnect = true}, true)
		return

	if event == CHANNEL_EVENTS.error:
		var reset_rejoin := is_joined()
		_error(message.get_payload())
		_start_rejoin(reset_rejoin)
		return

	# Event related to the channel connection/status. The empty-ref guard keeps a
	# broadcast that carries no ref from being read as a join reply before this
	# channel has ever joined (_join_ref is "" until the join is pushed).
	if _join_ref != "" and message.get_ref() == _join_ref:
		_state = ChannelStates.JOINED if status == STATUS.ok else ChannelStates.ERRORED

		if _state == ChannelStates.JOINED:
			_joined_once = true
			_rejoin_pos = -1
		else:
			_joined_once = false
			_start_rejoin()

		emit_signal("on_join_result", status, message.get_response())
		return

	# Event related to push replies, presence or broadcasts
	if event == PRESENCE_EVENTS.diff or event == PRESENCE_EVENTS.state:
		if _presence:
			emit_signal("on_event", event, message.get_payload(), STATUS.ok)
		return

	# Try to get event related to the reply
	if event == CHANNEL_EVENTS.reply:
		var pending_event = _get_pending_ref(message.get_ref())
		if pending_event:
			event = pending_event
			var _success = _pending_refs.erase(message.get_ref())
			emit_signal("on_reply", message.get_ref(), event, message.get_response(), status)

	if event != CHANNEL_EVENTS.leave:
		emit_signal("on_event", event, message.get_response(), status)

#
# Implementation
#

func _error(error):
	_state = ChannelStates.ERRORED
	_pending_refs.clear()
	if _presence: _presence.clear()
	emit_signal("on_error", error)
	
func _start_rejoin(reset := false):
	if reset:
		_rejoin_pos = -1
		_joined_once = false		
		
	if _rejoin_pos < DEFAULT_REJOIN_AFTER_SECONDS.size() - 1:
		_rejoin_pos += 1
		
	_rejoin_timer.set_wait_time(DEFAULT_REJOIN_AFTER_SECONDS[_rejoin_pos])
	
	if _rejoin_timer.is_stopped():
		_rejoin_timer.start()

	_should_rejoin_until_connected = true
	
func _rejoin() -> bool:
	if _state == ChannelStates.JOINING or _state == ChannelStates.JOINED:
		return false
		
	else:
		if _socket.can_push(CHANNEL_EVENTS.join):
			if _should_rejoin_until_connected and !_rejoin_timer.is_stopped():
				_rejoin_timer.stop()
				_should_rejoin_until_connected = false
				
			_state = ChannelStates.JOINING
			
			# Refresh params from provider before rejoining (ensures fresh tokens)
			if _params_provider.is_valid():
				_params = _params_provider.call()
			
			var ref = _socket.make_ref()
			_join_ref = ref
			_socket.push(_socket.compose_message(CHANNEL_EVENTS.join, _params, _topic, ref, _join_ref))
			return true
			
		else:
			_should_rejoin_until_connected = true
			return false
			
func _get_pending_ref(ref):	
	if _pending_refs.has(ref):
		return _pending_refs[ref]
			
	return null
	
#
# Listeners
#

func _on_Timer_timeout():
	if _should_rejoin_until_connected:
		if not _joined_once:
			var _success = _rejoin()
