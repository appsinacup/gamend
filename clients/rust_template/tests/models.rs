mod harness;

use gamend::models::{Lobby, LobbyStats, WalletBalances};
use gamend::{json, Model, Response};
use harness::{got, Harness};

#[test]
fn a_reply_reads_as_its_model() {
    let h = Harness::new();
    let seen = h.client.api().lobbies_get_lobby("l1");
    h.server.reply(
        200,
        r#"{"data": {
            "id": "l1", "title": "Duel", "max_users": 2, "hostless": false, "state": "playing",
            "state_changed_at": null, "metadata": {"map": "dunes"},
            "members": [{"id": "u1", "username": "ann"}, {"id": "u2", "username": "bea"}]}}"#,
    );
    h.poll();
    let lobby = got(&seen).as_model::<Lobby>().unwrap();
    assert_eq!(lobby.id, "l1");
    assert_eq!(lobby.max_users, 2);
    assert_eq!(lobby.state, "playing");
    assert_eq!(lobby.state_changed_at, None);
    assert_eq!(lobby.metadata["map"], json!("dunes"));
    assert_eq!(lobby.members.len(), 2);
    assert_eq!(lobby.members[1].username, "bea");
    // Left out: the default.
    assert!(lobby.host_id.is_empty());
    assert_eq!(lobby.spectator_count, 0);
}

#[test]
fn a_page_reads_its_items_and_meta_and_a_list_of_strings_reads_too() {
    let h = Harness::new();
    let seen = h.client.api().lobbies_list_lobbies();
    h.server.reply(
        200,
        r#"{"data": [{"id": "a"}, {"id": "b"}],
            "meta": {"page": 1, "page_size": 25, "total_count": 2, "total_pages": 1,
                     "has_more": false, "count": 2}}"#,
    );
    h.poll();
    let page = got(&seen).page::<Lobby>().unwrap();
    assert_eq!(page.data.len(), 2);
    assert_eq!(page.meta.total_count, 2);
    assert!(!page.meta.has_more);

    let seen = h.client.api().authenticate_list_auth_providers();
    h.server.reply(200, r#"{"data": ["google", "steam"]}"#);
    h.poll();
    assert_eq!(
        got(&seen).as_model::<Vec<String>>().unwrap(),
        vec!["google".to_string(), "steam".to_string()]
    );
}

#[test]
fn reads_never_panic_wrong_kinds_keep_defaults_and_a_non_object_is_no_model() {
    let value = json!({ "id": 7, "max_users": "two", "members": "nobody", "title": "ok" });
    assert!(Lobby::accepts(&value));
    let lobby = Lobby::read(&value);
    assert!(lobby.id.is_empty());
    assert_eq!(lobby.max_users, 0);
    assert!(lobby.members.is_empty());
    assert_eq!(lobby.title, "ok");
    assert!(!Lobby::accepts(&json!([])));

    assert!(Response::default().as_model::<Lobby>().is_none());
}

#[test]
fn a_model_writes_back_to_the_json_it_read() {
    let source = json!({ "id": "l1", "title": "Duel", "max_users": 2,
                         "state_changed_at": "2026-09-19T10:00:00Z" });
    let lobby = Lobby::read(&source);
    let written = lobby.write();
    assert_eq!(written["id"], json!("l1"));
    assert_eq!(written["max_users"], json!(2));
    assert_eq!(written["state_changed_at"], json!("2026-09-19T10:00:00Z"));
    assert_eq!(written["host_id"], json!(""));
    assert_eq!(Lobby::read(&written).write(), written);
}

#[test]
fn a_map_shaped_answer_reads_as_a_map() {
    let response = Response {
        status: 200,
        body: json!({ "data": { "coins": 120, "gems": 3 } }),
        ..Response::default()
    };
    let wallet = response.as_model::<WalletBalances>().unwrap();
    assert_eq!(wallet["coins"], 120);
    assert_eq!(wallet["gems"], 3);

    let stats = LobbyStats::read(&json!({
        "by_state": { "playing": 2, "created": 1 },
        "lobbies_total": 3,
    }));
    assert_eq!(stats.by_state["playing"], 2);
    assert_eq!(stats.lobbies_total, 3);
}

#[test]
fn scalars_and_nullables_read_too() {
    let reply = |data: gamend::Value| Response {
        status: 200,
        body: json!({ "data": data }),
        ..Response::default()
    };
    assert_eq!(reply(json!(7)).as_model::<i64>(), Some(7));
    assert_eq!(reply(json!(1.5)).as_model::<f64>(), Some(1.5));
    assert_eq!(reply(json!(true)).as_model::<bool>(), Some(true));
    assert_eq!(
        reply(json!("x")).as_model::<String>(),
        Some("x".to_string())
    );
    assert_eq!(reply(json!("x")).as_model::<i64>(), None);
    assert_eq!(reply(json!(null)).as_model::<Option<i64>>(), Some(None));
    assert_eq!(reply(json!(3)).as_model::<Option<i64>>(), Some(Some(3)));
}

#[test]
fn a_nullable_field_is_empty_until_given_and_a_mistyped_one_stays_empty() {
    assert_eq!(Lobby::default().state_changed_at, None);
    let lobby = Lobby::read(&json!({ "state_changed_at": 12 }));
    assert_eq!(lobby.state_changed_at, None);
}
