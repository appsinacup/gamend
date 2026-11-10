//! Transports and a clock a test drives by hand, so a game's own tests can use
//! them too.
//!
//! ```
//! use std::sync::Arc;
//! use gamend::testing::{FakeClock, FakeHttp};
//! use gamend::{Client, Config};
//!
//! let server = Arc::new(FakeHttp::new());
//! let clock = FakeClock::new();
//! let mut config = Config::new("http://test");
//! config.http = Some(server.clone());
//! config.clock = Some(clock.steady());
//! let client = Client::new(config);
//!
//! let me = client.api().users_get_current_user();
//! server.reply(200, r#"{"data": {"id": "u1"}}"#);
//! assert!(!me.is_ready());
//! client.poll();
//! assert!(me.try_take().unwrap().ok());
//! ```

use std::collections::VecDeque;
use std::mem;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::Duration;

use crate::client::{Clock, UnixClock};
use crate::transport::{
    DataChannelSpec, HttpDone, HttpRequest, HttpResponse, HttpTransport, PeerHandlers,
    PeerTransport, WebSocketHandlers, WebSocketTransport,
};

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

#[derive(Default)]
struct HttpState {
    sent: Vec<HttpRequest>,
    waiting: VecDeque<(HttpRequest, HttpDone)>,
}

/// An HTTP transport that answers when told to. Every request is kept, in the
/// order it was sent; the unanswered ones wait in `pending()`.
#[derive(Default)]
pub struct FakeHttp {
    state: Mutex<HttpState>,
}

impl FakeHttp {
    pub fn new() -> Self {
        Self::default()
    }

    /// Every request sent so far, answered or not.
    pub fn sent(&self) -> Vec<HttpRequest> {
        lock(&self.state).sent.clone()
    }

    pub fn pending(&self) -> usize {
        lock(&self.state).waiting.len()
    }

    /// The oldest unanswered request.
    ///
    /// # Panics
    /// When there is none: check `pending()` first.
    pub fn next(&self) -> HttpRequest {
        lock(&self.state)
            .waiting
            .front()
            .expect("no request is waiting for an answer")
            .0
            .clone()
    }

    /// Answer the oldest unanswered request.
    pub fn reply(&self, status: u16, body: &str) {
        self.complete(HttpResponse {
            status,
            body: body.as_bytes().to_vec(),
            error: String::new(),
        });
    }

    /// Fail the oldest unanswered request, as a transport does when no reply
    /// arrives.
    pub fn fail(&self, error: &str) {
        self.complete(HttpResponse {
            status: 0,
            body: Vec::new(),
            error: error.to_string(),
        });
    }

    fn complete(&self, response: HttpResponse) {
        let waiting = lock(&self.state).waiting.pop_front();
        if let Some((_, done)) = waiting {
            done(response);
        }
    }
}

impl HttpTransport for FakeHttp {
    fn send(&self, request: HttpRequest, done: HttpDone) {
        let mut state = lock(&self.state);
        state.sent.push(request.clone());
        state.waiting.push_back((request, done));
    }
}

#[derive(Default)]
struct SocketState {
    url: String,
    handlers: Option<WebSocketHandlers>,
    frames: Vec<String>,
    unread: Vec<String>,
    opened: bool,
    opens: usize,
}

/// A WebSocket transport the test opens, feeds and drops.
#[derive(Default)]
pub struct FakeWebSocket {
    state: Mutex<SocketState>,
}

impl FakeWebSocket {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn url(&self) -> String {
        lock(&self.state).url.clone()
    }

    pub fn opened(&self) -> bool {
        lock(&self.state).opened
    }

    /// How many times the client opened a connection.
    pub fn opens(&self) -> usize {
        lock(&self.state).opens
    }

    /// Every frame the client sent, oldest first.
    pub fn frames(&self) -> Vec<String> {
        lock(&self.state).frames.clone()
    }

    /// The frames sent since the last `take_frames()`, oldest first.
    pub fn take_frames(&self) -> Vec<String> {
        mem::take(&mut lock(&self.state).unread)
    }

    fn handlers(&self) -> Option<WebSocketHandlers> {
        lock(&self.state).handlers.clone()
    }

    /// The server accepts the connection.
    pub fn accept(&self) {
        if let Some(handlers) = self.handlers() {
            handlers.on_open();
        }
    }

    /// The server sends a text frame.
    pub fn receive(&self, frame: &str) {
        if let Some(handlers) = self.handlers() {
            handlers.on_text(frame.to_string());
        }
    }

    /// The server sends a binary frame.
    pub fn receive_binary(&self, bytes: Vec<u8>) {
        if let Some(handlers) = self.handlers() {
            handlers.on_binary(bytes);
        }
    }

    /// The connection fails before or after opening, as a transport reports it.
    pub fn fail(&self, error: &str) {
        if let Some(handlers) = self.handlers() {
            handlers.on_error(error.to_string());
        }
    }

    /// The connection drops.
    pub fn drop_connection(&self) {
        lock(&self.state).opened = false;
        if let Some(handlers) = self.handlers() {
            handlers.on_close(1006, String::new());
        }
    }
}

impl WebSocketTransport for FakeWebSocket {
    fn open(&self, url: &str, handlers: WebSocketHandlers) {
        let mut state = lock(&self.state);
        state.url = url.to_string();
        state.handlers = Some(handlers);
        state.opened = true;
        state.opens += 1;
    }

    fn send_text(&self, frame: String) {
        let mut state = lock(&self.state);
        state.frames.push(frame.clone());
        state.unread.push(frame);
    }

    fn close(&self) {
        lock(&self.state).opened = false;
    }
}

/// What a `FakePeer` was asked to send.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PeerSent {
    pub label: String,
    pub data: Vec<u8>,
    pub binary: bool,
}

#[derive(Default)]
struct PeerState {
    handlers: Option<PeerHandlers>,
    ice_servers: Vec<String>,
    channels: Vec<DataChannelSpec>,
    protocol: String,
    remote: (String, String),
    candidates: Vec<(String, String)>,
    sent: Vec<PeerSent>,
    opened: bool,
    closes: usize,
}

/// A WebRTC peer the test drives: it records what the client asks of it, and
/// plays the connection's side of the story on command.
#[derive(Default)]
pub struct FakePeer {
    state: Mutex<PeerState>,
}

impl FakePeer {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn opened(&self) -> bool {
        lock(&self.state).opened
    }

    pub fn closes(&self) -> usize {
        lock(&self.state).closes
    }

    pub fn protocol(&self) -> String {
        lock(&self.state).protocol.clone()
    }

    pub fn ice_servers(&self) -> Vec<String> {
        lock(&self.state).ice_servers.clone()
    }

    pub fn channels(&self) -> Vec<DataChannelSpec> {
        lock(&self.state).channels.clone()
    }

    /// The remote description set: SDP and type.
    pub fn remote(&self) -> (String, String) {
        lock(&self.state).remote.clone()
    }

    pub fn candidates(&self) -> Vec<(String, String)> {
        lock(&self.state).candidates.clone()
    }

    pub fn sent(&self) -> Vec<PeerSent> {
        lock(&self.state).sent.clone()
    }

    fn handlers(&self) -> Option<PeerHandlers> {
        lock(&self.state).handlers.clone()
    }

    pub fn offer(&self, sdp: &str) {
        if let Some(handlers) = self.handlers() {
            handlers.on_local_description(sdp.to_string(), "offer".to_string());
        }
    }

    pub fn candidate(&self, candidate: &str, mid: &str) {
        if let Some(handlers) = self.handlers() {
            handlers.on_local_candidate(candidate.to_string(), mid.to_string());
        }
    }

    pub fn state(&self, state: &str) {
        if let Some(handlers) = self.handlers() {
            handlers.on_state(state.to_string());
        }
    }

    pub fn open_channel(&self, label: &str) {
        if let Some(handlers) = self.handlers() {
            handlers.on_channel_open(label.to_string());
        }
    }

    pub fn close_channel(&self, label: &str) {
        if let Some(handlers) = self.handlers() {
            handlers.on_channel_close(label.to_string());
        }
    }

    pub fn receive(&self, label: &str, data: &[u8], binary: bool) {
        if let Some(handlers) = self.handlers() {
            handlers.on_message(label.to_string(), data.to_vec(), binary);
        }
    }
}

impl PeerTransport for FakePeer {
    fn open(
        &self,
        ice_servers: &[String],
        channels: &[DataChannelSpec],
        protocol: &str,
        handlers: PeerHandlers,
    ) {
        let mut state = lock(&self.state);
        state.ice_servers = ice_servers.to_vec();
        state.channels = channels.to_vec();
        state.protocol = protocol.to_string();
        state.handlers = Some(handlers);
        state.opened = true;
    }

    fn set_remote_description(&self, sdp: &str, kind: &str) {
        lock(&self.state).remote = (sdp.to_string(), kind.to_string());
    }

    fn add_remote_candidate(&self, candidate: &str, mid: &str) {
        lock(&self.state)
            .candidates
            .push((candidate.to_string(), mid.to_string()));
    }

    fn send(&self, label: &str, data: &[u8], binary: bool) -> bool {
        lock(&self.state).sent.push(PeerSent {
            label: label.to_string(),
            data: data.to_vec(),
            binary,
        });
        true
    }

    fn close(&self) {
        let mut state = lock(&self.state);
        state.opened = false;
        state.closes += 1;
    }
}

struct Time {
    steady: u64,
    unix_ms: i64,
}

/// Both clocks a `Config` takes, moved by hand. Clones share one time.
#[derive(Clone)]
pub struct FakeClock {
    time: Arc<Mutex<Time>>,
}

impl Default for FakeClock {
    fn default() -> Self {
        Self::new()
    }
}

impl FakeClock {
    pub fn new() -> Self {
        Self {
            time: Arc::new(Mutex::new(Time {
                steady: 0,
                unix_ms: 1_800_000_000_000,
            })),
        }
    }

    pub fn advance(&self, by: Duration) {
        let mut time = lock(&self.time);
        time.steady += by.as_millis() as u64;
        time.unix_ms += by.as_millis() as i64;
    }

    /// The current wall clock, in Unix seconds.
    pub fn unix_now(&self) -> i64 {
        lock(&self.time).unix_ms / 1000
    }

    pub fn steady(&self) -> Clock {
        let time = self.time.clone();
        Arc::new(move || lock(&time).steady)
    }

    pub fn wall(&self) -> UnixClock {
        let time = self.time.clone();
        Arc::new(move || lock(&time).unix_ms / 1000)
    }
}
