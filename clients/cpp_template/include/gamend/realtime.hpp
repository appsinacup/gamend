// The realtime connection: Phoenix channels over the WebSocket transport.
//
//     client.realtime().connect();          // joins user:<id> itself
//     client.realtime().on_event([](const gamend::Event& e) {
//       if (e.kind == gamend::events::LOBBY_UPDATED) refresh_lobby(e.payload);
//     });
//     client.realtime().join_lobby(lobby_id);
//     client.realtime().call_hook("arena", "start", gamend::json::array(),
//       [](const gamend::HookResult& r) { if (r.ok) use(r.data); });
//
// A dropped connection reconnects on its own, with a fresh token when the
// old one would not do, and rejoins every topic it had; `on_state` says when.
// Callbacks run in `Client::poll()`, like every other. The methods are safe
// to call from any thread.
#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "gamend/export.hpp"
#include "gamend/json.hpp"
#include "gamend/session.hpp"

namespace gamend {

namespace detail {
struct Core;
class Phoenix;
struct Frame;
}  // namespace detail

enum class RealtimeState {
  /// Not connected, and not trying: before `connect()`, after `disconnect()`
  /// or a sign-out.
  Disconnected,
  /// Opening the first connection.
  Connecting,
  /// Open; topics are (re)joining or joined.
  Connected,
  /// The connection dropped; the next attempt is scheduled or under way.
  Reconnecting,
};

/// A message the server pushed on a topic.
struct Event {
  std::string topic;
  /// The event as the server named it (`updated`, `user_joined`, ...).
  std::string event;
  /// What this SDK calls it: one of `gamend::events`, or `events::MESSAGE`
  /// for an event the table does not name.
  std::string kind;
  /// The payload. Null for a binary payload nothing decoded; see `bytes`.
  json payload;
  /// A binary payload this SDK could not decode, as it arrived.
  std::string bytes;
  /// It arrived as a protobuf frame (`RealtimeFormat::Protobuf`), decoded or not.
  bool binary = false;
};

/// The server's answer to a join, leave or push.
struct Reply {
  /// The server said "ok".
  bool ok = false;
  /// "ok" or "error" from the server; "timeout", "disconnected" or
  /// "not_joined" when no answer came.
  std::string status;
  /// What the server answered.
  json response;
  /// Empty when `ok`; otherwise `response.error` or `response.reason`, or
  /// the status.
  std::string error;
};

/// A server hook's answer.
struct HookResult {
  bool ok = false;
  /// What the hook returned.
  json data;
  /// A typed hook's reply bytes (`WebRtc::call_hook_raw`), undecoded.
  std::string bytes;
  /// Why it failed: the hook's error, `timeout`, `not_joined`, ...
  std::string error;
};

/// Reads a game's own protobuf bytes into a value (usually with the game's
/// protobuf library), or nothing when they do not decode.
using BytesDecoder = std::function<std::optional<json>(std::string_view bytes)>;

using ReplyCallback = std::function<void(const Reply&)>;
using EventCallback = std::function<void(const Event&)>;
using HookCallback = std::function<void(const HookResult&)>;
using StateCallback = std::function<void(RealtimeState)>;

class GAMEND_EXPORT Realtime {
 public:
  explicit Realtime(detail::Core& core);
  ~Realtime();
  Realtime(const Realtime&) = delete;
  Realtime& operator=(const Realtime&) = delete;

  /// Open the connection for the signed-in player and join `user:<id>`.
  /// Stays connected, reconnecting as needed, until `disconnect()` or a
  /// sign-out.
  void connect();
  /// Close the connection and forget every topic. No reconnect.
  void disconnect();
  RealtimeState state() const { return state_.load(); }

  /// Join `topic`, now or as soon as the connection is open, and again
  /// after every reconnect until `leave`. `done` gets the first join's reply.
  void join(std::string topic, json params = json::object(), ReplyCallback done = {});
  void leave(std::string topic, ReplyCallback done = {});
  bool joined(const std::string& topic) const;

  void join_lobby(const std::string& lobby_id, ReplyCallback done = {});
  void join_lobbies(ReplyCallback done = {});
  void join_group(const std::string& group_id, ReplyCallback done = {});
  void join_groups(ReplyCallback done = {});
  void join_party(const std::string& party_id, ReplyCallback done = {});

  /// Send `event` to a joined topic; `done` gets the server's reply, or
  /// `timeout` after `Config::push_timeout`.
  void push(std::string topic, std::string event, json payload = json::object(),
            ReplyCallback done = {});
  /// Call a server hook over the user channel.
  void call_hook(std::string plugin, std::string fn, json args, HookCallback done);

  /// Every server event, on every topic. Answers an id for `off`.
  std::uint64_t on_event(EventCallback listener);
  /// Every change of `state()`.
  std::uint64_t on_state(StateCallback listener);
  void off(std::uint64_t listener);

  /// `user:<id>` of the signed-in player, or empty.
  std::string user_topic() const;

  /// With `RealtimeFormat::Protobuf`, the server sends metadata that fits the
  /// game plugin's registered schema (`UserMeta`, `LobbyMeta`, ...) as bytes,
  /// `metadata_pb`. This reads an entity's (`user`, `lobby`, `group`,
  /// `party`) into `metadata`; unread, it stays base64 as `metadata_pb`.
  void register_metadata_decoder(std::string entity, BytesDecoder decoder);
  /// The same for KV data sent as `data_pb` (the plugin's `kv_schemas/0`):
  /// an exact key, or a `prefix*` pattern. An exact key wins over a
  /// pattern, a longer pattern over a shorter one.
  void register_kv_decoder(std::string pattern, BytesDecoder decoder);

 private:
  friend class Auth;
  struct Topic;
  struct Pending;

  // Everything below runs inside the loop's exclusive section.
  void session_changed(const std::optional<Session>& session);
  void open();
  void opened(std::uint64_t generation);
  void received(std::uint64_t generation, const std::string& text);
  void received_binary(std::uint64_t generation, const std::string& bytes);
  void dropped(std::uint64_t generation, const std::string& why);
  void frame(detail::Frame frame);
  void emit(const Event& event);
  void send_join(Topic& topic);
  void schedule_heartbeat();
  void schedule_reconnect();
  void schedule_rejoin(const std::string& topic);
  void fail_pending(const std::string& status);
  void track(const std::string& ref, std::string topic, bool join, ReplyCallback done);
  void set_state(RealtimeState state);
  void close_socket();
  Topic* find(const std::string& topic);
  std::string url() const;

  detail::Core& core_;
  std::unique_ptr<detail::Phoenix> phoenix_;
  std::atomic<RealtimeState> state_{RealtimeState::Disconnected};
  bool wanted_ = false;       // connect() was called and not undone
  bool ever_opened_ = false;  // the current attempt series has opened once
  bool last_opened_ = false;  // the last connection opened before it dropped
  std::uint64_t generation_ = 0;
  std::size_t attempt_ = 0;
  std::uint64_t heartbeat_timer_ = 0;
  std::uint64_t reconnect_timer_ = 0;
  std::string user_id_;
  std::vector<Topic> topics_;
  std::map<std::string, Pending> pending_;
  std::uint64_t next_listener_ = 1;
  std::map<std::uint64_t, EventCallback> event_listeners_;
  std::map<std::uint64_t, StateCallback> state_listeners_;
  std::map<std::string, BytesDecoder> metadata_decoders_;
  std::map<std::string, BytesDecoder> kv_decoders_;
};

}  // namespace gamend
