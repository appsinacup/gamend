---
icon: hero-swatch
---

# Configure Theme

The host ships a default theme JSON for copy, navigation, footer sections, and reusable presentation pages. You can optionally override it at runtime with a different JSON file. Image fields may point at host-owned static assets, including GIFs.

## Configure theming JSON

Edit the packaged host default theme at theme/config.json, or place an override JSON file somewhere in your project. For example:

```text
theme/my_config.json
```

Add presentation pages under `pages`. Each page needs a `path`; existing code-owned routes keep priority, and unmatched configured paths render through the shared presentation layout. A full example:

```json
{
  "title": "My Game",
  "tagline": "Play together",
  "theme_color": {
    "light": "#ffffff",
    "dark": "#1a1a2e"
  },
  "pages": {
    "home": {
      "path": "/",
      "hero": {
        "title": "My Game",
        "text": "**Fast** multiplayer backend for [your game](/play).",
        "image": {
          "light": "/images/banner.gif",
          "alt": "My Game"
        },
        "image_position_desktop": "left",
        "image_position_mobile": "top",
        "media_width": "half",
        "media_size": "section",
        "buttons": [
          {
            "label": "Play",
            "href": "/play",
            "icon": "hero-play-solid",
            "style": "primary"
          }
        ]
      },
      "sections_height": "half",
      "sections": [
        {
          "title": "Matchmaking",
          "text": "Real-time lobbies, parties, and custom rules.",
          "image": {
            "light": "/images/matchmaking.gif",
            "dark": "/images/matchmaking_dark.gif",
            "alt": "Matchmaking"
          },
          "media_width": "third",
          "image_position_desktop": "right",
          "image_position_mobile": "top",
          "buttons": [
            {
              "label": "Docs",
              "href": "/docs/setup",
              "icon": "hero-book-open-solid"
            }
          ]
        },
        {
          "title": "Social",
          "text": "Friends, groups, chat, **leaderboards**, and quests.",
          "icon": "hero-user-group-solid",
          "height": "compact",
          "media_width": "third",
          "image_position_desktop": "left"
        }
      ]
    },
    "brand": {
      "path": "/brand",
      "hero": {
        "title": "Brand",
        "text": "Another page using the same hero and sections renderer.",
        "image": {
          "light": "/images/banner.gif",
          "alt": "Brand"
        }
      },
      "sections": []
    }
  },
  "navigation": {
    "primary_links": [
      { "label": "Play", "href": "/play", "icon": "hero-play-solid" },
      {
        "label": "Social",
        "icon": "hero-user-group-solid",
        "items": [
          { "label": "Leaderboards", "href": "/leaderboards", "icon": "hero-chart-bar-solid" },
          { "label": "Quests", "href": "/quests", "icon": "hero-trophy-solid" },
          { "label": "Groups", "href": "/groups", "icon": "hero-user-group-solid" }
        ]
      }
    ],
    "guest_links": [
      { "label": "Guides", "href": "/docs/setup" }
    ],
    "authenticated_links": [
      { "label": "Dashboard", "href": "/dashboard" }
    ],
    "account_links": [
      { "label": "Billing", "href": "/billing" },
      { "label": "Admin", "href": "/admin", "auth": "admin" },
      { "label": "Support", "href": "https://discord.gg/example", "external": true }
    ]
  },
  "footer": {
    "sections": [
      {
        "title": "Social",
        "links": [
          { "label": "Discord", "href": "https://discord.gg/example", "external": true },
          { "label": "Blog", "href": "/blog" }
        ]
      },
      {
        "title": "Privacy & Terms",
        "links": [
          { "label": "Privacy Policy", "href": "/privacy" },
          { "label": "Terms and Conditions", "href": "/terms" }
        ]
      }
    ]
  }
}
```

## Browser theme color

The theme_color field tints the browser chrome (address bar, tab bar) in Safari and Chrome. You can set a single color string or an object with light and dark variants:

```text
// Single color for all modes:
"theme_color": "#1a1a2e"

// Separate light and dark:
"theme_color": { "light": "#ffffff", "dark": "#1a1a2e" }
```

## Contact email

The contact_email field is the address the Privacy Policy, Data Deletion and Terms pages give for privacy and deletion requests, as a mailto link. App stores and data-protection rules expect a real address there. Without it, those pages only say to use "support channels".

```text
"contact_email": "support@example.com"
```

## Configure the app to use it

Optional: point the runtime override at a different JSON file:

```bash
GAMEND_CONTENT_THEME_CONFIG=theme/my_config.json
```

That exact file is the only one loaded; there is no per-locale variant. When GAMEND_CONTENT_THEME_CONFIG is not set, the host falls back to its packaged default theme under theme/.

## Translating the theme

Write the theme once, in English, and translate it through gettext like the rest of the UI. Text keys (title, tagline, description, label, text, alt, cta, subtitle) are translatable; everything else (colours, hrefs, icons, image paths, layout) is configuration and can never vary by locale.

```bash
mix gamend.theme.extract
mix gettext.merge priv/gettext
```

Then translate priv/gettext/LOCALE/LC_MESSAGES/theme.po. A missing translation falls back to the English source, so a partly translated locale still renders.

## Host-owned branding and content

Branding behavior is host-owned. The host layout decides which logo, banner, favicon, and CSS are used at runtime. A top-level `logo_dark` names the mark the navbar shows on the dark theme, for a logo drawn in colours that vanish on a dark page; without it the one `logo` serves both. Presentation media can use an image object for PNG/JPG/GIF assets, or omit image and set icon to render a plain icon.

Set image.light for the default presentation image, image.dark for a dark-mode variant, and image.alt for alt text.

Set media_width for the image/text column ratio. Set media_size to hero or section when a hero should use hero-sized or section-sized media.

Presentation media is visual only. Use buttons for links and calls to action.

Edit assets/css/app.css when you want to change the full base stylesheet. The compiled bundle is written to priv/static/assets/css/app.css. Use priv/static/theme.css for a small layer of token or color overrides without forking the whole base CSS.

Changelog, roadmap, and blog pages are host-owned, and their Markdown content now lives at the repository root as CHANGELOG.md, ROADMAP.md, and blog/. They are no longer configured through GAMEND_CONTENT_THEME_CONFIG.

### Your own static files

Put images, a `game/` web export, a favicon or a `theme.css` in a static folder of your project and the server serves them ahead of its own. A file at the same path as a built-in one replaces it: `static/images/banner.webp` is what `/images/banner.webp` returns, and the page links and hashes your file, not the engine's.

The folders are `GAMEND_CONTENT_STATIC_DIRS`, comma-separated, relative to the working directory and searched in order: `static,priv/static` by default. Each is used if it exists when the server starts or `gamend reload` runs.

Only the top-level entries of `:host_static_paths` are served from it (`images/`, `game/`, `favicon.ico`, `robots.txt`, `llms.txt`, `.well-known/`, `theme.css`), with the same cache headers as the built-in ones; `assets/` is always the engine's. A folder that is the app's own `priv/static`, as `priv/static` is when you run `mix phx.server` from this repository, is not served twice. After creating the folder, or adding or replacing a file that pages link (`theme.css`, the logo, theme images), run `gamend reload` (from a [download](/docs/standalone)) or restart the server so the pages link the new file.

Theme images may list `"widths": [480, 960]`: the page then offers `banner-480.webp` and `banner-960.webp` beside `banner.webp` in a `srcset`, but only the ones that exist in the same folder as the original, so a missing variant is never a broken image. `mix host.responsive_images` cuts them into `priv/static` at build time. For your own static folder the server cuts the missing ones itself, at start and after `gamend reload`, next to the original, when ImageMagick is installed (`magick`, or `convert` outside Windows). Without it the server logs once that it skipped them and pages serve the full-size image. A variant is never wider or heavier than its original.

### Markdown content

Every collection — the guides, the blog, the changelog — renders through one pipeline. A file may open with a `---` frontmatter block of `key: value` lines, `[a, b]` flow lists and `- a` block lists; nothing nested. Headings get ids, so `#section` links and a table of contents work. Footnotes render. An admonition is written either way and looks the same:

```
:::tip[For animators]
The clip plays on its own.
:::

> [!WARNING]
> This deletes the project.
```

A ```` ```mermaid ```` fence becomes a diagram, drawn by the `MermaidDiagram` hook when the page loads. A fixed set of raw HTML passes the sanitiser — `<figure>`, `<video>`, `<details>`, a `<div class>`, an inline `<svg>` — so a guide can hold a clip or a gallery; anything that runs is stripped.

#### Guides

A collection registered with `nesting: :tree` (`Gamend.Content.register_path/2`) reads folders at any depth. A folder is a category; its `_category.md` frontmatter gives it a `title`, `icon`, `color`, `position`, `description` and `collapsed`. An `index.md` in a folder is the category's own page. A file's slug is its path with each segment's numeric prefix stripped: `10-manual/20-scenes.md` is `manual/scenes`. Frontmatter on a guide: `title`, `description`, `sidebar_label` (or `label`), `position` (or `sidebar_position`), `slug` (`/reference` for the whole thing), `image`, `keywords`, `icon`. A name beginning with `_` is not a page.

With `base_path: "/docs"`, a link to a neighbouring file — `[Scenes](./scenes.md#nodes)`, `[Reference](../reference/index.md)` — is rewritten to that guide's route. With `assets: :static`, an image at a root-absolute path such as `/img/x.png` is left for `priv/static` to serve; relative paths still go through `/content/<collection>/`.

`use GamendWeb.DocsLive, layout: :sidebar` renders such a collection with the tree beside every page, a table of contents, breadcrumbs, a landing page per category and an "Edit this page" link (`edit_url:`); route it as `live "/docs/*path"`. The default `:cards` layout is the one-level index gamend's own guides use.

#### Blog

A post's frontmatter may give `title`, `slug`, `date`, `description`, `authors`, `image`, `keywords` and `tags`; without it, the first `# ` heading and the `YYYY-MM-DD-slug.md` filename still work. `authors: [dragos]` is resolved from `blog/_authors/dragos.md` (`name`, `title`, `url`, `image`). `<!-- truncate -->` marks where the excerpt ends. Feeds are at `/blog/rss.xml` and `/blog/atom.xml`.

The index is a grid of cards, grouped by year and month: one to a row on a phone, two on a tablet, three on a desktop. Each card shows the post's picture above its date, reading time, title, excerpt and authors. The picture is the frontmatter `image`, else the first picture in the post; a relative path is served from `/content/blog/` like the body's. The post page opens with the description, else the first paragraph, and shows the frontmatter `image` above the body only when the body does not already show it.

A host with smaller copies of its pictures registers the blog with `image_url: {MyHost.BlogImages, :url}` (`Gamend.Content.register_path/2`). It is called as `url(url, use)` for each picture the blog serves itself, and answers the URL to serve instead: `use` is `:card` on the index and `:page` on the post. `post_render:` runs on a post's HTML as it does on a guide's.

#### Pages

Register a `:pages` collection (`nesting: :tree`, `base_path: "/"`) and a markdown file answers its path with nothing routed: `content/pages/faq.md` is `/faq`, `content/pages/help/install.md` is `/help/install`. `layout: wide` in its frontmatter widens the frame.

## Configure navigation

Use the navigation object to move nav structure into config. Each section accepts normal links, or dropdown groups with an items array. primary_links render in the main nav for everyone, guest_links render only for signed-out visitors, authenticated_links render only for signed-in users, and account_links render inside the account dropdown. Notifications, locale switching, theme toggling, and logout stay code-owned.

| Section | Description |
|---|---|
| `primary_links` | Always-visible main nav links |
| `guest_links` | Additional links shown only to signed-out visitors |
| `authenticated_links` | Additional links shown only to signed-in users |
| `account_links` | Custom links inserted into the account dropdown |

| Property | Type | Description |
|---|---|---|
| `label` | string | Text displayed in the nav bar |
| `items` | array | Optional child links. When present, entry renders as a dropdown group instead of a direct link. |
| `href` | string | URL — can be an absolute path (internal) or a full URL (external) |
| `external` | boolean | When true, opens in a new tab with rel="noopener noreferrer" |
| `auth` | string | Visibility level: `"any"` — visible to everyone (default) `"unauthenticated"` — visible only to signed-out visitors `"authenticated"` — visible only to logged-in users `"admin"` — visible only to admin users |
| `admin_only` | boolean | Shortcut for auth="admin" on links or dropdown groups. |

Example: grouped public links plus admin-only account entry:

```text
"navigation": {
  "primary_links": [
    { "label": "Status", "href": "/status" },
    {
      "label": "Social",
      "items": [
        { "label": "Leaderboards", "href": "/leaderboards" },
        { "label": "Groups", "href": "/groups" }
      ]
    }
  ],
  "authenticated_links": [
    { "label": "Dashboard", "href": "/dashboard" }
  ],
  "account_links": [
    { "label": "Billing", "href": "/billing" },
    { "label": "Admin", "href": "/admin", "admin_only": true }
  ]
}
```

## Site search

Every page carries a magnifier in the header and answers Ctrl/Cmd+K with a search palette. Out of the box it searches your navigation: the links you configured above, flattened so a page two taps deep in a phone's hamburger menu is one query away.

Search is on by default. Turn it off with:

```elixir
config :gamend_web, :search_provider, false
```

That removes the button, the dialog and the index endpoint together.

### Putting your own content in it

Point the setting at a module implementing `GamendWeb.SearchIndex.Provider`:

```elixir
config :gamend_web, :search_provider, MyApp.Search
```

```elixir
defmodule MyApp.Search do
  @behaviour GamendWeb.SearchIndex.Provider

  @impl true
  def entries(context) do
    GamendWeb.SearchIndex.navigation_entries(context) ++
      Enum.map(MyApp.guides(), fn guide ->
        %{title: guide.title, href: "/guides/#{guide.slug}", group: "Guides"}
      end)
  end
end
```

`entries/1` is called once per palette open, with `%{scope: current_scope, locale: locale}`. Use `scope` to leave out what the reader cannot open; `locale` is the language to translate titles into, and gettext is already set to it.

| Key | Required | What it is |
|---|---|---|
| `title` | yes | What the row says |
| `href` | yes | A clean path (`/guides/intro`) or a full URL. Core adds the locale prefix |
| `group` | no | The heading the row sits under. Rows keep the order you return them in |
| `subtitle` | no | Shown greyed at the end of the row. Its words are matched too, below titles and keywords |
| `keywords` | no | Also matched, never shown — alternate names, codes, spellings |
| `scope` | no | See below |

Titles, subtitles and group labels are the reader's words: translate them in the provider.

A match on the title ranks first, then a keyword, then a whole word (or the start of one) in the subtitle. A query with a separator in it, `utf-8`, is matched as a phrase.

This site's own provider (`GamendHost.Search`) offers every guide, every blog post, and every `##` and `###` section of every guide, linked to its heading. A section's subtitle is its guide's title and the first sentence of the section, which is how a word that appears only in a guide's body can still be found: put it in the section's opening sentence. A guide or post can also list `keywords:` in its frontmatter, and they are matched like any keyword:

```markdown
---
keywords: [utf8, unicode]
---
```

### Cost

The palette fetches the index once and filters it in the browser, so typing sends no request (unless the provider answers live queries, below). On the server, the index is built from memory: `GamendHost.Search` keeps its content rows until the content reloads (`Gamend.Content.memoize/2`), so opening the palette costs a cache read and the navigation for whoever is reading. The browser keeps the index for `GAMEND_SEARCH_INDEX_MAX_AGE_SECONDS` (default 600) and then asks again with its ETag; an index that has not changed answers `304` with no body. The cache is private because the navigation and the scopes depend on who is reading.

An entry whose `href` contains `{q}` is a search rather than a destination: the palette substitutes what was typed and offers it under the page hits. That is how a query the palette cannot answer itself reaches a page that can.

```elixir
%{title: "Spanish", subtitle: "Search: {q}", href: "/vocabulary/spanish?q={q}",
  scope: "es_es", keywords: ["Spanish", "Español"]}
```

Which of these are offered is decided by scope, most relevant first:

1. one whose `keywords` the reader typed — `casa spanish` searches Spanish for `casa`, with the language name taken out of the query;
2. the ones matching a current scope, in scope order;
3. entries with no `scope` at all, but only when neither of the above matched.

Scopes come from two places, page first. A page says what it is about by setting `data-gamend-search-scopes` on `<html>` (a comma-separated list, most relevant first) — outside every LiveView, so a patch cannot clear it. The optional `scopes/1` callback adds the server's own suggestions after, which is where a signed-in reader's saved preference belongs.

### Things too numerous to put in the index

The index is everything worth offering before anyone types, and it is sent whole. Some content is too large for that — a dictionary, a product catalogue, a message archive. Add an optional `search/2` and the palette will ask per query instead:

```elixir
@impl true
def search(query, context) do
  Enum.map(MyApp.find(query, context[:scopes]), fn hit ->
    %{title: hit.name, subtitle: hit.summary, href: "/things/#{hit.id}", group: "Things"}
  end)
end
```

Rows come back in the same shape as an index entry and are shown below the ones the browser matched locally, in their own groups. The call is debounced, so it arrives once a reader stops typing rather than once per key, and `context[:scopes]` carries what they most likely mean, most likely first.

Order matters and is deliberate: local matches stay on top. They were instant and these were not, so anything that jumped the queue would move under the reader's cursor a moment after they could already act on it.

Leave the callback out and the palette searches its index and nothing else, which is the whole feature for most hosts.

### How it is served

The palette fetches `/search/index.json?locale=<locale>` once per page load, on first open, and filters it in the browser. A host with `search/2` also gets `/search/query.json?q=…&scopes=…&locale=…`, cached for a minute rather than ten. The locale is a parameter rather than a path prefix on purpose: a prefixed URL would store that locale in the session, and a background fetch must not decide what language the reader's next page arrives in.

### Spelling, and what the reader actually typed

The palette does three things before deciding a query matches nothing:

- **Names are matched on their first five letters.** A language, a country or a product is rarely typed in the form an index holds it in — "spaniolă" is written "în spaniolă", Polish "hiszpański" becomes "po hiszpańsku". Whole-word comparison caught nine of the fifteen locales tested; five letters caught all fifteen.
- **The connector between a word and a name is dropped**, so "casa in spanish" searches for "casa" and not "casa in". A closed list, because there is no shape that tells "in" from "go".
- **A typo is worth one edit on a short word and two on a long one**, tried only when nothing matched honestly, and never below four letters. Two letters swapped count as one edit, not two: that is the difference between reading "hosue" as "house" and offering "hose".
