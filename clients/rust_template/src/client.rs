//! The client: configuration, transports, and the one place tickets complete.
//!
//! I/O never runs on the game thread, and answers never arrive anywhere else:
//! transports complete on their own threads into an inbox that `poll()` drains,
//! in arrival order, along with the timers (token refresh, sign-in polling,
//! heartbeats, reconnects).

use std::sync::Arc;
use std::time::Duration;

use crate::auth::Auth;
use crate::core::Shared;
use crate::generated::api::Api;
use crate::kv::Kv;
use crate::presence::Presence;
use crate::realtime::{Event, Realtime};
use crate::rest::Rest;
use crate::transport::{DataChannelSpec, HttpTransport, PeerTransport, WebSocketTransport};
use crate::webrtc::WebRtc;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum LogLevel {
    Debug,
    Info,
    Warning,
    Error,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum RealtimeFormat {
    /// Every server event as JSON text.
    #[default]
    Json,
    /// The events `proto/gamend_realtime.proto` maps as binary protobuf frames,
    /// decoded before they reach `events()`: smaller on the wire, and timestamps
    /// arrive as unix milliseconds (`*_ms`).
    Protobuf,
}

/// Monotonic milliseconds for timers. Called while the client's state is held,
/// so it must not call the client.
pub type Clock = Arc<dyn Fn() -> u64 + Send + Sync>;
/// Unix seconds, for when a kept session's token lapses.
pub type UnixClock = Arc<dyn Fn() -> i64 + Send + Sync>;
/// Opens a sign-in page: the system browser, a web view.
pub type UrlOpener = Arc<dyn Fn(&str) + Send + Sync>;
/// Where the SDK's own lines go.
pub type Logger = Arc<dyn Fn(LogLevel, &str) + Send + Sync>;

pub struct Config {
    /// The server root, `https://game.example.com`; paths are appended to it.
    pub base_url: String,
    pub http: Option<Arc<dyn HttpTransport>>,
    /// For the realtime layer; unused until it connects.
    pub websocket: Option<Arc<dyn WebSocketTransport>>,
    /// For `Client::webrtc()`; unused until it connects.
    pub webrtc: Option<Arc<dyn PeerTransport>>,
    pub http_timeout: Duration,
    /// Without it, sign-in through a provider fails.
    pub open_url: Option<UrlOpener>,
    /// Silent without it.
    pub log: Option<Logger>,
    /// This run's id, sent as `x-gamend-session` so the server files a run's
    /// client and server lines together. Random when empty.
    pub run_id: String,
    /// How often `Auth::sign_in` asks whether the player finished at the
    /// provider, and how long it waits for them.
    pub sign_in_poll: Duration,
    pub sign_in_timeout: Duration,
    /// How the server sends realtime events.
    pub realtime_format: RealtimeFormat,
    /// How long a join or a push waits for the server's reply.
    pub push_timeout: Duration,
    /// ICE servers for WebRTC, as `stun:host:port` or
    /// `turn:user:pass@host:port`.
    pub ice_servers: Vec<String>,
    /// The DataChannels `WebRtc::connect` opens. The server answers hook calls
    /// on `events` and holds up to four channels.
    pub data_channels: Vec<DataChannelSpec>,
    /// How hook calls ride the `events` channel: JSON messages, or protobuf
    /// envelopes with request ids.
    pub webrtc_format: RealtimeFormat,
    /// How long `WebRtc::connect` waits for a channel to open.
    pub webrtc_timeout: Duration,
    /// The waits before each reconnect attempt; the last repeats.
    pub reconnect_delays: Vec<Duration>,
    /// The `native` feature's steady clock when empty; required without it.
    pub clock: Option<Clock>,
    /// The `native` feature's system clock when empty. Without either, the time
    /// a kept session lapses and when a player was last seen stay unknown.
    pub unix_clock: Option<UnixClock>,
    /// How many of each kind of drained news (`events()`, `changes()`, ...) wait
    /// to be read. Past this the oldest goes first, and the log says so.
    pub queue_limit: usize,
}

impl Config {
    /// A configuration with no transports: set the fields it needs.
    pub fn new(base_url: impl Into<String>) -> Self {
        Self {
            base_url: base_url.into(),
            http: None,
            websocket: None,
            webrtc: None,
            http_timeout: Duration::from_secs(10),
            open_url: None,
            log: None,
            run_id: String::new(),
            sign_in_poll: Duration::from_secs(1),
            sign_in_timeout: Duration::from_secs(300),
            realtime_format: RealtimeFormat::Json,
            push_timeout: Duration::from_secs(10),
            ice_servers: vec!["stun:stun.l.google.com:19302".to_string()],
            data_channels: vec![DataChannelSpec::reliable("events")],
            webrtc_format: RealtimeFormat::Json,
            webrtc_timeout: Duration::from_secs(15),
            reconnect_delays: vec![
                Duration::from_millis(100),
                Duration::from_millis(500),
                Duration::from_millis(1000),
                Duration::from_millis(2000),
                Duration::from_millis(5000),
                Duration::from_millis(10000),
            ],
            clock: None,
            unix_clock: None,
            queue_limit: 4096,
        }
    }

    /// A configuration with `UreqTransport` and `TungsteniteTransport`.
    #[cfg(feature = "native")]
    pub fn native(base_url: impl Into<String>) -> Self {
        let mut config = Self::new(base_url);
        config.http = Some(Arc::new(crate::native::UreqTransport::new()));
        config.websocket = Some(Arc::new(crate::native::TungsteniteTransport::new()));
        config
    }
}

#[cfg(feature = "native")]
fn default_clocks(config: &mut Config) {
    if config.clock.is_none() {
        config.clock = Some(crate::native::monotonic_clock());
    }
    if config.unix_clock.is_none() {
        config.unix_clock = Some(crate::native::unix_clock());
    }
}

#[cfg(not(feature = "native"))]
fn default_clocks(_config: &mut Config) {}

/// A Gamend client. `Send + Sync` with `&self` methods, so it can sit in a Bevy
/// `Resource` or a macroquad loop's locals alike. Clones share one connection.
///
/// Call `poll()` once per frame: it is where every `Ticket` completes.
#[derive(Clone)]
pub struct Client {
    shared: Arc<Shared>,
    api: Api,
    auth: Auth,
    rest: Rest,
    realtime: Realtime,
    kv: Kv,
    presence: Presence,
    webrtc: WebRtc,
}

impl Client {
    /// # Panics
    /// Without the `native` feature, when `Config::clock` is not set: nothing
    /// could ever come due.
    pub fn new(mut config: Config) -> Self {
        default_clocks(&mut config);
        let clock = config
            .clock
            .clone()
            .expect("Config::clock is required without the `native` feature");
        let shared = Shared::new(config, clock);
        let rest = Rest::new(shared.clone());
        Self {
            api: Api::new(rest.clone()),
            auth: Auth::new(shared.clone()),
            rest,
            realtime: Realtime::new(shared.clone()),
            kv: Kv::new(shared.clone()),
            presence: Presence::new(shared.clone()),
            webrtc: WebRtc::new(shared.clone()),
            shared,
        }
    }

    /// Every operation of the REST API a game can call, one method each.
    pub fn api(&self) -> &Api {
        &self.api
    }

    /// Signing in, and staying signed in.
    pub fn auth(&self) -> &Auth {
        &self.auth
    }

    /// The authenticated caller `api()` is built on, for a path it lacks.
    pub fn rest(&self) -> &Rest {
        &self.rest
    }

    /// The realtime connection: channels, events, server hooks.
    pub fn realtime(&self) -> &Realtime {
        &self.realtime
    }

    /// Live key-value rows over the realtime connection, and their cache.
    pub fn kv(&self) -> &Kv {
        &self.kv
    }

    /// Who is around, as the realtime events tell it.
    pub fn presence(&self) -> &Presence {
        &self.presence
    }

    /// WebRTC DataChannels to the server, signaled over the user channel.
    pub fn webrtc(&self) -> &WebRtc {
        &self.webrtc
    }

    /// Run what arrived since the last call: replies, then due timers. Call it
    /// once per frame.
    pub fn poll(&self) {
        self.shared.drain();
    }

    /// The realtime events that arrived since the last call:
    /// `client.realtime().events()`.
    pub fn drain_events(&self) -> Vec<Event> {
        self.realtime.events()
    }

    pub fn base_url(&self) -> String {
        self.shared.with(|core| core.base_url.clone())
    }

    pub fn run_id(&self) -> String {
        self.shared.with(|core| core.run_id.clone())
    }
}
