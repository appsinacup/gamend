/**
 * GameWebRTC — Browser WebRTC DataChannel client for gamend.
 *
 * Uses an existing Phoenix channel (e.g. from GameRealtime.joinUserChannel)
 * for SDP/ICE signaling. Once connected, named DataChannels carry game data
 * alongside the WebSocket at lower latency.
 *
 * Requires a browser with native WebRTC support (RTCPeerConnection).
 * For Node.js environments, install the `node-datachannel` package as a polyfill.
 *
 * Usage:
 *
 *   import { GameWebRTC } from '@ughuuu/gamend'
 *
 *   const realtime = gamend.realtime()  // gamend: a signed-in GamendSession
 *   const userChannel = realtime.joinUserChannel(gamend.userId)
 *
 *   const webrtc = new GameWebRTC(userChannel, {
 *     dataChannels: [
 *       { label: 'events', ordered: true },
 *       { label: 'state',  ordered: false, maxRetransmits: 0 },
 *     ],
 *     onData:         (label, data)  => console.log('data', label, data),
 *     onChannelOpen:  (label)        => console.log('channel open', label),
 *     onChannelClose: (label)        => console.log('channel close', label),
 *     onStateChange:  (state)        => console.log('state', state),
 *   })
 *
 *   await webrtc.connect()
 *   webrtc.send('events', JSON.stringify({ type: 'player_move', x: 10, y: 20 }))
 *   webrtc.close()
 */

import { PB } from './gamend_proto.js'

/**
 * Default DataChannel definitions.
 * - "events": reliable, ordered — important game events
 * - "state":  unreliable, unordered — high-frequency position/state sync
 */
const DEFAULT_DATA_CHANNELS = [
  { label: 'events', ordered: true },
  { label: 'state',  ordered: false, maxRetransmits: 0 },
]

const DEFAULT_ICE_SERVERS = [
  { urls: 'stun:stun.l.google.com:19302' },
]

export class GameWebRTC {
  /**
   * @param {Object} channel — A joined Phoenix channel (e.g. from GameRealtime.joinUserChannel)
   * @param {Object} opts
   * @param {Array}    opts.dataChannels   — Array of {label, ordered, maxRetransmits?} definitions
   * @param {Array}    opts.iceServers     — RTCIceServer configs (default: Google STUN)
   * @param {Function} opts.onData        — (label: string, data: ArrayBuffer|string) => void
   * @param {Function} opts.onChannelOpen  — (label: string) => void
   * @param {Function} opts.onChannelClose — (label: string) => void
   * @param {Function} opts.onStateChange  — (state: string) => void
   * @param {Function} opts.onError        — (error: Error) => void
   */
  constructor(channel, opts = {}) {
    this.channel = channel
    this.opts = opts
    this.iceServers = opts.iceServers || DEFAULT_ICE_SERVERS
    this.dataChannelDefs = opts.dataChannels || DEFAULT_DATA_CHANNELS
    // 'protobuf' negotiates the RtcEnvelope RPC protocol (with request ids)
    // on the "events" DataChannel via the DataChannel protocol field.
    this.format = opts.format === 'protobuf' ? 'protobuf' : 'json'
    /** @type {Map<number|string, {resolve: Function, reject: Function, timer: any}>} */
    this._pendingCalls = new Map()
    this._nextCallId = 1

    /** @type {RTCPeerConnection|null} */
    this.pc = null
    /** @type {Map<string, RTCDataChannel>} label → RTCDataChannel */
    this.channels = new Map()
    /** @type {string} */
    this.connectionState = 'new'

    this._resolveConnect = null
    this._rejectConnect = null

    this._setupChannelListeners()
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /**
   * Initiate the WebRTC connection.
   * Creates an RTCPeerConnection, opens DataChannels, sends an SDP offer
   * over the Phoenix channel, and exchanges ICE candidates.
   *
   * @returns {Promise<void>} Resolves when at least one DataChannel is open.
   */
  async connect() {
    this.pc = new RTCPeerConnection({ iceServers: this.iceServers })

    this.pc.onicecandidate = (event) => this._onIceCandidate(event)
    this.pc.onconnectionstatechange = () => this._onConnectionStateChange()

    // Create DataChannels on the client side (client-initiated)
    for (const def of this.dataChannelDefs) {
      const dcOpts = { ordered: def.ordered !== false }
      if (def.maxRetransmits !== undefined) dcOpts.maxRetransmits = def.maxRetransmits
      if (def.maxPacketLifeTime !== undefined) dcOpts.maxPacketLifeTime = def.maxPacketLifeTime
      if (this.format === 'protobuf') dcOpts.protocol = 'protobuf'

      const dc = this.pc.createDataChannel(def.label, dcOpts)
      this._wireDataChannel(dc)
      this.channels.set(def.label, dc)
    }

    // Create and send SDP offer
    const offer = await this.pc.createOffer()
    await this.pc.setLocalDescription(offer)

    return new Promise((resolve, reject) => {
      this.channel
        .push('webrtc:offer', { sdp: offer.sdp, type: offer.type })
        .receive('ok', () => {
          // Offer accepted — wait for webrtc:answer from server
          this._resolveConnect = resolve
          this._rejectConnect = reject
        })
        .receive('error', (resp) => {
          reject(new Error(resp.error || 'webrtc:offer rejected'))
        })

      // Timeout after 15 seconds
      setTimeout(() => {
        if (this._resolveConnect) {
          this._resolveConnect = null
          reject(new Error('WebRTC connection timed out'))
        }
      }, 15000)
    })
  }

  /**
   * Send data over a named DataChannel.
   * @param {string} label — channel label (e.g. "events" or "state")
   * @param {string|ArrayBuffer|Blob} data
   * @returns {boolean} true if sent, false if channel is not open
   */
  send(label, data) {
    const dc = this.channels.get(label)
    if (!dc || dc.readyState !== 'open') return false
    dc.send(data)
    return true
  }

  /**
   * Call a server-side plugin hook over the "events" DataChannel.
   *
   * In protobuf mode replies are correlated by request id, so concurrent
   * calls (including to the same function) are safe. In JSON mode replies
   * are matched by plugin+fn (legacy protocol), first pending call wins.
   *
   * @param {string} plugin
   * @param {string} fn
   * @param {Array}  args
   * @param {number} timeoutMs
   * @returns {Promise<any>} the hook result
   */
  callHook(plugin, fn, args = [], timeoutMs = 10000) {
    const dc = this.channels.get('events')
    if (!dc || dc.readyState !== 'open') {
      return Promise.reject(new Error('events DataChannel is not open'))
    }

    return new Promise((resolve, reject) => {
      let key
      if (this.format === 'protobuf') {
        const id = this._nextCallId++
        key = id
        const envelope = PB.RtcEnvelope.encode({
          call_hook: { id, plugin, fn, args_json: new TextEncoder().encode(JSON.stringify(args)) },
        }).finish()
        dc.send(envelope)
      } else {
        key = `${plugin} ${fn}`
        dc.send(JSON.stringify({ type: 'call_hook', plugin, fn, args }))
      }

      const timer = setTimeout(() => {
        this._pendingCalls.delete(key)
        reject(new Error(`callHook ${plugin}.${fn} timed out`))
      }, timeoutMs)

      this._pendingCalls.set(key, { resolve, reject, timer })
    })
  }

  /**
   * Call a typed (protobuf) plugin hook over the "events" DataChannel.
   *
   * Encode the bytes with your game's schema (convention: <FnName>Request /
   * <FnName>Reply, registered by the plugin) — the server decodes them into
   * the request struct, so a hook without a registered schema errors with
   * hook_schema_missing. Requires format: 'protobuf'.
   *
   * @param {string} plugin
   * @param {string} fn
   * @param {Uint8Array} bytes - encoded request message
   * @param {number} timeoutMs
   * @returns {Promise<Uint8Array>} the raw reply bytes
   */
  callHookRaw(plugin, fn, bytes, timeoutMs = 10000) {
    if (this.format !== 'protobuf') {
      return Promise.reject(new Error('callHookRaw requires format: "protobuf"'))
    }
    const dc = this.channels.get('events')
    if (!dc || dc.readyState !== 'open') {
      return Promise.reject(new Error('events DataChannel is not open'))
    }

    return new Promise((resolve, reject) => {
      const id = this._nextCallId++
      const envelope = PB.RtcEnvelope.encode({
        call_hook: { id, plugin, fn, args_raw: bytes },
      }).finish()
      dc.send(envelope)

      const timer = setTimeout(() => {
        this._pendingCalls.delete(id)
        reject(new Error(`callHookRaw ${plugin}.${fn} timed out`))
      }, timeoutMs)

      this._pendingCalls.set(id, { resolve, reject, timer })
    })
  }

  /**
   * Check if a specific DataChannel is open.
   * @param {string} label
   * @returns {boolean}
   */
  isChannelOpen(label) {
    const dc = this.channels.get(label)
    return dc ? dc.readyState === 'open' : false
  }

  /**
   * Check if the WebRTC connection is active.
   * @returns {boolean}
   */
  isConnected() {
    return this.pc != null && this.connectionState === 'connected'
  }

  /**
   * Close the WebRTC connection and all DataChannels.
   * Notifies the server via the Phoenix channel.
   */
  close() {
    this._removeChannelListeners()

    // Close all DataChannels
    for (const dc of this.channels.values()) {
      try { dc.close() } catch (_) {}
    }
    this.channels.clear()

    // Close PeerConnection
    if (this.pc) {
      try { this.pc.close() } catch (_) {}
      this.pc = null
    }

    // Notify server
    this.channel.push('webrtc:close', {})
    this.connectionState = 'closed'
  }

  // ── Private: signaling channel listeners ──────────────────────────────────

  _setupChannelListeners() {
    // Server sends SDP answer
    this._answerRef = this.channel.on('webrtc:answer', (payload) => {
      if (this.pc) {
        this.pc.setRemoteDescription(
          new RTCSessionDescription({ sdp: payload.sdp, type: payload.type })
        )
      }
    })

    // Server sends ICE candidate
    this._iceRef = this.channel.on('webrtc:ice', (payload) => {
      if (this.pc && payload.candidate) {
        this.pc.addIceCandidate(new RTCIceCandidate(payload)).catch((err) => this._emitError(err))
      }
    })

    // Server notifies about connection state changes
    this._stateRef = this.channel.on('webrtc:state', (payload) => {
      const cb = this.opts.onStateChange
      if (cb) cb(payload.state)
    })

    // Server relays DataChannel data back via WebSocket (fallback)
    this._dataRef = this.channel.on('webrtc:data', (payload) => {
      const cb = this.opts.onData
      if (cb) cb(payload.channel, payload.data)
    })

    // Server confirms channel open
    this._openRef = this.channel.on('webrtc:channel_open', (payload) => {
      const cb = this.opts.onChannelOpen
      if (cb) cb(payload.channel)
    })
  }

  _removeChannelListeners() {
    if (this._answerRef) this.channel.off('webrtc:answer', this._answerRef)
    if (this._iceRef)   this.channel.off('webrtc:ice', this._iceRef)
    if (this._stateRef) this.channel.off('webrtc:state', this._stateRef)
    if (this._dataRef)  this.channel.off('webrtc:data', this._dataRef)
    if (this._openRef)  this.channel.off('webrtc:channel_open', this._openRef)
  }

  // ── Private: RTCPeerConnection event handlers ─────────────────────────────

  _onIceCandidate(event) {
    if (event.candidate) {
      this.channel.push('webrtc:ice', event.candidate.toJSON())
    }
  }

  _onConnectionStateChange() {
    const state = this.pc.connectionState
    this.connectionState = state

    const cb = this.opts.onStateChange
    if (cb) cb(state)

    if (state === 'connected' && this._resolveConnect) {
      this._resolveConnect()
      this._resolveConnect = null
      this._rejectConnect = null
    }

    if (state === 'failed' && this._rejectConnect) {
      this._rejectConnect(new Error('WebRTC connection failed'))
      this._resolveConnect = null
      this._rejectConnect = null
    }
  }

  // ── Private: DataChannel wiring ───────────────────────────────────────────

  _wireDataChannel(dc) {
    dc.onopen = () => {
      const cb = this.opts.onChannelOpen
      if (cb) cb(dc.label)

      // Resolve connect() promise when the FIRST channel opens
      if (this._resolveConnect) {
        this._resolveConnect()
        this._resolveConnect = null
        this._rejectConnect = null
      }
    }

    dc.onclose = () => {
      const cb = this.opts.onChannelClose
      if (cb) cb(dc.label)
    }

    dc.onmessage = (event) => {
      if (dc.label === 'events' && this._handleRpcReply(event.data)) return
      const cb = this.opts.onData
      if (cb) cb(dc.label, event.data)
    }

    dc.onerror = (event) => {
      this._emitError(event.error || event)
    }
  }

  // Routes hook replies to pending callHook promises. Returns true when the
  // message was an RPC reply and has been consumed.
  _handleRpcReply(data) {
    try {
      if (this.format === 'protobuf') {
        if (typeof data === 'string') return false
        const bin = data instanceof Uint8Array ? data : new Uint8Array(data)
        const env = PB.RtcEnvelope.decode(bin)
        if (env.hook_reply) {
          const pending = this._takePending(env.hook_reply.id)
          if (pending) {
            if (env.hook_reply.data === 'data_raw') {
              pending.resolve(env.hook_reply.data_raw)
            } else {
              const json = new TextDecoder().decode(env.hook_reply.data_json ?? new Uint8Array())
              pending.resolve(json.length ? JSON.parse(json) : null)
            }
          }
          return true
        }
        if (env.hook_error) {
          const pending = this._takePending(env.hook_error.id)
          if (pending) pending.reject(new Error(env.hook_error.error))
          return true
        }
        return false
      }

      if (typeof data !== 'string') return false
      const msg = JSON.parse(data)
      if (msg.type !== 'hook_reply' && msg.type !== 'hook_error') return false
      const pending = this._takePending(`${msg.plugin} ${msg.fn}`)
      if (!pending) return false
      if (msg.type === 'hook_reply') pending.resolve(msg.data)
      else pending.reject(new Error(msg.error))
      return true
    } catch (_) {
      return false
    }
  }

  _takePending(key) {
    const pending = this._pendingCalls.get(key)
    if (pending) {
      clearTimeout(pending.timer)
      this._pendingCalls.delete(key)
    }
    return pending
  }

  _emitError(error) {
    const cb = this.opts.onError
    if (cb) cb(error)
  }
}

export default GameWebRTC
