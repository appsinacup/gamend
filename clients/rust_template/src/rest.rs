//! The REST layer: one authenticated JSON caller for the whole API.
//!
//! `Api` is generated over it, one method per operation; call it directly for a
//! path `Api` does not know yet. An authenticated call that answers 401 while a
//! refresh token is in hand refreshes the session once and is sent again, so an
//! expired access token heals without the caller seeing it.

use std::sync::Arc;

use serde_json::Value;

use crate::auth;
use crate::client::LogLevel;
use crate::core::{Core, Shared};
use crate::json::{dump, parse};
use crate::response::Response;
use crate::ticket::Ticket;
use crate::transport::{HttpRequest, HttpResponse};

const USER_AGENT: &str = concat!("gamend-rust/", env!("CARGO_PKG_VERSION"));

/// What a call sends: nothing, a JSON value, or raw bytes.
#[derive(Clone, Debug, Default, PartialEq)]
pub enum Body {
    #[default]
    None,
    Json(Value),
    Bytes {
        bytes: Vec<u8>,
        content_type: String,
    },
}

impl Body {
    pub fn none() -> Self {
        Self::None
    }

    pub fn of(value: Value) -> Self {
        Self::Json(value)
    }

    /// Raw bytes as `application/octet-stream`.
    pub fn raw(bytes: Vec<u8>) -> Self {
        Self::raw_as(bytes, "application/octet-stream")
    }

    pub fn raw_as(bytes: Vec<u8>, content_type: impl Into<String>) -> Self {
        Self::Bytes {
            bytes,
            content_type: content_type.into(),
        }
    }
}

/// What the SDK does with a reply it asked for itself.
pub(crate) type Done = Box<dyn FnOnce(&mut Core, Response) + Send>;

struct Call {
    method: String,
    path: String,
    body: Body,
    done: Done,
    authenticated: bool,
    retried: bool,
}

/// The authenticated caller `Api` is built on, for a path it lacks.
#[derive(Clone)]
pub struct Rest {
    shared: Arc<Shared>,
}

impl Rest {
    pub(crate) fn new(shared: Arc<Shared>) -> Self {
        Self { shared }
    }

    /// `method` on `path` (`/api/v1/...`, query included) with the session's
    /// bearer token when there is one.
    pub fn send(&self, method: &str, path: impl Into<String>, body: Body) -> Ticket<Response> {
        let path = path.into();
        self.shared.start(|core, ticket| {
            send(
                core,
                true,
                method,
                path,
                body,
                Box::new(move |core, reply| core.complete(ticket, reply)),
            );
        })
    }

    /// The same without the bearer token and without the refresh on 401:
    /// sign-in and refresh themselves go this way.
    pub fn send_anonymous(
        &self,
        method: &str,
        path: impl Into<String>,
        body: Body,
    ) -> Ticket<Response> {
        let path = path.into();
        self.shared.start(|core, ticket| {
            send(
                core,
                false,
                method,
                path,
                body,
                Box::new(move |core, reply| core.complete(ticket, reply)),
            );
        })
    }

    /// Complete, on the next `poll()`, with the error a call gets when the SDK
    /// will not send it: ``<call> needs `<field>` ``.
    pub fn refuse(&self, call: &str, field: &str) -> Ticket<Response> {
        let message = format!("{call} needs `{field}`");
        self.shared.start(|core, ticket| {
            core.log(LogLevel::Error, format!("gamend: {message}"));
            core.complete(ticket, Response::failed(message));
        })
    }
}

pub(crate) fn send(
    core: &mut Core,
    authenticated: bool,
    method: &str,
    path: String,
    body: Body,
    done: Done,
) {
    start(
        core,
        Call {
            method: method.to_string(),
            path,
            body,
            done,
            authenticated,
            retried: false,
        },
    );
}

fn carries_body(method: &str) -> bool {
    matches!(method, "POST" | "PUT" | "PATCH")
}

fn start(core: &mut Core, call: Call) {
    let mut request = HttpRequest {
        method: call.method.clone(),
        url: format!("{}{}", core.base_url, call.path),
        body: Vec::new(),
        headers: vec![
            ("accept".to_string(), "application/json".to_string()),
            ("user-agent".to_string(), USER_AGENT.to_string()),
            ("x-gamend-session".to_string(), core.run_id.clone()),
        ],
        timeout: core.config.http_timeout,
    };
    if call.authenticated {
        if let Some(bearer) = auth::bearer(core) {
            request.headers.push(("authorization".to_string(), bearer));
        }
    }
    let json_type = ("content-type".to_string(), "application/json".to_string());
    match &call.body {
        Body::Json(value) => {
            // A null body is an empty object.
            request.body = if value.is_null() {
                b"{}".to_vec()
            } else {
                dump(value).into_bytes()
            };
            request.headers.push(json_type);
        }
        Body::Bytes {
            bytes,
            content_type,
        } => {
            request.body.clone_from(bytes);
            request
                .headers
                .push(("content-type".to_string(), content_type.clone()));
        }
        Body::None => {
            if carries_body(&call.method) {
                request.body = b"{}".to_vec();
                request.headers.push(json_type);
            }
        }
    }

    let Some(http) = core.config.http.clone() else {
        let reply = HttpResponse {
            error: "no HTTP transport configured".to_string(),
            ..HttpResponse::default()
        };
        core.post(move |core| finish(core, call, reply));
        return;
    };
    // The transport completes on its own thread; the reply crosses to the
    // polling thread through the inbox, and is dropped there if the client is
    // gone.
    let post = core.poster();
    http.send(
        request,
        Box::new(move |reply| post.post(move |core| finish(core, call, reply))),
    );
}

fn finish(core: &mut Core, mut call: Call, reply: HttpResponse) {
    let mut response = Response {
        status: reply.status,
        body: Value::Null,
        bytes: reply.body,
        error: String::new(),
    };
    if !response.bytes.is_empty() {
        if let Some(parsed) = parse(&response.bytes) {
            response.body = parsed;
        }
    }
    if response.status == 0 {
        response.error = if reply.error.is_empty() {
            "no reply".to_string()
        } else {
            reply.error
        };
    } else if !(200..300).contains(&response.status) {
        let code = response.code();
        response.error = if code.is_empty() {
            format!("http_{}", response.status)
        } else {
            code
        };
    }

    if response.status == 401 && call.authenticated && !call.retried {
        call.retried = true;
        auth::refresh_then(
            core,
            Box::new(move |core, refreshed| {
                if refreshed {
                    start(core, call);
                } else {
                    (call.done)(core, response);
                }
            }),
        );
        return;
    }
    (call.done)(core, response);
}
