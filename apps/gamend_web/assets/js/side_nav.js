// The sidebar's state (`HostLayoutNavigation.side_nav/1`): `<html
// data-side="rail">` where the reader collapsed it. This browser keeps it, as
// it keeps the theme, and `theme-init.js` sets it again before the next page
// paints, so a page never draws the sidebar open and then folds it.

const KEY = "gamend:side"

// Under `xl` (a tablet, a small laptop) the sidebar is only ever the rail,
// its toggle not drawn: open, it left a page's heading too little room
// (Polyglot Pirates, 2026-11-20: the heading is the bar, the navbar's items
// at its end). From `xl` up the reader's choice stands, open by default.
const OPEN_FROM = 1280

// A host's fixed table instead (`<html data-nav-sizes="0:rail
// 1536:sidebar">`, `HostLayoutNavigation.nav_sizes/1`, 2026-11-25): what the
// navigation is from each window width on. `bar` the top bar's links,
// `rail` the sidebar that never opens, `sidebar` the reader's choice.
export function sizeMode(root = document.documentElement, width = windowWidth()) {
  const table = root?.dataset?.navSizes
  if (!table) return null
  let mode = null
  for (const row of table.split(" ")) {
    const [from, name] = row.split(":")
    if (width >= Number(from)) mode = name
  }
  return mode
}

function windowWidth() {
  return typeof window === "undefined" ? Infinity : window.innerWidth
}

// Whether the reader's choice stands at this width: from `xl`, or where the
// host's table says `sidebar`.
function choosable(root) {
  const mode = sizeMode(root)
  return mode === null ? windowWidth() >= OPEN_FROM : mode === "sidebar"
}

export function applySavedSide(root = document.documentElement) {
  let saved = null
  try {
    saved = localStorage.getItem(KEY)
  } catch (_) {
    // A browser that keeps nothing opens it on every wide page.
  }
  const fixed = !choosable(root)
  // The toggle not drawn where it could do nothing (`side_nav/1`).
  if (sizeMode(root) !== null) {
    if (fixed) root.dataset.sideFixed = ""
    else delete root.dataset.sideFixed
  }
  const rail = fixed || saved === "rail"
  if (rail === (root.dataset.side === "rail")) return false
  if (rail) root.dataset.side = "rail"
  else delete root.dataset.side
  return true
}

export function toggleSide(root = document.documentElement) {
  const rail = root.dataset.side !== "rail"
  if (rail) root.dataset.side = "rail"
  else delete root.dataset.side

  try {
    localStorage.setItem(KEY, rail ? "rail" : "open")
  } catch (_) {
    // Kept for this page only.
  }
  // The auto layout's bar fits again beside it (`navbar_fit.js`).
  document.dispatchEvent?.(new CustomEvent("gamend:side"))
  return rail
}

// On `document`, not on the button: the sidebar is drawn again with the
// page, and a listener bound to its button would go with it.
export function startSideNav() {
  document.addEventListener("click", (event) => {
    if (event.target.closest?.("[data-side-toggle]")) toggleSide()
  })
  // A window resized across `xl`, or into another row of the host's table:
  // the rail, or the reader's choice again.
  const state = () => `${choosable(document.documentElement)}|${sizeMode()}`
  let was = state()
  window.addEventListener?.(
    "resize",
    () => {
      if (state() === was) return
      was = state()
      if (applySavedSide()) document.dispatchEvent?.(new CustomEvent("gamend:side"))
    },
    {passive: true},
  )
}
