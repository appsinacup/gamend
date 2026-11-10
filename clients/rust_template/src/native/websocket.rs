//! WebSocket over tungstenite, one thread per connection. A tungstenite socket is
//! one object for both directions, so that thread reads with a short timeout and
//! sends what has queued up between reads.

use std::io;
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::mpsc::{channel, Receiver, Sender, TryRecvError};
use std::sync::{Mutex, MutexGuard, PoisonError};
use std::thread;
use std::time::{Duration, Instant};

use tungstenite::http::Uri;
use tungstenite::stream::MaybeTlsStream;
use tungstenite::{client_tls_with_config, Error, Message, WebSocket};

use crate::transport::{WebSocketHandlers, WebSocketTransport};

type Socket = WebSocket<MaybeTlsStream<TcpStream>>;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const WRITE_TIMEOUT: Duration = Duration::from_secs(10);
// How long a queued send can wait behind a read with nothing to say.
const READ_POLL: Duration = Duration::from_millis(5);
// How long a closing socket waits for the server's own close frame.
const CLOSE_LINGER: Duration = Duration::from_secs(1);

enum Command {
    Text(String),
    Close,
}

/// `WebSocketTransport` over tungstenite, with rustls for TLS.
#[derive(Default)]
pub struct TungsteniteTransport {
    current: Mutex<Option<Sender<Command>>>,
}

impl TungsteniteTransport {
    pub fn new() -> Self {
        Self::default()
    }

    fn lock(&self) -> MutexGuard<'_, Option<Sender<Command>>> {
        self.current.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

impl WebSocketTransport for TungsteniteTransport {
    fn open(&self, url: &str, handlers: WebSocketHandlers) {
        let (commands, inbox) = channel();
        if let Some(old) = self.lock().replace(commands) {
            let _ = old.send(Command::Close);
        }
        let url = url.to_string();
        let reporter = handlers.clone();
        let spawned = thread::Builder::new()
            .name("gamend-websocket".to_string())
            .spawn(move || run(&url, &inbox, &handlers));
        if let Err(error) = spawned {
            reporter.on_error(format!("could not start a socket thread: {error}"));
        }
    }

    fn send_text(&self, frame: String) {
        if let Some(commands) = self.lock().as_ref() {
            let _ = commands.send(Command::Text(frame));
        }
    }

    fn close(&self) {
        if let Some(commands) = self.lock().take() {
            let _ = commands.send(Command::Close);
        }
    }
}

impl Drop for TungsteniteTransport {
    fn drop(&mut self) {
        self.close();
    }
}

fn stream_of(socket: &Socket) -> Option<&TcpStream> {
    match socket.get_ref() {
        MaybeTlsStream::Plain(stream) => Some(stream),
        MaybeTlsStream::Rustls(stream) => Some(stream.get_ref()),
        _ => None,
    }
}

fn dial(uri: &Uri) -> Result<TcpStream, String> {
    let host = uri.host().ok_or("the url names no host")?;
    let host = host.trim_start_matches('[').trim_end_matches(']');
    let secure = uri.scheme_str() == Some("wss");
    let port = uri.port_u16().unwrap_or(if secure { 443 } else { 80 });
    let addresses = (host, port)
        .to_socket_addrs()
        .map_err(|error| format!("{host}: {error}"))?;
    let mut last = format!("{host}: no address");
    for address in addresses {
        match TcpStream::connect_timeout(&address, CONNECT_TIMEOUT) {
            Ok(stream) => return Ok(stream),
            Err(error) => last = format!("{address}: {error}"),
        }
    }
    Err(last)
}

fn connect(url: &str) -> Result<Socket, String> {
    let uri: Uri = url.parse().map_err(|error| format!("{error}"))?;
    let stream = dial(&uri)?;
    let timeouts = stream
        .set_nodelay(true)
        .and_then(|()| stream.set_read_timeout(Some(CONNECT_TIMEOUT)))
        .and_then(|()| stream.set_write_timeout(Some(WRITE_TIMEOUT)));
    timeouts.map_err(|error| error.to_string())?;
    let (socket, _) =
        client_tls_with_config(url, stream, None, None).map_err(|error| error.to_string())?;
    if let Some(stream) = stream_of(&socket) {
        stream
            .set_read_timeout(Some(READ_POLL))
            .map_err(|error| error.to_string())?;
    }
    Ok(socket)
}

fn would_block(error: &io::Error) -> bool {
    matches!(
        error.kind(),
        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
    )
}

fn run(url: &str, commands: &Receiver<Command>, handlers: &WebSocketHandlers) {
    let mut socket = match connect(url) {
        Ok(socket) => socket,
        Err(error) => {
            handlers.on_error(error);
            return;
        }
    };
    handlers.on_open();
    loop {
        loop {
            match commands.try_recv() {
                Ok(Command::Text(frame)) => {
                    if let Err(error) = socket.send(Message::text(frame)) {
                        handlers.on_error(error.to_string());
                        return;
                    }
                }
                Ok(Command::Close) | Err(TryRecvError::Disconnected) => {
                    linger(&mut socket);
                    return;
                }
                Err(TryRecvError::Empty) => break,
            }
        }
        match socket.read() {
            Ok(Message::Text(text)) => handlers.on_text(text.to_string()),
            Ok(Message::Binary(bytes)) => handlers.on_binary(bytes.to_vec()),
            Ok(Message::Close(frame)) => {
                let (code, reason) = frame.map_or((1005, String::new()), |frame| {
                    (u16::from(frame.code), frame.reason.to_string())
                });
                // tungstenite queued its answer; this sends it.
                let _ = socket.flush();
                handlers.on_close(code, reason);
                return;
            }
            Ok(_) => {}
            Err(Error::Io(error)) if would_block(&error) => {}
            Err(Error::ConnectionClosed | Error::AlreadyClosed) => {
                handlers.on_close(1006, String::new());
                return;
            }
            Err(error) => {
                handlers.on_error(error.to_string());
                return;
            }
        }
    }
}

// Say goodbye and give the server a moment to say it back. Nobody waits on this
// thread, and the client has already stopped listening to it.
fn linger(socket: &mut Socket) {
    if socket.close(None).is_err() {
        return;
    }
    let deadline = Instant::now() + CLOSE_LINGER;
    while Instant::now() < deadline {
        match socket.read() {
            Ok(_) => {}
            Err(Error::Io(error)) if would_block(&error) => {}
            Err(_) => return,
        }
    }
}
