//! The shipped transports against real sockets on this machine: a few lines of
//! HTTP over a listener, and tungstenite's own server side.

use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::mpsc::{channel, Receiver};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use gamend::{
    json, Client, Config, HttpRequest, HttpResponse, HttpTransport, Session, TungsteniteTransport,
    UreqTransport, WebSocketEvent, WebSocketHandlers, WebSocketTransport,
};
use tungstenite::Message;

const WAIT: Duration = Duration::from_secs(10);

// Answers one request with `reply`, and hands back what it read.
fn http_once(reply: &'static str) -> (String, Receiver<String>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let (found, seen) = channel();
    thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut read = Vec::new();
        let mut chunk = [0; 1024];
        loop {
            let n = stream.read(&mut chunk).unwrap();
            read.extend_from_slice(&chunk[..n]);
            let text = String::from_utf8_lossy(&read);
            if let Some((head, body)) = text.split_once("\r\n\r\n") {
                let length = head
                    .lines()
                    .find_map(|line| {
                        line.to_lowercase()
                            .strip_prefix("content-length: ")
                            .map(str::to_string)
                    })
                    .and_then(|size| size.parse::<usize>().ok())
                    .unwrap_or(0);
                if body.len() >= length {
                    break;
                }
            }
        }
        stream.write_all(reply.as_bytes()).unwrap();
        found
            .send(String::from_utf8_lossy(&read).into_owned())
            .unwrap();
    });
    (format!("http://{address}/thing"), seen)
}

fn send(transport: &UreqTransport, request: HttpRequest) -> HttpResponse {
    let (done, answered) = channel();
    transport.send(
        request,
        Box::new(move |reply| {
            done.send(reply).unwrap();
        }),
    );
    answered.recv_timeout(WAIT).unwrap()
}

#[test]
fn ureq_sends_the_request_and_answers_a_4xx_as_a_reply() {
    let (url, seen) = http_once(
        "HTTP/1.1 404 Not Found\r\ncontent-length: 7\r\nconnection: close\r\n\r\n{\"a\":1}",
    );
    let transport = UreqTransport::new();
    let reply = send(
        &transport,
        HttpRequest {
            method: "POST".to_string(),
            url,
            body: b"{\"b\":2}".to_vec(),
            headers: vec![
                ("content-type".to_string(), "application/json".to_string()),
                ("x-gamend-session".to_string(), "run-9".to_string()),
            ],
            timeout: WAIT,
        },
    );
    assert_eq!(reply.status, 404);
    assert_eq!(reply.body, b"{\"a\":1}");
    assert!(reply.error.is_empty());
    let request = seen.recv_timeout(WAIT).unwrap();
    assert!(request.starts_with("POST /thing HTTP/1.1"));
    assert!(request.to_lowercase().contains("x-gamend-session: run-9"));
    assert!(request.ends_with("{\"b\":2}"));
}

#[test]
fn ureq_reports_a_refused_connection_as_no_reply() {
    // A port that was just free, and is closed again by the time it is dialed.
    let address = TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap();
    let transport = UreqTransport::new();
    let reply = send(
        &transport,
        HttpRequest {
            method: "GET".to_string(),
            url: format!("http://{address}/"),
            timeout: WAIT,
            ..HttpRequest::default()
        },
    );
    assert_eq!(reply.status, 0);
    assert!(!reply.error.is_empty());
}

// One connection that echoes text, sends a binary frame, then closes.
fn echo_server() -> String {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut socket = tungstenite::accept(stream).unwrap();
        let Message::Text(text) = socket.read().unwrap() else {
            panic!("expected text");
        };
        socket.send(Message::text(format!("echo {text}"))).unwrap();
        socket.send(Message::binary(vec![1, 2, 3])).unwrap();
        socket.close(None).unwrap();
        while socket.read().is_ok() {}
    });
    format!("ws://{address}/socket")
}

fn handlers() -> (WebSocketHandlers, Receiver<WebSocketEvent>) {
    let (found, seen) = channel();
    let found = Arc::new(std::sync::Mutex::new(found));
    let handlers = WebSocketHandlers::new(move |event| {
        let _ = found.lock().unwrap().send(event);
    });
    (handlers, seen)
}

#[test]
fn tungstenite_opens_sends_receives_and_reports_the_close() {
    let transport = TungsteniteTransport::new();
    let (handlers, seen) = handlers();
    transport.open(&echo_server(), handlers);
    assert_eq!(seen.recv_timeout(WAIT).unwrap(), WebSocketEvent::Open);
    transport.send_text("hello".to_string());
    assert_eq!(
        seen.recv_timeout(WAIT).unwrap(),
        WebSocketEvent::Text("echo hello".to_string())
    );
    assert_eq!(
        seen.recv_timeout(WAIT).unwrap(),
        WebSocketEvent::Binary(vec![1, 2, 3])
    );
    assert!(matches!(
        seen.recv_timeout(WAIT).unwrap(),
        WebSocketEvent::Close { .. }
    ));
}

#[test]
fn tungstenite_reports_a_refused_connection_as_an_error() {
    let address = TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap();
    let transport = TungsteniteTransport::new();
    let (handlers, seen) = handlers();
    transport.open(&format!("ws://{address}/socket"), handlers);
    assert!(matches!(
        seen.recv_timeout(WAIT).unwrap(),
        WebSocketEvent::Error(_)
    ));
}

#[test]
fn a_client_over_the_real_transports_joins_and_hears_an_event() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut socket = tungstenite::accept(stream).unwrap();
        let Message::Text(join) = socket.read().unwrap() else {
            panic!("expected the join");
        };
        let join: serde_json::Value = serde_json::from_str(join.as_str()).unwrap();
        let answer = json!([join[0], join[1], join[2], "phx_reply",
                            { "status": "ok", "response": {} }]);
        socket.send(Message::text(answer.to_string())).unwrap();
        let event = json!([null, null, "user:u1", "updated", { "id": "u1" }]);
        socket.send(Message::text(event.to_string())).unwrap();
        while socket.read().is_ok() {}
    });

    let client = Client::new(Config::native(format!("http://{address}")));
    client.auth().restore(Session {
        access_token: "a1".to_string(),
        user_id: "u1".to_string(),
        expires_in: 900,
        ..Session::default()
    });
    client.realtime().connect();
    let mut heard = Vec::new();
    let deadline = Instant::now() + WAIT;
    while heard.is_empty() && Instant::now() < deadline {
        client.poll();
        heard = client.drain_events();
        thread::sleep(Duration::from_millis(1));
    }
    assert_eq!(heard.len(), 1);
    assert_eq!(heard[0].kind, gamend::events::USER_UPDATED);
    assert!(client.realtime().joined("user:u1"));
    client.realtime().disconnect();
}
