// `node --test assets/js/test/*.test.mjs` — no dependencies. Also run by
// `test/gamend_web/js_test.exs`.
//
// `icon_backdrop.js`: which logos get a background of their own, and on which
// theme.
import {test} from "node:test"
import assert from "node:assert/strict"

import {backdropFor} from "../icon_backdrop.js"

const CLEAR = [0, 0, 0, 0]

// `shares`: [[rgba, how many], ...], one pixel after another.
function image(shares) {
  return Uint8ClampedArray.from(shares.flatMap(([rgba, count]) => Array(count).fill(rgba).flat()))
}

test("a dark logo on a clear background gets a light backdrop, on a dark theme only", () => {
  const backdrop = backdropFor(image([[[15, 25, 45, 255], 50], [CLEAR, 50]]))
  assert.match(backdrop, /^light-dark\(transparent, color-mix\(in oklab, rgb\(15 25 45\) 15%, white\)\)$/)
})

test("a white logo on a clear background gets a dark backdrop, on a light theme only", () => {
  const backdrop = backdropFor(image([[[250, 250, 250, 255], 50], [CLEAR, 50]]))
  assert.match(backdrop, /^light-dark\(color-mix\(in oklab, rgb\(250 250 250\) 25%, black\), transparent\)$/)
})

test("a logo that reads on both themes is left alone", () => {
  assert.equal(backdropFor(image([[[200, 90, 40, 255], 50], [CLEAR, 50]])), null)
})

test("a dark logo with a bright accent counts as dark", () => {
  const backdrop = backdropFor(
    image([[[10, 15, 30, 255], 40], [[120, 190, 255, 255], 10], [CLEAR, 50]])
  )
  assert.match(backdrop, /, white\)\)$/)
})

test("an opaque image shows no background, so it gets none", () => {
  assert.equal(backdropFor(image([[[10, 10, 10, 255], 100]])), null)
})

test("a rounded square's clear corners are no reason for one", () => {
  assert.equal(backdropFor(image([[[10, 10, 10, 255], 95], [CLEAR, 5]])), null)
})

test("an image with nothing visible gets none", () => {
  assert.equal(backdropFor(image([[CLEAR, 100]])), null)
})
