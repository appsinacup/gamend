// `node --test assets/js/test/*.test.mjs` — no dependencies. Also run by
// `test/gamend_web/js_test.exs`.
//
// `back_link.js`: where the Back button goes — the page the reader came from
// by a click inside the site, else nowhere (its `href`, the page's trail).
import {test} from "node:test"
import assert from "node:assert/strict"

import {backEntry, isAuthPath, pathOf} from "../back_link.js"

const at = (path, lang = "en") => ({key: path, url: "https://site.test" + path, lang})

test("a path is compared without its query, hash or trailing slash", () => {
  assert.equal(pathOf("https://site.test/games/ro?topic=food#x"), "/games/ro")
  assert.equal(pathOf("https://site.test/games/"), "/games")
  assert.equal(pathOf("https://site.test/"), "/")
  assert.equal(pathOf(null), null)
  assert.equal(pathOf(""), null)
})

test("the first page of the tab has nowhere to go back to: the trail", () => {
  assert.equal(backEntry([at("/progress/romanian/games/7")], 0, "en"), null)
})

test("a page reached by a click goes back to the page it came from", () => {
  const entries = [at("/games"), at("/games/romanian/hangman"), at("/progress/romanian/games/7")]
  assert.equal(backEntry(entries, 2, "en").key, "/games/romanian/hangman")
})

test("the same page under another query is walked past", () => {
  const entries = [
    at("/games"),
    at("/games/romanian/hangman"),
    {...at("/games/romanian/hangman?lives=4"), key: "settings"},
    {...at("/games/romanian/hangman?lives=8"), key: "settings2"},
  ]
  assert.equal(backEntry(entries, 3, "en").key, "/games")
})

test("the page before it in the reader's language: taken; in another: the trail", () => {
  const entries = [at("/games", "en"), at("/ro/games", "ro"), at("/ro/games/romanian/hangman", "ro")]
  assert.equal(backEntry(entries, 2, "ro").key, "/ro/games")
  assert.equal(backEntry(entries, 1, "ro"), null)
})

test("an untagged entry is not trusted", () => {
  const entries = [{key: "old", url: "https://site.test/games"}, at("/games/romanian/hangman")]
  assert.equal(backEntry(entries, 1, "en"), null)
})

test("a sign-in page is walked past", () => {
  const entries = [at("/progress"), at("/users/log_in"), at("/classes")]
  assert.equal(backEntry(entries, 2, "en").key, "/progress")
  assert.equal(backEntry([at("/users/register"), at("/classes")], 1, "en"), null)
})

test("only the sign-in pages are sign-in pages", () => {
  assert.equal(isAuthPath("/users/log_in"), true)
  assert.equal(isAuthPath("/users/log_in/abc"), true)
  assert.equal(isAuthPath("/users/register"), true)
  assert.equal(isAuthPath("/users/confirm/abc"), true)
  assert.equal(isAuthPath("/users/settings/confirm_email/abc"), true)
  assert.equal(isAuthPath("/users/settings"), false)
  assert.equal(isAuthPath("/progress"), false)
})

test("a bad index or list is the trail", () => {
  assert.equal(backEntry(null, 1, "en"), null)
  assert.equal(backEntry([at("/a"), at("/b")], 5, "en"), null)
  assert.equal(backEntry([at("/a"), at("/b")], -1, "en"), null)
  assert.equal(backEntry([{key: "x", url: null, lang: "en"}, at("/b")], 1, "en"), null)
})
