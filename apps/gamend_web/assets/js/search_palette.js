// The site search palette: the magnifier in the navbar, Ctrl/Cmd+K, and the
// type-ahead list behind both.
//
// The whole index is fetched once and filtered in memory. A few hundred rows
// is nothing to scan per keystroke, and it is the difference between a list
// that answers while you type and one that answers after the network does.
//
// The markup is server-rendered (`HostLayoutShell.search_dialog/1`) and the
// two `<template>`s in it are the only source of class names: Tailwind purges
// what it cannot find in a scanned file, and a class written in a JS string is
// invisible to it. So this clones and sets `textContent`, and never builds
// markup.

const RESULT_LIMIT = 20
const QUERY_TOKEN = "{q}"
const MAX_NAMED_LANGUAGES = 3

// Matched against a word split, so a hyphenated or parenthesised form still
// counts as containing the word.
const WORD_SPLIT = /[^\p{L}\p{N}]+/gu

// Lowercase, and drop the accents: "espanol" should find "Español", the same
// way the vocabulary search does.
export const normalizeQuery = (value) =>
  String(value === undefined || value === null ? "" : value)
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Mn}/gu, "")

// 0 exact, 1 prefix, 2 a whole word inside a phrase, 3 substring, 4 miss.
// Ranking before truncating is what keeps "goal" above "goalpost": taking the
// first N in index order buries the thing you typed under everything that
// merely contains it.
export const fieldRank = (value, needle) => normalizedRank(normalizeQuery(value), needle)

const normalizedRank = (normalized, needle) => {
  if (normalized === "") return 4
  if (normalized === needle) return 0
  if (normalized.startsWith(needle)) return 1
  if (normalized.split(WORD_SPLIT).includes(needle)) return 2
  if (normalized.includes(needle)) return 3
  return 4
}

// Below every title and keyword hit, above a miss: the subtitle is a guide's
// summary or a section's first sentence, so it is where the words a reader
// half-remembers live, and also where a lot of words live.
const SUBTITLE_RANK = 3.5
const SUBTITLE_MIN_LENGTH = 3

// Normalizing is the costly part of matching, and the index does not change
// between keystrokes, so each row is normalized once, the first time it is
// ranked, and remembered for as long as the row itself lives.
const prepared = new WeakMap()

const prepare = (entry) => {
  let fields = prepared.get(entry)

  if (!fields) {
    const keywords = (Array.isArray(entry.keywords) ? entry.keywords : []).map(normalizeQuery)

    fields = {
      title: normalizeQuery(entry.title),
      keywords,
      keywordWords: keywords.flatMap((keyword) => keyword.split(WORD_SPLIT)).filter(Boolean),
      subtitle: normalizeQuery(entry.subtitle),
      subtitleWords: normalizeQuery(entry.subtitle).split(WORD_SPLIT).filter(Boolean),
    }

    prepared.set(entry, fields)
  }

  return fields
}

// A needle with a separator in it ("utf-8") is a phrase, and the words it
// spans are matched in order; one without is matched against the start of
// each word.
const SEPARATOR = /[^\p{L}\p{N}]/u

const subtitleMatches = (fields, needle) =>
  SEPARATOR.test(needle)
    ? fields.subtitle.includes(needle)
    : fields.subtitleWords.some((word) => word.startsWith(needle))

// The title carries the rank; a keyword can only match, never outrank a title
// match, so "Spanish" stays above a row that merely lists "spanish" as an
// alias. A subtitle word ranks below both, and only whole words and their
// starts count there, so "id" does not find every sentence with "hidden".
export const rankEntry = (entry, needle) => {
  const fields = prepare(entry)
  const title = normalizedRank(fields.title, needle)
  if (title < 4) return title

  let best = 4
  for (const keyword of fields.keywords) {
    const rank = normalizedRank(keyword, needle)
    if (rank < best) best = rank
  }
  // A keyword hit never beats a title hit of the same tier.
  if (best < 4) return Math.min(best + 1, 4)

  if (needle.length >= SUBTITLE_MIN_LENGTH && subtitleMatches(fields, needle)) {
    return SUBTITLE_RANK
  }

  return 4
}

// Edit distance, given up on as soon as it passes `max`. A reader who
// mistyped is one or two keys out; anything further is a different word, and
// bounding the walk is what keeps this cheap enough to run per keystroke.
//
// Two adjacent letters swapped count as ONE edit. Plain Levenshtein prices a
// swap at two, which is the difference between reading "hosue" as "house"
// and offering "hose" — a real word one plain edit away and the wrong
// answer. A host that also matches typos on the server should count the
// same way, or its page and the palette disagree about the same query.
export const editDistance = (a, b, max) => {
  if (a === b) return 0
  if (Math.abs(a.length - b.length) > max) return max + 1
  if (a.length === 0 || b.length === 0) return Math.max(a.length, b.length)

  let beforePrevious = null
  let previous = Array.from({length: b.length + 1}, (_value, index) => index)

  for (let i = 1; i <= a.length; i++) {
    const current = [i]
    let best = i

    for (let j = 1; j <= b.length; j++) {
      const substitution = previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)
      let value = Math.min(current[j - 1] + 1, previous[j] + 1, substitution)

      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        value = Math.min(value, beforePrevious[j - 2] + 1)
      }

      current[j] = value
      if (value < best) best = value
    }

    // Every alignment from here on is at least this far out.
    if (best > max) return max + 1
    beforePrevious = previous
    previous = current
  }

  return previous[b.length]
}

// Below four letters a single edit reaches too many different words: "cat"
// would match "cut", "car", "can" and "hat" at once.
const TYPO_MIN_LENGTH = 4
const TYPO_RANK = 5

const typoBudget = (length) => (length >= 7 ? 2 : 1)

// How badly the reader would have had to mistype to have meant this row.
// Null when they could not reasonably have meant it.
const typoDistance = (entry, needle) => {
  const budget = typoBudget(needle.length)
  const {title, keywordWords: words} = prepare(entry)
  const candidates = [title, ...title.split(WORD_SPLIT), ...words]

  let best = null
  for (const candidate of candidates) {
    if (candidate.length < TYPO_MIN_LENGTH) continue
    const distance = editDistance(needle, candidate, budget)
    if (distance <= budget && (best === null || distance < best)) best = distance
  }

  return best
}

export const isQueryAction = (entry) =>
  typeof entry?.href === "string" && entry.href.includes(QUERY_TOKEN)

// How much of a keyword has to match for the reader to have meant it.
//
// A language name is almost never typed in the form the index holds. Romance
// and Germanic readers inflect it ("spaniolă" becomes "în spaniolă"), and
// Slavic, Finnish, Hungarian and Turkish readers write a form the citation
// name does not contain at all — Polish "hiszpański" becomes "po
// hiszpańsku", Finnish "espanja" becomes "espanjaksi". Across the fifteen
// locales I checked, comparing whole words caught nine; comparing the first
// five letters caught all fifteen. Five is also long enough that no two
// language names on the site share a prefix by accident.
const STEM_LENGTH = 5

const sharesStem = (a, b) =>
  a.length >= STEM_LENGTH && b.length >= STEM_LENGTH && a.slice(0, STEM_LENGTH) === b.slice(0, STEM_LENGTH)

// A keyword can be a phrase ("Español (España)"), and the reader types one
// word of it.
const keywordWords = (entry) => {
  const keywords = Array.isArray(entry.keywords) ? entry.keywords : []
  const words = []
  for (const keyword of keywords) {
    for (const word of normalizeQuery(keyword).split(WORD_SPLIT)) {
      if (word) words.push(word)
    }
  }
  return words
}

// A scoped action can also be summoned by naming its language in the query
// ("casa spanish"). The name is then not part of what you are searching for,
// so it comes out of the query the action is given.
const keywordMatch = (entry, words) => {
  for (const keyword of keywordWords(entry)) {
    const index = words.findIndex((word) => word === keyword || sharesStem(word, keyword))
    if (index !== -1) return index
  }
  return -1
}

// The connector the reader put between the word and the language: "in",
// "în", "auf", "po", "på", or Dutch's two-word "in het".
//
// A closed list, and not a rule about length. "short word next to the
// language name" looked like it would save maintaining one, until "to go in
// spanish" came back as a search for "to" — "go" is two letters and sits
// exactly where a connector sits. There is no shape that separates them, so
// this names them. Being wrong about a word costs one worse query; eating a
// word the reader typed costs them the answer.
//
// Accent-folded, because that is the form they are compared in. Deliberately
// missing: "de", which is a connector in three languages and a word people
// search for in more.
const CONNECTORS = new Set([
  "in", "into", "to", "the", "at",
  "la", "al", "el",
  "auf", "ins", "im", "nach",
  "en", "dans", "au",
  "nel", "nella",
  "em", "no", "na",
  "po", "w", "v", "do", "ke",
  "pa", "paa", "till",
  "het", "naar",
  "dalam", "bang", "sang",
  "mein", "par",
  // Not every locale writes its connector in Latin script. Russian hyphenates
  // ("по-испански"), which the word split turns into a connector of its own.
  "по", "на", "в", "с",
  "στα", "στη", "στον", "σε",
])

const MAX_CONNECTORS = 2

const withoutLanguage = (words, at) => {
  const rest = words.slice()
  rest.splice(at, 1)

  let removed = 0
  let index = at - 1

  // Right to left from where the name was, stopping at the first word that is
  // not a connector — so a connector behind a real word is never reached.
  while (removed < MAX_CONNECTORS && rest.length > 1 && index >= 0 && CONNECTORS.has(rest[index])) {
    rest.splice(index, 1)
    removed += 1
    index -= 1
  }

  return rest.join(" ")
}

const substitute = (value, query) => {
  if (typeof value !== "string") return value
  return value.split(QUERY_TOKEN).join(query)
}

const resolveAction = (entry, query) => ({
  ...entry,
  title: substitute(entry.title, query),
  subtitle: substitute(entry.subtitle, query),
  href: entry.href.split(QUERY_TOKEN).join(encodeURIComponent(query)),
})

// Query actions, in the order they should be offered:
//   1. one whose keyword the reader typed (and that word leaves the query),
//   2. the scoped ones, in scope order — page language first, then recents,
//   3. the unscoped fallback, but only when nothing above matched.
const actionsFor = (entries, rawQuery, scopes) => {
  const query = String(rawQuery).trim()
  if (query === "") return []

  const actions = entries.filter(isQueryAction)
  if (actions.length === 0) return []

  const words = normalizeQuery(query).split(WORD_SPLIT).filter(Boolean)
  const chosen = []
  const taken = new Set()

  for (const entry of actions) {
    // A stem is loose enough that two languages can answer one word
    // ("portugheza" and "portugheza braziliana"). A couple of those is
    // helpful; ten is a list of every language that starts the same way.
    if (chosen.length >= MAX_NAMED_LANGUAGES) break
    if (!entry.scope) continue

    const at = keywordMatch(entry, words)
    if (at === -1) continue

    const remaining = withoutLanguage(words, at)
    // Naming a language and nothing else is not a search for a word.
    if (remaining === "") continue

    chosen.push(resolveAction(entry, remaining))
    taken.add(entry.href)
  }

  for (const scope of scopes) {
    for (const entry of actions) {
      if (entry.scope !== scope || taken.has(entry.href)) continue
      chosen.push(resolveAction(entry, query))
      taken.add(entry.href)
    }
  }

  if (chosen.length === 0) {
    for (const entry of actions) {
      if (entry.scope) continue
      chosen.push(resolveAction(entry, query))
    }
  }

  return chosen
}

/**
 * The rows to show for a query: ranked destinations, then query actions.
 *
 * An empty query lists the first `limit` destinations in the order the host
 * gave them — the palette opens showing where you can go, not a blank box.
 */
export const searchEntries = (entries, query, options = {}) => {
  const list = Array.isArray(entries) ? entries : []
  const limit = options.limit || RESULT_LIMIT
  const scopes = Array.isArray(options.scopes) ? options.scopes : []
  const destinations = list.filter((entry) => !isQueryAction(entry))
  const needle = normalizeQuery(query)

  if (needle === "") return destinations.slice(0, limit)

  const ranked = []
  destinations.forEach((entry, index) => {
    const rank = rankEntry(entry, needle)
    if (rank < 4) ranked.push([rank, index, entry])
  })

  // Only when nothing matched honestly. Run alongside the real tiers, a typo
  // guess would push its way in front of a word the reader actually typed —
  // and here it cannot, because there is nothing to push in front of.
  if (ranked.length === 0 && needle.length >= TYPO_MIN_LENGTH) {
    destinations.forEach((entry, index) => {
      const distance = typoDistance(entry, needle)
      if (distance !== null) ranked.push([TYPO_RANK + distance, index, entry])
    })
  }

  // Sort is stable on rank, so the host's own order breaks ties.
  ranked.sort((a, b) => a[0] - b[0] || a[1] - b[1])

  const hits = ranked.slice(0, limit).map((row) => row[2])
  return hits.concat(actionsFor(list, query, scopes))
}

// ── the palette itself ─────────────────────────────────────────────────────

const indexCache = new Map()

const loadIndex = (url) => {
  if (!indexCache.has(url)) {
    indexCache.set(
      url,
      fetch(url, {headers: {accept: "application/json"}, credentials: "same-origin"})
        .then((response) => (response.ok ? response.json() : null))
        .then((body) => ({
          entries: Array.isArray(body?.entries) ? body.entries : [],
          scopes: Array.isArray(body?.scopes) ? body.scopes : [],
        }))
        // A failed index costs the palette, nothing else: it opens, says there
        // is nothing, and the page underneath is untouched.
        .catch(() => ({entries: [], scopes: []})),
    )
  }
  return indexCache.get(url)
}

// The page publishes what it is about (a language, a section) on <html>, which
// no LiveView patch can reach. The server's suggestions come after, so a page
// with an opinion wins over a saved preference.
const currentScopes = (doc, serverScopes) => {
  const published = String(doc.documentElement?.dataset?.gamendSearchScopes || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean)

  return [...new Set(published.concat(serverScopes))].slice(0, 6)
}

export function startSearchPalette(doc = typeof document === "undefined" ? null : document) {
  if (!doc || doc.__gamendSearchPaletteBound) return
  doc.__gamendSearchPaletteBound = true

  const dialogFor = () => doc.querySelector("dialog[data-gamend-search]")

  let index = {entries: [], scopes: []}
  let loaded = false
  let rows = []
  let active = -1

  // Rows the browser cannot work out for itself, keyed by the query that
  // asked for them: a reply that arrives after the next keystroke answers a
  // question nobody is asking any more.
  let live = {query: "", rows: []}
  let liveTimer = null

  const setActive = (next) => {
    if (rows.length === 0) {
      active = -1
      return
    }

    active = (next + rows.length) % rows.length

    rows.forEach((row, position) => {
      const selected = position === active
      row.setAttribute("aria-selected", selected ? "true" : "false")
      row.classList.toggle("menu-active", selected)
      if (selected) {
        row.id = row.id || `gamend-search-option-${position}`
        row.scrollIntoView({block: "nearest"})
      }
    })

    const input = dialogFor()?.querySelector("[data-gamend-search-input]")
    if (input) input.setAttribute("aria-activedescendant", rows[active]?.id || "")
  }

  // One keystroke is not a search, and a fetch per keystroke is not one
  // either. 160 ms is about a fast typist's gap between letters.
  const LIVE_DEBOUNCE_MS = 160
  const LIVE_MIN_LENGTH = 2

  const requestLive = (dialog, rawQuery) => {
    const url = dialog.dataset.queryUrl
    const query = String(rawQuery).trim()

    if (!url) return
    if (query.length < LIVE_MIN_LENGTH) {
      live = {query: "", rows: []}
      return
    }
    if (live.query === query) return

    clearTimeout(liveTimer)
    liveTimer = setTimeout(() => {
      const scopes = currentScopes(doc, index.scopes).join(",")
      const separator = url.includes("?") ? "&" : "?"
      const target = `${url}${separator}q=${encodeURIComponent(query)}&scopes=${encodeURIComponent(scopes)}`

      fetch(target, {headers: {accept: "application/json"}, credentials: "same-origin"})
        .then((response) => (response.ok ? response.json() : null))
        .then((body) => {
          const open = dialogFor()
          const input = open?.querySelector("[data-gamend-search-input]")
          // Another keystroke landed while this was in flight.
          if (!input || String(input.value).trim() !== query) return

          live = {query, rows: Array.isArray(body?.entries) ? body.entries : []}
          if (open.open) render(open)
        })
        .catch(() => {})
    }, LIVE_DEBOUNCE_MS)
  }

  // Draw, then ask for what could not be drawn. Kept apart so that rendering
  // the reply cannot ask for it again.
  const refresh = (dialog) => {
    render(dialog)
    requestLive(dialog, dialog.querySelector("[data-gamend-search-input]")?.value || "")
  }

  const render = (dialog) => {
    const input = dialog.querySelector("[data-gamend-search-input]")
    const list = dialog.querySelector("[data-gamend-search-results]")
    const empty = dialog.querySelector("[data-gamend-search-empty]")
    const groupTemplate = dialog.querySelector("template[data-gamend-search-group]")
    const rowTemplate = dialog.querySelector("template[data-gamend-search-row]")
    if (!input || !list || !rowTemplate) return

    const query = input.value || ""
    const matches = searchEntries(index.entries, query, {
      scopes: currentScopes(doc, index.scopes),
    })

    // Server rows go under the ones matched here: those were instant and
    // these were not, so anything that jumped the queue would move under the
    // reader's cursor a moment after they could already act on it.
    const seen = new Set(matches.map((entry) => entry.href))
    const fresh =
      live.query === query.trim() ? live.rows.filter((row) => row && !seen.has(row.href)) : []

    list.replaceChildren()
    rows = []

    let group = null
    matches.concat(fresh).forEach((entry, position) => {
      if (groupTemplate && entry.group && entry.group !== group) {
        group = entry.group
        const heading = groupTemplate.content.cloneNode(true)
        const label = heading.querySelector("[data-group-label]")
        if (label) label.textContent = entry.group
        list.appendChild(heading)
      }

      const fragment = rowTemplate.content.cloneNode(true)
      const link = fragment.querySelector("a")
      if (!link) return

      link.href = entry.href
      link.id = `gamend-search-option-${position}`
      link.setAttribute("aria-selected", "false")

      const title = fragment.querySelector("[data-row-title]")
      if (title) title.textContent = entry.title || ""

      const subtitle = fragment.querySelector("[data-row-subtitle]")
      if (subtitle) subtitle.textContent = entry.subtitle || ""

      list.appendChild(fragment)
      rows.push(link)
    })

    const hasRows = rows.length > 0
    const waiting = live.query !== query.trim() && Boolean(dialog.dataset.queryUrl)
    list.hidden = !hasRows
    // Not while an index or a query is still in flight: on a cold server that
    // can take seconds, and "No results." is a wrong answer, not a slow one.
    if (empty) empty.hidden = hasRows || !loaded || waiting || query.trim() === ""
    input.setAttribute("aria-expanded", hasRows ? "true" : "false")

    setActive(0)
  }

  // Below this the palette is the full-width sheet the stylesheet describes:
  // a panel hanging off a button needs room beside the button, and a phone has
  // none. Matches Tailwind's `sm`, which is where the rest of the shell splits.
  const ANCHOR_MIN_WIDTH = 640
  const PANEL_WIDTH = 448
  const VIEWPORT_MARGIN = 16
  const BUTTON_GAP = 8

  const view = () => doc.defaultView

  // Hang the dialog under the button that opened it. A modal `<dialog>` is in
  // the top layer, so `position: fixed` here is relative to the viewport and
  // these four properties are the whole of the placement.
  const anchor = (dialog) => {
    const window_ = view()
    const button = doc.querySelector("[data-gamend-search-open]")
    const rect = button?.getBoundingClientRect()

    // No window, no button, or a button that is not currently laid out (inside
    // a closed hamburger, say): leave the sheet the stylesheet gives us.
    if (!window_ || !rect || rect.width === 0 || window_.innerWidth < ANCHOR_MIN_WIDTH) {
      for (const property of ["left", "right", "top", "width", "max-height"]) {
        dialog.style.removeProperty(property)
      }
      return
    }

    const width = Math.min(PANEL_WIDTH, window_.innerWidth - VIEWPORT_MARGIN * 2)

    // Aligned on the edge of the button the reader reads towards, so the panel
    // opens back across the page rather than off the side of it.
    const rtl = window_.getComputedStyle(doc.documentElement).direction === "rtl"
    const preferred = rtl ? rect.left : rect.right - width
    const furthest = window_.innerWidth - width - VIEWPORT_MARGIN

    dialog.style.left = `${Math.round(Math.max(VIEWPORT_MARGIN, Math.min(preferred, furthest)))}px`
    // `inset-x-0` in the class list pins both edges; the measured `left` only
    // wins if the other one lets go.
    dialog.style.right = "auto"
    const top = Math.round(rect.bottom + BUTTON_GAP)
    dialog.style.top = `${top}px`
    dialog.style.width = `${Math.round(width)}px`
    // Only as tall as the room under the button. A percentage of the viewport
    // cannot know where the panel starts, so on a short laptop screen the list
    // ran off the bottom with no way to reach the end of it.
    dialog.style.maxHeight = `${Math.max(0, window_.innerHeight - top - VIEWPORT_MARGIN)}px`
  }

  // The button moves under the palette when the window changes size, and on a
  // host whose header hides as you scroll it moves when the page does. One
  // frame at a time, and only while there is something to move.
  let anchorFrame = null

  const reanchor = () => {
    const dialog = dialogFor()
    if (!dialog?.open || anchorFrame !== null) return

    anchorFrame = view()?.requestAnimationFrame(() => {
      anchorFrame = null
      const current = dialogFor()
      if (current?.open) anchor(current)
    })
  }

  const open = async () => {
    const dialog = dialogFor()
    if (!dialog) return

    const input = dialog.querySelector("[data-gamend-search-input]")

    if (!dialog.open && typeof dialog.showModal === "function") dialog.showModal()
    anchor(dialog)
    if (input) {
      input.focus()
      input.select()
    }

    refresh(dialog)

    const url = dialog.dataset.indexUrl
    if (url) {
      index = await loadIndex(url)
      loaded = true
      // The dialog may have been closed while the index was in flight.
      if (dialog.open) render(dialog)
    }
  }

  const close = () => {
    const dialog = dialogFor()
    if (dialog?.open && typeof dialog.close === "function") dialog.close()
  }

  doc.addEventListener("click", (event) => {
    const target = event.target
    if (!target || typeof target.closest !== "function") return

    // The button is a toggle: it is the only thing on screen that says where
    // the palette is, so pressing it again to put it away is what a reader
    // expects — and it is outside the panel, so the rule below would otherwise
    // close and immediately reopen it.
    if (target.closest("[data-gamend-search-open]")) {
      event.preventDefault()
      if (dialogFor()?.open) close()
      else open()
      return
    }

    if (target.closest("[data-gamend-search-close]")) {
      close()
      return
    }

    // Anything that is not the panel is outside it. That includes the
    // `::backdrop`, which is a pseudo-element and so reports the `<dialog>`
    // itself as the target — the reason a plain "did the click land in the
    // panel" test covers clicking away, and the reason the daisyUI
    // `.modal-backdrop` div that used to sit here had to go: a real element
    // over the backdrop swallowed the click and nothing ever closed.
    if (dialogFor()?.open && !target.closest("[data-gamend-search-panel]")) close()
  })

  view()?.addEventListener("resize", reanchor)
  view()?.addEventListener("scroll", reanchor, {passive: true, capture: true})

  doc.addEventListener("input", (event) => {
    const target = event.target
    if (!target || typeof target.closest !== "function") return
    const dialog = target.closest("dialog[data-gamend-search]")
    if (dialog && target.matches("[data-gamend-search-input]")) refresh(dialog)
  })

  doc.addEventListener("keydown", (event) => {
    if (event.defaultPrevented || event.isComposing) return

    const dialog = dialogFor()
    const isOpen = Boolean(dialog?.open)

    if ((event.metaKey || event.ctrlKey) && !event.altKey && !event.shiftKey) {
      if (String(event.key).toLowerCase() !== "k") return
      // Another modal owns the keyboard while it is up — except this one,
      // where a second press means "I am already here, let me retype".
      if (!isOpen && doc.querySelector("dialog[open]")) return

      event.preventDefault()
      if (isOpen) {
        const input = dialog.querySelector("[data-gamend-search-input]")
        input?.focus()
        input?.select()
      } else {
        open()
      }
      return
    }

    if (!isOpen || event.metaKey || event.ctrlKey || event.altKey) return

    if (event.key === "Escape") {
      // `<input type="search">` eats the first Escape to clear itself, and the
      // cursor is always in it — so the dialog's own Esc never fired and the
      // palette could only be closed with the mouse.
      event.preventDefault()
      close()
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      setActive(active + 1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      setActive(active - 1)
    } else if (event.key === "Enter") {
      // The rows are real links, so "activate the selection" is a click on
      // one — middle-click and ⌘-click on the same element still work the way
      // the browser makes them work.
      const row = rows[active]
      if (row) {
        event.preventDefault()
        row.click()
      }
    }
  })
}
