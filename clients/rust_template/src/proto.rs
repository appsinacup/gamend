//! Protobuf realtime events, as `RealtimeFormat::Protobuf` asks the server to
//! send them: the binary payloads `proto/gamend_realtime.proto` describes, turned
//! back into the payload the event has in JSON mode.
//!
//! No protobuf library: the file uses a small part of the language (proto3
//! scalars, messages, optional, repeated, map<string, V>, oneof), so a field
//! table generated from it (`src/generated/proto_schema.rs`) and a wire reader
//! do.

use std::collections::BTreeMap;

use serde_json::{json, Map, Value};

use crate::generated::proto_schema::MESSAGES;
use crate::json::{integer, parse};

const VARINT: u32 = 0;
const FIXED64: u32 = 1;
const LENGTH: u32 = 2;
const FIXED32: u32 = 5;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Bool,
    Int32,
    Int64,
    Uint32,
    Uint64,
    Sint32,
    Sint64,
    String,
    Bytes,
    Message,
}

/// Singular: proto3 implicit presence. Optional: explicit presence (and oneof
/// members). Map: `map<string, type>`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Label {
    Singular,
    Optional,
    Repeated,
    Map,
}

#[derive(Clone, Copy, Debug)]
pub struct Field {
    pub number: u32,
    pub name: &'static str,
    pub label: Label,
    /// The value's type; a map's value type.
    pub kind: Kind,
    /// For `Kind::Message`: its index in the table.
    pub message: Option<usize>,
}

#[derive(Clone, Copy, Debug)]
pub struct Message {
    pub name: &'static str,
    pub fields: &'static [Field],
}

/// Offered every bytes field that is not `*_json` (a game's own protobuf in
/// `metadata_pb` or `data_pb`): the message and field it is in, its bytes, and
/// the fields decoded so far. A value replaces the field, under its name without
/// `_pb`; nothing leaves it as base64.
pub type BytesHook<'a> = &'a dyn Fn(&str, &str, &[u8], &Value) -> Option<Value>;

fn read_varint(input: &mut &[u8]) -> Option<u64> {
    let mut out = 0u64;
    let mut shift = 0;
    while shift < 64 {
        let (byte, rest) = input.split_first()?;
        *input = rest;
        out |= u64::from(byte & 0x7F) << shift;
        if byte & 0x80 == 0 {
            return Some(out);
        }
        shift += 7;
    }
    None
}

fn read_length<'a>(input: &mut &'a [u8]) -> Option<&'a [u8]> {
    let size = usize::try_from(read_varint(input)?).ok()?;
    if size > input.len() {
        return None;
    }
    let (span, rest) = input.split_at(size);
    *input = rest;
    Some(span)
}

fn take(input: &mut &[u8], size: usize) -> Option<()> {
    if input.len() < size {
        return None;
    }
    *input = &input[size..];
    Some(())
}

fn skip(input: &mut &[u8], wire: u32) -> Option<()> {
    match wire {
        VARINT => read_varint(input).map(|_| ()),
        FIXED64 => take(input, 8),
        LENGTH => read_length(input).map(|_| ()),
        FIXED32 => take(input, 4),
        _ => None,
    }
}

fn field_of(message: &Message, number: u32) -> Option<&'static Field> {
    message.fields.iter().find(|field| field.number == number)
}

fn scalar(kind: Kind, raw: u64) -> Value {
    match kind {
        Kind::Bool => Value::from(raw != 0),
        Kind::Int32 => Value::from(raw as i32),
        Kind::Int64 => Value::from(raw as i64),
        Kind::Uint32 => Value::from(raw as u32),
        Kind::Uint64 => Value::from(raw),
        Kind::Sint32 | Kind::Sint64 => Value::from(((raw >> 1) as i64) ^ -((raw & 1) as i64)),
        _ => Value::Null,
    }
}

// A bytes field as the JSON payload has it: `metadata_json` becomes the parsed
// `metadata` (an empty or unreadable one an empty object); anything else goes to
// the hook, and stays base64 under its own name when nothing reads it.
fn put_bytes(
    out: &mut Map<String, Value>,
    message: &Message,
    name: &str,
    bytes: &[u8],
    hook: Option<BytesHook<'_>>,
) {
    if let Some(base) = name.strip_suffix("_json") {
        let parsed = if bytes.is_empty() { None } else { parse(bytes) };
        out.insert(base.to_string(), parsed.unwrap_or_else(|| json!({})));
        return;
    }
    if bytes.is_empty() {
        return;
    }
    if let Some(hook) = hook {
        let decoded = Value::Object(out.clone());
        if let Some(read) = hook(message.name, name, bytes, &decoded) {
            out.insert(name.strip_suffix("_pb").unwrap_or(name).to_string(), read);
            return;
        }
    }
    out.insert(name.to_string(), Value::String(base64(bytes)));
}

fn default_of(field: &Field) -> Value {
    match field.kind {
        Kind::Bool => Value::Bool(false),
        Kind::String => Value::String(String::new()),
        Kind::Message | Kind::Bytes => Value::Null,
        _ => Value::from(0),
    }
}

enum Decoded<'a> {
    Value(Value),
    Bytes(&'a [u8]),
}

fn decode_value<'a>(
    field: &Field,
    wire: u32,
    input: &mut &'a [u8],
    defaults: bool,
    hook: Option<BytesHook<'_>>,
) -> Option<Decoded<'a>> {
    if matches!(field.kind, Kind::String | Kind::Bytes | Kind::Message) {
        if wire != LENGTH {
            return None;
        }
        let span = read_length(input)?;
        return Some(match field.kind {
            Kind::String => {
                Decoded::Value(Value::String(String::from_utf8_lossy(span).into_owned()))
            }
            Kind::Bytes => Decoded::Bytes(span),
            _ => Decoded::Value(decode(&MESSAGES[field.message?], span, defaults, hook)?),
        });
    }
    if wire != VARINT {
        return None;
    }
    Some(Decoded::Value(scalar(field.kind, read_varint(input)?)))
}

// One `map<string, V>` entry: a message whose field 1 is the key, 2 the value.
fn decode_entry(
    field: &Field,
    mut entry: &[u8],
    defaults: bool,
    hook: Option<BytesHook<'_>>,
) -> Option<(String, Value)> {
    let mut key = String::new();
    let mut value = default_of(field);
    while !entry.is_empty() {
        let tag = read_varint(&mut entry)?;
        let number = (tag >> 3) as u32;
        let wire = (tag & 7) as u32;
        if number == 1 && wire == LENGTH {
            key = String::from_utf8_lossy(read_length(&mut entry)?).into_owned();
        } else if number == 2 {
            if let Decoded::Value(read) = decode_value(field, wire, &mut entry, defaults, hook)? {
                value = read;
            }
        } else {
            skip(&mut entry, wire)?;
        }
    }
    Some((key, value))
}

fn put_varint(out: &mut Vec<u8>, mut value: u64) {
    while value >= 0x80 {
        out.push((value & 0x7F) as u8 | 0x80);
        value >>= 7;
    }
    out.push(value as u8);
}

fn put_tag(out: &mut Vec<u8>, number: u32, wire: u32) {
    put_varint(out, (u64::from(number) << 3) | u64::from(wire));
}

fn put_length(out: &mut Vec<u8>, number: u32, bytes: &[u8]) {
    put_tag(out, number, LENGTH);
    put_varint(out, bytes.len() as u64);
    out.extend_from_slice(bytes);
}

fn bytes_of(value: &Value) -> Option<Vec<u8>> {
    match value {
        Value::String(text) => Some(text.as_bytes().to_vec()),
        Value::Array(items) => Some(items.iter().map(|item| integer(item) as u8).collect()),
        _ => None,
    }
}

fn encode_value(out: &mut Vec<u8>, number: u32, field: &Field, value: &Value) {
    match field.kind {
        Kind::String | Kind::Bytes => {
            if let Some(bytes) = bytes_of(value) {
                put_length(out, number, &bytes);
            }
        }
        Kind::Message => {
            if let Some(index) = field.message {
                put_length(out, number, &encode(&MESSAGES[index], value));
            }
        }
        Kind::Bool => {
            put_tag(out, number, VARINT);
            put_varint(out, u64::from(value.as_bool().unwrap_or(false)));
        }
        Kind::Sint32 | Kind::Sint64 => {
            let n = integer(value);
            put_tag(out, number, VARINT);
            put_varint(out, ((n as u64) << 1) ^ ((n >> 63) as u64));
        }
        _ => {
            put_tag(out, number, VARINT);
            put_varint(out, integer(value) as u64);
        }
    }
}

pub fn find(name: &str) -> Option<&'static Message> {
    MESSAGES.iter().find(|message| message.name == name)
}

/// `bytes` as JSON with the message's field names. `defaults` fills the fields a
/// proto3 message leaves out for being zero, as protobufjs's
/// `toObject({defaults: true})` does; explicitly optional ones stay absent.
/// `X_json` bytes come out parsed, as `X`; other bytes as base64.
pub fn decode(
    message: &Message,
    mut input: &[u8],
    defaults: bool,
    hook: Option<BytesHook<'_>>,
) -> Option<Value> {
    let mut out = Map::new();
    let mut bytes_fields: BTreeMap<&'static str, &[u8]> = BTreeMap::new();
    while !input.is_empty() {
        let tag = read_varint(&mut input)?;
        let number = (tag >> 3) as u32;
        let wire = (tag & 7) as u32;
        let Some(field) = field_of(message, number) else {
            skip(&mut input, wire)?;
            continue;
        };
        if field.label == Label::Map {
            if wire != LENGTH {
                return None;
            }
            let entry = read_length(&mut input)?;
            let (key, value) = decode_entry(field, entry, defaults, hook)?;
            let map = out
                .entry(field.name.to_string())
                .or_insert_with(|| json!({}));
            if let Some(map) = map.as_object_mut() {
                map.insert(key, value);
            }
            continue;
        }
        match decode_value(field, wire, &mut input, defaults, hook)? {
            Decoded::Bytes(bytes) => {
                bytes_fields.insert(field.name, bytes);
            }
            Decoded::Value(value) if field.label == Label::Repeated => {
                let list = out
                    .entry(field.name.to_string())
                    .or_insert_with(|| json!([]));
                if let Some(list) = list.as_array_mut() {
                    list.push(value);
                }
            }
            Decoded::Value(value) => {
                out.insert(field.name.to_string(), value);
            }
        }
    }
    for (name, bytes) in &bytes_fields {
        put_bytes(&mut out, message, name, bytes, hook);
    }

    if defaults {
        for field in message.fields {
            let name = field.name;
            match field.label {
                Label::Repeated => {
                    out.entry(name.to_string()).or_insert_with(|| json!([]));
                }
                Label::Map => {
                    out.entry(name.to_string()).or_insert_with(|| json!({}));
                }
                Label::Singular => {
                    if field.kind == Kind::Bytes {
                        if !bytes_fields.contains_key(name) {
                            put_bytes(&mut out, message, name, &[], hook);
                        }
                    } else if field.kind != Kind::Message && !out.contains_key(name) {
                        out.insert(name.to_string(), default_of(field));
                    }
                }
                Label::Optional => {}
            }
        }
    }
    Some(Value::Object(out))
}

/// `value`, keyed by field name, on the wire. A bytes field takes a string of
/// its bytes or an array of numbers; fields `value` leaves out are left out.
pub fn encode(message: &Message, value: &Value) -> Vec<u8> {
    let mut out = Vec::new();
    let Some(entries) = value.as_object() else {
        return out;
    };
    for field in message.fields {
        let Some(item) = entries.get(field.name).filter(|item| !item.is_null()) else {
            continue;
        };
        match field.label {
            Label::Repeated => {
                for element in item.as_array().map_or(&[][..], Vec::as_slice) {
                    encode_value(&mut out, field.number, field, element);
                }
            }
            Label::Map => {
                let Some(map) = item.as_object() else {
                    continue;
                };
                for (key, element) in map {
                    let mut body = Vec::new();
                    put_length(&mut body, 1, key.as_bytes());
                    encode_value(&mut body, 2, field, element);
                    put_length(&mut out, field.number, &body);
                }
            }
            _ => encode_value(&mut out, field.number, field, item),
        }
    }
    out
}

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn base64(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    let letter = |n: u32| char::from(ALPHABET[(n & 63) as usize]);
    for chunk in bytes.chunks(3) {
        let n = (u32::from(chunk[0]) << 16)
            | (u32::from(chunk.get(1).copied().unwrap_or(0)) << 8)
            | u32::from(chunk.get(2).copied().unwrap_or(0));
        out.push(letter(n >> 18));
        out.push(letter(n >> 12));
        out.push(if chunk.len() > 1 { letter(n >> 6) } else { '=' });
        out.push(if chunk.len() > 2 { letter(n) } else { '=' });
    }
    out
}

/// Nothing when `text` is not base64.
pub fn unbase64(text: &str) -> Option<Vec<u8>> {
    let value = |byte: u8| -> Option<u32> {
        match byte {
            b'A'..=b'Z' => Some(u32::from(byte - b'A')),
            b'a'..=b'z' => Some(u32::from(byte - b'a') + 26),
            b'0'..=b'9' => Some(u32::from(byte - b'0') + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    };
    let mut out = Vec::with_capacity(text.len() / 4 * 3);
    let mut buffer = 0u32;
    let mut bits = 0;
    for byte in text.trim_end_matches('=').bytes() {
        buffer = (buffer << 6) | value(byte)?;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buffer >> bits) as u8);
            buffer &= (1 << bits) - 1;
        }
    }
    Some(out)
}

// The server's `GamendWeb.EventCodec` table, event by event: which message a
// binary `event` on a `kind` of topic carries, and whether to fill proto3's
// left-out zero fields, as the JS client does for these. `*` is any topic.
const MAPPINGS: &[(&str, &str, &str, bool)] = &[
    ("user", "updated", "User", false),
    ("user", "friend_updated", "FriendUpdate", false),
    ("*", "kv_updated", "KvEntry", false),
    ("*", "kv_deleted", "KvEntry", false),
    ("*", "notification_created", "Notification", true),
    ("*", "chat_message_created", "ChatMessage", true),
    ("*", "chat_message_updated", "ChatMessage", true),
    ("*", "chat_message_deleted", "EntityId", false),
    ("*", "group_invite_accepted", "GroupInviteEvent", true),
    ("*", "group_invite_cancelled", "GroupInviteEvent", true),
    ("*", "group_join_request_approved", "GroupInviteEvent", true),
    ("*", "group_join_request_rejected", "GroupInviteEvent", true),
    ("*", "party_invite_accepted", "PartyInviteEvent", true),
    ("*", "party_invite_declined", "PartyInviteEvent", true),
    ("*", "party_invite_cancelled", "PartyInviteEvent", true),
    ("*", "wallet_updated", "WalletChange", true),
    ("*", "inventory_updated", "InventoryChange", true),
    ("*", "chat_muted", "ChatMute", true),
    ("*", "chat_unmuted", "ChatUnmute", true),
    ("*", "quest_progress", "QuestProgress", true),
    ("*", "quest_completed", "QuestProgress", true),
    ("*", "quest_claimed", "QuestProgress", true),
    ("*", "ready_check_started", "ReadyCheckState", true),
    ("*", "ready_check_updated", "ReadyCheckState", true),
    ("*", "ready_check_passed", "ReadyCheckState", true),
    ("*", "ready_check_failed", "ReadyCheckState", true),
    ("lobby", "updated", "Lobby", false),
    ("lobby", "user_joined", "MemberEvent", false),
    ("lobby", "user_left", "MemberEvent", false),
    ("lobby", "user_kicked", "MemberEvent", false),
    ("lobby", "user_online", "MemberEvent", false),
    ("lobby", "user_offline", "MemberEvent", false),
    ("lobby", "host_changed", "HostChanged", true),
    ("lobby", "state_changed", "LobbyStateChanged", true),
    ("lobby", "user_updated", "UserBrief", false),
    ("group", "member_updated", "UserBrief", false),
    ("party", "member_updated", "UserBrief", false),
    ("lobbies", "lobby_created", "Lobby", false),
    ("lobbies", "lobby_updated", "Lobby", false),
    ("lobbies", "lobby_deleted", "EntityId", false),
    ("lobbies", "lobby_membership_changed", "EntityId", false),
    ("group", "updated", "Group", false),
    ("group", "member_joined", "MemberEvent", false),
    ("group", "member_left", "MemberEvent", false),
    ("group", "member_kicked", "MemberEvent", false),
    ("group", "member_promoted", "MemberEvent", false),
    ("group", "member_demoted", "MemberEvent", false),
    ("group", "join_request_approved", "MemberEvent", false),
    ("group", "join_request_rejected", "MemberEvent", false),
    ("group", "member_online", "MemberEvent", false),
    ("group", "member_offline", "MemberEvent", false),
    ("groups", "group_created", "Group", false),
    ("groups", "group_updated", "Group", false),
    ("groups", "group_deleted", "EntityId", false),
    ("party", "updated", "Party", false),
    ("party", "member_joined", "MemberEvent", false),
    ("party", "member_left", "MemberEvent", false),
    ("party", "member_online", "MemberEvent", false),
    ("party", "member_offline", "MemberEvent", false),
    ("party", "disbanded", "PartyRef", false),
    ("user", "tournament_updated", "TournamentEvent", false),
    ("user", "tournament_finished", "TournamentEvent", false),
    (
        "user",
        "tournament_match_ready",
        "TournamentMatchEvent",
        true,
    ),
    (
        "user",
        "tournament_match_resolved",
        "TournamentMatchEvent",
        true,
    ),
    ("user", "match_found", "MatchmakingFound", true),
];

/// The payload of a binary `event` on `topic`, or nothing when this SDK has no
/// decoder for it (or the bytes do not decode).
pub fn decode_binary_event(
    topic: &str,
    event: &str,
    bytes: &[u8],
    hook: Option<BytesHook<'_>>,
) -> Option<Value> {
    let kind = topic.split_once(':').map_or(topic, |(kind, _)| kind);
    // A topic-specific row wins over `*`, as in the server's clause order.
    let (_, _, name, defaults) = MAPPINGS
        .iter()
        .find(|(k, e, _, _)| *k == kind && *e == event)
        .or_else(|| {
            MAPPINGS
                .iter()
                .find(|(k, e, _, _)| *k == "*" && *e == event)
        })?;
    decode(find(name)?, bytes, *defaults, hook)
}
