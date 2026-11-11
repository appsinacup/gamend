//! Phoenix Channels, protocol V2, with no socket in it: refs, joins, the
//! heartbeat and frame decoding, fed text, bytes and a clock by `Realtime`.
//!
//! Wire shape of a text frame, both directions: `[join_ref, ref, topic, event,
//! payload]`, refs being stringified counters or null. A binary frame (the
//! server's protobuf events) is a kind byte, sizes, then the strings and the
//! payload bytes; see `Phoenix.Socket.V2.JSONSerializer`.

use std::time::Duration;

use serde_json::{json, Value};

use crate::json::{field, parse, text};

/// Phoenix's own rhythm: a beat every thirty seconds, and a beat still
/// unanswered when the next is due means the server is gone.
pub const HEARTBEAT: Duration = Duration::from_secs(30);

// Binary frame kinds, as `Phoenix.Socket.V2.JSONSerializer` numbers them.
const PUSH: u8 = 0;
const REPLY: u8 = 1;
const BROADCAST: u8 = 2;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrameKind {
    /// The reply to a join, leave or push, correlated by `reference`.
    Reply,
    /// A server-pushed event on a topic.
    Message,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Frame {
    pub kind: FrameKind,
    pub topic: String,
    /// Message: the event. Reply: empty.
    pub event: String,
    /// Reply: the ref it answers.
    pub reference: String,
    /// Reply: "ok" or "error".
    pub status: String,
    /// Message: the payload. Reply: the response.
    pub payload: Value,
    /// A binary frame's payload, undecoded. `payload` is null then.
    pub bytes: Option<Vec<u8>>,
}

impl Frame {
    fn empty() -> Self {
        Self {
            kind: FrameKind::Message,
            topic: String::new(),
            event: String::new(),
            reference: String::new(),
            status: String::new(),
            payload: Value::Null,
            bytes: None,
        }
    }
}

/// What the heartbeat asks of the connection.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Heartbeat {
    /// Not due yet.
    Wait,
    /// Send this frame.
    Beat(String),
    /// The last one went unanswered: the connection is dead.
    Dead,
}

fn frame(
    join_ref: Option<&str>,
    reference: &str,
    topic: &str,
    event: &str,
    payload: &Value,
) -> String {
    json!([join_ref, reference, topic, event, payload]).to_string()
}

// Reads length-prefixed pieces off a binary frame, refusing to run past it.
struct Reader<'a> {
    bytes: &'a [u8],
}

impl<'a> Reader<'a> {
    fn byte(&mut self) -> Option<usize> {
        let (first, rest) = self.bytes.split_first()?;
        self.bytes = rest;
        Some(usize::from(*first))
    }

    fn piece(&mut self, size: usize) -> Option<&'a [u8]> {
        if self.bytes.len() < size {
            return None;
        }
        let (piece, rest) = self.bytes.split_at(size);
        self.bytes = rest;
        Some(piece)
    }

    fn text(&mut self, size: usize) -> Option<String> {
        Some(String::from_utf8_lossy(self.piece(size)?).into_owned())
    }
}

#[derive(Debug)]
pub struct Phoenix {
    next_ref: u64,
    // Topic, and the join_ref it was joined under; Phoenix routes channel
    // traffic by it.
    joins: Vec<(String, String)>,
    last_heartbeat: u64,
    pending_heartbeat: Option<String>,
}

impl Default for Phoenix {
    fn default() -> Self {
        Self::new()
    }
}

impl Phoenix {
    pub fn new() -> Self {
        Self {
            next_ref: 1,
            joins: Vec::new(),
            last_heartbeat: 0,
            pending_heartbeat: None,
        }
    }

    fn fresh_ref(&mut self) -> String {
        let reference = self.next_ref.to_string();
        self.next_ref += 1;
        reference
    }

    fn join_ref_of(&self, topic: &str) -> Option<String> {
        self.joins
            .iter()
            .find(|(joined, _)| joined == topic)
            .map(|(_, join_ref)| join_ref.clone())
    }

    fn forget(&mut self, topic: &str) {
        self.joins.retain(|(joined, _)| joined != topic);
    }

    /// The ref its reply carries, and the frame that joins `topic`.
    pub fn join(&mut self, topic: &str, payload: &Value) -> (String, String) {
        let reference = self.fresh_ref();
        self.forget(topic);
        self.joins.push((topic.to_string(), reference.clone()));
        let text = frame(Some(&reference), &reference, topic, "phx_join", payload);
        (reference, text)
    }

    /// The frame that leaves `topic`, or nothing when it was never joined.
    pub fn leave(&mut self, topic: &str) -> Option<(String, String)> {
        let join_ref = self.join_ref_of(topic)?;
        let reference = self.fresh_ref();
        let text = frame(Some(&join_ref), &reference, topic, "phx_leave", &json!({}));
        self.forget(topic);
        Some((reference, text))
    }

    /// The frame that pushes `event` to a joined topic, or nothing when it was
    /// never joined.
    pub fn push(&mut self, topic: &str, event: &str, payload: &Value) -> Option<(String, String)> {
        let join_ref = self.join_ref_of(topic)?;
        let reference = self.fresh_ref();
        let text = frame(Some(&join_ref), &reference, topic, event, payload);
        Some((reference, text))
    }

    pub fn joined(&self, topic: &str) -> bool {
        self.joins.iter().any(|(joined, _)| joined == topic)
    }

    /// What is due at `now`, in milliseconds on the client's clock.
    pub fn heartbeat(&mut self, now: u64) -> Heartbeat {
        if now.saturating_sub(self.last_heartbeat) < HEARTBEAT.as_millis() as u64 {
            return Heartbeat::Wait;
        }
        if self.pending_heartbeat.is_some() {
            return Heartbeat::Dead;
        }
        let reference = self.fresh_ref();
        let text = frame(None, &reference, "phoenix", "heartbeat", &json!({}));
        self.pending_heartbeat = Some(reference);
        self.last_heartbeat = now;
        Heartbeat::Beat(text)
    }

    /// A text frame, decoded; nothing for internal traffic (heartbeat replies)
    /// and for text that is not a frame.
    pub fn decode(&mut self, frame_text: &str) -> Option<Frame> {
        let parts = parse(frame_text.as_bytes())?;
        let parts = parts.as_array().filter(|parts| parts.len() == 5)?;
        let piece = |i: usize| parts[i].as_str().unwrap_or_default().to_string();
        let mut out = Frame::empty();
        out.reference = piece(1);
        out.topic = piece(2);
        out.event = piece(3);

        if out.topic == "phoenix" {
            if self.pending_heartbeat.as_deref() == Some(out.reference.as_str()) {
                self.pending_heartbeat = None;
            }
            return None;
        }
        if out.event == "phx_reply" {
            let reply = &parts[4];
            out.kind = FrameKind::Reply;
            out.event.clear();
            out.status = text(reply, "status");
            out.payload = field(reply, "response").clone();
            return Some(out);
        }
        if out.event == "phx_error" || out.event == "phx_close" {
            self.forget(&out.topic);
        }
        out.payload = parts[4].clone();
        Some(out)
    }

    /// A binary frame, decoded; nothing when it is not one.
    pub fn decode_binary(&mut self, bytes: &[u8]) -> Option<Frame> {
        let mut reader = Reader { bytes };
        let mut out = Frame::empty();
        match u8::try_from(reader.byte()?).ok()? {
            PUSH => {
                let join_ref_size = reader.byte()?;
                let topic_size = reader.byte()?;
                let event_size = reader.byte()?;
                reader.piece(join_ref_size)?;
                out.topic = reader.text(topic_size)?;
                out.event = reader.text(event_size)?;
            }
            REPLY => {
                let join_ref_size = reader.byte()?;
                let ref_size = reader.byte()?;
                let topic_size = reader.byte()?;
                let status_size = reader.byte()?;
                reader.piece(join_ref_size)?;
                out.reference = reader.text(ref_size)?;
                out.topic = reader.text(topic_size)?;
                out.status = reader.text(status_size)?;
                out.kind = FrameKind::Reply;
            }
            BROADCAST => {
                let topic_size = reader.byte()?;
                let event_size = reader.byte()?;
                out.topic = reader.text(topic_size)?;
                out.event = reader.text(event_size)?;
            }
            _ => return None,
        }
        out.bytes = Some(reader.bytes.to_vec());
        Some(out)
    }

    /// Forget every join: the socket closed, and a new one starts clean.
    pub fn reset(&mut self, now: u64) {
        self.joins.clear();
        self.pending_heartbeat = None;
        self.last_heartbeat = now;
    }
}
