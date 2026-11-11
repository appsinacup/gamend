// WebRTC DataChannels to the server: lower latency than the socket for game
// traffic, signaled over the realtime user channel.
//
//     config.webrtc = gamend::make_libdatachannel_transport();  // GAMEND_WITH_WEBRTC
//     ...
//     client.realtime().connect();
//     client.webrtc().connect([&](const std::string& error) {
//       if (!error.empty()) return log(error);
//       client.webrtc().call_hook("arena", "move", {{"x", 1}},
//         [](const gamend::HookResult& r) { ... });
//     });
//
// The server is the other peer. One channel by default: `events`, reliable
// and ordered, which hook calls ride on (`Config::data_channels` adds more,
// up to the server's four). Like the other transports, the peer connection
// is an interface: libdatachannel is the one shipped, an engine can bring
// its own.
#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "gamend/export.hpp"
#include "gamend/json.hpp"
#include "gamend/realtime.hpp"
#include "gamend/transport.hpp"

namespace gamend {

namespace detail {
struct Core;
}

enum class WebRtcState { Closed, Connecting, Connected, Failed };

class GAMEND_EXPORT WebRtc {
 public:
  explicit WebRtc(detail::Core& core);
  ~WebRtc();
  WebRtc(const WebRtc&) = delete;
  WebRtc& operator=(const WebRtc&) = delete;

  /// Offer a connection to the server over the user channel (join it first:
  /// `Realtime::connect`). `done` gets "" once a channel is open, or why
  /// not: `not_joined`, `no_transport`, the server's refusal, `failed`,
  /// `timeout`.
  void connect(std::function<void(const std::string& error)> done = {});
  /// Close the connection and tell the server.
  void close();
  WebRtcState state() const { return state_.load(); }
  bool channel_open(const std::string& label) const;

  /// Send on a channel; false when it is not open.
  bool send(const std::string& label, const std::string& data, bool binary = false);
  /// Call a server hook over the `events` channel.
  void call_hook(std::string plugin, std::string fn, json args, HookCallback done);
  /// Call a typed hook with the game's own encoded request
  /// (`<FnName>Request`, registered by the plugin); `done` gets the reply's
  /// bytes in `HookResult::bytes`. Needs `webrtc_format = Protobuf`; the
  /// server relays the bytes without decoding them.
  void call_hook_raw(std::string plugin, std::string fn, std::string request, HookCallback done);

  /// What arrives on any channel, hook replies aside.
  std::uint64_t on_data(
      std::function<void(const std::string& label, const std::string& data, bool binary)> listener);
  std::uint64_t on_state(std::function<void(WebRtcState)> listener);
  /// A channel opened (`true`) or closed.
  std::uint64_t on_channel(std::function<void(const std::string& label, bool open)> listener);
  void off(std::uint64_t listener);

 private:
  struct Call;

  void signal(const Event& event);
  void local_description(std::uint64_t generation, const std::string& sdp,
                         const std::string& type);
  void local_candidate(std::uint64_t generation, const std::string& candidate,
                       const std::string& mid);
  void peer_state(std::uint64_t generation, const std::string& state);
  void channel_opened(std::uint64_t generation, const std::string& label);
  void channel_closed(std::uint64_t generation, const std::string& label);
  void message(std::uint64_t generation, const std::string& label, const std::string& data,
               bool binary);
  bool reply(const std::string& data, bool binary);
  void start_call(std::string plugin, std::string fn, json args, std::string raw, bool is_raw,
                  HookCallback done);
  void finish_connect(const std::string& error);
  void set_state(WebRtcState state);
  void fail_calls(const std::string& error);

  detail::Core& core_;
  std::atomic<WebRtcState> state_{WebRtcState::Closed};
  std::uint64_t generation_ = 0;
  std::function<void(const std::string&)> connecting_;
  std::uint64_t connect_timer_ = 0;
  std::map<std::string, bool> open_;
  std::vector<std::shared_ptr<Call>> calls_;
  std::uint32_t next_call_ = 1;
  std::uint64_t next_listener_ = 1;
  std::map<std::uint64_t, std::function<void(const std::string&, const std::string&, bool)>>
      data_listeners_;
  std::map<std::uint64_t, std::function<void(WebRtcState)>> state_listeners_;
  std::map<std::uint64_t, std::function<void(const std::string&, bool)>> channel_listeners_;
};

}  // namespace gamend
