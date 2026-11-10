//! WebRTC DataChannels to the server: lower latency than the socket for game
//! traffic, signaled over the realtime user channel.
//!
//! The server is the other peer. One channel by default: `events`, reliable and
//! ordered, which hook calls ride on (`Config::data_channels` adds more, up to
//! the server's four). Like the other transports, the peer connection is a
//! trait; no implementation ships yet, so a game brings its own.

use std::collections::BTreeMap;
use std::mem;
use std::sync::Arc;

use serde_json::{json, Value};

use crate::client::RealtimeFormat;
use crate::core::{Core, Queue, Shared};
use crate::json::{dump, field, number, parse, text, text_or};
use crate::proto;
use crate::realtime::{self, args_of, Event, HookResult, RealtimeState};
use crate::ticket::{Completer, Ticket};
use crate::transport::{PeerEvent, PeerHandlers};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WebRtcState {
    Closed,
    Connecting,
    Connected,
    Failed,
}

/// A message on a DataChannel that was not a hook reply.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DataMessage {
    pub label: String,
    pub data: Vec<u8>,
    pub binary: bool,
}

/// A DataChannel opened or closed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChannelChange {
    pub label: String,
    pub open: bool,
}

struct Call {
    serial: u64,
    // Protobuf: the envelope's request id.
    id: u32,
    // JSON: replies are matched by these, oldest first.
    plugin: String,
    function: String,
    done: Completer<HookResult>,
    timer: u64,
}

pub(crate) struct State {
    state: WebRtcState,
    generation: u64,
    connecting: Option<Completer<Result<(), String>>>,
    connect_timer: u64,
    open: BTreeMap<String, bool>,
    calls: Vec<Call>,
    next_call: u32,
    next_serial: u64,
    data: Queue<DataMessage>,
    states: Queue<WebRtcState>,
    channels: Queue<ChannelChange>,
}

impl State {
    pub(crate) fn new(limit: usize) -> Self {
        Self {
            state: WebRtcState::Closed,
            generation: 0,
            connecting: None,
            connect_timer: 0,
            open: BTreeMap::new(),
            calls: Vec::new(),
            next_call: 1,
            next_serial: 1,
            data: Queue::new(limit),
            states: Queue::new(limit),
            channels: Queue::new(limit),
        }
    }
}

fn protobuf(core: &Core) -> bool {
    core.config.webrtc_format == RealtimeFormat::Protobuf
}

/// WebRTC DataChannels to the server, signaled over the user channel.
#[derive(Clone)]
pub struct WebRtc {
    shared: Arc<Shared>,
}

impl WebRtc {
    pub(crate) fn new(shared: Arc<Shared>) -> Self {
        Self { shared }
    }

    /// Offer a connection to the server over the user channel (join it first:
    /// `Realtime::connect`). The ticket gets `Ok` once a channel is open, or why
    /// not: `not_joined`, `no_transport`, the server's refusal, `failed`,
    /// `timeout`.
    pub fn connect(&self) -> Ticket<Result<(), String>> {
        self.shared.start(connect)
    }

    /// Close the connection and tell the server.
    pub fn close(&self) {
        self.shared.with(close);
    }

    pub fn state(&self) -> WebRtcState {
        self.shared.with(|core| core.webrtc.state)
    }

    pub fn channel_open(&self, label: &str) -> bool {
        self.shared.with(|core| channel_open(core, label))
    }

    /// Send on a channel; false when it is not open.
    pub fn send(&self, label: &str, data: &[u8], binary: bool) -> bool {
        self.shared.with(|core| {
            channel_open(core, label)
                && core
                    .config
                    .webrtc
                    .as_ref()
                    .is_some_and(|peer| peer.send(label, data, binary))
        })
    }

    /// Call a server hook over the `events` channel. `args` that is not an array
    /// goes as its one element.
    pub fn call_hook(&self, plugin: &str, function: &str, args: Value) -> Ticket<HookResult> {
        self.start_call(plugin, function, args_of(args), None)
    }

    /// Call a typed hook with the game's own encoded request
    /// (`<FnName>Request`, registered by the plugin); the ticket gets the
    /// reply's bytes in `HookResult::bytes`. Needs `webrtc_format = Protobuf`;
    /// the server relays the bytes without decoding them.
    pub fn call_hook_raw(
        &self,
        plugin: &str,
        function: &str,
        request: Vec<u8>,
    ) -> Ticket<HookResult> {
        self.start_call(plugin, function, Value::Null, Some(request))
    }

    fn start_call(
        &self,
        plugin: &str,
        function: &str,
        args: Value,
        raw: Option<Vec<u8>>,
    ) -> Ticket<HookResult> {
        self.shared
            .start(|core, done| start_call(core, plugin, function, &args, raw, done))
    }

    /// What arrived on any channel since the last call, hook replies aside.
    pub fn data(&self) -> Vec<DataMessage> {
        self.shared
            .with(|core| core.drained(|core| &mut core.webrtc.data))
    }

    /// Every change of `state()` since the last call.
    pub fn state_changes(&self) -> Vec<WebRtcState> {
        self.shared
            .with(|core| core.drained(|core| &mut core.webrtc.states))
    }

    /// Channels opened or closed since the last call.
    pub fn channel_changes(&self) -> Vec<ChannelChange> {
        self.shared
            .with(|core| core.drained(|core| &mut core.webrtc.channels))
    }
}

fn channel_open(core: &Core, label: &str) -> bool {
    core.webrtc.open.get(label).copied().unwrap_or(false)
}

fn connect(core: &mut Core, done: Completer<Result<(), String>>) {
    let user = realtime::user_topic(core);
    let refused = if core.config.webrtc.is_none() {
        Some("no_transport")
    } else if !realtime::joined(core, &user) {
        Some("not_joined")
    } else {
        None
    };
    if let Some(refused) = refused {
        core.complete(done, Err(refused.to_string()));
        return;
    }
    if core.webrtc.state != WebRtcState::Closed {
        close(core);
    }

    core.webrtc.generation += 1;
    let generation = core.webrtc.generation;
    core.webrtc.connecting = Some(done);
    core.webrtc.open.clear();
    set_state(core, WebRtcState::Connecting);
    let timeout = core.config.webrtc_timeout;
    core.webrtc.connect_timer = core.after(timeout, move |core| {
        if generation != core.webrtc.generation || core.webrtc.connecting.is_none() {
            return;
        }
        finish_connect(core, "timeout");
        close(core);
        set_state(core, WebRtcState::Failed);
    });

    let post = core.poster();
    let handlers = PeerHandlers::new(move |event| {
        post.post(move |core| {
            if generation != core.webrtc.generation {
                return;
            }
            match event {
                PeerEvent::LocalDescription { sdp, kind } => local_description(core, &sdp, &kind),
                PeerEvent::LocalCandidate { candidate, mid } => {
                    local_candidate(core, &candidate, &mid);
                }
                PeerEvent::State(state) => peer_state(core, &state),
                PeerEvent::ChannelOpen(label) => channel_opened(core, label),
                PeerEvent::ChannelClose(label) => channel_closed(core, label),
                PeerEvent::Message {
                    label,
                    data,
                    binary,
                } => message(core, label, data, binary),
            }
        });
    });
    let protocol = if protobuf(core) { "protobuf" } else { "" };
    if let Some(peer) = &core.config.webrtc {
        peer.open(
            &core.config.ice_servers,
            &core.config.data_channels,
            protocol,
            handlers,
        );
    }
}

fn close(core: &mut Core) {
    if core.webrtc.state == WebRtcState::Closed {
        return;
    }
    core.webrtc.generation += 1;
    let timer = mem::take(&mut core.webrtc.connect_timer);
    core.cancel(timer);
    if let Some(peer) = &core.config.webrtc {
        peer.close();
    }
    let user = realtime::user_topic(core);
    if realtime::joined(core, &user) {
        realtime::push(core, &user, "webrtc:close", &json!({}), None);
    }
    finish_connect(core, "closed");
    fail_calls(core, "closed");
    for (label, was_open) in mem::take(&mut core.webrtc.open) {
        if was_open {
            core.webrtc
                .channels
                .push(ChannelChange { label, open: false });
        }
    }
    set_state(core, WebRtcState::Closed);
}

/// The server's peer lives in the user channel's process: when the socket goes,
/// so does the other end of this connection.
pub(crate) fn realtime_state_changed(core: &mut Core, state: RealtimeState) {
    if state != RealtimeState::Connected && core.webrtc.state != WebRtcState::Closed {
        close(core);
    }
}

fn local_description(core: &mut Core, sdp: &str, kind: &str) {
    let generation = core.webrtc.generation;
    let topic = realtime::user_topic(core);
    realtime::push(
        core,
        &topic,
        "webrtc:offer",
        &json!({ "sdp": sdp, "type": kind }),
        Some(Box::new(move |core, reply| {
            if generation != core.webrtc.generation || reply.ok {
                return;
            }
            finish_connect(core, &reply.error);
            close(core);
            set_state(core, WebRtcState::Failed);
        })),
    );
}

fn local_candidate(core: &mut Core, candidate: &str, mid: &str) {
    let topic = realtime::user_topic(core);
    realtime::push(
        core,
        &topic,
        "webrtc:ice",
        &json!({ "candidate": candidate, "sdpMid": mid, "sdpMLineIndex": 0 }),
        None,
    );
}

pub(crate) fn signal(core: &mut Core, event: &Event) {
    if event.topic != realtime::user_topic(core) || core.webrtc.state == WebRtcState::Closed {
        return;
    }
    let Some(peer) = &core.config.webrtc else {
        return;
    };
    if event.event == "webrtc:answer" {
        peer.set_remote_description(
            &text(&event.payload, "sdp"),
            &text_or(&event.payload, "type", "answer"),
        );
    } else if event.event == "webrtc:ice" {
        let candidate = text(&event.payload, "candidate");
        if !candidate.is_empty() {
            let mut mid = text(&event.payload, "sdpMid");
            if mid.is_empty() {
                mid = number(&event.payload, "sdpMLineIndex").to_string();
            }
            peer.add_remote_candidate(&candidate, &mid);
        }
    }
}

fn peer_state(core: &mut Core, peer: &str) {
    match peer {
        "connected" => set_state(core, WebRtcState::Connected),
        "failed" | "closed" | "disconnected" => {
            finish_connect(core, peer);
            fail_calls(core, peer);
            set_state(
                core,
                if peer == "failed" {
                    WebRtcState::Failed
                } else {
                    WebRtcState::Closed
                },
            );
        }
        _ => {}
    }
}

fn channel_opened(core: &mut Core, label: String) {
    core.webrtc.open.insert(label.clone(), true);
    set_state(core, WebRtcState::Connected);
    finish_connect(core, "");
    core.webrtc
        .channels
        .push(ChannelChange { label, open: true });
}

fn channel_closed(core: &mut Core, label: String) {
    core.webrtc.open.insert(label.clone(), false);
    if label == "events" {
        fail_calls(core, "closed");
    }
    core.webrtc
        .channels
        .push(ChannelChange { label, open: false });
}

fn message(core: &mut Core, label: String, data: Vec<u8>, binary: bool) {
    if label == "events" && reply(core, &data, binary) {
        return;
    }
    core.webrtc.data.push(DataMessage {
        label,
        data,
        binary,
    });
}

// A hook reply on `events`, matched to its call. False for anything else.
fn reply(core: &mut Core, data: &[u8], binary: bool) -> bool {
    let mut result = HookResult::default();
    let position;
    if protobuf(core) {
        if !binary {
            return false;
        }
        let decoded = proto::find("RtcEnvelope")
            .and_then(|envelope| proto::decode(envelope, data, false, None));
        let Some(decoded) = decoded else {
            return false;
        };
        let body = if let Some(body) = decoded.get("hook_reply") {
            result.ok = true;
            if body.get("data_raw").is_some() {
                // A typed hook's reply: the bytes as the plugin encoded them.
                result.bytes = proto::unbase64(&text(body, "data_raw")).unwrap_or_default();
            } else {
                result.data = field(body, "data").clone();
            }
            body
        } else if let Some(body) = decoded.get("hook_error") {
            result.error = text_or(body, "error", "hook_error");
            body
        } else {
            return false;
        };
        let id = number(body, "id") as u32;
        position = core.webrtc.calls.iter().position(|call| call.id == id);
    } else {
        if binary {
            return false;
        }
        let message = parse(data).unwrap_or(Value::Null);
        let kind = text(&message, "type");
        if kind != "hook_reply" && kind != "hook_error" {
            return false;
        }
        let plugin = text(&message, "plugin");
        let function = text(&message, "fn");
        position = core
            .webrtc
            .calls
            .iter()
            .position(|call| call.plugin == plugin && call.function == function);
        result.ok = kind == "hook_reply";
        if result.ok {
            result.data = field(&message, "data").clone();
        } else {
            result.error = text_or(&message, "error", "hook_error");
        }
    }
    let Some(position) = position else {
        return true;
    };
    let call = core.webrtc.calls.remove(position);
    core.cancel(call.timer);
    core.complete(call.done, result);
    true
}

fn start_call(
    core: &mut Core,
    plugin: &str,
    function: &str,
    args: &Value,
    raw: Option<Vec<u8>>,
    done: Completer<HookResult>,
) {
    let mut refused = "not_open";
    let mut sent = false;
    let mut id = 0;
    if raw.is_some() && !protobuf(core) {
        refused = "needs_protobuf";
    } else if channel_open(core, "events") {
        if let Some(peer) = core.config.webrtc.clone() {
            if protobuf(core) {
                id = core.webrtc.next_call;
                core.webrtc.next_call += 1;
                let mut body = json!({ "id": id, "plugin": plugin, "fn": function });
                match raw {
                    // Raw bytes need not be valid UTF-8, so they cannot ride in
                    // a JSON string on their way to the encoder.
                    Some(bytes) => body["args_raw"] = json!(bytes),
                    None => body["args_json"] = json!(dump(args)),
                }
                if let Some(envelope) = proto::find("RtcEnvelope") {
                    let wire = proto::encode(envelope, &json!({ "call_hook": body }));
                    sent = peer.send("events", &wire, true);
                }
            } else {
                let message =
                    json!({ "type": "call_hook", "plugin": plugin, "fn": function, "args": args });
                sent = peer.send("events", dump(&message).as_bytes(), false);
            }
        }
    }
    if !sent {
        let result = HookResult {
            error: refused.to_string(),
            ..HookResult::default()
        };
        core.complete(done, result);
        return;
    }
    let serial = core.webrtc.next_serial;
    core.webrtc.next_serial += 1;
    let timeout = core.config.push_timeout;
    let timer = core.after(timeout, move |core| {
        let Some(position) = core.webrtc.calls.iter().position(|c| c.serial == serial) else {
            return;
        };
        let call = core.webrtc.calls.remove(position);
        let result = HookResult {
            error: "timeout".to_string(),
            ..HookResult::default()
        };
        core.complete(call.done, result);
    });
    core.webrtc.calls.push(Call {
        serial,
        id,
        plugin: plugin.to_string(),
        function: function.to_string(),
        done,
        timer,
    });
}

fn finish_connect(core: &mut Core, error: &str) {
    let timer = mem::take(&mut core.webrtc.connect_timer);
    core.cancel(timer);
    if let Some(done) = core.webrtc.connecting.take() {
        let result = if error.is_empty() {
            Ok(())
        } else {
            Err(error.to_string())
        };
        core.complete(done, result);
    }
}

fn fail_calls(core: &mut Core, error: &str) {
    for call in mem::take(&mut core.webrtc.calls) {
        core.cancel(call.timer);
        let result = HookResult {
            error: error.to_string(),
            ..HookResult::default()
        };
        core.complete(call.done, result);
    }
}

fn set_state(core: &mut Core, state: WebRtcState) {
    if core.webrtc.state == state {
        return;
    }
    core.webrtc.state = state;
    core.webrtc.states.push(state);
}
