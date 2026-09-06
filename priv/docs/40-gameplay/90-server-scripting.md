---
icon: hero-command-line
---

# Server-side scripting & hooks

[Scripting Interface](https://docs.gamend.org/Gamend.Hooks.html)

The application exposes a lightweight server-side scripting surface via the `Gamend.Hooks` behaviour. Hooks let you run custom code on lifecycle events (eg. user register/login, lobby create/update) and optionally expose RPC functions.

Hooks can be written in **Elixir** (this guide), in **GDScript** (see [GDScript hooks](95-gdscript-hooks.md)), or in any other BEAM language; see [Other BEAM languages](#other-beam-languages-gleam-lfe-erlang) below.

## Add a lifecycle callback

Implement the behaviour in a hooks module:

```elixir
# your_hook_module.ex

defmodule MyApp.HooksImpl do
    @behaviour Gamend.Hooks

    @impl true
    def after_user_register(user) do
        # safe database update (non-blocking in hooks is recommended)
        Gamend.Accounts.update_user(user, %{metadata: Map.put(user.metadata || %{}, "from_hook", true)})
    :ok
    end

    @impl true
    def after_user_updated(_user) do
        # React to any user profile change (metadata, display name, etc.)
        :ok
    end
end
```

### Loading hooks via OTP plugins

Hooks are loaded from OTP plugin applications under `modules/plugins/*`. You can override the plugins directory using:

```elixir
GAMEND_CONTENT_PLUGINS_DIR=modules/plugins
```

Each plugin is an OTP app directory with an `ebin` folder containing a `.app` file and compiled `.beam` modules. The plugin's `.app` env must include a `hooks_module` entry pointing at the module name.

### Gating resource creation with before hooks

"Before" hooks let you block operations or modify attributes before they are persisted. For example, `before_group_create/2` receives the full user struct and the group attributes map, so you can check metadata (coins, level, etc.) to decide whether the user is allowed to create a group:

```elixir
@impl true
def before_group_create(user, attrs) do
  coins = get_in(user.metadata, ["coins"]) || 0

  if coins >= 50 do
    {:ok, attrs}
  else
    {:error, :not_enough_coins}
  end
end
```

Other "before" hooks follow the same pattern: `before_lobby_create/1`, `before_lobby_join/3`, `before_group_join/3`, `before_user_update/2`. Return {:ok, attrs} (or the appropriate tuple) to allow, {:error, reason} to reject. At registration time, before_user_register/2 receives the tentative user and the registration attrs (including the generated username) on every signup path (email, device, and OAuth) and may adjust the attrs or abort. Tournaments have their own hook family (before/after_tournament_register, before_tournament_leave, tournament_match_ready, tournament_match_expired, before_tournament_result, after_tournament_match_resolved, after_tournament_finished); see the Tournaments guide for the match resolution contract. Matchmaking has its own family too (before_matchmaking_join, after_matchmaking_join, after_matchmaking_cancel, matchmaking_form_matches, after_matchmaking_matched); see the Matchmaking guide. matchmaking_form_matches/2 is the one hook that replaces built-in logic rather than gating it: it hands you a whole queue bucket and lets you group it yourself.

### Declaring what your plugin contributes

Three optional callbacks tell the server what your game adds, so it shows up in the admin Runtime page next to the built-in surface instead of being invisible. Notification codes are enforced: the server never reads a notification's type, so an undeclared code would be delivered and silently ignored by every client. It is rejected at write time instead. Realtime events are enforced at the push site for the same reason. Env vars are declaration only, since a plugin can always read one directly.

```elixir
def notification_types do
  %{"quest_completed" => "Player finished a quest"}
end

def realtime_events do
  %{"quest_progress" => "An objective counter moved"}
end

def env_vars do
  [%{name: "MYGAME_DIFFICULTY", default: "normal", description: "Global difficulty"},
   %{name: "MYGAME_MAX_BOTS", default: 8, description: "Bots per match"},
   %{name: "MYGAME_TUTORIAL", default: true, description: "Show the tutorial"}]
end

# The type comes from the default, so reads are already coerced —
# no String.to_integer/1 or == "true" at each call site.
Gamend.Config.get("MYGAME_MAX_BOTS")   # 8 (integer)
Gamend.Config.get("MYGAME_TUTORIAL")   # true (boolean)

# Pushing a declared event to one player — rides the existing
# user:<id> channel, so the client needs no new subscription.
Gamend.Realtime.push_to_user(user.id, "quest_progress", %{id: 7, step: 2})
```

Codes and event names are global: if two plugins declare the same one, the first in name order wins and the loser is logged. See example_hook for a working set.

### Quest hooks

before_quest_claim/3 can veto a player's claim (return an error tuple to reject; anything else allows; it never rewrites its args, and auto_claim quests skip it). after_quest_completed/1 and after_quest_claimed/1 observe the progress row asynchronously: chain the next quest, feed analytics, or push a custom notification. Report custom gameplay events from any hook with Gamend.Quests.report_event/4:

```elixir
@impl true
def before_quest_claim(_user_id, quest, _progress) do
# Example: event quests only claimable while the event runs
  if quest.kind == "event" and quest.ends_at &&
       DateTime.compare(DateTime.utc_now(), quest.ends_at) == :gt do
    {:error, :event_over}
  else
    :ok
  end
end

@impl true
def after_quest_completed(progress) do
# Advance your own systems when a quest completes
  MyGame.Story.on_quest_completed(progress.user_id, progress.quest_key)
  :ok
end

# From any hook: count a custom event toward matching quests
def on_enemy_killed(user_id, map) do
  Gamend.Quests.report_event(user_id, "enemy_killed", 1, %{"map" => map})
end
```

### Push hooks

before_push_send/2 runs once per recipient before any delivery job is enqueued. It receives the user id and the message as a string-keyed map; return {:ok, message} to allow (optionally rewritten, and the result is re-validated against the push limits) or {:error, reason} to drop the push for that user. It is where per-user opt-out, quiet hours, or moderation belong. after_push_sent/3 observes each device's final outcome: "delivered", "invalid" (token disabled), or "failed". Send a push from any hook with Gamend.Push.send_to_user/2. Delivery is queued, retried, and never blocks the caller:

```elixir
@impl true def before_push_send(user_id, message) do # Example: respect a per-user mute stored in KV case Gamend.KV.get("push_muted", user_id: user_id) do {:ok, %{value: %{"muted" => true}}} -> {:error, :muted} _ -> {:ok, message} end end # From any hook: ping an offline player def on_turn_ready(user_id, match_id) do Gamend.Push.send_to_user(user_id, %{ "title" => "Your move!", "body" => "It is your turn.", "data" => %{"match_id" => match_id}, "collapse_key" => "turn-#{match_id})
end
```

### Chat moderation hooks

Core already enforces the word filter and mutes inside `before_chat_message`: a
blocked word or a muted sender never reaches your hook. These two observe what
core did: `after_chat_message_reported/1` fires when a player reports a message
or the filter files one itself (`reporter_id` is nil then), and
`after_user_muted/1` fires whenever anyone is muted by an admin, lobby host, group
admin, party leader or a plugin. Both are fire-and-forget; the report is already
queued and the mute already in effect. They are where a strike policy lives,
since core deliberately ships none:

```elixir
@impl true
def after_chat_message_reported(report) do
  open = Gamend.Chat.count_reports(%{"reported_user_id" => report.reported_user_id, "status" => "open"})

  # Three open reports and you sit out an hour.
  if open >= 3 do
    Gamend.Chat.mute_user(report.reported_user_id, "global", nil, %{
      "expires_at" => DateTime.add(DateTime.utc_now(), 3600, :second),
      "reason" => "auto: #{open} open reports"
    })
  end

  :ok
end

@impl true
def after_user_muted(mute) do
  Gamend.Push.send_to_user(mute.user_id, %{
    "title" => "You have been muted",
    "body" => mute.reason || "Chat is disabled for you."
  })
end
```

### Ready check hooks

before_ready_check_open/2 can veto a check before it opens (veto-only: it never rewrites its args). after_ready_check_passed/1 is the "everyone answered ready" callback, the natural place to start the match. after_ready_check_failed/3 receives (check, reason, not_ready) where reason is "declined\

```elixir
@impl true
def after_ready_check_passed(%{lobby_id: lobby_id}) when is_binary(lobby_id) do
  Gamend.Lobbies.transition_state(Gamend.Lobbies.get_lobby(lobby_id), "starting")
end

# Refuse to start until the last check passed
@impl true
def before_lobby_state_change(lobby, _from, "playing") do
  if Gamend.ReadyChecks.passed?(lobby), do: :ok, else: {:error, :not_ready}
end

# Bots cannot press a button — answer for them
def ready_up_bots(check, bot_ids) do
  Enum.each(bot_ids, &Gamend.ReadyChecks.answer_for(check, &1, true))
end
```

### Exposing an RPC function

Hooks modules can also export arbitrary functions:

```elixir
defmodule MyApp.HooksImpl do
  @behaviour Gamend.Hooks

  def hello_world(name) do
    {:ok, "Hello, #{name}!"}
  end
end
```

You can now call this function via the API (or better yet from the client SDK's), eg:

```bash
curl -X POST https://your-gamend.com/api/v1/hooks/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"plugin":"my_game_hook","fn":"hello_world","args":["Alice"]}'
```

### Server-only privileges

A few domain functions accept options that the HTTP and channel surfaces never pass, so they are reachable only from server-side code. The main one is seating a player in a locked lobby:

```elixir
# Join succeeds even though the lobby is locked Gamend.Lobbies.join_lobby(user, lobby_id, %{bypass_lock: true})
```

Useful for reconnects, admin tooling, or seating a late player into a match already in progress. Capacity and blacklist checks still apply: bypass_lock only skips the lock, so it cannot be used to overfill a lobby or to put two players who blocked each other together.

### Background jobs & scheduling

For work that must survive a restart, retry on failure, or run later, enqueue a hook as a durable background job instead of doing it inline. Args are stored as JSON, so callbacks receive a string-keyed map:

```elixir
# Run now, retried with backoff on failure Gamend.Jobs.enqueue_hook(:on_welcome_email, %{"user_id" => user.id}) # Run in 24 hours Gamend.Jobs.enqueue_in(24 * 60 * 60, :on_trial_reminder, %{"user_id" => user.id}) def on_welcome_email(%{"user_id" => user_id}), do: :ok
```

For recurring work, register cron-like schedules from your after_startup hook. These are durable and distributed-safe, and exactly one instance runs each job per period:

```elixir
def after_startup do Gamend.Schedule.hourly(:on_hourly) Gamend.Schedule.daily(:on_morning_report, hour: 9) Gamend.Schedule.cron(:sweep, "*/15 * * * *", :on_every_15m) :ok end
```

### Virtual economy (wallets)

Grant and spend virtual currency from hooks. Currencies are free-form codes; every change is atomic and recorded in a ledger, so two concurrent spends can never overspend:

```elixir
# On match win, reward the player Gamend.Economy.grant(user_id, "gold", 100, reason: "match_reward") # Charge for a store item — refuses to go negative case Gamend.Economy.spend(user_id, "gold", 30, reason: "store_purchase") do {:ok, balance} -> {:ok, %{"gold" => balance}} {:error, :insufficient_funds} -> {:error, "not enough gold
end

Gamend.Economy.balances(user_id)   # => %{"gold" => 70}

# Items work the same way, via Gamend.Inventory
Gamend.Inventory.grant_item(user_id, "health_potion", 3)
Gamend.Inventory.consume_item(user_id, "health_potion", 1)  # {:error, :insufficient_items} if empty
```

Pass idempotency_key: so an at-least-once job or a client retry can't double-apply. These are server-authoritative: clients only read their wallet (GET /me/wallet).

React to changes made anywhere (admin, jobs, another plugin) with the after_wallet_changed / after_inventory_changed hooks:

```elixir
def after_wallet_changed(%{user_id: id, currency: cur, balance: bal, delta: d}) do
  # e.g. sync a Discord role when coins cross a threshold
  :ok
end
```

### What works, and what to avoid

- Keep hooks fast and resilient: avoid long blocking work in the main request path. Use `Task.start` for background processing.
- When returning values from lifecycle hooks, prefer a `{:ok, map}` shape for "before" hooks that may modify attrs. Return `{:error, reason}` to reject flows; domain code will convert to `{:hook_rejected, reason}`.
- Do not return structs as hook results intended to be used as params; always return plain maps when you intend to pass modified params into changesets.
- Tests that modify global plugin configuration (eg. `GAMEND_CONTENT_PLUGINS_DIR` ) should run serially (`async: false`) and restore env via `on_exit` to avoid cross-test races.
- Be careful modifying user or lobby data from hooks: reuse high-level domain functions (eg. `Gamend.Accounts.update_user/2`, `Gamend.Lobbies.update_lobby/2` ) so changes are validated and broadcast consistently.

## Server signals

Hooks are request-shaped: something happens, your code runs, it returns. When
one part of a plugin needs to *wait* for another part, use `Gamend.Signals`,
the server's answer to Godot's `signal` / `emit` / `await`. Signals are scoped
to your plugin, so two plugins can use the same name without colliding, and
they ride `Phoenix.PubSub`, so an emit reaches every node in a cluster.

```elixir
# One hook finishes a level and announces it — :ok whether or not
# anyone is listening; an unheard signal is dropped, as in Godot.
Gamend.Signals.emit("my_game", "level_up", [user_id, 5])

# Another waits for it. Subscribe BEFORE await, not inside it —
# a signal emitted between the two would otherwise be missed.
Gamend.Signals.subscribe("my_game", "level_up")
{:ok, [user_id, level]} = Gamend.Signals.await("my_game", "level_up", 10_000)
```

`await/3` returns `{:ok, payload}` (whatever the emitter passed, unchanged)
or `{:error, :timeout}` after the given timeout (30 seconds by default). A
subscription belongs to the process that made it, so when a hook's task ends
the subscription goes with it; `Gamend.Signals.topic/2` names the underlying
PubSub topic for a plugin that wants to subscribe by hand. GDScript plugins
get the subscribe-first rule for free: the GDScript front end subscribes at
function entry for every signal the function awaits.

## Other BEAM languages (Gleam, LFE, Erlang)

Hooks are dispatched with `function_exported?/3`, so a plugin only has to
*export* the callbacks it implements; it never has to be an Elixir module. Any
language that compiles to BEAM bytecode works, with no bridge and no runtime
cost.

A Gleam plugin is an ordinary Gleam project plus a bundling step. `gleam export
erlang-shipment` already emits one directory per OTP app with a real `.app`
file; the only key it cannot express is `hooks_module`, so the bundle script
patches that in.

```gleam
// An Elixir module is the atom `Elixir.<Name>` on the BEAM, so a gamend
// context needs no shim -- only a type signature.
@external(erlang, "Elixir.Gamend.Economy", "grant")
fn economy_grant(user_id: String, currency: String, amount: Int,
                 opts: List(#(Dynamic, String))) -> Dynamic

pub fn after_user_register(user: Dynamic) -> Dynamic {
  let user_id = string_field(user, "id")
  let _ = economy_grant(user_id, "gold", 250, [#(atom("reason"), "starter")])
  atom("ok")
}
```

Hook payloads arrive as Elixir structs, which on the BEAM are maps with atom
keys, so `maps:get/2` plus a decoder reads a field out. A Gleam `Dict` *is* an
Erlang map, so anything gamend guards with `is_map/1` takes one directly.

The trade-off is the SDK: `sdk/` ships Elixir stub modules with typespecs, so
an Elixir plugin gets autocomplete, `mix gen.sdk` and Dialyzer. From another
language every context call is a hand-written `@external` declaration, and
nothing checks it until it runs.

A complete, runnable example is in
[`modules/plugins_examples/example_gleam`](https://github.com/appsinacup/gamend/tree/main/modules/plugins_examples/example_gleam).

## Every hook

79 callbacks, all optional; implement only what you need. A `before_*`
hook returns `{:ok, value}` to continue (optionally rewriting the value) or
`{:error, reason}` to reject the operation. An `after_*` hook runs once the
change is committed and its return value is ignored.

| Domain | `before_*` (may veto) | `after_*` (observe) |
|---|---|---|
| Lifecycle | `before_stop` | `after_startup` |
| Users | `before_user_register` `before_user_update` | `after_user_deleted` `after_user_logged_in` `after_user_offline` `after_user_online` `after_user_register` `after_user_updated` |
| Lobbies | `before_lobby_create` `before_lobby_delete` `before_lobby_join` `before_lobby_kick` `before_lobby_leave` `before_lobby_state_change` `before_lobby_update` | `after_lobby_create` `after_lobby_deleted` `after_lobby_host_change` `after_lobby_join` `after_lobby_kick` `after_lobby_leave` `after_lobby_state_changed` `after_lobby_updated` |
| Parties | `before_party_create` `before_party_join` `before_party_kick` `before_party_update` | `after_party_create` `after_party_disband` `after_party_join` `after_party_kick` `after_party_leave` `after_party_updated` |
| Groups | `before_group_create` `before_group_delete` `before_group_join` `before_group_kick` `before_group_update` | `after_group_create` `after_group_deleted` `after_group_join` `after_group_kick` `after_group_leave` `after_group_updated` |
| Chat | `before_chat_message` | `after_chat_message` `after_chat_message_reported` `after_user_muted` |
| Quests | `before_quest_claim` | `after_quest_claimed` `after_quest_completed` |
| Matchmaking | `before_matchmaking_join` | `after_matchmaking_cancel` `after_matchmaking_join` `after_matchmaking_matched` |
| Ready checks | `before_ready_check_open` | `after_ready_check_failed` `after_ready_check_passed` |
| Tournaments | `before_tournament_leave` `before_tournament_register` `before_tournament_result` | `after_tournament_finished` `after_tournament_match_resolved` `after_tournament_register` |
| Leaderboards | — | `after_score_submitted` |
| Key-value | `before_kv_get` | — |
| Wallets | — | `after_wallet_changed` |
| Inventory | — | `after_inventory_changed` |
| Purchases | `before_purchase` | `after_purchase_fulfilled` `after_purchase_revoked` |
| Entitlements | — | `after_entitlement_changed` |
| Push | `before_push_send` | `after_push_sent` |

Each callback's exact signature, arguments and return contract is in the
[`Gamend.Hooks` docs](https://docs.gamend.org/Gamend.Hooks.html). The
[admin runtime page](/admin/runtime) shows the same list for *your* server,
including which plugin implements what.
