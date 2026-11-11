// Who is around: merged user profiles, lobbies and online state, kept up by
// the realtime events as they arrive. A game reads instead of bookkeeping.
//
//     client.presence().on_user_changed([&](const std::string& id) {
//       redraw_name_tag(id, client.presence().user(id));
//     });
//     bool here = client.presence().online(friend_id);
//
// Updates arrive as partial patches, metadata as sparse sections; they are
// merged, so a profile only grows more complete. The signed-in player's own
// `user:<id>` push carries the whole metadata map and replaces it, which is
// how a key the server deleted disappears.
#pragma once

#include <cstdint>
#include <functional>
#include <map>
#include <string>

#include "gamend/export.hpp"
#include "gamend/json.hpp"

namespace gamend {

namespace detail {
struct Core;
}

class GAMEND_EXPORT Presence {
 public:
  explicit Presence(detail::Core& core);
  ~Presence();
  Presence(const Presence&) = delete;
  Presence& operator=(const Presence&) = delete;

  /// The merged profile, or an empty object.
  json user(const std::string& user_id) const;
  /// The lobby as last pushed, or an empty object.
  json lobby(const std::string& lobby_id) const;
  /// Online as far as this client knows; the signed-in player always is.
  bool online(const std::string& user_id) const;
  /// When an offline player was last seen, in Unix seconds; 0 when unknown.
  std::int64_t last_seen(const std::string& user_id) const;

  /// Record presence learned elsewhere (a friend list, a search result).
  void set_online(const std::string& user_id, bool online, std::int64_t last_seen = 0);
  /// Merge user data learned elsewhere (a REST answer, a member list).
  void cache_user(const std::string& user_id, const json& data);
  /// Forget everything. Signing out does it.
  void clear();

  std::uint64_t on_user_changed(std::function<void(const std::string& user_id)> listener);
  std::uint64_t on_lobby_changed(std::function<void(const json& lobby)> listener);
  void off(std::uint64_t listener);

  /// Metadata merged one section deep: `{"player": {"hat": "x"}}` sets the
  /// hat without wiping the rest of `player`.
  static json merge_metadata(const json& existing, const json& patch);

 private:
  friend class Auth;
  void event(const std::string& kind, const json& payload);
  void apply_user_update(const json& user);
  void merge_into(const std::string& user_id, const json& patch, bool metadata_is_whole);
  void user_changed(const std::string& user_id);
  void lobby_changed(const json& lobby);

  detail::Core& core_;
  std::map<std::string, json> users_;
  std::map<std::string, json> lobbies_;
  std::map<std::string, bool> online_;
  std::map<std::string, std::int64_t> last_seen_;
  std::uint64_t next_listener_ = 1;
  std::map<std::uint64_t, std::function<void(const std::string&)>> user_listeners_;
  std::map<std::uint64_t, std::function<void(const json&)>> lobby_listeners_;
};

}  // namespace gamend
