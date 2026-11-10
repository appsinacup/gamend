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

// "3m ago": not a format of the instant but of its distance from now, so it is
// said again as time passes (`startLocalTime`).
const RELATIVE = "relative"
const RELATIVE_TICK_MS = 10_000

// Marks what a node was last rendered from, so re-running over a page that has
// not changed is free and cannot loop against the MutationObserver below.
const RENDERED = "localTimeRendered"

function pageLocale() {
  const lang = document.documentElement.getAttribute("lang")
  return lang && lang.trim() !== "" ? lang : undefined
}

// How long ago, in the largest unit that fits: [3, "minute"]. Counted as the
// server counts for its first paint (`timestamp/1`). Never under a second: a
// clock a little ahead of the server's would otherwise say "in 2s".
export function agoParts(seconds) {
  const s = Math.max(1, Math.floor(seconds))
  if (s < 60) return [s, "second"]
  if (s < 3600) return [Math.floor(s / 60), "minute"]
  if (s < 86400) return [Math.floor(s / 3600), "hour"]
  if (s < 2592000) return [Math.floor(s / 86400), "day"]
  if (s < 31536000) return [Math.floor(s / 2592000), "month"]
  return [Math.floor(s / 31536000), "year"]
}

// Terse up to the hour ("3m ago") and spelled out from a day ("1 day ago").
// The words are the browser's, so all the site's languages come for free.
export function agoText(date, locale, now = Date.now()) {
  const [value, unit] = agoParts((now - date.getTime()) / 1000)
  const say = style => new Intl.RelativeTimeFormat(locale, {style, numeric: "always"}).format(-value, unit)

  if (!["second", "minute", "hour"].includes(unit)) return say("long")

  // French, Russian, Swedish and others make the narrow form a bare "-3 min".
  const narrow = say("narrow")
  return /^[-−]/.test(narrow) ? say("short") : narrow
}

function localize(el) {
  const iso = el.getAttribute("datetime")
  const format = el.dataset.localTime
  if (!iso || !format) return

  const stamp = `${iso}|${format}`
  if (format !== RELATIVE && el.dataset[RENDERED] === stamp) return

  // `2026-09` is a valid HTML month string but not every engine parses it as a
  // date; anchoring it to the first keeps it on the calendar-month path.
  const date = new Date(/^\d{4}-\d{2}$/.test(iso) ? `${iso}-01` : iso)
  if (isNaN(date.getTime())) return

  try {
    const text =
      format === RELATIVE
        ? agoText(date, pageLocale())
        : date.toLocaleString(pageLocale(), FORMATS[format] || FORMATS.datetime)

    // A relative time comes through here on every tick; rewriting the same
    // words would only wake the observer.
    if (el.textContent !== text) el.textContent = text
    if (format === RELATIVE) el.title = date.toLocaleString(pageLocale(), FORMATS.full)
    el.dataset[RENDERED] = stamp
  } catch (_e) {
    // Leave the server's UTC text in place rather than showing nothing.
  }
}

export function localizeTimes(root = document) {
  const scope = root instanceof Element || root instanceof Document ? root : document
  if (scope instanceof Element && scope.matches("time[data-local-time]")) localize(scope)
  scope.querySelectorAll("time[data-local-time]").forEach(localize)
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

  setInterval(() => {
    document.querySelectorAll(`time[data-local-time="${RELATIVE}"]`).forEach(localize)
  }, RELATIVE_TICK_MS)
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
