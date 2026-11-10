//! The only place a network library appears. The core speaks to these traits;
//! the `native` feature ships `UreqTransport` and `TungsteniteTransport`, an
//! engine plugs in its own, and the unit tests use `gamend::testing`.
//!
//! A transport may complete on any thread. The client hands every completion to
//! the thread that calls `poll()` through its inbox, so an implementation never
//! needs to.

use std::sync::Arc;
use std::time::Duration;

pub type Headers = Vec<(String, String)>;

#[derive(Clone, Debug, Default)]
pub struct HttpRequest {
    /// GET, POST, PUT, PATCH, DELETE.
    pub method: String,
    pub url: String,
    /// Empty for none.
    pub body: Vec<u8>,
    pub headers: Headers,
    pub timeout: Duration,
}

impl HttpRequest {
    /// The value of `name` in the headers, if it is there.
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    }
}

#[derive(Clone, Debug, Default)]
pub struct HttpResponse {
    /// 0 when no reply arrived.
    pub status: u16,
    pub body: Vec<u8>,
    /// Why no reply arrived; empty when one did.
    pub error: String,
}

/// What a transport calls with the reply, exactly once, from any thread.
pub type HttpDone = Box<dyn FnOnce(HttpResponse) + Send>;

pub trait HttpTransport: Send + Sync {
    /// Send `request` and call `done`. A 4xx or 5xx is a reply like any other,
    /// not an `error`. A transport being dropped may drop the completions it
    /// still owes.
    fn send(&self, request: HttpRequest, done: HttpDone);
}

/// What happened on a WebSocket.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WebSocketEvent {
    Open,
    Text(String),
    /// The server's protobuf events, when asked for.
    Binary(Vec<u8>),
    /// The connection ended, whoever ended it. It may or may not come for a
    /// `close()` the client asked for.
    Close {
        code: u16,
        reason: String,
    },
    /// The connection failed, opening or open. A `Close` may follow.
    Error(String),
}

/// Where a WebSocket transport reports. May be called from any thread.
#[derive(Clone)]
pub struct WebSocketHandlers {
    sink: Arc<dyn Fn(WebSocketEvent) + Send + Sync>,
}

impl WebSocketHandlers {
    /// Handlers that give every event to `sink`: for a transport that wraps
    /// another and wants to see what goes by.
    pub fn new(sink: impl Fn(WebSocketEvent) + Send + Sync + 'static) -> Self {
        Self {
            sink: Arc::new(sink),
        }
    }

    pub fn on_open(&self) {
        (self.sink)(WebSocketEvent::Open);
    }

    pub fn on_text(&self, frame: String) {
        (self.sink)(WebSocketEvent::Text(frame));
    }

    pub fn on_binary(&self, bytes: Vec<u8>) {
        (self.sink)(WebSocketEvent::Binary(bytes));
    }

    pub fn on_close(&self, code: u16, reason: String) {
        (self.sink)(WebSocketEvent::Close { code, reason });
    }

    pub fn on_error(&self, error: String) {
        (self.sink)(WebSocketEvent::Error(error));
    }
}

pub trait WebSocketTransport: Send + Sync {
    /// Connect to `url` (`ws://` or `wss://`). Reconnecting is the caller's
    /// business, not the transport's.
    fn open(&self, url: &str, handlers: WebSocketHandlers);
    fn send_text(&self, frame: String);
    fn close(&self);
}

/// A WebRTC DataChannel to open.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DataChannelSpec {
    pub label: String,
    pub ordered: bool,
    /// -1: reliable. 0 or more: give up on a message after that many retries.
    pub max_retransmits: i32,
}

impl DataChannelSpec {
    pub fn new(label: impl Into<String>, ordered: bool, max_retransmits: i32) -> Self {
        Self {
            label: label.into(),
            ordered,
            max_retransmits,
        }
    }

    /// Ordered, and retried until it arrives.
    pub fn reliable(label: impl Into<String>) -> Self {
        Self::new(label, true, -1)
    }
}

/// What a peer connection reports.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PeerEvent {
    /// The offer to send: its SDP and type (`offer`).
    LocalDescription {
        sdp: String,
        kind: String,
    },
    /// An ICE candidate (`candidate:...`) and its media id.
    LocalCandidate {
        candidate: String,
        mid: String,
    },
    /// `connecting`, `connected`, `disconnected`, `failed` or `closed`.
    State(String),
    ChannelOpen(String),
    ChannelClose(String),
    Message {
        label: String,
        data: Vec<u8>,
        binary: bool,
    },
}

/// Where a peer connection reports. May be called from any thread.
#[derive(Clone)]
pub struct PeerHandlers {
    sink: Arc<dyn Fn(PeerEvent) + Send + Sync>,
}

impl PeerHandlers {
    pub fn new(sink: impl Fn(PeerEvent) + Send + Sync + 'static) -> Self {
        Self {
            sink: Arc::new(sink),
        }
    }

    pub fn on_local_description(&self, sdp: String, kind: String) {
        (self.sink)(PeerEvent::LocalDescription { sdp, kind });
    }

    pub fn on_local_candidate(&self, candidate: String, mid: String) {
        (self.sink)(PeerEvent::LocalCandidate { candidate, mid });
    }

    pub fn on_state(&self, state: String) {
        (self.sink)(PeerEvent::State(state));
    }

    pub fn on_channel_open(&self, label: String) {
        (self.sink)(PeerEvent::ChannelOpen(label));
    }

    pub fn on_channel_close(&self, label: String) {
        (self.sink)(PeerEvent::ChannelClose(label));
    }

    pub fn on_message(&self, label: String, data: Vec<u8>, binary: bool) {
        (self.sink)(PeerEvent::Message {
            label,
            data,
            binary,
        });
    }
}

pub trait PeerTransport: Send + Sync {
    /// Create the connection with `channels` (each negotiated with `protocol`,
    /// empty or `protobuf`) and make the offer.
    fn open(
        &self,
        ice_servers: &[String],
        channels: &[DataChannelSpec],
        protocol: &str,
        handlers: PeerHandlers,
    );
    fn set_remote_description(&self, sdp: &str, kind: &str);
    fn add_remote_candidate(&self, candidate: &str, mid: &str);
    /// False when the channel is not open.
    fn send(&self, label: &str, data: &[u8], binary: bool) -> bool;
    fn close(&self);
}
