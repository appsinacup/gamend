// `node --test apps/gamend_web/assets/js/test/` — no dependencies. Also run by
// `test/gamend_web/js_test.exs`, so `mix test` covers it.
import {test, beforeEach} from "node:test"
import assert from "node:assert/strict"

import {ANONYMOUS_SESSION_PATH, startAnonymousSession, stampAnonymousSession} from "../anonymous_session.js"

let listeners, socketCalls, liveSocket

beforeEach(() => {
  listeners = {}
  socketCalls = []
  globalThis.window = {addEventListener: (type, fn) => (listeners[type] ||= []).push(fn)}
  globalThis.document = {
    querySelector: (sel) => (sel.includes("csrf") ? {getAttribute: () => "csrf-1"} : null),
  }
  liveSocket = {
    disconnect: (cb) => {
      socketCalls.push("disconnect")
      cb()
    },
    connect: () => socketCalls.push("connect"),
  }
})

const okFetch = (calls) => async (url, opts) => {
  calls.push({url, opts})
  return {ok: true}
}

test("the token is posted with the CSRF header, then the socket reconnects", async () => {
  const calls = []
  const ok = await stampAnonymousSession("tok", {getLiveSocket: () => liveSocket, fetchImpl: okFetch(calls)})

  assert.equal(ok, true)
  assert.equal(calls[0].url, ANONYMOUS_SESSION_PATH)
  assert.equal(calls[0].opts.method, "POST")
  assert.equal(calls[0].opts.headers["x-csrf-token"], "csrf-1")
  assert.deepEqual(JSON.parse(calls[0].opts.body), {token: "tok"})
  assert.deepEqual(socketCalls, ["disconnect", "connect"])
})

test("a refused token leaves the socket alone", async () => {
  const ok = await stampAnonymousSession("tok", {
    getLiveSocket: () => liveSocket,
    fetchImpl: async () => ({ok: false}),
  })

  assert.equal(ok, false)
  assert.deepEqual(socketCalls, [])
})

test("a network failure is swallowed", async () => {
  const ok = await stampAnonymousSession("tok", {
    getLiveSocket: () => liveSocket,
    fetchImpl: async () => {
      throw new Error("offline")
    },
  })

  assert.equal(ok, false)
  assert.deepEqual(socketCalls, [])
})

test("the pushed event drives it, and an event with no token does nothing", async () => {
  const calls = []
  startAnonymousSession({getLiveSocket: () => liveSocket, fetchImpl: okFetch(calls)})
  const [listener] = listeners["phx:gamend:anonymous_session"]

  await listener({detail: {}})
  assert.equal(calls.length, 0)

  await listener({detail: {token: "tok"}})
  assert.equal(calls.length, 1)
  assert.deepEqual(socketCalls, ["disconnect", "connect"])
})
