// What the navbar has room for, measured rather than guessed from a
// breakpoint (2026-10-21, user): its links spelled out, then as icons, then
// without the reader's name, then the menu. How wide a bar is depends on the
// host's links, the language's words and the reader's name and balance, so
// no width fits every site.
//
// `<html data-nav>` names what shows, and each word is a class's condition
// (`HostLayoutNavigation`): `bar` the links in the bar, `labels` their words,
// `name` the reader's name. Each stage's width is measured once the page is
// drawn and kept per language, so the next page's `theme-init.js` sets the
// stage before its first paint, and a resize only compares numbers.
//
// `"layout": "auto"` (`<html data-side-nav="auto">`, 2026-10-23): the bar
// with every link while one of its stages that spells them out fits the
// window (`AUTO_STAGES`: never a bar of icons, user 2026-10-23); where none
// does, `side` joins the words, and the sidebar shows (the tab bar on a
// phone) with the bar's other entries at the first of the same stages that
// fits beside it (`SIDE_STAGES`), else its menu.

export const STAGES = [
  ["full", "bar labels name"],
  ["icons", "bar name"],
  ["avatar", "bar"],
]

// The auto layout's bar: only the stages with the links' words.
export const AUTO_STAGES = STAGES.filter(([, words]) => words.split(" ").includes("labels"))

export const MENU = "menu"

export const SIDE_STAGES = STAGES.map(([name, words]) => [`side-${name}`, `side ${words}`])

export const SIDE_MENU = `side ${MENU}`

// The bar from this width while nothing is measured: the `xl` breakpoint it
// had before it was measured.
export const UNMEASURED_BAR = 1280

const KEY = "gamend:nav"

// The first stage whose width fits, else the menu. `side` is the auto
// layout's sidebar (`sideRoom/0`): how wide it is where it shows, and
// whether this is a phone, where it is the tab bar and the bar is the menu.
export function stageFor(needs, width, side = null) {
  if (!needs) {
    if (width >= UNMEASURED_BAR) return STAGES[0][1]
    return side ? SIDE_MENU : MENU
  }
  for (const [name, words] of side ? AUTO_STAGES : STAGES) {
    if (needs[name] <= width) return words
  }
  if (!side) return MENU
  if (side.phone) return SIDE_MENU
  for (const [name, words] of SIDE_STAGES) {
    if (needs[name] <= width - side.width) return words
  }
  return SIDE_MENU
}

function auto() {
  return document.documentElement.dataset.sideNav === "auto"
}

// The auto layout's sidebar, or null for another layout: open (14rem,
// `md:w-56`) unless collapsed or on a full-screen page, else the rail (6rem,
// `w-24`), as `side_nav/1` draws it; below `md` the tab bar.
// From the breakpoints rather than its box, which is not drawn while the
// bar fits, and is mid-fold while it opens.
function sideRoom() {
  if (!auto() || typeof matchMedia !== "function") return null
  const root = document.documentElement
  const rem = parseFloat(getComputedStyle(root).fontSize) || 16
  const open = root.dataset.side !== "rail" && !document.getElementById("navbar-autohide")
  return {width: rem * (open ? 14 : 6), phone: !matchMedia("(min-width: 48rem)").matches}
}

// What the stages are compared with: the header's width, or in the auto
// layout the window's, since the header narrows while the sidebar shows.
function roomOf(header) {
  return auto() ? document.documentElement.clientWidth : header.clientWidth
}

function readSaved(lang) {
  try {
    return JSON.parse(localStorage.getItem(KEY) || "{}")[lang] || null
  } catch (_) {
    return null
  }
}

function save(lang, needs) {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) || "{}")
    saved[lang] = needs
    localStorage.setItem(KEY, JSON.stringify(saved))
  } catch (_) {
    // A browser that keeps nothing measures again on every page.
  }
}

// With the sidebar (`<html data-side-nav>`) there is none on a phone, so a
// phone's width is the menu whatever else would fit: the sidebar's links are
// the menu's there.
function sidePhone() {
  const root = document.documentElement
  return (
    root.dataset?.sideNav === "sidebar" &&
    typeof matchMedia === "function" &&
    !matchMedia("(min-width: 48rem)").matches
  )
}

function apply(words) {
  const root = document.documentElement
  if (sidePhone()) words = MENU
  if (root.dataset.nav !== words) root.dataset.nav = words
}

// Before the first paint (`theme-init.js`): the page has no header yet, and
// the root's width is the window's.
export function applySaved() {
  const root = document.documentElement
  apply(stageFor(readSaved(root.lang), root.clientWidth, sideRoom()))
}

// Each stage's width: the header's padding and gap, the logo with its name on
// one line, and the bar. The logo's room is widened while it is measured, so
// the name neither wraps nor turns to screen-reader text (`@max-[8rem]`).
export function measure(header) {
  const logo = header.querySelector("[data-nav-logo]")
  const bar = header.querySelector("[data-nav-bar]")
  if (!logo || !bar) return null

  const root = document.documentElement
  const before = root.dataset.nav
  const room = logo.parentElement
  room.style.flex = "none"
  room.style.width = "100vw"

  // The auto layout's bar also beside the sidebar, its links there.
  const stages = auto() ? STAGES.concat(SIDE_STAGES) : STAGES
  const needs = {}
  for (const [name, words] of stages) {
    root.dataset.nav = words
    const style = getComputedStyle(header)
    const gap = parseFloat(style.columnGap) || 0
    const padding = parseFloat(style.paddingLeft) + parseFloat(style.paddingRight)
    const width = logo.getBoundingClientRect().width + bar.getBoundingClientRect().width
    needs[name] = Math.ceil(padding + gap + width)
  }

  room.style.flex = ""
  room.style.width = ""
  if (before === undefined) delete root.dataset.nav
  else root.dataset.nav = before
  return needs
}

// What the last measure read. A page change draws the same header again, and
// each stage restyles the whole page (`root.dataset.nav`): while its words and
// the fonts are the same, so are its widths.
let last = null

function measured(header) {
  const key = `${document.fonts?.status}|${header.textContent}`
  if (last?.key !== key) last = {key, needs: measure(header)}
  return last.needs
}

const fitted = new WeakMap()

// Measures `header` now, again when its width, its fonts or its content
// change (`refit`, from the navbar's hook), and sets the stage that fits.
export function startNavbarFit(header) {
  if (!header) return null
  if (fitted.has(header)) return fitted.get(header)

  const lang = document.documentElement.lang
  let needs = readSaved(lang)
  let width = null

  const refit = () => {
    needs = measured(header) || needs
    if (needs) save(lang, needs)
    width = roomOf(header)
    apply(stageFor(needs, width, sideRoom()))
  }

  // Only a change of width: a stage that changes the header's height must
  // not measure it again. In the auto layout the window's: the sidebar
  // showing narrows the header and decides nothing. In the next frame, not
  // in this callback: a stage resizes what is observed, and from inside the
  // callback the browser reports that as "ResizeObserver loop completed with
  // undelivered notifications".
  let frame = null
  const observer = new ResizeObserver(() => {
    frame ??= requestAnimationFrame(() => {
      frame = null
      if (roomOf(header) !== width) refit()
    })
  })
  observer.observe(header)
  document.fonts?.ready.then(refit)

  // The sidebar collapsed or opened (`side_nav.js`): the room beside it
  // changed, the widths did not.
  const resided = () => {
    if (width !== null) apply(stageFor(needs, width, sideRoom()))
  }
  document.addEventListener("gamend:side", resided)

  const stop = () => {
    observer.disconnect()
    if (frame !== null) cancelAnimationFrame(frame)
    document.removeEventListener("gamend:side", resided)
    fitted.delete(header)
  }

  const fit = {refit, stop}
  fitted.set(header, fit)
  return fit
}
