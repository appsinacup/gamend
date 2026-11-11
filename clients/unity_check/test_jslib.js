// Run GamendWebSocket.jslib in node against a fake browser WebSocket and a
// fake Emscripten heap, the way a WebGL player runs it, and check what reaches
// the C# callbacks:
//
//   node clients/unity_check/test_jslib.js unity_sdk
//
// Emscripten's `{{{ makeDynCall(sig, ptr) }}}` becomes a lookup in a table of
// JS functions standing in for the C# ones. It shows the library's logic; the
// build of a real WebGL player is what shows Emscripten takes it.
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = process.argv[2] || 'unity_sdk';
const file = path.join(root, 'Runtime/Unity/Plugins/WebGL/GamendWebSocket.jslib');
const source = fs
  .readFileSync(file, 'utf8')
  .replace(/\{\{\{\s*makeDynCall\('(\w+)',\s*'([^']+)'\)\s*\}\}\}/g, (_, sig, pointer) => `dynCall('${sig}', ${pointer})`);

const heap = new Uint8Array(1 << 16);
let next = 8;
const live = new Set();
const sockets = [];
const timers = [];
const calls = [];

class FakeWebSocket {
  constructor(url) {
    if (!/^wss?:\/\//.test(url)) throw new SyntaxError(`invalid url ${url}`);
    this.url = url;
    this.readyState = 0;
    this.sent = [];
    this.closed = null;
    sockets.push(this);
  }
  send(frame) {
    this.sent.push(frame);
  }
  close(code) {
    this.closed = code;
    this.readyState = 3;
  }
}

const table = new Map();
let nextFunction = 1;
function callback(name, sig) {
  const pointer = nextFunction++;
  table.set(pointer, { sig, fn: (...args) => calls.push([name, ...args]) });
  return pointer;
}

// C#'s side reads the bytes during the call, as Marshal.Copy does.
function readBytes(pointer, length) {
  assert.ok(live.has(pointer), 'the bytes are still allocated during the call');
  return Buffer.from(heap.subarray(pointer, pointer + length));
}

const library = {};
const context = vm.createContext({
  TextEncoder,
  WebSocket: FakeWebSocket,
  HEAPU8: heap,
  setTimeout: (fn) => timers.push(fn),
  _malloc(size) {
    const pointer = next;
    next += size;
    live.add(pointer);
    return pointer;
  },
  _free(pointer) {
    assert.ok(live.delete(pointer), 'freed once');
  },
  UTF8ToString(pointer) {
    let end = pointer;
    while (heap[end] !== 0) end++;
    return Buffer.from(heap.subarray(pointer, end)).toString('utf8');
  },
  dynCall(sig, pointer) {
    const entry = table.get(pointer);
    assert.ok(entry, `callback ${pointer} registered`);
    assert.equal(entry.sig, sig, 'the signature the C# delegate has');
    return entry.fn;
  },
  LibraryManager: { library },
  mergeInto(target, items) {
    Object.assign(target, items);
  },
  autoAddDeps(items, name) {
    assert.ok(items[name], `${name} is in the library`);
  },
});
vm.runInContext(source, context, { filename: file });

// What Emscripten does with the library: `$name` becomes a global `name`, and
// every other entry a function C# can call.
for (const [key, value] of Object.entries(library)) {
  if (key.startsWith('$')) context[key.slice(1)] = value;
}
const lib = library;

// A C# string argument: NUL-terminated UTF-8 in the heap.
function cString(text) {
  const bytes = Buffer.from(text + '\0', 'utf8');
  const pointer = next;
  next += bytes.length;
  heap.set(bytes, pointer);
  return pointer;
}

const onData = callback('data', 'viiii');
const onError = callback('error', 'viii');
const onClose = callback('close', 'viiii');
const onOpen = callback('open', 'vi');
table.get(onData).fn = (id, pointer, length, binary) => calls.push(['data', id, readBytes(pointer, length), binary]);
table.get(onError).fn = (id, pointer, length) => calls.push(['error', id, readBytes(pointer, length).toString('utf8')]);
table.get(onClose).fn = (id, code, pointer, length) =>
  calls.push(['close', id, code, readBytes(pointer, length).toString('utf8')]);

lib.GamendWebSocketInit(onOpen, onData, onError, onClose);

// Open, and binary frames as array buffers.
lib.GamendWebSocketOpen(1, cString('wss://game.example.com/socket/websocket?vsn=2.0.0'));
const first = sockets[0];
assert.equal(first.url, 'wss://game.example.com/socket/websocket?vsn=2.0.0');
assert.equal(first.binaryType, 'arraybuffer');

// Nothing is sent before the socket opens.
lib.GamendWebSocketSend(1, cString('early'));
assert.deepEqual(first.sent, []);

first.readyState = 1;
first.onopen();
assert.deepEqual(calls.shift(), ['open', 1]);

lib.GamendWebSocketSend(1, cString('[null,"1","phoenix","heartbeat",{}]'));
assert.deepEqual(first.sent, ['[null,"1","phoenix","heartbeat",{}]']);

// Text arrives as UTF-8 bytes, binary as itself; an empty frame is empty.
first.onmessage({ data: 'héllo ✓' });
assert.deepEqual(calls.shift(), ['data', 1, Buffer.from('héllo ✓', 'utf8'), 0]);
first.onmessage({ data: new Uint8Array([0, 1, 254, 255]).buffer });
assert.deepEqual(calls.shift(), ['data', 1, Buffer.from([0, 1, 254, 255]), 1]);
first.onmessage({ data: '' });
assert.deepEqual(calls.shift(), ['data', 1, Buffer.alloc(0), 0]);

first.onerror();
assert.deepEqual(calls.shift(), ['error', 1, 'websocket error']);

// The server closes: its code and reason, then the connection is forgotten.
first.onclose({ code: 4001, reason: 'token expired' });
assert.deepEqual(calls.shift(), ['close', 1, 4001, 'token expired']);
first.onmessage({ data: 'late' });
lib.GamendWebSocketSend(1, cString('after close'));
assert.deepEqual(calls, []);
assert.equal(first.sent.length, 1);

// The client closes: a normal close, and nothing from that socket after.
lib.GamendWebSocketOpen(2, cString('ws://localhost:4000/socket/websocket'));
const second = sockets[1];
second.readyState = 1;
second.onopen();
calls.length = 0;
lib.GamendWebSocketClose(2);
assert.equal(second.closed, 1000);
second.onmessage({ data: 'late' });
second.onclose({ code: 1000, reason: '' });
assert.deepEqual(calls, []);
lib.GamendWebSocketClose(2);

// A URL the browser refuses fails the connection after Open returns.
lib.GamendWebSocketOpen(3, cString('not a url'));
assert.deepEqual(calls, []);
timers.splice(0).forEach((fn) => fn());
assert.equal(calls.length, 1);
assert.equal(calls[0][0], 'error');
assert.equal(calls[0][1], 3);
assert.match(calls[0][2], /invalid url/);

assert.equal(live.size, 0, 'every byte handed to C# was freed');
console.log('GamendWebSocket.jslib: ok');
