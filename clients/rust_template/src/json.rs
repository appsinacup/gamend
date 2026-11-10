//! Reading a reply without being able to fail: these answer a fallback where
//! `value["key"].as_str().unwrap()` would panic.

use serde_json::Value;

static NULL: Value = Value::Null;

/// `object[key]` as text, or empty when it is missing or not a string.
pub fn text(object: &Value, key: &str) -> String {
    text_or(object, key, "")
}

/// `object[key]` as text, or `fallback` when it is missing or not a string.
pub fn text_or(object: &Value, key: &str, fallback: &str) -> String {
    object
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or(fallback)
        .to_string()
}

/// `object[key]` as an integer, or 0 when it is missing or not a number.
pub fn number(object: &Value, key: &str) -> i64 {
    object.get(key).map_or(0, integer)
}

/// A number as an integer: a float is cut, and anything else is 0.
pub(crate) fn integer(value: &Value) -> i64 {
    value
        .as_i64()
        .or_else(|| value.as_u64().map(|n| n as i64))
        .or_else(|| value.as_f64().map(|n| n as i64))
        .unwrap_or(0)
}

/// `object[key]`, or null when it is missing or `object` is not an object.
pub fn field<'a>(object: &'a Value, key: &str) -> &'a Value {
    object.get(key).unwrap_or(&NULL)
}

/// Serialized for the wire.
pub fn dump(value: &Value) -> String {
    value.to_string()
}

/// Parsed, or nothing when `text` is not JSON.
pub fn parse(text: &[u8]) -> Option<Value> {
    serde_json::from_slice(text).ok()
}
