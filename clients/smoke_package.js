#!/usr/bin/env node
/**
 * smoke_package.js
 *
 * Prove the built JS SDK actually works before it is published: make a real
 * HTTP round trip through the generated client, and load the handcrafted
 * realtime code (which reaches phoenix and protobufjs).
 *
 * The publish job resolves the SDK's runtime dependencies to their newest
 * versions on every run, so this is what makes that safe: a new major that
 * breaks the client fails here instead of shipping.
 *
 *   node clients/smoke_package.js
 */

const crypto = require('crypto')
const http = require('http')
const path = require('path')

const dist = path.join(__dirname, 'javascript', 'dist', 'index.js')
const {
  ApiClient, HealthApi, AuthenticationApi, UsersApi, GameRealtime, GameWebRTC, GamendSession
} = require(dist)

const failures = []

function check (name, ok, detail) {
  if (ok) {
    console.log(`  ok    ${name}`)
  } else {
    console.log(`  FAIL  ${name}${detail ? ` - ${detail}` : ''}`)
    failures.push(name)
  }
}

// One access token is good at a time, for the API and the socket alike, as
// after a refresh; the sign-in routes issue the next one.
const auth = { access: 'fresh', refresh: 'r1', issued: 0, logoutHeader: null }

function issueSession () {
  auth.access = `a${++auth.issued}`
  return {
    data: {
      access_token: auth.access,
      refresh_token: auth.refresh,
      expires_in: 900,
      user_id: 'u1',
      username: 'player',
      display_name: 'Player'
    }
  }
}

const server = http.createServer((req, res) => {
  let raw = ''
  req.on('data', (chunk) => { raw += chunk })
  req.on('end', () => {
    const reply = (status, body) => {
      res.statusCode = status
      res.setHeader('content-type', 'application/json')
      res.end(JSON.stringify(body))
    }
    const bearer = req.headers.authorization
    switch (`${req.method} ${req.url.split('?')[0]}`) {
      case 'POST /api/v1/login':
        return reply(200, issueSession())
      case 'POST /api/v1/refresh':
        return JSON.parse(raw || '{}').refresh_token === auth.refresh
          ? reply(200, issueSession())
          : reply(401, { error: 'invalid_refresh_token' })
      case 'GET /api/v1/me':
        return bearer === `Bearer ${auth.access}`
          ? reply(200, { data: { id: 'u1' } })
          : reply(401, { error: 'unauthorized' })
      case 'DELETE /api/v1/logout':
        auth.logoutHeader = bearer
        return reply(200, { ok: true })
      default:
        // Answers as GET /api/v1/health does: the one-object shape, under `data`.
        return reply(200, { data: { status: 'ok', timestamp: new Date().toISOString() } })
    }
  })
})

// Answers the socket as UserSocket does: 403 for any token but the good one.
const tokensSent = []
const upgraded = new Set()
server.on('upgrade', (req, socket) => {
  const token = new URL(req.url, 'http://x').searchParams.get('token')
  tokensSent.push(token)
  if (token !== auth.access) {
    socket.end('HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n', () => socket.destroy())
    return
  }
  const accept = crypto.createHash('sha1')
    .update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
    .digest('base64')
  socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${accept}\r\n\r\n`)
  upgraded.add(socket)
})

// Node's WebSocket fires no close after a failed handshake, and a close is what
// makes Phoenix retry. Browsers fire one (code 1006); this does too.
class BrowserWebSocket extends WebSocket {
  constructor (url, protocols) {
    super(url, protocols)
    let closed = false
    this.addEventListener('close', () => { closed = true })
    this.addEventListener('error', () => setTimeout(() => {
      if (!closed) {
        closed = true
        if (this.onclose) this.onclose({ code: 1006 })
      }
    }, 0))
  }
}

function opens (realtime) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(false), 5000)
    realtime.socket.onOpen(() => { clearTimeout(timer); resolve(true) })
  })
}

server.listen(0, '127.0.0.1', async () => {
  const { port } = server.address()
  console.log('smoke_package: exercising the built package')

  try {
    const client = new ApiClient()
    client.basePath = `http://127.0.0.1:${port}`

    const body = await new HealthApi(client).index()
    check('generated client completes an HTTP request',
      body && body.data && body.data.status === 'ok', `got ${JSON.stringify(body)}`)

    check('GameRealtime is exported', typeof GameRealtime === 'function')
    check('GameWebRTC is exported', typeof GameWebRTC === 'function')

    let rejected = false
    try { new GameRealtime(`ws://127.0.0.1:${port}`, 'a-token') } catch (e) { rejected = e instanceof TypeError }
    check('GameRealtime takes a token function, not a token', rejected)

    // A socket whose token expired: the first connect is refused, and only then
    // does getToken (async, as an app's refresh is) answer with a fresh token.
    let asked = 0
    const getToken = async () => (++asked === 1 ? 'expired' : 'fresh')
    const realtime = new GameRealtime(`ws://127.0.0.1:${port}`, getToken, { transport: BrowserWebSocket })
    const opened = await opens(realtime)
    realtime.disconnect()
    check('GameRealtime reconnects with a refreshed token',
      opened && tokensSent[0] === 'expired' && tokensSent[tokensSent.length - 1] === 'fresh',
      `tokens sent: ${tokensSent.join(', ')}`)

    // GamendSession holds the tokens the app would otherwise juggle.
    const gamend = new GamendSession(`http://127.0.0.1:${port}`)
    const sessions = []
    let authFailed = 0
    gamend.on('session', (session) => sessions.push(session))
    gamend.on('authFailed', () => { authFailed++ })

    await new AuthenticationApi(gamend.client)
      .login({ loginRequest: { email: 'player@example.com', password: 'secret' } })
    check('GamendSession picks up a sign-in',
      gamend.userId === 'u1' && gamend.session.access_token === 'a1' && sessions.length === 1)

    auth.access = 'revoked' // a1 stops working before its expires_in says so
    const me = await new UsersApi(gamend.client).getCurrentUser()
    check('GamendSession refreshes and retries after a 401',
      me && me.data && me.data.id === 'u1' && gamend.session.access_token === 'a2',
      `holds ${gamend.session && gamend.session.access_token}`)

    check('GamendSession opens realtime with its token',
      await opens(gamend.realtime({ transport: BrowserWebSocket })))

    await gamend.signOut()
    check('GamendSession signs out with the refresh token',
      auth.logoutHeader === 'Bearer r1' && !gamend.signedIn && sessions[sessions.length - 1] === null,
      `logout sent ${auth.logoutHeader}`)

    gamend.restore({ access_token: 'a2', refresh_token: 'revoked', expires_at: 0, user_id: 'u1' })
    const token = await gamend.getAccessToken()
    check('GamendSession drops a session whose refresh token is refused',
      token === null && !gamend.signedIn && authFailed === 1)

    // realtime.js pulls phoenix; gamend_realtime.pb.js pulls protobufjs.
    // Requiring them here is what catches an undeclared runtime dependency.
    const proto = require(path.join(__dirname, 'javascript', 'dist', 'gamend_proto.js'))
    check('protobuf codec loads', proto && typeof proto.decodeEvent === 'function')
  } catch (error) {
    check('package loads and runs', false, error && error.message)
  } finally {
    upgraded.forEach((socket) => socket.destroy())
    server.close()
  }

  if (failures.length > 0) {
    console.error(`\nsmoke_package: ${failures.length} check(s) failed - not safe to publish`)
    process.exit(1)
  }
  console.log('smoke_package: all checks passed')
})
