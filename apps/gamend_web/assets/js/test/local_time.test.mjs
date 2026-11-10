// `node --test assets/js/test/*.test.mjs` — no dependencies. Also run by
// `test/gamend_web/js_test.exs`.
//
// `local_time.js`: how long ago a relative `<.timestamp>` says something was.
import {test} from "node:test"
import assert from "node:assert/strict"

import {agoParts, agoText} from "../local_time.js"

const MINUTE = 60
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

test("picks the largest unit that fits", () => {
  assert.deepEqual(agoParts(3), [3, "second"])
  assert.deepEqual(agoParts(59), [59, "second"])
  assert.deepEqual(agoParts(60), [1, "minute"])
  assert.deepEqual(agoParts(3 * MINUTE + 59), [3, "minute"])
  assert.deepEqual(agoParts(HOUR), [1, "hour"])
  assert.deepEqual(agoParts(23 * HOUR), [23, "hour"])
  assert.deepEqual(agoParts(DAY), [1, "day"])
  assert.deepEqual(agoParts(40 * DAY), [1, "month"])
  assert.deepEqual(agoParts(400 * DAY), [1, "year"])
})

test("a clock ahead of the server's still says it was a moment ago", () => {
  assert.deepEqual(agoParts(0), [1, "second"])
  assert.deepEqual(agoParts(-5), [1, "second"])
})

const ago = (seconds, locale) => agoText(new Date(1_000_000_000), locale, 1_000_000_000 + seconds * 1000)

test("spells out a day and more", () => {
  assert.equal(ago(DAY, "en"), "1 day ago")
  assert.equal(ago(2 * DAY, "en"), "2 days ago")
})

test("never leaves a bare minus sign for a language with no narrow words", () => {
  for (const locale of ["fr", "no", "ro", "ru", "sv"]) {
    assert.doesNotMatch(ago(3 * MINUTE, locale), /^[-−]/, locale)
  }
})
