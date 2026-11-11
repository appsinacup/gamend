//! Live key-value rows: subscribe once, read any time, hear every change.
//!
//! A subscription outlives the connection: every time the user channel (re)joins,
//! each one is sent again and its reply refreshes the row. The cache also takes
//! `fetch` results, so a game can paint what it knows before the socket is up.

use std::collections::BTreeMap;
use std::mem;
use std::sync::Arc;

use serde_json::{json, Value};

use crate::client::LogLevel;
use crate::core::{Core, Queue, Shared};
use crate::generated::events;
use crate::json::{field, text};
use crate::query::{escape, query};
use crate::realtime::{self, Reply};
use crate::rest::{self, Body};
use crate::ticket::{Completer, Ticket};

/// Which row: a key, global or scoped to a user or a lobby.
#[derive(Clone, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct KvKey {
    pub key: String,
    pub user_id: String,
    pub lobby_id: String,
}

impl KvKey {
    /// A global key.
    pub fn new(key: impl Into<String>) -> Self {
        Self {
            key: key.into(),
            ..Self::default()
        }
    }

    pub fn of_user(key: impl Into<String>, user_id: impl Into<String>) -> Self {
        Self {
            key: key.into(),
            user_id: user_id.into(),
            ..Self::default()
        }
    }

    pub fn of_lobby(key: impl Into<String>, lobby_id: impl Into<String>) -> Self {
        Self {
            key: key.into(),
            lobby_id: lobby_id.into(),
            ..Self::default()
        }
    }
}

impl From<&str> for KvKey {
    fn from(key: &str) -> Self {
        Self::new(key)
    }
}

impl From<String> for KvKey {
    fn from(key: String) -> Self {
        Self::new(key)
    }
}

/// A row as the cache knows it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct KvRow {
    /// False: the server said there is no such row (yet).
    pub exists: bool,
    pub data: Value,
    pub metadata: Value,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct KvResult {
    pub ok: bool,
    pub row: KvRow,
    /// Why not: the server's code (`forbidden`, `invalid_key`), or the
    /// transport's.
    pub error: String,
}

pub(crate) struct State {
    rows: BTreeMap<KvKey, KvRow>,
    subscriptions: BTreeMap<KvKey, Vec<Completer<KvResult>>>,
    confirmed: BTreeMap<KvKey, bool>,
    changes: Queue<(KvKey, KvRow)>,
}

impl State {
    pub(crate) fn new(limit: usize) -> Self {
        Self {
            rows: BTreeMap::new(),
            subscriptions: BTreeMap::new(),
            confirmed: BTreeMap::new(),
            changes: Queue::new(limit),
        }
    }
}

fn scope_payload(key: &KvKey) -> Value {
    let mut payload = json!({ "key": key.key });
    if !key.user_id.is_empty() {
        payload["user_id"] = json!(key.user_id);
    }
    if !key.lobby_id.is_empty() {
        payload["lobby_id"] = json!(key.lobby_id);
    }
    payload
}

fn key_of(payload: &Value) -> KvKey {
    KvKey {
        key: text(payload, "key"),
        user_id: text(payload, "user_id"),
        lobby_id: text(payload, "lobby_id"),
    }
}

/// Live key-value rows over the realtime connection, and their cache.
#[derive(Clone)]
pub struct Kv {
    shared: Arc<Shared>,
}

impl Kv {
    pub(crate) fn new(shared: Arc<Shared>) -> Self {
        Self { shared }
    }

    /// Subscribe to a row: `kv_updated` and `kv_deleted` keep it current from
    /// now on, over every reconnect, until `unsubscribe`. The ticket gets the
    /// current row, or why the server refused (a refusal is not retried).
    pub fn subscribe(&self, key: impl Into<KvKey>) -> Ticket<KvResult> {
        let key = key.into();
        self.shared.start(|core, ticket| {
            let fresh = !core.kv.subscriptions.contains_key(&key);
            core.kv
                .subscriptions
                .entry(key.clone())
                .or_default()
                .push(ticket);
            if fresh && realtime::joined(core, &realtime::user_topic(core)) {
                send_subscribe(core, key);
            }
        })
    }

    pub fn unsubscribe(&self, key: impl Into<KvKey>) {
        let key = key.into();
        self.shared.with(|core| {
            if core.kv.subscriptions.remove(&key).is_none() {
                return;
            }
            core.kv.confirmed.remove(&key);
            let topic = realtime::user_topic(core);
            if realtime::joined(core, &topic) {
                realtime::push(core, &topic, "kv:unsubscribe", &scope_payload(&key), None);
            }
        });
    }

    pub fn subscribed(&self, key: impl Into<KvKey>) -> bool {
        let key = key.into();
        self.shared
            .with(|core| core.kv.confirmed.get(&key).copied().unwrap_or(false))
    }

    /// The row as last seen, or nothing when this client never learned it.
    pub fn row(&self, key: impl Into<KvKey>) -> Option<KvRow> {
        let key = key.into();
        self.shared.with(|core| core.kv.rows.get(&key).cloned())
    }

    /// The row from the cache, or `GET /api/v1/kv/{key}` when it is not there
    /// (or `force`). A 404 caches "no such row"; a failure caches nothing.
    pub fn fetch(&self, key: impl Into<KvKey>, force: bool) -> Ticket<KvResult> {
        let key = key.into();
        self.shared.start(|core, ticket| {
            if !force {
                if let Some(row) = core.kv.rows.get(&key).cloned() {
                    let hit = KvResult {
                        ok: true,
                        row,
                        error: String::new(),
                    };
                    core.complete(ticket, hit);
                    return;
                }
            }
            let mut options = json!({});
            if !key.user_id.is_empty() {
                options["user_id"] = json!(key.user_id);
            }
            if !key.lobby_id.is_empty() {
                options["lobby_id"] = json!(key.lobby_id);
            }
            let path = format!(
                "/api/v1/kv/{}{}",
                escape(&key.key),
                query(&options, &["user_id", "lobby_id"])
            );
            rest::send(
                core,
                true,
                "GET",
                path,
                Body::none(),
                Box::new(move |core, r| {
                    let mut result = KvResult::default();
                    if r.ok() {
                        result.ok = true;
                        result.row.exists = true;
                        result.row.data = field(r.data(), "data").clone();
                        result.row.metadata = field(r.data(), "metadata").clone();
                        store(core, &key, &result.row);
                    } else if r.status == 404 {
                        // The server's word that there is no row.
                        result.ok = true;
                        store(core, &key, &result.row);
                    } else {
                        result.error = r.error;
                    }
                    core.complete(ticket, result);
                }),
            );
        })
    }

    /// Every change to a cached row since the last call, from any source.
    pub fn changes(&self) -> Vec<(KvKey, KvRow)> {
        self.shared
            .with(|core| core.drained(|core| &mut core.kv.changes))
    }

    /// Forget every row and subscription. Signing out does it.
    pub fn clear(&self) {
        self.shared.with(clear);
    }
}

fn send_subscribe(core: &mut Core, key: KvKey) {
    let topic = realtime::user_topic(core);
    let payload = scope_payload(&key);
    realtime::push(
        core,
        &topic,
        "kv:subscribe",
        &payload,
        Some(Box::new(move |core, reply| subscribed(core, &key, reply))),
    );
}

fn subscribed(core: &mut Core, key: &KvKey, reply: Reply) {
    let Some(waiting) = core.kv.subscriptions.get_mut(key) else {
        return; // unsubscribed meanwhile
    };
    let waiting = mem::take(waiting);
    let mut result = KvResult::default();
    if reply.ok {
        core.kv.confirmed.insert(key.clone(), true);
        result.ok = true;
        result.row.exists = field(&reply.response, "missing").as_bool() != Some(true);
        result.row.data = field(&reply.response, "data").clone();
        result.row.metadata = field(&reply.response, "metadata").clone();
        store(core, key, &result.row);
    } else {
        result.error.clone_from(&reply.error);
        if reply.status == "error" {
            // Forbidden or invalid: asking again will not change the answer.
            core.kv.subscriptions.remove(key);
            core.log(
                LogLevel::Warning,
                format!(
                    "gamend: kv subscribe to {} refused: {}",
                    key.key, reply.error
                ),
            );
        }
    }
    for done in waiting {
        core.complete(done, result.clone());
    }
}

pub(crate) fn user_channel_joined(core: &mut Core) {
    // A fresh join means the server forgot every subscription.
    core.kv.confirmed.clear();
    let keys: Vec<KvKey> = core.kv.subscriptions.keys().cloned().collect();
    for key in keys {
        send_subscribe(core, key);
    }
}

fn store(core: &mut Core, key: &KvKey, row: &KvRow) {
    core.kv.rows.insert(key.clone(), row.clone());
    core.kv.changes.push((key.clone(), row.clone()));
}

pub(crate) fn event(core: &mut Core, kind: &str, payload: &Value) {
    if kind == events::KV_UPDATED {
        let row = KvRow {
            exists: true,
            data: field(payload, "data").clone(),
            metadata: field(payload, "metadata").clone(),
        };
        store(core, &key_of(payload), &row);
    } else if kind == events::KV_DELETED {
        store(core, &key_of(payload), &KvRow::default());
    }
}

pub(crate) fn clear(core: &mut Core) {
    core.kv.rows.clear();
    core.kv.subscriptions.clear();
    core.kv.confirmed.clear();
}
