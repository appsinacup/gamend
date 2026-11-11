# Gamend Rust SDK

A Rust client for [Gamend](https://gamend.org): every player-facing REST
operation, typed models, sign-in and a session that stays fresh, the realtime
connection with server hooks, live key-value rows and presence, protobuf events,
and WebRTC DataChannels, over transports you choose. It builds on stable Rust and
serves Bevy, Fyrox, macroquad and tools.

This directory is generated: `src/generated/*.rs` and `REFERENCE.md` by
`clients/sdkgen` from the OpenAPI document, `clients/events.json`,
`clients/commands.json` and `proto/gamend_realtime.proto`; the rest is copied
from `clients/rust_template/`. Edit those, not this, and run
`clients/generate_rust.sh`. A game never holds an admin token, so the admin API
is left out; `client.rest().send` reaches it for a tool that needs it.

## Add it

```toml
[dependencies]
gamend = "1"                        # from crates.io
# gamend = { path = "rust_sdk" }    # or from the release's tarball
```

The one dependency of the core is `serde_json`. The default feature `native` adds
`ureq` for HTTP, `tungstenite` with rustls for the socket, and the default clock.
Every network library sits behind a trait in `transport.rs`: `HttpTransport`,
`WebSocketTransport` and `PeerTransport`. An engine with its own stack, or a
target with no threads, turns `native` off (`default-features = false`),
implements those and sets `Config::clock`. No peer connection ships yet; `WebRtc`
runs over one you bring.

## Use it

```rust
use gamend::{events, json, models, Client, Config};

let client = Client::new(Config::native("https://game.example.com"));

let signed_in = client.auth().login_device("device-123");
let mut joined = None;

// Once per frame:
client.poll();
if let Some(result) = signed_in.try_take() {
    if result.ok {
        client.realtime().connect(); // joins user:<id> itself
        joined = Some(client.api().lobbies_quick_join(json!({ "title": "duel", "max_users": 2 })));
    }
}
if let Some(reply) = joined.as_ref().and_then(|ticket| ticket.try_take()) {
    if let Some(lobby) = reply.as_model::<models::Lobby>() {
        client.realtime().join_lobby(&lobby.id);
    }
}
for event in client.drain_events() {
    if event.kind == events::LOBBY_UPDATED {
        refresh_lobby(&event.payload);
    }
}
```

**Everything completes in `poll()`.** Every call answers a `Ticket<T>`: read it
with `try_take()` or `is_ready()`, or `.await` it, since it is a `Future`. The
answer never arrives inside the call that started it. Transports may finish on
any thread and hand their results to an inbox; `poll()` runs them on the thread
that calls it, in the order they arrived, then the timers that are due (token
refresh, sign-in polling, heartbeats, reconnects). Dropping a ticket does not
cancel the call.

**News is drained, not delivered.** No callback captures your game state, so a
Bevy system or a macroquad loop reads with `&mut` access to its world.
`client.drain_events()` (or `client.realtime().events()`) hands back what arrived
since the last call. The same goes for `realtime().state_changes()`,
`auth().session_changes()`, `kv().changes()`, `presence().user_changes()` and
`lobby_changes()`, and `webrtc().data()`, `state_changes()` and
`channel_changes()`. Each holds up to `Config::queue_limit` entries; past that
the oldest goes first.

`Client` is `Send + Sync` with `&self` methods, so it can be a Bevy `Resource`,
and clones share one connection.

## REST

**Every method is one operation**, named as the Godot SDK names it: the path's
parameters as `&str`, then `body: Value`, then `options: Value` for the query.
Where every query key is optional the plain name leaves `options` out and
`<name>_with` takes it. `REFERENCE.md` lists them by tag and
`src/generated/api.rs` lists each one's fields. A missing required field or empty
path parameter is not sent: the ticket gets ``<name> needs `<field>` ``.

**A `Response`** is the `status`, the decoded `body`, the raw `bytes` and an
`error` that is empty on success. Gamend answers one of four shapes, and the
accessors read them: `data()`, `meta()` for a page, `code()` and `message()` for
an error, `errors()` for `validation_failed`.

**Typed models.** `gamend::models` has a struct for every schema the API answers
with. `r.as_model::<models::Lobby>()` reads `data()`,
`r.page::<models::Lobby>()` a page with its `meta`, and
`r.as_model::<Vec<String>>()` a list. Reads are lenient: a field that is missing
or mistyped keeps its default, a nullable value is an `Option`, a map a `HashMap`,
and a free-form object stays a `Value`. A field named after a keyword takes a
trailing underscore (`type_`). `Model::write` turns a model back into JSON.

**Reading JSON.** `gamend::json::text(&value, "key")`, `number` and `field` cannot
fail where `value["key"].as_str().unwrap()` can.

## Sessions

`auth()` signs in and keeps the session: `login_device`, `login_email`,
`login_steam` (a `GetAuthTicketForWebApi` ticket), and `sign_in(provider)`, which
opens the provider's page through `Config::open_url` and polls until the player
finishes. Every call after that carries the access token. It is refreshed when
three quarters of its 15 minutes have passed, and once more on a `401`; a refresh
the server refuses signs out.

Signing in never links: `link(provider)` and `link_steam(ticket)` add a provider
to the signed-in account. Registering is not a sign-in either, and takes no
password: `register_email(email)` makes the account, and
`confirm_registration(email, code, password)` takes the emailed code, sets the
password and signs in.

Keep the session between runs where your platform keeps secrets:

```rust
for change in client.auth().session_changes() {
    match change {
        Some(session) => secure_store::write("gamend", &session.to_json().to_string()),
        None => secure_store::erase("gamend"),
    }
}

let kept = gamend::json::parse(secure_store::read("gamend").as_bytes())
    .and_then(|value| gamend::Session::from_json(&value, 0));
if let Some(kept) = kept {
    client.auth().restore(kept); // refreshed on the next poll if it lapsed
}
```

## Realtime

`realtime().connect()` opens the Phoenix socket (`vsn=2.0.0`) as the signed-in
player and joins `user:<id>`. `join(topic, params)` (and `join_lobby`,
`join_lobbies`, `join_group`, `join_groups`, `join_party`) joins now or as soon as
the socket opens; `push(topic, event, payload)` answers the server's reply or
`timeout`; `call_hook(plugin, fn, args)` calls a server hook over the user
channel. `gamend::commands` has a function for each event a channel answers.

A dropped connection reconnects on its own, backing off (0.1 s, 0.5 s, 1 s, 2 s,
5 s, then every 10 s: `Config::reconnect_delays`), refreshing the token first when
the last attempt never opened, and rejoins every topic it had, in order. A missed
heartbeat counts as a drop. A channel the server errors is joined again after a
second; one it closes (a kick) is not. A join refused as `unauthorized`,
`forbidden` or `not_found` is dropped. Signing out disconnects.

Events arrive named: `Event::kind` is one of `gamend::events`, or `events::MESSAGE`
for one the table does not name.

**Protobuf.** `Config::realtime_format = RealtimeFormat::Protobuf` asks the server
for binary frames; they are decoded before `events()`, into the same payload as
JSON mode except that timestamps are unix milliseconds (`*_ms`). No protobuf
library is involved. Metadata or KV data the game plugin sends in its own schema
is read by the decoder you register: `register_metadata_decoder("lobby", fn)`,
`register_kv_decoder("match:*", fn)`. Unread, it stays base64. A decoder must not
call the client.

## Live rows and presence

`kv().subscribe(KvKey::of_user("progress", user_id))` subscribes to a key-value
row over the socket, again after every rejoin; `kv().row(key)` is the latest value
from subscribe replies, pushes and `kv().fetch(key, false)` (REST, cache first).

`presence()` keeps merged user profiles, lobbies and online state from the
realtime events: `user(id)`, `lobby(id)`, `online(id)`, `last_seen(id)`. Metadata
merges one section deep, so a sparse update never wipes the rest; the player's own
push replaces theirs whole.

## WebRTC

With `Config::webrtc` set and the realtime connection up, `webrtc().connect()`
opens a DataChannel to the server, signaled over the user channel.
`webrtc().call_hook` calls hooks over it, as JSON messages or, with
`Config::webrtc_format` set to protobuf, envelopes with request ids, where
`call_hook_raw` sends a typed hook the game's own encoded request and hands back
the reply's bytes. `send` and `data()` carry the game's own messages. Losing the
socket closes it.

## Test with it

`gamend::testing` has `FakeHttp`, `FakeWebSocket`, `FakePeer` and `FakeClock`:
answer requests, play the server's frames, drive the peer and move time by hand,
then `poll()`.

```sh
cargo build --all-targets
cargo test
cargo run --example conformance -- http://127.0.0.1:4000             # live, JSON
cargo run --example conformance -- http://127.0.0.1:4000 --protobuf  # live, protobuf
```

The conformance program runs the scenario every Gamend SDK passes: sign in,
`/me`, refresh, connect and join, a lobby and its update, a hook and a failing
one, a KV subscription hearing a write, a dropped socket reconnecting and
rejoining, and a clean disconnect. The KV step writes as an admin: set
`GAMEND_ADMIN_EMAIL` and `GAMEND_ADMIN_PASSWORD`, or it is skipped. The hooks need
the example plugins (`GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples`).

MIT, as Gamend is.
