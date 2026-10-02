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

const http = require('http')
const path = require('path')

const dist = path.join(__dirname, 'javascript', 'dist', 'index.js')
const { ApiClient, HealthApi, GameRealtime, GameWebRTC } = require(dist)

const failures = []

function check (name, ok, detail) {
  if (ok) {
    console.log(`  ok    ${name}`)
  } else {
    console.log(`  FAIL  ${name}${detail ? ` - ${detail}` : ''}`)
    failures.push(name)
  }
}

// Answers as GET /api/v1/health does: the one-object shape, under `data`.
const server = http.createServer((req, res) => {
  res.setHeader('content-type', 'application/json')
  res.end(JSON.stringify({ data: { status: 'ok', timestamp: new Date().toISOString() } }))
})

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

    // Constructing GameRealtime exercises the Phoenix.Socket wrapper and proves
    // the bundle can reach phoenix. Passing a tokenProvider (4th arg, the fix
    // for #47) must not throw: Phoenix JS stores params as a function and only
    // calls it on an actual transport connect, which we pre-empt with disconnect().
    try {
      const realtime = new GameRealtime(
        `ws://127.0.0.1:${port}`,
        'dummy-token',
        {},
        () => 'dummy-token'
      )
      check('GameRealtime accepts a tokenProvider (4th arg)', typeof realtime === 'object')
      realtime.disconnect()
      check('GameRealtime disconnects cleanly with a tokenProvider', true)
    } catch (e) {
      check('GameRealtime accepts a tokenProvider (4th arg)', false, e.message)
    }

    // realtime.js pulls phoenix; gamend_realtime.pb.js pulls protobufjs.
    // Requiring them here is what catches an undeclared runtime dependency.
    const proto = require(path.join(__dirname, 'javascript', 'dist', 'gamend_proto.js'))
    check('protobuf codec loads', proto && typeof proto.decodeEvent === 'function')
  } catch (error) {
    check('package loads and runs', false, error && error.message)
  } finally {
    server.close()
  }

  if (failures.length > 0) {
    console.error(`\nsmoke_package: ${failures.length} check(s) failed - not safe to publish`)
    process.exit(1)
  }
  console.log('smoke_package: all checks passed')
})
