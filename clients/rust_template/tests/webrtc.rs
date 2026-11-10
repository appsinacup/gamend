mod harness;

use gamend::detail::proto;
use gamend::{json, DataMessage, RealtimeFormat, Ticket, Value, WebRtcState};
use harness::{got, message, parsed, reply_to, secs, Harness};

// Offer, answer, one channel open: connected.
fn connect_all(h: &Harness) -> Ticket<Result<(), String>> {
    let ticket = h.client.webrtc().connect();
    h.peer.offer("v=0 offer");
    h.poll();
    let offer = h.frames().remove(0);
    h.socket.receive(&reply_to(&offer, "ok", json!({})));
    h.peer.open_channel("events");
    h.poll();
    ticket
}

fn envelope() -> &'static proto::Message {
    proto::find("RtcEnvelope").unwrap()
}

#[test]
fn webrtc_needs_the_user_channel_and_a_peer_transport() {
    let h = Harness::new();
    let seen = h.client.webrtc().connect();
    h.poll();
    assert_eq!(got(&seen), Err("not_joined".to_string()));
    assert!(!h.peer.opened());
}

#[test]
fn the_offer_goes_over_the_user_channel_and_the_answer_and_candidates_come_back() {
    let h = Harness::connected();
    let seen = h.client.webrtc().connect();
    assert!(h.peer.opened());
    assert!(h.peer.protocol().is_empty());
    assert_eq!(
        h.peer.ice_servers(),
        vec!["stun:stun.l.google.com:19302".to_string()]
    );
    let channels = h.peer.channels();
    assert_eq!(channels.len(), 1);
    assert_eq!(channels[0].label, "events");
    assert!(channels[0].ordered);
    assert_eq!(channels[0].max_retransmits, -1);
    assert_eq!(h.client.webrtc().state(), WebRtcState::Connecting);

    h.peer.offer("v=0 offer");
    h.peer
        .candidate("candidate:1 1 UDP 1 10.0.0.1 5000 typ host", "0");
    h.poll();
    let sent = h.frames();
    assert_eq!(sent.len(), 2);
    assert_eq!(sent[0][3], json!("webrtc:offer"));
    assert_eq!(sent[0][4], json!({ "sdp": "v=0 offer", "type": "offer" }));
    assert_eq!(sent[1][3], json!("webrtc:ice"));
    assert_eq!(sent[1][4]["sdpMid"], json!("0"));
    h.socket.receive(&reply_to(&sent[0], "ok", json!({})));

    h.socket.receive(&message(
        "user:u1",
        "webrtc:answer",
        json!({ "sdp": "v=0 answer", "type": "answer" }),
    ));
    h.socket.receive(&message(
        "user:u1",
        "webrtc:ice",
        json!({ "candidate": "candidate:2 1 UDP 1 10.0.0.2 6000 typ host",
                "sdpMid": "0", "sdpMLineIndex": 0 }),
    ));
    h.poll();
    assert_eq!(
        h.peer.remote(),
        ("v=0 answer".to_string(), "answer".to_string())
    );
    assert_eq!(h.peer.candidates().len(), 1);
    assert_eq!(h.peer.candidates()[0].1, "0");
    assert!(!seen.is_ready());

    h.peer.open_channel("events");
    h.poll();
    assert_eq!(got(&seen), Ok(()));
    assert_eq!(h.client.webrtc().state(), WebRtcState::Connected);
    assert!(h.client.webrtc().channel_open("events"));
    assert!(!h.client.webrtc().channel_open("state"));
}

#[test]
fn hooks_over_the_events_channel_json_matched_by_plugin_and_function() {
    let h = Harness::connected();
    connect_all(&h);
    let seen = h
        .client
        .webrtc()
        .call_hook("arena", "move", json!({ "x": 1 }));
    let sent = h.peer.sent();
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0].label, "events");
    assert!(!sent[0].binary);
    assert_eq!(
        parsed(&sent[0].data),
        json!({ "type": "call_hook", "plugin": "arena", "fn": "move", "args": [{ "x": 1 }] })
    );

    h.peer
        .receive("events", br#"{"type":"game_event","n":1}"#, false);
    h.peer.receive(
        "events",
        br#"{"type":"hook_reply","plugin":"arena","fn":"move","data":42}"#,
        false,
    );
    h.poll();
    let result = got(&seen);
    assert!(result.ok);
    assert_eq!(result.data, json!(42));
    let data = h.client.webrtc().data();
    assert_eq!(
        data,
        vec![DataMessage {
            label: "events".to_string(),
            data: br#"{"type":"game_event","n":1}"#.to_vec(),
            binary: false,
        }]
    );

    let seen = h.client.webrtc().call_hook("arena", "nope", json!([]));
    h.peer.receive(
        "events",
        br#"{"type":"hook_error","plugin":"arena","fn":"nope","error":"boom"}"#,
        false,
    );
    h.poll();
    let result = got(&seen);
    assert!(!result.ok);
    assert_eq!(result.error, "boom");
}

#[test]
fn hooks_over_the_events_channel_protobuf_envelopes_with_request_ids() {
    let h = Harness::connected_with(RealtimeFormat::Protobuf);
    connect_all(&h);
    assert_eq!(h.peer.protocol(), "protobuf");
    let first = h.client.webrtc().call_hook("arena", "move", json!([1]));
    let second = h.client.webrtc().call_hook("arena", "move", json!([2]));
    let sent = h.peer.sent();
    assert_eq!(sent.len(), 2);
    assert!(sent[0].binary);
    let call = proto::decode(envelope(), &sent[1].data, false, None).unwrap();
    assert_eq!(call["call_hook"]["id"], json!(2));
    assert_eq!(call["call_hook"]["args"], json!([2]));

    // Out of order, told apart by id.
    h.peer.receive(
        "events",
        &proto::encode(
            envelope(),
            &json!({ "hook_reply": { "id": 2, "data_json": "\"two\"" } }),
        ),
        true,
    );
    h.peer.receive(
        "events",
        &proto::encode(
            envelope(),
            &json!({ "hook_error": { "id": 1, "error": "nope" } }),
        ),
        true,
    );
    h.poll();
    let second = got(&second);
    assert!(second.ok);
    assert_eq!(second.data, json!("two"));
    let first = got(&first);
    assert!(!first.ok);
    assert_eq!(first.error, "nope");
}

#[test]
fn an_offer_the_server_refuses_fails_the_connect() {
    let h = Harness::connected();
    let seen = h.client.webrtc().connect();
    h.peer.offer("v=0");
    h.poll();
    let offer = h.frames().remove(0);
    h.socket.receive(&reply_to(
        &offer,
        "error",
        json!({ "error": "webrtc_disabled" }),
    ));
    h.poll();
    assert_eq!(got(&seen), Err("webrtc_disabled".to_string()));
    assert_eq!(h.client.webrtc().state(), WebRtcState::Failed);
}

#[test]
fn a_connection_that_never_opens_a_channel_times_out() {
    let h = Harness::connected();
    let seen = h.client.webrtc().connect();
    h.advance(secs(15));
    assert_eq!(got(&seen), Err("timeout".to_string()));
    assert_eq!(h.client.webrtc().state(), WebRtcState::Failed);
    assert!(h.peer.closes() >= 1);
}

#[test]
fn close_tells_the_server_and_losing_the_socket_closes_too() {
    let h = Harness::connected();
    connect_all(&h);
    h.frames();
    h.client.webrtc().close();
    let sent = h.frames();
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0][3], json!("webrtc:close"));
    assert_eq!(h.client.webrtc().state(), WebRtcState::Closed);
    assert!(!h.peer.opened());

    connect_all(&h);
    assert_eq!(h.client.webrtc().state(), WebRtcState::Connected);
    let pending = h.client.webrtc().call_hook("a", "b", json!([]));
    h.socket.drop_connection();
    h.poll();
    assert_eq!(h.client.webrtc().state(), WebRtcState::Closed);
    assert_eq!(got(&pending).error, "closed");
}

#[test]
fn a_typed_hook_sends_raw_bytes_and_answers_raw_bytes_in_protobuf_mode_only() {
    let h = Harness::connected_with(RealtimeFormat::Protobuf);
    connect_all(&h);
    // Bytes that are not valid UTF-8 go as they are.
    let seen = h
        .client
        .webrtc()
        .call_hook_raw("arena", "move", vec![0x08, 0xFF]);
    let sent = h.peer.sent();
    let decoded = proto::decode(envelope(), &sent.last().unwrap().data, false, None).unwrap();
    assert_eq!(
        decoded["call_hook"]["args_raw"],
        Value::String(proto::base64(&[0x08, 0xFF]))
    );
    h.peer.receive(
        "events",
        &proto::encode(
            envelope(),
            &json!({ "hook_reply": { "id": 1, "data_raw": "\u{10}\u{02}" } }),
        ),
        true,
    );
    h.poll();
    let result = got(&seen);
    assert!(result.ok);
    assert_eq!(result.bytes, vec![0x10, 0x02]);

    let json_mode = Harness::connected();
    connect_all(&json_mode);
    let seen = json_mode
        .client
        .webrtc()
        .call_hook_raw("arena", "move", b"x".to_vec());
    json_mode.poll();
    assert_eq!(got(&seen).error, "needs_protobuf");
}

#[test]
fn channels_report_opening_and_closing() {
    let h = Harness::connected();
    connect_all(&h);
    h.peer.close_channel("events");
    h.poll();
    let changes = h.client.webrtc().channel_changes();
    assert_eq!(changes.len(), 2);
    assert!(changes[0].open);
    assert!(!changes[1].open);
    assert!(!h.client.webrtc().channel_open("events"));
}
