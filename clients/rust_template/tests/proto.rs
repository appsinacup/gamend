mod harness;

use std::sync::Arc;

use gamend::detail::proto;
use gamend::{events, json, Value};
use harness::Harness;

fn message(name: &str) -> &'static proto::Message {
    proto::find(name).unwrap_or_else(|| panic!("no message {name}"))
}

#[test]
fn the_wire_format_decodes_strings_varints_zigzag_nested_and_repeated() {
    // WalletChange{currency: "coins", balance: 150, delta: -5}, by hand.
    let wire = [
        0x0A, 5, b'c', b'o', b'i', b'n', b's', 0x10, 0x96, 0x01, 0x18, 0x09,
    ];
    let decoded = proto::decode(message("WalletChange"), &wire, true, None).unwrap();
    assert_eq!(
        decoded,
        json!({ "currency": "coins", "balance": 150, "delta": -5 })
    );

    assert!(proto::decode(message("WalletChange"), &[0x0A, 9, b'c'], true, None).is_none());
}

#[test]
fn encode_and_decode_agree_maps_and_nested_messages_included() {
    let lobby = json!({
        "id": "l1",
        "title": "Duel",
        "max_users": 4,
        "hostless": false,
        "members": [{ "id": "u1", "username": "ann" }, { "id": "u2" }],
        "metadata_json": "{\"map\":\"dunes\"}",
    });
    let wire = proto::encode(message("Lobby"), &lobby);
    let back = proto::decode(message("Lobby"), &wire, false, None).unwrap();
    assert_eq!(back["id"], json!("l1"));
    assert_eq!(back["max_users"], json!(4));
    assert_eq!(back["hostless"], json!(false)); // optional: present because it was sent
    assert_eq!(back["members"].as_array().unwrap().len(), 2);
    assert_eq!(back["members"][0]["username"], json!("ann"));
    assert_eq!(back["metadata"], json!({ "map": "dunes" }));
    assert!(back.get("metadata_json").is_none());
    assert!(back.get("host_id").is_none());

    let found = json!({ "lobby_id": "l9", "match_params": { "mode": "duel", "region": "eu" } });
    let params = proto::decode(
        message("MatchmakingFound"),
        &proto::encode(message("MatchmakingFound"), &found),
        true,
        None,
    )
    .unwrap();
    assert_eq!(params, found);
}

#[test]
fn defaults_fill_what_proto3_leaves_out_and_never_an_optional_field() {
    let chat = proto::decode(message("ChatMessage"), &[], true, None).unwrap();
    assert_eq!(chat["id"], json!(""));
    assert_eq!(chat["inserted_at_ms"], json!(0));
    assert_eq!(chat["metadata"], json!({}));
    assert!(chat.get("updated_at_ms").is_none());
    assert!(chat.get("sender_email").is_none());

    let user = proto::decode(message("User"), &[], false, None).unwrap();
    assert_eq!(user, json!({}));
}

#[test]
fn binary_events_decode_by_topic_and_event_as_the_server_maps_them() {
    let kv = json!({ "key": "progress", "user_id": "u1", "data_json": "{\"level\":3}",
                     "metadata_json": "{}" });
    let decoded = proto::decode_binary_event(
        "user:u1",
        "kv_updated",
        &proto::encode(message("KvEntry"), &kv),
        None,
    )
    .unwrap();
    assert_eq!(
        decoded,
        json!({ "key": "progress", "user_id": "u1", "data": { "level": 3 }, "metadata": {} })
    );

    // `updated` is a User on user:, a Lobby on lobby:.
    let lobby = proto::decode_binary_event(
        "lobby:l1",
        "updated",
        &proto::encode(message("Lobby"), &json!({ "id": "l1", "title": "T" })),
        None,
    )
    .unwrap();
    assert_eq!(lobby["title"], json!("T"));
    assert!(proto::decode_binary_event("lobby:l1", "unmapped", &[], None).is_none());

    let pb = proto::decode_binary_event(
        "user:u1",
        "kv_updated",
        &proto::encode(
            message("KvEntry"),
            &json!({ "key": "k", "data_pb": [1, 2] }),
        ),
        None,
    )
    .unwrap();
    assert_eq!(pb["data_pb"], json!("AQI="));
}

#[test]
fn a_binary_frame_on_a_protobuf_connection_reaches_the_game_decoded() {
    let h = Harness::new();
    h.signed_in();
    h.client.realtime().connect();
    h.socket.accept();
    h.poll();
    let body = proto::encode(
        message("WalletChange"),
        &json!({ "currency": "coins", "balance": 10, "delta": 2 }),
    );
    let mut frame = vec![0, 1, 7, 14]; // push, then the three sizes
    frame.extend_from_slice(b"1");
    frame.extend_from_slice(b"user:u1");
    frame.extend_from_slice(b"wallet_updated");
    frame.extend_from_slice(&body);
    h.socket.receive_binary(frame);
    h.poll();
    let seen = h.client.drain_events();
    assert_eq!(seen.len(), 1);
    assert_eq!(seen[0].kind, events::WALLET_UPDATED);
    assert_eq!(
        seen[0].payload,
        json!({ "currency": "coins", "balance": 10, "delta": 2 })
    );
    assert!(seen[0].bytes.is_empty());
}

#[test]
fn base64() {
    assert_eq!(proto::base64(b""), "");
    assert_eq!(proto::base64(b"f"), "Zg==");
    assert_eq!(proto::base64(b"fo"), "Zm8=");
    assert_eq!(proto::base64(b"foo"), "Zm9v");
}

// A connected client in protobuf mode that hands back what arrived.
fn pb() -> Harness {
    let h = Harness::new();
    h.signed_in();
    h.client.realtime().connect();
    h.socket.accept();
    h.poll();
    h
}

fn receive(h: &Harness, topic: &str, event: &str, name: &str, value: &Value) -> Value {
    let body = proto::encode(message(name), value);
    let mut frame = vec![2, topic.len() as u8, event.len() as u8]; // broadcast
    frame.extend_from_slice(topic.as_bytes());
    frame.extend_from_slice(event.as_bytes());
    frame.extend_from_slice(&body);
    h.socket.receive_binary(frame);
    h.poll();
    h.client.drain_events().pop().unwrap().payload
}

#[test]
fn a_games_kv_bytes_read_through_its_decoder_exact_key_first_then_longest_prefix() {
    let h = pb();
    let realtime = h.client.realtime();
    realtime.register_kv_decoder(
        "match:*",
        Arc::new(|b: &[u8]| Some(json!({ "by": "match", "size": b.len() }))),
    );
    realtime.register_kv_decoder(
        "match:final:*",
        Arc::new(|_: &[u8]| Some(json!({ "by": "final" }))),
    );
    realtime.register_kv_decoder(
        "match:final:7",
        Arc::new(|_: &[u8]| Some(json!({ "by": "exact" }))),
    );
    let kv = |key: &str| {
        receive(
            &h,
            "user:u1",
            "kv_updated",
            "KvEntry",
            &json!({ "key": key, "data_pb": [8, 42] }),
        )
    };
    assert_eq!(kv("match:1")["data"], json!({ "by": "match", "size": 2 }));
    assert_eq!(kv("match:final:1")["data"]["by"], json!("final"));
    assert_eq!(kv("match:final:7")["data"]["by"], json!("exact"));
    let unread = kv("loadout");
    assert_eq!(unread["data_pb"], json!("CCo="));
    assert!(unread.get("data").is_none());
}

#[test]
fn a_games_metadata_bytes_read_through_its_entitys_decoder() {
    let h = pb();
    h.client.realtime().register_metadata_decoder(
        "lobby",
        Arc::new(|b: &[u8]| Some(json!({ "hat_bytes": b.len() }))),
    );
    let meta = [0x0A, 0x03, b'r', b'e', b'd'];
    let lobby = receive(
        &h,
        "lobby:l1",
        "updated",
        "Lobby",
        &json!({ "id": "l1", "metadata_pb": meta }),
    );
    assert_eq!(lobby["metadata"], json!({ "hat_bytes": 5 }));
    assert!(lobby.get("metadata_pb").is_none());

    // No decoder for users: the bytes stay, base64.
    let user = receive(
        &h,
        "user:u1",
        "updated",
        "User",
        &json!({ "id": "u1", "metadata_pb": meta }),
    );
    assert_eq!(user["metadata_pb"], json!(proto::base64(&meta)));
}

#[test]
fn unbase64_undoes_base64() {
    let texts: [&[u8]; 5] = [b"", b"f", b"fo", b"foo", &[0x00, 0xFF, 0x10]];
    for text in texts {
        assert_eq!(proto::unbase64(&proto::base64(text)).unwrap(), text);
    }
    assert!(proto::unbase64("not base64!").is_none());
}
