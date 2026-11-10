//! What every generated call needs: an escaped path segment, a query string,
//! and the required-field check.

use serde_json::Value;

use crate::json::dump;

const HEX: &[u8; 16] = b"0123456789ABCDEF";

/// Percent-encoding of everything but RFC 3986's unreserved characters, so a
/// value is safe in a path segment and in a query alike.
pub fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for byte in text.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            out.push(char::from(byte));
        } else {
            out.push('%');
            out.push(char::from(HEX[usize::from(byte >> 4)]));
            out.push(char::from(HEX[usize::from(byte & 0x0F)]));
        }
    }
    out
}

/// Whether `table` carries `key` with a value. A key set to null is absent: the
/// server would refuse it, and refusing here names the field instead.
pub fn given(table: &Value, key: &str) -> bool {
    table.get(key).is_some_and(|value| !value.is_null())
}

fn text_of(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        other => dump(other),
    }
}

/// `?a=1&b=2` for the keys an operation declares, in the order it declares them,
/// skipping the ones `options` leaves out. Empty when none are given.
pub fn query(options: &Value, allowed: &[&str]) -> String {
    let mut out = String::new();
    for key in allowed {
        if !given(options, key) {
            continue;
        }
        out.push(if out.is_empty() { '?' } else { '&' });
        out.push_str(&escape(key));
        out.push('=');
        out.push_str(&escape(&text_of(&options[*key])));
    }
    out
}
