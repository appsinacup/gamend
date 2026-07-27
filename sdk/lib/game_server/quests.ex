defmodule GameServer.Quests do
  @moduledoc ~S"""
  Event-driven quest/progression engine.
  
  One engine, three independent dimensions: a **reset** cycle (never / daily /
  weekly / monthly / every N days), an optional **window**
  (`starts_at`/`ends_at`), and an optional **prerequisite**
  (`prerequisite_quest_key`). Any combination works — a biweekly quest inside
  a seasonal window that also requires an earlier quest is just those three
  fields set. Rewards pay into `GameServer.Economy` / `GameServer.Inventory`
  exactly once. `category` is a free-form label for your UI only.
  
  ## Reporting progress (server-side / hooks)
  
      Quests.report_event(user_id, "enemy_killed", 1, %{"map" => "desert"})
  
  Every **active** quest with an objective on `"enemy_killed"` (whose `params`
  all match the meta) advances; a quest completes when every objective meets
  its target. There is deliberately **no public endpoint** for this — clients
  cannot advance their own quests. Core wires common events; games call it
  from their hooks for custom events.
  
  ## Claiming
  
      {:ok, %{progress: progress, rewards: rewards}} = Quests.claim(user_id, "daily_win_3")
  
  Claiming is gated by an atomic `completed → claimed` status transition, so a
  double-tap or a concurrent claim can't double-pay. Rewards are granted after
  the transition with a per-entry idempotency key (`"quest:<progress_id>:<i>"`),
  so a crashed or retried grant can't double-apply either; rows that claimed
  but never finished granting are healed by `recover_pending_rewards/1`.
  Quests with `auto_claim` grant immediately on completion (skipping the
  `before_quest_claim` hook — there is no player request to veto).
  
  ## Resets
  
  `period_key` is derived from **UTC time** by the quest's reset (daily →
  `"2026-07-22"`, weekly → `"2026-W30"`, monthly → `"2026-07"`, interval →
  `"I14-1436"`, never → `"static"`). A new period simply means a new progress
  row on the next reported event — nothing needs to fire at midnight, and
  state resolves correctly even if no job ever runs.
  
  UTC means one global rollover instant rather than one per player: a daily
  turns over at noon in New Zealand and mid-afternoon the day before on the US
  west coast. That is deliberate — everyone races the same clock — but it is
  why the API exposes the *remaining time* on a period and never a reset
  timestamp, and why clients should show a countdown rather than an hour.
  

  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the GameServer.
  """

  @type user_id() :: Ecto.UUID.t()

  @doc ~S"""
    All active quest definitions (cached — this backs event dispatch).
  """
  @spec active_quests() :: [GameServer.Quests.Quest.t()]
  def active_quests() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Quests.active_quests/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Claim on a user's behalf, skipping the `before_quest_claim` veto (admin).
  """
  @spec admin_claim(user_id(), String.t()) ::
  {:ok, %{progress: GameServer.Quests.QuestProgress.t(), rewards: [map()]}} | {:error, term()}
  def admin_claim(_user_id, _quest_key) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %{progress: %GameServer.Quests.QuestProgress{id: "", user_id: "", quest_key: "", period_key: "static", objective_progress: %{}, status: "active", completed_at: nil, claimed_at: nil, rewards_granted_at: nil, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}, rewards: []}}

      _ ->
        raise "GameServer.Quests.admin_claim/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Force-complete a quest for a user (admin grant): every objective jumps to
    its target and the normal completion side effects fire (hooks, auto-claim).
    
  """
  @spec admin_complete(user_id(), String.t()) ::
  {:ok, GameServer.Quests.QuestProgress.t()} | {:error, term()}
  def admin_complete(_user_id, _quest_key) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Quests.QuestProgress{id: "", user_id: "", quest_key: "", period_key: "static", objective_progress: %{}, status: "active", completed_at: nil, claimed_at: nil, rewards_granted_at: nil, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Quests.admin_complete/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Delete a user's current-period progress row for a quest (admin reset).
  """
  @spec admin_reset(user_id(), String.t()) ::
  {:ok, GameServer.Quests.QuestProgress.t() | :not_found} | {:error, term()}
  def admin_reset(_user_id, _quest_key) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Quests.admin_reset/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Every quest in `quest_key`'s prerequisite chain, in tier order, each with the
    user's current-period progress.
    
    The quest list hides a tier until its prerequisite is done; this is the one
    read that shows a whole chain — earlier tiers and the ones still ahead. Each
    entry carries `:tier` (1-based), `:locked` (prerequisite not yet done for
    this user) and the usual `:progress`/`:claimable`. With a `nil` user every
    tier after the first is locked and progress is `nil`.
    
    Returns `[]` for an unknown or inactive key. A quest with no chain links
    returns just its own entry.
    
  """
  @spec chain(user_id() | nil, String.t()) :: [
  %{
    quest: GameServer.Quests.Quest.t(),
    progress: GameServer.Quests.QuestProgress.t() | nil,
    claimable: boolean(),
    locked: boolean(),
    tier: pos_integer()
  }
]
  def chain(_user_id, _quest_key) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Quests.chain/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Returns a changeset for tracking quest changes (used by forms).
  """
  @spec change_quest(GameServer.Quests.Quest.t(), map()) :: Ecto.Changeset.t()
  def change_quest(_quest, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Quests.change_quest/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Claim a completed quest's rewards for the current period.
    
    Runs the `before_quest_claim` pipeline hook (veto), then transitions
    `completed → claimed` atomically — only the winner grants rewards.
    
    Returns `{:ok, %{progress: progress, rewards: rewards}}` or
    `{:error, :quest_not_found | :not_completed | :already_claimed | term()}`.
    
  """
  @spec claim(user_id(), String.t(), keyword()) ::
  {:ok, %{progress: GameServer.Quests.QuestProgress.t(), rewards: [map()]}} | {:error, term()}
  def claim(_user_id, _quest_key, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %{progress: %GameServer.Quests.QuestProgress{id: "", user_id: "", quest_key: "", period_key: "static", objective_progress: %{}, status: "active", completed_at: nil, claimed_at: nil, rewards_granted_at: nil, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}, rewards: []}}

      _ ->
        raise "GameServer.Quests.claim/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Number of completed-but-unclaimed quests for a user (badge count).
  """
  @spec claimable_count(user_id()) :: non_neg_integer()
  def claimable_count(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Quests.claimable_count/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count progress rows (same filters as `list_progress/1`).
  """
  @spec count_progress(keyword()) :: non_neg_integer()
  def count_progress(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Quests.count_progress/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count quest definitions (same filters as `list_quests/1`).
  """
  @spec count_quests(keyword()) :: non_neg_integer()
  def count_quests(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Quests.count_quests/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count of a user's completed quests (same filters as `list_user_completions/2`).
  """
  @spec count_user_completions(
  user_id(),
  keyword()
) :: non_neg_integer()
  def count_user_completions(_user_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Quests.count_user_completions/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count of quests visible to the user (same filters as `list_user_quests/2`).
  """
  @spec count_user_quests(
  user_id(),
  keyword()
) :: non_neg_integer()
  def count_user_quests(_user_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Quests.count_user_quests/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Creates a quest definition. Capped by the `max_quests` limit.
  """
  @spec create_quest(map()) :: {:ok, GameServer.Quests.Quest.t()} | {:error, term()}
  def create_quest(_attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Quests.Quest{id: "", key: "", title: "", description: "", icon_url: nil, sort_order: 0, hidden: false, kind: "achievement", objectives: [], rewards: [], auto_claim: false, prerequisite_quest_key: nil, starts_at: nil, ends_at: nil, active: true, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Quests.create_quest/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Quest statistics for the admin dashboard.
  """
  @spec dashboard_stats() :: map()
  def dashboard_stats() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "GameServer.Quests.dashboard_stats/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Deletes a quest definition and all related progress.
  """
  @spec delete_quest(GameServer.Quests.Quest.t()) ::
  {:ok, GameServer.Quests.Quest.t()} | {:error, Ecto.Changeset.t()}
  def delete_quest(_quest) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Quests.Quest{id: "", key: "", title: "", description: "", icon_url: nil, sort_order: 0, hidden: false, kind: "achievement", objectives: [], rewards: [], auto_claim: false, prerequisite_quest_key: nil, starts_at: nil, ends_at: nil, active: true, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Quests.delete_quest/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Per-status progress counts for one quest (admin completion funnel).
  """
  @spec funnel(String.t()) :: %{required(String.t()) => non_neg_integer()}
  def funnel(_quest_key) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Quests.funnel/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Get a user's progress row for a quest's current period.
  """
  @spec get_progress(user_id(), String.t()) :: GameServer.Quests.QuestProgress.t() | nil
  def get_progress(_user_id, _quest_key) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Quests.QuestProgress{id: "", user_id: "", quest_key: "", period_key: "static", objective_progress: %{}, status: "active", completed_at: nil, claimed_at: nil, rewards_granted_at: nil, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Quests.get_progress/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Get a quest by ID.
  """
  @spec get_quest(Ecto.UUID.t()) :: GameServer.Quests.Quest.t() | nil
  def get_quest(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Quests.Quest{id: "", key: "", title: "", description: "", icon_url: nil, sort_order: 0, hidden: false, kind: "achievement", objectives: [], rewards: [], auto_claim: false, prerequisite_quest_key: nil, starts_at: nil, ends_at: nil, active: true, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Quests.get_quest/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Get a quest by key.
  """
  @spec get_quest_by_key(String.t()) :: GameServer.Quests.Quest.t() | nil
  def get_quest_by_key(_key) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Quests.Quest{id: "", key: "", title: "", description: "", icon_url: nil, sort_order: 0, hidden: false, kind: "achievement", objectives: [], rewards: [], auto_claim: false, prerequisite_quest_key: nil, starts_at: nil, ends_at: nil, active: true, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Quests.get_quest_by_key/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Lists progress rows (admin viewer).
    
    ## Options
    - `:user_id` — exact UUID or username/display-name substring
    - `:quest_key`, `:status`
    - `:page` / `:page_size`
    
  """
  @spec list_progress(keyword()) :: [GameServer.Quests.QuestProgress.t()]
  def list_progress(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Quests.list_progress/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Lists quest definitions (admin view — no per-user state).
    
    ## Options
    - `:category` — filter by category
    - `:active` — filter by active flag
    - `:search` — substring match on key/title
    - `:page` / `:page_size`
    
  """
  @spec list_quests(keyword()) :: [GameServer.Quests.Quest.t()]
  def list_quests(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Quests.list_quests/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    A user's completed quests, newest first — the public-profile view
    ("their achievements"). Hidden quests appear once earned.
    
    ## Options
    - `:category` — filter by category (a profile typically wants `"achievement"`)
    - `:page` / `:page_size`
    
  """
  @spec list_user_completions(
  user_id(),
  keyword()
) :: [%{quest: GameServer.Quests.Quest.t(), progress: GameServer.Quests.QuestProgress.t()}]
  def list_user_completions(_user_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "GameServer.Quests.list_user_completions/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Lists quests as seen by one user: active definitions in-window with the
    user's current-period progress and a claimable flag.
    
    Hidden quests are listed but carry no details until earned (callers obscure
    them). Chain quests only appear once their prerequisite is met.
    
    ## Options
    - `:category` — filter by category
    - `:status` — `"in_progress"` (not yet completed), `"claimable"`
      (completed, waiting to be claimed) or `"done"` (completed or claimed)
    - `:page` / `:page_size`
    
  """
  @spec list_user_quests(
  user_id(),
  keyword()
) :: [
  %{
    quest: GameServer.Quests.Quest.t(),
    progress: GameServer.Quests.QuestProgress.t() | nil,
    claimable: boolean()
  }
]
  def list_user_quests(_user_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Quests.list_user_quests/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The reset bucket a quest is in at `now` (UTC).
    
    `"static"` when it never resets, else the current day (`"2026-07-22"`),
    ISO week (`"2026-W30"`), month (`"2026-07"`), or interval bucket
    (`"I14-1436"` — the 1436th 14-day window since the epoch). Derived purely
    from the clock, so a reset needs nothing to fire at midnight.
    
  """
  @spec period_key(GameServer.Quests.Quest.t() | String.t(), DateTime.t()) :: String.t()
  def period_key(_quest_or_reset, _now) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "GameServer.Quests.period_key/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    True when the quest's prerequisite (if any) is completed by the user.
  """
  @spec prerequisite_met?(user_id(), GameServer.Quests.Quest.t()) :: boolean()
  def prerequisite_met?(_user_id, _quest) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "GameServer.Quests.prerequisite_met?/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Deletes daily/weekly progress rows whose period ended more than
    `max_quest_period_history` days ago (called from `GameServer.Retention`).
    
  """
  @spec prune_old_periods() :: non_neg_integer()
  def prune_old_periods() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Quests.prune_old_periods/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Re-runs reward grants for rows that claimed but never finished granting
    (e.g. the process died mid-grant). Safe to run anywhere, any time — the
    per-entry idempotency keys dedupe. Pass `:user_id` to heal one user (done
    lazily when they list their quests). Returns the number of rows retried.
    
  """
  @spec recover_pending_rewards(keyword()) :: non_neg_integer()
  def recover_pending_rewards(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Quests.recover_pending_rewards/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Report a gameplay event for a user, advancing every matching active quest.
    
    `meta` narrows objective matching: an objective with `params` only advances
    when every param key/value is present in `meta`.
    
    Returns `{:ok, progress_rows}` for the quests that advanced.
    
  """
  @spec report_event(user_id(), String.t(), pos_integer(), map()) ::
  {:ok, [GameServer.Quests.QuestProgress.t()]}
  def report_event(_user_id, _event, _amount, _meta) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, []}

      _ ->
        raise "GameServer.Quests.report_event/4 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Subscribe to global quest events (definition changes, completions).
  """
  @spec subscribe_quests() :: :ok | {:error, term()}
  def subscribe_quests() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Quests.subscribe_quests/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Updates a quest definition.
  """
  @spec update_quest(GameServer.Quests.Quest.t(), map()) ::
  {:ok, GameServer.Quests.Quest.t()} | {:error, Ecto.Changeset.t()}
  def update_quest(_quest, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Quests.Quest{id: "", key: "", title: "", description: "", icon_url: nil, sort_order: 0, hidden: false, kind: "achievement", objectives: [], rewards: [], auto_claim: false, prerequisite_quest_key: nil, starts_at: nil, ends_at: nil, active: true, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Quests.update_quest/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The categories that actually have something behind them for this viewer.
    
    Derived from the same visibility rule as `list_user_quests/2` rather than
    from every definition: a chain's later tiers are hidden until unlocked, so
    listing their category gives a tab that opens onto nothing. Pass `nil` for
    the signed-out catalog.
    
  """
  @spec visible_categories(user_id() | nil) :: [String.t()]
  def visible_categories(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "GameServer.Quests.visible_categories/1 is a stub - only available at runtime on GameServer"
    end
  end

end
