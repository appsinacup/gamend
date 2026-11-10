// `node --test assets/js/test/*.test.mjs` — no dependencies. Also run by
// `test/gamend_web/js_test.exs`.
//
// `unsaved_changes.js`: which clicks leave a form that is not saved.
import {test} from "node:test"
import assert from "node:assert/strict"

import {leavingElement} from "../unsaved_changes.js"

const here = {href: "https://example.test/users/settings?tab=account", pathname: "/users/settings", search: "?tab=account"}

function element(attrs) {
  const node = {
    hasAttribute: (name) => name in attrs,
    getAttribute: (name) => (name in attrs ? attrs[name] : null),
  }
  node.closest = () => node
  return node
}

test("a link to another page leaves", () => {
  const link = element({href: "/users/groups"})
  assert.equal(leavingElement(link, here), link)
})

test("a live link leaves, the settings tabs included", () => {
  const link = element({href: "/users/settings?tab=groups", "data-phx-link": "patch"})
  assert.equal(leavingElement(link, here), link)
})

test("a button marked leaves", () => {
  const button = element({"data-leaves-form": ""})
  assert.equal(leavingElement(button, here), button)
})

test("what stays on the page does not", () => {
  assert.equal(leavingElement(element({href: "#"}), here), null)
  assert.equal(leavingElement(element({href: "#section"}), here), null)
  assert.equal(leavingElement(element({href: "/users/settings?tab=account#x"}), here), null)
})

test("what opens elsewhere does not", () => {
  assert.equal(leavingElement(element({href: "/guide", target: "_blank"}), here), null)
  assert.equal(leavingElement(element({href: "/file.zip", download: ""}), here), null)
  assert.equal(leavingElement(element({href: "mailto:a@example.test"}), here), null)
  assert.equal(leavingElement(element({href: "tel:123"}), here), null)
})

test("a click on nothing that leaves does not", () => {
  const nothing = {closest: () => null}
  assert.equal(leavingElement(nothing, here), null)
  assert.equal(leavingElement(null, here), null)
})
