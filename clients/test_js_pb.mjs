// E2E: JS client in protobuf mode against the live gamend.
// 1. GameRealtime format=protobuf: join user channel, decoded "updated" event.
// 2. GameWebRTC protocol=protobuf: callHook round-trip with request ids.
import { readFileSync } from 'fs'
import { RTCPeerConnection, RTCSessionDescription, RTCIceCandidate } from 'node-datachannel/polyfill'
import { GameRealtime } from './realtime.js'
import { GameWebRTC } from './webrtc.js'

globalThis.RTCPeerConnection = RTCPeerConnection
globalThis.RTCSessionDescription = RTCSessionDescription
globalThis.RTCIceCandidate = RTCIceCandidate

const creds = JSON.parse(readFileSync('/tmp/pbtok.json')).data
const token = creds.access_token
const userId = creds.user_id

function fail(msg) {
  console.log(`RESULT: FAIL (${msg})`)
  process.exit(1)
}

const timeout = setTimeout(() => fail('timeout'), 20000)

const realtime = new GameRealtime('http://127.0.0.1:4000', () => token, { format: 'protobuf' })
const channel = realtime.joinUserChannel(userId)

const updated = await new Promise((resolve) => channel.on('updated', resolve))
if (!(updated && typeof updated === 'object') || updated instanceof ArrayBuffer) {
  fail(`updated not decoded: ${updated?.constructor?.name}`)
}
if (updated.id !== userId) fail(`id mismatch: ${updated.id}`)
if (typeof updated.last_seen_at_ms !== 'number') fail(`last_seen_at_ms: ${updated.last_seen_at_ms}`)
if (typeof updated.metadata !== 'object') fail(`metadata: ${updated.metadata}`)
console.log('WS updated decoded OK:', JSON.stringify({ id: updated.id, is_online: updated.is_online, last_seen_at_ms: updated.last_seen_at_ms }))

// WebRTC protobuf RPC
const webrtc = new GameWebRTC(channel, {
  format: process.env.RTC_FORMAT || 'protobuf',
  dataChannels: [{ label: 'events', ordered: true }],
  onData: (label, data) => console.log('onData:', label, typeof data, data?.constructor?.name, data?.byteLength ?? data?.length ?? ''),
})
await webrtc.connect()
for (let i = 0; i < 50 && !webrtc.isChannelOpen('events'); i++) {
  await new Promise((r) => setTimeout(r, 100))
}
if (!webrtc.isChannelOpen('events')) fail('events channel never opened')
console.log('WebRTC connected (protobuf events channel)')

// Concurrent calls to the same fn — only possible to correlate with ids.
// Concurrent same-fn calls require id correlation (protobuf only); the
// legacy JSON protocol matches by plugin+fn so it must call sequentially.
let r1, r2
if ((process.env.RTC_FORMAT || 'protobuf') === 'protobuf') {
  ;[r1, r2] = await Promise.all([
    webrtc.callHook('example_hook', 'hello', ['alpha']),
    webrtc.callHook('example_hook', 'hello', ['beta']),
  ])
} else {
  r1 = await webrtc.callHook('example_hook', 'hello', ['alpha'])
  r2 = await webrtc.callHook('example_hook', 'hello', ['beta'])
}
console.log('hook replies:', JSON.stringify(r1), '|', JSON.stringify(r2))
// hello/1 returns a Bunt iolist (nested arrays); verify content + id correlation.
const flat = (x) => (Array.isArray(x) ? x.map(flat).join('') : String(x))
if (!flat(r1).includes('alpha') || !flat(r2).includes('beta')) fail(`replies not correlated: ${flat(r1)} / ${flat(r2)}`)

clearTimeout(timeout)
console.log('RESULT: PASS')
process.exit(0)
