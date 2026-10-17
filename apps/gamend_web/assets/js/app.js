// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Theme switcher & card collapse/expand (previously inline in root.html.heex)
import "./theme.js"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/gamend_web"
import "./lobbies"
import {Captcha} from "./captcha"
import {LocalDatetimeInput, startLocalTime} from "./local_time"
import {startAvatarFallback} from "./avatar_fallback"
import {startVideoClickToPlay} from "./video_click_to_play"
import {startConnectionState} from "./connection_state"
import {startSearchPalette} from "./search_palette"
import {startAnonymousSession} from "./anonymous_session"
import {startLiveNav} from "./live_nav"
import {startBackLink} from "./back_link"
import {ReportForm, ReportPagePath, startLastPage} from "./report_form"
import topbar from "../vendor/topbar"

// Custom hooks
const Hooks = {
  Captcha,
  LocalDatetimeInput,
  ReportForm,
  ReportPagePath,



  /**
   * MermaidDiagram — renders the mermaid source in `data-diagram` into the
   * element. The 2.7MB mermaid bundle is lazy-loaded on first use so it never
   * weighs on normal pages (it is only used by /admin/runtime).
   */
  MermaidDiagram: {
    mounted() { this.render() },
    updated() { this.render() },
    async render() {
      if (!window.mermaid) {
        await new Promise((resolve, reject) => {
          const s = document.createElement("script")
          s.src = "/assets/js/mermaid.js"
          s.onload = resolve
          s.onerror = reject
          document.head.appendChild(s)
        }).catch(() => null)
      }
      if (!window.mermaid) {
        this.el.textContent = "mermaid failed to load"
        return
      }
      const dark = document.documentElement.getAttribute("data-theme") === "dark"
      window.mermaid.initialize({startOnLoad: false, theme: dark ? "dark" : "default"})
      const src = this.el.dataset.diagram
      try {
        const {svg} = await window.mermaid.render(`mm-${this.el.id}`, src)
        this.el.innerHTML = svg
        this.enablePanZoom()
      } catch (e) {
        this.el.textContent = `diagram error: ${e.message || e}`
      }
    },
    // Zoom/pan on top of mermaid's own responsive sizing. The SVG is left at
    // width:100% so CSS fits it to the container — deriving a fit scale in JS
    // needs viewport metrics that are not reliably available at mount time.
    // scale 1 therefore means "fitted"; double-click returns to it.
    enablePanZoom() {
      const svg = this.el.querySelector("svg")
      if (!svg) return
      svg.style.width = "100%"
      svg.style.height = "auto"
      svg.style.maxWidth = "100%"
      let scale = 1, tx = 0, ty = 0
      const apply = () => {
        svg.style.transformOrigin = "0 0"
        svg.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`
      }
      this.el.addEventListener("wheel", (e) => {
        e.preventDefault()
        const rect = this.el.getBoundingClientRect()
        const mx = e.clientX - rect.left, my = e.clientY - rect.top
        const factor = e.deltaY < 0 ? 1.15 : 1 / 1.15
        const next = Math.min(Math.max(scale * factor, 0.05), 12)
        // keep the point under the cursor fixed while zooming
        tx = mx - (mx - tx) * (next / scale)
        ty = my - (my - ty) * (next / scale)
        scale = next
        apply()
      }, {passive: false})
      let dragging = null
      this.el.addEventListener("pointerdown", (e) => {
        dragging = {x: e.clientX - tx, y: e.clientY - ty}
        this.el.style.cursor = "grabbing"
        this.el.setPointerCapture(e.pointerId)
      })
      this.el.addEventListener("pointermove", (e) => {
        if (!dragging) return
        tx = e.clientX - dragging.x
        ty = e.clientY - dragging.y
        apply()
      })
      this.el.addEventListener("pointerup", () => {
        dragging = null
        this.el.style.cursor = "grab"
      })
      this.el.addEventListener("dblclick", () => {
        scale = 1; tx = 0; ty = 0
        apply()
      })
    },
  },
  GameAuth: {
    mounted() {
      const access = this.el.dataset.accessToken
      const refresh = this.el.dataset.refreshToken
      if (access) localStorage.setItem("gamend_access_token", access)
      if (refresh) localStorage.setItem("gamend_refresh_token", refresh)
      // Clear tokens when not authenticated
      if (!access) localStorage.removeItem("gamend_access_token")
      if (!refresh) localStorage.removeItem("gamend_refresh_token")
    }
  },
  GameViewport: {
    mounted() {
      // Prevent mobile browsers from zooming when the virtual keyboard opens.
      // We swap the viewport meta to disable user scaling while the game is
      // visible, and restore it when the LiveView is destroyed.
      const meta = document.querySelector('meta[name="viewport"]')
      if (meta) {
        this._origViewport = meta.getAttribute("content")
        meta.setAttribute(
          "content",
          "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"
        )
      }

      // Prevent scroll drift when virtual keyboard opens/closes
      const vv = window.visualViewport
      if (vv) {
        this._onResize = () => window.scrollTo(0, 0)
        vv.addEventListener("resize", this._onResize)
        vv.addEventListener("scroll", this._onResize)
      }
    },
    destroyed() {
      // Restore original viewport meta
      const meta = document.querySelector('meta[name="viewport"]')
      if (meta && this._origViewport) {
        meta.setAttribute("content", this._origViewport)
      }

      const vv = window.visualViewport
      if (vv && this._onResize) {
        vv.removeEventListener("resize", this._onResize)
        vv.removeEventListener("scroll", this._onResize)
      }
    }
  },
  ScrollToBottom: {
    mounted() {
      this.el.scrollTop = this.el.scrollHeight
    },
    updated() {
      this.el.scrollTop = this.el.scrollHeight
    }
  },
  AutoClose: {
    mounted() {
      let seconds = 3
      this.el.innerText = `This window will close in ${seconds}s...`
      
      this.interval = setInterval(() => {
        seconds -= 1
        if (seconds <= 0) {
          clearInterval(this.interval)
          this.el.innerText = "Closing..."
          window.close()
        } else {
          this.el.innerText = `This window will close in ${seconds}s...`
        }
      }, 1000)
    },
    destroyed() {
      if (this.interval) clearInterval(this.interval)
    }
  },
  NavbarDropdowns: {
    mounted() {
      this.boundDropdowns = []
      this.boundSummaries = []

      this.closeOpenDropdowns = (except = null) => {
        this.el.querySelectorAll("[data-navbar-dropdown][open]").forEach((dropdown) => {
          if (dropdown !== except) dropdown.open = false
        })
      }

      this.onSummaryPointerDown = (event) => {
        const summary = event.currentTarget
        const dropdown = summary.closest("[data-navbar-dropdown]")
        if (dropdown instanceof HTMLDetailsElement && !dropdown.open) {
          this.closeOpenDropdowns(dropdown)
        }
      }

      this.onToggle = (event) => {
        const dropdown = event.currentTarget
        if (dropdown instanceof HTMLDetailsElement && dropdown.open) {
          requestAnimationFrame(() => this.closeOpenDropdowns(dropdown))
        }
      }

      this.onDocumentClick = (event) => {
        if (!this.el.contains(event.target)) this.closeOpenDropdowns()
      }

      this.onEscape = (event) => {
        if (event.key === "Escape") this.closeOpenDropdowns()
      }

      this.bindDropdowns = () => {
        this.boundDropdowns.forEach((dropdown) => {
          dropdown.removeEventListener("toggle", this.onToggle)
        })
        this.boundSummaries.forEach((summary) => {
          summary.removeEventListener("pointerdown", this.onSummaryPointerDown)
        })

        this.boundDropdowns = Array.from(this.el.querySelectorAll("[data-navbar-dropdown]"))
        this.boundDropdowns.forEach((dropdown) => {
          dropdown.addEventListener("toggle", this.onToggle)
        })
        this.boundSummaries = this.boundDropdowns
          .map((dropdown) => dropdown.querySelector("summary"))
          .filter(Boolean)
        this.boundSummaries.forEach((summary) => {
          summary.addEventListener("pointerdown", this.onSummaryPointerDown)
        })
      }

      this.bindDropdowns()
      document.addEventListener("click", this.onDocumentClick)
      document.addEventListener("keydown", this.onEscape)
    },
    updated() {
      this.bindDropdowns()
    },
    destroyed() {
      this.boundDropdowns.forEach((dropdown) => {
        dropdown.removeEventListener("toggle", this.onToggle)
      })
      this.boundSummaries.forEach((summary) => {
        summary.removeEventListener("pointerdown", this.onSummaryPointerDown)
      })
      document.removeEventListener("click", this.onDocumentClick)
      document.removeEventListener("keydown", this.onEscape)
    }
  },
  NavbarAutohide: {
    mounted() {
      this.targetId = this.el.dataset.target || "main-navbar"
      this.navbar = null
      // Navbar starts collapsed on flush (game) pages. A single fixed toggle
      // button shows/hides it — no auto-hide timer, so LiveView reconnects
      // never make the navbar reappear on their own.
      this.isHidden = true
      // Skip the slide animation on first paint so the navbar doesn't flash.
      this.instant = true

      this.toggleBtn = document.createElement("button")
      this.toggleBtn.className =
        "fixed top-3 right-3 z-[60] btn btn-circle btn-sm bg-base-100/60 backdrop-blur-sm border-base-content/10 shadow-md"
      this.toggleBtn.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        if (this.isHidden) {
          this.showNavbar()
        } else {
          this.hideNavbar()
        }
      })

      document.body.appendChild(this.toggleBtn)
      this.syncNavbar()
      this.instant = false
    },
    updated() {
      this.syncNavbar()
    },
    // A reconnect (Safari suspends sockets on background tabs) re-patches the
    // layout from server HTML, wiping the client-set inline styles that keep
    // the navbar hidden. Re-apply the state this hook instance still holds.
    reconnected() {
      this.instant = true
      this.syncNavbar()
      this.instant = false
    },
    destroyed() {
      if (this.navbar) this.applyVisibleState()
      if (this.toggleBtn) {
        this.toggleBtn.remove()
      }
    },
    syncNavbar() {
      const navbar = document.getElementById(this.targetId)
      if (!navbar) return

      this.navbar = navbar

      if (this.isHidden) {
        this.applyHiddenState()
      } else {
        this.applyVisibleState()
      }
    },
    hideNavbar() {
      if (!this.navbar) return
      this.isHidden = true
      this.applyHiddenState()
    },
    showNavbar() {
      if (!this.navbar) this.syncNavbar()
      if (!this.navbar) return

      this.isHidden = false
      this.applyVisibleState()
    },
    navbarTransition() {
      return this.instant ? "none" : "opacity 0.3s ease, transform 0.3s ease"
    },
    applyHiddenState() {
      if (!this.navbar || !this.toggleBtn) return

      this.navbar.style.transition = this.navbarTransition()
      this.navbar.style.opacity = "0"
      this.navbar.style.transform = "translateY(-100%)"
      this.navbar.style.pointerEvents = "none"
      this.toggleBtn.setAttribute("aria-label", "Show navigation")
      this.toggleBtn.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/></svg>`
    },
    applyVisibleState() {
      if (!this.navbar || !this.toggleBtn) return

      this.navbar.style.transition = this.navbarTransition()
      this.navbar.style.opacity = "1"
      this.navbar.style.transform = "translateY(0)"
      this.navbar.style.pointerEvents = "auto"
      this.toggleBtn.setAttribute("aria-label", "Hide navigation")
      this.toggleBtn.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7"/></svg>`
    }
  },

  /**
   * AutoScroll — keeps a scrollable container pinned to the bottom
   * as new content is added (e.g. live log viewer).
   */
  AutoScroll: {
    mounted() {
      this._scroll = () => {
        this.el.scrollTop = this.el.scrollHeight
      }
      this._observer = new MutationObserver(this._scroll)
      this._observer.observe(this.el, { childList: true, subtree: true })
      this._scroll()
    },
    updated() {
      this._scroll()
    },
    destroyed() {
      if (this._observer) this._observer.disconnect()
    }
  }
}

function configuredExtraHookModules() {
  const meta = document.querySelector("meta[name='gamend-extra-hooks']")
  const content = meta && meta.getAttribute("content")

  if (!content) return []

  return content
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value !== "")
}

function extractHookMap(loadedModule) {
  if (loadedModule && typeof loadedModule.hooks === "object") return loadedModule.hooks
  if (loadedModule && loadedModule.default && typeof loadedModule.default === "object") {
    return loadedModule.default
  }

  return {}
}

async function loadExtraHooks() {
  const modules = configuredExtraHookModules()
  const mergedHooks = {}

  for (const modulePath of modules) {
    try {
      const loadedModule = await import(/* @vite-ignore */ modulePath)
      Object.assign(mergedHooks, extractHookMap(loadedModule))
    } catch (error) {
      console.error(`Failed to load extra hooks from ${modulePath}`, error)
    }
  }

  return mergedHooks
}

// An IANA name ("Europe/Bucharest"), or nothing when the browser will not say.
function browserTimeZone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || undefined
  } catch (_error) {
    return undefined
  }
}

function createLiveSocket(extraHooks) {
  // Optional: a publicly cacheable, signed-out page omits the token on purpose
  // (see the comment on the tag in root.html.heex). Such a page carries no
  // LiveView, so `connect()` never joins and the token is never needed — but a
  // hard `.getAttribute` on null threw here, which killed this whole module and
  // took every colocated hook on the page down with it.
  const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

  return new LiveSocket("/live", Socket, {
    longPollFallbackMs: 2500,
    // How fast a dead network is noticed when the browser still thinks it is
    // online (Wi-Fi up, no internet): a heartbeat left unanswered at the next
    // one closes the socket. Phoenix's 30 s default meant up to a minute of
    // typing into a page that had already stopped listening.
    heartbeatIntervalMs: 15000,
    // The reader's time zone, saved on their account (`GamendWeb.UserAuth`)
    // so "today" and "this evening" are theirs, not UTC's.
    params: {_csrf_token: csrfToken, timezone: browserTimeZone()},
    hooks: {...colocatedHooks, ...Hooks, ...extraHooks},
    // A `phx-remove` plays when a patch takes its element away, never when
    // the page is left. LiveView 1.2 defaults this to true: on a live
    // navigation every `phx-remove` in the old page played at the click, so
    // a list item faded out (a hub's Continue card, a pinned tile) and a
    // panel folded shut, and the page sat that way until the next one came.
    cascadePhxRemoveOnNavigation: false,
  })
}

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
startAvatarFallback()
// Before the poster can be shown: the overlay button is in the server-rendered
// markup, so the listener must exist by the time the first click can land.
startVideoClickToPlay()
// Before the socket: a page can push the anonymous account it made on the
// first event it handles.
startAnonymousSession({getLiveSocket: () => window.liveSocket})

window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Timestamps render as UTC server-side and are rewritten in the viewer's zone.
// Started before the socket so static (non-LiveView) pages are covered too.
startLocalTime()

// The search palette listens on `document`, not on the button: the navbar is
// re-rendered by any `push_patch`, which would drop a listener bound to an
// element. Started here so it works on pages with no LiveView at all.
startSearchPalette()
startLastPage()

// Smooth scrolling for in-page anchors — armed on the reader's first input,
// not in the markup. `scroll-behavior: smooth` on <html> also governs scrolls
// the browser makes on its own, and Chrome applies it to the scroll
// *restoration* of a reload: a page refreshed halfway down paints at the top
// and then glides back to where it was. Nothing the reader did asked for
// motion there, and it reads as a flash. A pointerdown or keydown precedes
// every anchor click, so those stay smooth; every load-time scroll —
// restoration, `#fragment` on arrival — is instant. Explicit
// `scrollIntoView({behavior})` calls in hooks are unaffected either way.
// `motion-safe:` keeps the reduced-motion preference in charge.
function armSmoothScrolling() {
  const arm = () => document.documentElement.classList.add("motion-safe:scroll-smooth")
  const opts = {once: true, passive: true, capture: true}
  window.addEventListener("pointerdown", arm, opts)
  window.addEventListener("keydown", arm, opts)
}
armSmoothScrolling()

// A reload is the browser's to restore, not LiveView's.
//
// LiveView sets `history.scrollRestoration = "manual"` on connect so it can
// own the position across its live navigations. The setting lives on the
// history entry and survives a reload, which turns the browser's native
// restore — done before first paint, at the exact position — off for plain
// refreshes too. What replaces it is LiveView's own bookkeeping: `scrollY`
// written into `history.state.scroll` by a scroll listener debounced 100 ms,
// and read back in `joinDeadView` after app.js, the hooks import and one
// animation frame. Two symptoms, seen on every page: a refresh paints the
// top and then jumps to the saved spot; and a refresh mid-scroll lands where
// the reader was 100 ms ago, not where they let go.
//
// `pagehide` runs on every full navigation away, reload included, and the
// mode it leaves on the entry is what the next document loads under: flip it
// to `auto` there and the browser restores natively. (The state cannot be
// edited at that point — a `replaceState` in `pagehide` does not survive the
// reload, the entry is already committed — so the stale `scroll` is dropped
// on the way IN instead.) LiveView flips back to `manual` when it connects,
// so its live navigations are untouched; `pagehide` never fires for those.
//
// On the way in, before LiveView connects: `auto` on the entry means the
// browser has restored, or will from its own record, and LiveView's saved
// `scroll` would move the page a second time, to a position 100 ms stale —
// drop it. `manual` means the browser did nothing (an entry left by a live
// navigation, reached again cross-document) and LiveView's copy is the only
// one there is — keep it. Reading the mode is what tells the two apart, so
// this must run before `connect()` rewrites it.
function nativeScrollRestoreOnReload() {
  const state = history.state
  if (
    history.scrollRestoration === "auto" &&
    state && typeof state === "object" && "scroll" in state
  ) {
    const {scroll: _scroll, ...rest} = state
    history.replaceState(rest, "", window.location.href)
  }
  window.addEventListener("pagehide", () => {
    if (history.scrollRestoration) history.scrollRestoration = "auto"
  })
  // Back from the bfcache: same document, no reload, and the entry is now
  // `auto` from our own `pagehide`. LiveView's same-document `popstate`
  // restore expects `manual`, so give it back.
  window.addEventListener("pageshow", (e) => {
    if (e.persisted && history.scrollRestoration) history.scrollRestoration = "manual"
  })
}
nativeScrollRestoreOnReload()

// Back returns to the page the reader came from, when that was a click
// inside the site; else its link, the page's trail (`back_link.js`).
startBackLink()

loadExtraHooks().then((extraHooks) => {
  const liveSocket = createLiveSocket(extraHooks)
  startConnectionState(liveSocket.getSocket())

  // connect if there are any LiveViews on the page
  liveSocket.connect()

  // A plain link to another LiveView page of this `live_session` moves over
  // the open socket rather than loading the page (`GamendWeb.LiveNav`).
  startLiveNav(liveSocket)

  // expose liveSocket on window for web console debug logs and latency simulation:
  // >> liveSocket.enableDebug()
  // >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
  // >> liveSocket.disableLatencySim()
  window.liveSocket = liveSocket
})

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
