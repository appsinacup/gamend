// The client: configuration, transports, and the one place callbacks run.
//
//     gamend::Config config;
//     config.base_url = "https://game.example.com";
//     config.http = gamend::make_curl_transport();
//     gamend::Client client(std::move(config));
//
//     client.auth().login_device("device-123", [&](const gamend::AuthResult& r) {
//       if (!r.ok) return log(r.error);
//       client.api().lobbies_quick_join({{"title", "duel"}, {"max_users", 2}},
//         [](const gamend::Response& r) { if (r.ok()) use(r.data()); });
//     });
//
//     // Once per frame, on the game thread:
//     client.poll();
//
// I/O never runs on the game thread, and callbacks never run anywhere else:
// transports complete on their own threads into an inbox that `poll()`
// drains, in arrival order, along with the timers (token refresh, sign-in
// polling). A callback never runs inside the call that started it.
#pragma once

#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "gamend/export.hpp"
#include "gamend/transport.hpp"

namespace gamend {

class Api;
class Auth;
class Kv;
class Presence;
class Realtime;
class Rest;
class WebRtc;

enum class Dispatch {
  /// Callbacks run in `Client::poll()`, on the thread that calls it.
  Poll,
  /// Callbacks run on the transport's thread as soon as it completes, one at
  /// a time. For bots and tools with no frame loop; racy for game code that
  /// touches its own state from them. Timers still run in `poll()`.
  Immediate,
};

enum class LogLevel { Debug, Info, Warning, Error };

enum class RealtimeFormat {
  /// Every server event as JSON text.
  Json,
  /// The events `proto/gamend_realtime.proto` maps as binary protobuf
  /// frames, decoded before they reach `on_event`: smaller on the wire, and
  /// timestamps arrive as unix milliseconds (`*_ms`).
  Protobuf,
};

struct Config {
  /// The server root, `https://game.example.com`; paths are appended to it.
  std::string base_url;
  /// Required. `make_curl_transport()`, an engine adapter, or a fake.
  std::unique_ptr<HttpTransport> http;
  /// For the realtime layer; unused until it connects.
  std::unique_ptr<WebSocketTransport> websocket;
  /// For `Client::webrtc()`: `make_libdatachannel_transport()` or an
  /// engine's own. Unused until it connects.
  std::unique_ptr<PeerTransport> webrtc;
  Dispatch dispatch = Dispatch::Poll;
  std::chrono::milliseconds http_timeout{10000};
  /// Opens a sign-in page for `Auth::sign_in`: the system browser, a web
  /// view, `ShellExecute`. Without it, sign-in through a provider fails.
  std::function<void(const std::string& url)> open_url;
  /// Where the SDK's own lines go. Silent without it.
  std::function<void(LogLevel level, const std::string& line)> log;
  /// This run's id, sent as `x-gamend-session` so the server files a run's
  /// client and server lines together. Random when empty.
  std::string run_id;
  /// How often `Auth::sign_in` asks whether the player finished at the
  /// provider, and how long it waits for them.
  std::chrono::milliseconds sign_in_poll{1000};
  std::chrono::milliseconds sign_in_timeout{300000};
  /// How the server sends realtime events.
  RealtimeFormat realtime_format = RealtimeFormat::Json;
  /// How long a join or a push waits for the server's reply.
  std::chrono::milliseconds push_timeout{10000};
  /// ICE servers for WebRTC, as `stun:host:port` or `turn:user:pass@host:port`.
  std::vector<std::string> ice_servers{"stun:stun.l.google.com:19302"};
  /// The DataChannels `WebRtc::connect` opens. The server answers hook calls
  /// on `events` and holds up to four channels; add `{"state", false, 0}`
  /// for an unordered pipe, as the JS and Godot clients open by default.
  std::vector<DataChannelSpec> data_channels{{"events", true, -1}};
  /// How hook calls ride the `events` channel: JSON messages, or protobuf
  /// envelopes with request ids.
  RealtimeFormat webrtc_format = RealtimeFormat::Json;
  /// How long `WebRtc::connect` waits for a channel to open.
  std::chrono::milliseconds webrtc_timeout{15000};
  /// The waits before each reconnect attempt; the last repeats.
  std::vector<std::chrono::milliseconds> reconnect_delays{
      std::chrono::milliseconds(100),  std::chrono::milliseconds(500),
      std::chrono::milliseconds(1000), std::chrono::milliseconds(2000),
      std::chrono::milliseconds(5000), std::chrono::milliseconds(10000)};
  /// Monotonic milliseconds for timers; the steady clock when empty. Tests
  /// pass a fake one.
  std::function<std::chrono::milliseconds()> clock;
  /// Unix seconds, for when a kept session's token lapses; the system clock
  /// when empty.
  std::function<std::int64_t()> unix_clock;
};

namespace detail {
struct Core;
}

class GAMEND_EXPORT Client {
 public:
  explicit Client(Config config);
  ~Client();
  Client(const Client&) = delete;
  Client& operator=(const Client&) = delete;

  /// Every operation of the REST API, one method each.
  Api& api();
  /// Signing in, and staying signed in.
  Auth& auth();
  /// The authenticated caller `api()` is built on, for a path it lacks.
  Rest& rest();
  /// The realtime connection: channels, events, server hooks.
  Realtime& realtime();
  /// Live key-value rows over the realtime connection, and their cache.
  Kv& kv();
  /// Who is around, as the realtime events tell it.
  Presence& presence();
  /// WebRTC DataChannels to the server, signaled over the user channel.
  WebRtc& webrtc();
  /// The transport the realtime layer drives; null when none was given.
  WebSocketTransport* websocket();

  /// Run what arrived since the last call: replies, then due timers. Call it
  /// once per frame on the game thread.
  void poll();

  const std::string& base_url() const;
  const std::string& run_id() const;

 private:
  std::unique_ptr<detail::Core> core_;
};

}  // namespace gamend
