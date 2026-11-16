// `node --test assets/js/test/*.test.mjs` — no dependencies. Also run by
// `test/gamend_web/js_test.exs`.
//
// `local_time.js`: how far from now a relative `<.timestamp>` says something
// is, and how long a `<.duration>` says it lasted.
import {test} from "node:test"
import assert from "node:assert/strict"

import {
  dueThisTick,
  durationParts,
  durationText,
  relativeParts,
  relativeText,
  toggleExact,
} from "../local_time.js"

const MINUTE = 60
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

test("picks the largest unit that fits, one unit only", () => {
  assert.deepEqual(relativeParts(3), [3, "second"])
  assert.deepEqual(relativeParts(59), [59, "second"])
  assert.deepEqual(relativeParts(60), [1, "minute"])
  assert.deepEqual(relativeParts(3 * MINUTE + 59), [3, "minute"])
  assert.deepEqual(relativeParts(HOUR), [1, "hour"])
  assert.deepEqual(relativeParts(23 * HOUR), [23, "hour"])
  assert.deepEqual(relativeParts(DAY), [1, "day"])
  assert.deepEqual(relativeParts(6 * DAY), [6, "day"])
  assert.deepEqual(relativeParts(7 * DAY), [1, "week"])
  assert.deepEqual(relativeParts(13 * DAY), [1, "week"])
  assert.deepEqual(relativeParts(29 * DAY), [4, "week"])
  assert.deepEqual(relativeParts(30 * DAY), [1, "month"])
  assert.deepEqual(relativeParts(40 * DAY), [1, "month"])
  assert.deepEqual(relativeParts(362 * DAY), [11, "month"])
  assert.deepEqual(relativeParts(400 * DAY), [1, "year"])
})

test("ignores the sign and never says less than a second", () => {
  assert.deepEqual(relativeParts(-3 * MINUTE), [3, "minute"])
  assert.deepEqual(relativeParts(0), [1, "second"])
})

const NOW = 1_000_000_000_000
const at = (seconds, locale, opts) => relativeText(new Date(NOW + seconds * 1000), locale, NOW, opts)

test("says a past instant as ago and a future one as in", () => {
  assert.equal(at(-3 * MINUTE, "en"), "3m ago")
  assert.equal(at(3 * MINUTE, "en"), "in 3m")
  assert.equal(at(-DAY, "en"), "1 day ago")
  assert.equal(at(12 * DAY, "en"), "in 1 week")
  assert.equal(at(-2 * DAY, "en"), "2 days ago")
  assert.equal(at(-40 * DAY, "en"), "1 month ago")
})

test("a time the server saw in the past stays in the past on a slow clock", () => {
  assert.equal(at(120, "en", {past: true}), "2m ago")
  assert.equal(at(0, "en"), "1s ago")
})

test("never leaves a bare sign for a language with no narrow words", () => {
  for (const locale of ["fr", "no", "ro", "ru", "sv"]) {
    assert.doesNotMatch(at(-3 * MINUTE, locale), /^[-−+]/, locale)
    assert.doesNotMatch(at(3 * MINUTE, locale), /^[-−+]/, locale)
  }
})

test("other languages get their own words both ways", () => {
  assert.equal(at(12 * DAY, "de"), "in 1 Woche")
  assert.match(at(5 * DAY, "fr"), /^dans 5 jours$/)
  assert.match(at(-3 * HOUR, "ja"), /3.*前/)
})

test("a span keeps its largest unit and the one under it", () => {
  assert.deepEqual(durationParts(45), [[45, "seconds"]])
  assert.deepEqual(durationParts(541), [[9, "minutes"], [1, "seconds"]])
  assert.deepEqual(durationParts(3 * HOUR + 5 * MINUTE + 9), [[3, "hours"], [5, "minutes"]])
  assert.deepEqual(durationParts(2 * DAY + 5 * MINUTE), [[2, "days"]])
  assert.deepEqual(durationParts(541, 1), [[9, "minutes"]])
  assert.deepEqual(durationParts(0), [[0, "seconds"]])
})

test("says a span in the reader's language", () => {
  assert.equal(durationText(541, "en"), "9m 1s")
  assert.equal(durationText(0, "en"), "0s")
  assert.equal(durationText(2 * DAY + 3 * HOUR, "en"), "2d 3h")
})

const stamp = (attrs = {}, closest = null) => ({
  dataset: {localTime: "relative"},
  title: "",
  textContent: "",
  getAttribute: name => attrs[name] ?? null,
  hasAttribute: name => name in attrs,
  closest: () => closest,
})

test("a deadline under a minute away is re-said every tick, anything else every tenth", () => {
  const soon = stamp({datetime: new Date(NOW + 30_000).toISOString()})
  const later = stamp({datetime: new Date(NOW + 2 * HOUR * 1000).toISOString()})
  const past = stamp({datetime: new Date(NOW - 5_000).toISOString(), "data-local-time-past": ""})

  assert.equal(dueThisTick(soon, 3, NOW), true)
  assert.equal(dueThisTick(later, 3, NOW), false)
  assert.equal(dueThisTick(past, 3, NOW), false)
  assert.equal(dueThisTick(later, 10, NOW), true)
})

test("a tap swaps the exact moment in and back, but not inside a link", () => {
  globalThis.document = {documentElement: {getAttribute: () => "en"}}
  const iso = new Date(Date.now() - 3 * DAY * 1000).toISOString()

  const el = stamp({datetime: iso, "data-local-time-past": ""})
  assert.equal(toggleExact(el), true)
  assert.equal(el.textContent, el.title)
  assert.equal(toggleExact(el), true)
  assert.equal(el.textContent, "3 days ago")

  const linked = stamp({datetime: iso}, {tagName: "A"})
  assert.equal(toggleExact(linked), false)
  assert.equal(linked.textContent, "")
})
