---
icon: hero-video-camera
---

# WebRTC

Two independent features; pick by where the game simulation runs. A game can use
either, both, or neither.

| | **Server as peer** | **Peer-to-peer signaling** |
|---|---|---|
| Who talks to whom | Client ⇄ server | Client ⇄ client |
| The server is | A WebRTC peer terminating DataChannels | An SDP/ICE relay; no media path |
| Room identity | The user (`user:<id>` channel) | A **lobby** (`signaling:<lobby_id>` channel) |
| Use it for | Low-latency hook RPC and state to an authoritative server | Player-hosted matches, voice, direct state exchange |
| Client SDK | `GameWebRTC` (JS) / `GamendWebRTC` (Godot) | `GamendSignalingClient` (Godot); JS joins the channel directly |
| Rust toolchain | Required (`ex_sctp` NIF), locally and in Docker/CI | Not needed |

## Server as peer

SDP/ICE is exchanged over the already-authenticated `user:<id>` channel, so
there is no separate WebRTC auth. One PeerConnection per user, spawned on the
first `webrtc:offer` and linked to the channel process, so it dies with the
WebSocket. Both transports coexist: WS keeps notifications and chat, WebRTC
carries high-frequency game data.

```text
Client                           Server (ex_webrtc)
  │── WS push "webrtc:offer"  ────────>│  creates PeerConnection
  │<── WS push "webrtc:answer" ────────│
  │<─► WS push "webrtc:ice"   ────────►│  ICE exchange
  │══ DataChannel "events" ════════════│  reliable, ordered
  │══ DataChannel "state"  ════════════│  unreliable, unordered
```

| Channel label | Ordered | Reliable | Use case |
|---|---|---|---|
| `"events"` | Yes | Yes | Game events, hook RPC |
| `"state"` | No | No | High-frequency state (positions) |

The server peer's ICE servers are settings: `GAMEND_WEBRTC_STUN_URLS` (default Google's public STUN server) and, for a server behind NAT or on a network that filters UDP, a TURN relay with `GAMEND_WEBRTC_TURN_URLS`, `GAMEND_WEBRTC_TURN_USERNAME` and `GAMEND_WEBRTC_TURN_CREDENTIAL`. The URL settings take comma-separated lists. These are the server's own servers; a client passes its own to its peer connection. `enabled: false` in the host config rejects offers at runtime, and an `ice_servers:` list there replaces the settings outright:

```text
config :gamend_web, :webrtc,
  enabled: true,
  ice_servers: [%{urls: "stun:stun.l.google.com:19302"}]
```

### UserChannel signaling events

| Direction | Event | Payload |
|---|---|---|
| C → S | `webrtc:offer` / S → C `webrtc:answer` | `{sdp, type}` |
| Both | `webrtc:ice` | `{candidate, sdpMid, sdpMLineIndex}` |
| C → S | `webrtc:close` | `{}` |
| S → C | `webrtc:state`, `webrtc:channel_open`, `webrtc:channel_closed` | `{state}`, `{channel}`, `{}` |

There is no send or data event on the channel: game data goes over the
DataChannels only.

### Hook RPC

Messages on `"events"` with `{"type": "call_hook", "plugin": ..., "fn": ..., "args": [...]}`
invoke plugin hooks without an HTTP round-trip; the reply (`hook_reply` /
`hook_error`) arrives on the same channel. The `"state"` channel stays an opaque
byte pipe. A connection holds up to four channels; the server refuses more.

JSON is the default; a channel opts into protobuf via the DataChannel protocol
field (envelope: `RtcEnvelope` in `proto/gamend_realtime.proto`). **Prefer
protobuf here**: DataChannels have no compression, and protobuf calls carry a
request id so concurrent calls to the same function are correlated safely, where
JSON matches replies by plugin+fn and needs caller-side serialization.

Typed hooks: define `<FnName>Request` / `<FnName>Reply` protobuf messages in
your plugin's proto and the pair registers automatically; the plugin function
receives the decoded struct and returns a reply struct, callable from every
transport (`callHookRaw` / `call_hook_raw` for binary). Regenerate bindings for
all targets with `mix host.proto.gen`.

### Clients

```javascript
const webrtc = new GameWebRTC(userChannel, { format: 'protobuf' })
await webrtc.connect()
webrtc.send("events", JSON.stringify({ type: "move", x: 10 }))
const result = await webrtc.callHook('my_plugin', 'my_func', [1, 2])
```

```gdscript
var webrtc := GamendWebRTC.new(user_channel, {})
add_child(webrtc)
webrtc.connect_webrtc()
var result = await webrtc.call_hook("my_plugin", "my_func", [1, 2])
```

```cpp
// Built with GAMEND_WITH_WEBRTC; the realtime connection is up.
config.webrtc = gamend::make_libdatachannel_transport();
config.webrtc_format = gamend::RealtimeFormat::Protobuf;
// ...
client.webrtc().connect([&](const std::string& error) {
  if (!error.empty()) return;
  client.webrtc().send("events", R"({"type":"move","x":10})");
  client.webrtc().call_hook("my_plugin", "my_func", gamend::json::array({1, 2}),
    [](const gamend::HookResult& r) { if (r.ok) use(r.data); });
});
```

The C++ SDK opens only `events` by default; `Config::data_channels` adds
more, up to the server's four.

Deployment: Rust toolchain in the image, UDP ports open, TURN recommended.
The peer connection gets only `ice_servers`; no ICE IP filter is wired (for
example Fly.io's `ExWebRTC.ICE.FlyIpFilter`).

## Peer-to-peer signaling

The server relays SDP/ICE between clients and enforces who may talk to whom;
media and game data never touch it. **A room is a lobby**, with the same id and no room
record or process. Configuration lives in the lobby's server-owned `webrtc_*`
columns, membership in presence, relay over PubSub; all cluster-wide, so peers
on different nodes signal fine.

Configure through `Gamend.Signaling.configure/2`, the only writer of those
server-owned columns; the star host defaults to `lobby.host_id`:

```elixir
Gamend.Signaling.configure(lobby, enabled: true, topology: :star)
# options: :enabled (false), :topology (:star | :mesh), :host_id (lobby host),
#          :late_join (true), :reconnect_timeout (30_000 ms)
```

`:host_id` pins the star host to someone else, a headless server process that
hosts the match without being a lobby member. It grants that user the `:host`
role on join, so it is server-side only and never reachable from a client
`PATCH`; an unknown id returns `{:error, :host_not_found}`.

| Topology | Rule |
|---|---|
| `:mesh` | Any peer may signal any other |
| `:star` | Every exchange involves the host; only the host may broadcast |

Roles (`:host` / `:user`) are assigned by the server in the join reply and
recomputed from the lobby on every read, so a host change applies immediately.

### Channel events on topic `signaling:<lobby_id>`

| Direction | Event | Payload |
|---|---|---|
| C → S | `offer` / `answer` / `ice` | `{target, sdp}` / `{target, candidate}` |
| C → S | `broadcast_offer` | `{sdp}` — star host only |
| C → S | `list_users` | `{}` |
| S → C | `offer` / `answer` / `ice` | `{sdp \| candidate, from_user_id}` |
| S → C | `user_joined` / `user_rejoined` | `{user_id, role}` |
| S → C | `user_left` | `{user_id}` |
| S → C | `room_closed` | `{}` |

On join the server pushes one `user_joined` per peer already connected. Rate
limits per user: 300 msgs / 10 s overall, plus a separate 150 / 30 s budget for
ICE so candidate bursts cannot starve offers. `webrtc:*` and signaling events
stay JSON even on protobuf sockets.

In Godot, `GamendSignalingClient` owns the peer connections and leaves the
topology to you: connect on `peer_joined` for mesh, or only to the host's
user_id for star. Pass `user_id`: it is what resolves simultaneous offers.

```gdscript
var p2p := GamendSignalingClient.new(signaling_channel, {"user_id": my_user_id})
p2p.peer_joined.connect(func(user_id, _role): p2p.connect_to_peer(user_id))
p2p.data_received.connect(_on_data_received)
add_child(p2p)

p2p.broadcast_text("events", "hello")
```

The bundled `webrtc_lobby_hook` plugin enables mesh signaling on every new
lobby and closes the room when the lobby is deleted. If you switch a lobby to
star yourself, it also pushes `webrtc:room_ready` (with the topic to join) to
the new host's `user:<id>` channel when the lobby host changes, so a headless
host connects on its own. Drop it to call `Signaling.configure/2` yourself,
e.g. star rooms, or signaling only once a match starts.
