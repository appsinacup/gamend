// E2E: typed protobuf hook (args_raw/data_raw relay) against the live server,
// plus runtime format-swap checks.
import { readFileSync } from 'fs'
import protobuf from 'protobufjs'
import { RTCPeerConnection, RTCSessionDescription, RTCIceCandidate } from 'node-datachannel/polyfill'
import { GameRealtime } from './realtime.js'
import { GameWebRTC } from './webrtc.js'

globalThis.RTCPeerConnection = RTCPeerConnection
globalThis.RTCSessionDescription = RTCSessionDescription
globalThis.RTCIceCandidate = RTCIceCandidate

const creds = JSON.parse(readFileSync('/tmp/pbtok.json')).data

function fail(msg) {
  console.log(`RESULT: FAIL (${msg})`)
  process.exit(1)
}
setTimeout(() => fail('timeout'), 25000)

// The game's own schema — mirrors the plugin's proto/example_hook.proto.
const { root } = protobuf.parse(
  `syntax = "proto3";
   message HelloProtoRequest { string name = 1; uint32 repeat = 2; }
   message HelloProtoReply  { string greeting = 1; uint32 name_length = 2; }`,
  { keepCase: true }
)
const HelloProtoRequest = root.lookupType('HelloProtoRequest')
const HelloProtoReply = root.lookupType('HelloProtoReply')

const format = process.env.RTC_FORMAT || 'protobuf'
const realtime = new GameRealtime('http://127.0.0.1:4000', () => creds.access_token, { format })
const channel = realtime.joinUserChannel(creds.user_id)
await new Promise((resolve) => channel.on('updated', resolve))

const webrtc = new GameWebRTC(channel, { format, dataChannels: [{ label: 'events', ordered: true }] })
await webrtc.connect()
for (let i = 0; i < 50 && !webrtc.isChannelOpen('events'); i++) {
  await new Promise((r) => setTimeout(r, 100))
}

// Dynamic JSON-args hook works identically in both formats.
const dynamic = await webrtc.callHook('example_hook', 'hello', ['world'])
console.log(`dynamic hook OK (${format} envelope)`)

if (format === 'protobuf') {
  // Typed hook: encode with the game schema, decode the raw reply.
  const req = HelloProtoRequest.encode({ name: 'gamend', repeat: 2 }).finish()
  const rawReply = await webrtc.callHookRaw('example_hook', 'hello_proto', req)
  const reply = HelloProtoReply.toObject(HelloProtoReply.decode(rawReply))
  console.log('typed hook reply:', JSON.stringify(reply))
  if (reply.greeting !== 'Hello, gamend! Hello, gamend!' || reply.name_length !== 6) {
    fail(`unexpected typed reply: ${JSON.stringify(reply)}`)
  }
  console.log(`typed hook request: ${req.length}B vs JSON equivalent: ${JSON.stringify({ name: 'gamend', repeat: 2 }).length}B`)

  // Binary calls to schema-less hooks must be rejected (no opaque relay).
  const noSchemaErr = await webrtc.callHookRaw('example_hook', 'hello', req).catch((e) => e)
  if (!(noSchemaErr instanceof Error) || !noSchemaErr.message.includes('hook_schema_missing')) {
    fail(`expected hook_schema_missing, got: ${noSchemaErr}`)
  }
  console.log('schema-less binary call rejected:', noSchemaErr.message)
} else {
  // Typed hooks must refuse cleanly on a JSON channel.
  const err = await webrtc.callHookRaw('example_hook', 'hello_proto', new Uint8Array([1])).catch((e) => e)
  if (!(err instanceof Error)) fail('callHookRaw should reject on json format')
  console.log('callHookRaw correctly rejected on json channel:', err.message)
}

// The SAME typed hook is callable with a plain JSON object from any format —
// the server converts through the registered schema (auto-conversion).
const jsonReply = await webrtc.callHook('example_hook', 'hello_proto', [{ name: 'swap', repeat: 1 }])
console.log('typed hook via JSON object:', JSON.stringify(jsonReply))
if (jsonReply.greeting !== 'Hello, swap!' || jsonReply.name_length !== 4) {
  fail(`json-object typed reply wrong: ${JSON.stringify(jsonReply)}`)
}

// And over the WebSocket call_hook too (phx_reply framing).
const wsReply = await realtime.callHook('example_hook', 'hello_proto', [{ name: 'ws', repeat: 3 }])
console.log('typed hook via WS:', JSON.stringify(wsReply))
if (wsReply.name_length !== 2) fail(`ws typed reply wrong: ${JSON.stringify(wsReply)}`)

console.log(`RESULT: PASS (${format})`)
process.exit(0)
