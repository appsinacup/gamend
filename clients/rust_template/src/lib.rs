//! A Rust client for [Gamend](https://gamend.org): every player-facing REST
//! operation, typed models, sign-in and a session that stays fresh, the realtime
//! connection with server hooks, live key-value rows and presence, protobuf
//! events, and WebRTC DataChannels, over transports you choose.
//!
//! ```no_run
//! # #[cfg(feature = "native")] {
//! use gamend::{events, json, models, Client, Config};
//!
//! let client = Client::new(Config::native("https://game.example.com"));
//!
//! let signed_in = client.auth().login_device("device-123");
//! let mut lobby = None;
//!
//! // Once per frame:
//! client.poll();
//! if let Some(result) = signed_in.try_take() {
//!     if result.ok {
//!         client.realtime().connect(); // joins user:<id> itself
//!         lobby = Some(client.api().lobbies_quick_join(json!({ "title": "duel" })));
//!     }
//! }
//! if let Some(reply) = lobby.as_ref().and_then(|ticket| ticket.try_take()) {
//!     if let Some(lobby) = reply.as_model::<models::Lobby>() {
//!         client.realtime().join_lobby(&lobby.id);
//!     }
//! }
//! for event in client.drain_events() {
//!     if event.kind == events::LOBBY_UPDATED {
//!         println!("{}", event.payload);
//!     }
//! }
//! # }
//! ```

mod auth;
mod client;
mod core;
// Written by clients/sdkgen. Its emitter lays the code out, not rustfmt: a
// generator whose output had to match rustfmt line for line would break on
// whichever schema first wrapped differently.
#[rustfmt::skip]
mod generated;
pub mod json;
mod kv;
mod model;
#[cfg(feature = "native")]
pub mod native;
mod phoenix;
mod presence;
mod proto;
mod query;
mod realtime;
mod response;
mod rest;
mod session;
pub mod testing;
mod ticket;
mod transport;
mod webrtc;

pub use auth::{Auth, AuthResult};
pub use client::{Client, Clock, Config, LogLevel, Logger, RealtimeFormat, UnixClock, UrlOpener};
pub use generated::api::Api;
pub use generated::{commands, events, models};
pub use kv::{Kv, KvKey, KvResult, KvRow};
pub use model::Model;
#[cfg(feature = "native")]
pub use native::{TungsteniteTransport, UreqTransport};
pub use presence::Presence;
pub use realtime::{BytesDecoder, Event, HookResult, Realtime, RealtimeState, Reply};
pub use response::Response;
pub use rest::{Body, Rest};
pub use serde_json::{json, Value};
pub use session::Session;
pub use ticket::Ticket;
pub use transport::{
    DataChannelSpec, Headers, HttpDone, HttpRequest, HttpResponse, HttpTransport, PeerEvent,
    PeerHandlers, PeerTransport, WebSocketEvent, WebSocketHandlers, WebSocketTransport,
};
pub use webrtc::{ChannelChange, DataMessage, WebRtc, WebRtcState};

/// The wire code, public only so this crate's tests can reach it.
#[doc(hidden)]
pub mod detail {
    pub use crate::phoenix::{Frame, FrameKind, Heartbeat, Phoenix};
    pub use crate::query::{escape, given, query};

    pub mod proto {
        pub use crate::proto::*;
    }
}
