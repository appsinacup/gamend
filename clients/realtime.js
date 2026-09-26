/**
 * GameRealtime — Phoenix WebSocket client for gamend.
 *
 * Wraps Phoenix.Socket to provide helpers for common gamend channel topics.
 * The `phoenix` npm package is included as a dependency.
 *
 * Usage (browser / Node.js with bundler):
 *
 *   import { GameRealtime } from '@ughuuu/gamend'
 *
 *   const realtime = new GameRealtime('https://your-server.com', accessToken)
 *
 *   // Join the authenticated user channel
 *   const userChannel = realtime.joinUserChannel(userId)
 *   userChannel.on('notification_created', (payload) => console.log('notification:', payload))
 *   userChannel.on('updated', (payload) => console.log('user updated:', payload))
 *
 *   // Join a lobby channel
 *   const lobbyChannel = realtime.joinLobbyChannel(lobbyId)
 *   lobbyChannel.on('updated', (payload) => console.log('lobby event:', payload))
 *
 *   // After a token refresh. The server checks the token only when the socket
 *   // connects, so this is what the next reconnect sends. Or pass a function
 *   // returning the current token instead of a string.
 *   realtime.setToken(newAccessToken)
 *
 *   realtime.disconnect()
 *
 * Dependency: `phoenix` (bundled with @ughuuu/gamend)
 */

import { Socket } from 'phoenix'
import { decodeEvent, registerMetaSchema, registerKvSchema } from './gamend_proto.js'

export class GameRealtime {
  /**
   * @param {string} serverUrl  - Base HTTP(S) or WS(S) server URL,
   *                              e.g. "https://game.example.com" or "wss://game.example.com"
   * @param {string|function(): string} token
   *                            - JWT access token from the REST login endpoints,
   *                              or a function returning the current one. It is
   *                              read on every connect and reconnect; see
   *                              `setToken` for keeping it fresh.
   * @param {Object} socketOpts - Optional Phoenix.Socket constructor options.
   *                              Pass `format: 'protobuf'` to receive server
   *                              events as protobuf binary frames; channels
   *                              obtained through the join helpers decode them
   *                              transparently (timestamps become unix-ms
   *                              numbers, see proto/gamend_realtime.proto).
   *                              `params` (object or function) are sent
   *                              alongside the token.
   */
  constructor(serverUrl, token, socketOpts = {}) {
    // Normalise URL: strip trailing slash, ensure ws(s):// scheme, append /socket
    const wsUrl =
      serverUrl
        .replace(/\/$/, '')
        .replace(/^http(s?):\/\//, (_m, s) => `ws${s}://`) + '/socket'

    const { format, params, ...opts } = socketOpts
    this._token = token
    this._format = format === 'protobuf' ? 'protobuf' : 'json'
    this._closed = false
    // A function, so Phoenix reads the token on every reconnect. A value
    // fixed here is replayed after the access token expires, and the server
    // refuses the socket from then on.
    this._socket = new Socket(wsUrl, { ...opts, params: () => this._socketParams(params) })
    this._socket.connect()
    /** @type {Map<string, Object>} topic → Phoenix Channel */
    this._channels = new Map()
  }

  /**
   * The access token the next connect or reconnect sends.
   * @returns {string}
   */
  get token() {
    return typeof this._token === 'function' ? this._token() : this._token
  }

  /**
   * Replace the access token, e.g. after `POST /api/v1/refresh`.
   *
   * The server checks the token when the socket connects, so an open socket
   * and its channels carry on untouched; the new token is what the next
   * reconnect sends. A socket that is down right now (its reconnects refused
   * with the expired token) retries at once instead of waiting out its
   * backoff, and its channels rejoin.
   * @param {string|function(): string} token - the token, or a function returning it
   */
  setToken(token) {
    this._token = token
    if (!this._closed && !this._socket.isConnected()) {
      this._socket.disconnect(() => this._socket.connect())
    }
  }

  /**
   * Registers the game's protobuf metadata schema for an entity (mirrors the
   * server plugin's UserMeta/LobbyMeta/GroupMeta/PartyMeta registration), so
   * decoded events expose `metadata` as a plain object in protobuf mode.
   * @param {string} entity - 'user' | 'lobby' | 'group' | 'party'
   * @param {Object|Function} schema - protobufjs class, or (Uint8Array) => value
   */
  registerMetaSchema(entity, schema) {
    registerMetaSchema(entity, schema)
  }

  /**
   * Registers the game's protobuf KV data schema for a key or '*'-suffixed
   * key prefix (mirrors the server plugin's kv_schemas/0 registration).
   * @param {string} pattern - e.g. 'loadout' or 'match:*'
   * @param {Object|Function} schema - protobufjs class, or (Uint8Array) => value
   */
  registerKvSchema(pattern, schema) {
    registerKvSchema(pattern, schema)
  }

  // ── Channel helpers ──────────────────────────────────────────────────────

  /**
   * Join the user channel for notifications, presence, and real-time events.
   * Topic: `"user:<userId>"`
   * @param {string|number} userId
   * @param {Object} params - Extra join params
   * @returns {Object} Phoenix Channel
   */
  joinUserChannel(userId, params = {}) {
    return this._join(`user:${userId}`, params)
  }

  /**
   * Join a lobby channel for in-lobby events (member joins/leaves, updates).
   * Topic: `"lobby:<lobbyId>"`
   * @param {string|number} lobbyId
   * @param {Object} params
   * @returns {Object} Phoenix Channel
   */
  joinLobbyChannel(lobbyId, params = {}) {
    return this._join(`lobby:${lobbyId}`, params)
  }

  /**
   * Join the global lobbies feed (lobby list changes).
   * Topic: `"lobbies"`
   * @param {Object} params
   * @returns {Object} Phoenix Channel
   */
  joinLobbiesChannel(params = {}) {
    return this._join('lobbies', params)
  }

  /**
   * Join a group channel for group events.
   * Topic: `"group:<groupId>"`
   * @param {string|number} groupId
   * @param {Object} params
   * @returns {Object} Phoenix Channel
   */
  joinGroupChannel(groupId, params = {}) {
    return this._join(`group:${groupId}`, params)
  }

  /**
   * Join the global groups feed.
   * Topic: `"groups"`
   * @param {Object} params
   * @returns {Object} Phoenix Channel
   */
  joinGroupsChannel(params = {}) {
    return this._join('groups', params)
  }

  /**
   * Join a party channel for party events.
   * Topic: `"party:<partyId>"`
   * @param {string|number} partyId
   * @param {Object} params
   * @returns {Object} Phoenix Channel
   */
  joinPartyChannel(partyId, params = {}) {
    return this._join(`party:${partyId}`, params)
  }

  // ── Push helpers ─────────────────────────────────────────────────────────

  /**
   * Push an event to a channel by topic. Returns a Phoenix Push object.
   * If no topic is given, pushes to the user channel.
   * @param {string} event
   * @param {Object} [payload={}]
   * @param {string} [topic] - defaults to the user channel
   * @returns {Object} Phoenix Push
   */
  push(event, payload = {}, topic) {
    const ch = topic ? this._channels.get(topic) : this._findUserChannel()
    if (!ch) {
      throw new Error(`No channel found${topic ? ` for topic "${topic}"` : ''}. Join it first.`)
    }
    return ch.push(event, payload)
  }

  /**
   * Call a plugin hook via the user channel. Returns a Promise.
   * @param {string} plugin
   * @param {string} fn
   * @param {Array}  [args=[]]
   * @returns {Promise<any>}
   */
  callHook(plugin, fn, args = []) {
    return new Promise((resolve, reject) => {
      this.push('call_hook', { plugin, fn, args })
        .receive('ok', (resp) => resolve(resp.data))
        .receive('error', (resp) => reject(new Error(resp.error || 'unknown_error')))
        .receive('timeout', () => reject(new Error('timeout')))
    })
  }

  /**
   * Join an arbitrary channel topic.
   * @param {string} topic  - Full Phoenix channel topic string
   * @param {Object} params - Join params
   * @returns {Object} Phoenix Channel
   */
  joinChannel(topic, params = {}) {
    return this._join(topic, params)
  }

  /**
   * Leave and remove a channel by topic.
   * @param {string} topic
   */
  leaveChannel(topic) {
    const ch = this._channels.get(topic)
    if (ch) {
      ch.leave()
      this._channels.delete(topic)
    }
  }

  /**
   * Retrieve an already-joined channel by topic.
   * @param {string} topic
   * @returns {Object|undefined} Phoenix Channel or undefined if not joined
   */
  channel(topic) {
    return this._channels.get(topic)
  }

  /**
   * Access the underlying Phoenix.Socket instance.
   * @returns {Object}
   */
  get socket() {
    return this._socket
  }

  /**
   * Disconnect the socket and leave all channels.
   */
  disconnect() {
    this._closed = true
    this._channels.forEach((ch) => { try { ch.leave() } catch (_) {} })
    this._channels.clear()
    this._socket.disconnect()
  }

  // ── Private ────────────────────────────────────────────────────────────────

  _socketParams(extra) {
    const params = { token: this.token }
    if (this._format === 'protobuf') params.format = 'protobuf'
    return { ...params, ...(typeof extra === 'function' ? extra() : extra) }
  }

  // No token in the join params: the server authenticates the socket, not the
  // join, and a token captured here would be replayed stale on every rejoin.
  _join(topic, extraParams = {}) {
    if (this._channels.has(topic)) {
      return this._channels.get(topic)
    }
    const ch = this._socket.channel(topic, extraParams)
    if (this._format === 'protobuf') this._wrapBinaryDecode(ch)
    ch.join()
      .receive('error', (err) =>
        console.error(`GameRealtime: failed to join channel "${topic}"`, err)
      )
    this._channels.set(topic, ch)
    return ch
  }

  // On protobuf sockets the server delivers mapped events as binary frames;
  // decode them before they reach `channel.on(...)` handlers so application
  // code sees plain objects in both formats.
  _wrapBinaryDecode(ch) {
    const originalTrigger = ch.trigger.bind(ch)
    ch.trigger = (event, payload, ref, joinRef) => {
      let decoded = payload
      if (payload instanceof ArrayBuffer || payload instanceof Uint8Array) {
        try {
          decoded = decodeEvent(ch.topic, event, payload) ?? payload
        } catch (err) {
          console.error(`GameRealtime: failed to decode "${event}" on ${ch.topic}`, err)
        }
      }
      return originalTrigger(event, decoded, ref, joinRef)
    }
  }

  _findUserChannel() {
    for (const [topic, ch] of this._channels) {
      if (topic.startsWith('user:')) return ch
    }
    return undefined
  }
}

export default GameRealtime
