---
icon: hero-wrench-screwdriver-solid
---

# Rust Client SDK

[Download](https://github.com/appsinacup/gamend/releases/download/latest/gamend-rust-sdk.tar.gz) ·
[View the source](https://github.com/appsinacup/gamend/tree/main/clients/rust_template)

A crate for Bevy, Fyrox, macroquad and Rust tools, on stable Rust. Every
player-facing operation is a method, generated from the same OpenAPI document as
the other SDKs and named as the Godot SDK names it.

## Add it

From [crates.io](https://crates.io/crates/gamend):

```bash
cargo add gamend
```

Or unpack the download beside your project and use
`gamend = { path = "rust_sdk" }`. Every change to Gamend publishes both, at the
same version.

The default `native` feature brings `ureq` and `tungstenite` with rustls. With
`default-features = false` the core has no threads and builds for wasm32: bring
your own `HttpTransport` and `WebSocketTransport`, and set `Config::clock`.

## Connect and sign in

```rust
use gamend::{events, json, models, Client, Config};

let client = Client::new(Config::native("https://game.example.com"));
let signed_in = client.auth().login_device("device-123");

// Once per frame:
client.poll();
if let Some(result) = signed_in.try_take() {
    if result.ok {
        client.realtime().connect();
    }
}
```

A call answers a `Ticket`, completed in `poll()`. Read it with `try_take()`, or
`.await` it, since it is a `Future`. `Client` is `Send + Sync`, so it can be a
Bevy `Resource`.

## Calls and replies

```rust
let joined = client.api().lobbies_quick_join(json!({ "title": "duel", "max_users": 2 }));

// Later, after a poll:
if let Some(reply) = joined.try_take() {
    if let Some(lobby) = reply.as_model::<models::Lobby>() {
        client.realtime().join_lobby(&lobby.id);
    }
}
```

A method takes the path's parameters, then the body. Where every query key is
optional, `<name>_with` also takes them. A missing required field is not sent:
the reply's `error` names it. The admin API is left out, since a game never holds
an admin token.

## Realtime

Nothing calls back into your game. Each frame, read what arrived:

```rust
for event in client.drain_events() {
    if event.kind == events::LOBBY_UPDATED {
        refresh_lobby(&event.payload);
    }
}
```

A dropped connection reconnects, refreshes its token and rejoins its topics. The
`commands` module has a function for each event a channel answers. Live key-value
rows are `client.kv()`, merged profiles and online state `client.presence()`, each
with its own changes to drain.

## WebRTC

`client.webrtc()` runs the server's DataChannels over any `PeerTransport`. None
ships yet, so bring one that wraps your engine's WebRTC library.
