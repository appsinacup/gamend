#!/usr/bin/env node
/**
 * check_realtime.mjs
 *
 * Drive GameRealtime (realtime.js, the source the package ships) against a
 * live server through a token change, the way a long-lived client meets one:
 * the socket is up, its access token stops being valid, the connection drops,
 * and the client refreshes.
 *
 * The server checks the token only when a socket connects, so what matters is
 * the token each reconnect sends. A socket that replays its first token is
 * refused from then on; one given the fresh token must reconnect and rejoin.
 *
 *   node clients/check_realtime.mjs http://127.0.0.1:4000
 *   node clients/check_realtime.mjs http://127.0.0.1:4000 --expiry
 *
 * By default the old token is made invalid by revoking it (`DELETE /logout`),
 * which takes seconds. `--expiry` waits for it to expire instead and renews it
 * with `POST /refresh`: run the server with GAMEND_AUTH_ACCESS_TOKEN_TTL_MINUTES=1.
 *
 * The socket goes through a local TCP relay, so the check can cut it the way a
 * network drop does. The relay forwards raw bytes: give it an http:// server.
 *
 * Signs in with a fresh device id, so device login must be on.
 */
import net from 'node:net'
import { WebSocket } from 'undici'
import { GameRealtime } from './realtime.js'

const server = (process.argv.find((a) => /^https?:\/\//.test(a)) || 'http://127.0.0.1:4000').replace(/\/$/, '')
const useExpiry = process.argv.includes('--expiry')
const deviceId = `realtime-check-${Date.now()}`
let failures = 0

function check (label, ok, detail) {
  if (ok) console.log(`ok   ${label}`)
  else { failures++; console.log(`FAIL ${label}${detail ? `: ${detail}` : ''}`) }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

async function api (method, path, { body, token } = {}) {
  const res = await fetch(`${server}/api/v1${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {})
    },
    body: body && JSON.stringify(body)
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${JSON.stringify(json)}`)
  return json.data
}

const login = () => api('POST', '/login/device', { body: { device_id: deviceId } })

// Resolves once `predicate()` holds, polling; false after `ms`.
async function waitFor (predicate, ms) {
  const until = Date.now() + ms
  while (Date.now() < until) {
    if (predicate()) return true
    await sleep(50)
  }
  return predicate()
}

// A TCP relay in front of the server. `drop()` destroys every connection
// without a close frame, which the client sees as a network drop (1006) and
// answers with a reconnect. Closing the WebSocket from the client instead
// would be a clean close, after which Phoenix does not reconnect.
function relay (target) {
  const { hostname, port } = new URL(target)
  const open = new Set()
  const server = net.createServer((client) => {
    const upstream = net.connect(Number(port) || 80, hostname)
    const end = () => {
      client.destroy()
      upstream.destroy()
      open.delete(client)
      open.delete(upstream)
    }
    open.add(client)
    open.add(upstream)
    client.pipe(upstream)
    upstream.pipe(client)
    for (const s of [client, upstream]) { s.on('error', end); s.on('close', end) }
  })
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({
    url: `http://127.0.0.1:${server.address().port}`,
    drop: () => open.forEach((s) => s.destroy()),
    close: () => { open.forEach((s) => s.destroy()); server.close() }
  })))
}

// Makes the session's current access token invalid and returns fresh
// credentials: revoke and sign in again, or wait out the TTL and refresh.
async function invalidateAndRenew (session) {
  if (useExpiry) {
    const waitMs = (session.expires_in + 5) * 1000
    console.log(`     waiting ${session.expires_in + 5}s for the access token to expire`)
    await sleep(waitMs)
    return { expired: session, renew: () => api('POST', '/refresh', { body: { refresh_token: session.refresh_token } }) }
  }
  await api('DELETE', '/logout', { token: session.access_token })
  return { expired: session, renew: login }
}

function track (realtime) {
  const state = { opens: 0, errors: 0 }
  realtime.socket.onOpen(() => state.opens++)
  realtime.socket.onError(() => state.errors++)
  return state
}

// The socket's transport. Node 22's built-in WebSocket (undici 6) fires
// `error` on a refused upgrade and never `close`, so Phoenix, which reconnects
// on `close`, waits forever. Browsers and current undici fire both, and that is
// the behaviour this check is about.
const socketOpts = { transport: WebSocket }

async function scenario (name, makeRealtime, afterRenew) {
  console.log(`-- ${name}`)
  const link = await relay(server)
  let session = await login()
  const holder = { token: session.access_token }
  const realtime = makeRealtime(link.url, holder)
  const channel = realtime.joinUserChannel(session.user_id)
  const state = track(realtime)

  check(`${name}: socket connects and joins user:<id>`,
    await waitFor(() => channel.state === 'joined', 5000), `channel state ${channel.state}`)

  const { renew } = await invalidateAndRenew(session)
  check(`${name}: the open socket survives the token going stale`, realtime.socket.isConnected())

  const errorsBefore = state.errors
  link.drop()
  await waitFor(() => state.errors > errorsBefore, 5000)
  await sleep(500)
  check(`${name}: reconnects with the stale token are refused`,
    !realtime.socket.isConnected() && state.errors > errorsBefore,
    `connected=${realtime.socket.isConnected()} errors=${state.errors - errorsBefore}`)

  session = await renew()
  const opensBefore = state.opens
  const started = Date.now()
  afterRenew(realtime, holder, session.access_token)
  const back = await waitFor(() => state.opens > opensBefore && channel.state === 'joined', 8000)
  check(`${name}: reconnects with the renewed token and rejoins`, back,
    `connected=${realtime.socket.isConnected()} channel=${channel.state}`)
  if (back) console.log(`     back in ${Date.now() - started}ms`)

  realtime.disconnect()
  link.close()
  await api('DELETE', '/logout', { token: session.access_token }).catch(() => {})
}

;(async () => {
  console.log(`check_realtime: ${server} (${useExpiry ? 'token expiry + refresh' : 'token revocation + sign-in'})`)

  await scenario('setToken',
    (url, holder) => new GameRealtime(url, holder.token, socketOpts),
    // Guarded so a build without setToken reports the failure, not a crash.
    (realtime, _holder, token) => realtime.setToken && realtime.setToken(token))

  await scenario('token function',
    (url, holder) => new GameRealtime(url, () => holder.token, socketOpts),
    (_realtime, holder, token) => { holder.token = token })

  console.log(`failures=${failures}`)
  process.exit(failures ? 1 : 0)
})().catch((e) => { console.log('FAIL', e.message); process.exit(1) })
