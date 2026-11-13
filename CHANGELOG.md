# November 2026

- [added] **Unreal plugin, Unity, Rust and C# SDKs** ([#28](https://github.com/appsinacup/gamend/issues/28)), and TypeScript types in the npm package. Every SDK can send every socket event, `python3 clients/sdkgen lint` holds each one to the whole API, and the `Result*` schemas are `PlayResult*`.
- [changed] **Balaur SDK**: typed calls, an activity log of its own, saves through Balaur's `addons/save` (which a game now carries beside `addons/gamend`), and live key-value rows that reach the server.
- [breaking] **The game seats a formed match** ([#17](https://github.com/appsinacup/gamend/issues/17)): `matchmaking_seat_match/1` answers with `Gamend.MatchSeating` (a new lobby, a free seat in a running match, an accept window). Up to 8 matches start at once, and a ticket survives a page change. **Hosts:** run the migration, regenerate clients, and move `accept_timeout_ms` from `before_matchmaking_join` to the hook.
- [added] **`Gamend.Rating`** ([#26](https://github.com/appsinacup/gamend/issues/26)): Elo, Glicko-2, teams and free-for-alls, as pure functions that ship in the SDK too.
- [added] **Redemption codes** ([#53](https://github.com/appsinacup/gamend/issues/53)): reward codes and activation keys that finish a quest, redeemed at `/redeem` or over the API. Quest cards gain a button to where the quest is done and a note about the viewer. **Hosts:** run the migration; `:quest_action` answers `{label, path}`; `:currency_component` is now `:reward_component`.
- [breaking] **One status per error reason, and a hook's veto is `403 rejected`** with its words in `message` (`GamendWeb.ErrorStatus`). Many `400`, `422` and `500` answers are now `403`, `404` or `409`. **Clients:** handle the new statuses. **Hosts:** pass the reasons you don't handle to `reply_reason/2` and match `{:hook_rejected, reason}`.
- [fixed] **Rules hold under races.** One lobby and one party per player, friend requests, invites, ready checks, tournaments, quest claims, receipts, refunds and every cap are decided at the write (`Repo.compare_and_set/2`). A refund runs `after_purchase_revoked` once; `before_tournament_register` runs with the seat held. **Hosts:** build `update_user/2`'s `metadata` from `user.metadata`.
- [added] **`mix gamend.race.lint` and `mix gamend.literal.lint`** catch racy code and names typed out as strings (`use Gamend.Names`). **Hosts:** add both to `precommit` and call `.github/workflows/host-checks.yml` from CI.
- [fixed] **Security and privacy.** `/content/*` serves media only (a release's `.env` and database were readable), the chat page and hidden groups check the reader, banned accounts are refused on every route, sign-up no longer tells which emails have accounts, no legal name is imported, and others see less of a player's metadata.
- [changed] **Payments.** A guest who signs in keeps purchases, entitlements, coins and items; a grant can be extended, revoked and announced; a deleted account's Stripe subscriptions are cancelled; Admin → Payments tells an unpaid checkout from an ended one and shows card declines. **Hosts:** a stub Stripe adapter answers `checkout_decline/1` with nil.
- [added] **Notifications**: email digests (`email_every:`), sections and stacks on `/notifications`, each notification's `group` in the API, and `site_only` sends. **Hosts:** run the migration and regenerate clients.
- [breaking] **A page a product lacks is left out of the router, not switched off.** `except:` on the route macros replaces the `GAMEND_FEATURES_WEB_*` switches and `GAMEND_REPORTS_ENABLED`; `"locale_flags": false` in the theme replaces `GAMEND_FEATURES_LOCALE_FLAGS`; `CanonicalHost` is gone. **Hosts:** a build that still sets a removed switch fails and says what to write.
- [changed] **Public and signed-in pages share one socket.** **Hosts:** call `gamend_signed_in_routes/2` inside `gamend_current_user_routes/3`; `gamend_authenticated_live_routes/2` still works, with a reload.
- [changed] **A host's stylesheet is one import**, `gamend.css`, written by the `:gamend_assets` compiler: Tailwind, core's sources, heroicons and core's classes. **Hosts:** add the compiler, ignore `/assets/vendor/gamend/`, start `app.css` with `@import "../vendor/gamend/gamend.css";` and delete what it now brings.
- [changed] **Icons and avatars.** Icons are cached files, a picked icon has a colour, every user has an icon, a group can use its own image, players wear their avatar everywhere (`:player_avatar`, `:user_title_class`), and a new avatar or icon waits for Save. **Clients:** `profile_url` is that icon where it was `""`. **Hosts:** `GroupIconUpload.allow/3` is `allow/2`.
- [changed] **A group has its own page**, `/users/groups/<owner>/<slug>`. **Hosts:** link a group as `~p"/users/groups/#{id}"`.
- [added] **Page building blocks**: `nudge`, `form_heading/1`, `<.owner_picker>`, a warning before leaving an unsaved form, `data-confirm` in the page's popup, and page state in the URL (`GamendWeb.UrlState`). Back goes one step up; top-level pages have none. **Hosts:** drop `back_link`s to `home_path/0`.
- [changed] **Admin**: a title and icon on every page, and a grid of cards on `/admin`. Configuration splits into `/admin/plugins`, `/admin/theme` and System; `/admin/settings` lists every limit and downloads a `.env`. **Hosts:** an `AdminCard` takes `icon` and `color`; `AdminCard.all/0` is `load/0`.
- [changed] **Faster pages and dev.** Pages that list players are about twice as fast, icons skip the rate limiter, the first visit no longer jumps sideways, and a dev request no longer re-checks code when nothing changed.
- [added] **Hosting**: moving a server (`Gamend.Export`, `./rebuild.sh --export DIR`), more `Gamend.Containers`, release metadata in every image, `Gamend.Settings.declared/0`, builds that survive a GitHub outage, and `mix gamend.latest`. A bare `docker build .` builds the release. **Hosts:** regenerate the `Dockerfile`; a compose file names `target: full`.
- [breaking] **Ids are `Ecto.UUID`**, old migrations no longer call app modules, and a null id is refused on SQLite too. **Hosts:** a `Gamend.UUIDv7` field becomes `Ecto.UUID`.
- [changed] **Slugs and usernames take any script.** `GAMEND_LIMITS_USERNAME_ASCII_ONLY` and `GAMEND_GROUPS_UNIQUE_TITLES` are gone. **Hosts:** drop them; keep ASCII handles with `validate_username/1`.
- [changed] **Secrets**: rotation finishes in one call, a malformed key no longer writes under the next, and `secrets.fingerprint` is gone. **Hosts:** run the migration.
- [added] **Smaller additions**: the guides as one download ([#58](https://github.com/appsinacup/gamend/issues/58)), Oban Lifeline, `before_user_delete/1`, `after_socket_connected/3`, Balaur Script highlighting and `flag_path/1`. **Hosts:** an Oban config of your own adds `Oban.Plugins.Lifeline`.
- [fixed] **Smaller fixes**: fenced code is highlighted again, a chat edit is moderated as a send, IPv4 clients behind a proxy are seen, a Postgres image builds, and dialogs, the theme toggle and Safari's icon picker work. **Hosts:** `mix deps.get`; a settings `group:` is snake_case, its text in `label:`.

# October 2026

- [added] **Results**: what a play leaves, one row per player with its events, over the socket, `GET /api/v1/results` and `/admin/results`. They replace lobby snapshots. **Hosts:** run the migrations; drop `GAMEND_LOBBY_SNAPSHOTS_*` and `GAMEND_RETENTION_LOBBY_SNAPSHOTS_*`.
- [added] **Guests keep their progress.** The website makes guest accounts and merges them into the account they register or sign in to; `Gamend.AccountRequired` keeps chosen features for registered players. **Hosts:** implement `merge_user_data/2`, and pass `?return_to=`.
- [breaking] **Bans**: accounts, IPs and chat mutes, for a while or for good, kept as history (`/admin/bans`, the admin API). **Hosts:** run the migrations; the chat mute endpoints and `after_user_muted/1` are gone: use `/api/v1/admin/bans` with `kind: "chat"` and `after_ban_created/1`.
- [added] **Groups**: slugs, invite links on the site and the API, pending invites, hosts that keep groups private, a New group dialog, and an icon picked from the site's. **Hosts:** run the migrations.
- [added] **Navigation**: a sidebar, a phone tab bar, link tones, an avatar menu button, a navbar that fits itself, one-screen pages, and table rows that open what they list.
- [added] **Pages**: one player card with a host's title and badge, a Back button and title icon everywhere, three page widths, and breadcrumbs. **Hosts:** declare `text-muted` and `--container-narrow` in your stylesheet.
- [added] **Leaderboards with several rankings**, an All time tab, the rows around a record and hidden boards, on the site and the API.
- [changed] **Quests**: periods on the player's clock, claims that wait, repeat runs that bank, and named item rewards.
- [added] **Stripe payments, end to end**: refunds, resuming, plan changes, free periods, per-subject products, a checkout in the site's colours, and `mix gamend.stripe.setup`. **Hosts:** set the webhook to API version `2025-11-17.clover`.
- [added] **Analytics events and an Overview** that rates each number, with cohorts, activation, a funnel and money. **Hosts:** run the migration and describe your events in `:analytics_catalog`.
- [added] **Reports and moderation by email.** Players report from `/report` or the API, and admins work the queue at `/admin/reports`.
- [added] **Per-account preferences**: notifications per group and channel with one-click unsubscribe; the time zone, language and theme follow the account.
- [added] **Hosting**: base images and one deploy script, `Gamend.Containers`, a GitHub App, other host names, a server-wide socket cap and sign-in gate. **Hosts:** run `mix gamend.gen.dockerfile` and move your build steps into `assets.deploy`.
- [breaking] **Key settings take the key, never a path to its file.** **Hosts:** put the file's contents in the setting.
- [added] **Translations**: a host catalogue that falls back to core's, a site in fewer languages, an informal "you" and American English. **Hosts:** build your Gettext backend with `GamendWeb.HostGettext`.
- [changed] **Pages hold up at a million players**, measured by `mix demo.seed --count 1000000` and `mix demo.bench`. **Hosts:** run the migrations; walk KV with `KV.stream_prefix/2`.
- [breaking] **Registering takes no password**: the emailed code confirms the address. A crashing game hook answers 500 without details.
- [changed] **Version 1.1** (`1.1.<commit count>`) and **Nebulex 3.1**. **Hosts:** `mix deps.update nebulex nebulex_local nebulex_distributed nebulex_redis_adapter`.
- [removed] **IndexNow.** **Hosts:** drop `GAMEND_INDEX_NOW_*` and any `urls/1` from your sitemap source.
- [added] **Smaller additions**: crawler statistics, FAQ sections, rate-limit-exempt IPs, KV pruning by prefix, slow query logging, website feature switches and host RPC modules.
- [fixed] **Players dropping at once no longer run a server out of memory.**
- [fixed] **Smaller fixes**: Steam sign-in, confirmation emails, TLS 1.2 clients, WebSocket origins, a 16-character slug read as an id, one notification email an hour, and stale state after races.

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
