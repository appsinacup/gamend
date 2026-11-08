<!-- api-lint: unimplemented -->

# Redemption codes: rewards and activation keys

Goal: a player types a code and gets something: currency, items, or access to a
game mode. An admin generates codes in bulk, invalidates them, and sees who used
them. From [issue #53](https://github.com/appsinacup/gamend/issues/53).

## Built on quests

A redemption code is a way to finish a quest. The quest holds everything about
what the code gives; the only new thing is the code itself.

| Needed | Already there |
|---|---|
| A set of codes with its own purpose | A quest: `key`, `title`, `category`, `metadata`, `icon_url` |
| What a code pays | `quest.rewards`, paid exactly once, with crash recovery |
| Valid from and until, on and off | `starts_at`, `ends_at`, `active` |
| One per player | `quest_progress`'s unique index on user, quest and period |
| Admin form, grant, reset, force-claim, funnel | `/admin/quests` and `/api/v1/admin/quests` |
| Realtime | `quest_completed`, `quest_claimed` |
| Game logic around it | `before_quest_claim`, `after_quest_completed`, `after_quest_claimed` |
| Surviving guest sign-in | `Quests.merge_user_progress/2`, already a `GuestMerge` step |
| A player's history | `GET /me/quests`, `/quests` |

New: one table, two columns, one player endpoint, one card on `/quests`, one
small admin page.

Demand is one requester so far, who reports that codes are standard in games
shipping in China, for event rewards and invitation-only test servers. Built this
way, the feature is small enough for that to be a fair bet.

## How it works for the player

### In the game

1. The player gets a code from a stream, an email or a community post.
2. They paste it into the game's "Redeem code" box. Spaces, dashes, letter case
   and full-width characters do not matter.
3. The game calls `POST /api/v1/me/quests/redeem` with
   `{"token": "ABCD-EFGH-JKMN-PQRS"}`.
4. The answer has the shape a quest claim already has, `{progress, rewards}`, so
   the game shows what was granted with the code it already has for claims.
5. The socket delivers the wallet and inventory updates it always sends, then
   `quest_completed` and `quest_claimed`. A "Quest completed" notification lands
   in the player's inbox.

### On the website

1. `/quests` shows a "Have a code?" card above the list, on any server with at
   least one code. Signed out, the card is a sign-in link.
2. The player pastes the code and presses Redeem.
3. A flash says what they got (`Code redeemed: Spring gift, +100 gold`), and the
   quest appears in the list as claimed.

### What the player can be told

| Situation | API | Player sees |
|---|---|---|
| Accepted | 200 | The rewards |
| Unknown, expired, revoked, disabled, or used up | 404 `code_not_found` | "That code is not valid." |
| This player already has this quest | 409 `already_redeemed` | "You already redeemed this." |
| Guest on a shared code, or the host requires accounts | 403 `account_required` | "Register to redeem", with the link |
| Too many tries | 429 `redeem_rate_limit` | "Try again in a minute." |
| The game's `before_quest_claim` refused | 403 `rejected` | The hook's words. The code is not spent |

### A key that unlocks a game mode

The admin makes a quest with no rewards (`beta_access`). A code-only quest has a
progress row for a player only once they redeem, so the game's gate is one line
in a hook:

```elixir
Gamend.Quests.get_progress(user_id, "beta_access") != nil
```

A client can show the state from `GET /me/quests?category=access`. The row moves
with the player when a guest signs in to an account.

## How it works for the admin

### Reward codes for an event

1. `/admin/quests`, New Quest. Key `spring_gift`, a title, rewards
   `[{"type": "currency", "code": "gold", "amount": 100}]`, an optional window,
   and tick **Only by code**. Objectives stay empty. Save.
2. The quest's row now has a **Codes** button, which opens
   `/admin/quests/:id/codes`.
3. **Generate**: count 5000, uses per code 1, metadata `{"source": "bilibili"}`.
   The metadata travels to each player's progress row, so a hook can tell which
   channel a redemption came from.
4. **Download CSV**, and hand the codes out.
5. The table shows each token, uses, status and who used it. The existing User
   Progress table on `/admin/quests` lists everyone who redeemed the quest.

### One public code

Same quest setup, then **Add code**: type `春节快乐`, and leave uses blank for
every player once, or enter 1000 for the first 1000 players.

### Invitation keys for a test server

A quest `beta_access` in category `access`, no rewards, **Only by code**.
Generate 200 single-use codes and send one to each tester. The game gates on the
progress row as above.

### Stopping codes

- One code: **Revoke**. **Restore** undoes it.
- Every code of a quest: untick **Active** on the quest. Ticking it resumes them.
- At a set time: `ends_at` on the quest.

### Support

- "My code does not work": search the codes page for it. It shows who used it,
  or that it is revoked or used up.
- Reward missing: the existing **Force claim** on User Progress.
- Let a player redeem again: the existing **Reset**. The code's use is not given
  back.
- Give it to someone with no code: the existing **Grant**.

## What is new

### Data

```
quest_codes
  id
  quest_key  references(:quests, column: :key, type: :string, on_delete: :delete_all)
  token      string          -- as people see it: ABCD-EFGH-JKMN-PQRS, 春节快乐
  lookup     string, unique  -- normalized; the only column a redeem reads by
  max_uses   integer         -- 1: single-use. N: first N players. NULL: every player once
  uses       integer, default 0
  status     string          -- "active" | "revoked"
  metadata   map             -- copied onto the player's progress row
  timestamps

quests          + code_only  boolean, default false
quest_progress  + code_id    references(:quest_codes, on_delete: :nilify_all), nullable
```

Indexes: `quest_codes (quest_key, status)` and a partial
`quest_progress (code_id) WHERE code_id IS NOT NULL`, which answers "who used
this code".

`Quest.changeset/2` when `code_only` is true: `reset` must be `"never"`,
`objectives` must be empty, and `group_key` and `prerequisite_quest_key` must be
unset. That keeps the event engine, periods, chains and groups out of it: no
event can touch the quest and its only possible row is the `"static"` one. Codes
can only be created on a `code_only` quest.

Listing: a `code_only` quest shows only to a player who has a row. One clause on
`visible_to_user?/3`, plus a `Quests.catalog/0` (`active_quests/0` without them)
for the three signed-out readers: `visible_categories(nil)`,
`QuestsLive.anonymous_catalog/6` and `QuestController.index/2`.

Notes:

- **`lookup` is unique across quests.** The player types only the code, so
  nothing else can say which quest is meant.
- **The field is `token`, not `code`.** `code` in api-conventions.md is a value
  from a fixed vocabulary (`gold`), and `Reward.code` is one. `token` matches
  group invite links, and `filter_parameters` in `config/host_config.exs` already
  masks it, so it stays out of request logs. `code` is not masked.
- **No retention class.** Codes are bounded by what admins generate and go with
  their quest. `Quests.prune_old_periods/0` never touches `"static"` rows, so the
  proof of the one-per-player rule is kept.

Limits (`Gamend.Limits`, listed in `@limit_categories`): `max_quest_code_token`
128, `max_codes_per_generate` 10,000, `max_redeem_attempts_per_min` 10.

The issue asks for arbitrary length. It gets a cap, as every string here does.
`max_quest_code_token` can be raised to 512 and no further: a Postgres btree
entry tops out near 2,700 bytes, and 512 four-byte characters fit under that.

### Matching what the player typed

```elixir
raw |> String.normalize(:nfkc) |> String.replace(~r/[\s-]/u, "") |> String.downcase()
```

- In Elixir, so both adapters compare the same bytes and no collation is
  involved.
- NFKC folds the full-width forms CJK input methods produce, so `ＡＢＣ－１２３`
  matches `ABC-123`.
- The cap applies to the normalized form, because NFKC can lengthen a string.
  Input over `4 * max_quest_code_token` bytes is refused before normalizing.
- Empty after normalizing is `:code_not_found` for a player and a changeset error
  for an admin.

### Redeeming

`Quests.redeem_code(user_id, token)` returns what `claim/3` returns. The API
controller and the `/quests` card both call it, and a plugin may. It lives in
`Gamend.Quests` because it uses the engine's private steps; token handling, CRUD
and generation live in `Gamend.Quests.Codes`, re-exported as `Groups.InviteLinks`
is.

1. Normalize, then read the code with its quest. Missing, revoked, quest
   inactive or not `code_only`, or outside the window: `:code_not_found`.
2. The player already has a row for this quest: `:already_redeemed`.
3. Used up (`uses >= max_uses`): `:code_not_found`.
4. Guest check (see **Guests**).
5. `before_quest_claim`, given a `%QuestProgress{}` that is not written yet, so a
   veto costs the player nothing. It answers `{:hook_rejected, reason}`.
6. The write, two statements:

```elixir
Repo.rescue_foreign_key(:code_not_found, fn ->
  AfterCommit.transaction(fn ->
    progress = insert_completed(user_id, quest, code, now)  # unique index: rollback :already_redeemed
    take_use(code, now)                                     # conditional update below
    progress
  end)
end)
```

```elixir
from(c in Code,
  where: c.id == ^code.id and c.status == "active" and
           (is_nil(c.max_uses) or c.uses < c.max_uses)
)
|> Repo.compare_and_set(set: [updated_at: now], inc: [uses: 1])
# {:error, :precondition_failed} rolls back as :code_not_found
```

7. Pay through the engine: the part of `on_completed/3` before auto-claim, split
   out as `announce_completed/3` (broadcast, notification, `after_quest_completed`),
   then `do_claim(user_id, quest, skip_hooks: true)`. The hook already ran in step
   5. A code pays at once whatever the quest's `auto_claim` says.

Why it has this shape:

- **Each rule is held by a write.** One per player is `quest_progress`'s unique
  index, capacity is the conditional update. Steps 1 to 3 only refuse early.
- **The conditional update goes last,** so a popular code's row is locked only
  across the commit. Every code writes it, shared or not, which keeps one path
  and an accurate `uses`.
- **Paying is the quest claim, unchanged.** `completed → claimed` is conditional,
  grants carry idempotency keys, and `recover_pending_rewards/1` heals a crash
  mid-grant. A crash between the commit and the claim leaves a completed row that
  lists as claimable, so the player presses Claim and nothing is lost.
- **Deadlock:** the insert's foreign key takes `FOR KEY SHARE` on the code row,
  which does not conflict with the update's `FOR NO KEY UPDATE`.

### Guests

`GuestMerge` moves a guest's wallet and items into the account they sign in to.
So a guest could redeem a shared code, sign in, and repeat with a new guest: one
code paying N times to one account at no cost.

- **A guest is refused with `:account_required` on any code with `max_uses` other
  than 1.** No setting: this protects the game's currency.
- Single-use codes cannot be farmed, since each pays once whoever holds it. They
  follow the host's existing `AccountRequired` `:quest_claims`.
- A guest who redeemed and signs in keeps the quest through
  `merge_user_progress/2`, `code_id` included. If the account already has that
  quest, the guest's row goes with the guest.

### Abuse

- `GamendWeb.RateLimit.check_redeem/1` follows `check_chat_daily/1`: one
  per-user bucket, answering `{:error, :redeem_rate_limit}`. Per-IP limits are the
  ones the API and LiveViews already have.
- Generated tokens carry 80 bits, so guessing one is not realistic. The limit
  protects the database and human-chosen tokens.
- **One answer for every miss:** `code_not_found`, as
  `get_invite_link_by_token/1` does. `already_redeemed` differs, and it only
  speaks of the caller's own history.
- **The token goes in the POST body, never a path or query.** Paths reach access
  logs and `Referer` headers, and `filter_parameters` covers only params.
- The card submits on `phx-submit` only. A `phx-change` check would spend rate
  limit on every keystroke.

### Generating codes

`Quests.Codes.generate(quest, count, max_uses: 1, metadata: %{})`:

- 16 symbols from Crockford base32 (no `I L O U`), from
  `:crypto.strong_rand_bytes/1`, shown as `XXXX-XXXX-XXXX-XXXX`.
- `Repo.insert_all` in chunks of 500, each its own transaction so SQLite's write
  lock is released between them. Every row sets `id: Gamend.UUIDv7.generate()`,
  since `insert_all` runs no autogenerate. `on_conflict: :nothing` on `lookup`,
  then top up by what was dropped.
- Capped at `max_codes_per_generate` so a run finishes inline (`start_async` on
  the admin page, one admin API call) with no job or progress state. Need more:
  run it again. Measure 10,000 on SQLite while building this and lower the
  default if it does not fit an API request.

`Quests.Codes.create(quest, %{token: …, max_uses: …, metadata: …})` makes one
code with a chosen token. A taken token is a uniqueness failure, answered 409 by
`unprocessable_or_conflict/2`.

### API

Player, `:api_auth`, in `gamend_quest_api_routes/0` beside claim:

```
POST /api/v1/me/quests/redeem   {"token": "…"}   200 QuestClaimResponse
```

The controller hands every failure to `reply_reason/2`. `code_not_found` and
`already_redeemed` follow the `*_not_found` and `already_*` rules,
`account_required` is in `ErrorStatus` already, and `redeem_rate_limit` is one new
line there, 429.

Admin, `:api_admin`, in `gamend_admin_chat_quest_api_routes/0`, with parity for
the admin page:

```
GET   /api/v1/admin/quests/:id/codes    page, page_size, search
POST  /api/v1/admin/quests/:id/codes    {count, max_uses, metadata} or {token, max_uses, metadata}
PATCH /api/v1/admin/quest_codes/:id     {status}
```

The admin quest create and update accept `code_only`. No new realtime events, no
new hooks.

`metadata` on a code reaches the player through `quest_progress.metadata`, so the
admin form says not to put private notes in it. The token never appears in a
player answer.

### Pages

`/quests` gets the card. The page stays in `live_session :current_user`, because
it serves signed-out readers too, and the card's event refuses without a user.
The card shows when `Quests.Codes.any?/0` is true, cached on the quests version
like `active_quests/0`, so a host running no codes never sees it. The flash reuses
`claimed_flash/1`, with the quest's title so a no-reward key still says something.

`/admin/quests` gets an **Only by code** checkbox beside the Auto-claim one, and a
**Codes** button on `code_only` rows.

`/admin/quests/:id/codes` is `AdminLive.QuestCodes`, in `live_session :require_admin`
through `gamend_admin_live_routes/1` because it is admin-only: generate, add one,
exact search on `lookup`, revoke and restore, used-by names, pagination, copy with
the `CopyText` hook. It is a sub-page of Quests, so it goes in
`AdminLive.Pages`' `@subpages` and draws `<.admin_header>`, with no dashboard
card. CSV is a controller action at `/admin/quests/:id/codes/export` in the
`[:browser, :require_admin_user]` scope; scripts page through the JSON list, since
the API has no CSV shape.

## What comes with quests

Consequences of the reuse, accepted:

- **One redemption per player per quest,** by the existing unique index. A player
  cannot stack two codes of one quest. A host that wants stacking makes separate
  quests.
- Code quests count against `max_quests` (500) and in quest stats.
- Redeeming sends the "Quest completed" notification.
- Past `ends_at` or with **Active** off, a redeemed quest leaves the player's list,
  as any quest does. Its row stays, so the `get_progress/2` gate is unaffected.
- A quest in category `achievement` shows on the public profile, like any
  achievement.
- The quests guide says "Clients cannot advance their own quests". It gets the
  exception: except with a code the server issued.

## What this deliberately does not do

- **No code in a URL** (`/quests?token=…`). A link would be convenient for public
  codes and is worth revisiting for those alone; a single-use code in a link ends
  up in logs and history.
- **No targeting by region, platform or level.** `before_quest_claim` is the place
  for it.
- **No expiring access.** A key unlocks for good. When a game needs a month of
  access: add `entitlement` to `Quests.Reward`'s types and a branch in
  `grant_rewards/3`. `GuestMerge` already carries granted entitlements over.
- **No undo.** Reversing a payout uses the existing `Economy.spend/4` and Reset.

## Alternatives considered

- **Tables of its own** (campaigns, redemptions, a reward embed, two hooks, a
  realtime event, `/redeem`, `/admin/redemptions`, two `GuestMerge` steps). This
  spec's first draft. It pays in one transaction and can grant entitlements, at
  the cost of rebuilding most of the table at the top of this file.
- **KV plus a hook, as a plugin.** Works, and needs a lock around the capacity
  check. It leaves bulk generation and admin UI undone.
- **A reserved event through `report_event/4`.** Reuses more of the engine, but an
  event reaches every quest listening for it, and the code's use could not commit
  with the completion.
- **`active: false` instead of `code_only`.** No new column, and inactive quests
  are already unlisted, but it takes away the admin's off switch.
- **`hidden: true`.** It lists as a `???` teaser the player can do nothing with.
- **Oban job for generation.** Durable and resumable, at the cost of progress
  state and a page that polls, for a one-off action a cap already bounds.

## Open decisions

1. **Guests and shared codes.** Specced as refused outright. The alternative is
   following `:quest_claims` like single-use codes, which accepts the farming
   above for games where a guest redeeming matters more.
2. **Plaintext or hashed tokens.** Specced as plaintext, like
   `GroupInviteLink.token`, so an admin can export a batch again and read a public
   code. Hashing protects unused codes if the database leaks, but each code can
   only be shown once, at generation.
3. **Where the box lives.** Specced as a card on `/quests`, the least to build. A
   host that closes that page (`GAMEND_FEATURES_LIST_QUESTS`) then has no web box,
   only the API. The alternative is a small `/redeem` page of its own, which is
   also easier to link to from a community post.

## Definition of done (CONTRIBUTING)

- [ ] Migration on SQLite **and** Postgres; `Quests.Code` uses `Gamend.Schema` and
      `timestamps(type: :utc_datetime)`; Data Schema guide updated.
- [ ] `code_only` changeset rules tested; limits declared, listed in
      `@limit_categories` and enforced in changesets; normalization covers NFKC,
      full-width input, case and dashes.
- [ ] A code-only quest is absent from every signed-out list, and from a player's
      list until they redeem.
- [ ] `Gamend.RaceCase` tests beside `quest_claim_race_test.exs`, on Postgres: N
      players racing a code capped at K complete exactly K; one player racing the
      same code pays once; one player racing two codes of one quest pays once and
      spends one use. `mix gamend.race.lint` clean.
- [ ] A veto spends nothing; a crash between commit and claim leaves a claimable
      row.
- [ ] Guests refused on shared codes, `:quest_claims` honoured, a redeemed quest
      survives `GuestMerge`.
- [ ] Player and admin API with named schemas, each documented 4xx tested;
      `mix gamend.api.lint` clean; `redeem_rate_limit` in `ErrorStatus`.
- [ ] `/quests` card, Only by code checkbox, `/admin/quests/:id/codes` with an
      `admin_pages_render_test` entry, CSV export.
- [ ] `Quests.Code` struct stub and placeholder rules for `mix gen.sdk`, example
      plugin warning-free; the redeem call in the Godot façade
      (`clients/gamend_template/GamendApi.gd`), which `sdk_facade_drift_test.exs`
      asks for.
- [ ] A section in the quests guide, a `mix demo.seed` set, every locale translated
      for the card, CHANGELOG, the Quests row in AGENTS.md.
- [ ] Generating `max_codes_per_generate` measured on SQLite.
- [ ] The real path exercised on a running server, then `mix precommit` green.
