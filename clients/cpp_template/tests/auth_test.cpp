#include <doctest/doctest.h>

#include "harness.hpp"

using gamend::json;
using harness::FakeHttp;
using harness::Harness;
using harness::Seen;
using harness::SeenAuth;
using std::chrono::seconds;

constexpr const char* kPending =
    R"({"data": {"status": "pending", "error": "", "message": "", "session": null}})";

TEST_CASE("device sign-in keeps the session and hands it to the game") {
  Harness h;
  SeenAuth seen;
  h.client->auth().login_device("device-123", seen.callback());
  auto request = h.server->next();
  CHECK(request.url == "http://game.test/api/v1/login/device");
  CHECK(json::parse(request.body) == json{{"device_id", "device-123"}});
  CHECK(FakeHttp::header(request, "authorization").empty());
  h.server->reply(200, harness::session_reply());
  h.client->poll();

  CHECK(seen.calls == 1);
  CHECK(seen.last.ok);
  CHECK(seen.last.session.user_id == "u1");
  CHECK(seen.last.session.username == "ann");
  CHECK(seen.last.session.expires_at == h.clock.wall()() + 900);
  CHECK(h.client->auth().signed_in());
  // The listener runs in the poll after the one that signed in.
  h.client->poll();
  REQUIRE(h.changes.size() == 1);
  CHECK(h.changes.back()->access_token == "a1");

  h.client->api().users_get_current_user(nullptr);
  CHECK(FakeHttp::header(h.server->next(), "authorization") == "Bearer a1");
}

TEST_CASE("a refused sign-in says why and keeps nothing") {
  Harness h;
  SeenAuth seen;
  h.client->auth().login_email("ann@example.com", "wrong", seen.callback());
  CHECK(json::parse(h.server->next().body) ==
        json{{"email", "ann@example.com"}, {"password", "wrong"}});
  h.server->reply(401, R"({"error": "invalid_credentials"})");
  h.client->poll();
  CHECK_FALSE(seen.last.ok);
  CHECK(seen.last.error == "invalid_credentials");
  CHECK(seen.last.response.status == 401);
  CHECK_FALSE(h.client->auth().signed_in());
  CHECK(h.changes.empty());
}

TEST_CASE("register sends no password, and a username only when there is one") {
  Harness h;
  Seen seen;
  h.client->auth().register_email("ann@example.com", seen.callback());
  auto plain = h.server->next();
  CHECK(plain.url == "http://game.test/api/v1/register");
  CHECK(json::parse(plain.body) == json{{"email", "ann@example.com"}});
  CHECK(FakeHttp::header(plain, "authorization").empty());
  h.server->reply(
      201, R"({"data": {"user_id": "u1", "username": "ann", "display_name": "", "email_confirmed": false}})");
  h.client->poll();
  CHECK(seen.calls == 1);
  CHECK(seen.last.ok());
  CHECK(seen.last.data()["email_confirmed"] == false);

  h.client->auth().register_email("bob@example.com", "bob", nullptr);
  CHECK(json::parse(h.server->next().body) ==
        json{{"email", "bob@example.com"}, {"username", "bob"}});
}

TEST_CASE("registering is not a sign-in") {
  Harness h;
  h.signed_in();
  Seen seen;
  h.client->auth().register_email("ann@example.com", seen.callback());
  h.server->next();
  // Even an answer that carried tokens would not be taken as a session.
  h.server->reply(201, harness::session_reply(2));
  h.client->poll();
  h.client->poll();
  CHECK(seen.calls == 1);
  CHECK(h.client->auth().session()->access_token == "a1");
  CHECK(h.changes.empty());
}

TEST_CASE("the emailed code confirms the registration, sets the password and signs in") {
  Harness h;
  SeenAuth seen;
  h.client->auth().confirm_registration("ann@example.com", "042137", "secret-pass",
                                        seen.callback());
  auto request = h.server->next();
  CHECK(request.url == "http://game.test/api/v1/register/confirm");
  CHECK(json::parse(request.body) ==
        json{{"email", "ann@example.com"}, {"code", "042137"}, {"password", "secret-pass"}});
  CHECK(FakeHttp::header(request, "authorization").empty());
  h.server->reply(200, harness::session_reply());
  h.client->poll();
  CHECK(seen.last.ok);
  CHECK(h.client->auth().signed_in());

  h.client->auth().confirm_registration("ann@example.com", "000000", "secret-pass",
                                        seen.callback());
  h.server->next();
  h.server->reply(401, R"({"error": "invalid_code"})");
  h.client->poll();
  CHECK_FALSE(seen.last.ok);
  CHECK(seen.last.error == "invalid_code");
}

TEST_CASE("a new code is asked for with the address alone") {
  Harness h;
  Seen seen;
  h.client->auth().resend_confirmation("ann@example.com", seen.callback());
  auto request = h.server->next();
  CHECK(request.url == "http://game.test/api/v1/register/resend");
  CHECK(json::parse(request.body) == json{{"email", "ann@example.com"}});
  h.server->reply(200, R"({"ok": true})");
  h.client->poll();
  CHECK(seen.last.ok());
}

TEST_CASE("Steam signs in with a ticket; an answer with no token signs nobody in") {
  Harness h;
  h.signed_in();
  SeenAuth seen;
  h.client->auth().login_steam("14000000", seen.callback());
  auto request = h.server->next();
  CHECK(request.url == "http://game.test/api/v1/auth/steam/callback");
  CHECK(json::parse(request.body) == json{{"code", "14000000"}});
  CHECK(FakeHttp::header(request, "authorization").empty());
  // An answer with no token signed nobody in.
  h.server->reply(200, R"({"data": {"linked": true, "provider": "steam"}})");
  h.client->poll();
  CHECK_FALSE(seen.last.ok);
  CHECK(seen.last.error == "no_session");
}

TEST_CASE("the access token is refreshed when three quarters of it are gone") {
  Harness h;
  h.client->auth().login_device("d", nullptr);
  h.server->reply(200, harness::session_reply(1, 900));
  h.client->poll();
  CHECK(h.server->pending() == 0);

  h.advance(seconds(674));
  CHECK(h.server->pending() == 0);
  h.advance(seconds(1));
  REQUIRE(h.server->pending() == 1);
  CHECK(h.server->next().url == "http://game.test/api/v1/refresh");
  h.server->reply(200, harness::session_reply(2, 900));
  h.client->poll();
  CHECK(h.client->auth().session()->access_token == "a2");

  // The next refresh counts from the new token.
  h.advance(seconds(674));
  CHECK(h.server->pending() == 0);
  h.advance(seconds(1));
  CHECK(h.server->pending() == 1);
}

TEST_CASE("a refresh that cannot reach the server keeps the session and tries again") {
  Harness h;
  h.signed_in(30);  // lapses within the margin: refreshed on the next poll
  h.client->poll();
  REQUIRE(h.server->pending() == 1);
  h.server->fail("timeout");
  h.client->poll();
  CHECK(h.client->auth().signed_in());
  CHECK(h.server->pending() == 0);
  h.advance(seconds(30));
  CHECK(h.server->pending() == 1);
}

TEST_CASE("a restored session is not announced back to the game") {
  Harness h;
  h.signed_in();
  h.client->poll();
  CHECK(h.changes.empty());
  CHECK(h.client->auth().session()->username == "ann");
}

TEST_CASE("an explicit refresh reports the new session") {
  Harness h;
  h.signed_in();
  SeenAuth seen;
  h.client->auth().refresh(seen.callback());
  h.server->reply(200, harness::session_reply(3));
  h.client->poll();
  CHECK(seen.last.ok);
  CHECK(seen.last.session.access_token == "a3");

  Harness signed_out;
  signed_out.client->auth().refresh(seen.callback());
  CHECK(seen.calls == 1);
  signed_out.client->poll();
  CHECK(seen.calls == 2);
  CHECK(seen.last.error == "not_signed_in");
}

TEST_CASE("logout revokes on the server and forgets here, whatever it answered") {
  Harness h;
  h.signed_in();
  SeenAuth seen;
  h.client->auth().logout(seen.callback());
  auto request = h.server->next();
  CHECK(request.method == "DELETE");
  CHECK(request.url == "http://game.test/api/v1/logout");
  CHECK(FakeHttp::header(request, "authorization") == "Bearer a1");
  h.server->fail("offline");
  h.client->poll();
  CHECK_FALSE(seen.last.ok);
  CHECK_FALSE(h.client->auth().signed_in());
  h.client->poll();
  REQUIRE(h.changes.size() == 1);
  CHECK_FALSE(h.changes.back().has_value());
}

TEST_CASE("a provider sign-in opens its page and waits for the server to resolve it") {
  Harness h;
  SeenAuth seen;
  h.client->auth().sign_in("google", seen.callback());
  auto start = h.server->next();
  CHECK(start.method == "GET");
  CHECK(start.url == "http://game.test/api/v1/auth/google");
  h.server->reply(200, R"({"data": {"authorization_url": "https://accounts.test/o", "session_id": "s 1"}})");
  h.client->poll();
  REQUIRE(h.opened.size() == 1);
  CHECK(h.opened[0] == "https://accounts.test/o");
  CHECK(h.server->pending() == 0);

  h.advance(seconds(1));
  REQUIRE(h.server->pending() == 1);
  CHECK(h.server->next().url == "http://game.test/api/v1/auth/session/s%201");
  h.server->reply(200, kPending);
  h.client->poll();
  CHECK(seen.calls == 0);

  h.advance(seconds(1));
  REQUIRE(h.server->pending() == 1);
  h.server->reply(200, R"({"data": {"status": "completed", "error": "", "message": "", "session": {
      "access_token": "oa", "refresh_token": "or", "user_id": "u9", "username": "u",
      "display_name": "", "expires_in": 900}}})");
  h.client->poll();
  CHECK(seen.calls == 1);
  CHECK(seen.last.ok);
  CHECK(seen.last.session.user_id == "u9");
  CHECK(h.client->auth().session()->access_token == "oa");
}

TEST_CASE("a sign-in the server refuses ends with its code") {
  Harness h;
  SeenAuth seen;
  h.client->auth().sign_in("discord", seen.callback());
  h.server->reply(200, R"({"data": {"authorization_url": "https://d.test", "session_id": "s1"}})");
  h.client->poll();
  h.advance(seconds(1));
  h.server->reply(200, R"({"data": {"status": "error", "error": "account_not_activated",
      "message": "Pending activation", "session": null}})");
  h.client->poll();
  CHECK_FALSE(seen.last.ok);
  CHECK(seen.last.error == "account_not_activated");
  CHECK(seen.last.response.message().empty());
  CHECK(gamend::text(seen.last.response.data(), "message") == "Pending activation");
}

TEST_CASE("a sign-in already collected answers no session") {
  Harness h;
  SeenAuth seen;
  h.client->auth().sign_in("discord", seen.callback());
  h.server->reply(200, R"({"data": {"authorization_url": "https://d.test", "session_id": "s1"}})");
  h.client->poll();
  h.advance(seconds(1));
  h.server->reply(200, R"({"data": {"status": "completed", "error": "", "message": "", "session": null}})");
  h.client->poll();
  CHECK(seen.last.error == "no_session");
  CHECK_FALSE(h.client->auth().signed_in());
}

TEST_CASE("linking opens the provider's page as the signed-in player") {
  Harness h;
  h.signed_in();
  Seen seen;
  h.client->auth().link("google", seen.callback());
  auto start = h.server->next();
  CHECK(start.method == "POST");
  CHECK(start.url == "http://game.test/api/v1/me/providers/google/authorize");
  CHECK(FakeHttp::header(start, "authorization") == "Bearer a1");
  h.server->reply(200, R"({"data": {"authorization_url": "https://g.test", "session_id": "k1"}})");
  h.client->poll();
  CHECK(h.opened == std::vector<std::string>{"https://g.test"});

  h.advance(seconds(1));
  auto poll = h.server->next();
  CHECK(poll.url == "http://game.test/api/v1/me/providers/sessions/k1");
  CHECK(FakeHttp::header(poll, "authorization") == "Bearer a1");
  h.server->reply(200, R"({"data": {"status": "pending", "error": "", "message": "", "provider": "google"}})");
  h.client->poll();
  h.advance(seconds(1));
  h.server->reply(200, R"({"data": {"status": "completed", "error": "", "message": "", "provider": "google"}})");
  h.client->poll();
  CHECK(seen.calls == 1);
  CHECK(seen.last.ok());
  // Linking leaves the session as it was.
  CHECK(h.client->auth().session()->access_token == "a1");
}

TEST_CASE("a link the server refuses ends with its code") {
  Harness h;
  h.signed_in();
  Seen seen;
  h.client->auth().link("google", seen.callback());
  h.server->reply(200, R"({"data": {"authorization_url": "https://g.test", "session_id": "k1"}})");
  h.client->poll();
  h.advance(seconds(1));
  h.server->reply(200, R"({"data": {"status": "error", "error": "provider_already_linked",
      "message": "Linked to another account", "provider": "google"}})");
  h.client->poll();
  CHECK_FALSE(seen.last.ok());
  CHECK(seen.last.error == "provider_already_linked");
}

TEST_CASE("a Steam ticket links Steam to the signed-in account") {
  Harness h;
  h.signed_in();
  Seen seen;
  h.client->auth().link_steam("14000000", seen.callback());
  auto request = h.server->next();
  CHECK(request.url == "http://game.test/api/v1/me/providers/steam");
  CHECK(json::parse(request.body) == json{{"code", "14000000"}});
  CHECK(FakeHttp::header(request, "authorization") == "Bearer a1");
  h.server->reply(200, R"({"data": {"id": "u1", "linked_providers": {"steam": true}}})");
  h.client->poll();
  CHECK(seen.last.ok());
  CHECK(seen.last.data()["linked_providers"]["steam"] == true);
}

TEST_CASE("a sign-in nobody finishes times out") {
  Harness h;
  SeenAuth seen;
  h.client->auth().sign_in("google", seen.callback());
  h.server->reply(200, R"({"data": {"authorization_url": "https://g.test", "session_id": "s1"}})");
  h.client->poll();
  for (int i = 0; i < 10 && seen.calls == 0; ++i) {
    h.advance(seconds(1));
    if (h.server->pending() > 0) {
      h.server->reply(200, kPending);
      h.client->poll();
    }
  }
  CHECK(seen.calls == 1);
  CHECK(seen.last.error == "timeout");
}

TEST_CASE("a cancelled sign-in says so, and ignores what arrives after") {
  Harness h;
  SeenAuth seen;
  h.client->auth().sign_in("google", seen.callback());
  h.server->reply(200, R"({"data": {"authorization_url": "https://g.test", "session_id": "s1"}})");
  h.client->poll();
  h.client->auth().cancel_sign_in();
  CHECK(seen.calls == 0);
  h.client->poll();
  CHECK(seen.calls == 1);
  CHECK(seen.last.error == "cancelled");
  h.advance(seconds(2));
  CHECK(h.server->pending() == 0);
}

TEST_CASE("sign-in without a way to open the page fails") {
  Harness h(gamend::Dispatch::Poll, false);
  SeenAuth seen;
  h.client->auth().sign_in("google", seen.callback());
  CHECK(h.server->pending() == 0);
  h.client->poll();
  CHECK(seen.last.error == "no open_url configured");
}

TEST_CASE("a session survives a round trip through JSON") {
  gamend::Session session;
  session.access_token = "a";
  session.refresh_token = "r";
  session.user_id = "u";
  session.username = "n";
  session.display_name = "N";
  session.expires_in = 900;
  session.expires_at = 1234;
  auto back = gamend::Session::from_json(session.to_json());
  REQUIRE(back.has_value());
  CHECK(back->to_json() == session.to_json());

  CHECK_FALSE(gamend::Session::from_json(json{{"refresh_token", "r"}}).has_value());
  auto fresh = gamend::Session::from_json(json{{"access_token", "a"}, {"expires_in", 60}}, 1000);
  CHECK(fresh->expires_at == 1060);
}
