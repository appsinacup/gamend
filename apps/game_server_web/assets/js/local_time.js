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
}

// Marks what a node was last rendered from, so re-running over a page that has
// not changed is free and cannot loop against the MutationObserver below.
const RENDERED = "localTimeRendered"

function pageLocale() {
  const lang = document.documentElement.getAttribute("lang")
  return lang && lang.trim() !== "" ? lang : undefined
}

function localize(el) {
  const iso = el.getAttribute("datetime")
  const format = el.dataset.localTime
  if (!iso || !format) return

  const stamp = `${iso}|${format}`
  if (el.dataset[RENDERED] === stamp) return

  const date = new Date(iso)
  if (isNaN(date.getTime())) return

  try {
    el.textContent = date.toLocaleString(pageLocale(), FORMATS[format] || FORMATS.datetime)
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
