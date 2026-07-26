/**
 * GamendProto — protobuf event decoding for game_server realtime transports.
 *
 * Mirrors the server's `GameServerWeb.EventCodec` mapping (single wire
 * contract: proto/gamend_realtime.proto). Used by GameRealtime when
 * constructed with `format: 'protobuf'` and by GameWebRTC DataChannels
 * negotiated with `protocol: 'protobuf'`.
 *
 * Decoded payloads differ from JSON payloads in two documented ways:
 *   - timestamps are unix-millisecond numbers (`*_ms` suffixed fields)
 *   - arbitrary JSON values (metadata, KV data) are already parsed from
 *     their bytes form back into JS values
 */

import { gamend } from './gamend_realtime.pb.js'

const PB = gamend.realtime.v1

const td = new TextDecoder()

// Game-registered metadata schemas: entity ('user'|'lobby'|'group'|'party')
// -> protobufjs message class (or a custom (bytes) => value decoder).
const metaSchemas = {}

/**
 * Registers the game's metadata schema for an entity so decoded events expose
 * `metadata` as a plain object (mirrors the plugin-side UserMeta/LobbyMeta/...
 * registration). Without a registration, binary metadata is left on the
 * payload as raw `metadata_pb` bytes.
 *
 * @param {string} entity - 'user' | 'lobby' | 'group' | 'party'
 * @param {Object|Function} schema - protobufjs class, or (Uint8Array) => value
 */
export function registerMetaSchema(entity, schema) {
  metaSchemas[entity] = schema
}

// Game-registered KV data schemas: exact key or '*'-suffixed prefix pattern
// -> protobufjs class (or a custom (bytes) => value decoder). Mirrors the
// plugin's kv_schemas/0 registration.
const kvSchemas = { exact: {}, prefixes: [] }

/**
 * Registers the game's KV data schema for a key or key-prefix pattern
 * (e.g. 'loadout' or 'match:*'). Exact keys win; longest prefix wins.
 * @param {string} pattern
 * @param {Object|Function} schema - protobufjs class, or (Uint8Array) => value
 */
export function registerKvSchema(pattern, schema) {
  if (pattern.endsWith('*')) {
    kvSchemas.prefixes.push([pattern.slice(0, -1), schema])
    kvSchemas.prefixes.sort((a, b) => b[0].length - a[0].length)
  } else {
    kvSchemas.exact[pattern] = schema
  }
}

function kvSchemaFor(key) {
  if (kvSchemas.exact[key]) return kvSchemas.exact[key]
  const hit = kvSchemas.prefixes.find(([prefix]) => key.startsWith(prefix))
  return hit ? hit[1] : null
}

function withMeta(obj, entity) {
  if (obj.metadata_pb != null && obj.metadata_pb.length) {
    const schema = metaSchemas[entity]
    if (schema) {
      obj.metadata =
        typeof schema === 'function'
          ? schema(obj.metadata_pb)
          : schema.toObject(schema.decode(obj.metadata_pb), { defaults: true, longs: Number })
      delete obj.metadata_pb
    }
  }
  return obj
}

/** Parses a bytes-JSON field; empty/absent bytes decode to defaultValue. */
function fromJsonBytes(bytes, defaultValue = undefined) {
  if (!bytes || bytes.length === 0) return defaultValue
  return JSON.parse(td.decode(bytes))
}

/** Parses JSON-bytes fields into their JSON-mode field names. */
function withParsedJson(obj, fields) {
  for (const [src, dest] of fields) {
    if (obj[src] !== undefined && obj[src] !== null) {
      obj[dest] = fromJsonBytes(obj[src], {})
      if (src !== dest) delete obj[src]
    }
  }
  return obj
}

function decodeUser(bin) {
  const u = PB.User.decode(bin)
  const out = PB.User.toObject(u, { defaults: false, longs: Number })
  return withMeta(withParsedJson(out, [['metadata_json', 'metadata']]), 'user')
}

const decoders = {
  user: {
    updated: decodeUser,
    friend_updated: (bin) => {
      const msg = PB.FriendUpdate.decode(bin)
      const friends = {}
      for (const [id, user] of Object.entries(msg.friends)) {
        friends[id] = withMeta(
          withParsedJson(
            PB.User.toObject(user, { defaults: false, longs: Number }),
            [['metadata_json', 'metadata']]
          ),
          'user'
        )
      }
      return { friends }
    },
    group_invite_accepted: (bin) => PB.GroupInviteEvent.toObject(PB.GroupInviteEvent.decode(bin)),
    group_invite_cancelled: (bin) => PB.GroupInviteEvent.toObject(PB.GroupInviteEvent.decode(bin)),
    group_join_request_approved: (bin) => PB.GroupInviteEvent.toObject(PB.GroupInviteEvent.decode(bin)),
    group_join_request_rejected: (bin) => PB.GroupInviteEvent.toObject(PB.GroupInviteEvent.decode(bin)),
    party_invite_accepted: (bin) => PB.PartyInviteEvent.toObject(PB.PartyInviteEvent.decode(bin)),
    party_invite_declined: (bin) => PB.PartyInviteEvent.toObject(PB.PartyInviteEvent.decode(bin)),
    party_invite_cancelled: (bin) => PB.PartyInviteEvent.toObject(PB.PartyInviteEvent.decode(bin)),
    tournament_updated: (bin) => PB.TournamentEvent.toObject(PB.TournamentEvent.decode(bin)),
    tournament_finished: (bin) => PB.TournamentEvent.toObject(PB.TournamentEvent.decode(bin)),
    tournament_match_ready: (bin) =>
      PB.TournamentMatchEvent.toObject(PB.TournamentMatchEvent.decode(bin), {
        defaults: true,
        longs: Number,
      }),
    tournament_match_resolved: (bin) =>
      PB.TournamentMatchEvent.toObject(PB.TournamentMatchEvent.decode(bin), {
        defaults: true,
        longs: Number,
      }),
    match_found: (bin) =>
      PB.MatchmakingFound.toObject(PB.MatchmakingFound.decode(bin), { defaults: true }),
  },
  lobby: {
    updated: (bin) => decodeLobby(bin),
    user_joined: (bin) => decodeMember(bin),
    user_left: (bin) => decodeMember(bin),
    user_kicked: (bin) => decodeMember(bin),
    host_changed: (bin) => PB.HostChanged.toObject(PB.HostChanged.decode(bin)),
    user_online: (bin) => decodeMember(bin),
    user_offline: (bin) => decodeMember(bin),
    user_updated: (bin) => decodeBrief(bin),
  },
  lobbies: {
    lobby_created: (bin) => decodeLobby(bin),
    lobby_updated: (bin) => decodeLobby(bin),
    lobby_deleted: (bin) => PB.EntityId.toObject(PB.EntityId.decode(bin)),
    lobby_membership_changed: (bin) => PB.EntityId.toObject(PB.EntityId.decode(bin)),
  },
  group: {
    updated: (bin) => decodeGroup(bin),
    member_joined: (bin) => decodeMember(bin),
    member_left: (bin) => decodeMember(bin),
    member_kicked: (bin) => decodeMember(bin),
    member_promoted: (bin) => decodeMember(bin),
    member_demoted: (bin) => decodeMember(bin),
    join_request_approved: (bin) => decodeMember(bin),
    join_request_rejected: (bin) => decodeMember(bin),
    member_online: (bin) => decodeMember(bin),
    member_offline: (bin) => decodeMember(bin),
    member_updated: (bin) => decodeBrief(bin),
  },
  groups: {
    group_created: (bin) => decodeGroup(bin),
    group_updated: (bin) => decodeGroup(bin),
    group_deleted: (bin) => PB.EntityId.toObject(PB.EntityId.decode(bin)),
  },
  party: {
    updated: (bin) =>
      withMeta(
        withParsedJson(
          PB.Party.toObject(PB.Party.decode(bin), { defaults: false, longs: Number }),
          [['metadata_json', 'metadata']]
        ),
        'party'
      ),
    member_joined: (bin) => decodeMember(bin),
    member_left: (bin) => decodeMember(bin),
    member_online: (bin) => decodeMember(bin),
    member_offline: (bin) => decodeMember(bin),
    member_updated: (bin) => decodeBrief(bin),
    disbanded: (bin) => PB.PartyRef.toObject(PB.PartyRef.decode(bin)),
  },
}

function decodeLobby(bin) {
  return withMeta(
    withParsedJson(
      PB.Lobby.toObject(PB.Lobby.decode(bin), { defaults: false, longs: Number }),
      [['metadata_json', 'metadata']]
    ),
    'lobby'
  )
}

function decodeGroup(bin) {
  return withMeta(
    withParsedJson(
      PB.Group.toObject(PB.Group.decode(bin), { defaults: false, longs: Number }),
      [['metadata_json', 'metadata']]
    ),
    'group'
  )
}

function decodeMember(bin) {
  return withMeta(
    withParsedJson(
      PB.MemberEvent.toObject(PB.MemberEvent.decode(bin), { defaults: false, longs: Number }),
      [['metadata_json', 'metadata']]
    ),
    'user'
  )
}

function decodeBrief(bin) {
  return withMeta(
    withParsedJson(
      PB.UserBrief.toObject(PB.UserBrief.decode(bin), { defaults: false, longs: Number }),
      [['metadata_json', 'metadata']]
    ),
    'user'
  )
}

// Events with the same shape on every topic.
const anyTopic = {
  kv_updated: (bin) => decodeKv(bin),
  kv_deleted: (bin) => decodeKv(bin),
  notification_created: (bin) =>
    withParsedJson(
      PB.Notification.toObject(PB.Notification.decode(bin), { defaults: true, longs: Number }),
      [['metadata_json', 'metadata']]
    ),
  chat_message_created: (bin) => decodeChat(bin),
  chat_message_updated: (bin) => decodeChat(bin),
  chat_message_deleted: (bin) => PB.EntityId.toObject(PB.EntityId.decode(bin)),
  quest_progress: (bin) => decodeQuestProgress(bin),
  quest_completed: (bin) => decodeQuestProgress(bin),
  quest_claimed: (bin) => decodeQuestProgress(bin),
  // Ready checks arrive on lobby:<id> and, for an accept check, on user:<id>.
  ready_check_started: (bin) => decodeReadyCheck(bin),
  ready_check_updated: (bin) => decodeReadyCheck(bin),
  ready_check_passed: (bin) => decodeReadyCheck(bin),
  ready_check_failed: (bin) => decodeReadyCheck(bin),
}

// `participants` is absent on an accept check: it carries counts only, so a
// pending match does not reveal who you were paired with.
function decodeReadyCheck(bin) {
  return PB.ReadyCheckState.toObject(PB.ReadyCheckState.decode(bin), {
    defaults: true,
    longs: Number,
    arrays: true,
  })
}

function decodeQuestProgress(bin) {
  return withParsedJson(
    PB.QuestProgress.toObject(PB.QuestProgress.decode(bin), { defaults: true, longs: Number }),
    [['metadata_json', 'metadata']]
  )
}

function decodeKv(bin) {
  const msg = PB.KvEntry.decode(bin)
  const kv = PB.KvEntry.toObject(msg, { defaults: false })
  if (msg.data_json && msg.data_json.length) kv.data = fromJsonBytes(msg.data_json)
  if (msg.metadata_json && msg.metadata_json.length) kv.metadata = fromJsonBytes(msg.metadata_json, {})
  if (msg.data_pb && msg.data_pb.length) {
    const schema = kvSchemaFor(msg.key)
    if (schema) {
      kv.data =
        typeof schema === 'function'
          ? schema(msg.data_pb)
          : schema.toObject(schema.decode(msg.data_pb), { defaults: true, longs: Number })
      delete kv.data_pb
    }
    // unregistered: raw bytes stay on kv.data_pb
  } else {
    delete kv.data_pb
  }
  delete kv.data_json
  delete kv.metadata_json
  return kv
}

function decodeChat(bin) {
  return withParsedJson(
    PB.ChatMessage.toObject(PB.ChatMessage.decode(bin), { defaults: true, longs: Number }),
    [['metadata_json', 'metadata']]
  )
}

/**
 * Decodes a binary event payload received on `topic` for `event`.
 * Returns the decoded object, or null when the event has no protobuf
 * mapping (callers should treat the frame as opaque).
 *
 * @param {string} topic  - Phoenix topic, e.g. "user:<id>" or "lobby:<id>"
 * @param {string} event  - event name, e.g. "updated"
 * @param {ArrayBuffer|Uint8Array} data
 */
export function decodeEvent(topic, event, data) {
  const kind = topic.split(':', 1)[0]
  const bin = data instanceof Uint8Array ? data : new Uint8Array(data)
  const decoder = (decoders[kind] && decoders[kind][event]) || anyTopic[event]
  return decoder ? decoder(bin) : null
}

/** Raw generated messages, for advanced use (RtcEnvelope etc.). */
export { PB }
