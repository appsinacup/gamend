//! The conformance scenario (docs/specs/client-sdks.md), live:
//!
//!   cargo run --example conformance -- http://127.0.0.1:4000 [--protobuf]
//!
//! 1. `POST /login/device` answers a session; `GET /me` works with its token.
//! 2. `POST /refresh` answers a new token, and the next call carries it.
//! 3. The socket connects (`vsn=2.0.0`) and joins `user:<id>`.
//! 4. A lobby is created, `lobby:<id>` joined, and an update arrives as
//!    `updated`.
//! 5. A server hook answers; a hook that does not exist answers its error.
//! 6. A KV subscription hears a write made through the API.
//! 7. A dropped socket reconnects, rejoins its topics, and events resume.
//! 8. Leaving the lobby and disconnecting end cleanly.
//!
//! The server needs device sign-in (its default) and the example plugins
//! (`GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples`). Step 6 writes as an
//! admin: set GAMEND_ADMIN_EMAIL and GAMEND_ADMIN_PASSWORD, or it is skipped.
//! Exits non-zero on the first step that fails.

use std::cell::RefCell;
use std::process::ExitCode;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use gamend::json::{dump, number, text};
use gamend::{
    events, json, models, Body, Client, Config, Event, HttpDone, HttpRequest, HttpTransport,
    RealtimeFormat, RealtimeState, Ticket, TungsteniteTransport, UreqTransport, WebSocketHandlers,
    WebSocketTransport,
};

// The HTTP transport, noting which token each call carried.
struct Recording {
    inner: UreqTransport,
    authorization: Mutex<String>,
}

impl HttpTransport for Recording {
    fn send(&self, request: HttpRequest, done: HttpDone) {
        *self.authorization.lock().unwrap() = request
            .header("authorization")
            .unwrap_or_default()
            .to_string();
        self.inner.send(request, done);
    }
}

impl Recording {
    fn last_authorization(&self) -> String {
        self.authorization.lock().unwrap().clone()
    }
}

// The WebSocket transport, with a way to pull the plug the way a network does:
// the client is told the connection died, not that it closed it.
struct Droppable {
    inner: TungsteniteTransport,
    handlers: Mutex<Option<WebSocketHandlers>>,
}

impl WebSocketTransport for Droppable {
    fn open(&self, url: &str, handlers: WebSocketHandlers) {
        *self.handlers.lock().unwrap() = Some(handlers.clone());
        self.inner.open(url, handlers);
    }

    fn send_text(&self, frame: String) {
        self.inner.send_text(frame);
    }

    fn close(&self) {
        self.inner.close();
    }
}

impl Droppable {
    fn drop_connection(&self) {
        let handlers = self.handlers.lock().unwrap().clone();
        self.inner.close();
        if let Some(handlers) = handlers {
            handlers.on_close(1006, "dropped by the conformance run".to_string());
        }
    }
}

struct Failed {
    step: String,
    why: String,
}

fn failed<T>(step: &str, why: impl Into<String>) -> Result<T, Failed> {
    Err(Failed {
        step: step.to_string(),
        why: why.into(),
    })
}

fn ok(line: &str) {
    println!("ok   {line}");
}

// A client polled as a game would, keeping what it drains.
struct Game {
    client: Client,
    events: RefCell<Vec<Event>>,
    states: RefCell<Vec<RealtimeState>>,
}

impl Game {
    fn new(client: Client) -> Self {
        Self {
            client,
            events: RefCell::new(Vec::new()),
            states: RefCell::new(Vec::new()),
        }
    }

    fn poll(&self) {
        self.client.poll();
        self.events.borrow_mut().extend(self.client.drain_events());
        self.states
            .borrow_mut()
            .extend(self.client.realtime().state_changes());
    }

    // Poll once a frame until `done()` or `seconds`.
    fn wait(&self, done: impl Fn() -> bool, seconds: u64) -> bool {
        let deadline = Instant::now() + Duration::from_secs(seconds);
        while !done() && Instant::now() < deadline {
            self.poll();
            thread::sleep(Duration::from_millis(16));
        }
        done()
    }

    // Wait for one call's answer.
    fn call<T>(&self, ticket: Ticket<T>, step: &str) -> Result<T, Failed> {
        self.wait(|| ticket.is_ready(), 10);
        match ticket.try_take() {
            Some(value) => Ok(value),
            None => failed(step, "no answer"),
        }
    }

    // With --protobuf, an event only counts when it came as a decoded binary
    // frame: proof the server honoured the format, not that it was asked.
    fn saw(&self, kind: &str, topic: &str, protobuf: bool) -> bool {
        self.events.borrow().iter().any(|event| {
            event.kind == kind
                && event.topic == topic
                && event.binary == protobuf
                && !event.payload.is_null()
        })
    }
}

fn kv_step(game: &Game, url: &str, email: &str, password: &str) -> Result<(), Failed> {
    let client = &game.client;
    let key = format!("rust_conformance_{}", client.run_id());
    let subscribed = game.call(client.kv().subscribe(key.as_str()), "6 kv subscribe")?;
    if !subscribed.ok {
        return failed("6 kv subscribe", subscribed.error);
    }

    let admin = Game::new(Client::new(Config::native(url)));
    let login = admin.call(
        admin.client.auth().login_email(email, password),
        "6 admin login",
    )?;
    if !login.ok {
        return failed("6 admin login", login.error);
    }
    // A game SDK ships no admin API, so this goes through `Rest`.
    let body = json!({ "key": key, "data": { "score": 42 } });
    let written = admin.call(
        admin
            .client
            .rest()
            .send("PUT", "/api/v1/admin/kv", Body::of(body)),
        "6 kv write",
    )?;
    if !written.ok() {
        return failed("6 kv write", written.error);
    }
    let heard = game.wait(
        || {
            client
                .kv()
                .row(key.as_str())
                .is_some_and(|row| row.exists && number(&row.data, "score") == 42)
        },
        10,
    );
    if !heard {
        return failed("6 kv_updated", "the write never arrived");
    }
    ok(&format!("6 kv subscribe heard the admin write to {key}"));
    admin.client.rest().send(
        "DELETE",
        format!("/api/v1/admin/kv?key={}", gamend::detail::escape(&key)),
        Body::none(),
    );
    admin.wait(|| false, 1);
    Ok(())
}

fn scenario(
    game: &Game,
    url: &str,
    protobuf: bool,
    wire: &Recording,
    socket: &Droppable,
) -> Result<(), Failed> {
    let client = &game.client;

    // 1. Device sign-in, then /me with the token it answered.
    let device = format!("rust-conformance-{}", client.run_id());
    let login = game.call(client.auth().login_device(&device), "1 login_device")?;
    if !login.ok {
        return failed("1 login_device", login.error);
    }
    let user_id = login.session.user_id.clone();
    ok(&format!("1 login_device: user {user_id}"));

    let me = game.call(client.api().users_get_current_user(), "1 GET /me")?;
    if !me.ok() {
        return failed("1 GET /me", me.error);
    }
    if text(me.data(), "id") != user_id {
        return failed(
            "1 GET /me",
            format!("answered another user: {}", dump(me.data())),
        );
    }
    if wire.last_authorization() != format!("Bearer {}", login.session.access_token) {
        return failed("1 GET /me", "did not carry the sign-in token");
    }
    let Some(typed_me) = me
        .as_model::<models::CurrentUser>()
        .filter(|typed| typed.id == user_id)
    else {
        return failed("1 GET /me", "did not read as models::CurrentUser");
    };
    ok(&format!("1 GET /me as {}", typed_me.username));

    // 2. Refresh, and the next call carries the new token.
    let refreshed = game.call(client.auth().refresh(), "2 refresh")?;
    if !refreshed.ok {
        return failed("2 refresh", refreshed.error);
    }
    if refreshed.session.access_token == login.session.access_token {
        return failed("2 refresh", "answered the same access token");
    }
    ok(&format!(
        "2 refresh: new access token, expires in {}s",
        refreshed.session.expires_in
    ));
    let me = game.call(client.api().users_get_current_user(), "2 GET /me")?;
    if !me.ok() {
        return failed("2 GET /me", me.error);
    }
    if wire.last_authorization() != format!("Bearer {}", refreshed.session.access_token) {
        return failed("2 GET /me", "did not carry the refreshed token");
    }
    ok("2 GET /me with the refreshed token");

    // 3. Connect; the user channel joins.
    let realtime = client.realtime();
    let user_topic = realtime.user_topic();
    realtime.connect();
    if !game.wait(|| realtime.joined(&user_topic), 10) {
        return failed("3 connect", "user channel not joined");
    }
    ok(&format!("3 connected, joined {user_topic}"));

    // 4. A lobby: create it, join its topic, hear its update.
    let lobby = game.call(
        client
            .api()
            .lobbies_create_lobby(json!({ "title": "rust conformance", "max_users": 2 })),
        "4 create lobby",
    )?;
    if !lobby.ok() {
        return failed("4 create lobby", lobby.error);
    }
    let Some(typed_lobby) = lobby
        .as_model::<models::Lobby>()
        .filter(|typed| !typed.id.is_empty() && typed.max_users == 2 && typed.host_id == user_id)
    else {
        return failed(
            "4 create lobby",
            format!("did not read as models::Lobby: {}", dump(lobby.data())),
        );
    };
    let lobby_topic = format!("lobby:{}", typed_lobby.id);
    let joined = game.call(realtime.join_lobby(&typed_lobby.id), "4 join lobby")?;
    if !joined.ok {
        return failed("4 join lobby", joined.error);
    }
    let renamed = game.call(
        client
            .api()
            .lobbies_update_lobby(json!({ "title": "rust conformance (renamed)" })),
        "4 update lobby",
    )?;
    if !renamed.ok() {
        return failed("4 update lobby", renamed.error);
    }
    if !game.wait(
        || game.saw(events::LOBBY_UPDATED, &lobby_topic, protobuf),
        10,
    ) {
        return failed(
            "4 lobby updated",
            format!("no updated event on {lobby_topic}"),
        );
    }
    let suffix = if protobuf { " (protobuf)" } else { "" };
    ok(&format!("4 joined {lobby_topic}, heard its update{suffix}"));

    // 5. A hook that answers, and one that does not exist.
    let hook = game.call(
        realtime.call_hook("example_hook", "hello", json!(["rust"])),
        "5 call_hook",
    )?;
    if !hook.ok {
        return failed("5 call_hook", hook.error);
    }
    ok(&format!(
        "5 call_hook example_hook.hello: {}",
        dump(&hook.data)
    ));
    let hook = game.call(
        realtime.call_hook("example_hook", "no_such_function", json!([])),
        "5 failing hook",
    )?;
    if hook.ok {
        return failed(
            "5 failing hook",
            "a function that does not exist answered ok",
        );
    }
    ok(&format!(
        "5 a missing hook answers its error: {}",
        hook.error
    ));

    // 6. KV: subscribe, write through the API, hear it.
    let email = std::env::var("GAMEND_ADMIN_EMAIL");
    let password = std::env::var("GAMEND_ADMIN_PASSWORD");
    match (email, password) {
        (Ok(email), Ok(password)) => kv_step(game, url, &email, &password)?,
        _ => println!(
            "skip 6 kv: set GAMEND_ADMIN_EMAIL and GAMEND_ADMIN_PASSWORD to write as admin"
        ),
    }

    // 7. Pull the plug: it reconnects, rejoins, and events flow again.
    game.states.borrow_mut().clear();
    socket.drop_connection();
    // The drop is news on the next poll, like everything else.
    if !game.wait(|| realtime.state() == RealtimeState::Reconnecting, 10) {
        return failed("7 reconnect", "the drop was not noticed");
    }
    let rejoined = game.wait(
        || {
            realtime.state() == RealtimeState::Connected
                && realtime.joined(&user_topic)
                && realtime.joined(&lobby_topic)
        },
        10,
    );
    if !rejoined {
        return failed(
            "7 reconnect",
            format!("did not rejoin {user_topic} and {lobby_topic}"),
        );
    }
    if game.states.borrow().first() != Some(&RealtimeState::Reconnecting) {
        return failed("7 reconnect", "no Reconnecting state was announced");
    }
    game.events.borrow_mut().clear();
    let renamed = game.call(
        client
            .api()
            .lobbies_update_lobby(json!({ "title": "rust conformance (after the drop)" })),
        "7 update lobby",
    )?;
    if !renamed.ok() {
        return failed("7 update lobby", renamed.error);
    }
    if !game.wait(
        || game.saw(events::LOBBY_UPDATED, &lobby_topic, protobuf),
        10,
    ) {
        return failed("7 events resume", "no updated event after the reconnect");
    }
    ok("7 dropped, reconnected, rejoined both topics, events resumed");

    println!("skip 9 webrtc: no peer transport ships with this SDK");

    // 8. Leave the lobby and disconnect.
    let left = game.call(client.api().lobbies_leave_lobby(), "8 leave lobby")?;
    if !left.ok() {
        return failed("8 leave lobby", left.error);
    }
    game.call(realtime.leave(&lobby_topic), "8 leave topic")?;
    realtime.disconnect();
    if realtime.state() != RealtimeState::Disconnected {
        return failed("8 disconnect", "still connected");
    }
    ok("8 left the lobby and disconnected");
    Ok(())
}

fn main() -> ExitCode {
    let mut url = "http://127.0.0.1:4000".to_string();
    let mut protobuf = false;
    for arg in std::env::args().skip(1) {
        if arg == "--protobuf" {
            protobuf = true;
        } else {
            url = arg;
        }
    }
    let wire = Arc::new(Recording {
        inner: UreqTransport::new(),
        authorization: Mutex::new(String::new()),
    });
    let socket = Arc::new(Droppable {
        inner: TungsteniteTransport::new(),
        handlers: Mutex::new(None),
    });
    let mut config = Config::new(url.as_str());
    config.http = Some(wire.clone());
    config.websocket = Some(socket.clone());
    if protobuf {
        config.realtime_format = RealtimeFormat::Protobuf;
        config.webrtc_format = RealtimeFormat::Protobuf;
    }
    let game = Game::new(Client::new(config));
    match scenario(&game, &url, protobuf, &wire, &socket) {
        Ok(()) => ExitCode::SUCCESS,
        Err(failure) => {
            eprintln!("FAIL {}: {}", failure.step, failure.why);
            ExitCode::FAILURE
        }
    }
}
