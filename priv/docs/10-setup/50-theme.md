---
icon: hero-swatch
---

# Configure Theme

Runtime theming (JSON)

The host ships a default theme JSON for copy, navigation, footer sections, and reusable presentation pages. You can optionally override it at runtime with a different JSON file. Image fields may point at host-owned static assets, including GIFs.

## Configure theming JSON

Edit the packaged host default theme at theme/config.json, or place an override JSON file somewhere in your project. For example:

```text
theme/my_config.json
```

With the following:

Add presentation pages under pages. Each page needs a path; existing code-owned routes keep priority, and unmatched configured paths render through the shared presentation layout.

```text
title": "My Game", "tagline": "Play together", "theme_color": { "light": "#ffffff", "dark": "#1a1a2e,
  "pages": home": { "path": "/", "hero": { "title": "My Game", "text": "**Fast** multiplayer backend for [your game](/play).", "image": { "light": "/images/banner.gif", "alt": "My Game,
        "image_position_desktop": "left",
        "image_position_mobile": "top",
        "media_width": "half",
        "media_size": "section",
        "buttons": [
          label": "Play", "href": "/play", "icon": "hero-play-solid", "style": "primary
        ]
      },
      "sections_height": "half",
      "sections": [
        title": "Matchmaking", "text": "Real-time lobbies, parties, and custom rules.", "image": { "light": "/images/matchmaking.gif", "dark": "/images/matchmaking_dark.gif", "alt": "Matchmaking,
          "media_width": "third",
          "image_position_desktop": "right",
          "image_position_mobile": "top",
          "buttons": [
            label": "Docs", "href": "/docs/setup", "icon": "hero-book-open-solid
          ]
        },
        title": "Social", "text": "Friends, groups, chat, **leaderboards**, and quests.", "icon": "hero-user-group-solid", "height": "compact", "media_width": "third", "image_position_desktop": "left
      ]
    },
    "brand": path": "/brand", "hero": { "title": "Brand", "text": "Another page using the same hero and sections renderer.", "image": { "light": "/images/banner.gif", "alt": "Brand
      },
      "sections": []
    }
  },
  "navigation": primary_links": [ { "label": "Play", "href": "/play", "icon": "hero-play-solid,
      label": "Social", "icon": "hero-user-group-solid", "items": [ { "label": "Leaderboards", "href": "/leaderboards", "icon": "hero-chart-bar-solid,
          label": "Quests", "href": "/quests", "icon": "hero-trophy-solid,
          label": "Groups", "href": "/groups", "icon": "hero-user-group-solid
        ]
      }
    ],
    "guest_links": [
      label": "Guides", "href": "/docs/setup
    ],
    "authenticated_links": [
      label": "Dashboard", "href": "/dashboard
    ],
    "account_links": [
      label": "Billing", "href": "/billing,
      label": "Admin", "href": "/admin", "auth": "admin,
      label": "Support", "href": "https://discord.gg/example", "external": true } ] }, "footer": { "sections": [ { "title": "Social", "links": [ { "label": "Discord", "href": "https://discord.gg/example", "external": true }, { "label": "Blog", "href": "/blog
        ]
      },
      title": "Privacy & Terms", "links": [ { "label": "Privacy Policy", "href": "/privacy,
          label": "Terms and Conditions", "href": "/terms
        ]
      }
    ]
  }
}
```

Theme color (browser chrome)

## Browser theme color

The theme_color field tints the browser chrome (address bar, tab bar) in Safari and Chrome. You can set a single color string or an object with light and dark variants:

```text
// Single color for all modes:
"theme_color": "#1a1a2e"

// Separate light and dark:
"theme_color": light": "#ffffff", "dark": "#1a1a2e
```

## Configure the app to use it

Optional: point the runtime override at a different JSON file:

```bash
GAMEND_CONTENT_THEME_CONFIG=theme/my_config.json
```

That exact file is the only one loaded — there is no per-locale variant. When GAMEND_CONTENT_THEME_CONFIG is not set, the host falls back to its packaged default theme under theme/.

## Translating the theme

Write the theme once, in English, and translate it through gettext like the rest of the UI. Text keys (title, tagline, description, label, text, alt, site_message, cta, subtitle) are translatable; everything else — colours, hrefs, icons, image paths, layout — is configuration and can never vary by locale.

```bash
mix gamend.theme.extract
mix gettext.merge priv/gettext
```

Then translate priv/gettext/LOCALE/LC_MESSAGES/theme.po. A missing translation falls back to the English source, so a partly translated locale still renders.

## Host-owned branding and content

Branding behavior is host-owned. The host layout decides which logo, banner, favicon, and CSS are used at runtime. Presentation media can use an image object for PNG/JPG/GIF assets, or omit image and set icon to render a plain icon.

Set image.light for the default presentation image, image.dark for a dark-mode variant, and image.alt for alt text.

Set media_width for the image/text column ratio. Set media_size to hero or section when a hero should use hero-sized or section-sized media.

Presentation media is visual only. Use buttons for links and calls to action.

Edit assets/css/app.css when you want to change the full base stylesheet. The compiled bundle is written to priv/static/assets/css/app.css. Use priv/static/theme.css for a small layer of token or color overrides without forking the whole base CSS.

Changelog, roadmap, and blog pages are host-owned, and their Markdown content now lives at the repository root as CHANGELOG.md, ROADMAP.md, and blog/. They are no longer configured through GAMEND_CONTENT_THEME_CONFIG.

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
"navigation": primary_links": [ { "label": "Status", "href": "/status,
    label": "Social", "items": [ { "label": "Leaderboards", "href": "/leaderboards,
        label": "Groups", "href": "/groups
      ]
    }
  ],
  "authenticated_links": [
    label": "Dashboard", "href": "/dashboard
  ],
  "account_links": [
    label": "Billing", "href": "/billing,
    { "label": "Admin", "href": "/admin", "admin_only": true }
  ]
}
```
