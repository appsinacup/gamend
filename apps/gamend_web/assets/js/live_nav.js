// Moving between LiveView pages over the websocket the page already has
// (`GamendWeb.LiveNav`). A plain `<a href>` to another LiveView page of the
// same `live_session` is made a live link at the moment it is clicked, so
// LiveView mounts the next page over the open socket (~140 ms on production)
// instead of loading it and opening a new one (~450 ms before it answers).
//
// The server sends its GET routes in the router's own order, each with its
// `live_session` or null for a controller route. The first route that matches
// a path is the one the router would serve, so only that one decides. A wrong
// guess costs one round trip: LiveView answers a live redirect it cannot mount
// by loading the page.

// `[[path, session, hasLocaleCopies, signedInOnly], ...]` -> matchers, order kept.
export function compileTable(json) {
  const routes = Array.isArray(json?.routes) ? json.routes : []
  return {
    prefixes: new Set(Array.isArray(json?.prefixes) ? json.prefixes : []),
    routes: routes.map(([path, session, prefixed, signedInOnly]) => ({
      segments: String(path).split("/").filter(Boolean),
      session: session || null,
      prefixed: prefixed === true,
      signedInOnly: signedInOnly === true,
    })),
  }
}

// `{prefix, parts}`: the locale prefix (or null) and the path's other segments.
export function splitPath(table, pathname) {
  const parts = String(pathname).split("/").filter(Boolean)
  if (parts.length > 0 && table.prefixes.has(parts[0])) return {prefix: parts[0], parts: parts.slice(1)}
  return {prefix: null, parts}
}

// Phoenix's matching: a literal segment equal, `:param` any one segment,
// `*glob` the rest (and nothing).
export function matches(segments, parts) {
  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i]
    if (segment.startsWith("*")) return true
    if (i >= parts.length) return false
    if (segment.startsWith(":")) continue
    let part = parts[i]
    try {
      part = decodeURIComponent(part)
    } catch (_) {
      return false
    }
    if (segment !== part) return false
  }
  return segments.length === parts.length
}

// Whether a click from `fromPath` to `url` (a URL object) can move over the
// socket of a page in `session`.
export function liveTarget(table, session, fromPath, url, origin, signedIn = false) {
  if (!table || !session || !url || url.origin !== origin) return false

  const from = splitPath(table, fromPath)
  const to = splitPath(table, url.pathname)
  // A locale switch reloads: the page's locale is the session's, set by the
  // HTTP request, and the root layout carries the language.
  if (from.prefix !== to.prefix) return false

  const route = table.routes.find((r) => matches(r.segments, to.parts))
  if (!route || route.session !== session) return false
  // A signed-out reader is sent to sign in, and only a request keeps the page
  // to come back to.
  if (route.signedInOnly && !signedIn) return false
  return to.prefix === null || route.prefixed
}

// The link a click on `target` follows, when it is one a page may take over:
// a plain same-tab link with nothing else asking for it.
export function plainLink(target) {
  const link = target && typeof target.closest === "function" ? target.closest("a[href]") : null
  if (!link) return null
  if (link.hasAttribute("data-phx-link") || link.hasAttribute("download")) return null
  if (link.hasAttribute("data-no-live-nav") || link.hasAttribute("phx-click")) return null
  const targetAttr = link.getAttribute("target")
  if (targetAttr && targetAttr !== "_self") return null
  const href = link.getAttribute("href") || ""
  if (href === "" || href.startsWith("#") || href.startsWith("mailto:") || href.startsWith("tel:")) return null
  return link
}

// Whether a link is one a press may fetch ahead (`startPressPrefetch`): a
// plain link to a page of this site that loads it (not this page with
// another hash, not a language switch, which writes the session's locale,
// nor a link with a method, which is not a GET).
export function prefetchable(link, target, win = window) {
  if (!link || !target) return false
  if (link.hasAttribute("data-method") || link.hasAttribute("data-no-prefetch")) return false
  if (target.origin !== win.location.origin) return false
  if (target.pathname === win.location.pathname && target.search === win.location.search) return false
  return !target.searchParams.has("setlang")
}

// A link that loads its page is fetched as the reader PRESSES it
// (`pointerdown`: a mouse button, a finger), through the browser's
// speculation rules, so the click 100-300 ms later finds the page on its
// way or in (2026-11-21: a Dictionary page from another was 500-1000 ms,
// a round trip and the page before anything changed). On a press, not a
// hover: a press is followed by its click, so nothing is fetched that is
// not opened and a page's views are not counted twice. A link this page
// follows over its socket (`isLive`) is not fetched: its HTML would go
// unread. Browsers without speculation rules (Safari, Firefox) do nothing.
export function startPressPrefetch(isLive = () => false, doc = document, win = window) {
  if (!win.HTMLScriptElement?.supports?.("speculationrules")) return
  const asked = new Set()

  doc.addEventListener(
    "pointerdown",
    (event) => {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
      const link = plainLink(event.target)
      if (!link) return

      let target
      try {
        target = new URL(link.href, win.location.href)
      } catch (_) {
        return
      }
      if (!prefetchable(link, target, win) || isLive(target)) return

      target.hash = ""
      if (asked.has(target.href)) return
      asked.add(target.href)

      const rules = doc.createElement("script")
      rules.type = "speculationrules"
      rules.textContent = JSON.stringify({prefetch: [{source: "list", urls: [target.href]}]})
      doc.head.appendChild(rules)
    },
    {capture: true, passive: true},
  )
}

// Answers whether a URL is one this page follows over its socket (for
// `startPressPrefetch`), or nothing on a page with no LiveView.
export function startLiveNav(liveSocket, doc = document, win = window) {
  const meta = doc.querySelector('meta[name="gamend-live-nav"]')
  if (!meta || !liveSocket) return

  const session = meta.getAttribute("data-session")
  const signedIn = meta.hasAttribute("data-signed-in")
  const url = meta.getAttribute("content")
  let table = null

  // Fetched once the page is up, cached by the browser for the version.
  fetch(url, {credentials: "same-origin", headers: {accept: "application/json"}})
    .then((response) => (response.ok ? response.json() : null))
    .then((json) => {
      if (json) table = compileTable(json)
    })
    .catch(() => {})

  // Capture phase: runs before LiveView's own click handler on `window`,
  // which then sees `data-phx-link` and navigates over the socket.
  doc.addEventListener(
    "click",
    (event) => {
      if (!table || event.defaultPrevented || event.button !== 0) return
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
      if (!liveSocket.isConnected()) return

      const link = plainLink(event.target)
      if (!link || !link.closest("[data-phx-main]")) return

      let target
      try {
        target = new URL(link.href, win.location.href)
      } catch (_) {
        return
      }
      // The same page with only a new hash is the browser's to scroll.
      if (target.pathname === win.location.pathname && target.search === win.location.search) return

      if (liveTarget(table, session, win.location.pathname, target, win.location.origin, signedIn)) {
        link.setAttribute("data-phx-link", "redirect")
        link.setAttribute("data-phx-link-state", "push")
      }
    },
    true,
  )

  return (target) =>
    Boolean(table) &&
    liveSocket.isConnected() &&
    liveTarget(table, session, win.location.pathname, target, win.location.origin, signedIn)
}
