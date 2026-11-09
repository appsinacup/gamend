# Contributing

Checklist for adding a feature. Keep PRs small; one feature at a time.

## Data model (if the feature stores data)

- Schema in `apps/gamend_core/lib/gamend/<feature>/` using `use Gamend.Schema` (UUIDv7 ids).
- Migration in `apps/gamend_core/priv/repo/migrations/`. Must work on **both SQLite and Postgres** — no `ALTER COLUMN` and no `DISTINCT ON` on SQLite (rebuild the table / group in Elixir instead), test with `GAMEND_DB_ADAPTER=postgres` too.
- Index every column you filter, sort or count on. Use partial indexes for hot predicates (e.g. `create index(:t, [:deadline], where: "resolved_at IS NULL")`) — they serve sweeps and dashboard counters at once.
- Size/count caps in `Gamend.Limits` (auto-exposed as `GAMEND_LIMITS_*` env vars), enforced in the changeset, and listed in `@limit_categories` on the admin Config page.
- `timestamps(type: :utc_datetime)`, never a bare `timestamps()` — the bare form stores naive values that lose the zone and cannot be rendered safely (see **Time**).
- **Does the table grow without bound?** If rows accumulate per event, per session or per message, add a class to `Gamend.Retention` with a `GAMEND_RETENTION_*` window, or say in the PR why the table is bounded by its owner. Entity and balance state (users, wallets, inventories) is deliberately never pruned.
- Document the tables in the [Data Schema](https://gamend.org/docs/data-schema) guide (`priv/docs/10-setup/40-data-schema.md`).

## Time

The server stores and sends UTC and has **no timezone database**; the reader's
zone is only known in their browser. So:

- Persist `:utc_datetime` and serialise ISO8601 with the `Z` (the default `Jason` encoding). Never send a wall-clock string a client cannot place.
- Render every human-facing instant with `<.timestamp at={...} />`, never `Calendar.strftime` in a template. The component emits the UTC text plus the marks `local_time.js` needs; formatting by hand silently ships UTC dressed up as local time.
- A form field a person fills in uses `type="utc-datetime-local"`. A plain `datetime-local` submits the browser's wall clock with no offset, and casting that as UTC stores an instant hours off — the bug is invisible to whoever entered it, because it reads back the same way.
- Prefer a **duration** to an instant wherever the product allows: a countdown ("resets in 4h") is right in every zone and needs no conversion.
- Period boundaries (quest resets, quotas, recurring tournaments) are UTC and deliberately global — one rollover instant everyone races. Document the boundary where players can see it; never show them a reset hour.

## Functionality

- Context module in `gamend_core` (business logic, no web concerns).
- Every list function takes `:page` / `:page_size` and has a matching `count_*`. Pagination is not optional — assume 10k rows.
- Advisory lock namespaces go in `Gamend.Repo.AdvisoryLock` `@namespaces` before `Gamend.Lock.serialize/3` can use them.
- Any read-modify-write (merging a map, checking capacity before insert) must hold a lock. Plain "set field X" writes do not.
- A rule ("one per player", "pays once", "at most N") is enforced by the write itself, not by a read before it: a unique index, else `Gamend.Repo.compare_and_set/2` with the precondition in its `where`, else a lock keyed on the entity the rule belongs to. A check through the cache or outside the transaction only refuses early. Decide what comes next from the row the write answers, not from a struct read before it. Details in AGENTS.md, Locks.
- Background work (sweeps, schedulers) as a supervised GenServer — add it to `GamendWeb.HostSupervision.children/1`, which every host (this repo and the starter) starts. A host-only process goes in that function's `:extra` option instead.

## Named strings

A string the code compares, matches or stores as a name (a status, a job's action, a kind, a file in a bucket) is typed once. `"creat"` compiles, and whatever reads it simply never matches.

- **One module uses it:** `@failed "failed"`.
- **Another module reads it:** the module that owns the value names it, as a macro, so a pattern or a guard can use it and a typo fails the build: a compile error in a pattern, elsewhere a warning that `--warnings-as-errors` makes fatal. `use Gamend.Names` writes them, and `all/0` for `validate_inclusion/3`. `@all` stays set, for a macro that names part of the list:

  ```elixir
  defmodule MyApp.Servers.Status do
    use Gamend.Names, ~w(creating running failed)
  end

  require MyApp.Servers.Status, as: Status

  def up?(%Server{status: Status.running()}), do: true
  def busy?(status) when status in [Status.creating(), Status.failed()], do: true
  ```

- **Where the owner lives:** one small module per set of values, beside its feature: `Gamend.Lobbies.LobbyState` in `lobbies/`, `GamendWeb.AdminLive.BanDuration` in `live/admin_live/`. The top level is for a name several features share, like `Gamend.SortKey`.
- **Where a macro cannot go:** inside an Ecto query `Status.running()` is read as a field, so pin it (`^Status.running()`). In HEEx `@name` is an assign, so a template calls the macro, never a module attribute. `require` comes before any attribute that uses one. A file `gen.sdk.ex` copies into the SDK whole (`@copied_sources`) may use nothing but the standard library, so it keeps a module attribute.
- **Not names:** a map's keys (the shape of a document), anything shown or logged, a LiveView event, an API error's code in `reply_error/3` (`mix gamend.api.lint` reads it as a literal). Tests may spell a value out, and reuse the name where it reads as well.
- `mix gamend.literal.lint` (in `precommit` and CI) fails on a name typed out in two or more modules, or five or more times in one. In a template a comparison counts (`@s == "failed"`), so a template asks the owner too. A module attribute or a private function that is only its value counts once a second module of the same context gives the same string the same name: `@ebin "ebin"` in two `Gamend.Hooks` modules. A string that is someone else's, or a word two modules share by coincidence, is marked `# literal-ok: <why>`, or `<%!-- literal-ok: <why> --%>` in a template. There is no baseline: fix what it finds, then add it.
- A host runs these in CI by calling `.github/workflows/host-checks.yml` from a workflow of its own: `compile --warnings-as-errors`, `gamend.api.lint` and `gamend.literal.lint`, against the published Gamend.

## Errors

A failure is either **expected** — a client, bad input or a concurrent write can cause it — or a **bug**. They travel differently, and hosts (Forge, Polyglot Pirates) follow the same rules.

- **Expected failures return `{:error, reason}`** (or `nil` from a plain `get_*`), through `with`, `case`, guards and changesets. The `@spec` says so and holds: a function that returns tuples calls no `!` function on a path a client or a concurrent delete can reach. "Check, then `get_x!`" is that path — the row goes between the two.
- **Bugs and infrastructure failures raise** (a bad call, the database down, a constraint no changeset declares). A context does not rescue them, does not wrap and re-raise them as its own error, and does not turn them into `{:error, exception}`: the caller can do nothing with it, the stack trace is lost, and a server fault comes back as a 4xx.
- **A `!` function is a thin wrapper over its tuple twin**, for a caller whose miss is a bug: tests, seeds, mix tasks, boot, and an admin LiveView's `mount`/`handle_params` (`Ecto.NoResultsError` renders a 404). Never in an API controller, a channel, a hook RPC, a LiveView `handle_event`/`handle_info`/`handle_async` or a job's `perform` — there a miss is an answer. `mix gamend.api.lint` (R17) flags `get_*!` and `Repo` lookups with `!` in those places; an admin page answers a miss with `GamendWeb.AdminLive.Shared.with_record/3`.
- **Rescue one exception that has a domain meaning, at the write that raises it, around that one call:** `Repo.rescue_stale/2` (the row was deleted since it was read), `Repo.rescue_foreign_key/2` (its parent is gone). Prefer `unique_constraint/3` and `foreign_key_constraint/3` in the changeset, which need no rescue at all.
- **The process boundary handles everything else, the same way each time.** Plug answers 500 through `ErrorJSON`; a hook that raises answers 500 `exception` with no detail, logged with its stack trace by `Gamend.Hooks`; a crashed channel rejoins; a job that raises retries and still leaves its rows in a terminal state. A best-effort step that must not stop its caller (the cleanups in `Accounts.delete_user/1`) may rescue, and logs the exception with `Exception.format/3` — never `rescue _ -> :ok`.
- **An API controller names the reasons it answers its own way, and hands the rest to `reply_reason(conn, reason)`.** The status comes from `GamendWeb.ErrorStatus`, one table for every controller: a new reason is a line there, or a name its rules already cover (`*_not_found`, `already_*`, `*_not_configured`), and every endpoint that meets it answers the same. A reason the table does not know raises `GamendWeb.UnmappedReason`, a 500 that names it, never a status a catch-all made up. A game hook's veto travels as `{:error, {:hook_rejected, reason}}` and answers 403 `rejected` with the hook's words. `mix gamend.api.lint` (R18) flags a catch-all clause that picks its own status, and an explicit status the table disagrees with.
- **No `throw`/`catch` for control flow.** `with` and tagged tuples carry an early exit.
- **Test the misses.** Each documented 4xx of an endpoint gets a test, and so does the race a `rescue_stale` covers. `RESPONSE_CONTRACT_SEEN=<file> mix test` lists the operation/status pairs the suite reaches; a documented status missing from it is untested.

## Hooks (so plugins can extend the feature)

Adding one callback touches six places — miss one and plugins break in confusing ways:

1. `@callback` in `Gamend.Hooks`, listed under `@optional_callbacks` so existing plugins keep compiling.
2. Add the name to `internal_hooks()` — otherwise clients can invoke it over RPC.
3. `before_*` hooks: add to `lifecycle_pipeline_hook?/2`, plus a `normalize_pipeline_args/3` clause if the hook only vetoes (returns the value unchanged).
4. No-op implementation in `Gamend.Hooks.Default`.
5. Mirror in the SDK (`sdk/lib/gamend/hooks.ex`): `@callback` and `@optional_callbacks`. The default goes in `Gamend.Hooks.Defaults` (`apps/gamend_core/lib/gamend/hooks/defaults.ex`): in `default_callbacks` or `more_default_callbacks` (the quoted code `use Gamend.Hooks` injects), **and in the `overridable_callbacks` list** — a default that isn't listed there cannot be overridden by plugins. `mix gen.sdk` (in `mix precommit`) copies that file into the SDK, so a plugin gets the same defaults built with Mix or in-process.
6. Document the hook in `priv/docs/40-gameplay/90-server-scripting.md`.

**Hold the database only for database work.** On SQLite the repo has a single connection and every transaction takes the write lock, so anything slow inside a transaction or `Gamend.Lock.serialize/3` stalls every other request. Open transactions with `Gamend.AfterCommit.transaction/2` (or `serialize/3`) and broadcast with `Gamend.Broadcast.publish/2`: broadcasts, `Gamend.Async.run/1` tasks and anything passed to `Gamend.AfterCommit.defer/1` then wait for the commit, and a rollback drops them. A test in `after_commit_test.exs` fails on a bare `Repo.transaction` or `Phoenix.PubSub.broadcast` in core. Slow gates run *before* the lock: a plugin's `before_*` hook, a password check, an HTTP call. Inside it, re-check only what a concurrent writer could change (see `Lobbies.join_lobby/3`). When the hook needs the value the lock protects, go optimistic: read and ask the hook unlocked, then write under the lock only if the value is unchanged, and retry otherwise (`Lobbies.merge_metadata/2`).

## SDK (plugin-facing)

- Add the context to `@sdk_modules` in `mix gen.sdk`, then run `mix gen.sdk`.
- Hand-write struct stubs in `sdk/lib/gamend/<feature>/` (the generator does not create them) — plugins can't compile against a struct that doesn't exist.
- A pure module (no database, no other context, only the standard library) needs no stub: list its file in `@copied_sources` and the module in `@extra_api_modules`, and the SDK and GDScript get the real thing (`Gamend.Rating`, `Gamend.MatchSeating`).
- Add placeholder rules in `gen.sdk` for the new structs (`T | nil` and `{:ok, T}` return types). Without them a stub returns only `nil`/`{:ok, _}`, and every plugin that pattern-matches the other branch gets a bogus "clause cannot match" warning.
- Verify with `cd modules/plugins_examples/example_hook && mix compile --force` — it must be warning-free.
- The server loads plugins from their bundled `ebin/`, not from `_build` — after changing a plugin, run `mix plugin.bundle` in its directory (or the admin Config build button) or the running server keeps the old code. Without `mix` on the PATH (a release) the button builds in-process (`Gamend.Hooks.PluginBuilder.InProcess`), against the engine's modules rather than the SDK's stubs.

## Web

- API controller in `apps/gamend_web/.../controllers/api/v1/` with OpenAPI schemas (ids are `type: :string, format: :uuid`). List endpoints return `data` plus the six-key `meta` block (`page`, `page_size`, `count`, `total_count`, `total_pages`, `has_more`) built by `GamendWeb.Pagination`. Answer through `GamendWeb.Reply` in one of the four shapes of api-conventions.md (R15), document each response as a named `GamendWeb.Schemas.*` module (a `*Response` or `*Page` envelope, `OkResponse`, errors via `Schemas.error/1`), and add the controller's tag to `GamendWeb.ResponseContract` while the migration list exists.
- Routes in `apps/gamend_web/lib/gamend_web/router/shared.ex`. Public listing endpoints get a `GAMEND_FEATURES_LIST_*` feature gate (a `setting` in `GamendWeb.Features`).
- Server-authoritative actions get **no public endpoint** — expose them through hooks.
- Realtime events via channel/PubSub if clients need pushes; forward them in `UserChannel` and subscribe/unsubscribe on join/terminate.
- Public LiveView: copy the layout of an existing page (leaderboards is the reference) rather than inventing one — same heading sizes, card grid, badges and `<.pagination>` component.
- Nav links live in **two** places: `theme/config.json` (`navigation.primary_links`) and the Elixir defaults (`default_primary_nav_links/0` in `host_layouts.ex`). A configured dropdown wins outright — nested items are not merged — so a link added only to the defaults will not appear.

## Admin

- Admin LiveView page in `apps/gamend_web/lib/gamend_web/live/admin_live/`, opening with `<.admin_header page="/admin/thing" />`, plus its route, its title, icon and colour in `GamendWeb.AdminLive.Pages`, an `<.admin_card>` in its `<.admin_section>` on `/admin` (a test fails a listed page with none), and an entry in `admin_pages_render_test`.
- Show names, not raw UUIDs, and paginate every table.
- Admin API controller under `controllers/api/v1/admin/` with **parity for every admin UI action** — anything an admin can click, a script can call.

## Tests

- Context tests in `apps/gamend_core/test/` — they run without the web app, so a test that needs a conn, a channel or a `GamendWeb` module belongs in `apps/gamend_web/test/` instead. Controller, admin API, channel and LiveView tests in `apps/gamend_web/test/`. Both share `apps/gamend_core/test/support` (`Gamend.DataCase`, fixtures, `Gamend.TestSupport.NoopHooks`); root `mix test` runs both suites.
- Run against both adapters: `mix test`, and again with `GAMEND_DB_POSTGRES_HOST` and `GAMEND_DB_POSTGRES_USER` (or `GAMEND_DB_URL`) set, after `mix deps.clean gamend_core gamend_web --build`. SQLite and Postgres differ in ways tests hide: `config/test.exs` sets `busy_timeout`, so concurrent-write failures that bite in dev never surface in CI.
- **Race the rule.** A flow with a "one per", "exactly once" or capacity rule gets a `Gamend.RaceCase` test: two or more requests released together, each on its own connection, asserting the rule held and nothing raised. A `Gamend.DataCase` test runs on one connection and cannot overlap anything. When a hook sits between the read and the write, a hook that holds one caller until the other has passed is deterministic on both adapters (`quest_claim_race_test.exs`). `mix gamend.race.lint` (in `precommit`) asks for a guard or a `# race-safe: <why>` on every function shaped like a check-then-write; the marker is the reasoning, not a silencer.
- **Run the feature, don't only test it.** Boot the app (`mix run` a script, or the dev server) and exercise the real path — several classes of bug (hooks inside transactions, stale caches, missing supervision children) only appear at runtime.
- Add a set to `mix demo.seed` so the feature can be viewed at volume (pagination, large brackets, long lists).

## i18n

- `mix gettext.extract && mix gettext.merge priv/gettext` from `apps/gamend_web`, then translate every locale — `.po` files are kept fully translated.
- **Check for fuzzy matches after merging.** The merger silently borrows translations from similar strings (a new "Brackets" once picked up "Back"), and fuzzy entries are used at runtime. Grep for `fuzzy` and fix or clear them.
- Prefer `gettext("Players")` + a value over `ngettext` — plural rules differ wildly across the 30 locales.
- Plugin/sample content (example hook titles, seeded data) is not localized; it belongs to the host, not core.

## Finish

- Guide in `priv/docs/<NN-category>/<NN-name>.md` if user-facing — a markdown file is the whole change, no registration and no Elixir. The folder is the category, the numeric prefixes order it, the first `# ` heading is the title and the first paragraph becomes the one-line summary on the index. Also register any new server→client event in `GamendWeb.RealtimeEvents` (a drift test fails otherwise) and its row in the realtime guide's event table, and update the feature list in `api_spec.ex`.
- Keep guides short. They render inside a disclosure someone opened with a question in mind: lead with the answer, prefer a table or a short example over prose, and leave the exhaustive reference to the API docs.
- New settings declared with `Gamend.Settings.Provider`, never read with `System.get_env/1`. The env var name derives from the declaration, and both `.env.example` and the public Settings guide are generated — run `mix gamend.settings.env_example` and `mix gamend.settings.guide`, and commit the result. Both take `--check` so CI catches a declaration whose docs were never regenerated.
- `CHANGELOG.md` entry (`[added]` / `[changed]` / `[fixed]` / `[removed]` / `[breaking]`): a bold one-line summary and at most a short sentence, folded into the month's entry for the same area when there is one. Keep it light: what a reader notices, plus a one-line **Hosts:** note when they must change something. The details go in the guide and the commit.
- `mix format`, `mix credo --strict`, `mix gamend.api.lint`, `mix gamend.literal.lint`, full `mix test` green.
- SDKs regenerate from the OpenAPI spec in CI — no manual SDK edits, but for what `python3 clients/sdkgen lint` asks for: a new operation's function in the Godot façade (`clients/gamend_template/GamendApi.gd`), and a new socket event in `GamendWeb.RealtimeCommands` and the Godot and JavaScript clients.
