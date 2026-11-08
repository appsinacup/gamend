// An uploaded logo is drawn on a tile of the theme's own colour, so a dark
// logo with a transparent background all but vanishes on a dark theme, and a
// white one on a light theme. What it needs depends on the image, which only
// the browser has decoded.
//
// An image marked `data-icon-backdrop` is read once when it loads: a thumbnail
// says how bright what it draws is, and one that would vanish gets a
// background tinted with its own colour. `light-dark()` applies it only on the
// theme that needs it, so a theme switched later needs no second look.
//
// A CSS rule per image URL, not a style on the element: a LiveView patch
// removes attributes the server did not render, and every picker's preview is
// patched on every change. A rule outlives the patch, and covers every other
// place that image is drawn.

const MARKER = "data-icon-backdrop"
const SIZE = 32

// Below this share of see-through pixels nothing of a background would show.
const MIN_CLEAR = 0.1
const VISIBLE_ALPHA = 128

// Relative luminance a logo vanishes under on a dark tile, and over on a light
// one. Between them it reads on both.
const DARK = 0.1
const LIGHT = 0.5

const channel = (value) => {
  const c = value / 255
  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
}

const luminance = (r, g, b) => 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)

// The `background-color` for an image's RGBA pixels, or null for one that
// reads as it is: opaque, or bright enough for either theme. By the median, so
// that a dark logo with a bright accent still counts as dark.
export function backdropFor(pixels) {
  const total = pixels.length / 4
  const visible = []
  let [r, g, b] = [0, 0, 0]

  for (let i = 0; i < pixels.length; i += 4) {
    if (pixels[i + 3] < VISIBLE_ALPHA) continue
    visible.push(luminance(pixels[i], pixels[i + 1], pixels[i + 2]))
    r += pixels[i]
    g += pixels[i + 1]
    b += pixels[i + 2]
  }

  if (visible.length === 0 || 1 - visible.length / total < MIN_CLEAR) return null

  const count = visible.length
  const tint = `rgb(${Math.round(r / count)} ${Math.round(g / count)} ${Math.round(b / count)})`
  const median = visible.sort((x, y) => x - y)[count >> 1]

  if (median < DARK) return `light-dark(transparent, color-mix(in oklab, ${tint} 15%, white))`
  if (median > LIGHT) return `light-dark(color-mix(in oklab, ${tint} 25%, black), transparent)`
  return null
}

// A thumbnail's RGBA, null when the browser will not let it be read: an image
// on another origin, fetched without CORS.
function pixelsOf(img) {
  try {
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = SIZE
    const context = canvas.getContext("2d", {willReadFrequently: true})
    context.drawImage(img, 0, 0, SIZE, SIZE)
    return context.getImageData(0, 0, SIZE, SIZE).data
  } catch (_) {
    return null
  }
}

let sheet = null
const read = new Set()

function addRule(src, pixels) {
  const backdrop = backdropFor(pixels)
  if (!backdrop) return
  sheet ??= document.head.appendChild(document.createElement("style")).sheet
  sheet.insertRule(`img[${MARKER}][src="${CSS.escape(src)}"]{background-color:${backdrop}}`)
}

function inspect(img) {
  const src = img.getAttribute("src")
  if (!img.hasAttribute(MARKER) || !src || read.has(src) || !img.naturalWidth) return
  read.add(src)

  const pixels = pixelsOf(img)
  if (pixels) return addRule(src, pixels)

  // A bucket on another origin, drawn without `crossorigin` so a bucket that
  // sends no CORS still shows its image. A copy in CORS mode can be read;
  // failing, the image stays on the theme's tile.
  const copy = new Image()
  copy.crossOrigin = "anonymous"
  copy.onload = () => {
    const copied = pixelsOf(copy)
    if (copied) addRule(src, copied)
  }
  copy.src = src
}

export function startIconBackdrop() {
  document.addEventListener(
    "load",
    (event) => {
      if (event.target instanceof HTMLImageElement) inspect(event.target)
    },
    true
  )

  // What loaded before this script ran.
  const sweep = () => document.querySelectorAll(`img[${MARKER}]`).forEach(inspect)
  sweep()
  window.addEventListener("phx:page-loading-stop", sweep)
}
