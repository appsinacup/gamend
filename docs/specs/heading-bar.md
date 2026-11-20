# The heading is the bar

Design spec for moving Polyglot Pirates' heading bar (2026-11-20) into core, so
every host (Polyglot Pirates, Gamend Cloud, Forge, a new host) gets it from one
setting. Status: **proposal**. Polyglot Pirates runs a host-side version today;
this spec is what it takes to make it core's and to switch Cloud and Forge to it.

## Goal

On every page with a heading, the page's heading row **is** the navbar:

- **Phone (under `sm`):** no top navbar. The heading row takes the navbar's
  surface and hairline. It starts with the way home when the page has no Back,
  and ends with a … menu holding what the navbar held (the wallet, the
  account, the theme, the site language). The tab bar stays at the bottom.
- **Tablet and desktop (`sm` up):** the navbar stays in the DOM but is bare. It
  has no surface, its logo and trail are not drawn, and only its end (the host's
  wallet, the theme, the site language, the account) lies over the end of the
  heading row. The bar box has the surface, sticks to the top as the navbar
  did, and keeps its end clear of the navbar's items.
- **Sidebar:** always there. From `md` up it is the sidebar; under `xl` it is
  only the rail; below `md` it is the tab bar.
- **Never cut:** the heading row is measured. When it would need its last
  ("cut") stage, the navbar falls to its avatar or its menu first.
- **Second row:** what a page puts beside its title (filters, actions) shares
  the bar's line while it fits, and wraps under the bar when it does not. It is
  never drawn under the navbar's items.
- **The home page** (and any page without a heading row) keeps the normal
  navbar.

## Why

- Pages get the navbar's 64 px of height back. On a phone the bar replaces two
  rows, the navbar and the heading.
- One row says where you are and how to switch: the section, the language, the
  topic and Back. The breadcrumb trail repeated it, and Polyglot Pirates dropped
  it (`config :gamend_web, :breadcrumbs, false`).
- A host with many sections (Polyglot Pirates: 9) keeps them in the sidebar, and
  the top of the page belongs to the page.

## What exists today

| Piece | Where | State |
|---|---|---|
| Sidebar is only the rail under 1280 px, its Collapse hidden there | core `side_nav.js`, `host_layout_navigation.ex` | built 2026-11-20 |
| The navbar leaves room for a page's row (`--nav-reserve` on `#main-navbar`, px) | core `navbar_fit.js` (`reserve/0`, `stageFor/3`) | built 2026-11-20 |
| `config :gamend_web, :breadcrumbs, false` | core `host_layout_shell.ex` | built 2026-11-20 |
| Core pages mark their title row `data-heading-fit` | core: Quests, Leaderboards, Notifications, settings, stats, store, redeem, report, `form_heading/1`, content pages | exists; title only, actions are siblings |
| The bar's CSS (phone bar, bare navbar, `main::before` band, second rows, `--bar-end` padding) | Polyglot `assets/css/app.css` *A phone's bar*, *The heading is the bar* | host-only |
| Heading fit stages, `--bar-end`, `barBox`, `--nav-reserve` writer | Polyglot `assets/js/host_hooks.js` (`startHeadingFit`) | host-only |
| Home link and … menu | Polyglot `HostUI.bar_home/1`, `HostWallet.bar_menu/1`, a word game's `round_menu/1` | host-only |
| Measured stage variants (`fit-icon:` … `fit-name:`) | Polyglot `app.css` *Heading fit* | host-only |

Gamend Cloud (`modules/cloud_config.json`: 5 links) and Forge
(`modules/forge_config.json`: 6 links) both run `"layout": "auto"`. With that
few links the auto layout usually puts the links in the **top bar**, not the
sidebar. Cloud has 7 pages with a title and none marks `data-heading-fit`. Forge
has 15, and 3 of them mark it.

## Architecture

### 1. One setting

```json
"navigation": { "layout": "auto", "heading_bar": true }
```

`HostLayouts.heading_bar?/1` reads it. It sets `<html data-heading-bar>`, which
every rule below is scoped under, so a host without it is unchanged. With
`heading_bar`, the sidebar is always the navigation from `md` up: the auto
layout's bar stages (links in the top bar) are skipped (`navbar_fit.js`
`stageFor/3` uses `SIDE_STAGES` only). That is the one behavioural change for
Cloud and Forge: their 5 to 6 links move to the sidebar.

### 2. One heading component

Core's pages today put `data-heading-fit` on a title-only `div` and their
actions beside it, in shapes that differ page to page. Polyglot's `barBox`
guesses the box: a `.flex` parent, or a `.flex` grandparent. Replace both with:

```heex
<.page_heading back={~p"/servers"} icon="hero-server-solid">
  Servers
  <:menus>…section, language, topic switchers…</:menus>
  <:actions>…filters, New server…</:actions>
  <:intro>One line under the bar.</:intro>
</.page_heading>
```

It draws one outer row (`data-bar-box`). Inside it are the measured heading row
(`data-heading-fit`: home or Back, the title, the menus) and the actions. On a
phone it adds the … menu, and under it the intro. `header/1` and
`form_heading/1` become thin wrappers. Every core page moves to it, so no page
hand-rolls a row. A host's own pages use it the same way. Polyglot's
`game_header/1` and `vocab_header/1` become callers.

`form_heading/1` is `sticky top-16` today, under a sticky navbar. With the bar
it becomes the bar itself, sticky at the top (decision 4).

### 3. Core owns the CSS and the script

- `gamend.css`: the phone bar, the bare navbar, the sticky bar box, the
  second row (`[data-bar-box]` flex-wrap with `padding-inline-end:
  var(--bar-end)`), and the fit stage variants. All are scoped to
  `[data-heading-bar]`.
- `heading_fit.js` (new, core): Polyglot's `startHeadingFit`, `fittingStage`,
  `barEnd`, `putBarEnd`, `stageNeed` and `putNavReserve` move here unchanged.
  `barBox` is dropped: the box is `[data-bar-box]`. Its unit tests
  (`host_hooks` heading tests) move with it.
- The stage list (`icon`, `lang`, `small`, `menus`, `smaller`, `name`, `cut`)
  becomes core's. A host's own controls opt in with the same `fit-*:` variants.

### 4. What the host plugs in

The … menu and the home link are core components. What goes in the … menu comes
from the navbar's existing entries:

- the wallet: the host's `"render"` entry (Polyglot `HostWallet.entry/1`),
  drawn with `variant: :menu`;
- the account links (`account_links`), the theme, the site language (core's
  `language_modal` opened from the menu), and Log in / Register for a visitor;
- the sections the tab bar leaves out (`"mobile": "hidden"`, decision 3).

So Polyglot's `HostWallet.bar_menu/1` and `HostUI.bar_home/1` go away, and Cloud
and Forge need no code for it.

### 5. Pages with no heading row

The home page, the blog index and an error page keep the navbar. The rule is the
same as today: `[data-heading-bar]` applies only where a `[data-bar-box]` exists.
The admin console (`/admin`) is its own layout and is out of scope.

## Per host

| Host | Change |
|---|---|
| Polyglot Pirates | Set `heading_bar`. Delete the host CSS blocks, the `startHeadingFit` additions, `bar_home`, `bar_menu`. Move `game_header/1`, `vocab_header/1`, the hubs, the Pirate Pass and ~12 other rows to `<.page_heading>`. Check at 375, 700, 820, 1024, 1280 and 1440 px with the overlap probe (below). |
| Gamend Cloud | Set `heading_bar`; the 5 links move to the sidebar. Move its 7 page titles to `<.page_heading>` (servers, server, new server, editor connect, admin machines, admin servers, components). |
| Forge | Set `heading_bar`; the 6 links move to the sidebar. Move its 15 page titles to `<.page_heading>`, the 3 that mark `data-heading-fit` first. |
| A new host | Gets it from `gamend_starter` with the setting on. |

## Checks

- **Overlap probe:** each page in iframes at 700, 820, 1024 and 1280 px,
  signed in and as a visitor. It samples the navbar's items area with
  `elementsFromPoint` and fails on anything of the page drawn there, and on a
  heading at its `cut` stage. Polyglot ran it by hand on 2026-11-20 (about 30
  pages). It becomes a script in core's `stress/pages` beside `bench.mjs`.
- Core's `js_test.exs` runs the moved heading-fit unit tests.
- `/ui` (core's UI page) shows `<.page_heading>` in each state: phone, with
  actions, wrapped, with a Back.

## Decisions (user, 2026-11-20)

1. **Sidebar for every host.** Cloud's and Forge's links move to the sidebar;
   `heading_bar` uses the sidebar stages only.
2. **The rail under 1280 px** for every host, as Polyglot has it.
3. **The phone's … menu holds the hidden sections:** the sections a host marks
   `"mobile": "hidden"` (Polyglot: Flashcards, Pirate Pass) are listed in it,
   so every section is reachable on a phone.
4. **The bar is sticky**, as the navbar was. It cannot be today: the heading
   row sits inside a `header` with its intro, and a sticky element sticks only
   within its parent. `<.page_heading>` draws the bar box as a direct child of
   the page's stack, with the intro after it, so the box is `sticky top-0`
   (its surface its own, no `main::before` band), and the bare navbar is
   sticky over its end. `form_heading/1`'s own sticky goes.
5. **Cached HTML after a deploy:** accepted. A page cached for an hour may load
   the previous release's scripts until it expires.

## Order

1. Core: `heading_bar` setting, `<.page_heading>`, the CSS and `heading_fit.js`
   in core behind `[data-heading-bar]`, the … menu from navbar entries. Move
   core's own pages to `<.page_heading>`. Release to Hex.
2. Polyglot: switch to the setting, delete the host copies, move its rows.
3. Forge, then Cloud: set the flag, move their titles, run the probe.
