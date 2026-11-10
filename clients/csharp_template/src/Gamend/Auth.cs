// Signing in, and staying signed in.
//
// Gamend issues a short-lived access token (`expires_in`, 15 minutes by
// default) and a refresh token (30 days by default). `Auth` keeps both,
// refreshes the access token when three quarters of its life have passed, and
// `Rest` refreshes once more on a 401. The game keeps the session between runs
// where its platform keeps secrets: `OnSessionChanged` hands it over, `Restore`
// takes it back.
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    public sealed class AuthResult
    {
        public bool Ok { get; set; }
        /// <summary>Why it failed: the server's code (`invalid_credentials`, ...) or what went
        /// wrong before it answered. Empty on success.</summary>
        public string Error { get; set; } = "";
        /// <summary>The session signed in with; empty unless `Ok`.</summary>
        public Session Session { get; set; } = new Session();
        /// <summary>The last reply behind the result, for its `Message` or `Errors`.</summary>
        public Response Response { get; set; } = new Response();
    }

    public sealed class Auth
    {
        // Refresh when three quarters of the token's life have passed, and at
        // once when less than this is left.
        private const long RefreshMargin = 60;
        // How long to wait before trying again when the refresh could not reach
        // the server; the session stays until the server says it is no good.
        private const long RefreshRetryMs = 30000;

        private readonly Core _core;
        private Session _session;
        private Action<Session> _listener;

        private bool _refreshing;
        private List<Action<bool>> _waiters = new List<Action<bool>>();
        private long _refreshTimer;

        // Bumped by every provider page (a sign-in or a link) and by its end, so
        // a reply or a timer from one that is over finds a different number and
        // does nothing.
        private long _pageAttempt;
        private long _pageTimer;
        private bool _onPage;
        private Action<Response> _pageFinish;

        internal Auth(Core core)
        {
            _core = core;
        }

        private static AuthResult Failed(Response response, string error = "")
        {
            return new AuthResult
            {
                Response = response,
                Error = error.Length > 0 ? error : response.Error.Length > 0 ? response.Error : "unexpected_reply",
            };
        }

        /// <summary>Any string; an unknown id makes an anonymous account when the server has
        /// device sign-in enabled (its default).</summary>
        public Task<AuthResult> LoginDevice(string deviceId)
        {
            return SignInWith("/api/v1/login/device", new JObject { ["device_id"] = deviceId });
        }

        public Task<AuthResult> LoginEmail(string email, string password)
        {
            return SignInWith("/api/v1/login", new JObject { ["email"] = email, ["password"] = password });
        }

        /// <summary>A new account with an email, and no password yet. Not a sign-in: the session
        /// does not change, and the task answers the new account (`Models.Registration`). The
        /// server emails a link and a six-digit code; `ConfirmRegistration` takes the code and the
        /// password the player chooses, and signs in. A password is never sent here: anyone can
        /// type any address, and a password chosen before the inbox is proved would let them into
        /// the account once its owner confirmed it.</summary>
        public Task<Response> RegisterEmail(string email)
        {
            return RegisterEmail(email, "");
        }

        /// <summary>`RegisterEmail` with the username the player picked. The server picks one when
        /// `username` is empty.</summary>
        public Task<Response> RegisterEmail(string email, string username)
        {
            var body = new JObject { ["email"] = email };
            if (!string.IsNullOrEmpty(username)) body["username"] = username;
            return _core.Rest.SendAnonymous("POST", "/api/v1/register", Body.Of(body));
        }

        /// <summary>Confirm a `RegisterEmail` account with the code from its email, set its
        /// password, and sign in. Fails with `invalid_code` for a wrong, spent or expired code,
        /// `account_locked` after too many wrong ones, or `validation_failed` for a password the
        /// server refuses, which costs no attempt.</summary>
        public Task<AuthResult> ConfirmRegistration(string email, string code, string password)
        {
            return SignInWith("/api/v1/register/confirm",
                new JObject { ["email"] = email, ["code"] = code, ["password"] = password });
        }

        /// <summary>Email a `RegisterEmail` account a new code; only the newest works. Always
        /// succeeds, whether or not the address has an account waiting.</summary>
        public Task<Response> ResendConfirmation(string email)
        {
            return _core.Rest.SendAnonymous("POST", "/api/v1/register/resend", Body.Of(new JObject { ["email"] = email }));
        }

        /// <summary>A Steam session ticket (`GetAuthTicketForWebApi`, hex).</summary>
        public Task<AuthResult> LoginSteam(string ticket)
        {
            return SignInWith("/api/v1/auth/steam/callback", new JObject { ["code"] = ticket });
        }

        private Task<AuthResult> SignInWith(string path, JObject body)
        {
            return _core.Start<AuthResult>(done =>
                _core.Rest.Send(false, "POST", path, Body.Of(body), r =>
                {
                    AuthResult result;
                    var session = r.Ok ? Session.FromJson(r.Data, _core.UnixNow()) : null;
                    if (!r.Ok)
                    {
                        result = Failed(r);
                    }
                    else if (session != null)
                    {
                        Adopt(session, true);
                        result = new AuthResult { Ok = true, Session = session.Copy(), Response = r };
                    }
                    else
                    {
                        // A sign-in that answered no token: a link, for one.
                        result = Failed(r, "no_session");
                    }
                    done(result);
                }));
        }

        /// <summary>Sign in through a provider (`google`, `discord`, `apple`, ...): opens its page
        /// with `Config.OpenUrl`, then asks the server every `SignInPoll` whether the player
        /// finished, until `SignInTimeout`. Always a sign-in, even for a player signed in
        /// already.</summary>
        public Task<AuthResult> SignIn(string provider)
        {
            var path = "/api/v1/auth/" + Query.Escape(provider);
            return _core.Start<AuthResult>(done =>
                ProviderPage("GET", path, "/api/v1/auth/session/", false, r =>
                {
                    AuthResult result;
                    var session = r.Error.Length == 0 ? Session.FromJson(Json.Field(r.Data, "session"), _core.UnixNow()) : null;
                    if (r.Error.Length > 0)
                    {
                        result = Failed(r);
                    }
                    else if (session != null)
                    {
                        Adopt(session, true);
                        result = new AuthResult { Ok = true, Session = session.Copy(), Response = r };
                    }
                    else
                    {
                        // Completed, but the tokens were already collected.
                        result = Failed(r, "no_session");
                    }
                    done(result);
                }));
        }

        /// <summary>Link a provider to the signed-in account through its page, as `SignIn` signs in
        /// through it. Answers the final link status: ok once linked, else its code
        /// (`provider_already_linked`, ...). The session does not change.</summary>
        public Task<Response> Link(string provider)
        {
            var path = "/api/v1/me/providers/" + Query.Escape(provider) + "/authorize";
            return _core.Start<Response>(done =>
                ProviderPage("POST", path, "/api/v1/me/providers/sessions/", true, done));
        }

        /// <summary>Link Steam to the signed-in account with a session ticket. Answers the current
        /// user, whose `linked_providers` now has `steam`.</summary>
        public Task<Response> LinkSteam(string ticket)
        {
            return _core.Rest.Send("POST", "/api/v1/me/providers/steam", Body.Of(new JObject { ["code"] = ticket }));
        }

        // Open the page `startPath` answers, then poll `statusPath` + its session
        // id until the player is done there. `finish` gets the completed status
        // reply, or a reply whose `Error` says why not. One page at a time: a
        // second cancels the first.
        private void ProviderPage(string startMethod, string startPath, string statusPath, bool authenticated, Action<Response> finish)
        {
            CancelSignIn();
            var attempt = ++_pageAttempt;
            _onPage = true;
            _pageFinish = finish;
            if (_core.Config.OpenUrl == null)
            {
                _core.Post(() => EndPage(attempt, new Response { Error = "no open_url configured" }));
                return;
            }
            _core.Rest.Send(authenticated, startMethod, startPath, Body.None, r =>
            {
                if (!r.Ok)
                {
                    EndPage(attempt, r);
                    return;
                }
                var url = Json.Text(r.Data, "authorization_url");
                var sessionId = Json.Text(r.Data, "session_id");
                if (url.Length == 0 || sessionId.Length == 0)
                {
                    r.Error = "unexpected_reply";
                    EndPage(attempt, r);
                    return;
                }
                if (attempt != _pageAttempt) return;
                try
                {
                    _core.Config.OpenUrl(url);
                }
                catch (Exception e)
                {
                    // The game's own opener failed; its bug surfaces from `Poll`,
                    // and nobody is left waiting on a page that never opened.
                    _core.Loop.Keep(e);
                    EndPage(attempt, new Response { Error = "open_url failed" });
                    return;
                }
                PollPage(attempt, statusPath + Query.Escape(sessionId), authenticated,
                    _core.Loop.Now() + Ms(_core.Config.SignInTimeout));
            });
        }

        private void PollPage(long attempt, string statusPath, bool authenticated, long deadline)
        {
            var timer = _core.Loop.After(Ms(_core.Config.SignInPoll), () =>
            {
                if (attempt != _pageAttempt) return;
                _core.Rest.Send(authenticated, "GET", statusPath, Body.None, r =>
                {
                    if (r.Ok)
                    {
                        var status = Json.Text(r.Data, "status");
                        if (status == "completed")
                        {
                            EndPage(attempt, r);
                            return;
                        }
                        if (status != "pending")
                        {
                            // `error`: the provider or the account said no, and why.
                            r.Error = Json.Text(r.Data, "error", status);
                            EndPage(attempt, r);
                            return;
                        }
                    }
                    else if (r.Status >= 400 && r.Status < 500)
                    {
                        // The session is gone, or not this player's: asking again
                        // will not change that.
                        EndPage(attempt, r);
                        return;
                    }
                    // Still pending, or the poll itself failed on the way: keep
                    // asking until the player has had their time.
                    if (_core.Loop.Now() >= deadline)
                    {
                        r.Error = "timeout";
                        EndPage(attempt, r);
                        return;
                    }
                    PollPage(attempt, statusPath, authenticated, deadline);
                });
            });
            if (attempt == _pageAttempt)
            {
                _pageTimer = timer;
            }
            else
            {
                _core.Loop.Cancel(timer);
            }
        }

        private void EndPage(long attempt, Response response)
        {
            if (attempt != _pageAttempt) return;
            ++_pageAttempt;
            _onPage = false;
            _core.Loop.Cancel(_pageTimer);
            _pageTimer = 0;
            var finish = _pageFinish;
            _pageFinish = null;
            finish?.Invoke(response);
        }

        /// <summary>Stop waiting for a provider; its task gets `cancelled`.</summary>
        public void CancelSignIn()
        {
            lock (_core.Gate)
            {
                if (!_onPage) return;
                ++_pageAttempt;
                _onPage = false;
                _core.Loop.Cancel(_pageTimer);
                _pageTimer = 0;
                var finish = _pageFinish;
                _pageFinish = null;
                _core.Post(() => finish?.Invoke(new Response { Error = "cancelled" }));
            }
        }

        /// <summary>Trade the refresh token for a fresh access token now. Automatic; call it only
        /// to check a restored session is still good.</summary>
        public Task<AuthResult> Refresh()
        {
            return _core.Start<AuthResult>(RefreshCore);
        }

        private void RefreshCore(Action<AuthResult> done)
        {
            if (_session == null)
            {
                _core.Post(() => done?.Invoke(Failed(new Response(), "not_signed_in")));
                return;
            }
            if (_session.RefreshToken.Length == 0)
            {
                _core.Post(() => done?.Invoke(new AuthResult { Error = "refresh_failed" }));
                return;
            }
            RefreshThen(refreshed =>
            {
                if (done == null) return;
                var result = new AuthResult();
                if (refreshed && _session != null)
                {
                    result.Ok = true;
                    result.Session = _session.Copy();
                }
                else
                {
                    result.Error = _session != null ? "refresh_failed" : "not_signed_in";
                }
                done(result);
            });
        }

        /// <summary>Refresh (joining one in flight), then `next(true)`; `next(false)` when there is
        /// no refresh token or the refresh failed.</summary>
        internal void RefreshThen(Action<bool> next)
        {
            if (_session == null || _session.RefreshToken.Length == 0)
            {
                next(false);
                return;
            }
            var token = _session.RefreshToken;
            _waiters.Add(next);
            if (_refreshing) return;
            _refreshing = true;
            _core.Rest.Send(false, "POST", "/api/v1/refresh", Body.Of(new JObject { ["refresh_token"] = token }), r =>
            {
                var refreshed = false;
                var fresh = r.Ok ? Session.FromJson(r.Data, _core.UnixNow()) : null;
                // A sign-in or a sign-out since the refresh left: its answer is
                // about a session that is no longer the one in hand.
                var current = _session != null && _session.RefreshToken == token;
                if (current && fresh != null)
                {
                    if (fresh.RefreshToken.Length == 0) fresh.RefreshToken = token;
                    if (fresh.Username.Length == 0) fresh.Username = _session.Username;
                    Adopt(fresh, true);
                    refreshed = true;
                }
                else if (current && r.Status >= 400 && r.Status < 500)
                {
                    // The server read the refresh token and said no: expired,
                    // revoked by a password change or a logout elsewhere.
                    _core.Log(LogLevel.Warning, "gamend: refresh refused (" + r.Error + "), signed out");
                    Clear();
                }
                else if (current)
                {
                    _core.Log(LogLevel.Warning, "gamend: refresh failed (" + r.Error + "), retrying");
                    _core.Loop.Cancel(_refreshTimer);
                    _refreshTimer = _core.Loop.After(RefreshRetryMs, () => RefreshCore(null));
                }
                _refreshing = false;
                var waiters = _waiters;
                _waiters = new List<Action<bool>>();
                foreach (var waiter in waiters) waiter(refreshed);
            });
        }

        /// <summary>Revoke the session on the server, then forget it here, whatever the server
        /// answered.</summary>
        public Task<AuthResult> Logout()
        {
            return _core.Start<AuthResult>(done =>
                _core.Rest.Send(true, "DELETE", "/api/v1/logout", Body.None, r =>
                {
                    Clear();
                    var result = r.Ok ? new AuthResult() : Failed(r);
                    result.Ok = r.Ok;
                    result.Response = r;
                    done(result);
                }));
        }

        /// <summary>Forget the session here only.</summary>
        public void Forget()
        {
            lock (_core.Gate)
            {
                Clear();
            }
        }

        /// <summary>Adopt a session a previous run kept. A token that lapsed, or lapses within a
        /// minute, is refreshed on the next `Poll`.</summary>
        public void Restore(Session session)
        {
            lock (_core.Gate)
            {
                Adopt(session.Copy(), false);
            }
        }

        /// <summary>The session in hand, or null. A copy: changing it changes nothing.</summary>
        public Session Session
        {
            get
            {
                lock (_core.Gate)
                {
                    return _session?.Copy();
                }
            }
        }

        public bool SignedIn
        {
            get
            {
                lock (_core.Gate)
                {
                    return _session != null && _session.AccessToken.Length > 0;
                }
            }
        }

        /// <summary>Called, in `Poll`, whenever the session is set, refreshed or dropped (null), so
        /// the game can keep it. Not called for `Restore`.</summary>
        public void OnSessionChanged(Action<Session> listener)
        {
            lock (_core.Gate)
            {
                _listener = listener;
            }
        }

        internal string Bearer()
        {
            return _session == null || _session.AccessToken.Length == 0 ? "" : "Bearer " + _session.AccessToken;
        }

        internal string CurrentUserId
        {
            get { return _session == null ? "" : _session.UserId; }
        }

        internal Session Current
        {
            get { return _session; }
        }

        private void Adopt(Session session, bool notify)
        {
            var switched = _session != null && _session.UserId != session.UserId;
            _session = session;
            var listener = notify ? _listener : null;
            if (switched)
            {
                // Another player's rows and roster are not this one's.
                _core.Post(() =>
                {
                    _core.Kv.Clear();
                    _core.Presence.Clear();
                });
            }
            ScheduleRefresh();
            _core.Post(() => _core.Realtime.SessionChanged(session));
            if (listener != null) _core.Post(() => Announce(listener, session.Copy()));
        }

        private void Clear()
        {
            if (_session == null) return;
            _session = null;
            _core.Loop.Cancel(_refreshTimer);
            _refreshTimer = 0;
            var listener = _listener;
            _core.Post(() =>
            {
                _core.Realtime.SessionChanged(null);
                _core.Kv.Clear();
                _core.Presence.Clear();
            });
            if (listener != null) _core.Post(() => Announce(listener, null));
        }

        private void Announce(Action<Session> listener, Session session)
        {
            try
            {
                listener(session);
            }
            catch (Exception e)
            {
                _core.Loop.Keep(e);
            }
        }

        private void ScheduleRefresh()
        {
            _core.Loop.Cancel(_refreshTimer);
            _refreshTimer = 0;
            if (_session == null || _session.RefreshToken.Length == 0) return;

            var left = _session.ExpiresIn;
            if (_session.ExpiresAt > 0) left = _session.ExpiresAt - _core.UnixNow();
            // No lifetime at all (a session kept without one): refresh to learn it.
            long delay = 0;
            if (left > RefreshMargin) delay = left * 750;
            _refreshTimer = _core.Loop.After(delay, () => RefreshCore(null));
        }

        private static long Ms(TimeSpan span)
        {
            return (long)span.TotalMilliseconds;
        }
    }
}
