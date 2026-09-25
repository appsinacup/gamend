// A signed-in identity: the token pair and who it belongs to.
#pragma once

#include <cstdint>
#include <optional>
#include <string>

#include "gamend/json.hpp"

namespace gamend {

struct Session {
  std::string access_token;
  std::string refresh_token;
  std::string user_id;
  std::string username;      // empty when the sign-in did not say (OAuth)
  std::string display_name;
  /// The access token's lifetime in seconds, as the server said (900 by default).
  std::int64_t expires_in = 0;
  /// When the access token lapses, in Unix seconds; 0 when unknown.
  std::int64_t expires_at = 0;

  /// For keeping it where the platform keeps secrets, and `from_json` back.
  json to_json() const;
  /// A session from `to_json`'s output or a sign-in reply's `data`; empty
  /// when there is no `access_token`. `now` (Unix seconds) turns a reply's
  /// `expires_in` into `expires_at` when the value carries no `expires_at`.
  static std::optional<Session> from_json(const json& value, std::int64_t now = 0);
};

}  // namespace gamend
