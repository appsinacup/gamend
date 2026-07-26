# Regenerating currencies — lives, energy, stamina

Goal: let a currency refill itself over time. One declaration on the currency,
balances folded lazily from a timestamp, no timers anywhere, and the parameters
published so the client can run the same countdown.

## Why core

`GameServer.Economy` already models balances, atomic spends and a ledger, and
its own moduledoc names `"energy"` as an example currency — but a wallet only
ever changes when something writes to it. Every free-to-play game then bolts a
regenerating resource on the side.

Polyglot's `lives.ex` is that bolt-on: max 5, one life per 900 s, stored as
`user.metadata["lives"] = %{count, updated_at}`, folded on read, with the client
mirroring the arithmetic in `lives_logic.gd`. It is 200 lines and it is careful
about the two things that are easy to get wrong (below) — which is precisely why
it should not be re-derived per game. It also sits in `user.metadata`, outside
the economy, so a life is not spendable, not auditable and not visible to the
admin economy page.

The mechanic is not niche: lives, energy, stamina, action points, ship fuel and
free-roll counters are all the same three numbers — **amount, interval, cap**.

## Declaration

Currencies are free-form strings today (`wallets.currency`), which stays true —
a game can keep writing `"gold"` with no declaration. Regen needs configuration,
so it rides the existing plugin-declaration mechanism
(`GameServer.Hooks.Declarations`, alongside `notification_types/0`):

```elixir
def currencies do
  %{
    "lives"  => %{description: "Boat lives", regen: %{amount: 1, interval_sec: 900, cap: 5}},
    "coins"  => %{description: "Soft currency"}          # no regen: ordinary wallet
  }
end
```

Undeclared currencies keep working exactly as now (no regen, no cap). The
declaration is also what the admin runtime page and `/config` publish, so the
client can compute the same countdown instead of hardcoding 900.

Note the difference from `lobby_states/0`, which was removed from
`Declarations` in July 2026: that one declared *words core attached no meaning
to*, so the registry bought nothing over documentation. `currencies/0` declares
**behaviour core executes** — the fold below reads `amount`, `interval_sec` and
`cap` on every balance read — which puts it in the enforced category alongside
`notification_types/0`, not the observability-only one.

## Data model

One nullable column on the existing table:

```
wallets
  … existing …
  regen_at  utc_datetime  -- anchor for the fold; NULL for non-regen currencies
```

No new table, no ledger rows for regen. **Regen is derived, not recorded** — a
row per tick would write more ledger than the game does, for a value that is a
pure function of `(balance, regen_at, now)`. The ledger keeps recording real
credits and debits, including the *materialized* regen that a spend implies.

## The fold

The semantics are polyglot's, which are the correct ones:

```
elapsed   = now - regen_at
gained    = min(elapsed div interval, cap - balance)
balance'  = balance + gained * amount
regen_at' = if balance' >= cap, do: now, else: regen_at + gained * interval
```

Two rules that look like details and are not:

1. **Consumed intervals advance the anchor; the remainder is kept.** Adding
   `gained * interval` rather than setting `regen_at = now` preserves partial
   progress toward the next unit. Resetting to `now` on every read makes a
   player who checks their lives often regenerate slower — a bug that is
   invisible in tests and infuriating in play.
2. **At the cap the anchor tracks `now`.** Otherwise a player sitting at full
   for a day banks a day of intervals and refills instantly after spending five.
   Leaving the cap is what starts the clock.

`balance/2` folds **without writing** — reads stay reads. A write path
(`debit/credit`) folds first, then applies its own delta, inside the existing
atomic update, so the persisted row is always consistent with the last write.

## API

```elixir
Economy.balance(user_id, "lives")        # folded, no write
Economy.debit(user_id, "lives", 1, ...)  # folds, then the existing atomic spend
Economy.regen_state(user_id, "lives")
#=> %{balance: 3, cap: 5, amount: 1, interval_sec: 900,
#     next_at: ~U[…], full_at: ~U[…], server_now: ~U[…]}
```

`regen_state/2` is the client contract: `next_at` drives the "next life in
04:12" countdown and `full_at` the "full in 34:12" one, and `server_now` lets
the client correct its own clock skew (see
[netcode-sync.md](netcode-sync.md), same field, same meaning).

Overspend safety is unchanged: `debit/4` keeps its atomic
`balance = balance - x WHERE balance >= x`, applied to the folded value in the
same statement, so concurrent spends cannot mint a life between the fold and the
write.

Admin grants (`credit/4`) may exceed the cap — a support grant of 10 lives on a
cap of 5 should not silently vanish. Overflow simply sits above the cap and does
not regenerate until it falls below; the fold's `min(_, cap - balance)` already
yields 0 there. This is stated in the docs because the alternative (clamping a
support grant) is the more surprising behaviour.

## Wire

- `wallet_updated` (existing realtime event) gains `regen_at`, `cap` and
  `next_at` for regen currencies. Protobuf message updated in
  `proto/gamend_realtime.proto` with `EventCodec` clauses and Godot handling.
- No new event: a life regenerating is not a server event, it is the passage of
  time. The client counts down locally from `regen_state/2` and re-reads on
  focus. That is the whole point of the timestamp model — **nothing fires at the
  moment a life returns**, on the server or the wire.
- `GET /me/wallets` returns the folded balances, so a client that does nothing
  clever is still correct.

## Admin

Economy page shows the folded balance, the cap and the next-tick time per regen
currency; the currency list shows regen parameters from the declaration. The
existing grant/deduct actions work unchanged (they go through `credit`/`debit`,
so they fold first).

## What this deliberately does not do

- **No timers, no jobs, no scheduled refills.** State resolves on read. A server
  that is down for an hour returns players' lives correctly on the next request.
- **No per-currency cooldown UI, no "watch an ad to refill", no purchase
  bridge.** Buying a life is `credit/4` with an idempotency key — the game's
  call, through the existing payments/economy path.
- **No regen on inventory items.** Items are counted, not accrued; a game that
  wants a regenerating item wants a currency.

## Alternatives considered

- **Leave it in `user.metadata`, as polyglot does.** Cheapest, and wrong: the
  value is a currency in everything but name — spendable, grantable, worth
  auditing — and metadata gives it none of the economy's atomicity.
- **A separate `resources` table with its own context.** A second, parallel
  balance system with its own spend path, its own races and its own admin page.
  Regen is three fields on a currency, not a new domain.
- **Materialize regen with an Oban job per user per interval.** Precise events
  ("your lives are full") at the cost of a job per player per interval —
  unbounded work for a value that is already a pure function. If push
  notifications for "lives full" are wanted later, that is one scheduled push at
  `full_at`, scheduled at spend time, not a tick loop.
- **Store `next_at` instead of `regen_at`.** Equivalent, but it has to be
  rewritten whenever the cap or interval changes; an anchor plus the declared
  parameters survives a tuning change without a migration.

## Definition of done (CONTRIBUTING)

- [ ] Migration adds `wallets.regen_at` (nullable); applies on SQLite **and**
      `GAMEND_DB_ADAPTER=postgres`.
- [ ] `currencies/0` declaration registered in `Hooks.Declarations`, surfaced on
      the admin runtime page, published to clients via `/config`.
- [ ] `balance/2` folds without writing; `debit`/`credit` fold inside the
      existing atomic update; no ledger rows for regen.
- [ ] Partial-progress and at-cap anchor rules covered by tests, including the
      "reading often must not slow regen" case and the "sitting at cap must not
      bank" case.
- [ ] Concurrent spends cannot overspend a folded balance (both adapters).
- [ ] `regen_state/2` returns `next_at`, `full_at`, `server_now`; documented as
      the client's countdown source.
- [ ] `wallet_updated` carries regen fields, with protobuf + `EventCodec` +
      Godot parity.
- [ ] Admin economy page shows folded balance, cap and next tick; API parity.
- [ ] Docs (Economy page); any new setting declared on a provider with
      `.env.example` regenerated; `api_spec.ex`,
      CHANGELOG, i18n.
- [ ] Polyglot's `Lives` and `Shields` collapse onto declared currencies
      (tracked in that repo).
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin warning-free.
