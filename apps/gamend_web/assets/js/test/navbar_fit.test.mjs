// `node --test assets/js/test/*.test.mjs` — no dependencies. Also run by
// `test/gamend_web/js_test.exs`.
//
// `navbar_fit.js`: which stage of the navbar a width holds, from the widths
// each stage measured.
import {test} from "node:test"
import assert from "node:assert/strict"

import {MENU, STAGES, UNMEASURED_BAR, stageFor} from "../navbar_fit.js"

const needs = {full: 1660, icons: 1210, avatar: 1100}
const words = Object.fromEntries(STAGES)

test("a bar wide enough for every word spells the links out", () => {
  assert.equal(stageFor(needs, 1660), words.full)
  assert.equal(stageFor(needs, 2400), words.full)
})

test("the labels go first, then the reader's name, then the bar", () => {
  assert.equal(stageFor(needs, 1659), words.icons)
  assert.equal(stageFor(needs, 1209), words.avatar)
  assert.equal(stageFor(needs, 1099), MENU)
})

test("a stage never brings back what an earlier one dropped", () => {
  const shown = STAGES.map(([, w]) => new Set(w.split(" ")))
  for (let i = 1; i < shown.length; i++) {
    for (const word of shown[i]) assert.ok(shown[i - 1].has(word), word)
    assert.ok(shown[i].size < shown[i - 1].size)
  }
})

test("with nothing measured yet, the bar shows from the xl breakpoint", () => {
  assert.equal(stageFor(null, UNMEASURED_BAR), words.full)
  assert.equal(stageFor(null, UNMEASURED_BAR - 1), MENU)
})
