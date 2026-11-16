// Timestamps are stored and sent as UTC; the reader's clock is whatever their
// browser says it is. The server renders `<time datetime="…Z">` with UTC text
// inside, and this rewrites that text in the viewer's zone and locale. No
// timezone database on the server, no stored user preference, and DST is the
// browser's problem — which it already solves correctly.
//
// Without JS the page still shows the server's text, which is why that text is
// labelled UTC rather than left bare.

const FORMATS = {
  datetime: {dateStyle: "medium", timeStyle: "short"},
  date: {dateStyle: "medium"},
  time: {timeStyle: "short"},
  full: {dateStyle: "medium", timeStyle: "medium"},
  // A calendar date or month (a blog post's publication day) is not an instant.
  // Pinned to UTC so it is only *translated*, never shifted: in the reader's own
  // zone "2026-09-16" would print as the 15th anywhere west of Greenwich. The
  // server used to skip these entirely to avoid that shift, which left every
  // date on the site in English.
  "calendar-date": {dateStyle: "medium", timeZone: "UTC"},
  "calendar-month": {month: "long", timeZone: "UTC"},
}

// "7m ago", "in 12 days": not a format of the instant but of its distance from
// now, so it is said again as time passes (`startLocalTime`).
const RELATIVE = "relative"
const TICK_MS = 1_000
// A relative time is re-said every 10 ticks; one less than a minute ahead
// (a deadline counting down) and a running duration every tick.
const SLOW_TICKS = 10
const FAST_WITHIN_S = 60

// Marks what a node was last rendered from, so re-running over a page that has
// not changed is free and cannot loop against the MutationObserver below.
const RENDERED = "localTimeRendered"
// Set by a tap: the stamp shows its exact moment instead of the distance.
const EXACT = "localTimeExact"

const STAMPS = "time[data-local-time]"
const DURATIONS = "time[data-local-duration]"

const MINUTE = 60
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR
const WEEK = 7 * DAY
const MONTH = 30 * DAY
const YEAR = 365 * DAY

function pageLocale() {
  const lang = document.documentElement.getAttribute("lang")
  return lang && lang.trim() !== "" ? lang : undefined
}

// Building an Intl formatter costs far more than using one, and a page of
// stamps re-says itself every second.
const formatters = new Map()

function cached(kind, locale, options, build) {
  const key = `${kind}|${locale || ""}|${JSON.stringify(options)}`
  if (!formatters.has(key)) formatters.set(key, build())
  return formatters.get(key)
}

const relativeFormat = (locale, style) =>
  cached("relative", locale, style, () => new Intl.RelativeTimeFormat(locale, {style, numeric: "always"}))

// The distance in the largest unit that fits, one unit only: [3, "minute"],
// [1, "week"]. Counted as `GamendWeb.TimeText.parts/1` counts for the first
// paint. The sign is ignored, and it is never under a second.
export function relativeParts(seconds) {
  const s = Math.max(1, Math.floor(Math.abs(seconds)))
  if (s < MINUTE) return [s, "second"]
  if (s < HOUR) return [Math.floor(s / MINUTE), "minute"]
  if (s < DAY) return [Math.floor(s / HOUR), "hour"]
  if (s < WEEK) return [Math.floor(s / DAY), "day"]
  if (s < MONTH) return [Math.floor(s / WEEK), "week"]
  // 360 to 364 days would floor to "12 months": still under a year.
  if (s < YEAR) return [Math.min(Math.floor(s / MONTH), 11), "month"]
  return [Math.floor(s / YEAR), "year"]
}

// "7m ago" / "in 7m", terse up to the hour; "12 days ago" / "in 3 weeks" from a
// day. The words are the browser's, so all the site's languages come for free.
// `past`: the server saw the instant behind it, so a slow clock here still
// says it happened rather than that it will.
export function relativeText(date, locale, now = Date.now(), {past = false} = {}) {
  const diff = (date.getTime() - now) / 1000
  const future = diff >= 1 && !past
  const [value, unit] = relativeParts(diff)
  const say = style => relativeFormat(locale, style).format(future ? value : -value, unit)

  if (!["second", "minute", "hour"].includes(unit)) return say("long")

  // French, Russian, Swedish and others make the narrow form a bare "-3 min"
  // (or "+3 min" ahead).
  const narrow = say("narrow")
  return /^[-−+]/.test(narrow) ? say("short") : narrow
}

// A span in its largest unit and the one under it, the smaller left out when it
// is zero: [[9, "minutes"], [1, "seconds"]]. `GamendWeb.TimeText.duration_parts/2`
// counts the same way.
export function durationParts(seconds, units = 2) {
  const s = Math.max(0, Math.floor(seconds))
  const all = [
    [Math.floor(s / DAY), "days"],
    [Math.floor((s % DAY) / HOUR), "hours"],
    [Math.floor((s % HOUR) / MINUTE), "minutes"],
    [s % MINUTE, "seconds"],
  ]
  const first = all.findIndex(([count]) => count > 0)
  if (first === -1) return [[0, "seconds"]]

  return [all[first], ...all.slice(first + 1, first + units).filter(([count]) => count > 0)]
}

const LETTERS = {days: "d", hours: "h", minutes: "m", seconds: "s"}

// "9m 1s" in the reader's language where the browser can say it, the server's
// English letters where it cannot.
export function durationText(seconds, locale, units = 2) {
  const parts = durationParts(seconds, units)
  const english = parts.map(([count, unit]) => `${count}${LETTERS[unit]}`).join(" ")

  try {
    // `Intl.DurationFormat` says nothing at all for a zero-length span.
    if (parts[0][0] === 0) {
      return cached("zero", locale, "", () =>
        new Intl.NumberFormat(locale, {style: "unit", unit: "second", unitDisplay: "narrow"}),
      ).format(0)
    }
    if (typeof Intl.DurationFormat !== "function") return english

    const format = cached("duration", locale, "", () => new Intl.DurationFormat(locale, {style: "narrow"}))
    return format.format(Object.fromEntries(parts.map(([count, unit]) => [unit, count]))) || english
  } catch (_e) {
    return english
  }
}

function parseInstant(iso) {
  // `2026-09` is a valid HTML month string but not every engine parses it as a
  // date; anchoring it to the first keeps it on the calendar-month path.
  const date = new Date(/^\d{4}-\d{2}$/.test(iso) ? `${iso}-01` : iso)
  return isNaN(date.getTime()) ? null : date
}

function setText(el, text) {
  // A relative time or a running span comes through here on every tick;
  // rewriting the same words would only wake the observer.
  if (el.textContent !== text) el.textContent = text
}

function localize(el, now = Date.now()) {
  const iso = el.getAttribute("datetime")
  const format = el.dataset.localTime
  if (!iso || !format) return

  const stamp = `${iso}|${format}`
  if (format !== RELATIVE && el.dataset[RENDERED] === stamp) return

  const date = parseInstant(iso)
  if (!date) return

  try {
    const locale = pageLocale()

    if (format === RELATIVE) {
      const exact = date.toLocaleString(locale, FORMATS.full)
      const past = el.hasAttribute("data-local-time-past")
      setText(el, el.dataset[EXACT] ? exact : relativeText(date, locale, now, {past}))
      if (el.title !== exact) el.title = exact
    } else {
      setText(el, date.toLocaleString(locale, FORMATS[format] || FORMATS.datetime))
    }

    el.dataset[RENDERED] = stamp
  } catch (_e) {
    // Leave the server's UTC text in place rather than showing nothing.
  }
}

function localizeDuration(el, now = Date.now()) {
  const from = el.dataset.localDurationFrom
  const start = from && parseInstant(from)
  const seconds = start ? (now - start.getTime()) / 1000 : Number(el.dataset.localDuration)
  if (!Number.isFinite(seconds)) return

  const units = Number(el.dataset.localDurationUnits) || 2
  const stamp = `${seconds}|${units}`
  if (!start && el.dataset[RENDERED] === stamp) return

  setText(el, durationText(seconds, pageLocale(), units))
  el.dataset[RENDERED] = stamp
}

export function localizeTimes(root = document) {
  const scope = root instanceof Element || root instanceof Document ? root : document
  if (scope instanceof Element && scope.matches(STAMPS)) localize(scope)
  if (scope instanceof Element && scope.matches(DURATIONS)) localizeDuration(scope)
  scope.querySelectorAll(STAMPS).forEach(el => localize(el))
  scope.querySelectorAll(DURATIONS).forEach(el => localizeDuration(el))
}

// Whether a relative stamp is re-said on this tick: every tick while it is a
// deadline under a minute away, every tenth otherwise.
export function dueThisTick(el, tick, now = Date.now()) {
  if (tick % SLOW_TICKS === 0) return true
  if (el.hasAttribute("data-local-time-past")) return false

  const date = parseInstant(el.getAttribute("datetime") || "")
  if (!date) return false
  const ahead = (date.getTime() - now) / 1000
  return ahead > -SLOW_TICKS && ahead < FAST_WITHIN_S
}

// A tap on a relative stamp swaps in its exact moment, and back: a phone has
// no hover to show the title. Not inside a link or a control, where the tap
// already means something else.
export function toggleExact(el) {
  if (el.closest("a, button, label, summary, [phx-click]")) return false

  if (el.dataset[EXACT]) delete el.dataset[EXACT]
  else el.dataset[EXACT] = "1"

  localize(el)
  return true
}

// LiveView patches nodes in without firing navigation events, and static pages
// never fire them at all, so observing the document covers every case with one
// mechanism. Re-localizing a patched node is what the RENDERED guard makes cheap.
export function startLocalTime() {
  localizeTimes()

  const observer = new MutationObserver(mutations => {
    for (const mutation of mutations) {
      if (mutation.type === "childList") {
        mutation.addedNodes.forEach(node => {
          if (node.nodeType === Node.ELEMENT_NODE) localizeTimes(node)
        })
      } else if (mutation.target.parentElement) {
        localizeTimes(mutation.target.parentElement)
      }
    }
  })

  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
    characterData: true,
  })

  window.addEventListener("phx:page-loading-stop", () => localizeTimes())

  document.addEventListener("click", event => {
    const el = event.target instanceof Element && event.target.closest(`time[data-local-time="${RELATIVE}"]`)
    if (el) toggleExact(el)
  })

  let tick = 0
  setInterval(() => {
    tick += 1
    const now = Date.now()

    document.querySelectorAll(`time[data-local-time="${RELATIVE}"]`).forEach(el => {
      if (dueThisTick(el, tick, now)) localize(el, now)
    })
    document.querySelectorAll("time[data-local-duration-from]").forEach(el => localizeDuration(el, now))
  }, TICK_MS)
}

// Pairs a hidden UTC field (what the form casts) with a visible datetime-local
// input in the viewer's clock. Conversion runs against the *entered* date, so a
// value months away lands on the right side of a DST change — which is exactly
// what a single offset collected at page load would get wrong.
export const LocalDatetimeInput = {
  mounted() {
    this.hidden = this.el.querySelector("input[type=hidden]")
    this.visible = this.el.querySelector("input[data-local-mirror-for]")
    if (!this.hidden || !this.visible) return

    this.visible.addEventListener("input", () => this.pushUtc())
    this.visible.addEventListener("change", () => this.pushUtc())
    this.showLocal()
    this.showZone()
  },

  updated() {
    this.showLocal()
  },

  // UTC -> the local wall time the field should display.
  showLocal() {
    const utc = this.hidden.value
    if (!utc) {
      this.visible.value = ""
      return
    }

    const date = new Date(utc.endsWith("Z") || utc.includes("+") ? utc : `${utc}Z`)
    if (isNaN(date.getTime())) return

    const pad = n => String(n).padStart(2, "0")
    const local =
      `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
      `T${pad(date.getHours())}:${pad(date.getMinutes())}`

    if (this.visible.value !== local) this.visible.value = local
  },

  // The local wall time entered -> the UTC instant the server stores.
  pushUtc() {
    const local = this.visible.value
    const next = local ? new Date(local).toISOString().replace(/\.\d{3}Z$/, "Z") : ""
    if (this.hidden.value === next) return

    this.hidden.value = next
    // LiveView tracks the named field, so the change has to come from it.
    this.hidden.dispatchEvent(new Event("input", {bubbles: true}))
  },

  showZone() {
    const note = this.el.querySelector("[data-local-zone-note]")
    if (!note) return

    try {
      const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (zone) note.textContent = `Your time (${zone}); stored as UTC`
    } catch (_e) {
      // A browser that cannot name its zone still converts correctly.
    }
  },
}
