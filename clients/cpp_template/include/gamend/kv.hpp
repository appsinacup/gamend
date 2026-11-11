// Live key-value rows: subscribe once, read any time, hear every change.
//
//     client.kv().subscribe({"progress", client.auth().session()->user_id});
//     client.kv().on_change([](const gamend::KvKey& key, const gamend::KvRow& row) {
//       if (key.key == "progress" && row.exists) show(row.data);
//     });
//     auto progress = client.kv().row({"progress", user_id});
//
// A subscription outlives the connection: every time the user channel
// (re)joins, each one is sent again and its reply refreshes the row. The
// cache also takes `fetch` results, so a game can paint what it knows
// before the socket is up.
#pragma once

#include <cstdint>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <tuple>
#include <utility>

#include "gamend/export.hpp"
#include "gamend/json.hpp"

namespace gamend {

namespace detail {
struct Core;
}

/// Which row: a key, global or scoped to a user or a lobby.
struct KvKey {
  KvKey() = default;
  KvKey(std::string key, std::string user_id = {}, std::string lobby_id = {})
      : key(std::move(key)), user_id(std::move(user_id)), lobby_id(std::move(lobby_id)) {}
  // Not an aggregate on purpose: `{"progress", user_id}` leaves the lobby out
  // without a missing-initializer warning in the game's build.
  KvKey(const char* key) : KvKey(std::string(key)) {}

  std::string key;
  std::string user_id;
  std::string lobby_id;

  bool operator<(const KvKey& other) const {
    return std::tie(key, user_id, lobby_id) < std::tie(other.key, other.user_id, other.lobby_id);
  }
  bool operator==(const KvKey& other) const {
    return key == other.key && user_id == other.user_id && lobby_id == other.lobby_id;
  }
};

/// A row as the cache knows it.
struct KvRow {
  /// False: the server said there is no such row (yet).
  bool exists = false;
  json data;
  json metadata;
};

struct KvResult {
  bool ok = false;
  KvRow row;
  /// Why not: the server's code (`forbidden`, `invalid_key`), or the transport's.
  std::string error;
};

using KvCallback = std::function<void(const KvResult&)>;
using KvListener = std::function<void(const KvKey& key, const KvRow& row)>;

class GAMEND_EXPORT Kv {
 public:
  explicit Kv(detail::Core& core);
  ~Kv();
  Kv(const Kv&) = delete;
  Kv& operator=(const Kv&) = delete;

  /// Subscribe to a row: `kv_updated` and `kv_deleted` keep it current from
  /// now on, over every reconnect, until `unsubscribe`. `done` gets the
  /// current row, or why the server refused (a refusal is not retried).
  void subscribe(KvKey key, KvCallback done = {});
  void unsubscribe(const KvKey& key);
  bool subscribed(const KvKey& key) const;

  /// The row as last seen, or nothing when this client never learned it.
  std::optional<KvRow> row(const KvKey& key) const;
  /// The row from the cache, or `GET /api/v1/kv/{key}` when it is not there
  /// (or `force`). A 404 caches "no such row"; a failure caches nothing.
  void fetch(KvKey key, bool force, KvCallback done);

  /// Every change to a cached row, from any source. Answers an id for `off`.
  std::uint64_t on_change(KvListener listener);
  void off(std::uint64_t listener);
  /// Forget every row and subscription. Signing out does it.
  void clear();

 private:
  friend class Realtime;
  friend class Auth;
  struct Subscription;

  void user_channel_joined();
  void send_subscribe(const KvKey& key);
  void store(const KvKey& key, KvRow row);
  void event(const std::string& kind, const json& payload);

  detail::Core& core_;
  std::map<KvKey, KvRow> rows_;
  std::map<KvKey, std::vector<KvCallback>> subscriptions_;
  std::map<KvKey, bool> confirmed_;
  std::uint64_t next_listener_ = 1;
  std::map<std::uint64_t, KvListener> listeners_;
};

}  // namespace gamend
