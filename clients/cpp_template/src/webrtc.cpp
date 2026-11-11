#include "gamend/webrtc.hpp"

#include <algorithm>
#include <utility>

#include "core.hpp"
#include "proto.hpp"

namespace gamend {

struct WebRtc::Call {
  std::uint32_t id = 0;       // protobuf: the envelope's request id
  std::string plugin, fn;     // JSON: replies are matched by these, oldest first
  HookCallback done;
  std::uint64_t timer = 0;
};

namespace {

bool protobuf(const detail::Core& core) {
  return core.config.webrtc_format == RealtimeFormat::Protobuf;
}

}  // namespace

WebRtc::WebRtc(detail::Core& core) : core_(core) {
  core_.realtime.on_event([this](const Event& e) { signal(e); });
  core_.realtime.on_state([this](RealtimeState s) {
    // The server's peer lives in the user channel's process: when the
    // socket goes, so does the other end of this connection.
    if (s != RealtimeState::Connected && state() != WebRtcState::Closed) close();
  });
}

WebRtc::~WebRtc() = default;

void WebRtc::connect(std::function<void(const std::string&)> done) {
  core_.loop->exclusive([&] {
    auto* peer = core_.config.webrtc.get();
    auto user = core_.realtime.user_topic();
    std::string refused;
    if (peer == nullptr) {
      refused = "no_transport";
    } else if (!core_.realtime.joined(user)) {
      refused = "not_joined";
    }
    if (!refused.empty()) {
      if (done) core_.post([done = std::move(done), refused] { done(refused); });
      return;
    }
    if (state() != WebRtcState::Closed) close();

    auto generation = ++generation_;
    connecting_ = std::move(done);
    open_.clear();
    set_state(WebRtcState::Connecting);
    connect_timer_ = core_.loop->after(core_.config.webrtc_timeout, [this, generation] {
      if (generation != generation_ || !connecting_) return;
      finish_connect("timeout");
      close();
      set_state(WebRtcState::Failed);
    });

    auto post = core_.post;
    PeerHandlers handlers;
    handlers.on_local_description = [this, post, generation](std::string sdp, std::string type) {
      post([this, generation, sdp, type] { local_description(generation, sdp, type); });
    };
    handlers.on_local_candidate = [this, post, generation](std::string candidate, std::string mid) {
      post([this, generation, candidate, mid] { local_candidate(generation, candidate, mid); });
    };
    handlers.on_state = [this, post, generation](std::string s) {
      post([this, generation, s] { peer_state(generation, s); });
    };
    handlers.on_channel_open = [this, post, generation](std::string label) {
      post([this, generation, label] { channel_opened(generation, label); });
    };
    handlers.on_channel_close = [this, post, generation](std::string label) {
      post([this, generation, label] { channel_closed(generation, label); });
    };
    handlers.on_message = [this, post, generation](std::string label, std::string data,
                                                   bool binary) {
      post([this, generation, label, data, binary] {
        message(generation, label, data, binary);
      });
    };
    peer->open(core_.config.ice_servers, core_.config.data_channels,
               protobuf(core_) ? "protobuf" : "", std::move(handlers));
  });
}

void WebRtc::close() {
  core_.loop->exclusive([&] {
    if (state() == WebRtcState::Closed) return;
    ++generation_;
    core_.loop->cancel(connect_timer_);
    connect_timer_ = 0;
    if (auto* peer = core_.config.webrtc.get()) peer->close();
    auto user = core_.realtime.user_topic();
    if (core_.realtime.joined(user)) core_.realtime.push(user, "webrtc:close", json::object());
    finish_connect("closed");
    fail_calls("closed");
    auto was_open = std::move(open_);
    open_.clear();
    for (const auto& [label, is_open] : was_open) {
      if (!is_open) continue;
      auto listeners = channel_listeners_;
      for (auto& [id, listener] : listeners) {
        if (listener) listener(label, false);
      }
    }
    set_state(WebRtcState::Closed);
  });
}

void WebRtc::local_description(std::uint64_t generation, const std::string& sdp,
                               const std::string& type) {
  if (generation != generation_) return;
  core_.realtime.push(core_.realtime.user_topic(), "webrtc:offer", {{"sdp", sdp}, {"type", type}},
                      [this, generation](const Reply& reply) {
                        if (generation != generation_ || reply.ok) return;
                        finish_connect(reply.error);
                        close();
                        set_state(WebRtcState::Failed);
                      });
}

void WebRtc::local_candidate(std::uint64_t generation, const std::string& candidate,
                             const std::string& mid) {
  if (generation != generation_) return;
  core_.realtime.push(core_.realtime.user_topic(), "webrtc:ice",
                      {{"candidate", candidate}, {"sdpMid", mid}, {"sdpMLineIndex", 0}});
}

void WebRtc::signal(const Event& event) {
  if (event.topic != core_.realtime.user_topic() || state() == WebRtcState::Closed) return;
  auto* peer = core_.config.webrtc.get();
  if (peer == nullptr) return;
  if (event.event == "webrtc:answer") {
    peer->set_remote_description(text(event.payload, "sdp"), text(event.payload, "type", "answer"));
  } else if (event.event == "webrtc:ice") {
    auto candidate = text(event.payload, "candidate");
    if (!candidate.empty()) {
      auto mid = text(event.payload, "sdpMid");
      if (mid.empty()) mid = std::to_string(number(event.payload, "sdpMLineIndex"));
      peer->add_remote_candidate(candidate, mid);
    }
  }
}

void WebRtc::peer_state(std::uint64_t generation, const std::string& peer) {
  if (generation != generation_) return;
  if (peer == "connected") {
    set_state(WebRtcState::Connected);
  } else if (peer == "failed" || peer == "closed" || peer == "disconnected") {
    finish_connect(peer);
    fail_calls(peer);
    set_state(peer == "failed" ? WebRtcState::Failed : WebRtcState::Closed);
  }
}

void WebRtc::channel_opened(std::uint64_t generation, const std::string& label) {
  if (generation != generation_) return;
  open_[label] = true;
  set_state(WebRtcState::Connected);
  finish_connect("");
  auto listeners = channel_listeners_;
  for (auto& [id, listener] : listeners) {
    if (listener) listener(label, true);
  }
}

void WebRtc::channel_closed(std::uint64_t generation, const std::string& label) {
  if (generation != generation_) return;
  open_[label] = false;
  if (label == "events") fail_calls("closed");
  auto listeners = channel_listeners_;
  for (auto& [id, listener] : listeners) {
    if (listener) listener(label, false);
  }
}

void WebRtc::message(std::uint64_t generation, const std::string& label, const std::string& data,
                     bool binary) {
  if (generation != generation_) return;
  if (label == "events" && reply(data, binary)) return;
  auto listeners = data_listeners_;
  for (auto& [id, listener] : listeners) {
    if (listener) listener(label, data, binary);
  }
}

// A hook reply on `events`, matched to its call. False for anything else.
bool WebRtc::reply(const std::string& data, bool binary) {
  std::shared_ptr<Call> call;
  HookResult result;
  if (protobuf(core_)) {
    if (!binary) return false;
    const auto* envelope = detail::proto::find("RtcEnvelope");
    auto decoded = envelope ? detail::proto::decode(*envelope, data, false) : std::nullopt;
    if (!decoded) return false;
    const json* body = nullptr;
    if (decoded->contains("hook_reply")) {
      body = &(*decoded)["hook_reply"];
      result.ok = true;
      if (body->contains("data_raw")) {
        // A typed hook's reply: the bytes as the plugin encoded them.
        result.bytes = detail::proto::unbase64(text(*body, "data_raw")).value_or(std::string());
      } else {
        result.data = field(*body, "data");
      }
    } else if (decoded->contains("hook_error")) {
      body = &(*decoded)["hook_error"];
      result.error = text(*body, "error", "hook_error");
    } else {
      return false;
    }
    auto id = static_cast<std::uint32_t>(number(*body, "id"));
    auto it = std::find_if(calls_.begin(), calls_.end(), [&](const auto& c) { return c->id == id; });
    if (it == calls_.end()) return true;
    call = *it;
    calls_.erase(it);
  } else {
    if (binary) return false;
    auto message = parse(data);
    auto type = text(message, "type");
    if (type != "hook_reply" && type != "hook_error") return false;
    auto plugin = text(message, "plugin");
    auto fn = text(message, "fn");
    auto it = std::find_if(calls_.begin(), calls_.end(),
                           [&](const auto& c) { return c->plugin == plugin && c->fn == fn; });
    if (it == calls_.end()) return true;
    call = *it;
    calls_.erase(it);
    result.ok = type == "hook_reply";
    if (result.ok) {
      result.data = field(message, "data");
    } else {
      result.error = text(message, "error", "hook_error");
    }
  }
  core_.loop->cancel(call->timer);
  if (call->done) call->done(result);
  return true;
}

void WebRtc::call_hook(std::string plugin, std::string fn, json args, HookCallback done) {
  if (!args.is_array()) args = args.is_null() ? json::array() : json::array({std::move(args)});
  start_call(std::move(plugin), std::move(fn), std::move(args), {}, false, std::move(done));
}

void WebRtc::call_hook_raw(std::string plugin, std::string fn, std::string request,
                           HookCallback done) {
  start_call(std::move(plugin), std::move(fn), json(), std::move(request), true, std::move(done));
}

void WebRtc::start_call(std::string plugin, std::string fn, json args, std::string raw,
                        bool is_raw, HookCallback done) {
  core_.loop->exclusive([&] {
    auto call = std::make_shared<Call>();
    call->plugin = plugin;
    call->fn = fn;
    call->done = std::move(done);
    std::string refused = "not_open";
    bool sent = false;
    if (is_raw && !protobuf(core_)) {
      refused = "needs_protobuf";
    } else if (auto* peer = core_.config.webrtc.get(); peer != nullptr && channel_open("events")) {
      if (protobuf(core_)) {
        call->id = next_call_++;
        json body = {{"id", call->id}, {"plugin", plugin}, {"fn", fn}};
        if (is_raw) {
          body["args_raw"] = raw;
        } else {
          body["args_json"] = dump(args);
        }
        sent = peer->send(
            "events",
            detail::proto::encode(*detail::proto::find("RtcEnvelope"), {{"call_hook", body}}),
            true);
      } else {
        json message = {{"type", "call_hook"}, {"plugin", plugin}, {"fn", fn}, {"args", args}};
        sent = peer->send("events", dump(message), false);
      }
    }
    if (!sent) {
      if (call->done) {
        core_.post([call, refused] {
          HookResult result;
          result.error = refused;
          call->done(result);
        });
      }
      return;
    }
    call->timer = core_.loop->after(core_.config.push_timeout, [this, call] {
      auto it = std::find(calls_.begin(), calls_.end(), call);
      if (it == calls_.end()) return;
      calls_.erase(it);
      HookResult result;
      result.error = "timeout";
      if (call->done) call->done(result);
    });
    calls_.push_back(call);
  });
}

bool WebRtc::channel_open(const std::string& label) const {
  return core_.loop->exclusive([&] {
    auto it = open_.find(label);
    return it != open_.end() && it->second;
  });
}

bool WebRtc::send(const std::string& label, const std::string& data, bool binary) {
  return core_.loop->exclusive([&] {
    auto* peer = core_.config.webrtc.get();
    return peer != nullptr && channel_open(label) && peer->send(label, data, binary);
  });
}

void WebRtc::finish_connect(const std::string& error) {
  core_.loop->cancel(connect_timer_);
  connect_timer_ = 0;
  auto done = std::move(connecting_);
  connecting_ = {};
  if (done) done(error);
}

void WebRtc::fail_calls(const std::string& error) {
  auto calls = std::move(calls_);
  calls_.clear();
  for (auto& call : calls) {
    core_.loop->cancel(call->timer);
    HookResult result;
    result.error = error;
    if (call->done) call->done(result);
  }
}

void WebRtc::set_state(WebRtcState state) {
  if (state_.exchange(state) == state) return;
  auto listeners = state_listeners_;
  for (auto& [id, listener] : listeners) {
    if (listener) listener(state);
  }
}

std::uint64_t WebRtc::on_data(
    std::function<void(const std::string&, const std::string&, bool)> listener) {
  return core_.loop->exclusive([&] {
    auto id = next_listener_++;
    data_listeners_.emplace(id, std::move(listener));
    return id;
  });
}

std::uint64_t WebRtc::on_state(std::function<void(WebRtcState)> listener) {
  return core_.loop->exclusive([&] {
    auto id = next_listener_++;
    state_listeners_.emplace(id, std::move(listener));
    return id;
  });
}

std::uint64_t WebRtc::on_channel(std::function<void(const std::string&, bool)> listener) {
  return core_.loop->exclusive([&] {
    auto id = next_listener_++;
    channel_listeners_.emplace(id, std::move(listener));
    return id;
  });
}

void WebRtc::off(std::uint64_t id) {
  core_.loop->exclusive([&] {
    data_listeners_.erase(id);
    state_listeners_.erase(id);
    channel_listeners_.erase(id);
  });
}

}  // namespace gamend
