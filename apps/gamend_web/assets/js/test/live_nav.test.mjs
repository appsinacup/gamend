// `node --test assets/js/test/*.test.mjs` — no dependencies. Also run by
// `test/gamend_web/js_test.exs`.
//
// `live_nav.js`: which plain links may move over the open socket. The router
// matches in order, so a controller route declared first shadows a LiveView
// pattern it overlaps; a locale switch and another live_session reload.
import {test} from "node:test"
import assert from "node:assert/strict"

import {compileTable, liveTarget, matches, plainLink} from "../live_nav.js"

const table = compileTable({
  prefixes: ["ro", "pt-BR"],
  routes: [
    ["/tests/download", null, false],
    ["/tests/:target", "current_user", true],
    ["/games/:lang", null, false],
    ["/games/:lang/hangman", "current_user", true],
    ["/users/settings", "require_authenticated_user", true],
    ["/guide/:slug", "current_user", false],
    ["/*path", null, false],
  ],
})

const origin = "https://example.test"
const go = (from, to, session = "current_user") =>
  liveTarget(table, session, from, new URL(to, origin + from), origin)

test("a LiveView page of the same session moves over the socket", () => {
  assert.equal(go("/tests/spanish", "/games/spanish/hangman"), true)
  assert.equal(go("/games/spanish/hangman", "/tests/french?unit_id=3"), true)
})

test("a controller route, also one declared before a LiveView pattern, loads", () => {
  assert.equal(go("/tests/spanish", "/games/spanish"), false)
  assert.equal(go("/tests/spanish", "/tests/download"), false)
  assert.equal(go("/tests/spanish", "/about"), false)
})

test("another live_session and another origin load", () => {
  assert.equal(go("/tests/spanish", "/users/settings"), false)
  assert.equal(liveTarget(table, "current_user", "/tests/x", new URL("https://elsewhere.test/tests/y"), origin), false)
})

test("a locale prefix must stay the same, and the route must have a locale copy", () => {
  assert.equal(go("/ro/tests/spanish", "/ro/games/spanish/hangman"), true)
  assert.equal(go("/tests/spanish", "/ro/games/spanish/hangman"), false)
  assert.equal(go("/ro/tests/spanish", "/games/spanish/hangman"), false)
  assert.equal(go("/ro/tests/spanish", "/ro/guide/hangman"), false)
})

test("segments match the way the router matches them", () => {
  assert.equal(matches(["tests", ":target"], ["tests", "spanish"]), true)
  assert.equal(matches(["tests", ":target"], ["tests"]), false)
  assert.equal(matches(["tests", ":target"], ["tests", "a", "b"]), false)
  assert.equal(matches(["*path"], ["anything", "at", "all"]), true)
  assert.equal(matches(["guide", "x y"], ["guide", "x%20y"]), true)
})

const link = (attrs) => {
  const el = {
    getAttribute: (name) => (name in attrs ? attrs[name] : null),
    hasAttribute: (name) => name in attrs,
  }
  el.closest = (selector) => (selector === "a[href]" && "href" in attrs ? el : null)
  return el
}

test("only a plain same-tab link is taken over", () => {
  assert.ok(plainLink(link({href: "/tests/spanish"})))
  assert.equal(plainLink(link({href: "/x", "data-phx-link": "redirect"})), null)
  assert.equal(plainLink(link({href: "/x", download: ""})), null)
  assert.equal(plainLink(link({href: "/x", target: "_blank"})), null)
  assert.equal(plainLink(link({href: "/x", "data-no-live-nav": ""})), null)
  assert.equal(plainLink(link({href: "#top"})), null)
  assert.equal(plainLink(link({href: "mailto:a@b.c"})), null)
})
