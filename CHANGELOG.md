# October 2026

- [added] **Stripe payments, end to end.** Buyers refund within 14 days, resume a cancelled renewal and upgrade to a longer plan; checkouts can start with a free period; an hourly sweep catches lost webhooks; `mix gamend.stripe.setup` configures the account; payments are counted and logged. Disputes, refunds and failed renewals now end access properly, and a player opens one checkout at a time. **Hosts:** set the Stripe webhook to API version `2025-11-17.clover` (or run the setup task).
- [added] **Reports.** Players report problems from `/report` or the API, admins work the queue at `/admin/reports`, and a host can add its own report kinds.
- [added] **Per-account preferences.** Notification choices per group and channel, with email and one-click unsubscribe; time zone, language and theme follow the account.
- [added] **Guest accounts on the website**, kept when the visitor registers or signs in.
- [added] **Leaderboards hold several rankings per board and can be hidden.**
- [added] **Website feature switches**: the store, chat, groups, tournaments and the payments catalog and checkout API can be turned off on the site while the game keeps them.
- [added] **Smaller additions**: crawler statistics in Admin → Geo, FAQ sections on presentation pages, rate-limit-exempt IPs, KV pruning by prefix, slow query logging, and `Accounts.update_user_metadata/2`.
- [breaking] **Registering takes no password**: the emailed code confirms the address and sets it. A crashing game hook answers 500 without details.
- [changed] **Faster pages.** Links between pages reuse the open connection, settings and quests read less, and repeated per-user reads are cached.
- [added] **A Back button on every page**: `<.back_link>` and `home_path/0` in `CoreComponents`, at the start of each title row, and `<.header back_href=…>` for a plain page. Pages one step under home go home in the reader's locale.
- [changed] **Layout and accessibility.** Three page widths, breadcrumbs in the navbar, a navbar that fits a phone, and fixes from a Lighthouse pass. **Hosts:** declare `text-muted` and `--container-narrow` in your stylesheet, as `assets/css/app.css` does.
- [changed] **Version 1.1**: releases are `1.1.<commit count>`, read from the new `VERSION` file.
- [fixed] **`Sitemap.Cache.prune/0` reads every page of the storage listing**, so a host with over a thousand sitemap files no longer keeps every old signature.
- [fixed] **Races and stale data.** A revoked login, a balance or a KV value could stay cached for a minute; waiting on a lock no longer stalls for seconds; group admins, party invites, lobby leaders and rows deleted mid-request no longer leave bad state or answer 500. Scheduled hooks reach plugins again.

# September 2026

- [added] **Gamend as a download**: server binaries and a `gamend` command, with a project's own static files and plugins served from where it runs.
- [added] **A C++ SDK**, generated with the Godot and Balaur ones and shipped together.
- [breaking] **One response shape across the API**, player and admin, with named schemas; the SDKs' classes follow.
- [added] **Accounts**: personal API tokens, GitHub sign-in, lockout after failed passwords, a grace period before deletion, captcha for API sign-up and Unicode usernames. An email registration signs in only once confirmed.
- [added] **Stripe Managed Payments**, the customer portal, and entitlements granted without a purchase.
- [added] **Site search, a `/ui` page of building blocks, manuals in the docs, and blog posts with pictures.**
- [added] **Settings for values that were fixed in code**, plus host hook modules and plugs.
- [changed] **`gamend_core` and `gamend_web` are on Hex.**
- [fixed] **Reliability and security**: slow work kept out of transactions, rate limiting before the body is read, IPv6 bans per /64, hashed lobby passwords, no personal data in logs, and fewer 500s.

# August 2026

- [added] **Plugins in GDScript and Gleam**, client logs, player analytics (D1/D7/D30), and grouped and repeating quests.
- [added] **Friends and retention admin pages**, a load-test harness, a performance guide and 16 new guides.
- [changed] **The home page shows the product**: screenshots, a tour video and a news menu.
- [fixed] **Faster logins and matchmaking**, plugins in releases, and realtime events no longer sent twice.

# July 2026

- [breaking] **Renamed to Gamend**, with UUIDv7 ids, underscore API paths, one pagination shape and one theme file.
- [added] **Quests (replacing achievements), economy, inventory, object storage, matchmaking, tournaments, ready checks, push notifications and lobby state.**
- [added] **Chat moderation, captcha, settings, retention for every table, the API lint, 30 locales and an admin runtime page.**
- [changed] **Hardening** of auth, payments and realtime, and faster broadcasts and queries.

# April 2026

- [added] **Native HTTPS, account activation, sitemap and robots.txt, a roadmap page, Spanish, French and Romanian, and security hardening.**

# March 2026

- [added] **Achievements, rate limiting, and WebSocket and WebRTC updates**; leaderboards accept labels; the admin shows live connections.

# Feb 2026

- [added] **Groups, parties, notifications, chat, the changelog and the blog.**
