mod harness;

use gamend::{json, RealtimeFormat, Session};
use harness::{got, parsed, secs, session_reply, session_reply_lasting, Harness};

const PENDING: &str =
    r#"{"data": {"status": "pending", "error": "", "message": "", "session": null}}"#;

#[test]
fn device_sign_in_keeps_the_session_and_hands_it_to_the_game() {
    let h = Harness::new();
    let seen = h.client.auth().login_device("device-123");
    let request = h.server.next();
    assert_eq!(request.url, "http://game.test/api/v1/login/device");
    assert_eq!(parsed(&request.body), json!({ "device_id": "device-123" }));
    assert_eq!(request.header("authorization"), None);
    h.server.reply(200, &session_reply(1));
    h.poll();

    let result = got(&seen);
    assert!(result.ok);
    assert_eq!(result.session.user_id, "u1");
    assert_eq!(result.session.username, "ann");
    assert_eq!(result.session.expires_at, h.clock.unix_now() + 900);
    assert!(h.client.auth().signed_in());
    let changes = h.client.auth().session_changes();
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].as_ref().unwrap().access_token, "a1");

    h.client.api().users_get_current_user();
    assert_eq!(h.server.next().header("authorization"), Some("Bearer a1"));
}

#[test]
fn a_refused_sign_in_says_why_and_keeps_nothing() {
    let h = Harness::new();
    let seen = h.client.auth().login_email("ann@example.com", "wrong");
    assert_eq!(
        parsed(&h.server.next().body),
        json!({ "email": "ann@example.com", "password": "wrong" })
    );
    h.server.reply(401, r#"{"error": "invalid_credentials"}"#);
    h.poll();
    let result = got(&seen);
    assert!(!result.ok);
    assert_eq!(result.error, "invalid_credentials");
    assert_eq!(result.response.status, 401);
    assert!(!h.client.auth().signed_in());
    assert!(h.client.auth().session_changes().is_empty());
}

#[test]
fn register_sends_no_password_and_a_username_only_when_there_is_one() {
    let h = Harness::new();
    let seen = h.client.auth().register_email("ann@example.com");
    let plain = h.server.next();
    assert_eq!(plain.url, "http://game.test/api/v1/register");
    assert_eq!(parsed(&plain.body), json!({ "email": "ann@example.com" }));
    assert_eq!(plain.header("authorization"), None);
    h.server.reply(
        201,
        r#"{"data": {"user_id": "u1", "username": "ann", "display_name": "", "email_confirmed": false}}"#,
    );
    h.poll();
    let reply = got(&seen);
    assert!(reply.ok());
    assert_eq!(reply.data()["email_confirmed"], json!(false));

    h.client.auth().register_email_as("bob@example.com", "bob");
    assert_eq!(
        parsed(&h.server.next().body),
        json!({ "email": "bob@example.com", "username": "bob" })
    );
}

#[test]
fn registering_is_not_a_sign_in() {
    let h = Harness::new();
    h.signed_in();
    let seen = h.client.auth().register_email("ann@example.com");
    // Even an answer that carried tokens would not be taken as a session.
    h.server.reply(201, &session_reply(2));
    h.poll();
    h.poll();
    assert!(got(&seen).ok());
    assert_eq!(h.client.auth().session().unwrap().access_token, "a1");
    assert!(h.client.auth().session_changes().is_empty());
}

#[test]
fn the_emailed_code_confirms_the_registration_sets_the_password_and_signs_in() {
    let h = Harness::new();
    let seen = h
        .client
        .auth()
        .confirm_registration("ann@example.com", "042137", "secret-pass");
    let request = h.server.next();
    assert_eq!(request.url, "http://game.test/api/v1/register/confirm");
    assert_eq!(
        parsed(&request.body),
        json!({ "email": "ann@example.com", "code": "042137", "password": "secret-pass" })
    );
    assert_eq!(request.header("authorization"), None);
    h.server.reply(200, &session_reply(1));
    h.poll();
    assert!(got(&seen).ok);
    assert!(h.client.auth().signed_in());

    let seen = h
        .client
        .auth()
        .confirm_registration("ann@example.com", "000000", "secret-pass");
    h.server.reply(401, r#"{"error": "invalid_code"}"#);
    h.poll();
    let result = got(&seen);
    assert!(!result.ok);
    assert_eq!(result.error, "invalid_code");
}

#[test]
fn a_new_code_is_asked_for_with_the_address_alone() {
    let h = Harness::new();
    let seen = h.client.auth().resend_confirmation("ann@example.com");
    let request = h.server.next();
    assert_eq!(request.url, "http://game.test/api/v1/register/resend");
    assert_eq!(parsed(&request.body), json!({ "email": "ann@example.com" }));
    h.server.reply(200, r#"{"ok": true}"#);
    h.poll();
    assert!(got(&seen).ok());
}

#[test]
fn steam_signs_in_with_a_ticket_and_an_answer_with_no_token_signs_nobody_in() {
    let h = Harness::new();
    h.signed_in();
    let seen = h.client.auth().login_steam("14000000");
    let request = h.server.next();
    assert_eq!(request.url, "http://game.test/api/v1/auth/steam/callback");
    assert_eq!(parsed(&request.body), json!({ "code": "14000000" }));
    assert_eq!(request.header("authorization"), None);
    h.server
        .reply(200, r#"{"data": {"linked": true, "provider": "steam"}}"#);
    h.poll();
    let result = got(&seen);
    assert!(!result.ok);
    assert_eq!(result.error, "no_session");
}

#[test]
fn the_access_token_is_refreshed_when_three_quarters_of_it_are_gone() {
    let h = Harness::new();
    h.client.auth().login_device("d");
    h.server.reply(200, &session_reply_lasting(1, 900));
    h.poll();
    assert_eq!(h.server.pending(), 0);

    h.advance(secs(674));
    assert_eq!(h.server.pending(), 0);
    h.advance(secs(1));
    assert_eq!(h.server.pending(), 1);
    assert_eq!(h.server.next().url, "http://game.test/api/v1/refresh");
    h.server.reply(200, &session_reply_lasting(2, 900));
    h.poll();
    assert_eq!(h.client.auth().session().unwrap().access_token, "a2");

    // The next refresh counts from the new token.
    h.advance(secs(674));
    assert_eq!(h.server.pending(), 0);
    h.advance(secs(1));
    assert_eq!(h.server.pending(), 1);
}

#[test]
fn a_refresh_that_cannot_reach_the_server_keeps_the_session_and_tries_again() {
    let h = Harness::new();
    h.signed_in_for(30); // lapses within the margin: refreshed on the next poll
    h.poll();
    assert_eq!(h.server.pending(), 1);
    h.server.fail("timeout");
    h.poll();
    assert!(h.client.auth().signed_in());
    assert_eq!(h.server.pending(), 0);
    h.advance(secs(30));
    assert_eq!(h.server.pending(), 1);
}

#[test]
fn a_restored_session_is_not_announced_back_to_the_game() {
    let h = Harness::new();
    h.signed_in();
    h.poll();
    assert!(h.client.auth().session_changes().is_empty());
    assert_eq!(h.client.auth().session().unwrap().username, "ann");
}

#[test]
fn an_explicit_refresh_reports_the_new_session() {
    let h = Harness::new();
    h.signed_in();
    let seen = h.client.auth().refresh();
    h.server.reply(200, &session_reply(3));
    h.poll();
    let result = got(&seen);
    assert!(result.ok);
    assert_eq!(result.session.access_token, "a3");

    let signed_out = Harness::new();
    let seen = signed_out.client.auth().refresh();
    assert!(!seen.is_ready());
    signed_out.poll();
    assert_eq!(got(&seen).error, "not_signed_in");
}

#[test]
fn logout_revokes_on_the_server_and_forgets_here_whatever_it_answered() {
    let h = Harness::new();
    h.signed_in();
    let seen = h.client.auth().logout();
    let request = h.server.next();
    assert_eq!(request.method, "DELETE");
    assert_eq!(request.url, "http://game.test/api/v1/logout");
    assert_eq!(request.header("authorization"), Some("Bearer a1"));
    h.server.fail("offline");
    h.poll();
    assert!(!got(&seen).ok);
    assert!(!h.client.auth().signed_in());
    assert_eq!(h.client.auth().session_changes(), vec![None]);
}

#[test]
fn a_provider_sign_in_opens_its_page_and_waits_for_the_server_to_resolve_it() {
    let h = Harness::new();
    let seen = h.client.auth().sign_in("google");
    let start = h.server.next();
    assert_eq!(start.method, "GET");
    assert_eq!(start.url, "http://game.test/api/v1/auth/google");
    h.server.reply(
        200,
        r#"{"data": {"authorization_url": "https://accounts.test/o", "session_id": "s 1"}}"#,
    );
    h.poll();
    assert_eq!(h.opened(), vec!["https://accounts.test/o".to_string()]);
    assert_eq!(h.server.pending(), 0);

    h.advance(secs(1));
    assert_eq!(h.server.pending(), 1);
    assert_eq!(
        h.server.next().url,
        "http://game.test/api/v1/auth/session/s%201"
    );
    h.server.reply(200, PENDING);
    h.poll();
    assert!(!seen.is_ready());

    h.advance(secs(1));
    assert_eq!(h.server.pending(), 1);
    h.server.reply(
        200,
        r#"{"data": {"status": "completed", "error": "", "message": "", "session": {
            "access_token": "oa", "refresh_token": "or", "user_id": "u9", "username": "u",
            "display_name": "", "expires_in": 900}}}"#,
    );
    h.poll();
    let result = got(&seen);
    assert!(result.ok);
    assert_eq!(result.session.user_id, "u9");
    assert_eq!(h.client.auth().session().unwrap().access_token, "oa");
}

const PAGE: &str = r#"{"data": {"authorization_url": "https://d.test", "session_id": "s1"}}"#;

#[test]
fn a_sign_in_the_server_refuses_ends_with_its_code() {
    let h = Harness::new();
    let seen = h.client.auth().sign_in("discord");
    h.server.reply(200, PAGE);
    h.poll();
    h.advance(secs(1));
    h.server.reply(
        200,
        r#"{"data": {"status": "error", "error": "account_not_activated",
            "message": "Pending activation", "session": null}}"#,
    );
    h.poll();
    let result = got(&seen);
    assert!(!result.ok);
    assert_eq!(result.error, "account_not_activated");
    assert!(result.response.message().is_empty());
    assert_eq!(
        gamend::json::text(result.response.data(), "message"),
        "Pending activation"
    );
}

#[test]
fn a_sign_in_already_collected_answers_no_session() {
    let h = Harness::new();
    let seen = h.client.auth().sign_in("discord");
    h.server.reply(200, PAGE);
    h.poll();
    h.advance(secs(1));
    h.server.reply(
        200,
        r#"{"data": {"status": "completed", "error": "", "message": "", "session": null}}"#,
    );
    h.poll();
    assert_eq!(got(&seen).error, "no_session");
    assert!(!h.client.auth().signed_in());
}

const LINK_PAGE: &str = r#"{"data": {"authorization_url": "https://g.test", "session_id": "k1"}}"#;

#[test]
fn linking_opens_the_providers_page_as_the_signed_in_player() {
    let h = Harness::new();
    h.signed_in();
    let seen = h.client.auth().link("google");
    let start = h.server.next();
    assert_eq!(start.method, "POST");
    assert_eq!(
        start.url,
        "http://game.test/api/v1/me/providers/google/authorize"
    );
    assert_eq!(start.header("authorization"), Some("Bearer a1"));
    h.server.reply(200, LINK_PAGE);
    h.poll();
    assert_eq!(h.opened(), vec!["https://g.test".to_string()]);

    h.advance(secs(1));
    let poll = h.server.next();
    assert_eq!(poll.url, "http://game.test/api/v1/me/providers/sessions/k1");
    assert_eq!(poll.header("authorization"), Some("Bearer a1"));
    h.server.reply(
        200,
        r#"{"data": {"status": "pending", "error": "", "message": "", "provider": "google"}}"#,
    );
    h.poll();
    h.advance(secs(1));
    h.server.reply(
        200,
        r#"{"data": {"status": "completed", "error": "", "message": "", "provider": "google"}}"#,
    );
    h.poll();
    assert!(got(&seen).ok());
    // Linking leaves the session as it was.
    assert_eq!(h.client.auth().session().unwrap().access_token, "a1");
}

#[test]
fn a_link_the_server_refuses_ends_with_its_code() {
    let h = Harness::new();
    h.signed_in();
    let seen = h.client.auth().link("google");
    h.server.reply(200, LINK_PAGE);
    h.poll();
    h.advance(secs(1));
    h.server.reply(
        200,
        r#"{"data": {"status": "error", "error": "provider_already_linked",
            "message": "Linked to another account", "provider": "google"}}"#,
    );
    h.poll();
    let result = got(&seen);
    assert!(!result.ok());
    assert_eq!(result.error, "provider_already_linked");
}

#[test]
fn a_steam_ticket_links_steam_to_the_signed_in_account() {
    let h = Harness::new();
    h.signed_in();
    let seen = h.client.auth().link_steam("14000000");
    let request = h.server.next();
    assert_eq!(request.url, "http://game.test/api/v1/me/providers/steam");
    assert_eq!(parsed(&request.body), json!({ "code": "14000000" }));
    assert_eq!(request.header("authorization"), Some("Bearer a1"));
    h.server.reply(
        200,
        r#"{"data": {"id": "u1", "linked_providers": {"steam": true}}}"#,
    );
    h.poll();
    let reply = got(&seen);
    assert!(reply.ok());
    assert_eq!(reply.data()["linked_providers"]["steam"], json!(true));
}

#[test]
fn a_sign_in_nobody_finishes_times_out() {
    let h = Harness::new();
    let seen = h.client.auth().sign_in("google");
    h.server.reply(
        200,
        r#"{"data": {"authorization_url": "https://g.test", "session_id": "s1"}}"#,
    );
    h.poll();
    for _ in 0..10 {
        if seen.is_ready() {
            break;
        }
        h.advance(secs(1));
        if h.server.pending() > 0 {
            h.server.reply(200, PENDING);
            h.poll();
        }
    }
    assert_eq!(got(&seen).error, "timeout");
}

#[test]
fn a_cancelled_sign_in_says_so_and_ignores_what_arrives_after() {
    let h = Harness::new();
    let seen = h.client.auth().sign_in("google");
    h.server.reply(
        200,
        r#"{"data": {"authorization_url": "https://g.test", "session_id": "s1"}}"#,
    );
    h.poll();
    h.client.auth().cancel_sign_in();
    assert!(!seen.is_ready());
    h.poll();
    assert_eq!(got(&seen).error, "cancelled");
    h.advance(secs(2));
    assert_eq!(h.server.pending(), 0);
}

#[test]
fn sign_in_without_a_way_to_open_the_page_fails() {
    let h = Harness::with(false, RealtimeFormat::Json);
    let seen = h.client.auth().sign_in("google");
    assert_eq!(h.server.pending(), 0);
    h.poll();
    assert_eq!(got(&seen).error, "no open_url configured");
}

#[test]
fn a_session_survives_a_round_trip_through_json() {
    let session = Session {
        access_token: "a".to_string(),
        refresh_token: "r".to_string(),
        user_id: "u".to_string(),
        username: "n".to_string(),
        display_name: "N".to_string(),
        expires_in: 900,
        expires_at: 1234,
    };
    let back = Session::from_json(&session.to_json(), 0).unwrap();
    assert_eq!(back, session);

    assert!(Session::from_json(&json!({ "refresh_token": "r" }), 0).is_none());
    let fresh = Session::from_json(&json!({ "access_token": "a", "expires_in": 60 }), 1000);
    assert_eq!(fresh.unwrap().expires_at, 1060);
}

#[test]
fn an_explicit_refresh_without_a_refresh_token_still_answers_from_poll() {
    let h = Harness::new();
    h.client.auth().restore(Session {
        access_token: "a1".to_string(),
        user_id: "u1".to_string(),
        ..Session::default()
    });
    let seen = h.client.auth().refresh();
    assert!(!seen.is_ready());
    h.poll();
    assert_eq!(got(&seen).error, "refresh_failed");
    assert_eq!(h.server.pending(), 0);
}
