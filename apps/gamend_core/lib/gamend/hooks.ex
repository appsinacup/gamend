defmodule Gamend.Hooks do
  @moduledoc """
  Behaviour for application-level hooks / callbacks.

  Implement this behaviour to receive lifecycle events from core flows
  (registration, login, provider linking, deletion) and run custom logic.

  A module implementing this behaviour can be configured with

      config :gamend_core, :hooks_module, MyApp.HooksImpl

  The default implementation is a no-op.
  """

  alias Gamend.Accounts.User
  alias Gamend.Chat.Message
  alias Gamend.Chat.Mute
  alias Gamend.Chat.Report
  alias Gamend.Groups.Group
  alias Gamend.Hooks.Default, as: Default
  alias Gamend.Hooks.PluginManager
  alias Gamend.Lobbies.Lobby
  alias Gamend.Parties.Party
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Purchase
  require Logger

  @type hook_result(attrs_or_user) :: {:ok, attrs_or_user} | {:error, term()}

  @typedoc """
  A veto-only hook: `{:error, reason}` rejects, anything else allows. The
  return never rewrites the args, so a bare `:ok` is the usual "allow".
  """
  @type veto_result :: :ok | hook_result(term())

  @type kv_access ::
          :public
          | :owner_only
          | :lobby_members_only
          | :owner_or_lobby_member
          | :admin_only
          | :server_only

  @type kv_access_result :: kv_access() | {:ok, kv_access()} | {:error, term()}

  @kv_access_levels [
    :public,
    :owner_only,
    :lobby_members_only,
    :owner_or_lobby_member,
    :admin_only,
    :server_only
  ]

  @typedoc """
  Options passed to hooks that accept an options map/keyword list.

  Common keys include `:user_id`, `:lobby_id`, and other domain-specific options.
  Hooks may accept either a map or keyword list for convenience.
  """
  @type kv_opts :: map() | keyword()

  @callback after_startup() :: any()

  @callback before_stop() :: any()

  @doc """
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
  """
  @callback before_user_register(User.t(), Gamend.Types.user_registration_hook_attrs()) ::
              hook_result(Gamend.Types.user_registration_hook_attrs())

  @callback after_user_register(User.t()) :: any()

  @callback after_user_logged_in(User.t()) :: any()

  @callback before_user_update(User.t(), map()) :: hook_result(map())
  @callback after_user_updated(User.t()) :: any()

  @doc """
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
  """
  @callback validate_username(String.t()) :: :ok | {:error, String.t() | atom()} | :default

  @callback after_user_online(User.t()) :: any()
  @callback after_user_offline(User.t()) :: any()
  @callback after_user_deleted(User.t()) :: any()

  @doc """
  Handle a dynamically-exported RPC function.

  This callback is used for function names that were registered at runtime (eg.
  via a plugin's `after_startup/0` return value) and therefore may not exist as
  exported Elixir functions on the hooks module.

  Receives the function name and the argument list.
  """
  @callback on_custom_hook(String.t(), list()) :: any()

  # Lobby lifecycle hooks
  @callback before_lobby_create(map()) :: hook_result(map())
  @callback after_lobby_create(Lobby.t()) :: any()

  @callback before_lobby_join(User.t(), Lobby.t(), keyword()) ::
              hook_result({User.t(), Lobby.t(), keyword()})
  @callback after_lobby_join(User.t(), Lobby.t()) :: any()

  @callback before_group_create(User.t(), map()) :: hook_result(map())
  @callback after_group_create(Group.t()) :: any()

  @callback before_group_join(User.t(), Group.t(), map()) ::
              hook_result({User.t(), Group.t(), map()})

  @callback before_group_update(Group.t(), map()) :: hook_result(map())
  @callback after_group_updated(Group.t()) :: any()

  @callback after_group_join(String.t(), Group.t()) :: any()
  @callback after_group_leave(String.t(), String.t()) :: any()
  @callback after_group_deleted(Group.t()) :: any()
  @callback after_group_kick(String.t(), String.t(), String.t()) :: any()

  @callback before_group_delete(Group.t()) :: hook_result(Group.t())
  @callback before_group_kick(String.t(), String.t(), String.t()) ::
              hook_result({String.t(), String.t(), String.t()})

  # Party lifecycle hooks
  @callback before_party_create(User.t(), map()) :: hook_result(map())
  @callback after_party_create(Party.t()) :: any()

  @callback before_party_update(Party.t(), map()) :: hook_result(map())
  @callback after_party_updated(Party.t()) :: any()

  @callback after_party_join(User.t(), Party.t()) :: any()
  @callback after_party_leave(User.t(), String.t()) :: any()
  @callback after_party_kick(User.t(), User.t(), Party.t()) :: any()
  @callback after_party_disband(Party.t()) :: any()

  @callback before_party_join(User.t(), Party.t()) :: hook_result({User.t(), Party.t()})
  @callback before_party_kick(User.t(), User.t(), Party.t()) ::
              hook_result({User.t(), User.t(), Party.t()})

  # Quest lifecycle hooks. `before_quest_claim` is veto-only: return
  # `{:error, reason}` to reject the claim, anything else allows — the return
  # never rewrites the args. Auto-claim quests skip it (there is no player
  # request to veto). Achievements are quests of `kind: "achievement"`;
  # branch on `progress.quest_key` / the quest's kind in these hooks.
  @callback before_quest_claim(
              String.t(),
              Gamend.Quests.Quest.t(),
              Gamend.Quests.QuestProgress.t()
            ) :: veto_result()
  @callback after_quest_completed(Gamend.Quests.QuestProgress.t()) :: any()
  @callback after_quest_claimed(Gamend.Quests.QuestProgress.t()) :: any()
  @optional_callbacks before_quest_claim: 3,
                      after_quest_completed: 1,
                      after_quest_claimed: 1

  # Leaderboard lifecycle hooks
  @callback after_score_submitted(Gamend.Leaderboards.Record.t()) :: any()

  # Tournament lifecycle hooks (see TOURNAMENT_DESIGN.md). Match payloads are
  # `Gamend.Tournaments.Match` structs with `tournament`, `a_entry` and
  # `b_entry` preloaded. before_* hooks veto with `{:error, reason}`; any
  # other return allows. `tournament_match_ready` is where the game starts
  # the match (create a lobby, set up a challenge, ...) and
  # `tournament_match_expired` is where it adjudicates an unresolved match at
  # its deadline_at via `Gamend.Tournaments.resolve_match/2`.
  @callback before_tournament_register(User.t(), Gamend.Tournaments.Tournament.t()) ::
              hook_result(term())
  @callback after_tournament_register(User.t(), Gamend.Tournaments.Tournament.t()) :: any()
  @callback before_tournament_leave(User.t(), Gamend.Tournaments.Tournament.t()) ::
              hook_result(term())
  @callback tournament_match_ready(Gamend.Tournaments.Match.t()) :: any()
  @callback tournament_match_expired(Gamend.Tournaments.Match.t()) :: any()
  @callback before_tournament_result(Gamend.Tournaments.Match.t(), term()) ::
              hook_result(term())
  @callback after_tournament_match_resolved(Gamend.Tournaments.Match.t()) :: any()
  @callback after_tournament_finished(Gamend.Tournaments.Tournament.t(), map()) :: any()
  # ── Matchmaking ──────────────────────────────────────────────────────────
  #
  # `before_matchmaking_join` is the server's authority over the queue: the
  # client proposes `match_params`, and this hook may rewrite them (stamping a
  # skill band from stored MMR, forcing a region) or veto the join entirely.
  # Returning the attrs map replaces it; `{:error, reason}` rejects the join.
  #
  # `matchmaking_form_matches` replaces the built-in matcher for one bucket of
  # tickets that share identical params. It receives the params and that
  # bucket's queued tickets (oldest first) and returns a list of ticket groups
  # to seat. Returning `:default` (or not exporting it) keeps the built-in
  # FIFO matcher. Core still enforces the block-list on whatever it returns,
  # so a custom matcher cannot pair players who blocked each other.
  @callback before_matchmaking_join(User.t(), map()) :: hook_result(map())
  @callback after_matchmaking_join(User.t(), Gamend.Matchmaking.Ticket.t()) :: any()
  @callback after_matchmaking_cancel(Ecto.UUID.t(), non_neg_integer()) :: any()
  @callback matchmaking_form_matches(map(), [Gamend.Matchmaking.Ticket.t()]) ::
              [[Gamend.Matchmaking.Ticket.t()]] | :default
  @callback after_matchmaking_matched([Gamend.Matchmaking.Ticket.t()], Ecto.UUID.t()) :: any()

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

  # Payment lifecycle hooks
  @doc """
  Veto a purchase before the player is charged.

  Runs when a checkout starts and again when a receipt is validated, so a game
  can refuse to sell — an unlinked account whose entitlement would be stranded
  on one device, a region it does not ship to, a player it has banned. Return
  `{:error, reason}` to stop it; the money never moves.
  """
  @callback before_purchase(User.t(), product :: struct()) :: hook_result(term())
  @callback after_purchase_fulfilled(Purchase.t()) :: any()
  @callback after_purchase_revoked(Purchase.t()) :: any()
  @callback after_entitlement_changed(Entitlement.t()) :: any()
  @optional_callbacks before_purchase: 2,
                      after_purchase_fulfilled: 1,
                      after_purchase_revoked: 1,
                      after_entitlement_changed: 1

  # Economy lifecycle hooks. The change map carries the user, the currency/item,
  # the new balance/quantity, and the signed delta (+grant / -spend).
  @callback after_wallet_changed(map()) :: any()
  @callback after_inventory_changed(map()) :: any()
  @optional_callbacks after_wallet_changed: 1,
                      after_inventory_changed: 1

  @callback before_chat_message(User.t(), map()) :: hook_result(map())
  @callback after_chat_message(Message.t()) :: any()

  # Chat moderation observations. Both are fire-and-forget: core has already
  # filed the report / applied the mute by the time they run, so a plugin can
  # tally strikes, notify moderators or auto-escalate, but cannot veto.
  @callback after_chat_message_reported(Report.t()) :: any()
  @callback after_user_muted(Mute.t()) :: any()

  # Push delivery hooks. `before_push_send/2` runs once per recipient before
  # any delivery job is enqueued: return `{:ok, message}` (possibly rewritten)
  # or `{:error, reason}` to drop the push for that user (per-user opt-out,
  # quiet hours, moderation). `after_push_sent/3` observes each token's final
  # outcome (`"delivered"` / `"invalid"` / `"failed"`). Both receive the
  # message as a plain string-keyed map.
  @callback before_push_send(String.t(), map()) :: hook_result(map())
  @callback after_push_sent(String.t(), map(), map()) :: any()
  @optional_callbacks before_push_send: 2,
                      after_push_sent: 3

  # Fired synchronously just before a member leaves and the lobby-scoped KV is
  # wiped, so a plugin can persist state that dies with the membership (e.g.
  # banking cargo collected in a level the player abandons). Non-gating: the
  # return value is ignored — it cannot block the leave. Optional so existing
  # plugins need not implement it.
  @callback before_lobby_leave(User.t(), Lobby.t()) :: any()
  @optional_callbacks before_lobby_leave: 2

  @callback after_lobby_leave(User.t(), Lobby.t()) :: any()

  @callback before_lobby_update(Lobby.t(), map()) :: hook_result(map())
  @callback after_lobby_updated(Lobby.t()) :: any()

  @callback before_lobby_delete(Lobby.t()) :: hook_result(Lobby.t())
  @callback after_lobby_deleted(Lobby.t()) :: any()

  # Lobby lifecycle state (see Gamend.Lobbies.States). The vocabulary is
  # the game's — core only sets "created" — so `before_lobby_state_change` is
  # where a game enforces its own ordering or entry conditions. Veto-only: the
  # return never rewrites the args.
  @callback before_lobby_state_change(Lobby.t(), String.t(), String.t()) :: veto_result()
  @callback after_lobby_state_changed(Lobby.t(), String.t(), String.t()) :: any()
  @optional_callbacks before_lobby_state_change: 3, after_lobby_state_changed: 3

  @callback before_lobby_kick(User.t(), User.t(), Lobby.t()) ::
              hook_result({User.t(), User.t(), Lobby.t()})
  @callback after_lobby_kick(User.t(), User.t(), Lobby.t()) :: any()

  # Ready checks (see Gamend.ReadyChecks). `after_ready_check_passed` is the
  # "everyone answered yes" callback — where a game starts its match.
  # `after_ready_check_failed` receives the participants who did not answer
  # ready; core kicks nobody, so acting on them is the game's call.
  @callback before_ready_check_open(
              Gamend.Lobbies.Lobby.t() | Gamend.Parties.Party.t() | :matchmaking,
              [String.t()]
            ) ::
              veto_result()
  @callback after_ready_check_passed(Gamend.ReadyChecks.Check.t()) :: any()
  @callback after_ready_check_failed(Gamend.ReadyChecks.Check.t(), String.t(), [map()]) ::
              any()
  @optional_callbacks before_ready_check_open: 2,
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

  Server-side `Gamend.KV.get/2` calls are unaffected.

  Receives the `key` and an `opts` map/keyword (see `t:kv_opts/0`). Return
  either the bare atom (e.g. `:public`) or `{:ok, :public}`; return `{:error, reason}`
  to block the read.
  """
  @callback before_kv_get(String.t(), kv_opts()) :: kv_access_result()

  @callback after_lobby_host_change(Lobby.t(), String.t()) :: any()

  @doc "Return the configured module that implements the hooks behaviour."
  def module do
    # Primary config lives under :gamend_core.
    # We also support :gamend as a backward-compatible fallback because
    # older docs and apps may have set it there.
    case Application.get_env(:gamend_core, :hooks_module) ||
           Application.get_env(:gamend, :hooks_module) do
      nil -> Default
      mod -> mod
    end
  end

  @doc """
  Call an arbitrary function exported by the configured hooks module.

  This is a safe wrapper that checks function existence, enforces an allow-list
  if configured and runs the call inside a short Task with a configurable
  timeout to avoid long-running user code.

  Returns {:ok, result} | {:error, reason}
  """
  def call(name, args \\ [], opts \\ [])
      when is_list(args) and (is_atom(name) or is_binary(name)) do
    name =
      if is_binary(name) do
        try do
          String.to_existing_atom(name)
        rescue
          ArgumentError -> nil
        end
      else
        name
      end

    if is_nil(name) do
      {:error, :not_implemented}
    else
      do_call(name, args, opts)
    end
  end

  defp do_call(name, args, opts) do
    mod = module()
    opts = resolve_caller(opts)
    arity = length(args)

    # Disallow calling internal lifecycle callbacks or scheduled job callbacks
    # via the public `call/3` API.
    # Domain code should use `internal_call/3` for lifecycle callbacks.
    scheduled = Gamend.Schedule.registered_callbacks()

    cond do
      name in internal_hooks() ->
        {:error, :disallowed}

      MapSet.member?(scheduled, name) ->
        {:error, :disallowed}

      # private functions (defp) are not exported and will fall through to
      # :not_implemented.

      not exports_function?(mod, name, arity) ->
        {:error, :not_implemented}

      true ->
        timeout =
          Keyword.get(opts, :timeout_ms, default_hook_timeout())

        task =
          Task.async(fn ->
            # Make caller context available inside the task via process dictionary.
            if caller = Keyword.get(opts, :caller) do
              Process.put(:gamend_hook_caller, caller)
            end

            try do
              apply(mod, name, args)
            rescue
              e in FunctionClauseError -> {:error, {:function_clause, Exception.message(e)}}
              e -> {:error, {:exception, Exception.message(e)}}
            catch
              kind, reason -> {:error, {kind, reason}}
            end
          end)

        result =
          case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
            {:ok, {:ok, res}} -> {:ok, res}
            {:ok, {:error, err}} -> {:error, err}
            {:ok, res} -> {:ok, res}
            nil -> {:error, :timeout}
            {:exit, reason} -> {:error, {:exit, reason}}
          end

        # Snapshot the caller's lobby now that the mutation finished, errors
        # included — a failed hook is the case most worth having a record of.
        # No-op unless lobby snapshots are enabled.
        _ = Gamend.LobbySnapshots.capture_hook(name, Keyword.get(opts, :caller), result)

        result
    end
  end

  @doc "Call an internal lifecycle callback. When a callback is missing this
  returns a sensible default (eg. {:ok, attrs} for before callbacks) so
  domain code doesn't need to handle missing hooks specially in most cases."
  def internal_call(name, args \\ [], opts \\ [])
      when is_list(args) and (is_atom(name) or is_binary(name)) do
    name = if is_binary(name), do: String.to_existing_atom(name), else: name
    # resolve caller before spawning a task in case the caller was provided as
    # a simple id (avoids sandbox issues for spawned tasks in tests)
    opts = resolve_caller(opts)

    mods = lifecycle_modules()

    timeout =
      Keyword.get(opts, :timeout_ms, default_hook_timeout())

    arity = length(args)

    if lifecycle_pipeline_hook?(name, arity) do
      run_before_pipeline(mods, name, args, opts, timeout)
    else
      run_fanout(mods, name, args, opts, timeout)
    end
  end

  @doc """
  Invoke a dynamic hook function by name.

  This is used by `Gamend.Schedule` to call scheduled job callbacks.
  Unlike `internal_call/3`, this is designed for user-defined functions
  that are not part of the core lifecycle callbacks.

  Returns `:ok` on success, `{:error, reason}` on failure or if the
  function doesn't exist.
  """
  def invoke(name, args \\ []) when is_atom(name) and is_list(args) do
    mod = module()
    arity = length(args)

    if exports_function?(mod, name, arity) do
      try do
        case apply(mod, name, args) do
          :ok -> :ok
          {:ok, _} = ok -> ok
          {:error, _} = err -> err
          other -> {:ok, other}
        end
      rescue
        e -> {:error, {:exception, Exception.message(e)}}
      catch
        kind, reason -> {:error, {kind, reason}}
      end
    else
      {:error, {:not_found, {mod, name, arity}}}
    end
  end

  # Every hook is optional. A plugin implements the handful it cares about, and
  # declaring `@behaviour Gamend.Hooks` must never oblige it to stub the
  # other seventy — nor start warning when core grows a new one. `use
  # Gamend.Hooks` still injects no-op defaults for anyone who wants them.
  @optional_callbacks after_chat_message: 1,
                      after_chat_message_reported: 1,
                      after_group_create: 1,
                      after_group_deleted: 1,
                      after_group_join: 2,
                      after_group_kick: 3,
                      after_group_leave: 2,
                      after_group_updated: 1,
                      after_lobby_create: 1,
                      after_lobby_deleted: 1,
                      after_lobby_host_change: 2,
                      after_lobby_join: 2,
                      after_lobby_kick: 3,
                      after_lobby_leave: 2,
                      after_lobby_updated: 1,
                      after_party_create: 1,
                      after_party_disband: 1,
                      after_party_join: 2,
                      after_party_kick: 3,
                      after_party_leave: 2,
                      after_party_updated: 1,
                      after_score_submitted: 1,
                      after_startup: 0,
                      after_user_deleted: 1,
                      after_user_logged_in: 1,
                      after_user_muted: 1,
                      after_user_offline: 1,
                      after_user_online: 1,
                      after_user_register: 1,
                      after_user_updated: 1,
                      before_chat_message: 2,
                      before_group_create: 2,
                      before_group_delete: 1,
                      before_group_join: 3,
                      before_group_kick: 3,
                      before_group_update: 2,
                      before_kv_get: 2,
                      before_lobby_create: 1,
                      before_lobby_delete: 1,
                      before_lobby_join: 3,
                      before_lobby_kick: 3,
                      before_lobby_update: 2,
                      before_party_create: 2,
                      before_party_join: 2,
                      before_party_kick: 3,
                      before_party_update: 2,
                      before_stop: 0,
                      before_user_register: 2,
                      before_user_update: 2,
                      validate_username: 1,
                      on_custom_hook: 2

  @doc "Returns the set of internal lifecycle hook names that are not callable\n  through the public RPC interface."
  @spec internal_hooks() :: MapSet.t(atom())
  def internal_hooks do
    MapSet.new([
      :after_startup,
      :before_stop,
      :before_user_register,
      :after_user_register,
      :after_user_logged_in,
      :after_user_updated,
      :after_user_online,
      :after_user_offline,
      :after_user_deleted,
      :after_wallet_changed,
      :after_inventory_changed,
      :before_user_update,
      :validate_username,
      :before_lobby_create,
      :after_lobby_create,
      :before_group_create,
      :after_group_create,
      :before_lobby_join,
      :after_lobby_join,
      :before_group_join,
      :before_group_update,
      :after_group_updated,
      :after_group_join,
      :after_group_leave,
      :after_group_deleted,
      :after_group_kick,
      :before_group_delete,
      :before_group_kick,
      :before_party_create,
      :after_party_create,
      :before_party_update,
      :after_party_updated,
      :after_party_join,
      :after_party_leave,
      :after_party_kick,
      :after_party_disband,
      :before_party_join,
      :before_party_kick,
      :before_chat_message,
      :after_chat_message,
      :after_chat_message_reported,
      :after_user_muted,
      :before_push_send,
      :after_push_sent,
      :before_lobby_leave,
      :after_lobby_leave,
      :before_lobby_update,
      :after_lobby_updated,
      :before_lobby_delete,
      :after_lobby_deleted,
      :before_lobby_state_change,
      :after_lobby_state_changed,
      :before_lobby_kick,
      :after_lobby_kick,
      :after_lobby_host_change,
      :before_ready_check_open,
      :after_ready_check_passed,
      :after_ready_check_failed,
      :before_quest_claim,
      :after_quest_completed,
      :after_quest_claimed,
      :after_score_submitted,
      :before_matchmaking_join,
      :after_matchmaking_join,
      :after_matchmaking_cancel,
      :matchmaking_form_matches,
      :after_matchmaking_matched,
      :before_purchase,
      :before_tournament_register,
      :after_tournament_register,
      :before_tournament_leave,
      :tournament_match_ready,
      :tournament_match_expired,
      :before_tournament_result,
      :after_tournament_match_resolved,
      :after_tournament_finished,
      :after_purchase_fulfilled,
      :after_purchase_revoked,
      :after_entitlement_changed,
      :on_custom_hook,
      :before_kv_get,
      # Plugin declaration/metadata functions. The host calls these to discover a
      # plugin's env vars, notification types, realtime events and wire schemas;
      # they are not a client-facing API, so they must not be RPC-callable (or
      # appear in the RPC list) — a client could otherwise read a plugin's whole
      # config surface via call_hook.
      :env_vars,
      :notification_types,
      :realtime_events,
      :kv_schemas,
      :metadata_schemas
    ])
  end

  # The hooks module leads, a host app's own modules follow, plugins last.
  # `config :gamend_core, :host_hook_modules, [MyApp.Hooks]` is for a host
  # that wants a lifecycle event without taking over `:hooks_module`, which
  # would move every fan-out hook's primary result off `Default`. A host
  # module exports only what it implements, and is called only for that.
  defp lifecycle_modules do
    base = module()
    host_mods = Application.get_env(:gamend_core, :host_hook_modules, [])

    plugin_mods =
      Enum.map(PluginManager.hook_modules(), fn {_name, mod} -> mod end)

    ([base | host_mods] ++ plugin_mods)
    |> Enum.uniq()
  end

  @doc """
  True when the hook transforms its input (a `before_*` pipeline hook) rather
  than fanning out notifications. Exposed for the admin runtime page.
  """
  def pipeline_hook?(name, arity), do: lifecycle_pipeline_hook?(name, arity)

  defp lifecycle_pipeline_hook?(name, arity) when is_atom(name) and is_integer(arity) do
    (name in core_pipeline_hooks() or name in pipeline_hooks()) and arity > 0
  end

  @doc """
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
  """
  @spec register_pipeline_hook(atom()) :: :ok
  def register_pipeline_hook(name) when is_atom(name) do
    config = Application.get_env(:gamend_core, __MODULE__, [])
    names = config |> Keyword.get(:pipeline_hooks, []) |> List.delete(name)

    Application.put_env(
      :gamend_core,
      __MODULE__,
      Keyword.put(config, :pipeline_hooks, [name | names])
    )
  end

  @doc "Undoes `register_pipeline_hook/1`."
  @spec unregister_pipeline_hook(atom()) :: :ok
  def unregister_pipeline_hook(name) when is_atom(name) do
    config = Application.get_env(:gamend_core, __MODULE__, [])
    names = config |> Keyword.get(:pipeline_hooks, []) |> List.delete(name)

    Application.put_env(:gamend_core, __MODULE__, Keyword.put(config, :pipeline_hooks, names))
  end

  @doc "Pipeline hook names registered on top of core's own."
  @spec pipeline_hooks() :: [atom()]
  def pipeline_hooks do
    :gamend_core |> Application.get_env(__MODULE__, []) |> Keyword.get(:pipeline_hooks, [])
  end

  defp core_pipeline_hooks do
    [
      :before_user_register,
      :before_user_update,
      :before_lobby_create,
      :before_group_create,
      :before_lobby_join,
      :before_group_join,
      :before_group_update,
      :before_party_create,
      :before_party_update,
      :before_chat_message,
      :before_push_send,
      :before_lobby_update,
      :before_lobby_delete,
      :before_lobby_kick,
      :before_group_delete,
      :before_group_kick,
      :before_party_join,
      :before_party_kick,
      :before_matchmaking_join,
      :before_purchase,
      :before_tournament_register,
      :before_tournament_leave,
      :before_tournament_result,
      :before_quest_claim,
      :before_lobby_state_change,
      :before_ready_check_open
    ]
  end

  # Ensure all plain-map arguments passed to before_* hooks have string keys.
  # Structs (User, Group, etc.) are left untouched.
  defp normalize_hook_args(args) when is_list(args) do
    Enum.map(args, fn
      %_{} = struct -> struct
      m when is_map(m) -> Gamend.Parse.string_keys(m)
      other -> other
    end)
  end

  defp run_before_pipeline(mods, name, args, opts, timeout) do
    arity = length(args)
    args = normalize_hook_args(args)

    if Enum.any?(mods, &exports_function?(&1, name, arity)) do
      mods
      |> Enum.reduce_while(args, fn mod, current_args ->
        pipeline_step(mod, name, current_args, opts, timeout, arity)
      end)
      |> case do
        {:error, reason} -> {:error, reason}
        final_args -> {:ok, finalize_pipeline_value(name, final_args)}
      end
    else
      defaults_for_missing_callback(name, args)
    end
  end

  defp pipeline_step(mod, name, current_args, opts, timeout, arity)
       when is_atom(mod) and is_atom(name) and is_list(current_args) and is_list(opts) and
              is_integer(timeout) and is_integer(arity) do
    if exports_function?(mod, name, arity) do
      mod
      |> safe_apply_raw(name, current_args, opts, timeout)
      |> handle_pipeline_apply_result(name, current_args)
    else
      {:cont, current_args}
    end
  end

  defp handle_pipeline_apply_result({:ok, {:error, reason}}, _name, _current_args),
    do: {:halt, {:error, reason}}

  defp handle_pipeline_apply_result({:error, reason}, _name, _current_args),
    do: {:halt, {:error, reason}}

  defp handle_pipeline_apply_result({:ok, {:ok, new}}, name, current_args) do
    case normalize_pipeline_args(name, new, current_args) do
      {:ok, new_args} -> {:cont, normalize_hook_args(new_args)}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp handle_pipeline_apply_result({:ok, new}, name, current_args) do
    # For convenience, allow before_* hooks to return a raw value and treat it
    # like {:ok, value}.
    handle_pipeline_apply_result({:ok, {:ok, new}}, name, current_args)
  end

  defp normalize_pipeline_args(:before_matchmaking_join, value, current_args)
       when is_list(current_args) and length(current_args) == 2 do
    case value do
      tuple when is_tuple(tuple) and tuple_size(tuple) == 2 -> {:ok, Tuple.to_list(tuple)}
      attrs -> {:ok, [Enum.at(current_args, 0), attrs]}
    end
  end

  defp normalize_pipeline_args(:before_group_create, value, current_args)
       when is_list(current_args) and length(current_args) == 2 do
    case value do
      tuple when is_tuple(tuple) and tuple_size(tuple) == 2 -> {:ok, Tuple.to_list(tuple)}
      attrs -> {:ok, [Enum.at(current_args, 0), attrs]}
    end
  end

  defp normalize_pipeline_args(:before_chat_message, value, current_args)
       when is_list(current_args) and length(current_args) == 2 do
    case value do
      tuple when is_tuple(tuple) and tuple_size(tuple) == 2 -> {:ok, Tuple.to_list(tuple)}
      attrs -> {:ok, [Enum.at(current_args, 0), attrs]}
    end
  end

  defp normalize_pipeline_args(:before_push_send, value, current_args)
       when is_list(current_args) and length(current_args) == 2 do
    case value do
      tuple when is_tuple(tuple) and tuple_size(tuple) == 2 -> {:ok, Tuple.to_list(tuple)}
      message -> {:ok, [Enum.at(current_args, 0), message]}
    end
  end

  defp normalize_pipeline_args(:before_party_create, value, current_args)
       when is_list(current_args) and length(current_args) == 2 do
    case value do
      tuple when is_tuple(tuple) and tuple_size(tuple) == 2 -> {:ok, Tuple.to_list(tuple)}
      attrs -> {:ok, [Enum.at(current_args, 0), attrs]}
    end
  end

  defp normalize_pipeline_args(:before_party_update, value, current_args)
       when is_list(current_args) and length(current_args) == 2 do
    case value do
      tuple when is_tuple(tuple) and tuple_size(tuple) == 2 -> {:ok, Tuple.to_list(tuple)}
      attrs -> {:ok, [Enum.at(current_args, 0), attrs]}
    end
  end

  defp normalize_pipeline_args(:before_lobby_update, value, current_args)
       when is_list(current_args) and length(current_args) == 2 do
    case value do
      tuple when is_tuple(tuple) and tuple_size(tuple) == 2 -> {:ok, Tuple.to_list(tuple)}
      attrs -> {:ok, [Enum.at(current_args, 0), attrs]}
    end
  end

  defp normalize_pipeline_args(:before_user_update, value, current_args)
       when is_list(current_args) and length(current_args) == 2 do
    case value do
      tuple when is_tuple(tuple) and tuple_size(tuple) == 2 -> {:ok, Tuple.to_list(tuple)}
      attrs -> {:ok, [Enum.at(current_args, 0), attrs]}
    end
  end

  defp normalize_pipeline_args(:before_user_register, value, current_args)
       when is_list(current_args) and length(current_args) == 2 do
    case value do
      tuple when is_tuple(tuple) and tuple_size(tuple) == 2 -> {:ok, Tuple.to_list(tuple)}
      attrs -> {:ok, [Enum.at(current_args, 0), attrs]}
    end
  end

  defp normalize_pipeline_args(:before_group_update, value, current_args)
       when is_list(current_args) and length(current_args) == 2 do
    case value do
      tuple when is_tuple(tuple) and tuple_size(tuple) == 2 -> {:ok, Tuple.to_list(tuple)}
      attrs -> {:ok, [Enum.at(current_args, 0), attrs]}
    end
  end

  # Veto-only pipelines: the hook allows or rejects; whatever it
  # returns never rewrites the pipeline args.
  defp normalize_pipeline_args(name, _value, current_args)
       when name in [
              :before_purchase,
              :before_tournament_register,
              :before_tournament_leave,
              :before_tournament_result,
              :before_quest_claim,
              :before_lobby_state_change,
              :before_ready_check_open
            ] and is_list(current_args) do
    {:ok, current_args}
  end

  defp normalize_pipeline_args(_name, value, current_args) when is_list(current_args) do
    arity = length(current_args)

    cond do
      is_tuple(value) and tuple_size(value) == arity ->
        {:ok, Tuple.to_list(value)}

      arity == 1 ->
        {:ok, [value]}

      true ->
        {:error, {:invalid_arity, arity}}
    end
  end

  defp finalize_pipeline_value(:before_matchmaking_join, args)
       when is_list(args) and length(args) == 2 do
    Enum.at(args, 1)
  end

  defp finalize_pipeline_value(:before_group_create, args)
       when is_list(args) and length(args) == 2 do
    Enum.at(args, 1)
  end

  defp finalize_pipeline_value(:before_chat_message, args)
       when is_list(args) and length(args) == 2 do
    Enum.at(args, 1)
  end

  defp finalize_pipeline_value(:before_push_send, args)
       when is_list(args) and length(args) == 2 do
    Enum.at(args, 1)
  end

  defp finalize_pipeline_value(:before_lobby_update, args)
       when is_list(args) and length(args) == 2 do
    Enum.at(args, 1)
  end

  defp finalize_pipeline_value(:before_user_update, args)
       when is_list(args) and length(args) == 2 do
    Enum.at(args, 1)
  end

  defp finalize_pipeline_value(:before_user_register, args)
       when is_list(args) and length(args) == 2 do
    Enum.at(args, 1)
  end

  defp finalize_pipeline_value(:before_group_update, args)
       when is_list(args) and length(args) == 2 do
    Enum.at(args, 1)
  end

  defp finalize_pipeline_value(:before_party_create, args)
       when is_list(args) and length(args) == 2 do
    Enum.at(args, 1)
  end

  defp finalize_pipeline_value(:before_party_update, args)
       when is_list(args) and length(args) == 2 do
    Enum.at(args, 1)
  end

  defp finalize_pipeline_value(name, args) when is_atom(name) and is_list(args) do
    case args do
      [single] ->
        single

      many
      when name in [
             :before_lobby_join,
             :before_group_join,
             :before_lobby_kick
           ] ->
        List.to_tuple(many)

      _other ->
        List.to_tuple(args)
    end
  end

  defp run_fanout(mods, name, args, opts, timeout) do
    arity = length(args)

    exporting_mods = Enum.filter(mods, &exports_function?(&1, name, arity))

    case exporting_mods do
      [] ->
        defaults_for_missing_callback(name, args)

      _ when name == :before_kv_get and arity == 2 ->
        run_before_kv_get(exporting_mods, args, opts, timeout)

      _ when name == :matchmaking_form_matches and arity == 2 ->
        run_matchmaking_form_matches(exporting_mods, args, opts, timeout)

      _ when name == :validate_username and arity == 1 ->
        run_validate_username(exporting_mods, args, opts, timeout)

      [first_mod | rest] ->
        first_res = safe_apply_raw(first_mod, name, args, opts, timeout)

        rest
        |> Enum.each(fn mod ->
          mod
          |> safe_apply_raw(name, args, opts, timeout)
          |> log_non_primary_hook_failure(mod, name)
        end)

        case first_res do
          {:ok, {:ok, res}} -> {:ok, res}
          {:ok, {:error, err}} -> {:error, err}
          {:ok, res} -> {:ok, res}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Unlike the `after_*` fanouts, this hook's return value is used, so the
  # plain "first module wins" rule would let `Hooks.Default` — always first in
  # the module list — shadow the plugin that actually implements it. `:default`
  # means "I abstain": modules are tried in order and the first real answer
  # wins.
  defp run_matchmaking_form_matches(mods, args, opts, timeout) do
    Enum.reduce_while(mods, {:ok, :default}, fn mod, acc ->
      case safe_apply_raw(mod, :matchmaking_form_matches, args, opts, timeout) do
        {:ok, groups} when is_list(groups) ->
          {:halt, {:ok, groups}}

        {:ok, :default} ->
          {:cont, acc}

        other ->
          Logger.warning(
            "Hooks.matchmaking_form_matches ignored mod=#{inspect(mod)}: #{inspect(other)}"
          )

          {:cont, acc}
      end
    end)
  end

  # `validate_username` answers for one handle; `:default` means "I abstain".
  # A hook that fails is logged and abstains: a plugin bug must never lock a
  # player out of registration.
  defp run_validate_username(mods, args, opts, timeout) do
    Enum.reduce_while(mods, {:ok, :default}, fn mod, acc ->
      case safe_apply_raw(mod, :validate_username, args, opts, timeout) do
        {:ok, :ok} ->
          {:halt, {:ok, :ok}}

        {:ok, {:error, message}} when is_binary(message) or is_atom(message) ->
          {:halt, {:ok, {:error, message}}}

        {:ok, :default} ->
          {:cont, acc}

        other ->
          Logger.warning("Hooks.validate_username ignored mod=#{inspect(mod)}: #{inspect(other)}")
          {:cont, acc}
      end
    end)
  end

  defp run_before_kv_get(mods, args, opts, timeout) when is_list(mods) do
    # Security-sensitive hook: default to :public. Multiple plugin decisions
    # are intersected; incompatible restrictions fail closed to :server_only.
    # If any hook errors (timeout/exception), fail closed.
    mods
    |> Enum.reduce_while(:public, fn mod, decision ->
      mod
      |> safe_apply_raw(:before_kv_get, args, opts, timeout)
      |> normalize_before_kv_get_result()
      |> case do
        {:ok, access} ->
          {:cont, combine_kv_access(decision, access)}

        {:error, reason} ->
          Logger.warning("Hooks.before_kv_get failed mod=#{inspect(mod)}: #{inspect(reason)}")

          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, _} = err -> err
      decision -> {:ok, decision}
    end
  end

  defp combine_kv_access(:public, access), do: access
  defp combine_kv_access(access, :public), do: access
  defp combine_kv_access(:server_only, _access), do: :server_only
  defp combine_kv_access(_access, :server_only), do: :server_only
  defp combine_kv_access(access, access), do: access
  defp combine_kv_access(:owner_or_lobby_member, :owner_only), do: :owner_only
  defp combine_kv_access(:owner_only, :owner_or_lobby_member), do: :owner_only
  defp combine_kv_access(:owner_or_lobby_member, :lobby_members_only), do: :lobby_members_only
  defp combine_kv_access(:lobby_members_only, :owner_or_lobby_member), do: :lobby_members_only
  defp combine_kv_access(_left, _right), do: :server_only

  defp normalize_before_kv_get_result({:error, reason}), do: {:error, reason}
  defp normalize_before_kv_get_result({:ok, {:error, reason}}), do: {:error, reason}

  defp normalize_before_kv_get_result({:ok, {:ok, decision}})
       when decision in @kv_access_levels,
       do: {:ok, decision}

  defp normalize_before_kv_get_result({:ok, decision}) when decision in @kv_access_levels,
    do: {:ok, decision}

  defp normalize_before_kv_get_result({:ok, other}), do: {:error, {:invalid_return, other}}

  defp log_non_primary_hook_failure({:error, reason}, mod, name) do
    Logger.warning(
      "Hooks callback failed mod=#{inspect(mod)} name=#{inspect(name)}: #{inspect(reason)}"
    )
  end

  defp log_non_primary_hook_failure({:ok, {:error, reason}}, mod, name) do
    Logger.warning(
      "Hooks callback failed mod=#{inspect(mod)} name=#{inspect(name)}: #{inspect(reason)}"
    )
  end

  defp log_non_primary_hook_failure(_ok, _mod, _name), do: :ok

  defp safe_apply_raw(mod, name, args, opts, timeout)
       when is_atom(mod) and is_atom(name) and is_list(args) and is_list(opts) do
    task =
      Task.async(fn ->
        if caller = Keyword.get(opts, :caller) do
          Process.put(:gamend_hook_caller, caller)
        end

        try do
          apply(mod, name, args)
        rescue
          e in FunctionClauseError -> {:error, {:function_clause, Exception.message(e)}}
          e -> {:error, {:exception, Exception.message(e)}}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, res} -> {:ok, res}
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, {:exit, reason}}
    end
  end

  defp defaults_for_missing_callback(name, args) do
    default_mod = Default
    arity = length(args)

    if exports_function?(default_mod, name, arity) do
      case apply(default_mod, name, args) do
        {:ok, _} = ok -> ok
        {:error, _} = err -> err
        other -> {:ok, other}
      end
    else
      # Fallback when the Default module doesn't export the callback.
      # For pipeline hooks that transform multi-arity args, use
      # finalize_pipeline_value to return the correct element (e.g. attrs
      # rather than user for before_group_create/2).
      if lifecycle_pipeline_hook?(name, arity) and arity > 0 do
        {:ok, finalize_pipeline_value(name, args)}
      else
        {:ok, Enum.at(args, 0)}
      end
    end
  end

  defp exports_function?(mod, name, arity)
       when is_atom(mod) and is_atom(name) and is_integer(arity) do
    Code.ensure_loaded?(mod) and function_exported?(mod, name, arity)
  end

  defp exports_function?(_mod, _name, _arity), do: false

  # Helper: extract docs-based signatures into a map name -> %{arity => %{signature: sig, doc: doc_text}}
  defp doc_signatures_for(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.reduce(docs, %{}, fn
          {{:function, name, arity}, _line, signatures, doc_text, _meta}, acc ->
            sig_text =
              case signatures do
                [] -> nil
                _ -> Enum.map_join(signatures, "\n", &to_string/1)
              end

            # normalize doc_text which Code.fetch_docs may return as an i18n map
            normalized_doc =
              cond do
                is_binary(doc_text) ->
                  doc_text

                is_map(doc_text) ->
                  Map.get(doc_text, "en") || Map.get(doc_text, :en) ||
                    Enum.join(Map.values(doc_text), "\n")

                true ->
                  nil
              end

            Map.update(
              acc,
              name,
              %{arity => %{signature: sig_text, doc: normalized_doc}},
              fn map ->
                Map.put(map, arity, %{signature: sig_text, doc: normalized_doc})
              end
            )

          _, acc ->
            acc
        end)

      _ ->
        %{}
    end
  end

  defp build_signature(ar, name, parsed_signatures, doc_signatures, spec_map) do
    parsed_entry = Map.get(parsed_signatures, {name, ar})

    parsed_sig =
      if is_map(parsed_entry), do: Map.get(parsed_entry, :signature), else: parsed_entry

    doc_entry = Map.get(Map.get(doc_signatures, name, %{}), ar, %{})
    doc_text = Map.get(parsed_entry || %{}, :doc) || Map.get(doc_entry, :doc)

    typespec_sig = Map.get(spec_map, {name, ar})
    chosen_signature = choose_signature(parsed_sig, doc_entry, typespec_sig)
    example_args = example_args_for(chosen_signature)

    %{
      arity: ar,
      signature: chosen_signature,
      doc: doc_text,
      example_args: example_args
    }
  end

  # Helper: build a map of {{name, arity} => typespec_string} for module specs
  defp spec_map_for(mod) do
    case Code.Typespec.fetch_specs(mod) do
      {:ok, specs} when is_list(specs) ->
        Enum.reduce(specs, %{}, fn
          {{name, arity}, spec_list}, acc when is_list(spec_list) and spec_list != [] ->
            spec = hd(spec_list)

            spec_str =
              try do
                Code.Typespec.spec_to_quoted(name, spec) |> Macro.to_string()
              rescue
                _ -> nil
              end

            if is_binary(spec_str), do: Map.put(acc, {name, arity}, spec_str), else: acc

          _, acc ->
            acc
        end)

      _ ->
        %{}
    end
  end

  defp choose_signature(parsed, doc_entry, typespec_sig) do
    # Prefer parsed -> doc signature -> typespec
    parsed || Map.get(doc_entry || %{}, :signature) || typespec_sig
  end

  defp example_args_for(nil), do: nil

  defp example_args_for(chosen_signature) when is_binary(chosen_signature) do
    if String.contains?(chosen_signature, "(") do
      params =
        chosen_signature
        |> String.trim()
        |> String.replace(~r/^\w+\(/, "")
        |> String.replace(~r/\)$/, "")
        |> String.split(",")
        |> Enum.map(&String.trim/1)

      # If params list is a single empty string it means there are no params
      # (e.g. "fn_name()") — treat as zero-arity and produce an empty list.
      params =
        if params == [""] do
          []
        else
          params
        end

      example_list =
        Enum.map(params, fn
          "" ->
            []

          p ->
            cond do
              String.match?(p, ~r/^\w+\d+$/) -> p
              String.match?(p, ~r/name|user|email|id|msg|message|text/i) -> "name"
              String.match?(p, ~r/count|num|index|n|id\b/i) -> 0
              String.match?(p, ~r/bool|flag|active|enabled|true|false/i) -> true
              String.match?(p, ~r/list|items|arr|_list/i) -> []
              String.match?(p, ~r/map|opts|options|attrs|params|meta/i) -> %{}
              true -> "#{p}"
            end
        end)

      json =
        Enum.map_join(example_list, ", ", fn
          val when is_binary(val) -> "\"#{val}\""
          val when is_integer(val) -> to_string(val)
          other -> inspect(other)
        end)

      # If there are no parameters, we should render [] not [[]].
      if example_list == [] do
        "[]"
      else
        "[#{json}]"
      end
    else
      nil
    end
  end

  @doc """
  Return a list of exported functions on the currently registered hooks module.

  The result is a list of maps like: [%{name: "start_game", arities: [2,3]}, ...]
  This is useful for tooling and admin UI to display what RPCs are available.
  """
  def exported_functions(mod \\ module()) when is_atom(mod) do
    case Code.ensure_loaded(mod) do
      {:module, _} ->
        # Exclude functions coming from the default implementation - show only
        # functions uniquely exported by the user-provided hooks module.
        default_names =
          Default.__info__(:functions)
          |> Enum.map(fn {n, _} -> n end)
          |> MapSet.new()

        # Also exclude internal hooks and scheduled callbacks
        internal = internal_hooks()
        scheduled = Gamend.Schedule.registered_callbacks()

        excluded =
          [default_names, internal, scheduled]
          |> Enum.flat_map(&MapSet.to_list/1)
          |> MapSet.new()

        # Group functions by name -> arities and then filter out the excluded set
        func_map =
          mod
          |> public_functions()
          |> Enum.group_by(fn {name, _arity} -> name end, fn {_name, arity} -> arity end)
          |> Enum.reject(fn {name, _arities} -> MapSet.member?(excluded, name) end)

        # Extract docs-based signatures from compiled module docs
        doc_signatures = doc_signatures_for(mod)

        # Source-based signature parsing (via HOOKS_FILE_PATH / :hooks_file_path)
        # has been removed. We only use BEAM metadata (docs + typespecs).
        parsed_signatures = %{}

        # Extract typespecs -> signature strings
        spec_map = spec_map_for(mod)

        func_map
        |> Enum.map(fn {name, arities} ->
          sigs =
            Enum.map(
              arities,
              &build_signature(&1, name, parsed_signatures, doc_signatures, spec_map)
            )

          %{name: to_string(name), arities: Enum.sort(arities), signatures: sigs}
        end)

      {:error, _} ->
        []
    end
  end

  # `__info__/1` exists only on Elixir modules, so a plugin built from Gleam,
  # LFE or Erlang crashed `GET /api/v1/hooks` (the RPC path, `PluginManager`,
  # already knew). `module_info/1` is on every BEAM module; it also lists
  # itself, which is no hook.
  defp public_functions(mod) do
    if function_exported?(mod, :__info__, 1) do
      mod.__info__(:functions)
    else
      Enum.reject(mod.module_info(:exports), fn {name, _arity} -> name == :module_info end)
    end
  end

  defp resolve_caller(opts) when is_list(opts) do
    case Keyword.get(opts, :caller) do
      %User{} = _u ->
        opts

      %{} = _m ->
        # Do not resolve maps with an :id here. Keep map callers untouched so
        # callers who pass a user-like map will receive it verbatim.
        opts

      id when is_binary(id) ->
        case Gamend.Accounts.get_user(id) do
          %User{} = user -> Keyword.put(opts, :caller, user)
          nil -> opts
        end

      _ ->
        opts
    end
  end

  defp resolve_caller(other), do: other

  @doc """
  When a hooks function is executed via `call/3` or `internal_call/3`, an
  optional `:caller` can be provided in the options. The caller will be
  injected into the spawned task's process dictionary and is accessible via
  `Gamend.Hooks.caller/0` (the raw value) or `caller_id/0` (the numeric id
  when the value is a user struct or map containing `:id`).
  """
  @spec caller() :: any() | nil
  def caller do
    Process.get(:gamend_hook_caller)
  end

  @spec caller_id() :: String.t() | nil
  def caller_id do
    case caller() do
      %User{id: id} when is_binary(id) -> id
      %{} = m when is_map(m) -> Map.get(m, :id) || Map.get(m, "id")
      id when is_binary(id) -> id
      _ -> nil
    end
  end

  @doc "Return the user struct for the current caller when available. This will
  attempt to resolve the caller via Gamend.Accounts.get_user!/1 when the
  caller is a user id or a map containing an `:id` key. Returns nil when
  no caller or user is found."
  @spec caller_user() :: Gamend.Accounts.User.t() | nil
  def caller_user do
    case caller() do
      %User{} = u ->
        u

      %{} = m ->
        id = Map.get(m, :id) || Map.get(m, "id")

        if is_binary(id), do: Gamend.Accounts.get_user(id), else: nil

      id when is_binary(id) ->
        Gamend.Accounts.get_user(id)

      _ ->
        nil
    end
  end

  # How long a plugin hook may run before it is killed.
  #
  # Much shorter when the caller is inside a `Repo.transaction`. Ten call sites
  # invoke hooks from inside one — group join, lobby join and create, party
  # operations, tournament registration — and on SQLite (the production default)
  # an open transaction holds the single pooled write connection. At the 60s
  # default, one slow or looping plugin stalled *every* write in the
  # application, not just the operation it was attached to; worse, the hook runs
  # in its own task, so a plugin that touches the database ends up waiting on a
  # connection the caller is holding, and burns the whole budget doing nothing.
  #
  # Outside a transaction the generous budget stays: a hook doing real work on
  # its own time blocks nothing but its own request.
  #
  # Both budgets are settings (`GAMEND_HOOKS_CALL_TIMEOUT_MS` and
  # `GAMEND_HOOKS_CALL_TIMEOUT_IN_TRANSACTION_MS`).
  defp default_hook_timeout, do: PluginManager.call_timeout_ms()
end

defmodule Gamend.Hooks.Default do
  @moduledoc "Default no-op implementation for Gamend.Hooks"
  @behaviour Gamend.Hooks

  alias Gamend.Accounts.User
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Purchase

  @impl true
  def after_startup, do: :ok

  @impl true
  def before_stop, do: :ok

  @impl true
  def before_user_register(_user, attrs), do: {:ok, attrs}

  @impl true
  def after_user_register(_user), do: :ok

  @impl true
  def after_user_logged_in(_user), do: :ok

  @impl true
  def after_user_updated(_user), do: :ok

  @impl true
  def after_wallet_changed(_change), do: :ok

  @impl true
  def after_inventory_changed(_change), do: :ok

  @impl true
  def after_user_online(_user), do: :ok

  @impl true
  def after_user_offline(_user), do: :ok

  @impl true
  def after_user_deleted(_user), do: :ok

  @impl true
  def before_user_update(_user, attrs), do: {:ok, attrs}

  @impl true
  def validate_username(_username), do: :default

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
  def before_group_join(user, group, opts), do: {:ok, {user, group, opts}}

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
  def before_group_kick(admin_id, target_id, group_id), do: {:ok, {admin_id, target_id, group_id}}

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
  def before_party_join(user, party), do: {:ok, {user, party}}

  @impl true
  def before_party_kick(target, leader, party), do: {:ok, {target, leader, party}}

  @impl true
  def before_chat_message(_user, attrs), do: {:ok, attrs}

  @impl true
  def after_chat_message(_message), do: :ok

  @impl true
  def after_chat_message_reported(_report), do: :ok

  @impl true
  def after_user_muted(_mute), do: :ok

  @impl true
  def before_push_send(_user_id, message), do: {:ok, message}

  @impl true
  def after_push_sent(_user_id, _message, _result), do: :ok

  @impl true
  def after_lobby_join(_user, _lobby), do: :ok

  @impl true
  def before_lobby_leave(_user, _lobby), do: :ok

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
  @doc """
  Default implementation for `before_kv_get/2`.

  Scope-aware, not blanket-public. A global entry (no `user_id`, no `lobby_id`)
  is `:public`, which is what makes a shared config or welcome value readable by
  everyone. A read that *names* a user or lobby defaults to
  `:owner_or_lobby_member`, so the caller has to be that user or in that lobby.

  It used to return `:public` unconditionally, and `kv_access_allowed?/4` grants
  a `:public` read without looking at who is asking — so with no plugin
  overriding this hook, `GET /api/v1/kv/save_data?user_id=<someone else>` (and
  the `kv:subscribe` channel event, which then streamed every later write)
  returned another player's entries. Saves and progression live there.

  A game that genuinely wants cross-player reads implements this hook and
  returns `:public` for those keys.
  """
  def before_kv_get(_key, opts) do
    scoped? =
      is_binary(opts[:user_id]) or is_binary(opts["user_id"]) or
        is_binary(opts[:lobby_id]) or is_binary(opts["lobby_id"])

    if scoped?, do: :owner_or_lobby_member, else: :public
  end

  @impl true
  def before_quest_claim(_user_id, _quest, _progress), do: :ok

  @impl true
  def after_quest_completed(_progress), do: :ok

  @impl true
  def after_quest_claimed(_progress), do: :ok

  @impl true
  def after_score_submitted(_record), do: :ok

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
  def before_purchase(_user, product), do: {:ok, product}

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

  @impl true
  def after_purchase_fulfilled(%Purchase{} = purchase) do
    update_user_payment_metadata(purchase.user_id, fn metadata ->
      purchase_active = purchase.status == "completed"
      purchase_id = to_string(purchase.id)

      metadata
      |> put_payment_child("purchase_ids", purchase_id, purchase_active)
      |> put_payment_child(
        "purchase_details",
        purchase_id,
        purchase_metadata(purchase, purchase_active)
      )
    end)
  end

  @impl true
  def after_purchase_revoked(%Purchase{} = purchase) do
    update_user_payment_metadata(purchase.user_id, fn metadata ->
      purchase_id = to_string(purchase.id)

      metadata
      |> put_payment_child("purchase_ids", purchase_id, false)
      |> put_payment_child("purchase_details", purchase_id, purchase_metadata(purchase, false))
    end)
  end

  @impl true
  def after_entitlement_changed(%Entitlement{} = entitlement) do
    active = entitlement_active?(entitlement)

    update_user_payment_metadata(entitlement.user_id, fn metadata ->
      entitlement_id = to_string(entitlement.id)

      metadata
      |> put_payment_child("entitlements", entitlement.key, active)
      |> put_payment_child("entitlement_ids", entitlement_id, active)
      |> put_payment_child(
        "entitlement_details",
        entitlement.key,
        entitlement_metadata(entitlement, active)
      )
    end)
  end

  @impl true
  def on_custom_hook(_hook, _args), do: {:error, :not_implemented}

  # Optimistic, so the plugins' `before_user_update` hook (up to its timeout)
  # runs outside the lock: read, merge and ask the hook unlocked, then write
  # under the lock only if the metadata is still what the merge started from.
  # A concurrent change starts it over; the lock guards only the write.
  @payment_metadata_attempts 3

  defp update_user_payment_metadata(user_id, fun)
       when is_binary(user_id) and is_function(fun, 1) do
    update_user_payment_metadata(user_id, fun, @payment_metadata_attempts)
  end

  defp update_user_payment_metadata(_user_id, _fun), do: :ok

  defp update_user_payment_metadata(user_id, fun, attempts) do
    with %User{} = user <- Gamend.Repo.get(User, user_id) || {:error, :user_not_found},
         {:ok, attrs} <-
           Gamend.Accounts.run_before_user_update(user, %{metadata: fun.(user.metadata)}) do
      "user_payment_metadata"
      |> Gamend.Lock.serialize(user_id, fn -> write_payment_metadata(user, attrs) end)
      |> case do
        {:ok, :stale} when attempts > 1 ->
          update_user_payment_metadata(user_id, fun, attempts - 1)

        {:ok, :stale} ->
          {:error, :conflict}

        {:ok, {:ok, _user}} ->
          :ok

        {:ok, {:error, reason}} ->
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp write_payment_metadata(%User{id: id, metadata: read}, attrs) do
    case Gamend.Repo.get(User, id) do
      %User{metadata: ^read} = current -> Gamend.Accounts.apply_user_update(current, attrs)
      %User{} -> :stale
      nil -> {:error, :user_not_found}
    end
  end

  defp put_payment_child(metadata, child_key, item_key, value) do
    payments = metadata |> Map.get("payments") |> map_or_empty()
    child = payments |> Map.get(child_key) |> map_or_empty()

    Map.put(metadata, "payments", Map.put(payments, child_key, Map.put(child, item_key, value)))
  end

  defp map_or_empty(value) when is_map(value), do: value
  defp map_or_empty(_value), do: %{}

  defp purchase_metadata(%Purchase{} = purchase, active) do
    %{
      "active" => active,
      "amount" => purchase.amount,
      "currency" => purchase.currency,
      "order_id" => purchase.order_id,
      "product_id" => purchase.product_id,
      "provider" => purchase.provider,
      "provider_product_id" => purchase.provider_product_id,
      "provider_transaction_id" => purchase.provider_transaction_id,
      "status" => purchase.status,
      "purchased_at" => datetime_iso(purchase.purchased_at),
      "revoked_at" => datetime_iso(purchase.revoked_at)
    }
  end

  defp entitlement_metadata(%Entitlement{} = entitlement, active) do
    %{
      "active" => active,
      "expires_at" => datetime_iso(entitlement.expires_at),
      "id" => entitlement.id,
      "key" => entitlement.key,
      "product_id" => entitlement.product_id,
      "revoked_at" => datetime_iso(entitlement.revoked_at),
      "source_purchase_id" => entitlement.source_purchase_id,
      "status" => entitlement.status
    }
  end

  defp entitlement_active?(%Entitlement{status: "active", expires_at: nil}), do: true

  defp entitlement_active?(%Entitlement{status: "active", expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now(:second)) == :gt
  end

  defp entitlement_active?(_entitlement), do: false

  defp datetime_iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp datetime_iso(_value), do: nil
end
