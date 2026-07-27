defmodule GameServer.Hooks do
  @moduledoc """
  Behaviour for GameServer hooks/callbacks.

  Implement this behaviour in your hooks module to receive lifecycle events
  from the GameServer and run custom game logic.

  ## Setup

  1. Create a module implementing this behaviour
  2. Configure it in your GameServer instance

  ## Example

      defmodule MyGame.Hooks do
        @behaviour GameServer.Hooks

        @impl true
        def after_user_register(user) do
          # Give new users starting coins
          GameServer.Accounts.update_user(user, %{
            metadata: Map.put(user.metadata || %{}, "coins", 100)
          })
        end

        @impl true
        def after_user_logged_in(user) do
          # Log login
          :ok
        end

        @impl true
        def after_user_updated(user) do
          # React to user profile changes (e.g., sync display name to external system)
          :ok
        end

        @impl true
        def before_user_register(_user, attrs) do
          # Override the generated username or veto the registration
          {:ok, attrs}
        end

        @impl true
        def before_user_update(_user, attrs) do
          # Validate or modify user update attributes before they are applied
          # Return {:ok, attrs} to allow, {:error, reason} to block
          {:ok, attrs}
        end

        # Lobby hooks
        @impl true
        def before_lobby_create(attrs) do
          # Validate or modify lobby creation attributes
          {:ok, attrs}
        end

        @impl true
        def after_lobby_create(_lobby), do: :ok

        @impl true
        def before_lobby_join(user, lobby, opts) do
          # Check if user can join (e.g., level requirements)
          {:ok, {user, lobby, opts}}
        end

        @impl true
        def before_group_create(user, attrs) do
          # Check if user can create a group (e.g., enough coins in metadata)
          coins = get_in(user.metadata, ["coins"]) || 0
          if coins >= 50 do
            {:ok, attrs}
          else
            {:error, :not_enough_coins}
          end
        end

        @impl true
        def before_group_join(user, group, opts) do
          # Check if user can join group (e.g., level requirements based on metadata)
          {:ok, {user, group, opts}}
        end

        @impl true
        def after_lobby_join(_user, _lobby), do: :ok

        @impl true
        def before_lobby_leave(user, lobby) do
          {:ok, {user, lobby}}
        end

        @impl true
        def after_lobby_leave(_user, _lobby), do: :ok

        @impl true
        def before_lobby_update(_lobby, attrs) do
          {:ok, attrs}
        end

        @impl true
        def after_lobby_updated(_lobby), do: :ok

        @impl true
        def before_lobby_delete(lobby) do
          {:ok, lobby}
        end

        @impl true
        def after_lobby_deleted(_lobby), do: :ok

        @impl true
        def before_lobby_state_change(_lobby, _from, _to), do: :ok

        @impl true
        def after_lobby_state_changed(_lobby, _from, _to), do: :ok

        @impl true
        def before_lobby_kick(host, target, lobby) do
          {:ok, {host, target, lobby}}
        end

        @impl true
        def after_lobby_kick(_host, _target, _lobby), do: :ok

        @impl true
        def after_lobby_host_change(_lobby, _new_host_id), do: :ok

        @impl true
        def before_ready_check_open(_subject, _user_ids), do: :ok

        @impl true
        def after_ready_check_passed(_check), do: :ok

        @impl true
        def after_ready_check_failed(_check, _reason, _not_ready), do: :ok

        # Custom RPC handlers - define your own functions!
        # These are called from game clients via the RPC channel.
        #
        # def give_coins(amount, opts) do
        #   caller = Keyword.get(opts, :caller)
        #   # Update user's coins...
        #   {:ok, %{new_balance: 150}}
        # end
      end

  ## Hook Types

  ### User Lifecycle Hooks

  - `after_user_register/1` - Called after a new user registers
  - `after_user_logged_in/1` - Called after a user logs in
  - `after_user_updated/1` - Called after a user is updated (fire-and-forget)
  - `after_user_online/1` - Called after a user comes online (fire-and-forget)
  - `after_user_offline/1` - Called after a user goes offline (fire-and-forget)

  ### Lobby Lifecycle Hooks

  Before hooks can block operations by returning `{:error, reason}`.
  After hooks are fire-and-forget.

  - `before_lobby_create/1` - Before lobby creation, receives attrs map
  - `after_lobby_create/1` - After lobby is created
  - `before_lobby_join/3` - Before user joins lobby
  - `after_lobby_join/2` - After user joins lobby
  - `before_group_create/2` - Before group creation, receives `(user, attrs)`. Return `{:ok, attrs}` to allow or `{:error, reason}` to block
  - `after_group_create/1` - After group is created (fire-and-forget)
  - `before_group_join/3` - Before user is accepted into a group (public join, invite accept, or request approval)
  - `before_group_update/2` - Before group update, receives `(group, attrs)`. Return `{:ok, attrs}` to allow or `{:error, reason}` to block
  - `after_group_updated/1` - After group is updated (fire-and-forget)
  - `after_group_join/2` - After a user joins a group (fire-and-forget), receives `(user_id, group)`
  - `after_group_leave/2` - After a user leaves a group (fire-and-forget), receives `(user_id, group_id)`
  - `after_group_deleted/1` - After a group is deleted (fire-and-forget), receives `(group)`
  - `after_group_kick/3` - After a member is kicked from a group (fire-and-forget), receives `(admin_id, target_id, group_id)`
  - `before_party_create/2` - Before party creation, receives `(user, attrs)`. Return `{:ok, attrs}` to allow or `{:error, reason}` to block
  - `after_party_create/1` - After party is created (fire-and-forget)
  - `before_party_update/2` - Before party update, receives `(party, attrs)`. Return `{:ok, attrs}` to allow or `{:error, reason}` to block
  - `after_party_updated/1` - After party is updated (fire-and-forget)
  - `after_party_join/2` - After a user joins a party via invite accept (fire-and-forget), receives `(user, party)`
  - `after_party_leave/2` - After a user leaves a party (fire-and-forget), receives `(user, party_id)`
  - `after_party_kick/3` - After a member is kicked from a party (fire-and-forget), receives `(target, leader, party)`
  - `after_party_disband/1` - After a party is disbanded (fire-and-forget), receives `(party)`
  - `before_quest_claim/3` - Before a player claims a completed quest, receives `(user_id, quest, progress)`. Veto-only: return `{:error, reason}` to reject, anything else allows. Skipped for auto-claim quests
  - `after_quest_completed/1` - After a quest completes (fire-and-forget), receives the progress row
  - `after_quest_claimed/1` - After a quest's rewards are claimed (fire-and-forget), receives the progress row
  - `before_chat_message/2` - Before a chat message is sent, receives `(user, attrs)`. Return `{:ok, attrs}` to allow (and optionally modify), or `{:error, reason}` to block
  - `after_chat_message/1` - After a chat message is persisted (fire-and-forget)
  - `before_lobby_leave/2` - Before user leaves lobby
  - `after_lobby_leave/2` - After user leaves lobby
  - `before_lobby_update/2` - Before lobby is updated
  - `after_lobby_updated/1` - After lobby is updated
  - `before_lobby_delete/1` - Before lobby is deleted
  - `after_lobby_deleted/1` - After lobby is deleted
  - `before_lobby_state_change/3` - Before a lobby's `state` changes, receives `(lobby, from, to)`. Veto-only: return `{:error, reason}` to reject, anything else allows. The vocabulary is yours — enforce it here (reject words you don't use)
  - `after_lobby_state_changed/3` - After a lobby's `state` changed (fire-and-forget), receives `(lobby, from, to)`
  - `before_lobby_kick/3` - Before user is kicked from lobby
  - `after_lobby_kick/3` - After user is kicked from lobby
  - `after_lobby_host_change/2` - After lobby host changes
  - `before_ready_check_open/2` - Before a ready check opens, receives `(lobby | :matchmaking, user_ids)`. Veto-only: return `{:error, reason}` to reject
  - `after_ready_check_passed/1` - Everyone answered ready (fire-and-forget), receives the check. Where you start the match: `Lobbies.transition_state(lobby, "starting")`
  - `after_ready_check_failed/3` - A check was declined, timed out or cancelled, receives `(check, reason, not_ready_participants)`. Core kicks nobody — decide here
  - `before_kv_get/2` - Called before a client KV `get` to return a KV access decision such as `:public`, `:owner_only`, or `:server_only`

    ## Custom RPC Functions

    Game clients can call RPCs exposed by your hooks module in two ways:

    1. **Exported functions**: any exported function in your hooks module (other
      than the callbacks above) can be called from game clients.

    2. **Dynamic functions (custom hooks)**: your `after_startup/0` callback may
      return a list of dynamic exports describing additional callable function
      names that do **not** need to exist as exported Elixir functions.
      These dynamic calls are dispatched to `on_custom_hook/2`.

      # Client calls: rpc("give_coins", {amount: 50})
      def give_coins(amount, opts) do
        caller = Keyword.get(opts, :caller)
        # Your game logic here
        {:ok, %{success: true}}
      end

  Return values:
  - `{:ok, data}` - Success, data is sent back to client
  - `{:error, reason}` - Error, reason is sent back to client
  - `:ok` - Success with no data
  """

  @typedoc "A user struct from GameServer.Accounts.User"
  @type user :: GameServer.Accounts.User.t()

  @typedoc "A lobby struct from GameServer.Lobbies.Lobby"
  @type lobby :: GameServer.Lobbies.Lobby.t()

  @typedoc "A group struct from GameServer.Groups.Group"
  @type group :: GameServer.Groups.Group.t()

  @typedoc "A party struct from GameServer.Parties.Party"
  @type party :: GameServer.Parties.Party.t()

  @typedoc "A chat message struct from GameServer.Chat.Message"
  @type message :: GameServer.Chat.Message.t()

  @typedoc "Result type for before hooks"
  @type hook_result(t) :: {:ok, t} | {:error, term()}

  @typedoc "Client KV API access decision returned by `before_kv_get/2`."
  @type kv_access ::
          :public
          | :owner_only
          | :lobby_members_only
          | :owner_or_lobby_member
          | :admin_only
          | :server_only

  @type kv_access_result :: kv_access() | {:ok, kv_access()} | {:error, term()}

  @typedoc """
  A dynamic RPC export returned by `after_startup/0`.

  The minimal shape is:

      %{hook: "custom_hello"}

  Optionally, provide `:meta` for tooling / UI hints:

      %{hook: "custom_hello", meta: %{description: "...", args: [...], example_args: [...]}}

  Note: the runtime also accepts string keys (e.g. `%{"hook" => ...}`), but
  this type focuses on the atom-keyed form.
  """
  @type rpc_export :: %{
          required(:hook) => String.t(),
          optional(:meta) => map()
        }

  @typedoc """
  Options passed to hooks that accept an options map/keyword list.

  Common keys include `:user_id`, `:lobby_id`, and other domain-specific options.
  Hooks may accept either a map or keyword list for convenience.
  """
  @type kv_opts :: map() | keyword()

  # Startup/shutdown callbacks
  @callback after_startup() :: :ok | [rpc_export()]
  @callback before_stop() :: any()

  @doc """
  Handle a dynamically-exported RPC function.

  This callback is invoked when a client calls a function name that was
  registered at runtime from `after_startup/0`.

  Receives the function name and the argument list.
  """
  @callback on_custom_hook(String.t(), list()) :: any()

  # User lifecycle callbacks

  @doc """
  Called before a new user row is inserted, on every registration path
  (email, device, and all OAuth providers).

  Receives the tentative user (not yet inserted, `id` is `nil`) and the
  string-keyed registration attrs, which already contain the generated
  `"username"`. Return `{:ok, attrs}` — possibly with a different username —
  or `{:error, reason}` to abort. Core re-validates after all hooks ran: an
  invalid or taken username is replaced with a generated one so login never
  breaks; use `c:before_user_update/2` for strict checks on player-initiated
  username changes (profanity, reserved names).
  """
  @callback before_user_register(user(), attrs :: map()) :: hook_result(map())

  @callback before_user_update(user(), attrs :: map()) :: hook_result(map())
  @callback after_user_register(user()) :: any()
  @callback after_user_logged_in(user()) :: any()
  @callback after_user_updated(user()) :: any()
  @callback after_user_online(user()) :: any()
  @callback after_user_offline(user()) :: any()
  @callback after_user_deleted(user()) :: any()

  # Economy lifecycle callbacks. The change map carries the user, the
  # currency/item, the new balance/quantity, and the signed delta.
  @callback after_wallet_changed(change :: map()) :: any()
  @callback after_inventory_changed(change :: map()) :: any()
  @optional_callbacks after_wallet_changed: 1, after_inventory_changed: 1

  # Payment lifecycle. A game turns a fulfilled purchase into currency or items
  # here; core has already recorded the purchase and any entitlement.
  @callback after_purchase_fulfilled(GameServer.Payments.Purchase.t()) :: any()
  @callback after_purchase_revoked(GameServer.Payments.Purchase.t()) :: any()
  @callback after_entitlement_changed(GameServer.Payments.Entitlement.t()) :: any()

  @optional_callbacks after_purchase_fulfilled: 1,
                      after_purchase_revoked: 1,
                      after_entitlement_changed: 1

  @callback after_score_submitted(GameServer.Leaderboards.Record.t()) :: any()

  @optional_callbacks after_score_submitted: 1

  # Lobby lifecycle callbacks
  @callback before_lobby_create(attrs :: map()) :: hook_result(map())
  @callback after_lobby_create(lobby()) :: any()

  @callback before_lobby_join(user(), lobby(), opts :: keyword()) ::
              hook_result({user(), lobby(), keyword()})
  @callback after_lobby_join(user(), lobby()) :: any()

  @callback before_group_create(user(), map()) :: hook_result(map())
  @callback after_group_create(group()) :: any()

  @callback before_group_join(user(), group(), opts :: map()) ::
              hook_result({user(), group(), map()})

  @callback before_group_update(group(), map()) :: hook_result(map())
  @callback after_group_updated(group()) :: any()

  # Group after-hooks (fire-and-forget)
  @callback after_group_join(integer(), group()) :: any()
  @callback after_group_leave(integer(), integer()) :: any()
  @callback after_group_deleted(group()) :: any()
  @callback after_group_kick(integer(), integer(), integer()) :: any()

  @callback before_group_delete(group()) :: hook_result(group())
  @callback before_group_kick(String.t(), String.t(), String.t()) ::
              hook_result({String.t(), String.t(), String.t()})

  # Party lifecycle callbacks
  @callback before_party_create(user(), map()) :: hook_result(map())
  @callback before_party_join(user(), party()) :: hook_result({user(), party()})
  @callback before_party_kick(user(), user(), party()) ::
              hook_result({user(), user(), party()})
  @callback after_party_create(party()) :: any()

  @callback before_party_update(party(), map()) :: hook_result(map())
  @callback after_party_updated(party()) :: any()

  @callback after_party_join(user(), party()) :: any()
  @callback after_party_leave(user(), integer()) :: any()
  @callback after_party_kick(user(), user(), party()) :: any()
  @callback after_party_disband(party()) :: any()

  # Quest lifecycle callbacks. `before_quest_claim` is veto-only: return
  # `{:error, reason}` to reject the claim, anything else allows. Auto-claim
  # quests skip it. Achievements are quests of `kind: "achievement"`.
  @callback before_quest_claim(
              String.t(),
              GameServer.Quests.Quest.t(),
              GameServer.Quests.QuestProgress.t()
            ) ::
              {:ok, term()} | {:error, term()} | any()
  @callback after_quest_completed(GameServer.Quests.QuestProgress.t()) :: any()
  @callback after_quest_claimed(GameServer.Quests.QuestProgress.t()) :: any()

  # Tournament lifecycle hooks (all optional; see the Tournaments guide).
  # Match payloads are `GameServer.Tournaments.Match` structs with
  # `tournament`, `a_entry` and `b_entry` preloaded. before_* hooks veto with
  # `{:error, reason}`; any other return allows. `tournament_match_ready` is
  # where the game starts the match (create a lobby, set up a challenge, ...)
  # and `tournament_match_expired` is where it adjudicates an unresolved
  # match at its deadline via `GameServer.Tournaments.resolve_match/2`.
  @doc """
  Called before a matchmaking ticket is created.

  Receives the caller and the string-keyed attrs (`"match_params"`,
  `"min_players"`, `"max_players"`). Return the attrs — possibly rewritten, e.g.
  stamping a skill band computed from stored data — or `{:error, reason}` to
  refuse the join. This is the server's authority over the queue: without it a
  client picks its own `match_params` and can self-assign any bracket.
  """
  @callback before_matchmaking_join(user(), attrs :: map()) :: hook_result(map())
  @callback after_matchmaking_join(user(), ticket :: struct()) :: any()
  @callback after_matchmaking_cancel(user_id :: String.t(), count :: non_neg_integer()) :: any()

  @doc """
  Replaces the built-in matcher for one bucket of tickets sharing identical
  `match_params`.

  Receives the params and that bucket's queued tickets, oldest first, and
  returns the groups to seat. Return `:default` to keep the built-in FIFO
  matcher. Called once per bucket per sweep, so an O(n^2) scan here is cheap —
  it runs in-process, unlike a per-pair callback.

  Core re-checks the block list on whatever you return, so a custom matcher
  can never seat players who blocked each other.
  """
  @callback matchmaking_form_matches(params :: map(), tickets :: [struct()]) ::
              [[struct()]] | :default
  @callback after_matchmaking_matched(tickets :: [struct()], lobby_id :: String.t()) :: any()

  @callback before_tournament_register(user(), tournament :: struct()) :: hook_result(term())
  @callback after_tournament_register(user(), tournament :: struct()) :: any()
  @callback before_tournament_leave(user(), tournament :: struct()) :: hook_result(term())
  @callback tournament_match_ready(match :: struct()) :: any()
  @callback tournament_match_expired(match :: struct()) :: any()
  @callback before_tournament_result(match :: struct(), winner :: term()) :: hook_result(term())
  @callback after_tournament_match_resolved(match :: struct()) :: any()
  @callback after_tournament_finished(tournament :: struct(), standings :: map()) :: any()
  @optional_callbacks before_matchmaking_join: 2,
                      after_matchmaking_join: 2,
                      after_matchmaking_cancel: 2,
                      matchmaking_form_matches: 2,
                      after_matchmaking_matched: 2,
                      before_tournament_register: 2,
                      after_tournament_register: 2,
                      before_tournament_leave: 2,
                      tournament_match_ready: 1,
                      tournament_match_expired: 1,
                      before_tournament_result: 2,
                      after_tournament_match_resolved: 1,
                      after_tournament_finished: 2

  @callback before_chat_message(user(), attrs :: map()) :: hook_result(map())
  @callback after_chat_message(message()) :: any()

  @callback before_push_send(user_id :: String.t(), message :: map()) :: hook_result(map())
  @callback after_push_sent(user_id :: String.t(), message :: map(), result :: map()) :: any()

  @callback before_lobby_leave(user(), lobby()) :: hook_result({user(), lobby()})
  @callback after_lobby_leave(user(), lobby()) :: any()

  @callback before_lobby_update(lobby(), attrs :: map()) :: hook_result(map())
  @callback after_lobby_updated(lobby()) :: any()

  @callback before_lobby_delete(lobby()) :: hook_result(lobby())
  @callback after_lobby_deleted(lobby()) :: any()

  # Lobby lifecycle state. Core only ever sets "created" and accepts any sane
  # word; the vocabulary and its ordering are the game's, enforced right here.
  # Veto-only: the return never rewrites the args.
  @callback before_lobby_state_change(lobby(), String.t(), String.t()) ::
              {:ok, term()} | {:error, term()} | any()
  @callback after_lobby_state_changed(lobby(), String.t(), String.t()) :: any()

  @callback before_lobby_kick(host :: user(), target :: user(), lobby()) ::
              hook_result({user(), user(), lobby()})
  @callback after_lobby_kick(host :: user(), target :: user(), lobby()) :: any()

  # Ready checks. `after_ready_check_passed` is the "everyone answered yes"
  # callback; `after_ready_check_failed` gets the participants who did not —
  # core kicks nobody, so what that costs them is the game's call.
  @callback before_ready_check_open(lobby() | :matchmaking, [String.t()]) ::
              {:ok, term()} | {:error, term()} | any()
  @callback after_ready_check_passed(map()) :: any()
  @callback after_ready_check_failed(map(), String.t(), [map()]) :: any()

  @optional_callbacks before_group_create: 2,
                      after_group_create: 1,
                      before_group_join: 3,
                      before_group_update: 2,
                      after_group_updated: 1,
                      before_user_update: 2,
                      after_group_join: 2,
                      after_group_leave: 2,
                      after_group_deleted: 1,
                      after_group_kick: 3,
                      before_party_create: 2,
                      after_party_create: 1,
                      before_party_update: 2,
                      after_party_updated: 1,
                      after_party_join: 2,
                      after_party_leave: 2,
                      after_party_kick: 3,
                      after_party_disband: 1,
                      before_quest_claim: 3,
                      after_quest_completed: 1,
                      after_quest_claimed: 1,
                      before_chat_message: 2,
                      after_chat_message: 1,
                      before_push_send: 2,
                      after_push_sent: 3,
                      before_ready_check_open: 2,
                      after_ready_check_passed: 1,
                      after_ready_check_failed: 3

  @doc """
  Called before a KV `get/2` is performed. Implementations should return
  one of these client KV API access decisions:

  - `:public` — any authenticated client can read.
  - `:owner_only` — only the caller matching the requested `user_id` can read.
  - `:lobby_members_only` — only callers in the requested `lobby_id` can read.
  - `:owner_or_lobby_member` — caller may match either requested `user_id` or `lobby_id`.
  - `:admin_only` — only admins can read through the client KV API.
  - `:server_only` — no client KV reads.

  Server-side `GameServer.KV.get/2` calls are unaffected.

  Receives the `key` and an `opts` map/keyword (see `t:kv_opts/0`). Return
  either the bare atom (e.g. `:public`) or `{:ok, :public}`; return `{:error, reason}`
  to block the read.
  """
  @callback before_kv_get(String.t(), kv_opts()) :: kv_access_result()

  @callback after_lobby_host_change(lobby(), new_host_id :: integer()) :: any()

  @doc """
  Use this macro to get default implementations for all callbacks.

  This allows you to only implement the callbacks you need.

  ## Example

      defmodule MyGame.Hooks do
        use GameServer.Hooks

        @impl true
        def after_user_register(user) do
          # Only implement what you need
          :ok
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour GameServer.Hooks

      @impl true
      def after_startup, do: :ok

      @impl true
      def before_stop, do: :ok

      @impl true
      def on_custom_hook(_hook, _args), do: {:error, :not_implemented}

      @impl true
      def after_user_register(_user), do: :ok

      @impl true
      def after_user_logged_in(_user), do: :ok

      @impl true
      def after_user_updated(_user), do: :ok

      @impl true
      def after_user_online(_user), do: :ok

      @impl true
      def after_user_offline(_user), do: :ok

      @impl true
      def after_user_deleted(_user), do: :ok

      @impl true
      def after_wallet_changed(_change), do: :ok

      @impl true
      def after_inventory_changed(_change), do: :ok

      @impl true
      def before_user_register(_user, attrs), do: {:ok, attrs}

      @impl true
      def before_user_update(_user, attrs), do: {:ok, attrs}

      @impl true
      def before_lobby_create(attrs), do: {:ok, attrs}

      @impl true
      def after_lobby_create(_lobby), do: :ok

      @impl true
      def before_lobby_join(user, lobby, opts), do: {:ok, {user, lobby, opts}}

      @impl true
      def before_group_create(_user, attrs), do: {:ok, attrs}

      @impl true
      def after_group_create(_group), do: :ok

      @impl true
      def before_group_update(_group, attrs), do: {:ok, attrs}

      @impl true
      def after_group_updated(_group), do: :ok

      @impl true
      def after_group_join(_user_id, _group), do: :ok

      @impl true
      def after_group_leave(_user_id, _group_id), do: :ok

      @impl true
      def after_group_deleted(_group), do: :ok

      @impl true
      def after_group_kick(_admin_id, _target_id, _group_id), do: :ok

      @impl true
      def before_group_delete(group), do: {:ok, group}

      @impl true
      def before_group_kick(admin_id, target_id, group_id),
        do: {:ok, {admin_id, target_id, group_id}}

      @impl true
      def before_party_join(user, party), do: {:ok, {user, party}}

      @impl true
      def before_party_kick(admin, target, party), do: {:ok, {admin, target, party}}

      @impl true
      def after_purchase_fulfilled(_purchase), do: :ok

      @impl true
      def after_purchase_revoked(_purchase), do: :ok

      @impl true
      def after_entitlement_changed(_entitlement), do: :ok

      @impl true
      def after_score_submitted(_record), do: :ok

      @impl true
      def before_party_create(_user, attrs), do: {:ok, attrs}

      @impl true
      def after_party_create(_party), do: :ok

      @impl true
      def before_party_update(_party, attrs), do: {:ok, attrs}

      @impl true
      def after_party_updated(_party), do: :ok

      @impl true
      def after_party_join(_user, _party), do: :ok

      @impl true
      def after_party_leave(_user, _party_id), do: :ok

      @impl true
      def after_party_kick(_target, _leader, _party), do: :ok

      @impl true
      def after_party_disband(_party), do: :ok

      @impl true
      def before_quest_claim(_user_id, _quest, _progress), do: :ok

      @impl true
      def after_quest_completed(_progress), do: :ok

      @impl true
      def after_quest_claimed(_progress), do: :ok

      @impl true
      def after_lobby_join(_user, _lobby), do: :ok

      @impl true
      def before_chat_message(_user, attrs), do: {:ok, attrs}

      @impl true
      def after_chat_message(_message), do: :ok

      @impl true
      def before_push_send(_user_id, message), do: {:ok, message}

      @impl true
      def after_push_sent(_user_id, _message, _result), do: :ok

      @impl true
      def before_lobby_leave(user, lobby), do: {:ok, {user, lobby}}

      @impl true
      def after_lobby_leave(_user, _lobby), do: :ok

      @impl true
      def before_lobby_update(_lobby, attrs), do: {:ok, attrs}

      @impl true
      def after_lobby_updated(_lobby), do: :ok

      @impl true
      def before_lobby_delete(lobby), do: {:ok, lobby}

      @impl true
      def after_lobby_deleted(_lobby), do: :ok

      @impl true
      def before_lobby_state_change(_lobby, _from, _to), do: :ok

      @impl true
      def after_lobby_state_changed(_lobby, _from, _to), do: :ok

      @impl true
      def before_lobby_kick(host, target, lobby), do: {:ok, {host, target, lobby}}

      @impl true
      def after_lobby_kick(_host, _target, _lobby), do: :ok

      @impl true
      def after_lobby_host_change(_lobby, _new_host_id), do: :ok

      @impl true
      def before_ready_check_open(_subject, _user_ids), do: :ok

      @impl true
      def after_ready_check_passed(_check), do: :ok

      @impl true
      def after_ready_check_failed(_check, _reason, _not_ready), do: :ok

      @impl true
      def before_kv_get(_key, _opts), do: :public

      @impl true
      def before_matchmaking_join(_user, attrs), do: {:ok, attrs}

      @impl true
      def after_matchmaking_join(_user, _ticket), do: :ok

      @impl true
      def after_matchmaking_cancel(_user_id, _count), do: :ok

      @impl true
      def matchmaking_form_matches(_params, _tickets), do: :default

      @impl true
      def after_matchmaking_matched(_tickets, _lobby_id), do: :ok

      @impl true
      def before_tournament_register(_user, tournament), do: {:ok, tournament}

      @impl true
      def after_tournament_register(_user, _tournament), do: :ok

      @impl true
      def before_tournament_leave(_user, tournament), do: {:ok, tournament}

      @impl true
      def tournament_match_ready(_match), do: :ok

      @impl true
      def tournament_match_expired(_match), do: :ok

      @impl true
      def before_tournament_result(_match, winner), do: {:ok, winner}

      @impl true
      def after_tournament_match_resolved(_match), do: :ok

      @impl true
      def after_tournament_finished(_tournament, _standings), do: :ok

      defoverridable after_startup: 0,
                     before_stop: 0,
                     before_group_delete: 1,
                     before_group_kick: 3,
                     before_party_join: 2,
                     before_party_kick: 3,
                     after_purchase_fulfilled: 1,
                     after_purchase_revoked: 1,
                     after_entitlement_changed: 1,
                     after_score_submitted: 1,
                     before_user_register: 2,
                     after_user_register: 1,
                     after_user_logged_in: 1,
                     after_user_updated: 1,
                     after_user_online: 1,
                     after_user_offline: 1,
                     after_user_deleted: 1,
                     after_wallet_changed: 1,
                     after_inventory_changed: 1,
                     before_user_update: 2,
                     on_custom_hook: 2,
                     before_lobby_create: 1,
                     after_lobby_create: 1,
                     before_group_create: 2,
                     after_group_create: 1,
                     before_group_update: 2,
                     after_group_updated: 1,
                     after_group_join: 2,
                     after_group_leave: 2,
                     after_group_deleted: 1,
                     after_group_kick: 3,
                     before_party_create: 2,
                     after_party_create: 1,
                     before_party_update: 2,
                     after_party_updated: 1,
                     after_party_join: 2,
                     after_party_leave: 2,
                     after_party_kick: 3,
                     after_party_disband: 1,
                     before_quest_claim: 3,
                     after_quest_completed: 1,
                     after_quest_claimed: 1,
                     before_lobby_join: 3,
                     after_lobby_join: 2,
                     before_chat_message: 2,
                     after_chat_message: 1,
                     before_push_send: 2,
                     after_push_sent: 3,
                     before_lobby_leave: 2,
                     after_lobby_leave: 2,
                     before_lobby_update: 2,
                     after_lobby_updated: 1,
                     before_lobby_delete: 1,
                     after_lobby_deleted: 1,
                     before_lobby_state_change: 3,
                     after_lobby_state_changed: 3,
                     before_lobby_kick: 3,
                     after_lobby_kick: 3,
                     after_lobby_host_change: 2,
                     before_ready_check_open: 2,
                     after_ready_check_passed: 1,
                     after_ready_check_failed: 3,
                     before_kv_get: 2,
                     before_matchmaking_join: 2,
                     after_matchmaking_join: 2,
                     after_matchmaking_cancel: 2,
                     matchmaking_form_matches: 2,
                     after_matchmaking_matched: 2,
                     before_tournament_register: 2,
                     after_tournament_register: 2,
                     before_tournament_leave: 2,
                     tournament_match_ready: 1,
                     tournament_match_expired: 1,
                     before_tournament_result: 2,
                     after_tournament_match_resolved: 1,
                     after_tournament_finished: 2
    end
  end

  @doc """
  Returns the raw caller value for the current hook invocation.

  When GameServer executes a hook function, it may inject a `:caller` into the
  hook task's process dictionary. This helper fetches that raw value.
  """
  @spec caller() :: any() | nil
  def caller do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %GameServer.Accounts.User{
          id: 0,
          email: "",
          display_name: nil,
          profile_url: nil,
          metadata: %{},
          is_admin: false,
          is_online: false,
          last_seen_at: nil,
          lobby_id: nil,
          party_id: nil,
          inserted_at: ~U[1970-01-01 00:00:00Z],
          updated_at: ~U[1970-01-01 00:00:00Z]
        }

      _ ->
        raise "#{__MODULE__}.caller/0 is a stub - only available at runtime on GameServer"
    end
  end

  @doc """
  Returns the caller's numeric id when available.

  If the caller is a `GameServer.Accounts.User` struct, returns its `id`.
  If the caller is a map, returns `:id` or `"id"`.
  If the caller is already an integer, returns it.
  Otherwise returns `nil`.
  """
  @spec caller_id() :: integer() | nil
  def caller_id do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder -> 0
      _ -> raise "#{__MODULE__}.caller_id/0 is a stub - only available at runtime on GameServer"
    end
  end

  @doc """
  Returns the user struct for the current caller when available.

  This is a convenience wrapper over `caller/0` that returns a user struct when
  the caller is already a `%GameServer.Accounts.User{}`.

  In the full GameServer application this may also resolve ids/maps via the DB.
  In the SDK it only returns the struct when it is already present.
  """
  @spec caller_user() :: GameServer.Accounts.User.t() | nil
  def caller_user do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %GameServer.Accounts.User{
          id: 0,
          email: "",
          display_name: nil,
          profile_url: nil,
          metadata: %{},
          is_admin: false,
          is_online: false,
          last_seen_at: nil,
          lobby_id: nil,
          party_id: nil,
          inserted_at: ~U[1970-01-01 00:00:00Z],
          updated_at: ~U[1970-01-01 00:00:00Z]
        }

      _ ->
        raise "#{__MODULE__}.caller_user/0 is a stub - only available at runtime on GameServer"
    end
  end
end
