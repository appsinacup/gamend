// Signing in, and staying signed in.
//
// Gamend issues a short-lived access token (`expires_in`, 15 minutes by
// default) and a refresh token (30 days by default). `Auth` keeps both, refreshes the access token when
// three quarters of its life have passed, and `Rest` refreshes once more on
// a 401. The game keeps the session between runs where its platform keeps
// secrets: `on_session_changed` hands it over, `restore` takes it back.
#pragma once

#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

#include "gamend/response.hpp"
#include "gamend/rest.hpp"
#include "gamend/session.hpp"

namespace gamend {

namespace detail {
struct Core;
}

struct AuthResult {
  bool ok = false;
  /// Why it failed: the server's code (`invalid_credentials`, ...) or what
  /// went wrong before it answered. Empty on success.
  std::string error;
  /// The session signed in with; empty unless `ok`.
  Session session;
  /// The last reply behind the result, for its `message()` or `errors()`.
  Response response;
};

using AuthCallback = std::function<void(const AuthResult&)>;
using SessionListener = std::function<void(const std::optional<Session>& session)>;

class Auth {
 public:
  explicit Auth(detail::Core& core);
  ~Auth();
  Auth(const Auth&) = delete;
  Auth& operator=(const Auth&) = delete;

  /// Any string; an unknown id makes an anonymous account when the server
  /// has device sign-in enabled (its default).
  void login_device(std::string device_id, AuthCallback done = {});
  void login_email(std::string email, std::string password, AuthCallback done = {});
  /// A new account with an email and a password, signed in as it is made.
  /// The server picks a username when `username` is empty.
  void register_email(std::string email, std::string password, std::string username = {},
                      AuthCallback done = {});
  /// A Steam session ticket (`ISteamUser::GetAuthTicketForWebApi`, hex).
  void login_steam(std::string ticket, AuthCallback done = {});
  /// Sign in through a provider (`google`, `discord`, `apple`, ...): opens
  /// its page with `Config::open_url`, then asks the server every
  /// `sign_in_poll` whether the player finished, until `sign_in_timeout`.
  /// Always a sign-in, even for a player signed in already.
  void sign_in(std::string provider, AuthCallback done = {});
  /// Link a provider to the signed-in account through its page, as
  /// `sign_in` signs in through it. `done` gets the final link status: ok
  /// once linked, else its code (`provider_already_linked`, ...). The session
  /// does not change.
  void link(std::string provider, Callback done = {});
  /// Link Steam to the signed-in account with a session ticket. `done` gets
  /// the current user, whose `linked_providers` now has `steam`.
  void link_steam(std::string ticket, Callback done = {});
  /// Stop waiting for a provider; its callback gets `cancelled`.
  void cancel_sign_in();

  /// Trade the refresh token for a fresh access token now. Automatic; call
  /// it only to check a restored session is still good.
  void refresh(AuthCallback done = {});
  /// Revoke the session on the server, then forget it here, whatever the
  /// server answered.
  void logout(AuthCallback done = {});
  /// Forget the session here only.
  void forget();
  /// Adopt a session a previous run kept. A token that lapsed, or lapses
  /// within a minute, is refreshed on the next `poll()`.
  void restore(Session session);

  std::optional<Session> session() const;
  bool signed_in() const;
  /// Called, in `poll()`, whenever the session is set, refreshed or
  /// dropped, so the game can keep it. Not called for `restore`.
  void on_session_changed(SessionListener listener);

 private:
  friend class Rest;
  friend class Realtime;
  struct State;

  std::string bearer() const;
  /// Refresh (joining one in flight), then `next(true)`; `next(false)`
  /// when there is no refresh token or the refresh failed.
  void refresh_then(std::function<void(bool refreshed)> next);
  void sign_in_with(std::string path, Body body, AuthCallback done);
  void adopt(Session session, bool notify);
  void clear();
  void schedule_refresh();
  /// Open the page `start_path` answers, then poll `status_path` + its
  /// session id until the player is done there. `finish` gets the completed
  /// status reply, or a reply whose `error` says why not. One page at a time:
  /// a second cancels the first.
  void provider_page(std::string start_method, std::string start_path, std::string status_path,
                     bool authenticated, Callback finish);
  void poll_page(std::uint64_t attempt, std::string status_path, bool authenticated,
                 std::chrono::milliseconds deadline);
  void end_page(std::uint64_t attempt, Response response);
  void send(bool authenticated, std::string_view method, std::string path, Callback done);

  detail::Core& core_;
  std::unique_ptr<State> state_;
};

}  // namespace gamend
