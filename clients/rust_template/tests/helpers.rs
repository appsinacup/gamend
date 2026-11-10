mod harness;

use gamend::{json, KvKey, Presence, Value};
use harness::{frame_of, got, message, ms, reply_to, Harness};

fn progress() -> KvKey {
    KvKey::of_user("progress", "u1")
}

// Signed in as u1, not connected yet.
fn live() -> Harness {
    let h = Harness::new();
    h.signed_in();
    h
}

// Connects and joins the user channel, answering its join and handing back what
// was sent after it.
fn open(h: &Harness) -> Vec<Value> {
    h.connect();
    h.frames()
}

#[test]
fn a_subscription_is_sent_once_the_user_channel_joins_and_its_reply_fills_the_cache() {
    let h = live();
    let seen = h.client.kv().subscribe(progress());
    let sent = open(&h);
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0][3], json!("kv:subscribe"));
    assert_eq!(sent[0][4], json!({ "key": "progress", "user_id": "u1" }));

    h.socket.receive(&reply_to(
        &sent[0],
        "ok",
        json!({ "subscribed": true, "key": "progress", "data": { "level": 3 }, "metadata": {} }),
    ));
    h.poll();
    let result = got(&seen);
    assert!(result.ok);
    assert!(result.row.exists);
    assert_eq!(result.row.data["level"], json!(3));
    assert!(h.client.kv().subscribed(progress()));
    let row = h.client.kv().row(progress()).unwrap();
    assert_eq!(row.data["level"], json!(3));
    let changes = h.client.kv().changes();
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].0.key, "progress");
}

#[test]
fn a_subscribe_reply_for_a_missing_row_caches_that_it_is_missing() {
    let h = live();
    open(&h);
    h.client.kv().subscribe("loadout");
    let frames = h.frames();
    assert_eq!(frames.len(), 1);
    assert_eq!(frames[0][4], json!({ "key": "loadout" }));
    h.socket.receive(&reply_to(
        &frames[0],
        "ok",
        json!({ "subscribed": true, "key": "loadout", "missing": true }),
    ));
    h.poll();
    assert!(!h.client.kv().row("loadout").unwrap().exists);
}

#[test]
fn pushes_keep_a_row_current_deletes_included() {
    let h = live();
    open(&h);
    h.socket.receive(&message(
        "user:u1",
        "kv_updated",
        json!({ "key": "progress", "user_id": "u1", "lobby_id": "",
                "data": { "level": 4 }, "metadata": {} }),
    ));
    h.poll();
    assert_eq!(
        h.client.kv().row(progress()).unwrap().data["level"],
        json!(4)
    );

    h.socket.receive(&message(
        "user:u1",
        "kv_deleted",
        json!({ "key": "progress", "user_id": "u1", "lobby_id": "" }),
    ));
    h.poll();
    assert!(!h.client.kv().row(progress()).unwrap().exists);
    assert_eq!(h.client.kv().changes().len(), 2);
}

#[test]
fn every_rejoin_sends_the_subscriptions_again_and_a_refused_one_is_dropped() {
    let h = live();
    h.client.kv().subscribe(progress());
    let refused = h.client.kv().subscribe("secret");
    let sent = open(&h);
    assert_eq!(sent.len(), 2);
    h.socket
        .receive(&reply_to(&sent[0], "ok", json!({ "missing": true })));
    h.socket.receive(&reply_to(
        &sent[1],
        "error",
        json!({ "error": "forbidden" }),
    ));
    h.poll();
    let result = got(&refused);
    assert!(!result.ok);
    assert_eq!(result.error, "forbidden");

    h.socket.drop_connection();
    h.poll();
    h.advance(ms(100));
    h.socket.accept();
    h.poll();
    let join = h.frames().remove(0);
    h.socket.receive(&reply_to(&join, "ok", json!({})));
    h.poll();
    let again = h.socket.take_frames();
    assert_eq!(again.len(), 1);
    assert_eq!(frame_of(&again[0])[4]["key"], json!("progress"));
}

#[test]
fn unsubscribing_tells_the_server_and_stops_resubscribing() {
    let h = live();
    h.client.kv().subscribe(progress());
    let sent = open(&h);
    h.socket
        .receive(&reply_to(&sent[0], "ok", json!({ "missing": true })));
    h.poll();
    h.client.kv().unsubscribe(progress());
    let frames = h.frames();
    assert_eq!(frames.len(), 1);
    assert_eq!(frames[0][3], json!("kv:unsubscribe"));
    assert!(!h.client.kv().subscribed(progress()));
}

#[test]
fn fetch_reads_the_cache_first_the_api_otherwise_and_a_404_caches_the_absence() {
    let h = live();
    let seen = h.client.kv().fetch(progress(), false);
    assert_eq!(h.server.pending(), 1);
    assert_eq!(
        h.server.next().url,
        "http://game.test/api/v1/kv/progress?user_id=u1"
    );
    h.server.reply(
        200,
        r#"{"data": {"key": "progress", "user_id": "u1", "lobby_id": "",
            "data": {"level": 7}, "metadata": {}}}"#,
    );
    h.poll();
    let result = got(&seen);
    assert!(result.ok);
    assert_eq!(result.row.data["level"], json!(7));

    let seen = h.client.kv().fetch(progress(), false);
    assert_eq!(h.server.pending(), 0);
    assert!(!seen.is_ready());
    h.poll();
    assert_eq!(got(&seen).row.data["level"], json!(7));

    let seen = h.client.kv().fetch("nothing", false);
    h.server.reply(404, r#"{"error": "not_found"}"#);
    h.poll();
    let result = got(&seen);
    assert!(result.ok);
    assert!(!result.row.exists);
    assert!(h.client.kv().row("nothing").is_some());
}

#[test]
fn signing_out_forgets_rows_and_subscriptions() {
    let h = live();
    open(&h);
    h.socket.receive(&message(
        "user:u1",
        "kv_updated",
        json!({ "key": "progress", "user_id": "u1", "data": { "a": 1 } }),
    ));
    h.poll();
    assert!(h.client.kv().row(progress()).is_some());
    h.client.auth().forget();
    h.poll();
    assert!(h.client.kv().row(progress()).is_none());
}

#[test]
fn presence_merges_profiles_keeps_metadata_sections_and_tracks_who_is_online() {
    let h = live();
    open(&h);

    h.socket.receive(&message(
        "lobby:l1",
        "user_joined",
        json!({ "user_id": "u2", "display_name": "Bea",
                "metadata": { "player": { "hat": "red", "boots": "blue" } } }),
    ));
    h.socket.receive(&message(
        "lobby:l1",
        "user_updated",
        json!({ "user_id": "u2", "metadata": { "player": { "hat": "green" } } }),
    ));
    h.poll();
    let bea = h.client.presence().user("u2");
    assert_eq!(bea["display_name"], json!("Bea"));
    assert_eq!(bea["metadata"]["player"]["hat"], json!("green"));
    assert_eq!(bea["metadata"]["player"]["boots"], json!("blue"));

    h.socket.receive(&message(
        "lobby:l1",
        "user_online",
        json!({ "user_id": "u2" }),
    ));
    h.poll();
    assert!(h.client.presence().online("u2"));
    h.socket.receive(&message(
        "lobby:l1",
        "user_offline",
        json!({ "user_id": "u2" }),
    ));
    h.poll();
    assert!(!h.client.presence().online("u2"));
    assert_eq!(h.client.presence().last_seen("u2"), h.clock.unix_now());
    assert!(h.client.presence().online("u1"));
    assert_eq!(h.client.presence().user_changes().len(), 4);
}

#[test]
fn the_players_own_push_replaces_their_metadata_and_keeps_only_their_lobby() {
    let h = live();
    open(&h);
    h.socket.receive(&message(
        "lobby:l1",
        "updated",
        json!({ "id": "l1", "title": "One" }),
    ));
    h.socket.receive(&message(
        "lobby:l2",
        "updated",
        json!({ "id": "l2", "title": "Two" }),
    ));
    h.client
        .presence()
        .cache_user("u1", &json!({ "metadata": { "old": 1, "keep": 1 } }));
    h.socket.receive(&message(
        "user:u1",
        "updated",
        json!({ "id": "u1", "lobby_id": "l2", "metadata": { "keep": 2 } }),
    ));
    h.poll();
    let me = h.client.presence().user("u1");
    assert_eq!(me["metadata"], json!({ "keep": 2 }));
    assert_eq!(h.client.presence().lobby("l1"), json!({}));
    assert_eq!(h.client.presence().lobby("l2")["title"], json!("Two"));
}

#[test]
fn merge_metadata_merges_one_section_deep() {
    let merged = Presence::merge_metadata(
        &json!({ "player": { "hat": "red", "boots": "blue" }, "level": 1 }),
        &json!({ "player": { "hat": "green" }, "level": 2, "new": true }),
    );
    assert_eq!(
        merged,
        json!({ "player": { "hat": "green", "boots": "blue" }, "level": 2, "new": true })
    );
}
