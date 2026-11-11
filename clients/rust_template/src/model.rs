//! Reading a reply into a typed value, and writing one back.
//!
//! `Model` is implemented for every struct in `gamend::models`, for the JSON
//! scalars, and for vectors, maps and options of any of them, so
//! `response.as_model::<models::Lobby>()` and
//! `response.as_model::<Vec<String>>()` both work. Reads are lenient and never
//! panic: a field that is missing or of the wrong type keeps its default, and
//! only a value that is not even the right kind (an object for a struct, an
//! array for a list) reads as nothing.

use std::collections::HashMap;

use serde_json::{Map, Value};

use crate::json::integer;

pub trait Model: Sized {
    /// `value` as this type. A field that is missing or mistyped keeps its
    /// default.
    fn read(value: &Value) -> Self;

    fn write(&self) -> Value;

    /// Whether `value` is the right kind at all. `Response::as_model` answers
    /// nothing when it is not.
    fn accepts(_value: &Value) -> bool {
        true
    }
}

/// `object[key]` into `out` when it is there and the right kind; `out` keeps its
/// default otherwise.
pub(crate) fn read_field<T: Model>(object: &Value, key: &str, out: &mut T) {
    if let Some(value) = object.get(key) {
        if T::accepts(value) {
            *out = T::read(value);
        }
    }
}

impl Model for String {
    fn read(value: &Value) -> Self {
        value.as_str().unwrap_or_default().to_string()
    }

    fn write(&self) -> Value {
        Value::String(self.clone())
    }

    fn accepts(value: &Value) -> bool {
        value.is_string()
    }
}

impl Model for i64 {
    fn read(value: &Value) -> Self {
        integer(value)
    }

    fn write(&self) -> Value {
        Value::from(*self)
    }

    fn accepts(value: &Value) -> bool {
        value.is_number()
    }
}

impl Model for f64 {
    fn read(value: &Value) -> Self {
        value.as_f64().unwrap_or_default()
    }

    fn write(&self) -> Value {
        Value::from(*self)
    }

    fn accepts(value: &Value) -> bool {
        value.is_number()
    }
}

impl Model for bool {
    fn read(value: &Value) -> Self {
        value.as_bool().unwrap_or_default()
    }

    fn write(&self) -> Value {
        Value::Bool(*self)
    }

    fn accepts(value: &Value) -> bool {
        value.is_boolean()
    }
}

impl Model for Value {
    fn read(value: &Value) -> Self {
        value.clone()
    }

    fn write(&self) -> Value {
        self.clone()
    }
}

impl<T: Model> Model for Vec<T> {
    fn read(value: &Value) -> Self {
        value.as_array().map_or_else(Vec::new, |items| {
            items
                .iter()
                .filter(|item| T::accepts(item))
                .map(T::read)
                .collect()
        })
    }

    fn write(&self) -> Value {
        Value::Array(self.iter().map(Model::write).collect())
    }

    fn accepts(value: &Value) -> bool {
        value.is_array()
    }
}

impl<T: Model> Model for HashMap<String, T> {
    fn read(value: &Value) -> Self {
        value.as_object().map_or_else(HashMap::new, |entries| {
            entries
                .iter()
                .filter(|(_, item)| T::accepts(item))
                .map(|(key, item)| (key.clone(), T::read(item)))
                .collect()
        })
    }

    fn write(&self) -> Value {
        let mut out = Map::new();
        for (key, item) in self {
            out.insert(key.clone(), item.write());
        }
        Value::Object(out)
    }

    fn accepts(value: &Value) -> bool {
        value.is_object()
    }
}

impl<T: Model> Model for Option<T> {
    fn read(value: &Value) -> Self {
        if !value.is_null() && T::accepts(value) {
            Some(T::read(value))
        } else {
            None
        }
    }

    fn write(&self) -> Value {
        self.as_ref().map_or(Value::Null, Model::write)
    }

    fn accepts(value: &Value) -> bool {
        value.is_null() || T::accepts(value)
    }
}
