defmodule GameServer.ReadyChecks do
  @moduledoc ~S"""
  Ready checks: *these players must each answer before this proceeds*.
  
  One primitive, two kinds — the only differences are what a "no" means and
  whether an answer can be taken back:
  
  | | `"accept"` | `"ready"` |
  | --- | --- | --- |
  | Answer | one-shot, irrevocable | a toggle |
  | A "no" | fails the check for everyone | leaves it pending |
  | Deadline | mandatory | optional |
  | On timeout | fails | fails, naming who stalled |
  
  `"ready"` is the lobby's ready-up and the party's standing ready board;
  `"accept"` is matchmaking's match confirmation (see
  `docs/specs/ready-check.md`).
  
  ## Two lanes
  
  A player can be in at most one open check *per lane*: the match lane (lobby
  ready or matchmaking accept — one match at a time) and the party lane. The
  lanes are independent, so a party's standing board never blocks the party's
  lobby from opening its own check.
  
  ## What core does *not* do
  
  A failed check kicks nobody, deletes no lobby and moves no lobby state. Core
  records who did not answer (`not_ready/1`); the host — or the game, in
  `after_ready_check_failed` — decides what that is worth.
  
  ## Usage
  
      {:ok, check} = ReadyChecks.open(lobby, member_ids, opened_by: host.id)
      {:ok, check} = ReadyChecks.respond(user, true)
      ReadyChecks.passed?(lobby)
  
  ## Concurrency
  
  Answering is a single-row write, so no two players can lose each other's
  flag. *Evaluating* the result is the part that races: two players answering
  at once can each count the other as still pending, and nobody passes. So
  `respond/3` holds a per-check advisory lock (`:ready_check`) around
  write-then-evaluate. Hooks and broadcasts fire after the lock is released —
  never inside the transaction.
  

  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the GameServer.
  """

  @type answer() :: boolean()
  @type scope() :: :match | :party
  @type subject() :: GameServer.Lobbies.Lobby.t() | GameServer.Parties.Party.t() | :matchmaking

  @doc ~S"""
    Adds a member to the lobby's open check, if there is one.
  """
  @spec add_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def add_member(_lobby_id, _user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.ReadyChecks.add_member/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Adds a member to the party's open check, if there is one.
  """
  @spec add_party_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def add_party_member(_party_id, _user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.ReadyChecks.add_party_member/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Answers on behalf of a member — for bots and AI-controlled players, which
    cannot press anything.
    
    Server-side only: this is in `internal_hooks()`, so a client cannot reach it
    over RPC and mark someone else ready.
    
  """
  @spec answer_for(GameServer.ReadyChecks.Check.t(), Ecto.UUID.t(), answer()) ::
  {:ok, GameServer.ReadyChecks.Check.t()} | {:error, term()}
  def answer_for(_check, _user_id, _ready?) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.ReadyChecks.Check{id: "", kind: "ready", status: "pending", lobby_id: nil, deadline_at: nil, opened_by: nil, reason: nil, resolved_at: nil, metadata: %{}, participants: [], inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.ReadyChecks.answer_for/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Cancels a pending check — the host called it off, or the subject went away.
  """
  @spec cancel(GameServer.ReadyChecks.Check.t(), String.t()) ::
  {:ok, GameServer.ReadyChecks.Check.t()} | {:error, term()}
  def cancel(_check, _reason) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.ReadyChecks.Check{id: "", kind: "ready", status: "pending", lobby_id: nil, deadline_at: nil, opened_by: nil, reason: nil, resolved_at: nil, metadata: %{}, participants: [], inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.ReadyChecks.cancel/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Cancels the lobby's pending check, if it has one.
  """
  @spec cancel_for_lobby(Ecto.UUID.t()) :: :ok
  def cancel_for_lobby(_lobby_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.ReadyChecks.cancel_for_lobby/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Cancels the party's pending check, if it has one.
  """
  @spec cancel_for_party(Ecto.UUID.t()) :: :ok
  def cancel_for_party(_party_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.ReadyChecks.cancel_for_party/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Counts checks matching the same filters as `list_checks/1`.
  """
  @spec count_checks(keyword()) :: non_neg_integer()
  def count_checks(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.ReadyChecks.count_checks/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Fails one check on its deadline_at. A no-op if it already resolved.
  """
  @spec expire(GameServer.ReadyChecks.Check.t()) :: :ok | :noop
  def expire(_check) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.ReadyChecks.expire/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Fails every pending check whose deadline_at has passed.
    
    Each still-unanswered participant becomes `timed_out`. Returns how many
    checks were expired. Idempotent, so the durable expiry job and the
    matchmaking sweep's backstop can both run it.
    
  """
  @spec expire_due(DateTime.t()) :: non_neg_integer()
  def expire_due(_now) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.ReadyChecks.expire_due/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The caller's open check, with participants preloaded, or nil.
    
    `scope` narrows to one lane: `:match` (lobby or matchmaking) or `:party`.
    `:any` returns the newest across both lanes — the admin's view, not the
    API's.
    
  """
  @spec for_user(GameServer.Accounts.User.t() | Ecto.UUID.t(), scope() | :any) ::
  GameServer.ReadyChecks.Check.t() | nil
  def for_user(_user, _scope) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.ReadyChecks.Check{id: "", kind: "ready", status: "pending", lobby_id: nil, deadline_at: nil, opened_by: nil, reason: nil, resolved_at: nil, metadata: %{}, participants: [], inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.ReadyChecks.for_user/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Fetches a check by id (with participants), or nil.
  """
  @spec get_check(Ecto.UUID.t()) :: GameServer.ReadyChecks.Check.t() | nil
  def get_check(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.ReadyChecks.Check{id: "", kind: "ready", status: "pending", lobby_id: nil, deadline_at: nil, opened_by: nil, reason: nil, resolved_at: nil, metadata: %{}, participants: [], inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.ReadyChecks.get_check/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Lists checks for the admin views, newest first.
    
    Options: `:status`, `:kind`, `:lobby_id`, `:party_id`, `:page`,
    `:page_size`.
    
  """
  @spec list_checks(keyword()) :: [GameServer.ReadyChecks.Check.t()]
  def list_checks(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.ReadyChecks.list_checks/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The participants who did not answer ready — the host's kick list, and what
    `after_ready_check_failed` is handed.
    
  """
  @spec not_ready(GameServer.ReadyChecks.Check.t()) :: [GameServer.ReadyChecks.Participant.t()]
  def not_ready(_check) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.ReadyChecks.not_ready/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Opens a check over `user_ids` and notifies them.
    
    `subject` is a `%Lobby{}` or `%Party{}` (kind `"ready"`) or `:matchmaking`
    (kind `"accept"`). Options:
    
      * `:kind` — override the kind implied by the subject
      * `:timeout_ms` — answering window; `nil` leaves a `"ready"` check open
        until it passes or is cancelled. Defaults to `ready_check_timeout_ms`.
      * `:opened_by` — the user who asked for it; they are pre-marked ready,
        since clicking the button is their answer
      * `:ready` — user ids to pre-mark ready (bots, an auto-ready mode)
      * `:tickets` — `%{user_id => ticket_id}` for matchmaking checks
      * `:metadata` — game payload echoed to clients (match params, mode)
    
    Fails with `{:error, :already_pending}` when the subject already has an open
    check or any player is in one in the same lane, `{:error, :no_participants}`,
    and `{:error, :too_many_participants}` past `max_ready_check_participants`.
    
  """
  @spec open(subject(), [Ecto.UUID.t()], keyword()) ::
  {:ok, GameServer.ReadyChecks.Check.t()} | {:error, term()}
  def open(_subject, _user_ids, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.ReadyChecks.Check{id: "", kind: "ready", status: "pending", lobby_id: nil, deadline_at: nil, opened_by: nil, reason: nil, resolved_at: nil, metadata: %{}, participants: [], inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.ReadyChecks.open/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    True when the subject's most recent check passed.
    
    What a game calls from `before_lobby_state_change` to gate its own start.
    A reset opens a fresh pending check, which makes this false again — so a
    rematch cannot ride the previous match's pass.
    
  """
  @spec passed?(GameServer.Lobbies.Lobby.t() | GameServer.Parties.Party.t() | Ecto.UUID.t()) :: boolean()
  def passed?(_lobby_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "GameServer.ReadyChecks.passed?/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The lobby's open check, with participants preloaded, or nil.
  """
  @spec pending_for_lobby(Ecto.UUID.t()) :: GameServer.ReadyChecks.Check.t() | nil
  def pending_for_lobby(_lobby_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.ReadyChecks.Check{id: "", kind: "ready", status: "pending", lobby_id: nil, deadline_at: nil, opened_by: nil, reason: nil, resolved_at: nil, metadata: %{}, participants: [], inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.ReadyChecks.pending_for_lobby/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The party's open check, with participants preloaded, or nil.
  """
  @spec pending_for_party(Ecto.UUID.t()) :: GameServer.ReadyChecks.Check.t() | nil
  def pending_for_party(_party_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.ReadyChecks.Check{id: "", kind: "ready", status: "pending", lobby_id: nil, deadline_at: nil, opened_by: nil, reason: nil, resolved_at: nil, metadata: %{}, participants: [], inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.ReadyChecks.pending_for_party/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Drops a member from the lobby's open check and re-evaluates it.
    
    Called when someone leaves or is kicked: kicking the one player who never
    answered is a legitimate way to pass a check.
    
  """
  @spec remove_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def remove_member(_lobby_id, _user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.ReadyChecks.remove_member/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Drops a member from the party's open check and re-evaluates it.
  """
  @spec remove_party_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def remove_party_member(_party_id, _user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.ReadyChecks.remove_party_member/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Resets the subject's board: quietly cancels its pending check (no failed
    event, no hook — the fresh `ready_check_started` replaces it on clients) and
    opens a new one over `user_ids`.
    
    The one verb behind every "answers are stale now" moment: a match ended
    (rematch needs a fresh board), the game mode changed, a member joined a
    party whose board had already resolved, or the host wants everyone to
    re-confirm on a deadline_at ("force ready"). Same options as `open/3`.
    
  """
  @spec reset(subject(), [Ecto.UUID.t()], keyword()) ::
  {:ok, GameServer.ReadyChecks.Check.t()} | {:error, term()}
  def reset(_subject, _user_ids, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.ReadyChecks.Check{id: "", kind: "ready", status: "pending", lobby_id: nil, deadline_at: nil, opened_by: nil, reason: nil, resolved_at: nil, metadata: %{}, participants: [], inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.ReadyChecks.reset/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Records the caller's answer to their open check in `scope` and re-evaluates
    it.
    
    `scope` is `:match` (the lobby ready-up or matchmaking accept — the default)
    or `:party` (the party's standing board): a player can hold one open check
    in each lane, so the answer needs to say which one it is for.
    
    `true` is "ready"/"accept"; `false` is "not ready"/"decline". In an `accept`
    check a decline fails the whole check; in a `ready` check it just leaves the
    check pending and can be taken back.
    
    Returns the check as it stands after the answer. Fails with
    `{:error, :no_open_check}` and, for an `accept` check the caller already
    answered, `{:error, :not_revocable}`.
    
  """
  @spec respond(GameServer.Accounts.User.t() | Ecto.UUID.t(), answer(), scope()) ::
  {:ok, GameServer.ReadyChecks.Check.t()} | {:error, term()}
  def respond(_user, _ready?, _scope) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.ReadyChecks.Check{id: "", kind: "ready", status: "pending", lobby_id: nil, deadline_at: nil, opened_by: nil, reason: nil, resolved_at: nil, metadata: %{}, participants: [], inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.ReadyChecks.respond/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Counts by status over the last `hours` — the accept-rate and dodge-rate
    numbers on the admin page.
    
  """
  @spec stats(pos_integer()) :: %{required(String.t()) => non_neg_integer()}
  def stats(_hours) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.ReadyChecks.stats/1 is a stub - only available at runtime on GameServer"
    end
  end

end
