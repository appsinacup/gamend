#!/usr/bin/env node
/**
 * postgenerate.js
 *
 * Run this after `openapi-generator-cli generate` to inject the handcrafted
 * exports (GameRealtime, GameWebRTC, GamendSession) into the auto-generated
 * src/index.js without touching the rest of the generated code.
 *
 * Called automatically by the `generate` npm script in clients/package.json.
 * This file lives in clients/ (tracked by git) and is NOT inside clients/javascript/.
 */

const fs = require('fs')
const path = require('path')

// This script runs from clients/ directory, so javascript/src/index.js is the target
const indexPath = path.join(__dirname, 'javascript', 'src', 'index.js')

// A sentinel that only this script writes. The previous guard looked for the
// bare string "GameRealtime", which the OpenAPI description also contains (it
// documents `import { GameRealtime } from '@ughuuu/gamend'`, and the generator
// copies the description into the JSDoc header of index.js). So the guard
// matched the doc comment, the injection was skipped silently, and the built
// package exported no realtime classes at all.
const MARKER = '── Real-time extensions (handcrafted, not auto-generated) ──'

const additions = `
// ${MARKER}

/**
 * GameRealtime — Phoenix WebSocket channel manager.
 * Wraps Phoenix.Socket. \`phoenix\` ships as a dependency of this package.
 */
export { GameRealtime, GameRealtime as default_GameRealtime } from './realtime';

/**
 * GameWebRTC — WebRTC DataChannel client (browser only).
 * Uses an existing Phoenix channel for SDP/ICE signaling.
 */
export { GameWebRTC, GameWebRTC as default_GameWebRTC } from './webrtc';

/**
 * GamendSession — keeps a player signed in: holds the tokens, refreshes the
 * access token, and hands GameRealtime a token function.
 */
export { GamendSession, GamendSession as default_GamendSession } from './session';
`

let content = fs.readFileSync(indexPath, 'utf8')

if (content.includes(MARKER)) {
  console.log('postgenerate: real-time exports already present in index.js — skipping')
  process.exit(0)
}

fs.appendFileSync(indexPath, additions)
console.log('postgenerate: injected GameRealtime + GameWebRTC + GamendSession exports into src/index.js')
