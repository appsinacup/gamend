// The browser half of `/report` (`GamendWeb.ReportLive`).
//
// `ReportForm` sends the screen size, and takes images from the file picker, a
// drop or a paste, shrinks each one and hands it to the LiveView upload. The
// shrink is not only for size: drawing a photo onto a canvas and writing it out
// again leaves its EXIF behind, location included. The server checks the bytes
// either way, so a browser that cannot draw an image sends it as it is.
//
// `ReportPagePath` fills the page field with the full URL of the page the
// reader came from, which `startLastPage` keeps in sessionStorage as they move
// around the site.

const MAX_WIDTH = 1600
const MAX_HEIGHT = 4000
const QUALITY = 0.85
const LAST_PAGE_KEY = "gamend:last_page"

// `/report`, or the same under a locale prefix (`/ro/report`).
export function isReportPath(path) {
  return /^(\/[a-z]{2}(?:[-_][a-zA-Z]{2,4})?)?\/report\/?$/.test(path || "")
}

export function fitSize(width, height, maxWidth = MAX_WIDTH, maxHeight = MAX_HEIGHT) {
  const scale = Math.min(1, maxWidth / width, maxHeight / height)
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  }
}

function toBlob(canvas, type) {
  return new Promise((resolve) => canvas.toBlob(resolve, type, QUALITY))
}

export async function shrink(file) {
  if (!file || !file.type || !file.type.startsWith("image/")) return null
  if (typeof createImageBitmap !== "function") return file

  try {
    const bitmap = await createImageBitmap(file)
    const {width, height} = fitSize(bitmap.width, bitmap.height)
    const canvas = document.createElement("canvas")
    canvas.width = width
    canvas.height = height
    canvas.getContext("2d").drawImage(bitmap, 0, 0, width, height)
    if (bitmap.close) bitmap.close()

    // Safari before 17 writes PNG when asked for WebP: fall back to JPEG,
    // which every browser writes.
    let blob = await toBlob(canvas, "image/webp")
    if (!blob || blob.type !== "image/webp") blob = await toBlob(canvas, "image/jpeg")
    if (!blob) return file

    const ext = blob.type === "image/webp" ? "webp" : "jpg"
    return new File([blob], `screenshot.${ext}`, {type: blob.type})
  } catch (_error) {
    return file
  }
}

function imagesFrom(list) {
  return Array.from(list || []).filter((file) => file && file.type && file.type.startsWith("image/"))
}

export const ReportForm = {
  mounted() {
    this.pushEvent("client", {
      viewport: `${window.innerWidth}×${window.innerHeight}`,
      screen: `${window.screen.width}×${window.screen.height}@${window.devicePixelRatio || 1}x`,
    })

    // Delegated: the picker and the drop zone are re-rendered with the form.
    this.onChange = (event) => {
      if (!event.target.matches || !event.target.matches("[data-report-pick]")) return
      const files = event.target.files
      this.add(files)
      event.target.value = ""
    }
    this.onDragOver = (event) => {
      if (event.target.closest && event.target.closest("[data-report-drop]")) event.preventDefault()
    }
    this.onDrop = (event) => {
      if (!event.target.closest || !event.target.closest("[data-report-drop]")) return
      event.preventDefault()
      this.add(event.dataTransfer && event.dataTransfer.files)
    }
    this.onPaste = (event) => {
      const items = Array.from((event.clipboardData && event.clipboardData.items) || [])
      const files = items
        .filter((item) => item.kind === "file" && item.type.startsWith("image/"))
        .map((item) => item.getAsFile())
      if (files.length === 0) return
      event.preventDefault()
      this.add(files)
    }

    this.el.addEventListener("change", this.onChange)
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("drop", this.onDrop)
    window.addEventListener("paste", this.onPaste)
  },

  destroyed() {
    window.removeEventListener("paste", this.onPaste)
  },

  async add(list) {
    const images = imagesFrom(list)
    if (images.length === 0) return
    const shrunk = (await Promise.all(images.map(shrink))).filter(Boolean)
    if (shrunk.length > 0) this.upload("attachments", shrunk)
  },
}

export const ReportPagePath = {
  mounted() {
    if (this.el.value) return
    const path = lastPage()
    if (!path) return
    this.el.value = path
    this.el.dispatchEvent(new Event("input", {bubbles: true}))
  },
}

// The page's full URL, fragment dropped. A bare path (kept by an older page
// in this tab) gets the site's address in front.
function fullUrl(origin, page) {
  return page.startsWith("/") ? origin + page : page
}

function lastPage() {
  try {
    const stored = sessionStorage.getItem(LAST_PAGE_KEY)
    if (stored) return fullUrl(window.location.origin, stored)
  } catch (_error) {
    // Storage blocked: fall through to the referrer.
  }

  try {
    const referrer = new URL(document.referrer)
    if (referrer.origin === window.location.origin && !isReportPath(referrer.pathname)) {
      return referrer.origin + referrer.pathname + referrer.search
    }
  } catch (_error) {
    // No referrer, or not a URL.
  }

  return null
}

function remember() {
  const {origin, pathname, search} = window.location
  if (isReportPath(pathname)) return
  try {
    sessionStorage.setItem(LAST_PAGE_KEY, origin + pathname + search)
  } catch (_error) {
    // Private mode or blocked storage: the field stays empty, which is fine.
  }
}

// Every page load and every LiveView navigation records where the reader is,
// so `/report` can say which page they were on.
export function startLastPage() {
  remember()
  window.addEventListener("phx:page-loading-stop", remember)
}
