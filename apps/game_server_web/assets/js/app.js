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
import {hooks as colocatedHooks} from "phoenix-colocated/game_server_web"
import "./lobbies"
import {LocalDatetimeInput, startLocalTime} from "./local_time"
import {startAvatarFallback} from "./avatar_fallback"
import topbar from "../vendor/topbar"

// Custom hooks
const Hooks = {
  LocalDatetimeInput,

  /**
   * GuideDisclosure — mirrors a <details> section's open state into the URL so
   * the link can be shared and the state survives a reconnect (LiveView remounts
   * from the same params). The `toggle` event is what native <details> fires;
   * there is no click handler to keep in sync with keyboard use.
   *
   * One guide is open at a time. The previously open one is closed HERE, not
   * by the server patch: collapsing a tall section above the one just clicked
   * shifts the whole page, so it must happen synchronously with a scroll
   * correction that keeps the clicked summary where the reader sees it. The
   * patch then finds both `open` attributes already right and changes no
   * layout. (The programmatic close fires that section's own toggle event,
   * whose push the server ignores — it no longer matches the open slug.)
   */
  GuideDisclosure: {
    mounted() {
      this.onToggle = () => {
        if (this.el.open) {
          const before = this.el.getBoundingClientRect().top
          for (const other of document.querySelectorAll("details[data-slug][open]")) {
            if (other !== this.el) other.open = false
          }
          // "instant" bypasses the page's smooth scroll-behavior: this is a
          // correction, not a navigation, and animating it looks like a jump.
          // The second pass one frame later absorbs the browser's own scroll
          // anchoring, which adjusts again after this handler returns.
          const correct = () => {
            const delta = this.el.getBoundingClientRect().top - before
            if (delta !== 0) window.scrollBy({top: delta, behavior: "instant"})
          }
          correct()
          requestAnimationFrame(correct)
        }
        this.pushEvent("guide_toggled", {slug: this.el.dataset.slug, open: this.el.open})
      }
      this.el.addEventListener("toggle", this.onToggle)
    },
    destroyed() {
      this.el.removeEventListener("toggle", this.onToggle)
    },
  },


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
  ReconnectNotice: {
    mounted() {
      this.delayMs = parseInt(this.el.dataset.delayMs || "5000", 10)
      this.timer = null
      this.hide()

      this.onDisconnected = () => {
        this.clearTimer()
        this.timer = setTimeout(() => this.show(), this.delayMs)
      }

      this.onConnected = () => {
        this.clearTimer()
        this.hide()
      }

      this.el.addEventListener("gs:lv-disconnected", this.onDisconnected)
      this.el.addEventListener("gs:lv-connected", this.onConnected)
    },
    destroyed() {
      this.clearTimer()
      this.el.removeEventListener("gs:lv-disconnected", this.onDisconnected)
      this.el.removeEventListener("gs:lv-connected", this.onConnected)
    },
    clearTimer() {
      if (this.timer) {
        clearTimeout(this.timer)
        this.timer = null
      }
    },
    show() {
      this.el.removeAttribute("hidden")
    },
    hide() {
      this.el.setAttribute("hidden", "")
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
  const meta = document.querySelector("meta[name='game-server-extra-hooks']")
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

function createLiveSocket(extraHooks) {
  const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

  return new LiveSocket("/live", Socket, {
    longPollFallbackMs: 2500,
    params: {_csrf_token: csrfToken},
    hooks: {...colocatedHooks, ...Hooks, ...extraHooks},
  })
}

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
startAvatarFallback()

window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Timestamps render as UTC server-side and are rewritten in the viewer's zone.
// Started before the socket so static (non-LiveView) pages are covered too.
startLocalTime()

loadExtraHooks().then((extraHooks) => {
  const liveSocket = createLiveSocket(extraHooks)

  // connect if there are any LiveViews on the page
  liveSocket.connect()

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
