mod harness;

use gamend::detail::{Frame, FrameKind, Heartbeat, Phoenix};
use gamend::{commands, events, json, RealtimeState, Value};
use harness::{frame_of, got, message, ms, ok_reply, reply, secs, session_reply, Harness};

#[test]
fn the_connection_names_the_players_token_the_run_and_the_protocol_version() {
    let h = Harness::new();
    h.signed_in();
    h.client.realtime().connect();
    assert!(h.socket.opened());
    assert_eq!(
        h.socket.url(),
        "ws://game.test/socket/websocket?vsn=2.0.0&token=a1&client_session=run-1"
    );
    assert_eq!(h.client.realtime().state(), RealtimeState::Connecting);
}

#[test]
fn connecting_without_a_player_does_nothing() {
    let h = Harness::new();
    h.client.realtime().connect();
    assert!(!h.socket.opened());
    assert_eq!(h.client.realtime().state(), RealtimeState::Disconnected);
}

#[test]
fn once_open_it_joins_the_user_channel() {
    let h = Harness::new();
    h.signed_in();
    h.client.realtime().connect();
    h.socket.accept();
    h.poll();
    assert_eq!(h.client.realtime().state(), RealtimeState::Connected);
    let frames = h.socket.take_frames();
    assert_eq!(frames.len(), 1);
    assert_eq!(
        frame_of(&frames[0]),
        json!(["1", "1", "user:u1", "phx_join", {}])
    );
    assert!(!h.client.realtime().joined("user:u1"));
    h.socket.receive(&ok_reply("1", "1", "user:u1"));
    h.poll();
    assert!(h.client.realtime().joined("user:u1"));
}

#[test]
fn server_events_arrive_named_in_poll() {
    let c = Harness::connected();
    c.socket
        .receive(&message("user:u1", "updated", json!({ "id": "u1" })));
    assert!(c.client.drain_events().is_empty());
    c.poll();
    let events_seen = c.client.drain_events();
    assert_eq!(events_seen.len(), 1);
    assert_eq!(events_seen[0].kind, events::USER_UPDATED);
    assert_eq!(events_seen[0].event, "updated");
    assert_eq!(events_seen[0].payload["id"], json!("u1"));

    c.socket
        .receive(&message("user:u1", "something_new", json!({})));
    c.poll();
    assert_eq!(c.client.realtime().events()[0].kind, events::MESSAGE);
}

#[test]
fn a_hook_call_goes_over_the_user_channel_and_answers_its_data_or_its_error() {
    let c = Harness::connected();
    let seen = c
        .client
        .realtime()
        .call_hook("arena", "start", json!([1, "x"]));
    let frames = c.socket.take_frames();
    assert_eq!(frames.len(), 1);
    assert_eq!(
        frame_of(&frames[0]),
        json!(["1", "2", "user:u1", "call_hook",
               { "plugin": "arena", "fn": "start", "args": [1, "x"] }])
    );
    c.socket.receive(&reply(
        "1",
        "2",
        "user:u1",
        "ok",
        json!({ "data": { "round": 1 } }),
    ));
    c.poll();
    let result = got(&seen);
    assert!(result.ok);
    assert_eq!(result.data["round"], json!(1));

    let seen = c.client.realtime().call_hook("arena", "nope", json!([]));
    c.socket.receive(&reply(
        "1",
        "3",
        "user:u1",
        "error",
        json!({ "error": "unknown_function" }),
    ));
    c.poll();
    let result = got(&seen);
    assert!(!result.ok);
    assert_eq!(result.error, "unknown_function");
}

#[test]
fn a_command_goes_to_its_channel_with_its_event_and_params() {
    let c = Harness::connected();
    commands::results_list(c.client.realtime(), json!({ "kind": "match" }));
    let frames = c.frames();
    assert_eq!(frames.len(), 1);
    assert_eq!(frames[0][2], json!("user:u1"));
    assert_eq!(frames[0][3], json!("results:list"));
    assert_eq!(frames[0][4]["kind"], json!("match"));

    c.client.realtime().join_lobby("L1");
    let join = c.frames().remove(0);
    c.socket.receive(&harness::reply_to(&join, "ok", json!({})));
    c.poll();

    commands::lobby_get_server_time(c.client.realtime(), "L1");
    let frames = c.frames();
    assert_eq!(frames.len(), 1);
    assert_eq!(frames[0][2], json!("lobby:L1"));
    assert_eq!(frames[0][3], json!("get_server_time"));
}

#[test]
fn a_push_nobody_answers_times_out_and_one_to_an_unjoined_topic_is_refused() {
    let c = Harness::connected();
    let seen = c.client.realtime().push("user:u1", "ping", json!({}));
    assert_eq!(c.socket.take_frames().len(), 1);
    c.advance(secs(10));
    let answer = got(&seen);
    assert_eq!(answer.status, "timeout");
    assert!(!answer.ok);

    let seen = c.client.realtime().push("lobby:x", "ping", json!({}));
    assert!(c.socket.take_frames().is_empty());
    assert!(!seen.is_ready());
    c.poll();
    assert_eq!(got(&seen).status, "not_joined");
}

#[test]
fn topics_join_now_or_when_the_connection_opens_and_rejoin_after_a_drop_in_order() {
    let h = Harness::new();
    h.signed_in();
    let lobby_join = h.client.realtime().join_lobby("l1");
    h.client.realtime().connect();
    h.socket.accept();
    h.poll();
    let frames = h.frames();
    assert_eq!(frames.len(), 2);
    assert_eq!(frames[0][2], json!("user:u1"));
    assert_eq!(frames[1][2], json!("lobby:l1"));
    h.socket.receive(&ok_reply("1", "1", "user:u1"));
    h.socket.receive(&ok_reply("2", "2", "lobby:l1"));
    h.poll();
    assert!(got(&lobby_join).ok);

    h.socket.drop_connection();
    h.poll();
    assert_eq!(h.client.realtime().state(), RealtimeState::Reconnecting);
    assert!(!h.client.realtime().joined("lobby:l1"));
    assert_eq!(h.socket.opens(), 1);
    h.advance(ms(100));
    assert_eq!(h.socket.opens(), 2);
    h.socket.accept();
    h.poll();
    let frames = h.frames();
    assert_eq!(frames.len(), 2);
    assert_eq!(frames[0][2], json!("user:u1"));
    assert_eq!(frames[1][2], json!("lobby:l1"));
    assert_eq!(h.client.realtime().state(), RealtimeState::Connected);
}

#[test]
fn a_pending_push_fails_when_the_connection_drops() {
    let c = Harness::connected();
    let seen = c.client.realtime().push("user:u1", "ping", json!({}));
    c.socket.drop_connection();
    c.poll();
    assert_eq!(got(&seen).status, "disconnected");
}

#[test]
fn what_disconnect_fails_completes_in_the_next_poll_not_inside_it() {
    let c = Harness::connected();
    let seen = c.client.realtime().push("user:u1", "ping", json!({}));
    c.client.realtime().disconnect();
    assert!(!seen.is_ready());
    c.poll();
    assert_eq!(got(&seen).status, "disconnected");
}

#[test]
fn a_connection_that_never_opened_refreshes_the_token_before_the_next_attempt() {
    let h = Harness::new();
    h.signed_in();
    h.client.realtime().connect();
    h.socket.fail("handshake refused");
    h.poll();
    h.advance(ms(100));
    // The refresh goes first; the socket waits for it.
    assert_eq!(h.server.pending(), 1);
    assert_eq!(h.server.next().url, "http://game.test/api/v1/refresh");
    assert_eq!(h.socket.opens(), 1);
    h.server.reply(200, &session_reply(2));
    h.poll();
    assert_eq!(h.socket.opens(), 2);
    assert!(h.socket.url().contains("token=a2"));
}

#[test]
fn backoff_grows_and_holds_at_its_last_step() {
    let h = Harness::new();
    h.signed_in();
    h.client.realtime().connect();
    h.socket.accept();
    h.poll();
    for wait in [100, 500, 1000, 2000, 5000, 10000, 10000] {
        let before = h.socket.opens();
        h.socket.drop_connection();
        h.poll();
        h.advance(ms(wait - 1));
        assert_eq!(h.socket.opens(), before);
        h.advance(ms(1));
        if h.server.pending() > 0 {
            // A drop that never opened refreshes first.
            h.server.reply(200, &session_reply(1));
            h.poll();
        }
        assert_eq!(h.socket.opens(), before + 1);
    }
}

#[test]
fn a_missed_heartbeat_drops_the_connection_and_reconnects() {
    let c = Harness::connected();
    c.advance(secs(30));
    let frames = c.frames();
    assert_eq!(frames.len(), 1);
    assert_eq!(frames[0][2], json!("phoenix"));
    assert_eq!(frames[0][3], json!("heartbeat"));

    // Answered: the next beat goes out on time.
    let reference = frames[0][1].as_str().unwrap();
    c.socket.receive(
        &json!([null, reference, "phoenix", "phx_reply", { "status": "ok", "response": {} }])
            .to_string(),
    );
    c.advance(secs(30));
    assert_eq!(c.socket.take_frames().len(), 1);

    // Unanswered: the one after that finds it still pending.
    c.advance(secs(30));
    assert_eq!(c.client.realtime().state(), RealtimeState::Reconnecting);
    c.advance(ms(100));
    assert_eq!(c.socket.opens(), 2);
}

#[test]
fn a_channel_that_errors_rejoins_and_one_the_server_closes_does_not() {
    let c = Harness::connected();
    c.client.realtime().join_lobby("l1");
    c.socket.take_frames();
    c.socket.receive(&ok_reply("2", "2", "lobby:l1"));
    c.poll();

    c.socket
        .receive(&message("lobby:l1", "phx_error", json!({})));
    c.poll();
    assert!(!c.client.realtime().joined("lobby:l1"));
    c.advance(secs(1));
    let frames = c.frames();
    assert_eq!(frames.len(), 1);
    assert_eq!(frames[0][3], json!("phx_join"));
    let reference = frames[0][1].as_str().unwrap();
    c.socket
        .receive(&ok_reply(reference, reference, "lobby:l1"));
    c.poll();
    assert!(c.client.realtime().joined("lobby:l1"));

    c.socket
        .receive(&message("lobby:l1", "phx_close", json!({})));
    c.poll();
    assert!(!c.client.realtime().joined("lobby:l1"));
    c.advance(secs(5));
    assert!(c.socket.take_frames().is_empty());
}

#[test]
fn a_join_the_server_refuses_for_good_is_dropped_and_says_why() {
    let c = Harness::connected();
    let seen = c.client.realtime().join_lobby("secret");
    c.socket.take_frames();
    c.socket.receive(&reply(
        "2",
        "2",
        "lobby:secret",
        "error",
        json!({ "reason": "unauthorized" }),
    ));
    c.poll();
    let answer = got(&seen);
    assert!(!answer.ok);
    assert_eq!(answer.error, "unauthorized");
    c.advance(secs(5));
    assert!(c.socket.take_frames().is_empty());
}

#[test]
fn leaving_sends_phx_leave_and_stops_rejoining() {
    let c = Harness::connected();
    c.client.realtime().join_lobby("l1");
    c.socket.take_frames();
    c.socket.receive(&ok_reply("2", "2", "lobby:l1"));
    c.poll();
    let seen = c.client.realtime().leave("lobby:l1");
    let frames = c.frames();
    assert_eq!(frames.len(), 1);
    assert_eq!(frames[0], json!(["2", "3", "lobby:l1", "phx_leave", {}]));
    c.socket.receive(&ok_reply("2", "3", "lobby:l1"));
    c.poll();
    assert!(got(&seen).ok);

    c.socket.drop_connection();
    c.poll();
    c.advance(ms(100));
    c.socket.accept();
    c.poll();
    let frames = c.frames();
    assert_eq!(frames.len(), 1);
    assert_eq!(frames[0][2], json!("user:u1"));
}

#[test]
fn disconnect_closes_for_good_and_signing_out_does_the_same() {
    let c = Harness::connected();
    c.client.realtime().disconnect();
    assert_eq!(c.client.realtime().state(), RealtimeState::Disconnected);
    assert!(!c.socket.opened());
    c.advance(secs(20));
    assert_eq!(c.socket.opens(), 1);

    let d = Harness::connected();
    d.client.auth().forget();
    d.poll();
    assert_eq!(d.client.realtime().state(), RealtimeState::Disconnected);
    d.advance(secs(20));
    assert_eq!(d.socket.opens(), 1);
}

#[test]
fn state_changes_are_announced_in_order() {
    let c = Harness::connected();
    c.socket.drop_connection();
    c.poll();
    c.advance(ms(100));
    c.socket.accept();
    c.poll();
    assert_eq!(
        c.client.realtime().state_changes(),
        vec![
            RealtimeState::Connecting,
            RealtimeState::Connected,
            RealtimeState::Reconnecting,
            RealtimeState::Connected,
        ]
    );
}

#[test]
fn a_binary_event_no_decoder_reads_still_arrives_as_bytes() {
    let c = Harness::connected();
    let mut frame = vec![2, 7, 7]; // broadcast, topic and event sizes
    frame.extend_from_slice(b"user:u1");
    frame.extend_from_slice(b"unknown");
    frame.extend_from_slice(&[0x08, 0x01]);
    c.socket.receive_binary(frame);
    c.poll();
    let seen = c.client.drain_events();
    assert_eq!(seen.len(), 1);
    assert_eq!(seen[0].event, "unknown");
    assert_eq!(seen[0].payload, Value::Null);
    assert_eq!(seen[0].bytes, vec![0x08, 0x01]);
    assert!(seen[0].binary);
}

#[test]
fn the_protocol_refs_join_refs_and_frames() {
    let mut p = Phoenix::new();
    let (join_ref, join) = p.join("room:1", &json!({ "a": 1 }));
    assert_eq!(join_ref, "1");
    assert_eq!(join, r#"["1","1","room:1","phx_join",{"a":1}]"#);
    let (_, push) = p.push("room:1", "shout", &json!({})).unwrap();
    assert_eq!(push, r#"["1","2","room:1","shout",{}]"#);
    assert!(p.push("room:2", "shout", &json!({})).is_none());
    assert!(p.decode("not json").is_none());
    assert!(p.decode("[1,2,3]").is_none());

    let mut binary = vec![1, 1, 1, 6, 2]; // reply, then the four sizes
    binary.extend_from_slice(b"12room:1okBYTES");
    let decoded: Frame = p.decode_binary(&binary).unwrap();
    assert_eq!(decoded.kind, FrameKind::Reply);
    assert_eq!(decoded.reference, "2");
    assert_eq!(decoded.status, "ok");
    assert_eq!(decoded.bytes.unwrap(), b"BYTES");
    assert!(p.decode_binary(&binary[..8]).is_none());
}

#[test]
fn the_protocol_heartbeat_waits_beats_and_declares_the_link_dead() {
    let mut p = Phoenix::new();
    assert_eq!(p.heartbeat(10_000), Heartbeat::Wait);
    let Heartbeat::Beat(beat) = p.heartbeat(31_000) else {
        panic!("a heartbeat is due");
    };
    assert!(beat.contains(r#""phoenix","heartbeat""#));
    assert_eq!(p.heartbeat(62_000), Heartbeat::Dead);
}

#[test]
fn a_join_waiting_when_the_client_disconnects_hears_it_from_poll() {
    let c = Harness::connected();
    let seen = c.client.realtime().join_lobby("l1");
    c.client.realtime().disconnect();
    assert!(!seen.is_ready());
    c.poll();
    assert_eq!(got(&seen).status, "disconnected");
}
