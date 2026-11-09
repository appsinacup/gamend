---
icon: hero-ticket-solid
---

# Redemption codes

Hand out a code, and the player who types it gets rewards or access.

A code finishes a [quest](/docs/quests), so the quest says what the code gives and when it works: reward codes for an event, invitation keys for a test server.

## Make your first code

1. Open [/admin/quests](/admin/quests) and press **Create Quest**. Give it a key (`spring_gift`), a title and its rewards (`[{"type": "currency", "code": "gold", "amount": 100}]`). Tick **Only by code** and leave **Reset cycle** on `never`.
2. Press **Codes** on the quest's row.
3. Under **Generate**, set **How many** and **Uses per code**, then press **Generate**. For a code you choose (`SPRING2026`, `春节快乐`), use **Add one code**.
4. Copy the codes from the table, or press **Download CSV**.
5. Give players a code and a link to `/redeem?quest=spring_gift`. They type it, press **Redeem**, and the rewards are paid at once.

A code-only quest has no objectives, no group and no prerequisite. A code is the only way to finish it.

## Who can use a code

| Uses on a code | Who can redeem it |
|---|---|
| `1` | One player |
| `N` | The first N players |
| blank (`max_uses: null`) | Every player, once each |

A player redeems a quest once, by any of its codes.

A generated code looks like `ABCD-EFGH-JKMN-PQRS`. Spaces, dashes, letter case and full-width characters do not matter when a player types one. Every code is unique across all quests, compared the same way.

## Redeem from a game

```text
POST /api/v1/me/quests/redeem
{"token": "ABCD-EFGH-JKMN-PQRS"}
```

The client SDKs call it `redeem_quest_code`. It answers `progress` and `rewards`, like a claim, and pays at once whatever the quest's `auto_claim` says.

| Situation | Answer | |
|---|---|---|
| Unknown, expired, revoked, disabled, used up | 404 `code_not_found` | One answer for every miss |
| This player has this quest, by any code | 409 `already_redeemed` | |
| A guest, where `:quest_claims` needs an account | 403 `account_required` | `config :gamend_core, Gamend.AccountRequired, [:quest_claims]` |
| Too many tries | 429 `redeem_rate_limit` | See [Limits](#limits) |
| `before_quest_claim` refused | 403 `rejected` | The hook's words. The code is not spent |

`GET /api/v1/quests/redeemable` lists the quests a code can finish now, and `?quest=spring_gift` narrows it to one. `GAMEND_FEATURES_LIST_QUESTS` gates it.

## The /redeem page

`/redeem` lists every open code-only quest. `/redeem?quest=spring_gift` shows just that one, so an email can link to it. The link names the quest, never a code. `/quests` links to the page while a listed code-only quest is open.

A signed-out visitor who submits a working code gets a guest account. A code that does not work makes no account.

A host with no redemption page leaves it out of its router: `except: [:redeem]` on `gamend_current_user_routes`. Its link on `/quests` goes with it. The API stays, so a game can still redeem.

## Make codes from a plugin

```elixir
alias Gamend.Quests

{:ok, quest} =
  Quests.create_quest(%{
    key: "welcome_gift",
    title: "Welcome gift",
    code_only: true,
    rewards: [%{type: "currency", code: "gold", amount: 100}]
  })

# One code every player can use once.
{:ok, _code} = Quests.create_code(quest, %{token: "WELCOME-CODE", max_uses: nil})

# 500 single-use codes. Answers how many it made.
{:ok, _made} = Quests.generate_codes(quest, 500, max_uses: 1)
```

A token already in use fails on `:token`, so a boot task checks `Quests.count_codes(quest.key, search: token)` first.

## Make codes from the admin API

| To | Call | Body |
|---|---|---|
| List, or find one | `GET /api/v1/admin/quests/:id/codes` | `?search=<code>` |
| Add one | `POST /api/v1/admin/quests/:id/codes` | `{"token": "SPRING2026", "max_uses": null}` |
| Generate | `POST /api/v1/admin/quests/:id/codes/generate` | `{"count": 500, "max_uses": 1}` |
| Revoke or restore | `PATCH /api/v1/admin/quest_codes/:id` | `{"status": "revoked"}` or `{"status": "active"}` |

The first three take the quest's id, the last the code's. Left out, `max_uses` is `1` on Generate and every player on Add one.

## Recipes

**A key that unlocks a game mode** is a quest with no rewards. A player has a progress row for it only once they redeem, so the gate is one line in a hook:

```elixir
Gamend.Quests.get_progress(user_id, "beta_access") != nil
```

**A key you do not advertise:** tick **Hidden** on the quest. It stays off `/redeem` and the redeemable list until the player has redeemed it, and its codes work as usual.

**Where a redemption came from:** give each batch its own metadata, such as `{"channel": "newsletter"}`. It is copied onto each player's progress row, so `after_quest_completed/1` can read `progress.metadata`. Players can read it there too, so keep private notes out of it.

**A shared code on several devices:** a guest's wallet moves into the account it signs in to, so one person could redeem a shared code as several guests and sign each in. To stop that, refuse in the hook. `progress.code_id` says which code, and nothing is written yet:

```elixir
def before_quest_claim(user_id, %{code_only: true}, %{code_id: code_id}) do
  guest? = user_id |> Gamend.Accounts.get_user() |> Gamend.Accounts.User.anonymous?()
  shared? = Gamend.Quests.get_code(code_id).max_uses != 1

  if guest? and shared?, do: {:error, "Register to redeem this code"}, else: :ok
end

def before_quest_claim(_user_id, _quest, _progress), do: :ok
```

## Stop codes

| To stop | Do this |
|---|---|
| One code | **Revoke** on its row. **Restore** brings it back |
| Every code of a quest | Untick **Active** on the quest |
| Every code at a set time | Set **Ends at** on the quest (`ends_at`) |

A stopped code answers `code_not_found`, like an unknown one.

## Limits

| Setting | Default | |
|---|---|---|
| `GAMEND_LIMITS_MAX_REDEEM_ATTEMPTS_PER_MIN` | `10` | Tries per player per minute. `0` disables |
| `GAMEND_LIMITS_MAX_CODES_PER_GENERATE` | `10000` | Codes one Generate makes. To have more, run it again |
| `GAMEND_LIMITS_MAX_QUEST_CODE_TOKEN` | `128` | Longest code, in characters once spaces and dashes are gone. Up to 512 takes effect |

## Reference

- **Events:** a redemption sends `quest_completed`, then `quest_claimed`.
- **Hooks:** `before_quest_claim/3` runs first and may refuse. `after_quest_completed/1` and `after_quest_claimed/1` follow.
- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Quests`](https://docs.gamend.org/Gamend.Quests.html) - `redeem_code/2`, `create_code/2`, `generate_codes/3`, `set_code_status/2`.
