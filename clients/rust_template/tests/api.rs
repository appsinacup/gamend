mod harness;

use gamend::{json, Body, Value};
use harness::{got, Harness};

#[test]
fn a_missing_required_body_field_refuses_the_call_naming_the_field() {
    let h = Harness::new();
    let seen = h.client.api().authenticate_device_login(json!({}));
    assert_eq!(h.server.pending(), 0);
    assert!(!seen.is_ready());
    h.poll();
    let reply = got(&seen);
    assert_eq!(reply.status, 0);
    assert_eq!(reply.error, "authenticate_device_login needs `device_id`");

    // Null is as good as missing.
    h.client
        .api()
        .authenticate_device_login(json!({ "device_id": null }));
    assert_eq!(h.server.pending(), 0);
}

#[test]
fn a_missing_required_query_key_refuses_the_call_too() {
    let h = Harness::new();
    let seen = h.client.api().chat_chat_unread_count(json!({}));
    h.poll();
    assert_eq!(got(&seen).error, "chat_chat_unread_count needs `chat_type`");
    assert_eq!(h.server.pending(), 0);
}

#[test]
fn an_empty_path_parameter_refuses_the_call() {
    // `GET /lobbies/` is another operation; sending it would answer the wrong
    // question without saying so.
    let h = Harness::new();
    let seen = h.client.api().lobbies_get_lobby("");
    h.poll();
    assert_eq!(got(&seen).error, "lobbies_get_lobby needs `id`");
    assert_eq!(h.server.pending(), 0);
}

#[test]
fn path_parameters_are_escaped() {
    let h = Harness::new();
    h.client.api().lobbies_get_lobby("a b/c");
    assert_eq!(
        h.server.next().url,
        "http://game.test/api/v1/lobbies/a%20b%2Fc"
    );
}

#[test]
fn a_query_goes_in_the_order_the_operation_declares_or_not_at_all() {
    let h = Harness::new();
    h.client
        .api()
        .lobbies_list_lobbies_with(json!({ "page_size": 5, "title": "duel" }));
    assert_eq!(
        h.server.next().url,
        "http://game.test/api/v1/lobbies?title=duel&page_size=5"
    );
    h.server.reply(200, "{}");
    h.client.api().lobbies_list_lobbies();
    assert_eq!(h.server.next().url, "http://game.test/api/v1/lobbies");
}

#[test]
fn an_upload_sends_its_bytes_as_they_are() {
    // The one operation with a binary body is the admin's, and a game SDK ships
    // no admin API; `Rest::send` is what the generated method calls.
    let h = Harness::new();
    h.client.rest().send(
        "PUT",
        "/api/v1/admin/storage/object?key=maps%2Fa.bin",
        Body::raw(vec![1, 2]),
    );
    let request = h.server.next();
    assert_eq!(request.method, "PUT");
    assert_eq!(
        request.url,
        "http://game.test/api/v1/admin/storage/object?key=maps%2Fa.bin"
    );
    assert_eq!(request.body, vec![1, 2]);
    assert_eq!(
        request.header("content-type"),
        Some("application/octet-stream")
    );
}

#[test]
fn a_paged_list_reads_through_data_and_meta() {
    let h = Harness::new();
    let seen = h.client.api().lobbies_list_lobbies();
    h.server.reply(
        200,
        r#"{"data": [{"id": "l1"}], "meta": {"page": 1, "total_count": 1}}"#,
    );
    h.poll();
    let reply = got(&seen);
    assert_eq!(reply.data().as_array().unwrap().len(), 1);
    assert_eq!(gamend::json::number(reply.meta(), "total_count"), 1);
    assert_eq!(gamend::json::field(&reply.body, "missing"), &Value::Null);
}
