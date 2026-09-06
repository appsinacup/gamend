---
icon: hero-banknotes
---

# Economy & Inventory

Virtual-currency wallets and item stacks, both backed by an append-only ledger. Currencies and items are free-form string codes the game invents (`"gold"`, `"gems"`, `"health_potion"`); every balance change is a single atomic SQL statement recorded in the ledger, so concurrent spends can never overdraw and every mutation is auditable after the fact.

## How it works

A wallet row is one `(user, currency)` pair holding a non-negative integer balance; an inventory row is one `(user, item)` pair holding a quantity plus per-stack `metadata`. Grants upsert-and-increment, spends are a conditional decrement that only succeeds when enough is there. The balance is never left negative, and a failed spend returns `{:error, :insufficient_funds}` (`{:error, :insufficient_items}` for stacks) instead of writing anything.

Every successful change appends a ledger entry in the same transaction: the delta, the balance after, a `reason` label, and optional `metadata`. The ledger is append-only: nothing edits a wallet without leaving a row that explains it.

|  | Wallets (`Gamend.Economy`) | Items (`Gamend.Inventory`) |
|---|---|---|
| Unit | integer balance per currency code | integer quantity per item code |
| Add | `grant/4` | `grant_item/4` |
| Remove | `spend/4` → `:insufficient_funds` | `consume_item/4` → `:insufficient_items` |
| Read | `balance/2`, `balances/1` | `quantity/2`, `inventory/1` |
| Extras | — | `set_metadata/3` per stack |

Codes are 1–64 byte strings; anything else is `{:error, :invalid_currency}` / `{:error, :invalid_item}`. Granting an amount of `0` is a no-op that returns the current balance, not an error. A reward that works out to nothing after caps or discounts should not crash.

**Idempotency.** Pass `:idempotency_key` and a retried call (network retry, at-least-once job) becomes a no-op that returns the current balance. The key is enforced by the ledger itself, so even two concurrent calls racing with the same key apply exactly once.

**Server-authoritative.** Clients only read their wallet and inventory. All mutations happen server-side, through hooks, admin tools and quest rewards. There is deliberately no client "add currency" endpoint.

## Virtual currency vs. real money

This system is game currency; real-money purchases are the separate [Payments](/docs/payments) system. Payments validates provider transactions and creates purchases and entitlements. It never credits a wallet by itself. To sell a coin pack, grant the coins from the `after_purchase_fulfilled/1` hook, keyed on the purchase so a redelivered webhook cannot double-grant:

```elixir
def after_purchase_fulfilled(purchase) do
  Gamend.Economy.grant(purchase.user_id, "coins", 100,
    reason: "purchase",
    idempotency_key: "purchase:#{purchase.id}"
  )
end
```

## HTTP API

Player endpoints are read-only (see [/api/docs](/api/docs)):

- `GET /api/v1/me/wallet`: all balances as a `{"currency": balance}` map.
- `GET /api/v1/me/wallet/ledger`: paginated history, filterable by `currency`.
- `GET /api/v1/me/inventory`: all held items as an `{"item": quantity}` map.

Mutations live only under the admin API: `POST /api/v1/admin/economy/grant`, `/spend`, `/grant_item`, `/consume_item` (each takes `user_id`, `currency`/item code, `amount`, optional `reason` and `idempotency_key`), plus `GET` listings at `/admin/economy/wallets`, `/ledger`, and `/items`.

## Realtime events

Both changes push to the player's `user:{user_id}` channel the moment they commit:

- `wallet_updated`: `currency + balance + delta`
- `inventory_updated`: `item + quantity + delta`

A client that renders its wallet from these events never needs to poll. When a quest payout is what moved the balance, a `quest_claimed` event arrives on the same channel as well.

## Server scripting

```elixir
# Credit and debit — every option is a ledger column
Gamend.Economy.grant(user_id, "gold", 100, reason: "match_reward")

case Gamend.Economy.spend(user_id, "gold", 30, reason: "store_purchase") do
  {:ok, balance} -> :ok
  {:error, :insufficient_funds} -> :not_enough_gold
end

Gamend.Economy.balance(user_id, "gold")   #=> 70
Gamend.Economy.balances(user_id)          #=> %{"gold" => 70}

# Items work the same way, plus per-stack metadata
Gamend.Inventory.grant_item(user_id, "health_potion", 3)
Gamend.Inventory.consume_item(user_id, "health_potion", 1)
Gamend.Inventory.inventory(user_id)       #=> %{"health_potion" => 2}
Gamend.Inventory.set_metadata(user_id, "sword", %{"enchant" => "fire"})
```

After every change the `after_wallet_changed/1` / `after_inventory_changed/1` hooks fire asynchronously with the user, code, new balance and delta, the place for analytics or reacting to a balance crossing a threshold.

**Quest rewards** pay in through these same functions: a reward of type `"currency"` calls `Economy.grant`, type `"item"` calls `Inventory.grant_item`, with reason `quest_reward:<quest key>` and a per-reward idempotency key. The exactly-once guarantee comes from the quest's completed → claimed transition being a single conditional update, and a partially failed grant is retried safely under the same keys (see the [Quests](/docs/quests) guide).

## Operations

- [Admin → Economy](/admin/economy) grants or spends against any user's wallet, grants or consumes items, and browses every wallet, stack, and ledger entry, searchable by username as well as user id.
- Players see their own read-only copy in `/users/settings?tab=wallet` (balances plus full ledger history) and `?tab=items` (stacks with metadata).
- `GAMEND_RETENTION_LEDGER_DAYS` prunes wallet and inventory ledger entries older than N days; the default `0` keeps them forever. Balances are never touched by retention.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Economy`](https://docs.gamend.org/Gamend.Economy.html) and
  [`Gamend.Inventory`](https://docs.gamend.org/Gamend.Inventory.html) - the functions a plugin calls, with their
  signatures and docs.
