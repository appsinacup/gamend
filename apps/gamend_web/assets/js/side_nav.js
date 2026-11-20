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

const wide = () => typeof window === "undefined" || window.innerWidth >= OPEN_FROM

export function applySavedSide(root = document.documentElement) {
  let saved = null
  try {
    saved = localStorage.getItem(KEY)
  } catch (_) {
    // A browser that keeps nothing opens it on every wide page.
  }
  const rail = !wide() || saved === "rail"
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
  // A window resized across `xl`: the rail, or the reader's choice again.
  let wasWide = wide()
  window.addEventListener?.(
    "resize",
    () => {
      if (wide() === wasWide) return
      wasWide = wide()
      if (applySavedSide()) document.dispatchEvent?.(new CustomEvent("gamend:side"))
    },
    {passive: true},
  )
}
