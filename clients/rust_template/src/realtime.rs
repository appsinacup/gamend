//! The realtime connection: Phoenix channels over the WebSocket transport.
//!
//! A dropped connection reconnects on its own, with a fresh token when the old
//! one would not do, and rejoins every topic it had; `state_changes` says when.
//! Events are drained, not delivered: `events()` hands back what arrived, so a
//! system can read them with `&mut` access to its world. The methods are safe
//! to call from any thread.

use std::collections::BTreeMap;
use std::mem;
use std::sync::Arc;
use std::time::Duration;

use serde_json::{json, Value};

use crate::client::{LogLevel, RealtimeFormat};
use crate::core::{Core, Queue, Shared};
use crate::generated::events;
use crate::json::{field, text, text_or};
use crate::phoenix::{Frame, FrameKind, Heartbeat, Phoenix, HEARTBEAT};
use crate::proto;
use crate::query::escape;
use crate::session::Session;
use crate::ticket::Ticket;
use crate::transport::{WebSocketEvent, WebSocketHandlers};
use crate::{auth, kv, presence, webrtc};

// How long a channel that errored waits before it tries to join again.
const REJOIN: Duration = Duration::from_secs(1);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RealtimeState {
    /// Not connected, and not trying: before `connect()`, after `disconnect()`
    /// or a sign-out.
    Disconnected,
    /// Opening the first connection.
    Connecting,
    /// Open; topics are (re)joining or joined.
    Connected,
    /// The connection dropped; the next attempt is scheduled or under way.
    Reconnecting,
}

/// A message the server pushed on a topic.
#[derive(Clone, Debug, PartialEq)]
pub struct Event {
    pub topic: String,
    /// The event as the server named it (`updated`, `user_joined`, ...).
    pub event: String,
    /// What this SDK calls it: one of `gamend::events`, or `events::MESSAGE` for
    /// an event the table does not name.
    pub kind: &'static str,
    /// The payload. Null for a binary payload nothing decoded; see `bytes`.
    pub payload: Value,
    /// A binary payload this SDK could not decode, as it arrived.
    pub bytes: Vec<u8>,
    /// It arrived as a protobuf frame (`RealtimeFormat::Protobuf`), decoded or
    /// not.
    pub binary: bool,
}

/// The server's answer to a join, leave or push.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Reply {
    /// The server said "ok".
    pub ok: bool,
    /// "ok" or "error" from the server; "timeout", "disconnected" or
    /// "not_joined" when no answer came.
    pub status: String,
    /// What the server answered.
    pub response: Value,
    /// Empty when `ok`; otherwise `response.error` or `response.reason`, or the
    /// status.
    pub error: String,
}

/// A server hook's answer.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct HookResult {
    pub ok: bool,
    /// What the hook returned.
    pub data: Value,
    /// A typed hook's reply bytes (`WebRtc::call_hook_raw`), undecoded.
    pub bytes: Vec<u8>,
    /// Why it failed: the hook's error, `timeout`, `not_joined`, ...
    pub error: String,
}

/// Reads a game's own protobuf bytes into a value (usually with the game's
/// protobuf library), or nothing when they do not decode. It runs while the
/// client's state is held, so it must not call the client.
pub type BytesDecoder = Arc<dyn Fn(&[u8]) -> Option<Value> + Send + Sync>;

pub(crate) type ReplyFn = Box<dyn FnOnce(&mut Core, Reply) + Send>;

struct Topic {
    name: String,
    params: Value,
    joined: bool,
    // A join frame is out and its reply has not come.
    joining: bool,
    // What `join` callers wait on: the next join reply.
    waiting: Vec<ReplyFn>,
    rejoin_timer: u64,
}

struct Pending {
    topic: String,
    join: bool,
    done: Option<ReplyFn>,
    timer: u64,
}

pub(crate) struct State {
    phoenix: Phoenix,
    state: RealtimeState,
    // connect() was called and not undone.
    wanted: bool,
    // The current attempt series has opened once.
    ever_opened: bool,
    // The last connection opened before it dropped.
    last_opened: bool,
    generation: u64,
    attempt: usize,
    heartbeat_timer: u64,
    reconnect_timer: u64,
    user_id: String,
    topics: Vec<Topic>,
    pending: BTreeMap<String, Pending>,
    events: Queue<Event>,
    states: Queue<RealtimeState>,
    metadata_decoders: BTreeMap<String, BytesDecoder>,
    kv_decoders: BTreeMap<String, BytesDecoder>,
}

impl State {
    pub(crate) fn new(limit: usize) -> Self {
        Self {
            phoenix: Phoenix::new(),
            state: RealtimeState::Disconnected,
            wanted: false,
            ever_opened: false,
            last_opened: false,
            generation: 0,
            attempt: 0,
            heartbeat_timer: 0,
            reconnect_timer: 0,
            user_id: String::new(),
            topics: Vec::new(),
            pending: BTreeMap::new(),
            events: Queue::new(limit),
            states: Queue::new(limit),
            metadata_decoders: BTreeMap::new(),
            kv_decoders: BTreeMap::new(),
        }
    }

    fn find(&mut self, name: &str) -> Option<&mut Topic> {
        self.topics.iter_mut().find(|topic| topic.name == name)
    }

    fn forget(&mut self, name: &str) {
        self.topics.retain(|topic| topic.name != name);
    }
}

fn reply_of(status: &str, response: Value) -> Reply {
    let ok = status == "ok";
    let error = if ok {
        String::new()
    } else {
        let reason = text_or(&response, "reason", status);
        text_or(&response, "error", &reason)
    };
    Reply {
        ok,
        status: status.to_string(),
        response,
        error,
    }
}

fn local_reply(status: &str) -> Reply {
    reply_of(status, json!({}))
}

/// The realtime connection: channels, events, server hooks.
#[derive(Clone)]
pub struct Realtime {
    shared: Arc<Shared>,
}

impl Realtime {
    pub(crate) fn new(shared: Arc<Shared>) -> Self {
        Self { shared }
    }

    /// Open the connection for the signed-in player and join `user:<id>`. Stays
    /// connected, reconnecting as needed, until `disconnect()` or a sign-out.
    pub fn connect(&self) {
        self.shared.with(|core| {
            if core.realtime.wanted {
                return;
            }
            core.realtime.wanted = true;
            core.realtime.ever_opened = false;
            core.realtime.attempt = 0;
            open(core);
        });
    }

    /// Close the connection and forget every topic. No reconnect.
    pub fn disconnect(&self) {
        self.shared.with(disconnect);
    }

    pub fn state(&self) -> RealtimeState {
        self.shared.with(|core| core.realtime.state)
    }

    /// Join `topic`, now or as soon as the connection is open, and again after
    /// every reconnect until `leave`. The ticket gets the first join's reply.
    pub fn join(&self, name: &str, params: Value) -> Ticket<Reply> {
        self.shared.start(|core, ticket| {
            let done: ReplyFn = Box::new(move |core, reply| core.complete(ticket, reply));
            let Some(topic) = core.realtime.find(name) else {
                core.realtime.topics.push(Topic {
                    name: name.to_string(),
                    params: if params.is_object() {
                        params
                    } else {
                        json!({})
                    },
                    joined: false,
                    joining: false,
                    waiting: vec![done],
                    rejoin_timer: 0,
                });
                if core.realtime.state == RealtimeState::Connected {
                    send_join(core, name);
                }
                return;
            };
            if topic.joined {
                core.post(move |core| done(core, reply_of("ok", json!({}))));
                return;
            }
            topic.waiting.push(done);
            let joining = topic.joining;
            if core.realtime.state == RealtimeState::Connected && !joining {
                send_join(core, name);
            }
        })
    }

    pub fn leave(&self, name: &str) -> Ticket<Reply> {
        self.shared.start(|core, ticket| {
            let mut joined = false;
            let mut waiting = Vec::new();
            let mut timer = 0;
            if let Some(topic) = core.realtime.find(name) {
                joined = topic.joined;
                timer = topic.rejoin_timer;
                waiting = mem::take(&mut topic.waiting);
                core.realtime.forget(name);
            }
            core.cancel(timer);
            for waiter in waiting {
                waiter(core, local_reply("left"));
            }
            let frame = if joined {
                core.realtime.phoenix.leave(name)
            } else {
                None
            };
            let done: ReplyFn = Box::new(move |core, reply| core.complete(ticket, reply));
            let Some((reference, frame_text)) = frame else {
                core.post(move |core| done(core, reply_of("ok", json!({}))));
                return;
            };
            track(core, reference, name.to_string(), false, Some(done));
            send_text(core, frame_text);
        })
    }

    pub fn joined(&self, name: &str) -> bool {
        self.shared.with(|core| joined(core, name))
    }

    pub fn join_lobby(&self, lobby_id: &str) -> Ticket<Reply> {
        self.join(&format!("lobby:{lobby_id}"), json!({}))
    }

    pub fn join_lobbies(&self) -> Ticket<Reply> {
        self.join("lobbies", json!({}))
    }

    pub fn join_group(&self, group_id: &str) -> Ticket<Reply> {
        self.join(&format!("group:{group_id}"), json!({}))
    }

    pub fn join_groups(&self) -> Ticket<Reply> {
        self.join("groups", json!({}))
    }

    pub fn join_party(&self, party_id: &str) -> Ticket<Reply> {
        self.join(&format!("party:{party_id}"), json!({}))
    }

    /// Send `event` to a joined topic. The ticket gets the server's reply, or
    /// `timeout` after `Config::push_timeout`.
    pub fn push(&self, topic: &str, event: &str, payload: Value) -> Ticket<Reply> {
        self.shared.start(|core, ticket| {
            push(
                core,
                topic,
                event,
                &payload,
                Some(Box::new(move |core, reply| core.complete(ticket, reply))),
            );
        })
    }

    /// Call a server hook over the user channel. `args` that is not an array
    /// goes as its one element.
    pub fn call_hook(&self, plugin: &str, function: &str, args: Value) -> Ticket<HookResult> {
        let payload = json!({ "plugin": plugin, "fn": function, "args": args_of(args) });
        self.shared.start(|core, ticket| {
            let topic = user_topic(core);
            push(
                core,
                &topic,
                "call_hook",
                &payload,
                Some(Box::new(move |core, reply| {
                    let data = if reply.ok {
                        field(&reply.response, "data").clone()
                    } else {
                        Value::Null
                    };
                    let result = HookResult {
                        ok: reply.ok,
                        data,
                        bytes: Vec::new(),
                        error: reply.error,
                    };
                    core.complete(ticket, result);
                })),
            );
        })
    }

    /// What arrived since the last call, on every topic, oldest first.
    pub fn events(&self) -> Vec<Event> {
        self.shared
            .with(|core| core.drained(|core| &mut core.realtime.events))
    }

    /// Every change of `state()` since the last call.
    pub fn state_changes(&self) -> Vec<RealtimeState> {
        self.shared
            .with(|core| core.drained(|core| &mut core.realtime.states))
    }

    /// `user:<id>` of the signed-in player, or empty.
    pub fn user_topic(&self) -> String {
        self.shared.with(|core| user_topic(core))
    }

    /// With `RealtimeFormat::Protobuf`, the server sends metadata that fits the
    /// game plugin's registered schema (`UserMeta`, `LobbyMeta`, ...) as bytes,
    /// `metadata_pb`. This reads an entity's (`user`, `lobby`, `group`, `party`)
    /// into `metadata`; unread, it stays base64 as `metadata_pb`.
    pub fn register_metadata_decoder(&self, entity: &str, decoder: BytesDecoder) {
        self.shared.with(|core| {
            core.realtime
                .metadata_decoders
                .insert(entity.to_string(), decoder);
        });
    }

    /// The same for KV data sent as `data_pb` (the plugin's `kv_schemas/0`): an
    /// exact key, or a `prefix*` pattern. An exact key wins over a pattern, a
    /// longer pattern over a shorter one.
    pub fn register_kv_decoder(&self, pattern: &str, decoder: BytesDecoder) {
        self.shared.with(|core| {
            core.realtime
                .kv_decoders
                .insert(pattern.to_string(), decoder);
        });
    }
}

pub(crate) fn args_of(args: Value) -> Value {
    match args {
        Value::Array(_) => args,
        Value::Null => json!([]),
        other => json!([other]),
    }
}

pub(crate) fn user_topic(core: &Core) -> String {
    core.auth
        .session
        .as_ref()
        .map_or_else(String::new, |session| format!("user:{}", session.user_id))
}

pub(crate) fn joined(core: &Core, name: &str) -> bool {
    core.realtime
        .topics
        .iter()
        .any(|topic| topic.name == name && topic.joined)
}

fn send_text(core: &Core, frame: String) {
    if let Some(socket) = &core.config.websocket {
        socket.send_text(frame);
    }
}

fn disconnect(core: &mut Core) {
    core.realtime.wanted = false;
    close_socket(core);
    let topics = mem::take(&mut core.realtime.topics);
    let mut waiting = Vec::new();
    for topic in topics {
        core.cancel(topic.rejoin_timer);
        waiting.extend(topic.waiting);
    }
    for done in waiting {
        done(core, local_reply("disconnected"));
    }
    set_state(core, RealtimeState::Disconnected);
}

fn close_socket(core: &mut Core) {
    // Whatever the old socket still reports is about nothing now.
    core.realtime.generation += 1;
    let heartbeat = mem::take(&mut core.realtime.heartbeat_timer);
    let reconnect = mem::take(&mut core.realtime.reconnect_timer);
    core.cancel(heartbeat);
    core.cancel(reconnect);
    if let Some(socket) = &core.config.websocket {
        socket.close();
    }
    for topic in &mut core.realtime.topics {
        topic.joined = false;
        topic.joining = false;
    }
    fail_pending(core, "disconnected");
}

fn url(core: &Core) -> String {
    let base = &core.base_url;
    let mut out = if let Some(rest) = base.strip_prefix("https://") {
        format!("wss://{rest}")
    } else if let Some(rest) = base.strip_prefix("http://") {
        format!("ws://{rest}")
    } else {
        base.clone()
    };
    let token = core
        .auth
        .session
        .as_ref()
        .map_or("", |session| session.access_token.as_str());
    out.push_str("/socket/websocket?vsn=2.0.0");
    out.push_str(&format!("&token={}", escape(token)));
    out.push_str(&format!("&client_session={}", escape(&core.run_id)));
    if core.config.realtime_format == RealtimeFormat::Protobuf {
        out.push_str("&format=protobuf");
    }
    out
}

fn open(core: &mut Core) {
    if !core.realtime.wanted {
        return;
    }
    let (Some(socket), Some(session)) = (core.config.websocket.clone(), core.auth.session.clone())
    else {
        let line = if core.config.websocket.is_none() {
            "gamend: realtime has no WebSocket transport"
        } else {
            "gamend: realtime needs a signed-in player"
        };
        core.log(LogLevel::Error, line);
        core.realtime.wanted = false;
        set_state(core, RealtimeState::Disconnected);
        return;
    };
    if !core.realtime.user_id.is_empty() && session.user_id != core.realtime.user_id {
        // Another player: their channels, none of the last one's.
        let topics = mem::take(&mut core.realtime.topics);
        let mut waiting = Vec::new();
        for topic in topics {
            core.cancel(topic.rejoin_timer);
            waiting.extend(topic.waiting);
        }
        for done in waiting {
            done(core, local_reply("disconnected"));
        }
    }
    core.realtime.user_id.clone_from(&session.user_id);
    let user = format!("user:{}", session.user_id);
    if core.realtime.find(&user).is_none() {
        core.realtime.topics.insert(
            0,
            Topic {
                name: user,
                params: json!({}),
                joined: false,
                joining: false,
                waiting: Vec::new(),
                rejoin_timer: 0,
            },
        );
    }

    core.realtime.generation += 1;
    let generation = core.realtime.generation;
    core.realtime.last_opened = false;
    let next = if core.realtime.ever_opened {
        RealtimeState::Reconnecting
    } else {
        RealtimeState::Connecting
    };
    set_state(core, next);
    let post = core.poster();
    let handlers = WebSocketHandlers::new(move |event| {
        post.post(move |core| match event {
            WebSocketEvent::Open => opened(core, generation),
            WebSocketEvent::Text(text) => received(core, generation, &text),
            WebSocketEvent::Binary(bytes) => received_binary(core, generation, &bytes),
            WebSocketEvent::Close { code, reason } => {
                dropped(core, generation, &format!("closed ({code}) {reason}"));
            }
            WebSocketEvent::Error(error) => dropped(core, generation, &error),
        });
    });
    socket.open(&url(core), handlers);
}

fn opened(core: &mut Core, generation: u64) {
    if generation != core.realtime.generation {
        return;
    }
    core.realtime.ever_opened = true;
    core.realtime.last_opened = true;
    core.realtime.attempt = 0;
    let now = core.now();
    core.realtime.phoenix.reset(now);
    set_state(core, RealtimeState::Connected);
    let names: Vec<String> = core
        .realtime
        .topics
        .iter()
        .map(|topic| topic.name.clone())
        .collect();
    for name in names {
        send_join(core, &name);
    }
    schedule_heartbeat(core);
}

fn send_join(core: &mut Core, name: &str) {
    let Some(topic) = core.realtime.find(name) else {
        return;
    };
    let timer = mem::take(&mut topic.rejoin_timer);
    let params = topic.params.clone();
    topic.joining = true;
    topic.joined = false;
    core.cancel(timer);
    let (reference, frame) = core.realtime.phoenix.join(name, &params);
    track(core, reference, name.to_string(), true, None);
    send_text(core, frame);
}

fn schedule_heartbeat(core: &mut Core) {
    let timer = core.realtime.heartbeat_timer;
    core.cancel(timer);
    let generation = core.realtime.generation;
    core.realtime.heartbeat_timer = core.after(HEARTBEAT, move |core| {
        if generation != core.realtime.generation {
            return;
        }
        let now = core.now();
        match core.realtime.phoenix.heartbeat(now) {
            Heartbeat::Dead => {
                core.log(
                    LogLevel::Warning,
                    "gamend: the server missed a heartbeat; reconnecting",
                );
                close_socket(core);
                schedule_reconnect(core);
            }
            Heartbeat::Beat(frame) => {
                send_text(core, frame);
                schedule_heartbeat(core);
            }
            Heartbeat::Wait => schedule_heartbeat(core),
        }
    });
}

fn received(core: &mut Core, generation: u64, text: &str) {
    if generation != core.realtime.generation {
        return;
    }
    if let Some(decoded) = core.realtime.phoenix.decode(text) {
        frame(core, decoded);
    }
}

fn received_binary(core: &mut Core, generation: u64, bytes: &[u8]) {
    if generation != core.realtime.generation {
        return;
    }
    if let Some(decoded) = core.realtime.phoenix.decode_binary(bytes) {
        frame(core, decoded);
    }
}

fn frame(core: &mut Core, frame: Frame) {
    if frame.kind == FrameKind::Reply {
        reply(core, frame);
        return;
    }

    if frame.event == "phx_error" {
        // The channel crashed on the server; Phoenix's clients join it again.
        if let Some(topic) = core.realtime.find(&frame.topic) {
            topic.joined = false;
            topic.joining = false;
            schedule_rejoin(core, &frame.topic);
        }
    } else if frame.event == "phx_close" {
        // The server closed the channel (a kick, a disband): not rejoined.
        core.realtime.forget(&frame.topic);
    }

    let kind = events::signal_of(&frame.topic, &frame.event);
    let binary = frame.bytes.is_some();
    let mut payload = Value::Null;
    let mut undecoded = Vec::new();
    if let Some(bytes) = frame.bytes {
        match decode_event(core, &frame.topic, &frame.event, &bytes) {
            Some(decoded) => payload = decoded,
            None => {
                core.log(
                    LogLevel::Warning,
                    format!(
                        "gamend: no decoder for the binary {} on {}",
                        frame.event, frame.topic
                    ),
                );
                undecoded = bytes;
            }
        }
    } else {
        payload = frame.payload;
    }
    emit(
        core,
        Event {
            topic: frame.topic,
            event: frame.event,
            kind,
            payload,
            bytes: undecoded,
            binary,
        },
    );
}

fn decode_event(core: &Core, topic: &str, event: &str, bytes: &[u8]) -> Option<Value> {
    let metadata = &core.realtime.metadata_decoders;
    let kv_decoders = &core.realtime.kv_decoders;
    let hook = |message: &str, field: &str, bytes: &[u8], decoded: &Value| -> Option<Value> {
        if field == "metadata_pb" {
            // The message a metadata map rides in names whose it is.
            let entity = match message {
                "Lobby" => "lobby",
                "Group" => "group",
                "Party" => "party",
                _ => "user",
            };
            return metadata.get(entity).and_then(|decoder| decoder(bytes));
        }
        if field == "data_pb" && message == "KvEntry" {
            let key = text(decoded, "key");
            if let Some(exact) = kv_decoders.get(&key) {
                return exact(bytes);
            }
            let mut best: Option<(&BytesDecoder, usize)> = None;
            for (pattern, decoder) in kv_decoders {
                if let Some(prefix) = pattern.strip_suffix('*') {
                    let longer = best.is_none_or(|(_, length)| prefix.len() >= length);
                    if longer && key.starts_with(prefix) {
                        best = Some((decoder, prefix.len()));
                    }
                }
            }
            return best.and_then(|(decoder, _)| decoder(bytes));
        }
        None
    };
    proto::decode_binary_event(topic, event, bytes, Some(&hook))
}

fn reply(core: &mut Core, frame: Frame) {
    let Some(pending) = core.realtime.pending.remove(&frame.reference) else {
        return;
    };
    core.cancel(pending.timer);
    let response = if frame.bytes.is_some() {
        Value::Null
    } else {
        frame.payload
    };
    let answer = reply_of(&frame.status, response);
    if pending.join {
        let mut waiting = Vec::new();
        if let Some(topic) = core.realtime.find(&pending.topic) {
            topic.joining = false;
            topic.joined = answer.ok;
            waiting = mem::take(&mut topic.waiting);
            if !answer.ok {
                core.log(
                    LogLevel::Warning,
                    format!("gamend: joining {} failed: {}", pending.topic, answer.error),
                );
                // A refusal the server will repeat: stop asking.
                if matches!(
                    answer.error.as_str(),
                    "unauthorized" | "forbidden" | "not_found" | "invalid topic"
                ) {
                    core.realtime.forget(&pending.topic);
                } else {
                    schedule_rejoin(core, &pending.topic);
                }
            }
        }
        if answer.ok && pending.topic == format!("user:{}", core.realtime.user_id) {
            kv::user_channel_joined(core);
        }
        for done in waiting {
            done(core, answer.clone());
        }
    }
    if let Some(done) = pending.done {
        done(core, answer);
    }
}

fn emit(core: &mut Core, event: Event) {
    // The SDK's own bookkeeping first, so a game that reads this event finds the
    // row and the roster already up to date.
    kv::event(core, event.kind, &event.payload);
    presence::event(core, event.kind, &event.payload);
    webrtc::signal(core, &event);
    core.realtime.events.push(event);
}

fn schedule_rejoin(core: &mut Core, name: &str) {
    let Some(topic) = core.realtime.find(name) else {
        return;
    };
    let previous = topic.rejoin_timer;
    core.cancel(previous);
    let generation = core.realtime.generation;
    let again = name.to_string();
    let timer = core.after(REJOIN, move |core| {
        if generation != core.realtime.generation || core.realtime.state != RealtimeState::Connected
        {
            return;
        }
        let waiting = core
            .realtime
            .find(&again)
            .is_some_and(|topic| !topic.joined && !topic.joining);
        if waiting {
            send_join(core, &again);
        }
    });
    if let Some(topic) = core.realtime.find(name) {
        topic.rejoin_timer = timer;
    }
}

fn dropped(core: &mut Core, generation: u64, why: &str) {
    if generation != core.realtime.generation {
        return;
    }
    core.log(
        LogLevel::Info,
        format!("gamend: realtime connection lost: {why}"),
    );
    close_socket(core);
    schedule_reconnect(core);
}

fn schedule_reconnect(core: &mut Core) {
    if !core.realtime.wanted {
        set_state(core, RealtimeState::Disconnected);
        return;
    }
    let next = if core.realtime.ever_opened {
        RealtimeState::Reconnecting
    } else {
        RealtimeState::Connecting
    };
    set_state(core, next);
    let delays = &core.config.reconnect_delays;
    let delay = if delays.is_empty() {
        Duration::from_secs(1)
    } else {
        delays[core.realtime.attempt.min(delays.len() - 1)]
    };
    core.realtime.attempt += 1;
    let refresh_first = !core.realtime.last_opened;
    core.realtime.reconnect_timer = core.after(delay, move |core| {
        core.realtime.reconnect_timer = 0;
        if !core.realtime.wanted {
            return;
        }
        if refresh_first {
            // The last attempt never opened: the token may have lapsed while
            // the network was away. Refresh it first; open either way.
            auth::refresh_then(core, Box::new(|core, _| open(core)));
        } else {
            open(core);
        }
    });
}

fn fail_pending(core: &mut Core, status: &str) {
    let pending = mem::take(&mut core.realtime.pending);
    let mut waiting = Vec::new();
    for entry in pending.into_values() {
        core.cancel(entry.timer);
        if entry.join {
            if let Some(topic) = core.realtime.find(&entry.topic) {
                // A join waiting on this connection waits on the next one.
                topic.joining = false;
            }
        }
        waiting.extend(entry.done);
    }
    for done in waiting {
        done(core, local_reply(status));
    }
}

fn track(core: &mut Core, reference: String, topic: String, join: bool, done: Option<ReplyFn>) {
    let timeout = core.config.push_timeout;
    let key = reference.clone();
    let timer = core.after(timeout, move |core| timed_out(core, &key));
    core.realtime.pending.insert(
        reference,
        Pending {
            topic,
            join,
            done,
            timer,
        },
    );
}

fn timed_out(core: &mut Core, reference: &str) {
    let Some(entry) = core.realtime.pending.remove(reference) else {
        return;
    };
    if entry.join {
        if let Some(topic) = core.realtime.find(&entry.topic) {
            topic.joining = false;
            let waiting = mem::take(&mut topic.waiting);
            schedule_rejoin(core, &entry.topic);
            for done in waiting {
                done(core, local_reply("timeout"));
            }
        }
    }
    if let Some(done) = entry.done {
        done(core, local_reply("timeout"));
    }
}

pub(crate) fn push(
    core: &mut Core,
    name: &str,
    event: &str,
    payload: &Value,
    done: Option<ReplyFn>,
) {
    let frame = if core.realtime.state == RealtimeState::Connected && joined(core, name) {
        core.realtime.phoenix.push(name, event, payload)
    } else {
        None
    };
    let Some((reference, frame_text)) = frame else {
        if let Some(done) = done {
            core.post(move |core| done(core, local_reply("not_joined")));
        }
        return;
    };
    track(core, reference, name.to_string(), false, done);
    send_text(core, frame_text);
}

pub(crate) fn session_changed(core: &mut Core, session: Option<&Session>) {
    if !core.realtime.wanted {
        return;
    }
    let Some(session) = session else {
        // Signed out: nothing to be connected as.
        disconnect(core);
        return;
    };
    if session.user_id != core.realtime.user_id {
        // Another player signed in: reconnect as them.
        close_socket(core);
        core.realtime.ever_opened = false;
        core.realtime.attempt = 0;
        open(core);
    }
}

fn set_state(core: &mut Core, state: RealtimeState) {
    if core.realtime.state == state {
        return;
    }
    core.realtime.state = state;
    core.realtime.states.push(state);
    webrtc::realtime_state_changed(core, state);
}
