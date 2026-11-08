#include <doctest/doctest.h>

#include "harness.hpp"
#include "phoenix.hpp"

using gamend::json;
using gamend::RealtimeState;
using harness::Harness;
using std::chrono::milliseconds;
using std::chrono::seconds;

namespace {

std::string reply(const std::string& join_ref, const std::string& ref, const std::string& topic,
                  const std::string& status, const json& response = json::object()) {
  return gamend::dump(json::array(
      {join_ref, ref, topic, "phx_reply", {{"status", status}, {"response", response}}}));
}

std::string message(const std::string& topic, const std::string& event, const json& payload) {
  return gamend::dump(json::array({nullptr, nullptr, topic, event, payload}));
}

json frame_of(const std::string& text) { return json::parse(text); }

// Signed in as u1 and connected, the user channel joined.
struct Connected : Harness {
  Connected() {
    signed_in();
    client->realtime().on_event([this](const gamend::Event& e) { events.push_back(e); });
    client->realtime().on_state([this](RealtimeState s) { states.push_back(s); });
    client->realtime().connect();
    socket->accept();
    client->poll();
    auto frames = socket->take_frames();
    REQUIRE(frames.size() == 1);
    socket->receive(reply("1", "1", "user:u1", "ok"));
    client->poll();
  }
  std::vector<gamend::Event> events;
  std::vector<RealtimeState> states;
};

}  // namespace

TEST_CASE("the connection names the player's token, the run, and the protocol version") {
  Harness h;
  h.signed_in();
  h.client->realtime().connect();
  CHECK(h.socket->opened());
  CHECK(h.socket->url() ==
        "ws://game.test/socket/websocket?vsn=2.0.0&token=a1&client_session=run-1");
  CHECK(h.client->realtime().state() == RealtimeState::Connecting);
}

TEST_CASE("connecting without a player does nothing") {
  Harness h;
  h.client->realtime().connect();
  CHECK_FALSE(h.socket->opened());
  CHECK(h.client->realtime().state() == RealtimeState::Disconnected);
}

TEST_CASE("once open, it joins the user channel") {
  Harness h;
  h.signed_in();
  h.client->realtime().connect();
  h.socket->accept();
  h.client->poll();
  CHECK(h.client->realtime().state() == RealtimeState::Connected);
  auto frames = h.socket->take_frames();
  REQUIRE(frames.size() == 1);
  CHECK(frame_of(frames[0]) == json::array({"1", "1", "user:u1", "phx_join", json::object()}));
  CHECK_FALSE(h.client->realtime().joined("user:u1"));
  h.socket->receive(reply("1", "1", "user:u1", "ok"));
  h.client->poll();
  CHECK(h.client->realtime().joined("user:u1"));
}

TEST_CASE("server events arrive named, in poll") {
  Connected c;
  c.socket->receive(message("user:u1", "updated", {{"id", "u1"}}));
  CHECK(c.events.empty());
  c.client->poll();
  REQUIRE(c.events.size() == 1);
  CHECK(c.events[0].kind == gamend::events::USER_UPDATED);
  CHECK(c.events[0].event == "updated");
  CHECK(c.events[0].payload["id"] == "u1");

  c.socket->receive(message("user:u1", "something_new", json::object()));
  c.client->poll();
  CHECK(c.events.back().kind == gamend::events::MESSAGE);
}

TEST_CASE("a hook call goes over the user channel and answers its data or its error") {
  Connected c;
  gamend::HookResult got;
  c.client->realtime().call_hook("arena", "start", json::array({1, "x"}),
                                 [&](const gamend::HookResult& r) { got = r; });
  auto frames = c.socket->take_frames();
  REQUIRE(frames.size() == 1);
  CHECK(frame_of(frames[0]) ==
        json::array({"1", "2", "user:u1", "call_hook",
                     {{"plugin", "arena"}, {"fn", "start"}, {"args", {1, "x"}}}}));
  c.socket->receive(reply("1", "2", "user:u1", "ok", {{"data", {{"round", 1}}}}));
  c.client->poll();
  CHECK(got.ok);
  CHECK(got.data["round"] == 1);

  c.client->realtime().call_hook("arena", "nope", json::array(),
                                 [&](const gamend::HookResult& r) { got = r; });
  c.socket->receive(reply("1", "3", "user:u1", "error", {{"error", "unknown_function"}}));
  c.client->poll();
  CHECK_FALSE(got.ok);
  CHECK(got.error == "unknown_function");
}

TEST_CASE("a command goes to its channel with its event and params") {
  Connected c;
  gamend::commands::results_list(c.client->realtime(), {{"kind", "match"}});
  auto frames = c.socket->take_frames();
  REQUIRE(frames.size() == 1);
  json sent = frame_of(frames[0]);
  CHECK(sent[2] == "user:u1");
  CHECK(sent[3] == "results:list");
  CHECK(sent[4]["kind"] == "match");

  c.client->realtime().join_lobby("L1");
  frames = c.socket->take_frames();
  REQUIRE(frames.size() == 1);
  json join = frame_of(frames[0]);
  c.socket->receive(
      reply(join[0].get<std::string>(), join[1].get<std::string>(), "lobby:L1", "ok"));
  c.client->poll();

  gamend::commands::lobby_get_server_time(c.client->realtime(), "L1");
  frames = c.socket->take_frames();
  REQUIRE(frames.size() == 1);
  sent = frame_of(frames[0]);
  CHECK(sent[2] == "lobby:L1");
  CHECK(sent[3] == "get_server_time");
}

TEST_CASE("a push nobody answers times out; one to an unjoined topic is refused") {
  Connected c;
  gamend::Reply got;
  c.client->realtime().push("user:u1", "ping", json::object(),
                            [&](const gamend::Reply& r) { got = r; });
  CHECK(c.socket->take_frames().size() == 1);
  c.advance(seconds(10));
  CHECK(got.status == "timeout");
  CHECK_FALSE(got.ok);

  c.client->realtime().push("lobby:x", "ping", json::object(),
                            [&](const gamend::Reply& r) { got = r; });
  CHECK(c.socket->take_frames().empty());
  c.client->poll();
  CHECK(got.status == "not_joined");
}

TEST_CASE("topics join now or when the connection opens, and rejoin after a drop, in order") {
  Harness h;
  h.signed_in();
  gamend::Reply lobby_join;
  h.client->realtime().join_lobby("l1", [&](const gamend::Reply& r) { lobby_join = r; });
  h.client->realtime().connect();
  h.socket->accept();
  h.client->poll();
  auto frames = h.socket->take_frames();
  REQUIRE(frames.size() == 2);
  CHECK(frame_of(frames[0])[2] == "user:u1");
  CHECK(frame_of(frames[1])[2] == "lobby:l1");
  h.socket->receive(reply("1", "1", "user:u1", "ok"));
  h.socket->receive(reply("2", "2", "lobby:l1", "ok"));
  h.client->poll();
  CHECK(lobby_join.ok);

  h.socket->drop();
  h.client->poll();
  CHECK(h.client->realtime().state() == RealtimeState::Reconnecting);
  CHECK_FALSE(h.client->realtime().joined("lobby:l1"));
  CHECK(h.socket->opens() == 1);
  h.advance(milliseconds(100));
  CHECK(h.socket->opens() == 2);
  h.socket->accept();
  h.client->poll();
  frames = h.socket->take_frames();
  REQUIRE(frames.size() == 2);
  CHECK(frame_of(frames[0])[2] == "user:u1");
  CHECK(frame_of(frames[1])[2] == "lobby:l1");
  CHECK(h.client->realtime().state() == RealtimeState::Connected);
}

TEST_CASE("a pending push fails when the connection drops") {
  Connected c;
  gamend::Reply got;
  c.client->realtime().push("user:u1", "ping", json::object(),
                            [&](const gamend::Reply& r) { got = r; });
  c.socket->drop();
  c.client->poll();
  CHECK(got.status == "disconnected");
}

TEST_CASE("a connection that never opened refreshes the token before the next attempt") {
  Harness h;
  h.signed_in();
  h.client->realtime().connect();
  h.socket->fail("handshake refused");
  h.client->poll();
  h.advance(milliseconds(100));
  // The refresh goes first; the socket waits for it.
  REQUIRE(h.server->pending() == 1);
  CHECK(h.server->next().url == "http://game.test/api/v1/refresh");
  CHECK(h.socket->opens() == 1);
  h.server->reply(200, harness::session_reply(2));
  h.client->poll();
  CHECK(h.socket->opens() == 2);
  CHECK(h.socket->url().find("token=a2") != std::string::npos);
}

TEST_CASE("backoff grows and holds at its last step") {
  Harness h;
  h.signed_in();
  h.client->realtime().connect();
  h.socket->accept();
  h.client->poll();
  const int expected[] = {100, 500, 1000, 2000, 5000, 10000, 10000};
  for (int wait : expected) {
    int before = h.socket->opens();
    h.socket->drop();
    h.client->poll();
    h.advance(milliseconds(wait - 1));
    CHECK(h.socket->opens() == before);
    h.advance(milliseconds(1));
    if (h.server->pending() > 0) {
      // A drop that never opened refreshes first.
      h.server->reply(200, harness::session_reply(1));
      h.client->poll();
    }
    CHECK(h.socket->opens() == before + 1);
  }
}

TEST_CASE("a missed heartbeat drops the connection and reconnects") {
  Connected c;
  c.advance(seconds(30));
  auto frames = c.socket->take_frames();
  REQUIRE(frames.size() == 1);
  CHECK(frame_of(frames[0])[2] == "phoenix");
  CHECK(frame_of(frames[0])[3] == "heartbeat");

  // Answered: the next beat goes out on time.
  auto ref = frame_of(frames[0])[1].get<std::string>();
  c.socket->receive(gamend::dump(json::array({nullptr, ref, "phoenix", "phx_reply",
                                              {{"status", "ok"}, {"response", json::object()}}})));
  c.advance(seconds(30));
  REQUIRE(c.socket->take_frames().size() == 1);

  // Unanswered: the one after that finds it still pending.
  c.advance(seconds(30));
  CHECK(c.client->realtime().state() == RealtimeState::Reconnecting);
  c.advance(milliseconds(100));
  CHECK(c.socket->opens() == 2);
}

TEST_CASE("a channel that errors rejoins; one the server closes does not") {
  Connected c;
  c.client->realtime().join_lobby("l1");
  c.socket->take_frames();
  c.socket->receive(reply("2", "2", "lobby:l1", "ok"));
  c.client->poll();

  c.socket->receive(message("lobby:l1", "phx_error", json::object()));
  c.client->poll();
  CHECK_FALSE(c.client->realtime().joined("lobby:l1"));
  c.advance(seconds(1));
  auto frames = c.socket->take_frames();
  REQUIRE(frames.size() == 1);
  CHECK(frame_of(frames[0])[3] == "phx_join");
  auto ref = frame_of(frames[0])[1].get<std::string>();
  c.socket->receive(reply(ref, ref, "lobby:l1", "ok"));
  c.client->poll();
  CHECK(c.client->realtime().joined("lobby:l1"));

  c.socket->receive(message("lobby:l1", "phx_close", json::object()));
  c.client->poll();
  CHECK_FALSE(c.client->realtime().joined("lobby:l1"));
  c.advance(seconds(5));
  CHECK(c.socket->take_frames().empty());
}

TEST_CASE("a join the server refuses for good is dropped, and says why") {
  Connected c;
  gamend::Reply got;
  c.client->realtime().join_lobby("secret", [&](const gamend::Reply& r) { got = r; });
  c.socket->take_frames();
  c.socket->receive(reply("2", "2", "lobby:secret", "error", {{"reason", "unauthorized"}}));
  c.client->poll();
  CHECK_FALSE(got.ok);
  CHECK(got.error == "unauthorized");
  c.advance(seconds(5));
  CHECK(c.socket->take_frames().empty());
}

TEST_CASE("leaving sends phx_leave and stops rejoining") {
  Connected c;
  c.client->realtime().join_lobby("l1");
  c.socket->take_frames();
  c.socket->receive(reply("2", "2", "lobby:l1", "ok"));
  c.client->poll();
  gamend::Reply got;
  c.client->realtime().leave("lobby:l1", [&](const gamend::Reply& r) { got = r; });
  auto frames = c.socket->take_frames();
  REQUIRE(frames.size() == 1);
  CHECK(frame_of(frames[0]) == json::array({"2", "3", "lobby:l1", "phx_leave", json::object()}));
  c.socket->receive(reply("2", "3", "lobby:l1", "ok"));
  c.client->poll();
  CHECK(got.ok);

  c.socket->drop();
  c.client->poll();
  c.advance(milliseconds(100));
  c.socket->accept();
  c.client->poll();
  frames = c.socket->take_frames();
  REQUIRE(frames.size() == 1);
  CHECK(frame_of(frames[0])[2] == "user:u1");
}

TEST_CASE("disconnect closes for good; signing out does the same") {
  Connected c;
  c.client->realtime().disconnect();
  CHECK(c.client->realtime().state() == RealtimeState::Disconnected);
  CHECK_FALSE(c.socket->opened());
  c.advance(seconds(20));
  CHECK(c.socket->opens() == 1);

  Connected d;
  d.client->auth().forget();
  d.client->poll();
  CHECK(d.client->realtime().state() == RealtimeState::Disconnected);
  d.advance(seconds(20));
  CHECK(d.socket->opens() == 1);
}

TEST_CASE("state changes are announced in order") {
  Connected c;
  c.socket->drop();
  c.client->poll();
  c.advance(milliseconds(100));
  c.socket->accept();
  c.client->poll();
  CHECK(c.states == std::vector<RealtimeState>{RealtimeState::Connecting, RealtimeState::Connected,
                                               RealtimeState::Reconnecting,
                                               RealtimeState::Connected});
}

TEST_CASE("a binary event no decoder reads still arrives, as bytes") {
  Connected c;
  std::string frame;
  frame += static_cast<char>(2);  // broadcast
  frame += static_cast<char>(7);
  frame += static_cast<char>(7);
  frame += "user:u1";
  frame += "unknown";
  frame += std::string("\x08\x01", 2);
  c.socket->receive_binary(frame);
  c.client->poll();
  REQUIRE(c.events.size() == 1);
  CHECK(c.events[0].event == "unknown");
  CHECK(c.events[0].payload.is_null());
  CHECK(c.events[0].bytes == std::string("\x08\x01", 2));
}

TEST_CASE("the protocol: refs, join refs and frames") {
  gamend::detail::Phoenix p;
  auto [join_ref, join] = p.join("room:1", {{"a", 1}});
  CHECK(join_ref == "1");
  CHECK(join == R"(["1","1","room:1","phx_join",{"a":1}])");
  auto push = p.push("room:1", "shout", json::object());
  REQUIRE(push);
  CHECK(push->second == R"(["1","2","room:1","shout",{}])");
  CHECK_FALSE(p.push("room:2", "shout", json::object()));
  CHECK_FALSE(p.decode("not json"));
  CHECK_FALSE(p.decode("[1,2,3]"));

  std::string binary;
  binary += static_cast<char>(1);  // reply
  binary += static_cast<char>(1);
  binary += static_cast<char>(1);
  binary += static_cast<char>(6);
  binary += static_cast<char>(2);
  binary += "1";
  binary += "2";
  binary += "room:1";
  binary += "ok";
  binary += "BYTES";
  auto decoded = p.decode_binary(binary);
  REQUIRE(decoded);
  CHECK(decoded->kind == gamend::detail::Frame::Kind::Reply);
  CHECK(decoded->ref == "2");
  CHECK(decoded->status == "ok");
  CHECK(*decoded->bytes == "BYTES");
  CHECK_FALSE(p.decode_binary(binary.substr(0, 8)));
}
