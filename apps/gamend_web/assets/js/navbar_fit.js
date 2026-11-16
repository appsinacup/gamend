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
// A measure is dear: each stage is set on the root to be read, and that
// restyles the page (a thousand elements a stage on a long one; three
// measures on a first visit were half a second of a phone's main thread,
// 2026-11-14). So the widths are kept with what they were read for (`for`:
// the header's words and layout; `fonts`: read with the page's fonts in),
// and the next page reads them back instead of measuring; only the stages
// the layout can show are measured; and a phone in a layout with a sidebar
// measures nothing, its answer being the menu whatever would fit. A window
// resized compares its width with the numbers kept: nothing is read again.
// They are read again when the header's words or its stylesheets change
// (`headerKey/1`), and once a day for what neither says (`KEPT_FOR_MS`).
//
// The widths cannot come from the server: a site on the system's fonts
// (San Francisco, Segoe UI, Roboto) is a different width on each, so each
// browser reads its own, once.
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
  const needs = readSaved(root.lang)
  apply(stageFor(needs, root.clientWidth, sideRoom()))
  // Nothing measured: the shell waits unseen for `fitWhenStyled/0`, since a
  // guess painted is a shift. From `md` up only: narrower, no stage moves the
  // page (the sidebar is the tab bar there), and the title would wait for
  // nothing.
  if (!needs && wide()) root.dataset.navFit = "pending"
}

function wide() {
  return typeof matchMedia === "function" && matchMedia("(min-width: 48rem)").matches
}

// A first visit (`applySaved/0`'s hold) measures the header as soon as it is
// parsed and the stylesheets are in, whichever comes last, and is drawn once
// at the stage that fits. Before this it was drawn at a guess (the bar from
// 1280px) that the deferred `app.js` corrected: in the auto layout the
// sidebar's room then slid the whole page 224px sideways, a layout shift of
// 0.8 on a desktop (2026-11-12). Watched from the head, never blocking the
// parser: a script after the header that waited for the stylesheet left the
// rest of the page to be parsed after it, the title ~100 ms after the header.
export function fitWhenStyled() {
  const root = document.documentElement
  if (root.dataset.navFit !== "pending" || typeof MutationObserver !== "function") return

  const check = () => {
    const header = document.getElementById("main-navbar")
    // The header is whole once anything after it is parsed.
    if (!header?.nextElementSibling || !styled()) return
    stop()
    fitNow(header)
  }
  const done = () => {
    // A page with no navbar: nothing to fit.
    if (!document.getElementById("main-navbar")) {
      stop()
      reveal()
    }
  }
  const observer = new MutationObserver(check)
  const stop = () => {
    observer.disconnect()
    document.removeEventListener("load", check, true)
    document.removeEventListener("DOMContentLoaded", done)
  }
  observer.observe(root, {childList: true, subtree: true})
  // A stylesheet's `load` reaches a capturing listener on the document.
  document.addEventListener("load", check, true)
  document.addEventListener("DOMContentLoaded", done)
}

function styled() {
  return Array.from(document.querySelectorAll('link[rel="stylesheet"]')).every((link) => link.sheet)
}

// Measures `header`, keeps the widths and sets the stage, the shell's margin
// transition held so the stage arrives still, then shows the shell.
function fitNow(header) {
  const lang = document.documentElement.lang
  const shell = header.parentElement
  const transition = shell.style.transition
  shell.style.transition = "none"
  // The room first, with the page as it will be drawn: its scrollbar is part
  // of the window's width, and the lock below takes the page's height.
  const room = roomOf(header)
  // The page under the header is no part of the reading, and every stage
  // read restyles and lays out all there is: a long page, whole, six times
  // before its first paint. Locked (`content-visibility`), it is skipped;
  // nothing is drawn, focused or scrolled yet, so nothing is lost by it.
  const unlock = lockPage()
  // Before the fonts are in: good until they are (`measured/2`).
  const needs = tagged(measure(header), header, false)
  if (needs) {
    save(lang, needs)
    apply(stageFor(needs, room, sideRoom()))
  }
  // The stage's margin, read now, is where a transition would start from.
  void shell.offsetWidth
  shell.style.transition = transition
  unlock()
  reveal()
}

// The page's content (`#main-content`) left out of style and layout until
// the function it answers is called. Only before the first paint: a locked
// box has no height and cannot hold the focus.
function lockPage() {
  const page = document.getElementById("main-content")
  if (!page) return () => {}
  const before = page.style.contentVisibility
  page.style.contentVisibility = "hidden"
  return () => {
    page.style.contentVisibility = before
    if (!page.getAttribute("style")) page.removeAttribute("style")
  }
}

// The shell shown again (`applySaved/0`'s hold): by the fit, else by
// `startNavbarFit/1`, else by the stylesheet after two seconds.
function reveal() {
  delete document.documentElement.dataset.navFit
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

  // The auto layout's bar also beside the sidebar, its links there; never
  // a bar of icons, so those stages are not read.
  const stages = auto() ? AUTO_STAGES.concat(SIDE_STAGES) : STAGES
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

// What a measure is good for: this layout's stages, for a header with these
// words. Only the parts that are measured, the logo and the bar: the header
// also holds the page's breadcrumb, which differs on every page and changes
// no width read here. Short, since it is kept with the widths.
function headerKey(header) {
  const parts = ["[data-nav-logo]", "[data-nav-bar]"].map((part) => header.querySelector(part))
  // Its words, not its white space: a page LiveView has patched keeps other
  // gaps between its tags than the same page as it was sent. Nor its
  // numbers, only how many digits they have (2026-11-16): a coin earned, a
  // level or a count of quests changed the key, and every reward cost the
  // next page a measure. A number a digit longer is a new width, and still
  // measures.
  const words = parts.map((part) =>
    (part?.textContent ?? "").replace(/\s+/g, " ").replace(/\p{Nd}/gu, "0").trim(),
  )
  // And the stylesheets it is drawn with, by their addresses, which carry
  // their versions: a release that moves a padding or a gap changes every
  // width with no word changed, and the widths kept before it are not these.
  const sheets = Array.from(document.querySelectorAll('link[rel="stylesheet"]'), (link) => link.getAttribute("href"))
  const text = words.concat(sheets).join("|")
  let hash = 2166136261
  for (let i = 0; i < text.length; i++) hash = Math.imul(hash ^ text.charCodeAt(i), 16777619)
  return `${auto() ? "auto" : "bar"}:${(hash >>> 0).toString(36)}`
}

// A measure's widths with what they were read for.
function tagged(needs, header, fonts) {
  return needs && {...needs, for: headerKey(header), fonts, at: Date.now()}
}

// How long kept widths stand with nothing said to have changed. What the
// key cannot see (a reader's text size, a font their system replaced) moves
// them too, so they are read again once a day: one measure, on one page.
const KEPT_FOR_MS = 24 * 60 * 60 * 1000

function fresh(saved) {
  return typeof saved?.at === "number" && Date.now() - saved.at < KEPT_FOR_MS
}

// Whether this page's fonts are in (`document.fonts.ready`, set by
// `startNavbarFit/1`). Not `document.fonts.status`, which says "loaded"
// before the first font is asked for.
let fontsIn = typeof document === "undefined" || !document.fonts

// Whether a font the page declares (`@font-face`) was fetched and is in use.
function webFonts() {
  return !!document.fonts && Array.from(document.fonts).some((face) => face.status === "loaded")
}

// What the last measure read. A page change draws the same header again, and
// each stage restyles the whole page (`root.dataset.nav`): while its words and
// the fonts are the same, so are its widths.
let last = null

// The header's widths: the ones kept (`saved`) while they stand, else a
// measure. They stand for the same header read with its fonts in; and while
// this page's fonts are still coming, whatever is kept stands until they
// are, so a page measures once, with the fonts it will be read in.
function measured(header, saved) {
  const key = headerKey(header)
  const stands = saved?.for === key && fresh(saved)
  if (stands && saved.fonts) return saved
  if (saved && !fontsIn) return saved
  // The fonts are in and none was fetched: the page is drawn in the
  // system's, as it was when these were read, so they stand. A site with no
  // web font measures once a browser a day, the first time before its paint.
  if (stands && !webFonts()) return {...saved, fonts: true}
  if (last?.key !== key || last.fonts !== fontsIn) {
    last = {key, fonts: fontsIn, needs: tagged(measure(header), header, fontsIn)}
  }
  return last.needs
}

const fitted = new WeakMap()

// Measures `header` now, again when its width, its fonts or its content
// change (`refit`, from the navbar's hook), and sets the stage that fits.
export function startNavbarFit(header) {
  reveal()
  if (!header) return null
  if (fitted.has(header)) return fitted.get(header)

  const lang = document.documentElement.lang
  let needs = readSaved(lang)
  let width = null

  const refit = () => {
    width = roomOf(header)
    const side = sideRoom()
    // A phone in a layout with a sidebar is the menu whatever would fit
    // (the sidebar is its tab bar): nothing to measure. A window widened
    // later comes back here and measures then.
    if (!(side?.phone || sidePhone())) {
      const read = measured(header, needs)
      if (read && read !== needs) save(lang, read)
      needs = read || needs
    }
    apply(stageFor(needs, width, side))
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
  document.fonts?.ready.then(() => {
    fontsIn = true
    refit()
  })

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
