mod harness;

use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Wake, Waker};

use gamend::testing::FakeHttp;
use gamend::{json, Body, Client, Config, HttpDone, HttpRequest, HttpTransport, Ticket, Value};
use harness::{got, parsed, session_reply, Harness};

#[test]
fn a_ticket_completes_in_poll_never_inside_the_call_or_the_reply() {
    let h = Harness::new();
    let seen = h.client.api().lobbies_lobby_stats();
    assert_eq!(h.server.pending(), 1);
    h.server.reply(200, r#"{"data": {"total": 3}}"#);
    assert!(!seen.is_ready());
    assert!(seen.try_take().is_none());
    h.poll();
    assert!(seen.is_ready());
    let reply = got(&seen);
    assert!(reply.ok());
    assert_eq!(reply.data()["total"], json!(3));
    // Taken once, gone; still ready.
    assert!(seen.try_take().is_none());
    assert!(seen.is_ready());
}

// Records the order tickets woke in.
struct Named {
    name: &'static str,
    order: Arc<Mutex<Vec<&'static str>>>,
}

impl Wake for Named {
    fn wake(self: Arc<Self>) {
        self.order.lock().unwrap().push(self.name);
    }
}

fn register<T>(ticket: &mut Ticket<T>, waker: &Waker) {
    let mut context = Context::from_waker(waker);
    assert!(Pin::new(ticket).poll(&mut context).is_pending());
}

#[test]
fn replies_complete_in_the_order_they_arrived() {
    let h = Harness::new();
    let order = Arc::new(Mutex::new(Vec::new()));
    let mut a = h.client.rest().send("GET", "/api/v1/a", Body::none());
    let mut b = h.client.rest().send("GET", "/api/v1/b", Body::none());
    let waker = |name| {
        Waker::from(Arc::new(Named {
            name,
            order: order.clone(),
        }))
    };
    register(&mut a, &waker("a"));
    register(&mut b, &waker("b"));
    h.server.reply(200, "{}");
    h.server.reply(200, "{}");
    h.poll();
    assert_eq!(*order.lock().unwrap(), vec!["a", "b"]);
}

struct Counting(AtomicUsize);

impl Wake for Counting {
    fn wake(self: Arc<Self>) {
        self.0.fetch_add(1, Ordering::SeqCst);
    }
}

#[test]
fn a_ticket_can_be_awaited() {
    let h = Harness::new();
    let mut ticket = h.client.api().lobbies_lobby_stats();
    let counter = Arc::new(Counting(AtomicUsize::new(0)));
    let waker = Waker::from(counter.clone());
    let mut context = Context::from_waker(&waker);
    assert!(Pin::new(&mut ticket).poll(&mut context).is_pending());
    h.server.reply(200, r#"{"data": {"total": 1}}"#);
    assert_eq!(counter.0.load(Ordering::SeqCst), 0);
    h.poll();
    assert_eq!(counter.0.load(Ordering::SeqCst), 1);
    match Pin::new(&mut ticket).poll(&mut context) {
        Poll::Ready(reply) => assert!(reply.ok()),
        Poll::Pending => panic!("the ticket should have completed"),
    }
}

#[test]
fn every_clone_of_a_ticket_reads_one_answer_and_the_first_takes_it() {
    let h = Harness::new();
    let first = h.client.api().lobbies_lobby_stats();
    let second = first.clone();
    h.server.reply(200, "{}");
    h.poll();
    assert!(second.is_ready());
    assert!(first.try_take().is_some());
    assert!(second.try_take().is_none());
}

#[test]
fn a_client_and_its_tickets_cross_threads() {
    fn crosses<T: Send + Sync>() {}
    crosses::<Client>();
    crosses::<Ticket<gamend::Response>>();
    crosses::<gamend::Api>();
    crosses::<gamend::Realtime>();
}

#[test]
fn a_waker_may_call_straight_back_into_the_client() {
    struct Reenter(Client);
    impl Wake for Reenter {
        fn wake(self: Arc<Self>) {
            self.0.api().lobbies_lobby_stats();
        }
    }
    let h = Harness::new();
    let mut ticket = h.client.api().lobbies_lobby_stats();
    let waker = Waker::from(Arc::new(Reenter(h.client.clone())));
    let mut context = Context::from_waker(&waker);
    assert!(Pin::new(&mut ticket).poll(&mut context).is_pending());
    h.server.reply(200, "{}");
    h.poll();
    assert_eq!(h.server.pending(), 1);
}

#[test]
fn every_call_names_the_run_and_only_a_signed_in_one_carries_a_token() {
    let h = Harness::new();
    h.client.api().lobbies_lobby_stats();
    let anonymous = h.server.next();
    assert_eq!(anonymous.url, "http://game.test/api/v1/lobbies/stats");
    assert_eq!(anonymous.method, "GET");
    assert_eq!(anonymous.header("x-gamend-session"), Some("run-1"));
    assert_eq!(anonymous.header("accept"), Some("application/json"));
    assert!(anonymous
        .header("user-agent")
        .unwrap()
        .starts_with("gamend-rust/"));
    assert_eq!(anonymous.header("authorization"), None);
    assert!(anonymous.body.is_empty());
    assert_eq!(anonymous.header("content-type"), None);
    h.server.reply(200, "{}");

    h.signed_in();
    h.client.api().users_get_current_user();
    assert_eq!(h.server.next().header("authorization"), Some("Bearer a1"));
}

#[test]
fn a_body_goes_as_json_and_a_post_without_one_sends_an_empty_object() {
    let h = Harness::new();
    h.client
        .api()
        .lobbies_quick_join(json!({ "title": "duel", "max_users": 2 }));
    let join = h.server.next();
    h.server.reply(200, "{}");
    assert_eq!(join.method, "POST");
    assert_eq!(join.header("content-type"), Some("application/json"));
    assert_eq!(
        parsed(&join.body),
        json!({ "title": "duel", "max_users": 2 })
    );

    h.client.api().lobbies_leave_lobby();
    let leave = h.server.next();
    assert_eq!(leave.body, b"{}");
    assert_eq!(leave.header("content-type"), Some("application/json"));
}

#[test]
fn an_error_reply_carries_its_code_and_one_with_no_code_its_status() {
    let h = Harness::new();
    let seen = h.client.api().lobbies_get_lobby("x");
    h.server
        .reply(404, r#"{"error": "not_found", "message": "No such lobby"}"#);
    h.poll();
    let reply = got(&seen);
    assert!(!reply.ok());
    assert_eq!(reply.status, 404);
    assert_eq!(reply.error, "not_found");
    assert_eq!(reply.code(), "not_found");
    assert_eq!(reply.message(), "No such lobby");

    let seen = h.client.api().lobbies_get_lobby("x");
    h.server.reply(502, "<html>bad gateway</html>");
    h.poll();
    let reply = got(&seen);
    assert_eq!(reply.error, "http_502");
    assert_eq!(reply.body, Value::Null);
    assert_eq!(reply.text(), "<html>bad gateway</html>");
}

#[test]
fn no_reply_at_all_is_status_0_with_the_transports_reason() {
    let h = Harness::new();
    let seen = h.client.api().lobbies_lobby_stats();
    h.server.fail("connection refused");
    h.poll();
    let reply = got(&seen);
    assert_eq!(reply.status, 0);
    assert_eq!(reply.error, "connection refused");
    assert!(!reply.ok());
}

#[test]
fn a_401_refreshes_once_and_sends_the_call_again_with_the_new_token() {
    let h = Harness::new();
    h.signed_in();
    let seen = h.client.api().users_get_current_user();
    h.server.reply(401, r#"{"error": "unauthorized"}"#);
    h.poll();

    assert_eq!(h.server.pending(), 1);
    let refresh = h.server.next();
    assert_eq!(refresh.url, "http://game.test/api/v1/refresh");
    assert_eq!(parsed(&refresh.body), json!({ "refresh_token": "r1" }));
    assert_eq!(refresh.header("authorization"), None);
    h.server.reply(200, &session_reply(2));
    h.poll();

    assert_eq!(h.server.pending(), 1);
    let retry = h.server.next();
    assert_eq!(retry.url, "http://game.test/api/v1/me");
    assert_eq!(retry.header("authorization"), Some("Bearer a2"));
    h.server.reply(200, r#"{"data": {"id": "u1"}}"#);
    h.poll();

    assert!(got(&seen).ok());
    assert_eq!(h.client.auth().session().unwrap().access_token, "a2");
}

#[test]
fn two_calls_that_meet_a_401_share_one_refresh() {
    let h = Harness::new();
    h.signed_in();
    let first = h.client.api().users_get_current_user();
    let second = h.client.api().lobbies_lobby_stats();
    h.server.reply(401, "{}");
    h.server.reply(401, "{}");
    h.poll();

    assert_eq!(h.server.pending(), 1);
    h.server.reply(200, &session_reply(2));
    h.poll();
    assert_eq!(h.server.pending(), 2);
    h.server.reply(200, "{}");
    h.server.reply(200, "{}");
    h.poll();
    assert!(got(&first).ok());
    assert!(got(&second).ok());

    let refreshes = h
        .server
        .sent()
        .iter()
        .filter(|request| request.url == "http://game.test/api/v1/refresh")
        .count();
    assert_eq!(refreshes, 1);
}

#[test]
fn a_refused_refresh_signs_out_and_hands_the_call_its_401() {
    let h = Harness::new();
    h.signed_in();
    let seen = h.client.api().users_get_current_user();
    h.server.reply(401, r#"{"error": "unauthorized"}"#);
    h.poll();
    h.server.reply(401, r#"{"error": "invalid_token"}"#);
    h.poll();

    let reply = got(&seen);
    assert_eq!(reply.status, 401);
    assert_eq!(reply.error, "unauthorized");
    assert!(!h.client.auth().signed_in());
    assert_eq!(h.server.pending(), 0);
    assert_eq!(h.client.auth().session_changes(), vec![None]);
}

#[test]
fn a_401_with_no_session_to_refresh_goes_straight_to_the_caller() {
    let h = Harness::new();
    let seen = h.client.api().users_get_current_user();
    h.server.reply(401, r#"{"error": "unauthorized"}"#);
    h.poll();
    assert_eq!(got(&seen).error, "unauthorized");
    assert_eq!(h.server.pending(), 0);
}

fn fake_clock_client(config: Config) -> Client {
    let mut config = config;
    config.clock = Some(gamend::testing::FakeClock::new().steady());
    Client::new(config)
}

#[test]
fn a_client_with_no_transport_answers_every_call_with_an_error() {
    let client = fake_clock_client(Config::new("http://game.test"));
    let seen = client.api().lobbies_lobby_stats();
    client.poll();
    assert_eq!(got(&seen).error, "no HTTP transport configured");
}

// A transport the test keeps after the client that owned it is gone.
struct Shared(Arc<FakeHttp>);

impl HttpTransport for Shared {
    fn send(&self, request: HttpRequest, done: HttpDone) {
        self.0.send(request, done);
    }
}

#[test]
fn a_reply_that_lands_after_the_client_is_gone_is_dropped() {
    let server = Arc::new(FakeHttp::new());
    let seen;
    {
        let mut config = Config::new("http://game.test");
        config.http = Some(Arc::new(Shared(server.clone())));
        let client = fake_clock_client(config);
        seen = client.api().lobbies_lobby_stats();
        assert_eq!(server.pending(), 1);
    }
    server.reply(200, "{}");
    assert!(!seen.is_ready());
}

#[test]
fn drained_news_keeps_only_the_newest_past_the_limit() {
    let mut config = Config::new("http://game.test");
    let socket = Arc::new(gamend::testing::FakeWebSocket::new());
    let server = Arc::new(FakeHttp::new());
    config.http = Some(server.clone());
    config.websocket = Some(socket.clone());
    config.queue_limit = 2;
    let client = fake_clock_client(config);
    client.auth().login_device("d");
    server.reply(200, &session_reply(1));
    client.poll();
    client.realtime().connect();
    client.poll();
    socket.accept();
    client.poll();
    for n in 0..5 {
        socket.receive(&harness::message("user:u1", "ping", json!({ "n": n })));
    }
    client.poll();
    let events = client.drain_events();
    assert_eq!(events.len(), 2);
    assert_eq!(events[0].payload["n"], json!(3));
    assert_eq!(events[1].payload["n"], json!(4));
    assert!(client.drain_events().is_empty());
}

#[test]
fn a_transport_may_complete_on_any_thread_and_the_answer_still_arrives_in_poll() {
    let h = Harness::new();
    let seen = h.client.api().lobbies_lobby_stats();
    let server = h.server.clone();
    std::thread::spawn(move || server.reply(200, "{}"))
        .join()
        .unwrap();
    assert!(!seen.is_ready());
    h.poll();
    assert!(got(&seen).ok());
}

#[test]
fn a_retry_sends_the_body_the_call_meant() {
    let h = Harness::new();
    h.signed_in();
    let seen = h
        .client
        .api()
        .lobbies_quick_join(json!({ "title": "first" }));
    h.server.reply(401, "{}");
    h.poll();
    h.server.reply(200, &session_reply(2));
    h.poll();
    assert_eq!(parsed(&h.server.next().body), json!({ "title": "first" }));
    h.server.reply(200, "{}");
    h.poll();
    assert!(got(&seen).ok());
}
