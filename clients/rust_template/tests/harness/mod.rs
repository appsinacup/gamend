//! A client over a fake server and a fake clock, for every test.
#![allow(dead_code)]

use std::sync::{Arc, Mutex};
use std::time::Duration;

pub use gamend::testing::{FakeClock, FakeHttp, FakePeer, FakeWebSocket};
use gamend::{json, Client, Config, RealtimeFormat, Session, Ticket, Value};

pub fn secs(n: u64) -> Duration {
    Duration::from_secs(n)
}

pub fn ms(n: u64) -> Duration {
    Duration::from_millis(n)
}

/// A sign-in reply with the tokens `a<n>` / `r<n>`.
pub fn session_reply(n: u32) -> String {
    session_reply_lasting(n, 900)
}

pub fn session_reply_lasting(n: u32, expires_in: i64) -> String {
    json!({
        "data": {
            "access_token": format!("a{n}"),
            "refresh_token": format!("r{n}"),
            "user_id": "u1",
            "username": "ann",
            "display_name": "Ann",
            "expires_in": expires_in,
        }
    })
    .to_string()
}

pub fn parsed(body: &[u8]) -> Value {
    gamend::json::parse(body).expect("the body is not JSON")
}

/// What a ticket answered, which must have come.
pub fn got<T>(ticket: &Ticket<T>) -> T {
    ticket.try_take().expect("the ticket has not completed")
}

/// A server reply to a join, leave or push.
pub fn reply(
    join_ref: &str,
    reference: &str,
    topic: &str,
    status: &str,
    response: Value,
) -> String {
    json!([join_ref, reference, topic, "phx_reply", { "status": status, "response": response }])
        .to_string()
}

/// A reply to `frame`, one of the frames the client sent.
pub fn reply_to(frame: &Value, status: &str, response: Value) -> String {
    json!([frame[0], frame[1], frame[2], "phx_reply", { "status": status, "response": response }])
        .to_string()
}

pub fn ok_reply(join_ref: &str, reference: &str, topic: &str) -> String {
    reply(join_ref, reference, topic, "ok", json!({}))
}

/// A server push on a topic.
pub fn message(topic: &str, event: &str, payload: Value) -> String {
    json!([null, null, topic, event, payload]).to_string()
}

pub fn frame_of(text: &str) -> Value {
    parsed(text.as_bytes())
}

pub struct Harness {
    pub clock: FakeClock,
    pub server: Arc<FakeHttp>,
    pub socket: Arc<FakeWebSocket>,
    pub peer: Arc<FakePeer>,
    pub client: Client,
    opened: Arc<Mutex<Vec<String>>>,
}

impl Harness {
    pub fn new() -> Self {
        Self::with(true, RealtimeFormat::Json)
    }

    pub fn with(open_url: bool, webrtc_format: RealtimeFormat) -> Self {
        let clock = FakeClock::new();
        let server = Arc::new(FakeHttp::new());
        let socket = Arc::new(FakeWebSocket::new());
        let peer = Arc::new(FakePeer::new());
        let opened = Arc::new(Mutex::new(Vec::new()));
        let mut config = Config::new("http://game.test/");
        config.http = Some(server.clone());
        config.websocket = Some(socket.clone());
        config.webrtc = Some(peer.clone());
        config.webrtc_format = webrtc_format;
        config.run_id = "run-1".to_string();
        config.clock = Some(clock.steady());
        config.unix_clock = Some(clock.wall());
        config.sign_in_timeout = secs(5);
        if open_url {
            let seen = opened.clone();
            config.open_url = Some(Arc::new(move |url: &str| {
                seen.lock().unwrap().push(url.to_string());
            }));
        }
        Self {
            client: Client::new(config),
            clock,
            server,
            socket,
            peer,
            opened,
        }
    }

    /// Signed in as `a1`/`r1` without a round trip.
    pub fn signed_in(&self) {
        self.signed_in_for(900);
    }

    pub fn signed_in_for(&self, lasts: i64) {
        self.client.auth().restore(Session {
            access_token: "a1".to_string(),
            refresh_token: "r1".to_string(),
            user_id: "u1".to_string(),
            username: "ann".to_string(),
            display_name: String::new(),
            expires_in: 900,
            expires_at: self.clock.unix_now() + lasts,
        });
    }

    pub fn advance(&self, by: Duration) {
        self.clock.advance(by);
        self.client.poll();
    }

    /// The URLs handed to `Config::open_url`.
    pub fn opened(&self) -> Vec<String> {
        self.opened.lock().unwrap().clone()
    }

    pub fn poll(&self) {
        self.client.poll();
    }

    /// What the client sent since the last call, as JSON.
    pub fn frames(&self) -> Vec<Value> {
        self.socket
            .take_frames()
            .iter()
            .map(|frame| frame_of(frame))
            .collect()
    }

    /// Connected and the user channel joined, its join frame answered.
    pub fn connect(&self) {
        self.client.realtime().connect();
        self.socket.accept();
        self.poll();
        let join = self.frames().remove(0);
        self.socket.receive(&reply_to(&join, "ok", json!({})));
        self.poll();
    }

    /// Signed in as u1 and connected, the user channel joined.
    pub fn connected() -> Self {
        Self::connected_with(RealtimeFormat::Json)
    }

    pub fn connected_with(webrtc_format: RealtimeFormat) -> Self {
        let harness = Self::with(true, webrtc_format);
        harness.signed_in();
        harness.connect();
        harness
    }
}
