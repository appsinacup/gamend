// Core's own CSS: the classes core's templates use, for every host's
// stylesheet to load rather than copy. A host loads it as it loads daisyUI,
// through a one-line wrapper in its `assets/vendor` that finds this file in
// the sibling checkout or under deps (`resolve_gamend_web_vendor.js`):
//
//     // assets/vendor/gamend.js
//     module.exports = require(require("./resolve_gamend_web_vendor")("gamend.js"))
//
//     /* assets/css/app.css, after daisyUI */
//     @plugin "../vendor/gamend";
//
// A new class core needs lands here, and every host has it with its next
// core release. Before 2026-11-11 each host copied these blocks into its
// `app.css`, and the copies drifted: the starter had lost three of them.
//
// What it gives (each documented beside its rules below):
//   btn-surface   the secondary button
//   card-hover    how a card answers the pointer
//   text-muted    the second text tone, and daisyUI's own muted text in it
//   max-w-narrow  the one narrow width
//   nudge         the page's one next step, moving
//   icon-mask     an icon drawn from its file, in the text's colour

const plugin = require("tailwindcss/plugin")

const chevron = (path) =>
  `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill-rule='evenodd' d='${path}'/%3E%3C/svg%3E")`

// Heroicons' solid chevrons, the hero's scroll cue.
const CHEVRON_RIGHT = chevron(
  "M16.28 11.47a.75.75 0 0 1 0 1.06l-7.5 7.5a.75.75 0 0 1-1.06-1.06L14.69 12 7.72 5.03a.75.75 0 0 1 1.06-1.06l7.5 7.5Z"
)
const CHEVRON_DOWN = chevron(
  "M12.53 16.28a.75.75 0 0 1-1.06 0l-7.5-7.5a.75.75 0 0 1 1.06-1.06L12 14.69l6.97-6.97a.75.75 0 1 1 1.06 1.06l-7.5 7.5Z"
)
const CHEVRON_LEFT = chevron(
  "M7.72 12.53a.75.75 0 0 1 0-1.06l7.5-7.5a.75.75 0 1 1 1.06 1.06L9.31 12l6.97 6.97a.75.75 0 1 1-1.06 1.06l-7.5-7.5Z"
)

// animate-bounce's two curves: away slows down, back speeds up.
const EASE_OUT = "cubic-bezier(0, 0, 0.2, 1)"
const EASE_IN = "cubic-bezier(0.8, 0, 1, 1)"
const RING_OUT = "cubic-bezier(0.2, 0.7, 0.2, 1)"
const SLIDE = "cubic-bezier(0.4, 0, 0.2, 1)"

module.exports = plugin(
  function ({ addBase, addComponents, addUtilities }) {
    /* `icon-mask`: one of the site's icons drawn from its file
       (`GamendWeb.Icons.draw_path/1`, set as `--icon-src` by
       `<.entity_icon>`), masked over `currentColor` so it follows the theme
       and the browser fetches it once. A component, so a utility beside it
       (`w-6`, `hidden`, `inline-block`) wins. Laid out as the inline SVG it
       replaced (2026-11-12): a block, as Tailwind's base sets an `svg`, that
       a flex row does not shrink. Nothing shows until the file arrives. */
    /* The page's shell unseen while the navbar has no widths measured for
       its language (`<html data-nav-fit="pending">`, `navbar_fit.js`): a
       first visit is drawn once, at the stage that fits, not at a guess the
       sidebar's room then moves (2026-11-12). Shown by the fit before the
       first paint, else at the latest after two seconds. */
    addBase({
      '[data-nav-fit="pending"] :has(> #main-navbar)': {
        visibility: "hidden",
        animation: "nav-fit-reveal 0s 2s forwards"
      },
      "@keyframes nav-fit-reveal": { to: { visibility: "visible" } }
    })

    addComponents({
      ".icon-mask": {
        display: "block",
        "flex-shrink": "0",
        "vertical-align": "middle",
        "background-color": "currentColor",
        "-webkit-mask": "var(--icon-src) center / contain no-repeat",
        mask: "var(--icon-src) center / contain no-repeat"
      }
    })

    /* `btn-surface`: the secondary button, beside `btn-primary`. The page's
       own colour behind a dark hairline (2026-09-30, it replaced
       `btn-outline`'s white border). It sets the RESTING fill and border and
       nothing else, as daisyUI builds `btn-outline` and `btn-soft`, so
       hover, focus, active, disabled and sizes are `btn`'s own, and the text
       colour is left alone (`text-error` beside it just works). A utility, so
       `sm:btn-surface` works: `btn-ghost sm:btn-surface` is an icon alone on
       a phone and this from `sm` up. */
    addUtilities({
      ".btn-surface": {
        "&:not(.btn-active, :hover, :active:focus, :focus-visible, :disabled, [disabled], .btn-disabled)":
          {
            "--btn-bg": "var(--color-base-100)",
            "--btn-border": "var(--color-base-300)"
          }
      }
    })

    /* `card-hover`: how a card answers the pointer. A card is a box that is
       one link or one click (a tile, a topic, a Continue card, a blog post):
       it rises 2 px and takes a shadow, a primary edge and the base-200 fill.
       A control (a button, a chip, a row, a key) never rises: it changes
       colour and presses, as daisyUI's `btn` does (2026-10-17: one hover for
       cards, one for controls). A card whose own fill is base-200 or a tint
       names its hover fill with `hover:bg-*`. A card with a button of its own
       beside it (the X on a recent card) sits in a `group/card` parent, so
       the card stays up while the X is under the pointer. Hover only where a
       pointer hovers, the rise only where motion is welcome. */
    addUtilities({
      ".card-hover": {
        "transition-property": "color, background-color, border-color, box-shadow, translate",
        "transition-duration": "var(--motion-ease, 120ms)",
        "transition-timing-function": "ease",
        "@media (hover: hover)": {
          "&:hover, :where(.group\\/card):hover > &": {
            "@apply border-primary/40 bg-base-200 shadow-md": {}
          }
        },
        "@media (hover: hover) and (prefers-reduced-motion: no-preference)": {
          "&:hover, :where(.group\\/card):hover > &": {
            "@apply -translate-y-0.5": {}
          }
        },
        "@media (prefers-reduced-motion: reduce)": {
          transition: "none"
        }
      }
    })

    /* `text-muted`: the site's second text tone, for a detail under
       something. Text is `text-base-content` or this, nothing else: the
       lightest tone that reads at 4.5:1 on every base of both themes (`/60`
       was 4.46 on the light base-200; Lighthouse, 2026-10-08), and one name
       means a page cannot pick its own shade. A utility, so variants work. */
    addUtilities({
      ".text-muted": {
        color: "color-mix(in oklab, var(--color-base-content) 70%, transparent)"
      }
    })

    /* daisyUI's own muted text in the same tone: table heads, stat and
       fieldset labels at 60%, an inactive tab at 50%, a menu title at 40%
       read below 4.5:1 on the light theme (a table head 4.47 on base-200, a
       tab 3.29). Among the utilities, so it beats daisyUI's sub-layers and a
       colour class on the element still applies. */
    addUtilities({
      ".table :where(thead, tfoot), .fieldset-label, .stat-title, .stat-desc, .menu-title, .tab:is(.tabs > .tab):not(:checked, label:has(:checked), :hover, .tab-active, [aria-selected=\"true\"], [aria-current=\"true\"], [aria-current=\"page\"])":
        {
          color: "color-mix(in oklab, var(--color-base-content) 70%, transparent)"
        }
    })

    /* `nudge`: the one next step on a screen (2026-11-11). The class goes on
       the primary button or card a reader should press next, one a screen:
       a language to pick, Start, the next game, Claim, New server. A chevron
       (the hero's scroll cue, `animate-bounce`'s curves) bounces before it,
       pointing at it, and on every second landing a ring grows out of its
       edge. `nudge-top` puts the chevron above it, pointing down: a card in a
       grid. Both take the primary colour, or `--nudge-color` where the step
       wears another (a Claim in the success colour).

       The site picks the move in its theme JSON, `"nudge": {"move",
       "rhythm"}`, which core writes on <html> as `data-nudge` and
       `data-nudge-rhythm` (`GamendWeb.HostLayouts.nudge/0`). The move is
       `pointer`, `ring`, `hop` or `shine`, or `pointer` with one of the other
       three; unset, `pointer ring`. The rhythm: `always`, a 2 s beat, two
       landings and the effect on the second; `rest`, two landings, the
       effect, then still (3.2 s). One timeline drives both halves, so the
       effect lands on the beat. It starts 0.8 s after the element appears
       and never pauses. Reduced motion: a steady ring and the chevron
       standing still. */
    addUtilities({
      ".nudge": {
        position: "relative",
        "--nudge-ring":
          "color-mix(in oklch, var(--nudge-color, var(--color-primary)) 75%, transparent)",
        "--nudge-away": "translateX(-0.45rem)",
        "--nudge-knock": "translateX(0.25rem)",
        "--nudge-time": "2s",
        "--nudge-beat": "nudge-beat",
        "--nudge-ring-move": "nudge-ring",
        "--nudge-knock-move": "nudge-knock",
        "--nudge-shine-move": "nudge-shine"
      },
      ".nudge::after": {
        content: '""',
        position: "absolute",
        "inset-inline-end": "calc(100% + 0.25rem)",
        top: "50%",
        width: "1.5rem",
        height: "1.5rem",
        "margin-top": "-0.75rem",
        display: "none",
        "pointer-events": "none",
        "background-color": "var(--nudge-color, var(--color-primary))",
        mask: `${CHEVRON_RIGHT} center / contain no-repeat`
      },
      ".nudge-top": {
        "--nudge-away": "translateY(-0.45rem)",
        "--nudge-knock": "translateY(0.25rem)"
      },
      ".nudge-top::after": {
        "inset-inline-end": "auto",
        "inset-inline-start": "50%",
        top: "auto",
        bottom: "calc(100% + 0.125rem)",
        "margin-top": "0",
        "margin-inline-start": "-0.75rem",
        "mask-image": CHEVRON_DOWN
      },
      '[dir="rtl"] .nudge:not(.nudge-top)': {
        "--nudge-away": "translateX(0.45rem)",
        "--nudge-knock": "translateX(-0.25rem)"
      },
      '[dir="rtl"] .nudge:not(.nudge-top)::after': {
        "mask-image": CHEVRON_LEFT
      },
      '[data-nudge-rhythm="rest"] .nudge': {
        "--nudge-time": "3.2s",
        "--nudge-beat": "nudge-beat-rest",
        "--nudge-ring-move": "nudge-ring-rest",
        "--nudge-knock-move": "nudge-knock-rest",
        "--nudge-shine-move": "nudge-shine-rest"
      },
      '[data-nudge~="pointer"] .nudge::after': {
        display: "block",
        "@media (prefers-reduced-motion: no-preference)": {
          animation: "var(--nudge-beat) var(--nudge-time) 0.8s infinite"
        }
      },
      '[data-nudge~="ring"] .nudge': {
        "@media (prefers-reduced-motion: no-preference)": {
          animation: "var(--nudge-ring-move) var(--nudge-time) 0.8s infinite"
        }
      },
      // Hop alone: the step does the bounce itself. With the pointer:
      // knocked away from it on the second landing.
      '[data-nudge="hop"] .nudge': {
        "@media (prefers-reduced-motion: no-preference)": {
          "--nudge-away": "translateY(-0.3rem)",
          animation: "var(--nudge-beat) var(--nudge-time) 0.8s infinite"
        }
      },
      '[data-nudge~="pointer"][data-nudge~="hop"] .nudge': {
        "@media (prefers-reduced-motion: no-preference)": {
          animation: "var(--nudge-knock-move) var(--nudge-time) 0.8s infinite"
        }
      },
      // A light under the label: a background layer, so nothing clips the
      // pointer outside the element.
      '[data-nudge~="shine"] .nudge': {
        "@media (prefers-reduced-motion: no-preference)": {
          "background-image":
            "linear-gradient(105deg, transparent 38%, color-mix(in oklab, white 40%, transparent) 50%, transparent 62%)",
          "background-size": "250% 100%",
          "background-repeat": "no-repeat",
          "background-position": "170% 0",
          animation: "var(--nudge-shine-move) var(--nudge-time) 0.8s infinite"
        }
      },
      "[data-nudge] .nudge": {
        "@media (prefers-reduced-motion: reduce)": {
          "box-shadow": "0 0 0 3px var(--nudge-ring)"
        }
      }
    })

    // Always lands at 50% and 100%, the effect at 50%; rest lands at 30%
    // and 60%, the effect at 60%, then still.
    const beat = (lands) => {
      const [first, second] = lands
      const away = (at) => `${at}%`
      const frames = {
        "0%": { transform: "none", "animation-timing-function": EASE_OUT },
        [away(first / 2)]: { transform: "var(--nudge-away)", "animation-timing-function": EASE_IN },
        [`${first}%`]: { transform: "none", "animation-timing-function": EASE_OUT },
        [away(first + (second - first) / 2)]: {
          transform: "var(--nudge-away)",
          "animation-timing-function": EASE_IN
        }
      }

      frames[second === 100 ? "100%" : `${second}%, 100%`] = { transform: "none" }
      return frames
    }

    const ring = (at, end) => ({
      [`0%, ${at}%`]: {
        "box-shadow": "0 0 0 0 var(--nudge-ring)",
        "animation-timing-function": RING_OUT
      },
      [`${end}%, 100%`]: { "box-shadow": "0 0 0 0.75rem transparent" }
    })

    const knock = (at, peak, end) => ({
      [`0%, ${at}%`]: { transform: "none", "animation-timing-function": "cubic-bezier(0.2, 0.8, 0.4, 1)" },
      [`${peak}%`]: { transform: "var(--nudge-knock)", "animation-timing-function": SLIDE },
      [`${end}%, 100%`]: { transform: "none" }
    })

    const shine = (at, end) => ({
      [`0%, ${at}%`]: { "background-position": "170% 0", "animation-timing-function": SLIDE },
      [`${end}%, 100%`]: { "background-position": "-70% 0" }
    })

    addBase({
      "@keyframes nudge-beat": beat([50, 100]),
      "@keyframes nudge-ring": ring(50, 85),
      "@keyframes nudge-knock": knock(50, 55, 68),
      "@keyframes nudge-shine": shine(50, 85),
      "@keyframes nudge-beat-rest": beat([30, 60]),
      "@keyframes nudge-ring-rest": ring(60, 82),
      "@keyframes nudge-knock-rest": knock(60, 63, 71),
      "@keyframes nudge-shine-rest": shine(60, 82)
    })
  },
  {
    /* `max-w-narrow`: the one width a page narrows a block to (a form, a
       game board, a card, an article). 48rem is the column's own `md`
       width, so it only narrows from `lg` up. */
    theme: { extend: { maxWidth: { narrow: "48rem" } } }
  }
)
