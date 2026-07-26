---
icon: hero-video-camera
---

# WebRTC DataChannels

WebRTC DataChannel support provides low-latency, optionally unreliable data transport alongside the existing WebSocket. The server acts as a WebRTC peer (not peer-to-peer between clients). Both transports coexist — WebSocket handles signaling, notifications, and chat while WebRTC handles high-frequency game data.

**Rust required:** ex_sctp compiles a Rust NIF, so a Rust toolchain is required. Local dev needs rustup installed. Docker/CI images must include the Rust toolchain.

## Architecture overview

```text
Client                           Server (ex_webrtc)
  │                                    │
  │── WS connect (JWT auth) ──────────>│  existing flow
  │── WS join "user:<id>"  ───────────>│  existing flow
  │                                    │
  │── WS push "webrtc:offer"  ────────>│  Server creates PeerConnection
  │<── WS push "webrtc:answer"  ───────│  Server sends SDP answer
  │── WS push "webrtc:ice"  ──────────>│  ICE candidate exchange
  │<── WS push "webrtc:ice"  ──────────│  ICE candidate exchange
  │                                    │
  │══ DataChannel "events"  ═══════════│  reliable, ordered
  │══ DataChannel "state"  ════════════│  unreliable, unordered
  │                                    │
  │── WS still open  ─────────────────>│  notifications, chat, etc.
```

## Key design decisions

- **Signaling over existing UserChannel** — No new channel needed. SDP/ICE exchange happens via the already-authenticated WebSocket.
- **Auth inherited from WebSocket** — The PeerConnection is created inside the authenticated channel process. No separate WebRTC auth.
- **One PeerConnection per user** — Spawned on first "webrtc:offer". Linked to the channel process (auto-terminates when WS disconnects).
- **WebSocket stays open** — Both transports coexist. Client chooses which to use for game data.

## Setup

Dependencies are included in mix.exs:

```text
# In apps/game_server_web/mix.exs
{:ex_webrtc, "~> 0.16.0"},
{:ex_sctp, "~> 0.1.2"}   # Requires Rust toolchain
```

Configure ICE servers in the root host config under config/:

```text
config :game_server_web, :webrtc,
  enabled: true,
  ice_servers: [%{urls: "stun:stun.l.google.com:19302"}]

  # Optional TURN for restrictive NATs:
  # ice_servers: [
  #   %{urls: "stun:stun.l.google.com:19302"},
  #   %{urls: "turn:your-server:3478", username: "u", credential: "p"}
  # ]
```

## DataChannel strategy

| Channel label | Ordered | Reliable | Use case |
|---|---|---|---|
| `"events"` | Yes | Yes | Important game events (scores, spawns, deaths) |
| `"state"` | No | No | High-frequency state sync (positions, rotations) |

## RPC format: JSON (default) or Protobuf

Hook RPC on the "events" DataChannel speaks JSON by default. A channel opts into protobuf by setting the standard DataChannel protocol field when it is created — the server reads the negotiated protocol per channel, so JSON and protobuf channels can coexist on the same peer. The envelope is defined in proto/gamend_realtime.proto (RtcEnvelope).

```javascript
// JavaScript SDK — negotiates protocol: "protobuf" on the DataChannels
const webrtc = new GameWebRTC(userChannel, { format: 'protobuf' })
await webrtc.connect()
const result = await webrtc.callHook('my_plugin', 'my_func', [1, 2])

# Godot SDK
var webrtc = GamendWebRTC.new(user_channel, format": "protobuf)
webrtc.connect_webrtc()
var result = await webrtc.call_hook("my_plugin", "my_func", [1, 2])
```

- **Request ids** — protobuf RPC calls carry an id echoed in the reply, so concurrent calls — including to the same function — are correlated safely. The JSON protocol, which is the default, matches replies by plugin+fn instead, so concurrent calls to the same function must be serialized by the caller.
- **Wire size** — DataChannels have no compression, so protobuf's smaller payloads (35–84% below JSON in the encoding benchmark) are realized in full on this transport.
- **Custom game data** — the "state" channel remains an opaque byte pipe in both modes; send whatever encoding your game defines.

**Which to choose:** prefer protobuf for WebRTC — unlike the WebSocket there is no compression here, and the request-id correlation makes concurrent hook calls safe. Use JSON only when wire debuggability matters more than bandwidth or when a client platform lacks protobuf support.

### Typed hooks (game-defined schemas)

Define request/reply messages in your plugin's proto file using the
`<FnName>Request` / `<FnName>Reply` convention (`hello_proto` gives
`HelloProtoRequest` / `HelloProtoReply`); the pair registers the hook's schema
when the plugin loads.

The plugin function receives the decoded request struct and returns a reply
struct, and the server converts at the boundary. One hook is therefore callable
from every transport and format:

- binary protobuf on protobuf DataChannels (`callHookRaw` / `call_hook_raw`)
- plain JSON objects on JSON DataChannels and the WebSocket `call_hook`
- the admin hook tester

Clients can switch format at runtime without touching call sites. Binary calls
need the schema; without one the call falls back to JSON.

```elixir
# Plugin (Elixir) — bundles its own generated modules;
# receives the decoded request, returns the reply struct.
def hello_proto(%MyGame.V1.HelloProtoRequest{} = req) do
  %MyGame.V1.HelloProtoReply{greeting: "Hello, #{req.name}!"}
end

// JavaScript client
const req = HelloProtoRequest.encode({ name: 'gamend' }).finish()
const reply = HelloProtoReply.decode(await webrtc.callHookRaw('my_game', 'hello_proto', req))

# Godot client
var req = MyGamePb.HelloProtoRequest.new()
req.set_name("gamend")
var result = await webrtc.call_hook_raw("my_game", "hello_proto", req.to_bytes())
var reply = MyGamePb.HelloProtoReply.new()
reply.from_bytes(result.data)
```

### Regenerating client bindings

Whenever a proto file changes — the built-in realtime schema on upgrade, or your own game schema — regenerate the bindings and ship them with the game. One mix task drives all three generators, and the server is compiled from the same file, so everything stays in lock-step:

```bash
# One task, every target — ships with game_server_core,
# so downstream games can run it too.
mix host.proto.gen                    # every .proto it discovers
mix host.proto.gen my_game.proto      # just this one

# Restrict targets, or override an output path:
mix host.proto.gen --only elixir,js my_game.proto
mix host.proto.gen --godot-out godot/my_game_pb.gd my_game.proto

# Elixir needs protoc + protoc-gen-elixir; JS needs npx; Godot needs
# GODOT_BIN and GODOBUF_DIR. Missing toolchains are skipped, not fatal.
```

## Signaling events

| Direction | Event | Payload |
|---|---|---|
| Client → Server | `"webrtc:offer"` | sdp": "...", "type": "offer |
| Server → Client | `"webrtc:answer"` | sdp": "...", "type": "answer |
| Both | `"webrtc:ice"` | candidate": "...", "sdpMid": "...", "sdpMLineIndex": 0} |
| Client → Server | `"webrtc:send"` | {"channel": "events", "data": "... |
| Server → Client | `"webrtc:data"` | channel": "events", "data": "... |
| Client → Server | `"webrtc:close"` | {} |
| Server → Client | `"webrtc:state"` | state": "connected\|failed\|closed |
| Server → Client | `"webrtc:channel_open"` | channel": "events |
| Server → Client | `"webrtc:channel_closed"` | {} |

## Hook RPC over the events channel

Messages sent on the "events" DataChannel with a call_hook type invoke server-side plugin hooks, avoiding an HTTP round-trip. The reply arrives on the same channel:

```text
# Client → Server (on the "events" DataChannel)
type": "call_hook", "plugin": "my_plugin", "fn": "my_func", "args": [1, 2]} # Server → Client {"type": "hook_reply", "plugin": "my_plugin", "fn": "my_func", "data": ...} # or, on failure (including results that are not JSON-encodable) {"type": "hook_error", "plugin": "my_plugin", "fn": "my_func", "error": "reason
```

## JavaScript client

Import GameWebRTC from assets/js/webrtc.js:

```javascript
import { GameWebRTC } from "./webrtc"
import { _ensureSocket } from "./lobbies"

const socket = _ensureSocket()
const userChannel = socket.channel("user:123", {token: myToken})
userChannel.join()

const webrtc = new GameWebRTC(userChannel, {
  dataChannels: [
    { label: "events", ordered: true },
    { label: "state",  ordered: false, maxRetransmits: 0 },
  ],
  onData: (label, data) => {
    console.log(`Received on ${label}:`, data)
  },
  onChannelOpen: (label) => console.log(`Channel ${label} open`),
  onStateChange: (state) => console.log(`WebRTC state: ${state}`),
})

await webrtc.connect()
webrtc.send("events", JSON.stringify({ type: "move", x: 10, y: 20 }))
webrtc.close()
```

## Godot client

Use GamendWebRTC.gd from the gamend_template:

```gdscript
var realtime := GamendRealtime.new(token)
var user_channel := realtime.add_channel("user:%s" % user_id)  # ids are UUID strings
# wait for join...

var webrtc := GamendWebRTC.new(user_channel, {
    "enable_logs": true
})
add_child(webrtc)
webrtc.data_received.connect(_on_data)
webrtc.connected.connect(_on_connected)
webrtc.connect_webrtc()

func _on_data(label: String, data: PackedByteArray):
    print("Recv on %s: %s" % [label, data.get_string_from_utf8()])

func _on_connected():
    webrtc.send_text("events", '{"type":"move","x":10,"y":20}')
```

## Server-side components

- **WebRTCPeer** — GenServer managing ExWebRTC.PeerConnection per user. Handles SDP negotiation, ICE exchange, and DataChannel lifecycle.
- **UserChannel** — Extended with WebRTC signaling handlers. Handles webrtc:offer, webrtc:ice, webrtc:send, and webrtc:close events.

## Deployment

- Docker: Add Rust toolchain to Dockerfile (ex_sctp compiles a Rust NIF).
- Server needs UDP ports accessible for WebRTC media/data transport.
- Fly.io: ex_webrtc includes ExWebRTC.ICE.FlyIpFilter for correct public IP binding.
- TURN server recommended for clients behind restrictive NATs/firewalls.

## Disabling WebRTC at runtime

Set enabled: false in config to reject offers at runtime. The server will continue to work normally with WebSocket only.
