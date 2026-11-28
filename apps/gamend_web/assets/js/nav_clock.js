// The time left on a nav link's status (`HostLayoutNavigation.count_pill/1`'s
// `data-nav-deadline`, Unix ms): its `[data-nav-clock]` says `m:ss`, run down
// by the browser's frames while such a chip is on the page, and stopped once
// none is. `data-nav-now` is the server's time when the chip was drawn, so a
// clock off by minutes reads the same. At 0:00 it waits there: the host says
// when the thing timed is over (`nav_status` with no deadline).

let frame = 0

/** `m:ss` of `ms` left, never below 0:00 (the server draws the same). */
export function clockText(ms) {
  const seconds = Math.max(0, Math.ceil(ms / 1000))
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`
}

/**
 * Run the clocks if a chip has one and they are not running: at load, after
 * a live navigation (a new navbar) and after a `nav_status` push.
 */
export function syncNavClocks(doc = document) {
  if (frame || typeof requestAnimationFrame === "undefined") return
  if (!doc.querySelector("[data-nav-deadline]")) return
  frame = requestAnimationFrame(() => tick(doc))
}

function tick(doc) {
  frame = 0
  const chips = doc.querySelectorAll("[data-nav-deadline]")
  if (chips.length === 0) return
  const now = Date.now()
  for (const chip of chips) draw(chip, now)
  frame = requestAnimationFrame(() => tick(doc))
}

function draw(chip, now) {
  const clock = chip.querySelector("[data-nav-clock]")
  const deadline = Number(chip.dataset.navDeadline) || 0
  if (!clock || !deadline) return
  // Taken once for each time the server drew it: a patch that leaves
  // `data-nav-now` as it was keeps the offset taken then.
  if (chip._navNowFor !== chip.dataset.navNow) {
    chip._navNowFor = chip.dataset.navNow
    chip._navOffset = chip.dataset.navNow ? Number(chip.dataset.navNow) - now : 0
  }
  const text = clockText(deadline - (now + (chip._navOffset || 0)))
  if (clock.textContent !== text) clock.textContent = text
}

/**
 * A `nav_status` push's `deadline` (and `now`, the server's time) on one
 * chip: the clock added, or taken away with no deadline.
 */
export function setChipDeadline(chip, deadline, now) {
  let clock = chip.querySelector("[data-nav-clock]")

  if (Number.isInteger(deadline) && deadline > 0) {
    chip.dataset.navDeadline = String(deadline)
    chip.dataset.navNow = String(Number.isInteger(now) ? now : Date.now())
    chip.classList.remove("w-5")
    chip.classList.add("nav-status-clock", "gap-0.5", "ps-1", "pe-1.5")

    if (!clock) {
      clock = chip.ownerDocument.createElement("span")
      clock.dataset.navClock = ""
      clock.className = "text-[0.6875rem] font-bold leading-none tabular-nums"
      clock.setAttribute("aria-hidden", "true")
      chip.append(clock)
    }

    clock.textContent = clockText(deadline - Number(chip.dataset.navNow))
  } else {
    delete chip.dataset.navDeadline
    delete chip.dataset.navNow
    chip.classList.remove("nav-status-clock", "gap-0.5", "ps-1", "pe-1.5")
    chip.classList.add("w-5")
    clock?.remove()
  }
}
