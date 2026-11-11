//! A signed-in identity: the token pair and who it belongs to.

use serde_json::{json, Value};

use crate::json::{number, text};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Session {
    pub access_token: String,
    pub refresh_token: String,
    pub user_id: String,
    /// Empty when the sign-in did not say (OAuth).
    pub username: String,
    pub display_name: String,
    /// The access token's lifetime in seconds, as the server said (900 by
    /// default).
    pub expires_in: i64,
    /// When the access token lapses, in Unix seconds; 0 when unknown.
    pub expires_at: i64,
}

impl Session {
    /// For keeping it where the platform keeps secrets, and `from_json` back.
    pub fn to_json(&self) -> Value {
        json!({
            "access_token": self.access_token,
            "refresh_token": self.refresh_token,
            "user_id": self.user_id,
            "username": self.username,
            "display_name": self.display_name,
            "expires_in": self.expires_in,
            "expires_at": self.expires_at,
        })
    }

    /// A session from `to_json`'s output or a sign-in reply's `data`; nothing
    /// when there is no `access_token`. `now` (Unix seconds) turns a reply's
    /// `expires_in` into `expires_at` when the value carries no `expires_at`.
    pub fn from_json(value: &Value, now: i64) -> Option<Session> {
        let access_token = text(value, "access_token");
        if access_token.is_empty() {
            return None;
        }
        let expires_in = number(value, "expires_in");
        let mut expires_at = number(value, "expires_at");
        if expires_at == 0 && expires_in > 0 && now > 0 {
            expires_at = now + expires_in;
        }
        Some(Session {
            access_token,
            refresh_token: text(value, "refresh_token"),
            user_id: text(value, "user_id"),
            username: text(value, "username"),
            display_name: text(value, "display_name"),
            expires_in,
            expires_at,
        })
    }
}
