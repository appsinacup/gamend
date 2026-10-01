/**
 * GamendSession — keeps a player signed in.
 *
 * Holds the access and refresh tokens, sends the access token with every API
 * call made through `session.client`, refreshes it shortly before it expires
 * (and once after a 401), and gives GameRealtime a token function, so a socket
 * that reconnects hours later still carries a valid token. The JS counterpart
 * of the token handling in the Godot client's GamendApi.
 *
 * Usage:
 *
 *   import { GamendSession, AuthenticationApi, UsersApi } from '@ughuuu/gamend'
 *
 *   const gamend = new GamendSession('https://your-server.com')
 *   gamend.on('session', (session) => session ? save(session) : forget())
 *   gamend.on('authFailed', () => showLogin())
 *   gamend.restore(loadSaved())  // optional: a session saved earlier
 *
 *   // Any sign-in made through gamend.client is picked up: email, device, a provider.
 *   await new AuthenticationApi(gamend.client).login({ loginRequest: { email, password } })
 *   const me = await new UsersApi(gamend.client).getCurrentUser()
 *
 *   const realtime = gamend.realtime()
 *   realtime.joinUserChannel(gamend.userId)
 *
 *   await gamend.signOut()
 */

import ApiClient from './ApiClient'
import AuthenticationApi from './api/AuthenticationApi'
import { GameRealtime } from './realtime'

// Refresh this long before the access token expires, so a request sent just
// before the deadline does not arrive just after it.
const REFRESH_MARGIN_MS = 60 * 1000
const LOGOUT_PATH = '/api/v1/logout'

export class GamendSession {
  /**
   * @param {string} serverUrl - Base HTTP(S) server URL, e.g. "https://game.example.com"
   */
  constructor(serverUrl) {
    this._serverUrl = serverUrl.replace(/\/$/, '')
    this._session = null
    this._generation = 0
    this._refreshing = null
    this._listeners = { session: new Set(), authFailed: new Set() }
    this._realtimes = new Set()
    /** The ApiClient to hand every generated API class: `new LobbiesApi(gamend.client)`. */
    this.client = new SessionApiClient(this._serverUrl, this)
    // Refreshes bypass `client`, so their answer is adopted only when no
    // sign-in or sign-out happened while they were in flight.
    this._plainClient = new ApiClient(this._serverUrl)
  }

  /** Whether a session is held. */
  get signedIn() {
    return this._session !== null
  }

  /** The signed-in user's id, or null. */
  get userId() {
    return this._session ? this._session.user_id : null
  }

  /**
   * The session to save for `restore`: `{access_token, refresh_token,
   * expires_at, user_id}`, `expires_at` in unix ms; null when signed out. The
   * refresh token signs in for 30 days, so store it as you would a password.
   * @returns {Object|null}
   */
  get session() {
    return this._session ? { ...this._session } : null
  }

  /**
   * Resumes a session saved from `session` or the 'session' event. A missing
   * or past `expires_at` makes the first call refresh the access token.
   * @param {Object|null} saved
   */
  restore(saved) {
    this._set(saved && saved.refresh_token ? saved : null)
  }

  /**
   * Listens for 'session' (signed in, refreshed or signed out: the new
   * `session`, or null) or 'authFailed' (the server refused the refresh token,
   * as after a sign-out elsewhere or a password change; the session is gone).
   * @param {'session'|'authFailed'} event
   * @param {Function} listener
   * @returns {Function} Call it to stop listening
   */
  on(event, listener) {
    const listeners = this._listeners[event]
    if (!listeners) throw new Error(`GamendSession: unknown event "${event}"`)
    listeners.add(listener)
    return () => listeners.delete(listener)
  }

  /**
   * A valid access token, refreshed first when it expires within a minute;
   * null when signed out. Sockets from `realtime()` call this.
   * @returns {Promise<string|null>}
   */
  async getAccessToken() {
    const session = this._session
    if (!session) return null
    if (Date.now() < session.expires_at - REFRESH_MARGIN_MS) return session.access_token
    await this.refresh()
    return this._session ? this._session.access_token : null
  }

  /**
   * Exchanges the refresh token for a new access token now; concurrent calls
   * share one request. Resolves true when refreshed, false when signed out,
   * offline (the session is kept for the next try) or refused (the session is
   * dropped and 'authFailed' fires).
   * @returns {Promise<boolean>}
   */
  refresh() {
    if (!this._refreshing) {
      this._refreshing = this._refresh().finally(() => { this._refreshing = null })
    }
    return this._refreshing
  }

  /**
   * A GameRealtime socket that asks this session for its token, disconnected
   * when the session ends or another user signs in.
   * @param {Object} socketOpts - As for GameRealtime, e.g. `{ format: 'protobuf' }`
   * @returns {GameRealtime}
   */
  realtime(socketOpts = {}) {
    if (!this._session) throw new Error('GamendSession: sign in before opening a realtime socket')
    const realtime = new GameRealtime(this._serverUrl, () => this.getAccessToken(), socketOpts)
    this._realtimes.add(realtime)
    return realtime
  }

  /**
   * Revokes the tokens on the server (on every device: revocation is per
   * account) and drops the session here, even when the server cannot be reached.
   */
  async signOut() {
    if (!this._session) return
    try {
      await new AuthenticationApi(this.client).logout()
    } catch (_) {
      // `client` dropped the session whatever the answer; nothing to undo.
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  async _refresh() {
    const session = this._session
    if (!session) return false
    const generation = this._generation
    let body
    try {
      const { response } = await new AuthenticationApi(this._plainClient)
        .refreshTokenWithHttpInfo({ refreshTokenRequest: { refresh_token: session.refresh_token } })
      body = response.body
    } catch (err) {
      if (generation === this._generation && err.status === 401) {
        this._set(null)
        this._emit('authFailed')
      }
      return false
    }
    return generation === this._generation && this._adopt(body)
  }

  // After a 401 on a call that sent `sentToken`: true when there is a newer
  // token to retry with.
  async _recover(sentToken) {
    if (!this._session) return false
    if (this._session.access_token !== sentToken) return true
    return this.refresh()
  }

  // Takes the session from a sign-in or refresh answer: `data` is a Session,
  // or, for a polled provider sign-in, holds one under `data.session`.
  _adopt(body) {
    const data = body && body.data
    const session = data && (data.access_token ? data : data.session)
    if (!session || !session.access_token || !session.refresh_token) return false
    this._set({
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      expires_at: Date.now() + (session.expires_in || 0) * 1000,
      user_id: session.user_id || this.userId,
    })
    return true
  }

  _set(saved) {
    const previous = this._session
    this._generation++
    this._session = saved
      ? {
          access_token: saved.access_token || null,
          refresh_token: saved.refresh_token,
          expires_at: saved.expires_at || 0,
          user_id: saved.user_id || null,
        }
      : null
    this.client.authentications.authorization.accessToken =
      this._session ? this._session.access_token : null
    if (!this._session || (previous && previous.user_id !== this._session.user_id)) {
      this._realtimes.forEach((realtime) => realtime.disconnect())
      this._realtimes.clear()
    }
    this._emit('session', this.session)
  }

  _emit(event, value) {
    this._listeners[event].forEach((listener) => {
      try {
        listener(value)
      } catch (err) {
        console.error(`GamendSession: a '${event}' listener failed`, err)
      }
    })
  }
}

// The ApiClient behind `GamendSession.client`: sends the session's access
// token (refreshed first when due, and once more after a 401), adopts the
// session a sign-in answers, and signs out with the refresh token.
class SessionApiClient extends ApiClient {
  constructor(basePath, gamendSession) {
    super(basePath)
    this._gamendSession = gamendSession
  }

  async callApi(...args) {
    const gamend = this._gamendSession
    const [path, , , , headerParams, , , authNames] = args
    const call = () => ApiClient.prototype.callApi.apply(this, args)

    // Logout reads the token itself, so that an expired one can still sign
    // out, and its route is unauthenticated: the generated call sends no
    // token. Send the refresh token, which outlives the access token.
    if (path === LOGOUT_PATH) {
      if (!gamend.signedIn) return call()
      args[4] = { Authorization: `Bearer ${gamend._session.refresh_token}`, ...headerParams }
      try {
        return await call()
      } finally {
        gamend._set(null)
      }
    }

    const authed = authNames.includes('authorization') && gamend.signedIn
    if (authed) await gamend.getAccessToken()
    const sentToken = this.authentications.authorization.accessToken
    let result
    try {
      result = await call()
    } catch (err) {
      if (!authed || err.status !== 401 || !(await gamend._recover(sentToken))) throw err
      result = await call()
    }
    gamend._adopt(result.response && result.response.body)
    return result
  }
}
