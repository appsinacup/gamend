// A file dropped on a file field (`GamendWeb.FileDropComponents.file_drop/1`,
// or any element marked `data-file-drop`) is taken as a picked one.
//
// A zone that is a LiveView upload's `phx-drop-target` is LiveView's: it takes
// the drop and marks the zone `phx-drop-target-active` while a file is over
// it. Here such a zone only keeps the browser from opening the file while the
// socket is not up.
//
// Any other zone holds a plain `<input type="file">`: the drop sets its files
// (the first alone unless it is `multiple`; only those its `accept` takes, as
// the picker would offer) and fires `input` and `change`, as a pick does. The
// zone is `data-file-drop-active` while a file is over it.
//
// Delegated from the document, so a zone drawn after load (a LiveView patch, a
// script's markup) needs nothing more.

const ZONE = "[data-file-drop]"
const ACTIVE = "data-file-drop-active"

function zoneOf(target) {
  return target && target.closest ? target.closest(ZONE) : null
}

function hasFiles(event) {
  const types = event.dataTransfer && event.dataTransfer.types
  return !!types && Array.from(types).includes("Files")
}

function liveZone(zone) {
  return zone.hasAttribute("phx-drop-target") && zone.getAttribute("phx-drop-target") !== ""
}

// Whether an input's `accept` takes a file, read as the picker reads it: a
// `.ext`, a `type/*` or a full MIME type, any of them. No `accept`, any file.
export function accepts(accept, file) {
  const tokens = String(accept || "")
    .split(",")
    .map((token) => token.trim().toLowerCase())
    .filter(Boolean)
  if (tokens.length === 0) return true

  const name = String(file.name || "").toLowerCase()
  const type = String(file.type || "").toLowerCase()
  return tokens.some((token) => {
    if (token.startsWith(".")) return name.endsWith(token)
    if (token.endsWith("/*")) return type.startsWith(token.slice(0, -1))
    return type === token
  })
}

// The files a drop puts in an input.
export function pick(input, files) {
  const taken = Array.from(files || []).filter((file) => accepts(input.getAttribute("accept"), file))
  return input.multiple ? taken : taken.slice(0, 1)
}

export function fill(input, files, makeTransfer = () => new DataTransfer()) {
  const chosen = pick(input, files)
  if (chosen.length === 0) return false

  const transfer = makeTransfer()
  chosen.forEach((file) => transfer.items.add(file))
  input.files = transfer.files
  input.dispatchEvent(new Event("input", {bubbles: true}))
  input.dispatchEvent(new Event("change", {bubbles: true}))
  return true
}

export function startFileDrop(doc = document) {
  // Entering a child and leaving its sibling fire too: count per zone, as
  // LiveView does for its drop targets.
  const depths = new WeakMap()

  const clear = (zone) => {
    depths.delete(zone)
    zone.removeAttribute(ACTIVE)
  }

  doc.addEventListener("dragenter", (event) => {
    const zone = zoneOf(event.target)
    if (!zone || liveZone(zone) || !hasFiles(event)) return
    const depth = (depths.get(zone) || 0) + 1
    depths.set(zone, depth)
    if (depth === 1) zone.setAttribute(ACTIVE, "")
  })

  doc.addEventListener("dragover", (event) => {
    const zone = zoneOf(event.target)
    if (!zone || !hasFiles(event)) return
    event.preventDefault()
    if (event.dataTransfer) event.dataTransfer.dropEffect = "copy"
  })

  doc.addEventListener("dragleave", (event) => {
    const zone = zoneOf(event.target)
    if (!zone || liveZone(zone)) return
    const depth = depths.get(zone)
    if (depth === undefined) return
    if (depth > 1) depths.set(zone, depth - 1)
    else clear(zone)
  })

  doc.addEventListener("drop", (event) => {
    const zone = zoneOf(event.target)
    if (!zone) return
    event.preventDefault()
    if (liveZone(zone)) return
    clear(zone)

    const input = zone.matches('input[type="file"]') ? zone : zone.querySelector('input[type="file"]')
    if (!input || input.disabled || !event.dataTransfer) return
    fill(input, event.dataTransfer.files)
  })
}
