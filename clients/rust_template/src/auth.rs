//! Signing in, and staying signed in.
//!
//! Gamend issues a short-lived access token (`expires_in`, 15 minutes by
//! default) and a refresh token (30 days by default). `Auth` keeps both,
//! refreshes the access token when three quarters of its life have passed, and
//! `Rest` refreshes once more on a 401. The game keeps the session between runs
//! where its platform keeps secrets: `session_changes` hands it over, `restore`
//! takes it back.

use std::mem;
use std::sync::Arc;
use std::time::Duration;

use serde_json::json;

use crate::client::LogLevel;
use crate::core::{Core, Queue, Shared};
use crate::json::{field, text, text_or};
use crate::query::escape;
use crate::response::Response;
use crate::rest::{self, Body, Done};
use crate::session::Session;
use crate::ticket::{Completer, Ticket};
use crate::{kv, presence, realtime};

// Refresh when three quarters of the token's life have passed, and at once when
// less than this is left.
const REFRESH_MARGIN: i64 = 60;
// How long to wait before trying again when the refresh could not reach the
// server; the session stays until the server says it is no good.
const REFRESH_RETRY: Duration = Duration::from_secs(30);

#[derive(Clone, Debug, Default, PartialEq)]
pub struct AuthResult {
    pub ok: bool,
    /// Why it failed: the server's code (`invalid_credentials`, ...) or what
    /// went wrong before it answered. Empty on success.
    pub error: String,
    /// The session signed in with; empty unless `ok`.
    pub session: Session,
    /// The last reply behind the result, for its `message()` or `errors()`.
    pub response: Response,
}

fn failed(response: Response, error: &str) -> AuthResult {
    let error = if !error.is_empty() {
        error.to_string()
    } else if !response.error.is_empty() {
        response.error.clone()
    } else {
        "unexpected_reply".to_string()
    };
    AuthResult {
        error,
        response,
        ..AuthResult::default()
    }
}

pub(crate) type RefreshThen = Box<dyn FnOnce(&mut Core, bool) + Send>;

pub(crate) struct State {
    pub(crate) session: Option<Session>,
    changes: Queue<Option<Session>>,
    refreshing: bool,
    waiters: Vec<RefreshThen>,
    refresh_timer: u64,
    // Bumped by every provider page (a sign-in or a link) and by its end, so a
    // reply or a timer from one that is over finds a different number and does
    // nothing.
    page_attempt: u64,
    page_timer: u64,
    on_page: bool,
    page_finish: Option<Done>,
}

impl State {
    pub(crate) fn new(limit: usize) -> Self {
        Self {
            session: None,
            changes: Queue::new(limit),
            refreshing: false,
            waiters: Vec::new(),
            refresh_timer: 0,
            page_attempt: 0,
            page_timer: 0,
            on_page: false,
            page_finish: None,
        }
    }
}

/// Signing in, and staying signed in.
#[derive(Clone)]
pub struct Auth {
    shared: Arc<Shared>,
}

impl Auth {
    pub(crate) fn new(shared: Arc<Shared>) -> Self {
        Self { shared }
    }

    fn sign_in_with(&self, path: &'static str, body: serde_json::Value) -> Ticket<AuthResult> {
        self.shared.start(|core, ticket| {
            rest::send(
                core,
                false,
                "POST",
                path.to_string(),
                Body::of(body),
                Box::new(move |core, reply| finish_sign_in(core, ticket, reply)),
            );
        })
    }

    /// Any string; an unknown id makes an anonymous account when the server has
    /// device sign-in enabled (its default).
    pub fn login_device(&self, device_id: &str) -> Ticket<AuthResult> {
        self.sign_in_with("/api/v1/login/device", json!({ "device_id": device_id }))
    }

    pub fn login_email(&self, email: &str, password: &str) -> Ticket<AuthResult> {
        self.sign_in_with(
            "/api/v1/login",
            json!({ "email": email, "password": password }),
        )
    }

    /// A new account with an email, and no password yet. Not a sign-in: the
    /// session does not change, and the ticket answers the new account
    /// (`models::Registration`). The server emails a link and a six-digit code;
    /// `confirm_registration` takes the code and the password the player
    /// chooses, and signs in. A password is never sent here: anyone can type any
    /// address, and a password chosen before the inbox is proved would let them
    /// into the account once its owner confirmed it.
    pub fn register_email(&self, email: &str) -> Ticket<Response> {
        self.register_email_as(email, "")
    }

    /// `register_email` with the username the player picked. The server picks
    /// one when `username` is empty.
    pub fn register_email_as(&self, email: &str, username: &str) -> Ticket<Response> {
        let mut body = json!({ "email": email });
        if !username.is_empty() {
            body["username"] = json!(username);
        }
        self.anonymous("/api/v1/register", body)
    }

    fn anonymous(&self, path: &'static str, body: serde_json::Value) -> Ticket<Response> {
        self.shared.start(|core, ticket| {
            rest::send(
                core,
                false,
                "POST",
                path.to_string(),
                Body::of(body),
                Box::new(move |core, reply| core.complete(ticket, reply)),
            );
        })
    }

    /// Confirm a `register_email` account with the code from its email, set its
    /// password, and sign in. Fails with `invalid_code` for a wrong, spent or
    /// expired code, `account_locked` after too many wrong ones (the code is
    /// then void: `resend_confirmation`), or `validation_failed` for a password
    /// the server refuses, which costs no attempt.
    pub fn confirm_registration(
        &self,
        email: &str,
        code: &str,
        password: &str,
    ) -> Ticket<AuthResult> {
        self.sign_in_with(
            "/api/v1/register/confirm",
            json!({ "email": email, "code": code, "password": password }),
        )
    }

    /// Email a `register_email` account a new code; only the newest works.
    /// Always succeeds, whether or not the address has an account waiting.
    pub fn resend_confirmation(&self, email: &str) -> Ticket<Response> {
        self.anonymous("/api/v1/register/resend", json!({ "email": email }))
    }

    /// A Steam session ticket (`GetAuthTicketForWebApi`, hex).
    pub fn login_steam(&self, ticket: &str) -> Ticket<AuthResult> {
        self.sign_in_with("/api/v1/auth/steam/callback", json!({ "code": ticket }))
    }

    /// Sign in through a provider (`google`, `discord`, `apple`, ...): opens its
    /// page with `Config::open_url`, then asks the server every `sign_in_poll`
    /// whether the player finished, until `sign_in_timeout`. Always a sign-in,
    /// even for a player signed in already.
    pub fn sign_in(&self, provider: &str) -> Ticket<AuthResult> {
        let path = format!("/api/v1/auth/{}", escape(provider));
        self.shared.start(|core, ticket| {
            provider_page(
                core,
                "GET",
                path,
                "/api/v1/auth/session/",
                false,
                Box::new(move |core, r| {
                    let session = if r.error.is_empty() {
                        Session::from_json(field(r.data(), "session"), core.unix_now())
                    } else {
                        None
                    };
                    let result = if !r.error.is_empty() {
                        failed(r, "")
                    } else if let Some(session) = session {
                        adopt(core, session.clone(), true);
                        AuthResult {
                            ok: true,
                            session,
                            response: r,
                            ..AuthResult::default()
                        }
                    } else {
                        // Completed, but the tokens were already collected.
                        failed(r, "no_session")
                    };
                    core.complete(ticket, result);
                }),
            );
        })
    }

    /// Link a provider to the signed-in account through its page, as `sign_in`
    /// signs in through it. Answers the final link status: ok once linked, else
    /// its code (`provider_already_linked`, ...). The session does not change.
    pub fn link(&self, provider: &str) -> Ticket<Response> {
        let path = format!("/api/v1/me/providers/{}/authorize", escape(provider));
        self.shared.start(|core, ticket| {
            provider_page(
                core,
                "POST",
                path,
                "/api/v1/me/providers/sessions/",
                true,
                Box::new(move |core, reply| core.complete(ticket, reply)),
            );
        })
    }

    /// Link Steam to the signed-in account with a session ticket. Answers the
    /// current user, whose `linked_providers` now has `steam`.
    pub fn link_steam(&self, steam_ticket: &str) -> Ticket<Response> {
        self.shared.start(|core, ticket| {
            rest::send(
                core,
                true,
                "POST",
                "/api/v1/me/providers/steam".to_string(),
                Body::of(json!({ "code": steam_ticket })),
                Box::new(move |core, reply| core.complete(ticket, reply)),
            );
        })
    }

    /// Stop waiting for a provider; its ticket gets `cancelled`.
    pub fn cancel_sign_in(&self) {
        self.shared.with(cancel_sign_in);
    }

    /// Trade the refresh token for a fresh access token now. Automatic; call it
    /// only to check a restored session is still good.
    pub fn refresh(&self) -> Ticket<AuthResult> {
        self.shared
            .start(|core, ticket| refresh(core, Some(ticket)))
    }

    /// Revoke the session on the server, then forget it here, whatever the
    /// server answered.
    pub fn logout(&self) -> Ticket<AuthResult> {
        self.shared.start(|core, ticket| {
            rest::send(
                core,
                true,
                "DELETE",
                "/api/v1/logout".to_string(),
                Body::none(),
                Box::new(move |core, r| {
                    clear(core);
                    let ok = r.ok();
                    let mut result = if ok {
                        AuthResult::default()
                    } else {
                        failed(r.clone(), "")
                    };
                    result.ok = ok;
                    result.response = r;
                    core.complete(ticket, result);
                }),
            );
        })
    }

    /// Forget the session here only.
    pub fn forget(&self) {
        self.shared.with(clear);
    }

    /// Adopt a session a previous run kept. A token that lapsed, or lapses
    /// within a minute, is refreshed on the next `poll()`.
    pub fn restore(&self, session: Session) {
        self.shared.with(|core| adopt(core, session, false));
    }

    pub fn session(&self) -> Option<Session> {
        self.shared.with(|core| core.auth.session.clone())
    }

    pub fn signed_in(&self) -> bool {
        self.shared.with(|core| {
            core.auth
                .session
                .as_ref()
                .is_some_and(|session| !session.access_token.is_empty())
        })
    }

    /// Every time the session was set, refreshed or dropped since the last call,
    /// so the game can keep it. `None` is a sign-out. `restore` is not reported.
    pub fn session_changes(&self) -> Vec<Option<Session>> {
        self.shared
            .with(|core| core.drained(|core| &mut core.auth.changes))
    }
}

fn finish_sign_in(core: &mut Core, ticket: Completer<AuthResult>, r: Response) {
    let session = if r.ok() {
        Session::from_json(r.data(), core.unix_now())
    } else {
        None
    };
    let result = if !r.ok() {
        failed(r, "")
    } else if let Some(session) = session {
        adopt(core, session.clone(), true);
        AuthResult {
            ok: true,
            session,
            response: r,
            ..AuthResult::default()
        }
    } else {
        // A sign-in that answered no token: a link, for one.
        failed(r, "no_session")
    };
    core.complete(ticket, result);
}

fn send_page(core: &mut Core, authenticated: bool, method: &str, path: String, done: Done) {
    rest::send(core, authenticated, method, path, Body::none(), done);
}

// Open the page `start_path` answers, then poll `status_path` + its session id
// until the player is done there. `finish` gets the completed status reply, or a
// reply whose `error` says why not. One page at a time: a second cancels the
// first.
fn provider_page(
    core: &mut Core,
    start_method: &'static str,
    start_path: String,
    status_path: &'static str,
    authenticated: bool,
    finish: Done,
) {
    cancel_sign_in(core);
    core.auth.page_attempt += 1;
    let attempt = core.auth.page_attempt;
    core.auth.on_page = true;
    core.auth.page_finish = Some(finish);
    if core.config.open_url.is_none() {
        core.post(move |core| {
            end_page(core, attempt, Response::failed("no open_url configured"));
        });
        return;
    }
    send_page(
        core,
        authenticated,
        start_method,
        start_path,
        Box::new(move |core, mut r| {
            if !r.ok() {
                return end_page(core, attempt, r);
            }
            let url = text(r.data(), "authorization_url");
            let session_id = text(r.data(), "session_id");
            if url.is_empty() || session_id.is_empty() {
                r.error = "unexpected_reply".to_string();
                return end_page(core, attempt, r);
            }
            if attempt != core.auth.page_attempt {
                return;
            }
            core.open_url(url);
            let deadline = core.now() + core.config.sign_in_timeout.as_millis() as u64;
            poll_page(
                core,
                attempt,
                format!("{status_path}{}", escape(&session_id)),
                authenticated,
                deadline,
            );
        }),
    );
}

fn poll_page(
    core: &mut Core,
    attempt: u64,
    status_path: String,
    authenticated: bool,
    deadline: u64,
) {
    let delay = core.config.sign_in_poll;
    let timer = core.after(delay, move |core| {
        if attempt != core.auth.page_attempt {
            return;
        }
        let again = status_path.clone();
        send_page(
            core,
            authenticated,
            "GET",
            status_path,
            Box::new(move |core, mut r| {
                if r.ok() {
                    let status = text(r.data(), "status");
                    if status == "completed" {
                        return end_page(core, attempt, r);
                    }
                    if status != "pending" {
                        // `error`: the provider or the account said no, and why.
                        r.error = text_or(r.data(), "error", &status);
                        return end_page(core, attempt, r);
                    }
                } else if (400..500).contains(&r.status) {
                    // The session is gone, or not this player's: asking again
                    // will not change that.
                    return end_page(core, attempt, r);
                }
                // Still pending, or the poll itself failed on the way: keep
                // asking until the player has had their time.
                if core.now() >= deadline {
                    r.error = "timeout".to_string();
                    return end_page(core, attempt, r);
                }
                poll_page(core, attempt, again, authenticated, deadline);
            }),
        );
    });
    if attempt == core.auth.page_attempt {
        core.auth.page_timer = timer;
    } else {
        core.cancel(timer);
    }
}

fn end_page(core: &mut Core, attempt: u64, response: Response) {
    if attempt != core.auth.page_attempt {
        return;
    }
    core.auth.page_attempt += 1;
    core.auth.on_page = false;
    let timer = mem::take(&mut core.auth.page_timer);
    core.cancel(timer);
    if let Some(finish) = core.auth.page_finish.take() {
        finish(core, response);
    }
}

fn cancel_sign_in(core: &mut Core) {
    if !core.auth.on_page {
        return;
    }
    core.auth.page_attempt += 1;
    core.auth.on_page = false;
    let timer = mem::take(&mut core.auth.page_timer);
    core.cancel(timer);
    if let Some(finish) = core.auth.page_finish.take() {
        core.post(move |core| finish(core, Response::failed("cancelled")));
    }
}

fn refresh(core: &mut Core, done: Option<Completer<AuthResult>>) {
    if core.auth.session.is_none() {
        if let Some(done) = done {
            core.complete(done, failed(Response::default(), "not_signed_in"));
        }
        return;
    }
    refresh_then(
        core,
        Box::new(move |core, refreshed| {
            let Some(done) = done else {
                return;
            };
            let mut result = AuthResult::default();
            match core.auth.session.clone() {
                Some(session) if refreshed => {
                    result.ok = true;
                    result.session = session;
                }
                Some(_) => result.error = "refresh_failed".to_string(),
                None => result.error = "not_signed_in".to_string(),
            }
            core.complete(done, result);
        }),
    );
}

/// Refresh (joining one in flight), then `next(true)`; `next(false)` when there
/// is no refresh token or the refresh failed.
pub(crate) fn refresh_then(core: &mut Core, next: RefreshThen) {
    let token = core
        .auth
        .session
        .as_ref()
        .map(|session| session.refresh_token.clone())
        .unwrap_or_default();
    if token.is_empty() {
        next(core, false);
        return;
    }
    core.auth.waiters.push(next);
    if core.auth.refreshing {
        return;
    }
    core.auth.refreshing = true;
    let body = json!({ "refresh_token": token });
    rest::send(
        core,
        false,
        "POST",
        "/api/v1/refresh".to_string(),
        Body::of(body),
        Box::new(move |core, r| finish_refresh(core, &token, &r)),
    );
}

fn finish_refresh(core: &mut Core, token: &str, r: &Response) {
    let fresh = if r.ok() {
        Session::from_json(r.data(), core.unix_now())
    } else {
        None
    };
    // A sign-in or a sign-out since the refresh left: its answer is about a
    // session that is no longer the one in hand.
    let held = core
        .auth
        .session
        .as_ref()
        .filter(|session| session.refresh_token == token)
        .map(|session| session.username.clone());
    let current = held.is_some();
    let mut refreshed = false;
    let mut rejected = false;
    if let Some(username) = held {
        if let Some(mut fresh) = fresh {
            if fresh.refresh_token.is_empty() {
                fresh.refresh_token = token.to_string();
            }
            if fresh.username.is_empty() {
                fresh.username = username;
            }
            adopt(core, fresh, true);
            refreshed = true;
        } else if (400..500).contains(&r.status) {
            // The server read the refresh token and said no: expired, or
            // revoked by a password change or a logout elsewhere.
            rejected = true;
        }
    }
    if rejected {
        core.log(
            LogLevel::Warning,
            format!("gamend: refresh refused ({}), signed out", r.error),
        );
        clear(core);
    } else if current && !refreshed {
        core.log(
            LogLevel::Warning,
            format!("gamend: refresh failed ({}), retrying", r.error),
        );
        let timer = core.auth.refresh_timer;
        core.cancel(timer);
        core.auth.refresh_timer = core.after(REFRESH_RETRY, |core| refresh(core, None));
    }
    core.auth.refreshing = false;
    for waiter in mem::take(&mut core.auth.waiters) {
        waiter(core, refreshed);
    }
}

pub(crate) fn bearer(core: &Core) -> Option<String> {
    core.auth
        .session
        .as_ref()
        .filter(|session| !session.access_token.is_empty())
        .map(|session| format!("Bearer {}", session.access_token))
}

fn adopt(core: &mut Core, session: Session, notify: bool) {
    let switched = core
        .auth
        .session
        .as_ref()
        .is_some_and(|current| current.user_id != session.user_id);
    core.auth.session = Some(session.clone());
    if switched {
        // Another player's rows and roster are not this one's.
        core.post(|core| {
            kv::clear(core);
            presence::clear(core);
        });
    }
    schedule_refresh(core);
    if notify {
        core.auth.changes.push(Some(session.clone()));
    }
    core.post(move |core| realtime::session_changed(core, Some(&session)));
}

fn clear(core: &mut Core) {
    if core.auth.session.take().is_none() {
        return;
    }
    let timer = mem::take(&mut core.auth.refresh_timer);
    core.cancel(timer);
    core.auth.changes.push(None);
    core.post(|core| {
        realtime::session_changed(core, None);
        kv::clear(core);
        presence::clear(core);
    });
}

fn schedule_refresh(core: &mut Core) {
    let timer = mem::take(&mut core.auth.refresh_timer);
    core.cancel(timer);
    let Some(session) = core
        .auth
        .session
        .as_ref()
        .filter(|session| !session.refresh_token.is_empty())
    else {
        return;
    };
    let mut left = session.expires_in;
    if session.expires_at > 0 {
        left = session.expires_at - core.unix_now();
    }
    // No lifetime at all (a session kept without one): refresh to learn it.
    let delay = if left > REFRESH_MARGIN {
        Duration::from_millis(left as u64 * 750)
    } else {
        Duration::ZERO
    };
    core.auth.refresh_timer = core.after(delay, |core| refresh(core, None));
}
