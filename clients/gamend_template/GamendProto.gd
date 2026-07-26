class_name GamendProto
extends RefCounted

## Protobuf event decoding for gamend realtime transports.
##
## Mirrors the server's `GameServerWeb.EventCodec` mapping (wire contract:
## proto/gamend_realtime.proto in the game_server repo). Used by
## GamendRealtime when constructed with format "protobuf" and by
## GamendWebRTC DataChannels negotiated with protocol "protobuf".
##
## Decoded payloads match the JSON-mode payload keys, with two documented
## differences: timestamps are unix-millisecond ints (`*_ms` fields) and
## metadata/data values are already parsed.

const PB = preload("res://addons/gamend/proto/gamend_realtime_pb.gd")

## Game-registered metadata schemas: entity ("user"/"lobby"/"group"/"party")
## -> generated godobuf message class (e.g. MyGamePb.UserMeta) or a
## Callable(PackedByteArray) -> Variant.
static var _meta_schemas := {}


## Registers the game's metadata schema for an entity (mirrors the server
## plugin's UserMeta/LobbyMeta/GroupMeta/PartyMeta registration). With a
## message class the decoded payload's "metadata" becomes the typed message
## instance; with a Callable, whatever it returns. Without a registration,
## binary metadata is left on the payload as raw "metadata_pb" bytes.
static func register_meta_schema(entity: String, schema) -> void:
	_meta_schemas[entity] = schema


## Game-registered KV data schemas (mirrors the plugin's kv_schemas/0):
## exact key or "*"-suffixed prefix -> godobuf message class or Callable.
static var _kv_exact := {}
static var _kv_prefixes := []


## Registers the game's KV data schema for a key or "*"-suffixed key prefix
## (e.g. "loadout" or "match:*"). Exact keys win; longest prefix wins.
static func register_kv_schema(pattern: String, schema) -> void:
	if pattern.ends_with("*"):
		_kv_prefixes.append([pattern.substr(0, pattern.length() - 1), schema])
		_kv_prefixes.sort_custom(func(a, b): return a[0].length() > b[0].length())
	else:
		_kv_exact[pattern] = schema


static func _kv_schema_for(key: String) -> Variant:
	if _kv_exact.has(key):
		return _kv_exact[key]
	for entry in _kv_prefixes:
		if key.begins_with(entry[0]):
			return entry[1]
	return null


static func _decode_meta(entity: String, bytes: PackedByteArray) -> Variant:
	var schema = _meta_schemas.get(entity)
	if schema == null:
		return null
	if schema is Callable:
		return schema.call(bytes)
	var msg = schema.new()
	if msg.from_bytes(bytes) != PB.PB_ERR.NO_ERRORS:
		push_warning("GamendProto: failed to decode %s metadata" % entity)
		return null
	return msg


static func _put_meta(d: Dictionary, m, entity: String) -> Dictionary:
	if m.has_metadata_json():
		d["metadata"] = _json_bytes(m.get_metadata_json(), {})
	elif m.has_metadata_pb():
		var decoded = _decode_meta(entity, m.get_metadata_pb())
		if decoded != null:
			d["metadata"] = decoded
		else:
			d["metadata_pb"] = m.get_metadata_pb()
	return d


## Decodes a binary event payload received on `topic` for `event`.
## Returns a Dictionary, or null when the event has no protobuf mapping.
static func decode_event(topic: String, event: String, data: PackedByteArray) -> Variant:
	var kind := topic.split(":", true, 1)[0]

	match event:
		"kv_updated", "kv_deleted":
			return _kv(data)
		"notification_created":
			return _notification_payload(data)
		"chat_message_created", "chat_message_updated":
			return _chat(data)
		"chat_message_deleted":
			return _decode(PB.EntityId.new(), data, func(m): return {"id": m.get_id()})
		"quest_progress", "quest_completed", "quest_claimed":
			return _quest_progress(data)
		"ready_check_started", "ready_check_updated", "ready_check_passed", "ready_check_failed":
			return _ready_check(data)

	match kind:
		"user":
			match event:
				"updated":
					return _decode(PB.User.new(), data, _user_to_dict)
				"friend_updated":
					return _friend_update(data)
				"group_invite_accepted", "group_invite_cancelled", "group_join_request_approved", "group_join_request_rejected":
					return _decode(PB.GroupInviteEvent.new(), data, func(m): return {"group_id": m.get_group_id()})
				"party_invite_accepted", "party_invite_declined", "party_invite_cancelled":
					return _decode(PB.PartyInviteEvent.new(), data, func(m): return {"party_id": m.get_party_id(), "user_id": m.get_user_id()})
				"tournament_updated", "tournament_finished":
					return _decode(PB.TournamentEvent.new(), data, func(m): return {"tournament_id": m.get_tournament_id(), "slug": m.get_slug(), "state": m.get_state()})
				"tournament_match_ready", "tournament_match_resolved":
					return _decode(PB.TournamentMatchEvent.new(), data, func(m): return {
						"tournament_id": m.get_tournament_id(),
						"slug": m.get_slug(),
						"match_id": m.get_match_id(),
						"round": m.get_round(),
						"deadline_ms": m.get_deadline_ms(),
						"winner_entry_id": m.get_winner_entry_id(),
					})
				"match_found":
					return _decode(PB.MatchmakingFound.new(), data, func(m): return {"lobby_id": m.get_lobby_id(), "match_params": m.get_match_params()})
		"lobby":
			match event:
				"updated":
					return _decode(PB.Lobby.new(), data, _lobby_to_dict)
				"user_joined", "user_left", "user_kicked", "user_online", "user_offline":
					return _decode(PB.MemberEvent.new(), data, _member_event_to_dict)
				"host_changed":
					return _decode(PB.HostChanged.new(), data, func(m): return {"new_host_id": m.get_new_host_id(), "display_name": m.get_display_name()})
				"user_updated":
					return _decode(PB.UserBrief.new(), data, _brief_to_dict)
		"lobbies":
			match event:
				"lobby_created", "lobby_updated":
					return _decode(PB.Lobby.new(), data, _lobby_to_dict)
				"lobby_deleted", "lobby_membership_changed":
					return _decode(PB.EntityId.new(), data, func(m): return {"id": m.get_id()})
		"group":
			match event:
				"updated":
					return _decode(PB.Group.new(), data, _group_to_dict)
				"member_joined", "member_left", "member_kicked", "member_promoted", "member_demoted", "join_request_approved", "join_request_rejected", "member_online", "member_offline":
					return _decode(PB.MemberEvent.new(), data, _member_event_to_dict)
				"member_updated":
					return _decode(PB.UserBrief.new(), data, _brief_to_dict)
		"groups":
			match event:
				"group_created", "group_updated":
					return _decode(PB.Group.new(), data, _group_to_dict)
				"group_deleted":
					return _decode(PB.EntityId.new(), data, func(m): return {"id": m.get_id()})
		"party":
			match event:
				"updated":
					return _decode(PB.Party.new(), data, _party_to_dict)
				"member_joined", "member_left", "member_online", "member_offline":
					return _decode(PB.MemberEvent.new(), data, _member_event_to_dict)
				"member_updated":
					return _decode(PB.UserBrief.new(), data, _brief_to_dict)
				"disbanded":
					return _decode(PB.PartyRef.new(), data, func(m): return {"party_id": m.get_party_id()})

	return null


## Encodes an RPC call for the protobuf "events" DataChannel protocol.
static func encode_rpc_call(id: int, plugin: String, fn: String, args: Array) -> PackedByteArray:
	var env = PB.RtcEnvelope.new()
	var call = env.new_call_hook()
	call.set_id(id)
	call.set_plugin(plugin)
	call.set_fn(fn)
	call.set_args_json(JSON.stringify(args).to_utf8_buffer())
	return env.to_bytes()


## Encodes a typed RPC call. Encode the bytes with the game's schema
## (convention: <FnName>Request / <FnName>Reply, registered by the plugin);
## hooks without a registered schema error with hook_schema_missing.
static func encode_rpc_call_raw(id: int, plugin: String, fn: String, bytes: PackedByteArray) -> PackedByteArray:
	var env = PB.RtcEnvelope.new()
	var call = env.new_call_hook()
	call.set_id(id)
	call.set_plugin(plugin)
	call.set_fn(fn)
	call.set_args_raw(bytes)
	return env.to_bytes()


## Decodes an RPC reply/error envelope.
## Returns {id: int, ok: bool, data: Variant} / {id: int, ok: false, error: String},
## or null when the frame is not an RPC reply.
static func decode_rpc_reply(data: PackedByteArray) -> Variant:
	var env = PB.RtcEnvelope.new()
	if env.from_bytes(data) != PB.PB_ERR.NO_ERRORS:
		return null
	if env.has_hook_reply():
		var reply = env.get_hook_reply()
		if reply.has_data_raw():
			return {"id": reply.get_id(), "ok": true, "raw": true, "data": reply.get_data_raw()}
		return {"id": reply.get_id(), "ok": true, "data": _json_bytes(reply.get_data_json())}
	if env.has_hook_error():
		var err = env.get_hook_error()
		return {"id": err.get_id(), "ok": false, "error": err.get_error()}
	return null


#
# Message -> Dictionary converters (unset proto fields are omitted from the dict)
#

static func _decode(msg, data: PackedByteArray, to_dict: Callable) -> Variant:
	if msg.from_bytes(data) != PB.PB_ERR.NO_ERRORS:
		push_warning("GamendProto: failed to decode %s" % [msg])
		return null
	return to_dict.call(msg)


static func _json_bytes(bytes: PackedByteArray, default = null) -> Variant:
	if bytes.is_empty():
		return default
	return JSON.parse_string(bytes.get_string_from_utf8())


static func _user_to_dict(u) -> Dictionary:
	var d := {}
	if u.has_id(): d["id"] = u.get_id()
	if u.has_email(): d["email"] = u.get_email()
	if u.has_profile_url(): d["profile_url"] = u.get_profile_url()
	_put_meta(d, u, "user")
	if u.has_display_name(): d["display_name"] = u.get_display_name()
	if u.has_lobby_id(): d["lobby_id"] = u.get_lobby_id()
	if u.has_party_id(): d["party_id"] = u.get_party_id()
	if u.has_is_online(): d["is_online"] = u.get_is_online()
	if u.has_last_seen_at_ms(): d["last_seen_at_ms"] = u.get_last_seen_at_ms()
	if u.has_linked_providers():
		var lp = u.get_linked_providers()
		d["linked_providers"] = {
			"google": lp.get_google(),
			"facebook": lp.get_facebook(),
			"discord": lp.get_discord(),
			"apple": lp.get_apple(),
			"steam": lp.get_steam(),
			"device": lp.get_device(),
		}
	if u.has_has_password(): d["has_password"] = u.get_has_password()
	return d


static func _friend_update(data: PackedByteArray) -> Variant:
	var msg = PB.FriendUpdate.new()
	if msg.from_bytes(data) != PB.PB_ERR.NO_ERRORS:
		return null
	var friends := {}
	var map = msg.get_friends()
	for key in map:
		friends[key] = _user_to_dict(map[key])
	return {"friends": friends}


static func _brief_to_dict(b) -> Dictionary:
	var d := {}
	if b.has_id(): d["id"] = b.get_id()
	if b.has_display_name(): d["display_name"] = b.get_display_name()
	if b.has_profile_url(): d["profile_url"] = b.get_profile_url()
	_put_meta(d, b, "user")
	if b.has_is_online(): d["is_online"] = b.get_is_online()
	if b.has_is_activated(): d["is_activated"] = b.get_is_activated()
	if b.has_last_seen_at_ms(): d["last_seen_at_ms"] = b.get_last_seen_at_ms()
	return d


static func _member_event_to_dict(m) -> Dictionary:
	var d := {"user_id": m.get_user_id()}
	if m.has_display_name(): d["display_name"] = m.get_display_name()
	if m.has_id(): d["id"] = m.get_id()
	if m.has_profile_url(): d["profile_url"] = m.get_profile_url()
	_put_meta(d, m, "user")
	if m.has_is_online(): d["is_online"] = m.get_is_online()
	if m.has_is_activated(): d["is_activated"] = m.get_is_activated()
	if m.has_last_seen_at_ms(): d["last_seen_at_ms"] = m.get_last_seen_at_ms()
	if m.has_group_id(): d["group_id"] = m.get_group_id()
	return d


static func _notification_payload(data: PackedByteArray) -> Variant:
	return _decode(PB.Notification.new(), data, func(m): return {
		"id": m.get_id(),
		"sender_id": m.get_sender_id(),
		"sender_name": m.get_sender_name(),
		"recipient_id": m.get_recipient_id(),
		"title": m.get_title(),
		"content": m.get_content(),
		"metadata": _json_bytes(m.get_metadata_json(), {}),
		"inserted_at_ms": m.get_inserted_at_ms(),
	})


static func _chat(data: PackedByteArray) -> Variant:
	return _decode(PB.ChatMessage.new(), data, func(m):
		var d := {
			"id": m.get_id(),
			"content": m.get_content(),
			"metadata": _json_bytes(m.get_metadata_json(), {}),
			"sender_id": m.get_sender_id(),
			"sender_name": m.get_sender_name(),
			"chat_type": m.get_chat_type(),
			"chat_ref_id": m.get_chat_ref_id(),
			"inserted_at_ms": m.get_inserted_at_ms(),
		}
		if m.has_updated_at_ms(): d["updated_at_ms"] = m.get_updated_at_ms()
		if m.has_sender_email(): d["sender_email"] = m.get_sender_email()
		return d)


static func _quest_progress(data: PackedByteArray) -> Variant:
	return _decode(PB.QuestProgress.new(), data, func(m):
		var d := {
			"id": m.get_id(),
			"user_id": m.get_user_id(),
			"quest_key": m.get_quest_key(),
			"period_key": m.get_period_key(),
			"objective_progress": m.get_objective_progress(),
			"status": m.get_status(),
			"metadata": _json_bytes(m.get_metadata_json(), {}),
			"inserted_at_ms": m.get_inserted_at_ms(),
			"updated_at_ms": m.get_updated_at_ms(),
		}
		if m.has_completed_at_ms(): d["completed_at_ms"] = m.get_completed_at_ms()
		if m.has_claimed_at_ms(): d["claimed_at_ms"] = m.get_claimed_at_ms()
		return d)


static func _ready_check(data: PackedByteArray) -> Variant:
	return _decode(PB.ReadyCheckState.new(), data, func(m):
		var participants := []
		for p in m.get_participants():
			participants.append({
				"user_id": p.get_user_id(),
				"display_name": p.get_display_name(),
				"state": p.get_state(),
			})
		# `participants` stays empty for kind "accept": that check reports counts
		# only, so a match that may still dissolve keeps its roster private.
		return {
			"id": m.get_id(),
			"kind": m.get_kind(),
			"status": m.get_status(),
			"lobby_id": m.get_lobby_id(),
			"party_id": m.get_party_id(),
			"deadline_ms": m.get_deadline_ms(),
			"total": m.get_total(),
			"ready_count": m.get_ready_count(),
			"your_state": m.get_your_state(),
			"reason": m.get_reason(),
			"participants": participants,
		})


static func _lobby_to_dict(l) -> Dictionary:
	var d := {}
	if l.has_id(): d["id"] = l.get_id()
	if l.has_title(): d["title"] = l.get_title()
	if l.has_host_id(): d["host_id"] = l.get_host_id()
	if l.has_host_name(): d["host_name"] = l.get_host_name()
	if l.has_hostless(): d["hostless"] = l.get_hostless()
	if l.has_max_users(): d["max_users"] = l.get_max_users()
	if l.has_is_hidden(): d["is_hidden"] = l.get_is_hidden()
	if l.has_is_locked(): d["is_locked"] = l.get_is_locked()
	_put_meta(d, l, "lobby")
	if l.has_is_passworded(): d["is_passworded"] = l.get_is_passworded()
	if l.has_slowdown(): d["slowdown"] = l.get_slowdown()
	if l.has_spectator_count(): d["spectator_count"] = l.get_spectator_count()
	if l.has_has_members():
		var members := []
		for m in l.get_members():
			members.append(_brief_to_dict(m))
		d["members"] = members
	return d


static func _group_to_dict(g) -> Dictionary:
	var d := {}
	if g.has_id(): d["id"] = g.get_id()
	if g.has_title(): d["title"] = g.get_title()
	if g.has_description(): d["description"] = g.get_description()
	if g.has_type(): d["type"] = g.get_type()
	if g.has_max_members(): d["max_members"] = g.get_max_members()
	if g.has_creator_id(): d["creator_id"] = g.get_creator_id()
	if g.has_creator_name(): d["creator_name"] = g.get_creator_name()
	_put_meta(d, g, "group")
	if g.has_member_count(): d["member_count"] = g.get_member_count()
	if g.has_slowdown(): d["slowdown"] = g.get_slowdown()
	if g.has_inserted_at_ms(): d["inserted_at_ms"] = g.get_inserted_at_ms()
	if g.has_updated_at_ms(): d["updated_at_ms"] = g.get_updated_at_ms()
	return d


static func _party_to_dict(p) -> Dictionary:
	var d := {}
	if p.has_id(): d["id"] = p.get_id()
	if p.has_leader_id(): d["leader_id"] = p.get_leader_id()
	if p.has_leader_name(): d["leader_name"] = p.get_leader_name()
	if p.has_max_size(): d["max_size"] = p.get_max_size()
	_put_meta(d, p, "party")
	if p.has_has_members():
		var members := []
		for m in p.get_members():
			members.append(_brief_to_dict(m))
		d["members"] = members
	if p.has_inserted_at_ms(): d["inserted_at_ms"] = p.get_inserted_at_ms()
	if p.has_updated_at_ms(): d["updated_at_ms"] = p.get_updated_at_ms()
	return d


static func _kv(data: PackedByteArray) -> Variant:
	return _decode(PB.KvEntry.new(), data, func(m):
		var d := {"key": m.get_key()}
		if m.has_user_id(): d["user_id"] = m.get_user_id()
		if m.has_lobby_id(): d["lobby_id"] = m.get_lobby_id()
		if m.has_data_json(): d["data"] = _json_bytes(m.get_data_json())
		if m.has_data_pb():
			var schema = _kv_schema_for(m.get_key())
			if schema == null:
				d["data_pb"] = m.get_data_pb()
			elif schema is Callable:
				d["data"] = schema.call(m.get_data_pb())
			else:
				var msg = schema.new()
				if msg.from_bytes(m.get_data_pb()) == PB.PB_ERR.NO_ERRORS:
					d["data"] = msg
				else:
					d["data_pb"] = m.get_data_pb()
		if m.has_metadata_json(): d["metadata"] = _json_bytes(m.get_metadata_json(), {})
		return d)
