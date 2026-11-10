//! What a call answered.
//!
//! Every Gamend reply is one of four shapes: `{data}`, `{data, meta}`,
//! `{ok: true}` or `{error, message?, errors?}`. `data()`, `meta()`, `code()`
//! and `message()` read them without touching `body` directly.

use serde_json::Value;

use crate::generated::models::Page;
use crate::json::{field, text};
use crate::model::Model;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Response {
    /// The HTTP status; 0 when no reply arrived (the transport failed, or the
    /// SDK refused to send the call because a required field was missing).
    pub status: u16,
    /// The decoded body; null when it was empty or not JSON.
    pub body: Value,
    /// The body as it arrived: the bytes of a download, for one.
    pub bytes: Vec<u8>,
    /// Empty on success. Otherwise the server's error code (`not_found`,
    /// `validation_failed`, ...), `http_<status>` when it gave none, or what
    /// went wrong before a reply arrived.
    pub error: String,
}

impl Response {
    /// A reply that never came, and why.
    pub(crate) fn failed(error: impl Into<String>) -> Self {
        Self {
            error: error.into(),
            ..Self::default()
        }
    }

    pub fn ok(&self) -> bool {
        (200..300).contains(&self.status) && self.error.is_empty()
    }

    /// `body.data`: the object or list the call answered. Null otherwise.
    pub fn data(&self) -> &Value {
        field(&self.body, "data")
    }

    /// `body.meta` of a paged list: page, page_size, total_count, ...
    pub fn meta(&self) -> &Value {
        field(&self.body, "meta")
    }

    /// `body.error`, the machine-readable code; empty on success.
    pub fn code(&self) -> String {
        text(&self.body, "error")
    }

    /// `body.message`, the human-readable one, when the server sent it.
    pub fn message(&self) -> String {
        text(&self.body, "message")
    }

    /// `body.errors`: `{field: [messages]}` for `validation_failed`.
    pub fn errors(&self) -> &Value {
        field(&self.body, "errors")
    }

    /// The body as text, as it arrived.
    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.bytes).into_owned()
    }

    /// `data()` as a typed value: `as_model::<models::Lobby>()`, or
    /// `as_model::<Vec<String>>()`. Nothing when it is not that kind of value
    /// at all; a field that is missing keeps its default.
    pub fn as_model<T: Model>(&self) -> Option<T> {
        let data = self.data();
        T::accepts(data).then(|| T::read(data))
    }

    /// A page of `T` with its `meta`: `page::<models::Lobby>()` for
    /// `GET /lobbies`.
    pub fn page<T: Model>(&self) -> Option<Page<T>> {
        Page::<T>::accepts(&self.body).then(|| Page::read(&self.body))
    }
}
