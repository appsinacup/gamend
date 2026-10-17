#include "gamend/auth.hpp"

#include <mutex>
#include <utility>
#include <vector>

#include "core.hpp"
#include "query.hpp"

namespace gamend {

struct Auth::State {
  mutable std::mutex mutex;
  std::optional<Session> session;
  SessionListener listener;

  bool refreshing = false;
  std::vector<std::function<void(bool)>> waiters;
  std::uint64_t refresh_timer = 0;

  /// Bumped by every provider page (a sign-in or a link) and by its end, so
  /// a reply or a timer from one that is over finds a different number and
  /// does nothing.
  std::uint64_t page_attempt = 0;
  std::uint64_t page_timer = 0;
  bool on_page = false;
  Callback page_finish;
};

namespace {

// Refresh when three quarters of the token's life have passed, and at once
// when less than this is left.
constexpr std::int64_t kRefreshMargin = 60;
// How long to wait before trying again when the refresh could not reach the
// server; the session stays until the server says it is no good.
constexpr std::chrono::seconds kRefreshRetry{30};

AuthResult failed(const Response& response, std::string error = {}) {
  AuthResult result;
  result.response = response;
  result.error = !error.empty() ? std::move(error)
                 : !response.error.empty() ? response.error
                                           : "unexpected_reply";
  return result;
}

}  // namespace

Auth::Auth(detail::Core& core) : core_(core), state_(std::make_unique<State>()) {}
Auth::~Auth() = default;

void Auth::login_device(std::string device_id, AuthCallback done) {
  sign_in_with("/api/v1/login/device", Body::of({{"device_id", std::move(device_id)}}),
               std::move(done));
}

void Auth::login_email(std::string email, std::string password, AuthCallback done) {
  sign_in_with("/api/v1/login",
               Body::of({{"email", std::move(email)}, {"password", std::move(password)}}),
               std::move(done));
}

void Auth::register_email(std::string email, Callback done) {
  register_email(std::move(email), {}, std::move(done));
}

// Not `sign_in_with`: registering answers the account, never tokens. Two
// overloads rather than a defaulted username: the old `(email, password)`
// call would otherwise compile and send the password as the username.
void Auth::register_email(std::string email, std::string username, Callback done) {
  json params = {{"email", std::move(email)}};
  if (!username.empty()) params["username"] = std::move(username);
  core_.rest.send_anonymous("POST", "/api/v1/register", Body::of(std::move(params)),
                            std::move(done));
}

void Auth::confirm_registration(std::string email, std::string code, std::string password,
                                AuthCallback done) {
  sign_in_with("/api/v1/register/confirm",
               Body::of({{"email", std::move(email)},
                         {"code", std::move(code)},
                         {"password", std::move(password)}}),
               std::move(done));
}

void Auth::resend_confirmation(std::string email, Callback done) {
  core_.rest.send_anonymous("POST", "/api/v1/register/resend",
                            Body::of({{"email", std::move(email)}}), std::move(done));
}

void Auth::login_steam(std::string ticket, AuthCallback done) {
  sign_in_with("/api/v1/auth/steam/callback", Body::of({{"code", std::move(ticket)}}),
               std::move(done));
}

void Auth::sign_in_with(std::string path, Body body, AuthCallback done) {
  core_.rest.send_anonymous(
      "POST", std::move(path), std::move(body), [this, done = std::move(done)](const Response& r) {
        AuthResult result;
        if (!r.ok()) {
          result = failed(r);
        } else if (auto session = Session::from_json(r.data(), core_.unix_now())) {
          adopt(*session, true);
          result.ok = true;
          result.session = std::move(*session);
          result.response = r;
        } else {
          // A sign-in that answered no token: a link, for one.
          result = failed(r, "no_session");
        }
        if (done) done(result);
      });
}

void Auth::sign_in(std::string provider, AuthCallback done) {
  auto path = "/api/v1/auth/" + detail::escape(provider);
  provider_page("GET", path, "/api/v1/auth/session/", false,
                [this, done = std::move(done)](const Response& r) {
                  AuthResult result;
                  if (!r.error.empty()) {
                    result = failed(r);
                  } else if (auto session = Session::from_json(field(r.data(), "session"),
                                                               core_.unix_now())) {
                    adopt(*session, true);
                    result.ok = true;
                    result.session = std::move(*session);
                    result.response = r;
                  } else {
                    // Completed, but the tokens were already collected.
                    result = failed(r, "no_session");
                  }
                  if (done) done(result);
                });
}

void Auth::link(std::string provider, Callback done) {
  auto path = "/api/v1/me/providers/" + detail::escape(provider) + "/authorize";
  provider_page("POST", path, "/api/v1/me/providers/sessions/", true, std::move(done));
}

void Auth::link_steam(std::string ticket, Callback done) {
  core_.rest.send("POST", "/api/v1/me/providers/steam", Body::of({{"code", std::move(ticket)}}),
                  std::move(done));
}

void Auth::send(bool authenticated, std::string_view method, std::string path, Callback done) {
  if (authenticated) {
    core_.rest.send(method, std::move(path), Body::none(), std::move(done));
  } else {
    core_.rest.send_anonymous(method, std::move(path), Body::none(), std::move(done));
  }
}

void Auth::provider_page(std::string start_method, std::string start_path,
                         std::string status_path, bool authenticated, Callback finish) {
  cancel_sign_in();
  std::uint64_t attempt = 0;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    attempt = ++state_->page_attempt;
    state_->on_page = true;
    state_->page_finish = std::move(finish);
  }
  if (!core_.config.open_url) {
    core_.post([this, attempt] {
      Response response;
      response.error = "no open_url configured";
      end_page(attempt, std::move(response));
    });
    return;
  }
  send(authenticated, start_method, std::move(start_path),
       [this, attempt, status_path = std::move(status_path), authenticated](const Response& r) {
         if (!r.ok()) return end_page(attempt, r);
         auto url = text(r.data(), "authorization_url");
         auto session_id = text(r.data(), "session_id");
         if (url.empty() || session_id.empty()) {
           Response unexpected = r;
           unexpected.error = "unexpected_reply";
           return end_page(attempt, std::move(unexpected));
         }
         {
           std::lock_guard<std::mutex> lock(state_->mutex);
           if (attempt != state_->page_attempt) return;
         }
         core_.config.open_url(url);
         poll_page(attempt, status_path + detail::escape(session_id), authenticated,
                   core_.loop->now() + core_.config.sign_in_timeout);
       });
}

void Auth::poll_page(std::uint64_t attempt, std::string status_path, bool authenticated,
                     std::chrono::milliseconds deadline) {
  auto ask = [this, attempt, status_path, authenticated, deadline] {
    {
      std::lock_guard<std::mutex> lock(state_->mutex);
      if (attempt != state_->page_attempt) return;
    }
    send(authenticated, "GET", status_path,
         [this, attempt, status_path, authenticated, deadline](const Response& r) {
           if (r.ok()) {
             auto status = text(r.data(), "status");
             if (status == "completed") return end_page(attempt, r);
             if (status != "pending") {
               // `error`: the provider or the account said no, and why.
               Response refused = r;
               refused.error = text(r.data(), "error", status);
               return end_page(attempt, std::move(refused));
             }
           } else if (r.status >= 400 && r.status < 500) {
             // The session is gone, or not this player's: asking again will
             // not change that.
             return end_page(attempt, r);
           }
           // Still pending, or the poll itself failed on the way: keep
           // asking until the player has had their time.
           if (core_.loop->now() >= deadline) {
             Response late = r;
             late.error = "timeout";
             return end_page(attempt, std::move(late));
           }
           poll_page(attempt, status_path, authenticated, deadline);
         });
  };
  auto timer = core_.loop->after(core_.config.sign_in_poll, std::move(ask));
  std::lock_guard<std::mutex> lock(state_->mutex);
  if (attempt == state_->page_attempt) {
    state_->page_timer = timer;
  } else {
    core_.loop->cancel(timer);
  }
}

void Auth::end_page(std::uint64_t attempt, Response response) {
  Callback finish;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (attempt != state_->page_attempt) return;
    ++state_->page_attempt;
    state_->on_page = false;
    core_.loop->cancel(state_->page_timer);
    state_->page_timer = 0;
    finish = std::move(state_->page_finish);
    state_->page_finish = {};
  }
  if (finish) finish(response);
}

void Auth::cancel_sign_in() {
  Callback finish;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (!state_->on_page) return;
    ++state_->page_attempt;
    state_->on_page = false;
    core_.loop->cancel(state_->page_timer);
    state_->page_timer = 0;
    finish = std::move(state_->page_finish);
    state_->page_finish = {};
  }
  core_.post([finish = std::move(finish)] {
    if (!finish) return;
    Response response;
    response.error = "cancelled";
    finish(response);
  });
}

void Auth::refresh(AuthCallback done) {
  if (!session()) {
    core_.post([done = std::move(done)] {
      if (done) done(failed(Response{}, "not_signed_in"));
    });
    return;
  }
  refresh_then([this, done = std::move(done)](bool refreshed) {
    if (!done) return;
    AuthResult result;
    if (auto current = session(); refreshed && current) {
      result.ok = true;
      result.session = *current;
    } else {
      result.error = current ? "refresh_failed" : "not_signed_in";
    }
    done(result);
  });
}

void Auth::refresh_then(std::function<void(bool)> next) {
  std::string token;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (!state_->session || state_->session->refresh_token.empty()) {
      token.clear();
    } else {
      token = state_->session->refresh_token;
      state_->waiters.push_back(std::move(next));
      if (state_->refreshing) return;
      state_->refreshing = true;
    }
  }
  if (token.empty()) {
    next(false);
    return;
  }
  core_.rest.send_anonymous(
      "POST", "/api/v1/refresh", Body::of({{"refresh_token", token}}),
      [this, token](const Response& r) {
        bool refreshed = false;
        bool rejected = false;
        auto fresh = r.ok() ? Session::from_json(r.data(), core_.unix_now()) : std::nullopt;
        bool current = false;
        std::string username;
        {
          std::lock_guard<std::mutex> lock(state_->mutex);
          // A sign-in or a sign-out since the refresh left: its answer is
          // about a session that is no longer the one in hand.
          current = state_->session && state_->session->refresh_token == token;
          if (current) username = state_->session->username;
        }
        if (current && fresh) {
          if (fresh->refresh_token.empty()) fresh->refresh_token = token;
          if (fresh->username.empty()) fresh->username = std::move(username);
          adopt(*fresh, true);
          refreshed = true;
        } else if (current && r.status >= 400 && r.status < 500) {
          // The server read the refresh token and said no: expired, revoked
          // by a password change or a logout elsewhere.
          rejected = true;
        }
        if (rejected) {
          core_.log(LogLevel::Warning, "gamend: refresh refused (" + r.error + "), signed out");
          clear();
        } else if (current && !refreshed) {
          core_.log(LogLevel::Warning, "gamend: refresh failed (" + r.error + "), retrying");
          std::lock_guard<std::mutex> lock(state_->mutex);
          core_.loop->cancel(state_->refresh_timer);
          state_->refresh_timer = core_.loop->after(kRefreshRetry, [this] { refresh(); });
        }
        std::vector<std::function<void(bool)>> waiters;
        {
          std::lock_guard<std::mutex> lock(state_->mutex);
          state_->refreshing = false;
          waiters.swap(state_->waiters);
        }
        for (auto& waiter : waiters) waiter(refreshed);
      });
}

void Auth::logout(AuthCallback done) {
  core_.rest.send("DELETE", "/api/v1/logout", Body::none(),
                  [this, done = std::move(done)](const Response& r) {
                    clear();
                    if (!done) return;
                    AuthResult result = r.ok() ? AuthResult{} : failed(r);
                    result.ok = r.ok();
                    result.response = r;
                    done(result);
                  });
}

void Auth::forget() { clear(); }

void Auth::restore(Session session) { adopt(std::move(session), false); }

std::optional<Session> Auth::session() const {
  std::lock_guard<std::mutex> lock(state_->mutex);
  return state_->session;
}

bool Auth::signed_in() const {
  std::lock_guard<std::mutex> lock(state_->mutex);
  return state_->session && !state_->session->access_token.empty();
}

void Auth::on_session_changed(SessionListener listener) {
  std::lock_guard<std::mutex> lock(state_->mutex);
  state_->listener = std::move(listener);
}

std::string Auth::bearer() const {
  std::lock_guard<std::mutex> lock(state_->mutex);
  if (!state_->session || state_->session->access_token.empty()) return {};
  return "Bearer " + state_->session->access_token;
}

void Auth::adopt(Session session, bool notify) {
  SessionListener listener;
  bool switched = false;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    switched = state_->session && state_->session->user_id != session.user_id;
    state_->session = session;
    if (notify) listener = state_->listener;
  }
  if (switched) {
    // Another player's rows and roster are not this one's.
    core_.post([this] {
      core_.kv.clear();
      core_.presence.clear();
    });
  }
  schedule_refresh();
  core_.post([this, session] { core_.realtime.session_changed(session); });
  if (listener) {
    core_.post([listener = std::move(listener), session = std::move(session)] {
      listener(session);
    });
  }
}

void Auth::clear() {
  SessionListener listener;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (!state_->session) return;
    state_->session.reset();
    core_.loop->cancel(state_->refresh_timer);
    state_->refresh_timer = 0;
    listener = state_->listener;
  }
  core_.post([this] {
    core_.realtime.session_changed(std::nullopt);
    core_.kv.clear();
    core_.presence.clear();
  });
  if (listener) {
    core_.post([listener = std::move(listener)] { listener(std::nullopt); });
  }
}

void Auth::schedule_refresh() {
  std::lock_guard<std::mutex> lock(state_->mutex);
  core_.loop->cancel(state_->refresh_timer);
  state_->refresh_timer = 0;
  const auto& session = state_->session;
  if (!session || session->refresh_token.empty()) return;

  std::int64_t left = session->expires_in;
  if (session->expires_at > 0) left = session->expires_at - core_.unix_now();
  // No lifetime at all (a session kept without one): refresh to learn it.
  std::chrono::milliseconds delay{0};
  if (left > kRefreshMargin) delay = std::chrono::milliseconds(left * 750);
  state_->refresh_timer = core_.loop->after(delay, [this] { refresh(); });
}

}  // namespace gamend
