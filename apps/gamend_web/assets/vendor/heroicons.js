const plugin = require("tailwindcss/plugin")
const crypto = require("crypto")
const fs = require("fs")
const path = require("path")

// The heroicons dep of the project Tailwind runs in: a host's `deps/` (the
// CLI runs from the project's root, the tailwind profile's `cd`), else this
// umbrella's, else a dep's own. `gamend.css` loads this for every host.
const candidates = [
  path.join(process.cwd(), "deps/heroicons/optimized"),
  path.join(__dirname, "../../../../deps/heroicons/optimized"),
  path.join(__dirname, "../../deps/heroicons/optimized")
]

// Each class's suffix, its folder in the dep, and where the site serves the
// file (`GamendWeb.Plugs.Icons`): the 24px solid set at `/icons/<name>.svg`,
// the URL `<.entity_icon>` draws too, so a browser keeps one copy of it.
const sets = [
  ["", "/24/outline", "/icons/outline/"],
  ["-solid", "/24/solid", "/icons/"],
  ["-mini", "/20/solid", "/icons/mini/"],
  ["-micro", "/16/solid", "/icons/micro/"]
]

// A `hero-*` class is a mask of the icon's FILE, not of a data URI
// (2026-11-12): the icons were 44% of the stylesheet every page waits for
// (239 of 546 KB, 28 of 65 KB compressed), and each change to the stylesheet
// sent them all again. A file is fetched once, when a page first shows it,
// and kept: its URL carries its content hash, the one
// `GamendWeb.Icons.draw_path/1` computes, so a new heroicons release is a new
// URL. Nothing shows until the file arrives.
module.exports = plugin(function({matchComponents, theme}) {
  let iconsDir = candidates.find(dir => fs.existsSync(dir))
  if (!iconsDir) {
    throw new Error(`Could not locate Heroicons. Tried: ${candidates.join(", ")}`)
  }
  let values = {}
  sets.forEach(([suffix, dir, at]) => {
    fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
      let name = path.basename(file, ".svg") + suffix
      values[name] = {name, fullPath: path.join(iconsDir, dir, file), url: at + file}
    })
  })
  matchComponents({
    "hero": ({name, fullPath, url}) => {
      let hash = crypto
        .createHash("sha256")
        .update(fs.readFileSync(fullPath))
        .digest("base64url")
        .slice(0, 8)
      let size = theme("spacing.6")
      if (name.endsWith("-mini")) {
        size = theme("spacing.5")
      } else if (name.endsWith("-micro")) {
        size = theme("spacing.4")
      }
      return {
        [`--hero-${name}`]: `url(${url}?v=${hash})`,
        "-webkit-mask": `var(--hero-${name})`,
        "mask": `var(--hero-${name})`,
        "mask-repeat": "no-repeat",
        "background-color": "currentColor",
        "vertical-align": "middle",
        "display": "inline-block",
        "width": size,
        "height": size
      }
    }
  }, {values})
})
