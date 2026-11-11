// The C++ SDK as the Unreal plugin's GamendSDK module compiles it, used from
// outside its own library, as a game module of an editor build uses it.
//
// clients/check_unreal.sh builds the plugin's copy of the SDK into a shared
// library with every symbol hidden unless `GAMEND_EXPORT` marks it, and links
// this against it. A class or function a game can call that is not marked
// fails the link here instead of in a game's editor build. It then runs a
// short scenario over the fake transports, so the library also works.
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "gamend/gamend.hpp"
#include "gamend/testing/fake_transport.hpp"

namespace {

int failures = 0;

void expect(bool ok, const char* what) {
  if (ok) return;
  ++failures;
  std::fprintf(stderr, "sdk_check: %s\n", what);
}

std::string session_reply() {
  gamend::json data = {{"access_token", "a1"}, {"refresh_token", "r1"}, {"user_id", "u1"},
                       {"username", "ann"},    {"display_name", "Ann"}, {"expires_in", 900}};
  return gamend::dump(gamend::json{{"data", data}});
}

std::string phoenix_reply(const std::string& join_ref, const std::string& ref,
                          const std::string& topic) {
  return gamend::dump(gamend::json::array(
      {join_ref, ref, topic, "phx_reply", {{"status", "ok"}, {"response", gamend::json::object()}}}));
}

std::string phoenix_message(const std::string& topic, const std::string& event,
                            const gamend::json& payload) {
  return gamend::dump(gamend::json::array({nullptr, nullptr, topic, event, payload}));
}

}  // namespace

int main() {
  using gamend::json;
  using gamend::testing::FakeClock;
  using gamend::testing::FakeHttp;
  using gamend::testing::FakePeer;
  using gamend::testing::FakeWebSocket;

  FakeClock clock;
  auto http = std::make_unique<FakeHttp>();
  FakeHttp& server = *http;
  auto websocket = std::make_unique<FakeWebSocket>();
  FakeWebSocket& socket = *websocket;

  gamend::Config config;
  config.base_url = "http://game.test";
  config.http = std::move(http);
  config.websocket = std::move(websocket);
  config.webrtc = std::make_unique<FakePeer>();
  config.clock = clock.steady();
  config.unix_clock = clock.wall();
  config.run_id = "run-1";
  gamend::Client client(std::move(config));
  expect(client.base_url() == "http://game.test", "base_url");
  expect(client.websocket() != nullptr, "websocket");

  // Auth and Session.
  std::vector<std::optional<gamend::Session>> changes;
  client.auth().on_session_changed(
      [&](const std::optional<gamend::Session>& session) { changes.push_back(session); });
  bool signed_in = false;
  client.auth().login_device("device-1", [&](const gamend::AuthResult& r) { signed_in = r.ok; });
  expect(server.pending() == 1, "login_device sends a request");
  server.reply(200, session_reply());
  client.poll();  // the sign-in's callback
  client.poll();  // the session listener, posted by it
  expect(signed_in && client.auth().signed_in(), "login_device signs in");
  expect(changes.size() == 1 && changes.back() && changes.back()->user_id == "u1",
         "on_session_changed");
  auto kept = gamend::Session::from_json(client.auth().session()->to_json());
  expect(kept && kept->refresh_token == "r1", "Session round trip");

  // Api, Response and the generated codecs.
  std::optional<gamend::models::Lobby> lobby;
  client.api().lobbies_quick_join({{"title", "duel"}, {"max_users", 2}},
                                  [&](const gamend::Response& r) {
                                    lobby = r.as<gamend::models::Lobby>();
                                  });
  expect(server.pending() == 1, "lobbies_quick_join sends a request");
  expect(FakeHttp::header(server.next(), "authorization") == "Bearer a1", "bearer token");
  server.reply(200, R"({"data": {"id": "l1", "title": "duel", "max_users": 2}})");
  client.poll();
  expect(lobby && lobby->id == "l1" && lobby->max_users == 2, "Response::as<models::Lobby>");
  json written = gamend::Codec<gamend::models::Lobby>::write(*lobby);
  expect(gamend::text(written, "title") == "duel", "Codec<models::Lobby>::write");

  // Rest, for a path Api does not have.
  int status = 0;
  client.rest().send("GET", "/api/v1/anything", gamend::Body::none(),
                     [&](const gamend::Response& r) { status = r.status; });
  server.reply(204, "");
  client.poll();
  expect(status == 204, "Rest::send");

  // Realtime, Kv and Presence.
  std::vector<gamend::Event> events;
  client.realtime().on_event([&](const gamend::Event& e) { events.push_back(e); });
  client.realtime().connect();
  socket.accept();
  client.poll();
  auto frames = socket.take_frames();
  expect(frames.size() == 1, "connect joins the user channel");
  socket.receive(phoenix_reply("1", "1", "user:u1"));
  client.poll();
  expect(client.realtime().state() == gamend::RealtimeState::Connected, "Realtime connects");
  expect(client.realtime().joined("user:u1"), "Realtime joins user:<id>");

  socket.receive(phoenix_message("user:u1", "kv_updated",
                                 {{"key", "progress"}, {"user_id", "u1"}, {"data", {{"level", 3}}}}));
  client.poll();
  expect(!events.empty() && events.back().kind == gamend::events::KV_UPDATED, "Event::kind");
  expect(gamend::events::signal_of("lobby:l1", "updated") == gamend::events::LOBBY_UPDATED,
         "events::signal_of");

  socket.take_frames();
  client.kv().subscribe({"progress", "u1"});
  expect(socket.take_frames().size() == 1, "Kv::subscribe pushes kv:subscribe");
  expect(!client.kv().subscribed({"progress", "u1"}), "Kv::subscribed waits for the reply");
  client.presence().cache_user("u2", {{"id", "u2"}, {"username", "bo"}});
  expect(gamend::text(client.presence().user("u2"), "username") == "bo", "Presence");
  gamend::commands::results_list(client.realtime(), {{"kind", "match"}});
  expect(!socket.take_frames().empty(), "commands::results_list pushes");

  // WebRtc, without connecting.
  expect(!client.webrtc().channel_open("events"), "WebRtc");

  client.realtime().disconnect();
  expect(client.realtime().state() == gamend::RealtimeState::Disconnected, "disconnect");

  if (failures == 0) std::printf("sdk_check: ok\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
