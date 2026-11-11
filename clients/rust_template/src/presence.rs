//! Who is around: merged user profiles, lobbies and online state, kept up by the
//! realtime events as they arrive. A game reads instead of bookkeeping.
//!
//! Updates arrive as partial patches, metadata as sparse sections; they are
//! merged, so a profile only grows more complete. The signed-in player's own
//! `user:<id>` push carries the whole metadata map and replaces it, which is how
//! a key the server deleted disappears.

use std::collections::HashMap;
use std::sync::Arc;

use serde_json::{json, Map, Value};

use crate::core::{Core, Queue, Shared};
use crate::generated::events;
use crate::json::{field, text, text_or};

pub(crate) struct State {
    users: HashMap<String, Value>,
    lobbies: HashMap<String, Value>,
    online: HashMap<String, bool>,
    last_seen: HashMap<String, i64>,
    user_changes: Queue<String>,
    lobby_changes: Queue<Value>,
}

impl State {
    pub(crate) fn new(limit: usize) -> Self {
        Self {
            users: HashMap::new(),
            lobbies: HashMap::new(),
            online: HashMap::new(),
            last_seen: HashMap::new(),
            user_changes: Queue::new(limit),
            lobby_changes: Queue::new(limit),
        }
    }
}

/// Who is around, as the realtime events tell it.
#[derive(Clone)]
pub struct Presence {
    shared: Arc<Shared>,
}

impl Presence {
    pub(crate) fn new(shared: Arc<Shared>) -> Self {
        Self { shared }
    }

    /// The merged profile, or an empty object.
    pub fn user(&self, user_id: &str) -> Value {
        self.shared.with(|core| {
            core.presence
                .users
                .get(user_id)
                .cloned()
                .unwrap_or_else(|| json!({}))
        })
    }

    /// The lobby as last pushed, or an empty object.
    pub fn lobby(&self, lobby_id: &str) -> Value {
        self.shared.with(|core| {
            core.presence
                .lobbies
                .get(lobby_id)
                .cloned()
                .unwrap_or_else(|| json!({}))
        })
    }

    /// Online as far as this client knows; the signed-in player always is.
    pub fn online(&self, user_id: &str) -> bool {
        self.shared.with(|core| {
            let own = core
                .auth
                .session
                .as_ref()
                .is_some_and(|session| session.user_id == user_id);
            own || core.presence.online.get(user_id).copied().unwrap_or(false)
        })
    }

    /// When an offline player was last seen, in Unix seconds; 0 when unknown.
    pub fn last_seen(&self, user_id: &str) -> i64 {
        self.shared
            .with(|core| core.presence.last_seen.get(user_id).copied().unwrap_or(0))
    }

    /// Record presence learned elsewhere (a friend list, a search result).
    pub fn set_online(&self, user_id: &str, online: bool, last_seen: i64) {
        self.shared.with(|core| {
            core.presence.online.insert(user_id.to_string(), online);
            if !online && last_seen > 0 {
                core.presence
                    .last_seen
                    .insert(user_id.to_string(), last_seen);
            }
        });
    }

    /// Merge user data learned elsewhere (a REST answer, a member list).
    pub fn cache_user(&self, user_id: &str, data: &Value) {
        if user_id.is_empty() {
            return;
        }
        self.shared.with(|core| {
            merge_into(core, user_id, data, false);
            core.presence.user_changes.push(user_id.to_string());
        });
    }

    /// Forget everything. Signing out does it.
    pub fn clear(&self) {
        self.shared.with(clear);
    }

    /// The ids of the users whose profile or presence changed since the last
    /// call, oldest first, one entry per change.
    pub fn user_changes(&self) -> Vec<String> {
        self.shared
            .with(|core| core.drained(|core| &mut core.presence.user_changes))
    }

    /// The lobbies that changed since the last call, oldest first.
    pub fn lobby_changes(&self) -> Vec<Value> {
        self.shared
            .with(|core| core.drained(|core| &mut core.presence.lobby_changes))
    }

    /// Metadata merged one section deep: `{"player": {"hat": "x"}}` sets the hat
    /// without wiping the rest of `player`.
    pub fn merge_metadata(existing: &Value, patch: &Value) -> Value {
        let mut merged = existing.as_object().cloned().unwrap_or_else(Map::new);
        if let Some(entries) = patch.as_object() {
            for (key, value) in entries {
                let section = value.as_object();
                let current = merged.get_mut(key).and_then(Value::as_object_mut);
                if let (Some(section), Some(current)) = (section, current) {
                    for (name, item) in section {
                        current.insert(name.clone(), item.clone());
                    }
                } else {
                    merged.insert(key.clone(), value.clone());
                }
            }
        }
        Value::Object(merged)
    }
}

fn id_of(payload: &Value) -> String {
    let id = text(payload, "user_id");
    if id.is_empty() {
        text(payload, "id")
    } else {
        id
    }
}

pub(crate) fn event(core: &mut Core, kind: &str, payload: &Value) {
    match kind {
        events::USER_UPDATED => apply_user_update(core, payload),
        events::LOBBY_UPDATED => {
            let id = text(payload, "id");
            if !id.is_empty() {
                core.presence.lobbies.insert(id, payload.clone());
                core.presence.lobby_changes.push(payload.clone());
            }
        }
        events::LOBBY_STATE_CHANGED => {
            // The flip comes out of band; an `updated` in flight may still carry
            // the old state, so it is patched in and announced.
            let id = text(payload, "lobby_id");
            if id.is_empty() {
                return;
            }
            let lobby = core
                .presence
                .lobbies
                .entry(id.clone())
                .or_insert(Value::Null);
            if !lobby.is_object() {
                *lobby = json!({ "id": id });
            }
            lobby["state"] = json!(text(payload, "to"));
            let changed = lobby.clone();
            core.presence.lobby_changes.push(changed);
        }
        events::LOBBY_MEMBER_JOINED
        | events::LOBBY_MEMBER_UPDATED
        | events::PARTY_MEMBER_UPDATED
        | events::GROUP_MEMBER_UPDATED => {
            let id = id_of(payload);
            if !id.is_empty() {
                merge_into(core, &id, payload, false);
                core.presence.user_changes.push(id);
            }
        }
        events::LOBBY_MEMBER_ONLINE | events::PARTY_MEMBER_ONLINE | events::GROUP_MEMBER_ONLINE => {
            let id = id_of(payload);
            if !id.is_empty() {
                core.presence.online.insert(id.clone(), true);
                core.presence.user_changes.push(id);
            }
        }
        events::LOBBY_MEMBER_OFFLINE
        | events::PARTY_MEMBER_OFFLINE
        | events::GROUP_MEMBER_OFFLINE => {
            let id = id_of(payload);
            if !id.is_empty() {
                core.presence.online.insert(id.clone(), false);
                let now = core.unix_now();
                core.presence.last_seen.insert(id.clone(), now);
                core.presence.user_changes.push(id);
            }
        }
        _ => {}
    }
}

fn apply_user_update(core: &mut Core, user: &Value) {
    let own = core
        .auth
        .session
        .as_ref()
        .map(|session| session.user_id.clone())
        .unwrap_or_default();
    let id = text_or(user, "id", &own);
    if id.is_empty() {
        return;
    }
    // The `user:<id>` push is the one payload with the WHOLE metadata map; a
    // `u`-wrapped body is partial and merges.
    let wrapped = field(user, "u").is_object();
    let patch = if wrapped { field(user, "u") } else { user };
    merge_into(core, &id, patch, !wrapped);
    if id == own {
        // The player's own lobby_id is the truth: any other lobby is stale.
        let current = core
            .presence
            .users
            .get(&id)
            .map_or_else(String::new, |profile| text(profile, "lobby_id"));
        core.presence.lobbies.retain(|lobby, _| *lobby == current);
    }
    core.presence.user_changes.push(id);
}

fn merge_into(core: &mut Core, id: &str, patch: &Value, metadata_is_whole: bool) {
    let existing = core
        .presence
        .users
        .entry(id.to_string())
        .or_insert_with(|| json!({ "id": id }));
    let Some(entries) = patch.as_object() else {
        return;
    };
    for (key, value) in entries {
        if key == "metadata" && value.is_object() {
            let merged = if metadata_is_whole {
                value.clone()
            } else {
                Presence::merge_metadata(field(existing, "metadata"), value)
            };
            existing["metadata"] = merged;
        } else {
            existing[key.as_str()] = value.clone();
        }
    }
}

pub(crate) fn clear(core: &mut Core) {
    core.presence.users.clear();
    core.presence.lobbies.clear();
    core.presence.online.clear();
    core.presence.last_seen.clear();
}
