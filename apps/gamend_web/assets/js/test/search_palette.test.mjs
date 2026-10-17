// The search palette's matching rules, which are the part of it a person
// actually experiences: what comes first, and which "search for this" row is
// offered for a word the palette itself cannot look up.

import {test, describe} from "node:test"
import assert from "node:assert/strict"

import {
  normalizeQuery,
  fieldRank,
  rankEntry,
  isQueryAction,
  searchEntries,
  editDistance,
} from "../search_palette.js"

const page = (title, extra = {}) => ({title, href: `/${title.toLowerCase()}`, ...extra})

const action = (scope, keywords = []) => ({
  title: scope,
  href: `/vocabulary/${scope}?q={q}`,
  subtitle: "Search: {q}",
  scope,
  keywords,
})

describe("normalizeQuery", () => {
  test("folds case, accents and surrounding space", () => {
    assert.equal(normalizeQuery("  Español "), "espanol")
    assert.equal(normalizeQuery("CAFÉ"), "cafe")
  })

  test("survives the things a caller might pass by accident", () => {
    assert.equal(normalizeQuery(null), "")
    assert.equal(normalizeQuery(undefined), "")
    assert.equal(normalizeQuery(42), "42")
  })
})

describe("fieldRank", () => {
  test("ranks exact, prefix, whole word and substring in that order", () => {
    assert.equal(fieldRank("Guide", "guide"), 0)
    assert.equal(fieldRank("Guidelines", "guide"), 1)
    assert.equal(fieldRank("The player guide", "guide"), 2)
    assert.equal(fieldRank("Misguided", "guide"), 3)
    assert.equal(fieldRank("Blog", "guide"), 4)
  })

  test("a hyphen or a bracket still leaves a whole word", () => {
    assert.equal(fieldRank("word-search", "search"), 2)
    assert.equal(fieldRank("to brush (one's teeth)", "teeth"), 2)
  })
})

describe("rankEntry", () => {
  test("a title match outranks a keyword match of the same tier", () => {
    const byTitle = page("Spanish")
    const byKeyword = {title: "Mexico", href: "/mexico", keywords: ["spanish"]}

    assert.ok(rankEntry(byTitle, "spanish") < rankEntry(byKeyword, "spanish"))
  })

  test("a keyword is still a way to be found", () => {
    const entry = {title: "Spanish", href: "/s", keywords: ["Español", "es_es"]}

    assert.ok(rankEntry(entry, "espanol") < 4)
    assert.equal(rankEntry(entry, "portugues"), 4)
  })

  test("a subtitle word finds a row, below any title or keyword hit", () => {
    const section = {
      title: "Usernames",
      href: "/docs/authentication#usernames",
      subtitle: "Authentication · Handles are UTF-8 (utf8) text in one script.",
    }
    const byKeyword = {title: "Encodings", href: "/e", keywords: ["utf8"]}

    assert.ok(rankEntry(section, "utf8") < 4)
    assert.ok(rankEntry(section, "utf-8") < 4, "a phrase with a separator counts too")
    assert.ok(rankEntry(section, "handl") < 4, "the start of a word counts")
    assert.ok(rankEntry(byKeyword, "utf8") < rankEntry(section, "utf8"))
  })

  test("a subtitle matches whole words and their starts, never the middle of one", () => {
    const entry = {title: "Lobbies", href: "/l", subtitle: "Hidden lobbies never appear in lists."}

    assert.equal(rankEntry(entry, "idden"), 4)
    assert.ok(rankEntry(entry, "hidd") < 4)
  })

  test("a subtitle is not searched for one or two letters", () => {
    const entry = {title: "Lobbies", href: "/l", subtitle: "Hidden lobbies never appear in lists."}

    assert.equal(rankEntry(entry, "hi"), 4)
  })

  test("a row ranks the same the second time, from what it remembered", () => {
    const entry = {title: "Parties", href: "/p", keywords: ["group"], subtitle: "Invite-only crews."}

    assert.equal(rankEntry(entry, "crews"), rankEntry(entry, "crews"))
    assert.equal(rankEntry(entry, "group"), rankEntry(entry, "group"))
  })
})

describe("searchEntries", () => {
  const entries = [
    page("Play"),
    page("Leaderboards"),
    page("Guide"),
    page("Guidelines"),
    page("Blog"),
  ]

  test("an empty query opens on the host's own order", () => {
    const shown = searchEntries(entries, "")

    assert.deepEqual(
      shown.map((entry) => entry.title),
      ["Play", "Leaderboards", "Guide", "Guidelines", "Blog"],
    )
  })

  test("the word you typed beats the word that merely contains it", () => {
    const shown = searchEntries(entries, "guide")

    assert.deepEqual(
      shown.map((entry) => entry.title),
      ["Guide", "Guidelines"],
    )
  })

  test("ranking happens before the limit, not after", () => {
    const noise = Array.from({length: 30}, (_value, index) => page(`Guidebook${index}`))
    const shown = searchEntries(noise.concat([page("Guide")]), "guide", {limit: 5})

    assert.equal(shown[0].title, "Guide")
    assert.equal(shown.length, 5)
  })

  test("ties keep the order the host gave", () => {
    const shown = searchEntries([page("Guidebook"), page("Guidelines")], "guide")

    assert.deepEqual(
      shown.map((entry) => entry.title),
      ["Guidebook", "Guidelines"],
    )
  })

  test("nothing matching is nothing shown", () => {
    assert.deepEqual(searchEntries(entries, "zzzz"), [])
  })

  test("a missing index is not a crash", () => {
    assert.deepEqual(searchEntries(null, "guide"), [])
    assert.deepEqual(searchEntries(undefined, ""), [])
  })
})

describe("query actions", () => {
  const entries = [page("Play"), action("spanish", ["Spanish", "Español", "es_es"]), action("french", ["French", "Français"])]

  test("are not offered for an empty query", () => {
    assert.deepEqual(searchEntries(entries, "", {scopes: ["spanish"]}), [entries[0]])
  })

  test("follow the scope order: the page's language, then what you last picked", () => {
    const shown = searchEntries(entries, "casa", {scopes: ["french", "spanish"]})

    assert.deepEqual(
      shown.map((entry) => entry.href),
      ["/vocabulary/french?q=casa", "/vocabulary/spanish?q=casa"],
    )
  })

  test("substitute the query into the href, the title and the subtitle", () => {
    const [row] = searchEntries(entries, "casa nueva", {scopes: ["spanish"]})

    assert.equal(row.href, "/vocabulary/spanish?q=casa%20nueva")
    assert.equal(row.subtitle, "Search: casa nueva")
  })

  test("naming a language in the query summons it and leaves the query", () => {
    const shown = searchEntries(entries, "casa spanish", {scopes: ["french"]})

    assert.equal(shown[0].href, "/vocabulary/spanish?q=casa")
    // The scope's own row is still there, and still searching for the whole
    // thing — the reader may have meant a word that happens to be a language.
    assert.equal(shown[1].href, "/vocabulary/french?q=casa%20spanish")
  })

  test("a named language is matched on any of its keywords, accents folded", () => {
    const [row] = searchEntries(entries, "casa espanol", {scopes: []})

    assert.equal(row.href, "/vocabulary/spanish?q=casa")
  })

  test("naming a language and nothing else is not a search", () => {
    assert.deepEqual(searchEntries([entries[1]], "spanish", {scopes: []}), [])
  })

  test("the fallback shows only when no scoped action did", () => {
    const fallback = {title: "All languages", href: "/vocabulary?q={q}"}
    const list = [entries[1], fallback]

    assert.deepEqual(
      searchEntries(list, "casa", {scopes: []}).map((entry) => entry.href),
      ["/vocabulary?q=casa"],
    )

    assert.deepEqual(
      searchEntries(list, "casa", {scopes: ["spanish"]}).map((entry) => entry.href),
      ["/vocabulary/spanish?q=casa"],
    )
  })

  test("a scope with no action of its own is skipped quietly", () => {
    const shown = searchEntries(entries, "casa", {scopes: ["klingon", "spanish"]})

    assert.deepEqual(
      shown.map((entry) => entry.href),
      ["/vocabulary/spanish?q=casa"],
    )
  })

  test("are told apart from destinations by the token in the href", () => {
    assert.ok(isQueryAction(entries[1]))
    assert.ok(!isQueryAction(entries[0]))
    assert.ok(!isQueryAction({}))
    assert.ok(!isQueryAction(null))
  })

  test("a destination is never ranked out by an action", () => {
    const shown = searchEntries(entries, "play", {scopes: ["spanish"]})

    assert.equal(shown[0].title, "Play")
  })
})


describe("naming the language in the query", () => {
  // The names as the index holds them, and the form a reader of that locale
  // actually types. Nine of these fifteen are not the same string.
  const languages = [
    {name: "Spaniolă", typed: "casă în spaniolă"},
    {name: "Spanisch", typed: "Haus auf Spanisch"},
    {name: "espagnol", typed: "maison en espagnol"},
    {name: "español", typed: "casa en español"},
    {name: "spagnolo", typed: "casa in spagnolo"},
    {name: "espanhol", typed: "casa em espanhol"},
    {name: "hiszpański", typed: "dom po hiszpańsku"},
    {name: "испанский", typed: "дом по-испански"},
    {name: "іспанська", typed: "дім іспанською"},
    {name: "španělština", typed: "dům španělsky"},
    {name: "spanyol", typed: "ház spanyolul"},
    {name: "espanja", typed: "talo espanjaksi"},
    {name: "İspanyolca", typed: "ev İspanyolca"},
    {name: "Spaans", typed: "huis in het Spaans"},
    {name: "spanska", typed: "hus på spanska"},
  ]

  for (const {name, typed} of languages) {
    test(`"${typed}" reaches the ${name} search, without the connector`, () => {
      const action = {
        title: name,
        href: "/vocabulary/spanish?q={q}",
        scope: "es_es",
        keywords: [name],
      }
      // No scopes: the only way this row can appear is by being named.
      const [row] = searchEntries([action], typed, {scopes: []})

      assert.ok(row, `nothing offered for "${typed}"`)
      const query = decodeURIComponent(row.href.split("?q=")[1])
      // Whatever is left is the word, and never the language or the word
      // joining it.
      assert.equal(query.split(/\s+/).length, 1, `left over: "${query}"`)
    })
  }

  test("a short word is kept when it is all the reader typed", () => {
    const action = {title: "Spanish", href: "/v/es?q={q}", scope: "es", keywords: ["Spanish"]}
    const [row] = searchEntries([action], "cat in spanish", {scopes: []})

    assert.equal(row.href, "/v/es?q=cat")
  })

  test("a word that happens to be short is not eaten as a connector", () => {
    const action = {title: "Spanish", href: "/v/es?q={q}", scope: "es", keywords: ["Spanish"]}
    const [row] = searchEntries([action], "to go in spanish", {scopes: []})

    assert.equal(decodeURIComponent(row.href.split("?q=")[1]), "to go")
  })

  test("a phrase keyword is matched one word at a time", () => {
    const action = {
      title: "Spanish",
      href: "/v/es?q={q}",
      scope: "es",
      keywords: ["Español (España)"],
    }
    const [row] = searchEntries([action], "casa en espanol", {scopes: []})

    assert.equal(row.href, "/v/es?q=casa")
  })

  test("only a few languages answer one stem, not every language sharing it", () => {
    const actions = ["a", "b", "c", "d", "e"].map((suffix) => ({
      title: `Portuguese ${suffix}`,
      href: `/v/pt-${suffix}?q={q}`,
      scope: `pt_${suffix}`,
      keywords: [`portugheza ${suffix}`],
    }))
    const rows = searchEntries(actions, "casa portugheza", {scopes: []})

    assert.ok(rows.length <= 3, `offered ${rows.length}`)
  })
})

describe("typos", () => {
  const pages = [
    {title: "Clasamente", href: "/leaderboards"},
    {title: "Season Pass", href: "/season_pass"},
    {title: "Spaniolă", href: "/vocabulary/spanish", keywords: ["Spanish"]},
  ]

  test("a dropped letter still finds the page", () => {
    const [row] = searchEntries(pages, "clasamete")

    assert.equal(row.href, "/leaderboards")
  })

  test("a swapped letter still finds the page", () => {
    const [row] = searchEntries(pages, "clasmaente")

    assert.equal(row.href, "/leaderboards")
  })

  test("a keyword can be the thing mistyped", () => {
    const [row] = searchEntries(pages, "spansh")

    assert.equal(row.href, "/vocabulary/spanish")
  })

  test("a real match is never displaced by a guess", () => {
    const rows = searchEntries(pages.concat([{title: "Clase", href: "/clase"}]), "clas")

    // "clas" is a prefix of both, so neither is a typo and both rank honestly.
    assert.ok(rows.every((row) => row.href !== "/season_pass"))
  })

  test("three letters are too few to guess from", () => {
    // Not "cla", which is an honest prefix of Clasamente and needs no guess.
    assert.deepEqual(searchEntries(pages, "cls"), [])
  })

  test("a word nobody mistyped finds nothing", () => {
    assert.deepEqual(searchEntries(pages, "xyzzy"), [])
  })
})

describe("editDistance", () => {
  test("counts the edits", () => {
    assert.equal(editDistance("casa", "casa", 2), 0)
    assert.equal(editDistance("casa", "cosa", 2), 1)
    assert.equal(editDistance("casa", "cosas", 2), 2)
  })

  test("two letters swapped is one edit, not two", () => {
    // At a budget of 1 this is the whole difference between reading "hosue"
    // as "house" and offering "hose".
    assert.equal(editDistance("hosue", "house", 1), 1)
    assert.ok(editDistance("hosue", "hose", 1) >= 1)
  })

  test("gives up rather than finishing a walk it cannot use", () => {
    assert.ok(editDistance("casa", "elephant", 2) > 2)
    assert.ok(editDistance("", "casa", 2) > 2)
  })
})
