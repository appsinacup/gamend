# `Gamend.Hooks`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/hooks.ex#L1)

Behaviour for application-level hooks / callbacks.

Implement this behaviour to receive lifecycle events from core flows
(registration, login, provider linking, deletion) and run custom logic.

A module implementing this behaviour can be configured with

    config :gamend_core, :hooks_module, MyApp.HooksImpl

The default implementation is a no-op.

# `after_startup`
*optional* 

```elixir
@callback after_startup() :: any()
```

# `before_stop`
*optional* 

```elixir
@callback before_stop() :: any()
```

# `on_custom_hook`
*optional* 

```elixir
@callback on_custom_hook(String.t(), list()) :: any()
```

Handle a dynamically-exported RPC function.

This callback is used for function names that were registered at runtime (eg.
via a plugin's `after_startup/0` return value) and therefore may not exist as
exported Elixir functions on the hooks module.

Receives the function name and the argument list.

# `after_user_deleted`
*optional* 

```elixir
@callback after_user_deleted(Gamend.Accounts.User.t()) :: any()
```

# `after_user_logged_in`
*optional* 

```elixir
@callback after_user_logged_in(Gamend.Accounts.User.t()) :: any()
```

# `after_user_muted`
*optional* 

```elixir
@callback after_user_muted(Gamend.Chat.Mute.t()) :: any()
```

# `after_user_offline`
*optional* 

```elixir
@callback after_user_offline(Gamend.Accounts.User.t()) :: any()
```

# `after_user_online`
*optional* 

```elixir
@callback after_user_online(Gamend.Accounts.User.t()) :: any()
```

# `after_user_register`
*optional* 

```elixir
@callback after_user_register(Gamend.Accounts.User.t()) :: any()
```

# `after_user_updated`
*optional* 

```elixir
@callback after_user_updated(Gamend.Accounts.User.t()) :: any()
```

# `before_user_register`
*optional* 

```elixir
@callback before_user_register(
  Gamend.Accounts.User.t(),
  Gamend.Types.user_registration_hook_attrs()
) ::
  hook_result(Gamend.Types.user_registration_hook_attrs())
```

Called before a new user row is inserted, on every registration path:
email, device, and all OAuth providers (which register mid-login).

Receives the tentative user (not yet inserted, `id` is `nil`) and the
registration attrs (string keys), which already contain the generated
`"username"`. Return `{:ok, attrs}` — possibly with a different username
or other changes — or `{:error, reason}` to abort the registration.

Core re-validates after all hooks ran, against `c:validate_username/1` or
its own rules and for uniqueness; this hook cannot skip that. A
hook-supplied username that is invalid or already taken is
replaced with a generated one (a plugin bug must never lock a player out
of login). For strict policy on player-initiated changes — profanity or
reserved names — use `c:before_user_update/2`, where errors are returned
to the player:

    def before_user_update(_user, %{"username" => name} = attrs) do
      if MyGame.Profanity.allowed?(name),
        do: {:ok, attrs},
        else: {:error, :invalid_username}
    end

    def before_user_update(_user, attrs), do: {:ok, attrs}

# `before_user_update`
*optional* 

```elixir
@callback before_user_update(Gamend.Accounts.User.t(), map()) :: hook_result(map())
```

# `validate_username`
*optional* 

```elixir
@callback validate_username(String.t()) :: :ok | {:error, String.t() | atom()} | :default
```

Replaces the built-in username rules for one handle.

Receives the handle as it will be stored (NFKC-normalized, lowercased) and
answers `:ok`, `{:error, message}` (shown to the player), or `:default` to
keep core's rules: letters and digits of one script or Latin with Chinese,
Japanese or Korean, joined by `.` `_` `-` (`Gamend.Accounts.Username`).
Core still enforces length, uniqueness and the absence of invisible
characters. The generator asks the same question, so a policy that refuses
every `word-1234` must hand out handles in `c:before_user_register/2`.
Modules are tried in order and the first real answer wins. A hook that
raises or times out counts as `:default`, so a plugin bug never locks a
player out.

# `after_lobby_create`
*optional* 

```elixir
@callback after_lobby_create(Gamend.Lobbies.Lobby.t()) :: any()
```

# `after_lobby_deleted`
*optional* 

```elixir
@callback after_lobby_deleted(Gamend.Lobbies.Lobby.t()) :: any()
```

# `after_lobby_host_change`
*optional* 

```elixir
@callback after_lobby_host_change(Gamend.Lobbies.Lobby.t(), String.t()) :: any()
```

# `after_lobby_join`
*optional* 

```elixir
@callback after_lobby_join(Gamend.Accounts.User.t(), Gamend.Lobbies.Lobby.t()) :: any()
```

# `after_lobby_kick`
*optional* 

```elixir
@callback after_lobby_kick(
  Gamend.Accounts.User.t(),
  Gamend.Accounts.User.t(),
  Gamend.Lobbies.Lobby.t()
) ::
  any()
```

# `after_lobby_leave`
*optional* 

```elixir
@callback after_lobby_leave(Gamend.Accounts.User.t(), Gamend.Lobbies.Lobby.t()) :: any()
```

# `after_lobby_state_changed`
*optional* 

```elixir
@callback after_lobby_state_changed(Gamend.Lobbies.Lobby.t(), String.t(), String.t()) ::
  any()
```

# `after_lobby_updated`
*optional* 

```elixir
@callback after_lobby_updated(Gamend.Lobbies.Lobby.t()) :: any()
```

# `before_lobby_create`
*optional* 

```elixir
@callback before_lobby_create(map()) :: hook_result(map())
```

# `before_lobby_delete`
*optional* 

```elixir
@callback before_lobby_delete(Gamend.Lobbies.Lobby.t()) ::
  hook_result(Gamend.Lobbies.Lobby.t())
```

# `before_lobby_join`
*optional* 

```elixir
@callback before_lobby_join(Gamend.Accounts.User.t(), Gamend.Lobbies.Lobby.t(), keyword()) ::
  hook_result({Gamend.Accounts.User.t(), Gamend.Lobbies.Lobby.t(), keyword()})
```

# `before_lobby_kick`
*optional* 

```elixir
@callback before_lobby_kick(
  Gamend.Accounts.User.t(),
  Gamend.Accounts.User.t(),
  Gamend.Lobbies.Lobby.t()
) ::
  hook_result(
    {Gamend.Accounts.User.t(), Gamend.Accounts.User.t(),
     Gamend.Lobbies.Lobby.t()}
  )
```

# `before_lobby_leave`
*optional* 

```elixir
@callback before_lobby_leave(Gamend.Accounts.User.t(), Gamend.Lobbies.Lobby.t()) :: any()
```

# `before_lobby_state_change`
*optional* 

```elixir
@callback before_lobby_state_change(Gamend.Lobbies.Lobby.t(), String.t(), String.t()) ::
  veto_result()
```

# `before_lobby_update`
*optional* 

```elixir
@callback before_lobby_update(Gamend.Lobbies.Lobby.t(), map()) :: hook_result(map())
```

# `after_group_create`
*optional* 

```elixir
@callback after_group_create(Gamend.Groups.Group.t()) :: any()
```

# `after_group_deleted`
*optional* 

```elixir
@callback after_group_deleted(Gamend.Groups.Group.t()) :: any()
```

# `after_group_join`
*optional* 

```elixir
@callback after_group_join(String.t(), Gamend.Groups.Group.t()) :: any()
```

# `after_group_kick`
*optional* 

```elixir
@callback after_group_kick(String.t(), String.t(), String.t()) :: any()
```

# `after_group_leave`
*optional* 

```elixir
@callback after_group_leave(String.t(), String.t()) :: any()
```

# `after_group_updated`
*optional* 

```elixir
@callback after_group_updated(Gamend.Groups.Group.t()) :: any()
```

# `before_group_create`
*optional* 

```elixir
@callback before_group_create(Gamend.Accounts.User.t(), map()) :: hook_result(map())
```

# `before_group_delete`
*optional* 

```elixir
@callback before_group_delete(Gamend.Groups.Group.t()) ::
  hook_result(Gamend.Groups.Group.t())
```

# `before_group_join`
*optional* 

```elixir
@callback before_group_join(Gamend.Accounts.User.t(), Gamend.Groups.Group.t(), map()) ::
  hook_result({Gamend.Accounts.User.t(), Gamend.Groups.Group.t(), map()})
```

# `before_group_kick`
*optional* 

```elixir
@callback before_group_kick(String.t(), String.t(), String.t()) ::
  hook_result({String.t(), String.t(), String.t()})
```

# `before_group_update`
*optional* 

```elixir
@callback before_group_update(Gamend.Groups.Group.t(), map()) :: hook_result(map())
```

# `after_party_create`
*optional* 

```elixir
@callback after_party_create(Gamend.Parties.Party.t()) :: any()
```

# `after_party_disband`
*optional* 

```elixir
@callback after_party_disband(Gamend.Parties.Party.t()) :: any()
```

# `after_party_join`
*optional* 

```elixir
@callback after_party_join(Gamend.Accounts.User.t(), Gamend.Parties.Party.t()) :: any()
```

# `after_party_kick`
*optional* 

```elixir
@callback after_party_kick(
  Gamend.Accounts.User.t(),
  Gamend.Accounts.User.t(),
  Gamend.Parties.Party.t()
) ::
  any()
```

# `after_party_leave`
*optional* 

```elixir
@callback after_party_leave(Gamend.Accounts.User.t(), String.t()) :: any()
```

# `after_party_updated`
*optional* 

```elixir
@callback after_party_updated(Gamend.Parties.Party.t()) :: any()
```

# `before_party_create`
*optional* 

```elixir
@callback before_party_create(Gamend.Accounts.User.t(), map()) :: hook_result(map())
```

# `before_party_join`
*optional* 

```elixir
@callback before_party_join(Gamend.Accounts.User.t(), Gamend.Parties.Party.t()) ::
  hook_result({Gamend.Accounts.User.t(), Gamend.Parties.Party.t()})
```

# `before_party_kick`
*optional* 

```elixir
@callback before_party_kick(
  Gamend.Accounts.User.t(),
  Gamend.Accounts.User.t(),
  Gamend.Parties.Party.t()
) ::
  hook_result(
    {Gamend.Accounts.User.t(), Gamend.Accounts.User.t(),
     Gamend.Parties.Party.t()}
  )
```

# `before_party_update`
*optional* 

```elixir
@callback before_party_update(Gamend.Parties.Party.t(), map()) :: hook_result(map())
```

# `after_chat_message`
*optional* 

```elixir
@callback after_chat_message(Gamend.Chat.Message.t()) :: any()
```

# `after_chat_message_reported`
*optional* 

```elixir
@callback after_chat_message_reported(Gamend.Chat.Report.t()) :: any()
```

# `before_chat_message`
*optional* 

```elixir
@callback before_chat_message(Gamend.Accounts.User.t(), map()) :: hook_result(map())
```

# `after_quest_claimed`
*optional* 

```elixir
@callback after_quest_claimed(Gamend.Quests.QuestProgress.t()) :: any()
```

# `after_quest_completed`
*optional* 

```elixir
@callback after_quest_completed(Gamend.Quests.QuestProgress.t()) :: any()
```

# `before_quest_claim`
*optional* 

```elixir
@callback before_quest_claim(
  String.t(),
  Gamend.Quests.Quest.t(),
  Gamend.Quests.QuestProgress.t()
) :: veto_result()
```

# `after_score_submitted`
*optional* 

```elixir
@callback after_score_submitted(Gamend.Leaderboards.Record.t()) :: any()
```

# `after_tournament_finished`
*optional* 

```elixir
@callback after_tournament_finished(Gamend.Tournaments.Tournament.t(), map()) :: any()
```

# `after_tournament_match_resolved`
*optional* 

```elixir
@callback after_tournament_match_resolved(Gamend.Tournaments.Match.t()) :: any()
```

# `after_tournament_register`
*optional* 

```elixir
@callback after_tournament_register(
  Gamend.Accounts.User.t(),
  Gamend.Tournaments.Tournament.t()
) :: any()
```

# `before_tournament_leave`
*optional* 

```elixir
@callback before_tournament_leave(
  Gamend.Accounts.User.t(),
  Gamend.Tournaments.Tournament.t()
) ::
  hook_result(term())
```

# `before_tournament_register`
*optional* 

```elixir
@callback before_tournament_register(
  Gamend.Accounts.User.t(),
  Gamend.Tournaments.Tournament.t()
) ::
  hook_result(term())
```

# `before_tournament_result`
*optional* 

```elixir
@callback before_tournament_result(Gamend.Tournaments.Match.t(), term()) ::
  hook_result(term())
```

# `tournament_match_expired`
*optional* 

```elixir
@callback tournament_match_expired(Gamend.Tournaments.Match.t()) :: any()
```

# `tournament_match_ready`
*optional* 

```elixir
@callback tournament_match_ready(Gamend.Tournaments.Match.t()) :: any()
```

# `after_matchmaking_cancel`
*optional* 

```elixir
@callback after_matchmaking_cancel(Ecto.UUID.t(), non_neg_integer()) :: any()
```

# `after_matchmaking_join`
*optional* 

```elixir
@callback after_matchmaking_join(Gamend.Accounts.User.t(), Gamend.Matchmaking.Ticket.t()) ::
  any()
```

# `after_matchmaking_matched`
*optional* 

```elixir
@callback after_matchmaking_matched([Gamend.Matchmaking.Ticket.t()], Ecto.UUID.t()) ::
  any()
```

# `before_matchmaking_join`
*optional* 

```elixir
@callback before_matchmaking_join(Gamend.Accounts.User.t(), map()) :: hook_result(map())
```

# `matchmaking_form_matches`
*optional* 

```elixir
@callback matchmaking_form_matches(map(), [Gamend.Matchmaking.Ticket.t()]) ::
  [[Gamend.Matchmaking.Ticket.t()]] | :default
```

# `after_ready_check_failed`
*optional* 

```elixir
@callback after_ready_check_failed(Gamend.ReadyChecks.Check.t(), String.t(), [map()]) ::
  any()
```

# `after_ready_check_passed`
*optional* 

```elixir
@callback after_ready_check_passed(Gamend.ReadyChecks.Check.t()) :: any()
```

# `before_ready_check_open`
*optional* 

```elixir
@callback before_ready_check_open(
  Gamend.Lobbies.Lobby.t() | Gamend.Parties.Party.t() | :matchmaking,
  [
    String.t()
  ]
) :: veto_result()
```

# `after_entitlement_changed`
*optional* 

```elixir
@callback after_entitlement_changed(Gamend.Payments.Entitlement.t()) :: any()
```

# `after_purchase_fulfilled`
*optional* 

```elixir
@callback after_purchase_fulfilled(Gamend.Payments.Purchase.t()) :: any()
```

# `after_purchase_revoked`
*optional* 

```elixir
@callback after_purchase_revoked(Gamend.Payments.Purchase.t()) :: any()
```

# `before_purchase`
*optional* 

```elixir
@callback before_purchase(Gamend.Accounts.User.t(), product :: struct()) ::
  hook_result(term())
```

Veto a purchase before the player is charged.

Runs when a checkout starts and again when a receipt is validated, so a game
can refuse to sell — an unlinked account whose entitlement would be stranded
on one device, a region it does not ship to, a player it has banned. Return
`{:error, reason}` to stop it; the money never moves.

# `after_inventory_changed`
*optional* 

```elixir
@callback after_inventory_changed(map()) :: any()
```

# `after_wallet_changed`
*optional* 

```elixir
@callback after_wallet_changed(map()) :: any()
```

# `after_push_sent`
*optional* 

```elixir
@callback after_push_sent(String.t(), map(), map()) :: any()
```

# `before_push_send`
*optional* 

```elixir
@callback before_push_send(String.t(), map()) :: hook_result(map())
```

# `before_kv_get`
*optional* 

```elixir
@callback before_kv_get(String.t(), kv_opts()) :: kv_access_result()
```

Called before a KV `get/2` is performed. Implementations should return
one of these client KV API access decisions:

- `:public` — any authenticated client can read.
- `:owner_only` — only the caller matching the requested `user_id` can read.
- `:lobby_members_only` — only callers in the requested `lobby_id` can read.
- `:owner_or_lobby_member` — caller may match either requested `user_id` or `lobby_id`.
- `:admin_only` — only admins can read through the client KV API.
- `:server_only` — no client KV reads.

Server-side `Gamend.KV.get/2` calls are unaffected.

Receives the `key` and an `opts` map/keyword (see `t:kv_opts/0`). Return
either the bare atom (e.g. `:public`) or `{:ok, :public}`; return `{:error, reason}`
to block the read.

# `hook_result`

```elixir
@type hook_result(attrs_or_user) :: {:ok, attrs_or_user} | {:error, term()}
```

# `kv_access`

```elixir
@type kv_access() ::
  :public
  | :owner_only
  | :lobby_members_only
  | :owner_or_lobby_member
  | :admin_only
  | :server_only
```

# `kv_access_result`

```elixir
@type kv_access_result() :: kv_access() | {:ok, kv_access()} | {:error, term()}
```

# `kv_opts`

```elixir
@type kv_opts() :: map() | keyword()
```

Options passed to hooks that accept an options map/keyword list.

Common keys include `:user_id`, `:lobby_id`, and other domain-specific options.
Hooks may accept either a map or keyword list for convenience.

# `veto_result`

```elixir
@type veto_result() :: :ok | hook_result(term())
```

A veto-only hook: `{:error, reason}` rejects, anything else allows. The
return never rewrites the args, so a bare `:ok` is the usual "allow".

# `call`

Call an arbitrary function exported by the configured hooks module.

This is a safe wrapper that checks function existence, enforces an allow-list
if configured and runs the call inside a short Task with a configurable
timeout to avoid long-running user code.

Returns {:ok, result} | {:error, reason}

# `caller`

```elixir
@spec caller() :: any() | nil
```

When a hooks function is executed via `call/3` or `internal_call/3`, an
optional `:caller` can be provided in the options. The caller will be
injected into the spawned task's process dictionary and is accessible via
`Gamend.Hooks.caller/0` (the raw value) or `caller_id/0` (the numeric id
when the value is a user struct or map containing `:id`).

# `caller_id`

```elixir
@spec caller_id() :: String.t() | nil
```

# `caller_user`

```elixir
@spec caller_user() :: Gamend.Accounts.User.t() | nil
```

Return the user struct for the current caller when available. This will
  attempt to resolve the caller via Gamend.Accounts.get_user!/1 when the
  caller is a user id or a map containing an `:id` key. Returns nil when
  no caller or user is found.

# `exported_functions`

Return a list of exported functions on the currently registered hooks module.

The result is a list of maps like: [%{name: "start_game", arities: [2,3]}, ...]
This is useful for tooling and admin UI to display what RPCs are available.

# `internal_call`

Call an internal lifecycle callback. When a callback is missing this
  returns a sensible default (eg. {:ok, attrs} for before callbacks) so
  domain code doesn't need to handle missing hooks specially in most cases.

# `internal_hooks`

```elixir
@spec internal_hooks() :: MapSet.t(atom())
```

Returns the set of internal lifecycle hook names that are not callable
  through the public RPC interface.

# `invoke`

Invoke a dynamic hook function by name.

This is used by `Gamend.Schedule` to call scheduled job callbacks.
Unlike `internal_call/3`, this is designed for user-defined functions
that are not part of the core lifecycle callbacks.

Returns `:ok` on success, `{:error, reason}` on failure or if the
function doesn't exist.

# `module`

Return the configured module that implements the hooks behaviour.

# `pipeline_hook?`

True when the hook transforms its input (a `before_*` pipeline hook) rather
than fanning out notifications. Exposed for the admin runtime page.

# `pipeline_hooks`

```elixir
@spec pipeline_hooks() :: [atom()]
```

Pipeline hook names registered on top of core's own.

# `register_pipeline_hook`

```elixir
@spec register_pipeline_hook(atom()) :: :ok
```

Register a `before_*` hook name owned by a host application or a plugin.

A pipeline hook transforms its input: each plugin receives the previous
plugin's output, returns `{:ok, value}` to allow a possibly-modified value or
`{:error, reason}` to block, and the chain halts at the first refusal.

Core's own names are a fixed list, so a host's `before_*` hook fell through to
the fan-out path instead, where every plugin is called with the *same*
arguments, only the first one's result is returned, and the others run
regardless of whether the first refused. With one plugin the difference is
invisible; with two, the second plugin's changes are dropped and its side
effects happen even after the first blocked the operation.

    Gamend.Hooks.register_pipeline_hook(:before_build)

# `unregister_pipeline_hook`

```elixir
@spec unregister_pipeline_hook(atom()) :: :ok
```

Undoes `register_pipeline_hook/1`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
