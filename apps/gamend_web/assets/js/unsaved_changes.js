// Asks before the reader leaves a form its Save has not kept. The server says
// which forms those are (`data-unsaved`, `CoreComponents.unsaved?/2`), so what
// was refused stays marked and what was saved stops being.
//
// A link asks in the page's popup (`confirm_dialog.js`). A reload, a closed tab
// or a typed address can only ask in the browser's own (`beforeunload`). A
// button that leaves the form with no link says so with `data-leaves-form`.
//
// The browser's Back within LiveView does not ask: `popstate` cannot be
// cancelled, only undone after the page has moved.

// What a click on `target` follows off the form, or null: a same-tab link to
// another page, or a button marked.
export function leavingElement(target, location) {
  const element =
    target && typeof target.closest === "function" ? target.closest("a[href], [data-leaves-form]") : null
  if (!element) return null
  if (element.hasAttribute("data-leaves-form")) return element
  if (element.hasAttribute("download")) return null

  const targetAttr = element.getAttribute("target")
  if (targetAttr && targetAttr !== "_self") return null

  const href = element.getAttribute("href") || ""
  if (href === "" || href.startsWith("#") || href.startsWith("mailto:") || href.startsWith("tel:")) return null

  try {
    const url = new URL(href, location.href)
    // The same page with only a new hash is the browser's to scroll.
    if (url.pathname === location.pathname && url.search === location.search) return null
  } catch (_) {
    return null
  }
  return element
}

// How long a yes lets the next `beforeunload` through: a followed link starts
// unloading at once, and a link that did not leave must not disarm the page.
const LEAVING_MS = 1000

export function startUnsavedChanges(ask, doc = document, win = window) {
  const dialog = doc.getElementById("gamend-confirm")
  const text = dialog ? dialog.getAttribute("data-unsaved-message") : null
  const unsaved = () => doc.querySelector("[data-unsaved]") !== null
  let leaving = false

  // Capture phase: ahead of LiveView's click handler and `live_nav.js`.
  if (ask) {
    doc.addEventListener(
      "click",
      (event) => {
        if (leaving || event.defaultPrevented || event.button !== 0) return
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
        if (!unsaved()) return

        const element = leavingElement(event.target, win.location)
        if (!element) return

        event.preventDefault()
        event.stopImmediatePropagation()

        ask(text, () => {
          if (!element.isConnected) return

          leaving = true
          element.click()
          win.setTimeout(() => {
            leaving = false
          }, LEAVING_MS)
        })
      },
      true,
    )
  }

  win.addEventListener("beforeunload", (event) => {
    if (!leaving && unsaved()) event.preventDefault()
  })
}
