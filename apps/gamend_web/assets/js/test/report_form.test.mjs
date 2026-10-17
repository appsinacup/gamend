// `node --test assets/js/test/*.test.mjs` — no dependencies. Also run by
// `test/gamend_web/js_test.exs`.
//
// `report_form.js`: which paths are the report page itself (never remembered
// as "the page you came from"), and how far a screenshot is shrunk.
import {test} from "node:test"
import assert from "node:assert/strict"

import {fitSize, isReportPath, shrink} from "../report_form.js"

test("the report page, with or without a locale prefix, is the report page", () => {
  assert.equal(isReportPath("/report"), true)
  assert.equal(isReportPath("/report/"), true)
  assert.equal(isReportPath("/ro/report"), true)
  assert.equal(isReportPath("/pt-BR/report"), true)
  assert.equal(isReportPath("/zh_TW/report"), true)
})

test("any other page is a page worth remembering", () => {
  assert.equal(isReportPath("/"), false)
  assert.equal(isReportPath("/reports"), false)
  assert.equal(isReportPath("/games/report"), false)
  assert.equal(isReportPath("/admin/reports"), false)
  assert.equal(isReportPath(""), false)
  assert.equal(isReportPath(undefined), false)
})

test("a small image keeps its size", () => {
  assert.deepEqual(fitSize(800, 600), {width: 800, height: 600})
})

test("a wide image is cut down to the width cap, keeping its shape", () => {
  assert.deepEqual(fitSize(3200, 1800), {width: 1600, height: 900})
})

test("a tall phone screenshot keeps its width and is capped in height", () => {
  assert.deepEqual(fitSize(1170, 2532), {width: 1170, height: 2532})
  assert.deepEqual(fitSize(1000, 8000), {width: 500, height: 4000})
})

test("a file that is not an image is dropped", async () => {
  assert.equal(await shrink({type: "text/plain"}), null)
  assert.equal(await shrink(null), null)
})

test("with no canvas support the image is sent as it is", async () => {
  const file = {type: "image/png"}
  assert.equal(await shrink(file), file)
})
