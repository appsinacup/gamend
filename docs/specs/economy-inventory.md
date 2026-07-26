# Economy / inventory — generic currencies, atomic wallet, ledger

Design spec for the Phase 2 **Economy/inventory** item in
[ROADMAP.md](../../ROADMAP.md). This is the **base of the reward spine** —
economy → quests → achievements are designed together (see the roadmap
preamble), so this contract is what [quests-progression.md](quests-progression.md)
pays into.

Goal: a generic, game-agnostic economy — author-defined **currencies** and
**items**, an **atomic wallet** that can never go negative or double-spend, and
an **append-only ledger** that explains every balance to the cent. All mutations
are server-authoritative.

## Why (there was a wallet; it was ripped out to be rebuilt generic)

The repo *used* to have `wallet_ledger_entries`, welded to the payments system
(a `store_products.kind = "currency"`). Migration
`20260614130000_remove_payment_wallet_ledger` deleted it and folded currency
products back into `consumable`. That was deliberate: a payments-coupled wallet
can only ever credit what someone *bought*. A real economy credits quest
rewards, daily bonuses, PvP winnings, refunds, admin grants — none of which are
purchases. This item reintroduces the wallet/ledger as a **standalone
`GameServer.Economy` context** that payments becomes just one *caller* of.
`GameServer.Payments` stays the source of truth for entitlements/receipts; it
hands off to `Economy.credit/…` to actually move balances.

## Data model (both adapters)

**Definitions (admin/author-owned):**

- **`currencies`** — `key` (unique, e.g. `"gold"`), `name`, `precision`
  (integer minor units; `0` = whole coins), `max_balance`, `tradeable`
  (bool), `metadata`, timestamps.
- **`items`** — `key` (unique), `name`, `stackable` (bool), `max_stack`,
  `metadata`, timestamps.

**Balances (fast reads):**

- **`wallets`** — one row per `(user_id, currency_key)`: `balance` (integer,
  minor units), timestamps. `unique_index([:user_id, :currency_key])`.
- **`inventory_entries`** — one row per `(user_id, item_key)` for stackables:
  `quantity`, `metadata`. `unique_index([:user_id, :item_key])`. Non-stackable
  items get one row per instance (own `id`), so the unique index is conditional
  on `stackable`.

**Truth (append-only):**

- **`ledger_entries`** — `user_id`, `currency_key` **or** `item_key`, `delta`
  (signed), `balance_after`, `reason` (string, e.g. `"quest_reward"`,
  `"purchase"`, `"admin_adjust"`), `ref_type` + `ref_id` (what caused it),
  `idempotency_key` (nullable, **unique**), `metadata`, `inserted_at`.
  Append-only — no updates, no deletes. Partial `unique_index([:idempotency_key], where: "idempotency_key IS NOT NULL")`
  makes a credit **exactly-once** across job/webhook retries;
  `index([:user_id, :inserted_at])` for the per-user history page.

## Atomicity — the core correctness property

A credit/debit is a read-modify-write (read balance → check cap/floor → write
new balance → append ledger with `balance_after`), so per CONTRIBUTING
§Functionality it **holds an advisory lock**: add `:wallet` (and `:inventory`)
to `GameServer.Repo.AdvisoryLock` `@namespaces` (next free ids after
`matchmaking_sweep: 8`), keyed on `user_id`. Inside `GameServer.Lock.serialize(:wallet, user_id, fn -> … end)`:

1. Upsert-select the `wallets` row (create at 0 if absent).
2. Debit: reject with `{:error, :insufficient_funds}` if `balance + delta < 0`.
   Credit: reject with `{:error, :balance_cap}` if it would exceed
   `currency.max_balance`.
3. `Repo.update_all` the new balance (the atomic
   `fragment("? + ?", w.balance, ^delta)` form leaderboards already uses).
4. Insert the `ledger_entries` row with `balance_after` — in the **same
   transaction**, so balance and ledger can never diverge.

If an `idempotency_key` collides, the whole op is a no-op returning the prior
result (retry-safe). Items work identically against `inventory_entries`.

## `GameServer.Economy` — the context

Server-authoritative — **no public mutation endpoint**. Game code and other
contexts call:

```elixir
Economy.credit(user_id, "gold", 100, reason: "quest_reward", idempotency_key: quest_run_id)
Economy.debit(user_id, "gold", 50, reason: "shop_buy", ref: {:item, item_id})
Economy.transfer(from_id, to_id, "gold", 25, reason: "trade")   # two ledger rows, one txn
Economy.grant_item(user_id, "sword", 1, reason: "quest_reward")
Economy.consume_item(user_id, "potion", 1)
Economy.balance(user_id, "gold")            # + balances/1
Economy.list_inventory(user_id, opts)       # paginated + count_inventory/1
Economy.list_ledger(user_id, opts)          # paginated + count_ledger/1
```

`transfer/5` locks **both** users (ordered by id to avoid deadlock) and writes a
debit + credit ledger pair atomically.

## Hooks (all six places, per CONTRIBUTING §Hooks)

- **`before_currency_change(user_id, currency_key, delta, ctx)`** — pipeline
  veto/clamp (anti-cheat ceilings, event multipliers). Add to
  `lifecycle_pipeline_hook?/2` + a `normalize_pipeline_args/3` clause.
- **`after_currency_changed(ledger_entry)`** — observe (analytics, achievements).
- **`after_item_changed(ledger_entry)`** — observe.

Resolved **outside** the lock and deferred after commit (`defer/1`) — never
dispatch a hook inside the wallet lock/transaction (CONTRIBUTING §Hooks). All in
all six places, RPC-blocked, SDK-mirrored.

## Reads / Web API

- `GET /me/wallet` — all balances (small, uncached-or-versioned).
- `GET /me/inventory` — paginated `meta` block.
- `GET /me/ledger` — paginated history.
- Currency/item **definitions** are readable (catalog) via a listing endpoint
  behind a `LIST_*_ENABLED` gate; **mutations are admin/hook-only**.

## Payments integration (first real caller)

`Payments` stops owning balances. On a validated purchase that grants currency
or items, it calls `Economy.credit/grant_item` with
`idempotency_key = purchase_id` — so provider webhook re-delivery can't
double-grant. A refund/revoke debits with `reason: "refund"`. This is the
"generic currencies" replacement for the deleted `wallet_ledger_entries`.

## Limits (`GameServer.Limits`, auto `LIMIT_*`, `@limit_categories`)

`max_currencies`, `max_items`, `max_currency_balance`, `max_inventory_stack`,
`max_inventory_distinct_items`, `max_ledger_reason` (len).

## Admin

- `admin_live/economy.ex` — currency & item definitions CRUD; a per-user wallet
  + inventory viewer with an **adjust** action (writes a ledgered
  `admin_adjust`, never a raw balance set); a ledger browser (filter by
  user/currency/reason, paginated).
- `/admin` stat card (total currencies/items, circulating supply per currency) +
  routes + nav + `admin_pages_render_test`.
- Admin API parity for every action (define, adjust, read ledger).

## "Update everywhere" — file list

- **README** Features: Economy / inventory. **CHANGELOG** `[added]` Economy
  (currencies, wallet, ledger, inventory).
- **.env.example** — the `LIMIT_*` caps.
- **host_public_docs/** — new Economy page (currency/item authoring, the
  credit/debit/idempotency contract); Data Schema gains the five tables.
- **api_spec.ex** — feature list + read endpoints.
- **SDK** — `Economy` stub + struct stubs (currency, item, wallet, ledger entry);
  `@sdk_modules`, `gen.sdk`, placeholder rules; hooks mirrored.
- **AdvisoryLock** — `:wallet` / `:inventory` namespaces documented in the
  moduledoc.
- **runtime_introspection.ex** — economy stats (definitions, supply, ledger
  volume).
- **i18n** — 30 locales; **mix demo.seed** — a couple of currencies/items,
  seeded balances + ledger history so the admin views show volume.

## Deferred / rejected

- **Player-to-player market/auction house: defer.** `transfer/5` is the
  primitive; a listing/escrow market is a whole feature that rides on it later.
- **Decimal/float currencies: rejected.** Integer minor units (`precision`) only
  — floats can't represent money without rounding drift, and every ledger sum
  must reconcile exactly.
- **Cross-currency exchange rates: defer.** `transfer` is same-currency; an FX
  layer is a plugin concern until there's demand.

## Definition of done (CONTRIBUTING)

- [ ] Migrations for the five tables apply on SQLite **and**
      `GAMEND_DB_ADAPTER=postgres`; idempotency + history indexes as above.
- [ ] Credit/debit/transfer/item ops atomic under `:wallet`/`:inventory` locks,
      ledgered in the same txn, cap/floor enforced, idempotency-key exactly-once.
- [ ] Paginated `list_*`/`count_*`; `Limits` caps in changesets.
- [ ] Hooks `before_currency_change` / `after_currency_changed` /
      `after_item_changed` in all six places, RPC-blocked, SDK-mirrored.
- [ ] Payments re-wired to grant through `Economy` with `idempotency_key`.
- [ ] Admin page + `/admin` card + routes + nav + `admin_pages_render_test`;
      admin API parity.
- [ ] Docs, `.env.example`, CHANGELOG, README, `api_spec.ex`; i18n 30 locales.
- [ ] Tests: context + controller + admin + LiveView, both adapters; boot and
      actually credit, over-debit (rejected), transfer, and prove a duplicate
      idempotency key is a no-op. Concurrency test: parallel debits never
      oversell.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.
