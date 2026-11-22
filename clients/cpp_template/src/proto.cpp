#include "proto.hpp"

#include <map>
#include <utility>
#include <vector>

namespace gamend::detail {
namespace proto {
namespace {

constexpr std::uint32_t kVarint = 0;
constexpr std::uint32_t kFixed64 = 1;
constexpr std::uint32_t kLength = 2;
constexpr std::uint32_t kFixed32 = 5;

bool read_varint(std::string_view& in, std::uint64_t& out) {
  out = 0;
  for (int shift = 0; shift < 64; shift += 7) {
    if (in.empty()) return false;
    auto byte = static_cast<unsigned char>(in.front());
    in.remove_prefix(1);
    out |= static_cast<std::uint64_t>(byte & 0x7F) << shift;
    if ((byte & 0x80) == 0) return true;
  }
  return false;
}

bool read_length(std::string_view& in, std::string_view& out) {
  std::uint64_t size = 0;
  if (!read_varint(in, size) || size > in.size()) return false;
  out = in.substr(0, static_cast<std::size_t>(size));
  in.remove_prefix(static_cast<std::size_t>(size));
  return true;
}

bool skip(std::string_view& in, std::uint32_t wire) {
  std::uint64_t ignored = 0;
  std::string_view span;
  switch (wire) {
    case kVarint:
      return read_varint(in, ignored);
    case kFixed64:
      if (in.size() < 8) return false;
      in.remove_prefix(8);
      return true;
    case kLength:
      return read_length(in, span);
    case kFixed32:
      if (in.size() < 4) return false;
      in.remove_prefix(4);
      return true;
    default:
      return false;
  }
}

const Field* field_of(const Message& message, std::uint32_t number) {
  for (std::size_t i = 0; i < message.count; ++i) {
    if (message.fields[i].number == number) return &message.fields[i];
  }
  return nullptr;
}

json scalar(Type type, std::uint64_t raw) {
  switch (type) {
    case Type::Bool:
      return raw != 0;
    case Type::Int32:
      return static_cast<std::int32_t>(raw);
    case Type::Int64:
      return static_cast<std::int64_t>(raw);
    case Type::Uint32:
      return static_cast<std::uint32_t>(raw);
    case Type::Uint64:
      return raw;
    case Type::Sint32:
    case Type::Sint64:
      return static_cast<std::int64_t>((raw >> 1) ^ (~(raw & 1) + 1));
    default:
      return nullptr;
  }
}

bool ends_with(std::string_view text, std::string_view tail) {
  return text.size() >= tail.size() && text.substr(text.size() - tail.size()) == tail;
}

// A bytes field as the JSON payload has it: `metadata_json` becomes the
// parsed `metadata` (an empty or unreadable one an empty object); anything
// else goes to the hook, and stays base64 under its own name when nothing
// reads it.
void put_bytes(json& out, const Message& message, std::string_view name, std::string_view bytes,
               const BytesHook* hook) {
  if (ends_with(name, "_json")) {
    auto base = std::string(name.substr(0, name.size() - 5));
    auto parsed = bytes.empty() ? json::object() : parse(bytes);
    out[base] = parsed.is_discarded() ? json::object() : std::move(parsed);
    return;
  }
  if (bytes.empty()) return;
  if (hook != nullptr && *hook) {
    if (auto read = (*hook)(message.name, name, bytes, out)) {
      auto base = ends_with(name, "_pb") ? name.substr(0, name.size() - 3) : name;
      out[std::string(base)] = std::move(*read);
      return;
    }
  }
  out[std::string(name)] = base64(bytes);
}

json default_of(const Field& field) {
  switch (field.type) {
    case Type::Bool:
      return false;
    case Type::String:
      return "";
    case Type::Message:
      return nullptr;
    case Type::Bytes:
      return nullptr;
    default:
      return 0;
  }
}

bool decode_value(const Field& field, std::uint32_t wire, std::string_view& in, bool defaults,
                  const BytesHook* hook, json& value, std::string_view& bytes) {
  if (field.type == Type::String || field.type == Type::Bytes || field.type == Type::Message) {
    if (wire != kLength) return false;
    std::string_view span;
    if (!read_length(in, span)) return false;
    if (field.type == Type::String) {
      value = std::string(span);
    } else if (field.type == Type::Bytes) {
      bytes = span;
    } else {
      auto nested = decode(kMessages[field.message], span, defaults, hook);
      if (!nested) return false;
      value = std::move(*nested);
    }
    return true;
  }
  if (wire != kVarint) return false;
  std::uint64_t raw = 0;
  if (!read_varint(in, raw)) return false;
  value = scalar(field.type, raw);
  return true;
}

// One `map<string, V>` entry: a message whose field 1 is the key, 2 the value.
bool decode_entry(const Field& field, std::string_view entry, bool defaults, const BytesHook* hook,
                  std::string& key, json& value) {
  value = default_of(field);
  if (field.type == Type::String) value = "";
  while (!entry.empty()) {
    std::uint64_t tag = 0;
    if (!read_varint(entry, tag)) return false;
    auto number = static_cast<std::uint32_t>(tag >> 3);
    auto wire = static_cast<std::uint32_t>(tag & 7);
    if (number == 1 && wire == kLength) {
      std::string_view span;
      if (!read_length(entry, span)) return false;
      key.assign(span);
    } else if (number == 2) {
      std::string_view bytes;
      if (!decode_value(field, wire, entry, defaults, hook, value, bytes)) return false;
    } else if (!skip(entry, wire)) {
      return false;
    }
  }
  return true;
}

void put_varint(std::string& out, std::uint64_t value) {
  while (value >= 0x80) {
    out += static_cast<char>((value & 0x7F) | 0x80);
    value >>= 7;
  }
  out += static_cast<char>(value);
}

void put_tag(std::string& out, std::uint32_t number, std::uint32_t wire) {
  put_varint(out, (static_cast<std::uint64_t>(number) << 3) | wire);
}

void put_length(std::string& out, std::uint32_t number, std::string_view bytes) {
  put_tag(out, number, kLength);
  put_varint(out, bytes.size());
  out.append(bytes);
}

void encode_value(std::string& out, const Field& field, const json& value) {
  switch (field.type) {
    case Type::String:
    case Type::Bytes:
      if (value.is_string()) put_length(out, field.number, value.get<std::string>());
      return;
    case Type::Message:
      put_length(out, field.number, encode(kMessages[field.message], value));
      return;
    case Type::Bool:
      put_tag(out, field.number, kVarint);
      put_varint(out, value.is_boolean() && value.get<bool>() ? 1 : 0);
      return;
    case Type::Sint32:
    case Type::Sint64: {
      auto n = value.is_number() ? value.get<std::int64_t>() : 0;
      put_tag(out, field.number, kVarint);
      put_varint(out, (static_cast<std::uint64_t>(n) << 1) ^ static_cast<std::uint64_t>(n >> 63));
      return;
    }
    default: {
      auto n = value.is_number() ? value.get<std::int64_t>() : 0;
      put_tag(out, field.number, kVarint);
      put_varint(out, static_cast<std::uint64_t>(n));
      return;
    }
  }
}

}  // namespace

const Message* find(std::string_view name) {
  for (std::size_t i = 0; i < kMessageCount; ++i) {
    if (kMessages[i].name == name) return &kMessages[i];
  }
  return nullptr;
}

std::optional<json> decode(const Message& message, std::string_view in, bool defaults,
                           const BytesHook* hook) {
  json out = json::object();
  std::map<std::string_view, std::string_view> bytes_fields;
  while (!in.empty()) {
    std::uint64_t tag = 0;
    if (!read_varint(in, tag)) return std::nullopt;
    auto number = static_cast<std::uint32_t>(tag >> 3);
    auto wire = static_cast<std::uint32_t>(tag & 7);
    const Field* field = field_of(message, number);
    if (field == nullptr) {
      if (!skip(in, wire)) return std::nullopt;
      continue;
    }
    auto name = std::string(field->name);
    if (field->label == Label::Map) {
      std::string_view entry;
      if (wire != kLength || !read_length(in, entry)) return std::nullopt;
      std::string key;
      json value;
      if (!decode_entry(*field, entry, defaults, hook, key, value)) return std::nullopt;
      auto& map = out[name];
      if (!map.is_object()) map = json::object();
      map[key] = std::move(value);
      continue;
    }
    json value;
    std::string_view bytes;
    if (!decode_value(*field, wire, in, defaults, hook, value, bytes)) return std::nullopt;
    if (field->type == Type::Bytes) {
      bytes_fields[field->name] = bytes;
    } else if (field->label == Label::Repeated) {
      auto& list = out[name];
      if (!list.is_array()) list = json::array();
      list.push_back(std::move(value));
    } else {
      out[name] = std::move(value);
    }
  }
  for (const auto& [name, bytes] : bytes_fields) put_bytes(out, message, name, bytes, hook);

  if (defaults) {
    for (std::size_t i = 0; i < message.count; ++i) {
      const Field& field = message.fields[i];
      auto name = std::string(field.name);
      if (field.label == Label::Repeated) {
        if (!out.contains(name)) out[name] = json::array();
      } else if (field.label == Label::Map) {
        if (!out.contains(name)) out[name] = json::object();
      } else if (field.label == Label::Singular) {
        if (field.type == Type::Bytes) {
          if (bytes_fields.count(field.name) == 0) put_bytes(out, message, field.name, {}, hook);
        } else if (!out.contains(name) && field.type != Type::Message) {
          out[name] = default_of(field);
        }
      }
    }
  }
  return out;
}

std::string encode(const Message& message, const json& value) {
  std::string out;
  if (!value.is_object()) return out;
  for (std::size_t i = 0; i < message.count; ++i) {
    const Field& field = message.fields[i];
    auto it = value.find(field.name);
    if (it == value.end() || it->is_null()) continue;
    if (field.label == Label::Repeated) {
      if (!it->is_array()) continue;
      for (const auto& item : *it) encode_value(out, field, item);
    } else if (field.label == Label::Map) {
      if (!it->is_object()) continue;
      for (auto entry = it->begin(); entry != it->end(); ++entry) {
        std::string body;
        put_length(body, 1, entry.key());
        Field value_field = field;
        value_field.number = 2;
        encode_value(body, value_field, *entry);
        put_length(out, field.number, body);
      }
    } else {
      encode_value(out, field, *it);
    }
  }
  return out;
}

std::string base64(std::string_view bytes) {
  static constexpr char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out;
  out.reserve((bytes.size() + 2) / 3 * 4);
  std::size_t i = 0;
  for (; i + 2 < bytes.size(); i += 3) {
    auto n = (static_cast<unsigned char>(bytes[i]) << 16) |
             (static_cast<unsigned char>(bytes[i + 1]) << 8) |
             static_cast<unsigned char>(bytes[i + 2]);
    out += alphabet[(n >> 18) & 63];
    out += alphabet[(n >> 12) & 63];
    out += alphabet[(n >> 6) & 63];
    out += alphabet[n & 63];
  }
  if (i + 1 == bytes.size()) {
    auto n = static_cast<unsigned char>(bytes[i]) << 16;
    out += alphabet[(n >> 18) & 63];
    out += alphabet[(n >> 12) & 63];
    out += "==";
  } else if (i + 2 == bytes.size()) {
    auto n = (static_cast<unsigned char>(bytes[i]) << 16) |
             (static_cast<unsigned char>(bytes[i + 1]) << 8);
    out += alphabet[(n >> 18) & 63];
    out += alphabet[(n >> 12) & 63];
    out += alphabet[(n >> 6) & 63];
    out += '=';
  }
  return out;
}

std::optional<std::string> unbase64(std::string_view text) {
  auto value = [](char c) -> int {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
  };
  while (!text.empty() && text.back() == '=') text.remove_suffix(1);
  std::string out;
  std::uint32_t buffer = 0;
  int bits = 0;
  for (char c : text) {
    int v = value(c);
    if (v < 0) return std::nullopt;
    buffer = (buffer << 6) | static_cast<std::uint32_t>(v);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out += static_cast<char>((buffer >> bits) & 0xFF);
    }
  }
  return out;
}

}  // namespace proto

namespace {

struct Mapping {
  std::string_view message;
  /// Fill proto3's left-out zero fields, as the JS client does for these.
  bool defaults;
};

// The server's `GamendWeb.EventCodec` table, event by event: which message a
// binary `event` on a `kind` of topic carries. `*` is any topic.
std::optional<Mapping> mapping_of(std::string_view kind, std::string_view event) {
  struct Row {
    std::string_view kind;
    std::string_view event;
    Mapping mapping;
  };
  static constexpr Row rows[] = {
      {"user", "updated", {"User", false}},
      {"user", "friend_updated", {"FriendUpdate", false}},
      {"*", "kv_updated", {"KvEntry", false}},
      {"*", "kv_deleted", {"KvEntry", false}},
      {"*", "notification_created", {"Notification", true}},
      {"*", "chat_message_created", {"ChatMessage", true}},
      {"*", "chat_message_updated", {"ChatMessage", true}},
      {"*", "chat_message_deleted", {"EntityId", false}},
      {"*", "group_invite_accepted", {"GroupInviteEvent", true}},
      {"*", "group_invite_cancelled", {"GroupInviteEvent", true}},
      {"*", "group_join_request_approved", {"GroupInviteEvent", true}},
      {"*", "group_join_request_rejected", {"GroupInviteEvent", true}},
      {"*", "party_invite_accepted", {"PartyInviteEvent", true}},
      {"*", "party_invite_declined", {"PartyInviteEvent", true}},
      {"*", "party_invite_cancelled", {"PartyInviteEvent", true}},
      {"*", "wallet_updated", {"WalletChange", true}},
      {"*", "inventory_updated", {"InventoryChange", true}},
      {"*", "chat_muted", {"ChatMute", true}},
      {"*", "chat_unmuted", {"ChatUnmute", true}},
      {"*", "quest_progress", {"QuestProgress", true}},
      {"*", "quest_completed", {"QuestProgress", true}},
      {"*", "quest_claimed", {"QuestProgress", true}},
      {"*", "ready_check_started", {"ReadyCheckState", true}},
      {"*", "ready_check_updated", {"ReadyCheckState", true}},
      {"*", "ready_check_passed", {"ReadyCheckState", true}},
      {"*", "ready_check_failed", {"ReadyCheckState", true}},
      {"lobby", "updated", {"Lobby", false}},
      {"lobby", "user_joined", {"MemberEvent", false}},
      {"lobby", "user_left", {"MemberEvent", false}},
      {"lobby", "user_kicked", {"MemberEvent", false}},
      {"lobby", "user_online", {"MemberEvent", false}},
      {"lobby", "user_offline", {"MemberEvent", false}},
      {"lobby", "host_changed", {"HostChanged", true}},
      {"lobby", "state_changed", {"LobbyStateChanged", true}},
      {"lobby", "user_updated", {"UserBrief", false}},
      {"group", "member_updated", {"UserBrief", false}},
      {"party", "member_updated", {"UserBrief", false}},
      {"lobbies", "lobby_created", {"Lobby", false}},
      {"lobbies", "lobby_updated", {"Lobby", false}},
      {"lobbies", "lobby_deleted", {"EntityId", false}},
      {"lobbies", "lobby_membership_changed", {"EntityId", false}},
      {"group", "updated", {"Group", false}},
      {"group", "member_joined", {"MemberEvent", false}},
      {"group", "member_left", {"MemberEvent", false}},
      {"group", "member_kicked", {"MemberEvent", false}},
      {"group", "member_promoted", {"MemberEvent", false}},
      {"group", "member_demoted", {"MemberEvent", false}},
      {"group", "join_request_approved", {"MemberEvent", false}},
      {"group", "join_request_rejected", {"MemberEvent", false}},
      {"group", "member_online", {"MemberEvent", false}},
      {"group", "member_offline", {"MemberEvent", false}},
      {"groups", "group_created", {"Group", false}},
      {"groups", "group_updated", {"Group", false}},
      {"groups", "group_deleted", {"EntityId", false}},
      {"party", "updated", {"Party", false}},
      {"party", "member_joined", {"MemberEvent", false}},
      {"party", "member_left", {"MemberEvent", false}},
      {"party", "member_online", {"MemberEvent", false}},
      {"party", "member_offline", {"MemberEvent", false}},
      {"party", "disbanded", {"PartyRef", false}},
      {"user", "tournament_updated", {"TournamentEvent", false}},
      {"user", "tournament_finished", {"TournamentEvent", false}},
      {"user", "tournament_match_ready", {"TournamentMatchEvent", true}},
      {"user", "tournament_match_resolved", {"TournamentMatchEvent", true}},
      {"user", "match_found", {"MatchmakingFound", true}},
      {"user", "ticket_queued", {"MatchmakingTicketQueued", true}},
      {"user", "ticket_cancelled", {"MatchmakingTicketCancelled", true}},
      {"*", "result_started", {"PlayResult", true}},
      {"*", "result_ended", {"PlayResult", true}},
      {"*", "result_event", {"PlayResultEventPushed", true}},
      {"user", "account_banned", {"AccountBan", true}},
      {"user", "account_unbanned", {"Empty", false}},
      {"user", "outgoing_request", {"Friendship", true}},
      {"user", "incoming_request", {"Friendship", true}},
      {"user", "request_cancelled", {"Friendship", true}},
      {"user", "friend_accepted", {"Friendship", true}},
      {"user", "friend_rejected", {"Friendship", true}},
      {"user", "friend_removed", {"Friendship", true}},
      {"user", "friend_blocked", {"Friendship", true}},
      {"user", "friend_unblocked", {"Friendship", true}},
      {"user", "webrtc:answer", {"WebrtcAnswer", true}},
      {"user", "webrtc:ice", {"WebrtcIce", false}},
      {"user", "webrtc:channel_open", {"WebrtcChannelOpen", true}},
      {"user", "webrtc:channel_closed", {"Empty", false}},
      {"user", "webrtc:state", {"WebrtcState", true}},
      {"signaling", "user_joined", {"SignalingPeer", true}},
      {"signaling", "user_rejoined", {"SignalingPeer", true}},
      {"signaling", "user_left", {"SignalingPeerLeft", true}},
      {"signaling", "offer", {"SignalingSdp", true}},
      {"signaling", "answer", {"SignalingSdp", true}},
      {"signaling", "ice", {"SignalingIce", true}},
      {"signaling", "room_closed", {"SignalingRoomClosed", true}},
  };
  // A topic-specific row wins over `*`, as in the server's clause order.
  for (const auto& row : rows) {
    if (row.kind == kind && row.event == event) return row.mapping;
  }
  for (const auto& row : rows) {
    if (row.kind == "*" && row.event == event) return row.mapping;
  }
  return std::nullopt;
}

}  // namespace

std::optional<json> decode_binary_event(const std::string& topic, const std::string& event,
                                        const std::string& bytes, const proto::BytesHook* hook) {
  auto colon = topic.find(':');
  auto kind = std::string_view(topic).substr(0, colon);
  auto mapping = mapping_of(kind, event);
  if (!mapping) return std::nullopt;
  const auto* message = proto::find(mapping->message);
  if (message == nullptr) return std::nullopt;
  return proto::decode(*message, bytes, mapping->defaults, hook);
}

}  // namespace gamend::detail
