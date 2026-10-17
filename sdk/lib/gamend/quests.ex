defmodule Gamend.Quests do
  @moduledoc ~S"""
  Event-driven quest/progression engine.

  One engine, three independent dimensions: a **reset** cycle (never / daily /
  weekly / monthly / every N days / repeat-on-claim), an optional **window**
  (`starts_at`/`ends_at`), and an optional **prerequisite**
  (`prerequisite_quest_key`). Any combination works — a biweekly quest inside
  a seasonal window that also requires an earlier quest is just those three
  fields set. Rewards pay into `Gamend.Economy` / `Gamend.Inventory`
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
  the transition with a per-entry idempotency key (`"quest:<progress_id>:<i>"`,
  or `"quest:<progress_id>:<claim_count>:<i>"` once a `repeat` quest has been
  claimed before — the row alone would dedupe its own second payout),
  so a crashed or retried grant can't double-apply either; rows that claimed
  but never finished granting are healed by `recover_pending_rewards/1`.
  Quests with `auto_claim` grant immediately on completion (skipping the
  `before_quest_claim` hook — there is no player request to veto).

  **A finished run never expires.** A completed row waits for its claim
  whatever period it finished in: `claim/2` pays the oldest one first, the list
  shows that one until it is claimed and then the next, and the retention
  prune keeps completed rows. A daily finished three days running and never
  claimed is three claims, one after another.

  ## Resets

  `period_key` is derived from **UTC time** by the quest's reset (daily →
  `"2026-07-22"`, weekly → `"2026-W30"`, monthly → `"2026-07"`, interval →
  `"I14-1436"`, never → `"static"`). A new period simply means a new progress
  row on the next reported event — nothing needs to fire at midnight, and
  state resolves correctly even if no job ever runs.

  `repeat` is the exception: it has no clock at all. The row is re-armed the
  moment its reward is paid, so the quest is available again immediately and
  as often as the player can finish it — for an endless objective, a calendar
  reset would cap the payout at once per period. It reuses `"static"` as its
  period and counts claims on the row instead (see `claim_count`).

  A `repeat` row also **banks**: it keeps counting while it waits for its
  claim (its objective counts pass the target), and each target's worth is
  one claim. A claim takes one run's worth off every objective; the row stays
  completed while another run is left, so the next claim is ready at once.

  UTC means one global rollover instant rather than one per player: a daily
  turns over at noon in New Zealand and mid-afternoon the day before on the US
  west coast. That is the default — everyone races the same clock — but it is
  why the API exposes the *remaining time* on a period and never a reset
  timestamp, and why clients should show a countdown rather than an hour.

  `config :gamend_core, :quest_clock, :player` reads each player's periods on
  their own clock instead: a daily turns over at their midnight, a weekly at
  their Monday's, from the time zone in their preferences
  (`Gamend.Accounts.TimeZone`; UTC when unknown). Only the period moves:
  windows and every timestamp stay UTC. A player whose zone changes mid-day
  may land on a period already played or one not yet started, once.


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @type user_id() :: Ecto.UUID.t()

  @doc ~S"""
    All active quest definitions (cached — this backs event dispatch).
  """
  @spec active_quests() :: [Gamend.Quests.Quest.t()]
  def active_quests() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Quests.active_quests/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The active quests with an objective listening to `event`.
    
    `report_event/4` is the hottest write a player makes, and it used to scan
    every active quest to find the handful that care. That is linear in the size
    of the whole catalogue, so a host that adds a large family of quests — one
    per language, say — pays for all of them on every unrelated event.
    
    Cached **per event**, not as one grouped map. Nebulex copies a value out on
    read, so a single map of every event's quests would copy the entire
    catalogue on every lookup, which is the cost this exists to remove. One key
    per event copies only the quests that event can advance.
    
    Both keys carry `quests_version/0`, so creating, updating or deleting a
    definition drops these along with `active_quests/0`.
    
  """
  @spec active_quests_for_event(String.t()) :: [Gamend.Quests.Quest.t()]
  def active_quests_for_event(_event) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Quests.active_quests_for_event/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Claim on a user's behalf, skipping the `before_quest_claim` veto (admin).
  """
  @spec admin_claim(user_id(), String.t()) ::
          {:ok, %{progress: Gamend.Quests.QuestProgress.t(), rewards: [map()]}} | {:error, term()}
  def admin_claim(_user_id, _quest_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %{
           progress: %Gamend.Quests.QuestProgress{
             id: "",
             user_id: "",
             quest_key: "",
             period_key: "static",
             objective_progress: %{},
             status: "active",
             completed_at: nil,
             claimed_at: nil,
             rewards_granted_at: nil,
             metadata: %{},
             inserted_at: ~U[1970-01-01 00:00:00Z],
             updated_at: ~U[1970-01-01 00:00:00Z]
           },
           rewards: []
         }}

      _ ->
        raise "Gamend.Quests.admin_claim/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Force-complete a quest for a user (admin grant): every objective jumps to
    its target and the normal completion side effects fire (hooks, auto-claim).
    
  """
  @spec admin_complete(user_id(), String.t()) ::
          {:ok, Gamend.Quests.QuestProgress.t()} | {:error, term()}
  def admin_complete(_user_id, _quest_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Quests.QuestProgress{
           id: "",
           user_id: "",
           quest_key: "",
           period_key: "static",
           objective_progress: %{},
           status: "active",
           completed_at: nil,
           claimed_at: nil,
           rewards_granted_at: nil,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Quests.admin_complete/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete a user's current-period progress row for a quest (admin reset).
  """
  @spec admin_reset(user_id(), String.t()) ::
          {:ok, Gamend.Quests.QuestProgress.t() | :not_found} | {:error, term()}
  def admin_reset(_user_id, _quest_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Quests.admin_reset/2 is a stub - only available at runtime on Gamend"
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
            quest: Gamend.Quests.Quest.t(),
            progress: Gamend.Quests.QuestProgress.t() | nil,
            claimable: boolean(),
            locked: boolean(),
            tier: pos_integer()
          }
        ]
  def chain(_user_id, _quest_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Quests.chain/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns a changeset for tracking quest changes (used by forms).
  """
  @spec change_quest(Gamend.Quests.Quest.t(), map()) :: Ecto.Changeset.t()
  def change_quest(_quest, _attrs \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Quests.change_quest/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Claim a completed quest's rewards: its oldest finished run still waiting,
    whatever period it finished in, so claiming again pays the next one.
    
    Runs the `before_quest_claim` pipeline hook (veto), then transitions
    `completed → claimed` atomically — only the winner grants rewards.
    
    A guest is refused with `:account_required` when the host requires an
    account to claim (`Gamend.AccountRequired`, `:quest_claims`); the quest
    stays completed and pays once they register.
    
    Returns `{:ok, %{progress: progress, rewards: rewards}}` or
    `{:error, :quest_not_found | :account_required | :not_completed |
    :already_claimed | term()}`.
    
  """
  @spec claim(user_id(), String.t(), keyword()) ::
          {:ok, %{progress: Gamend.Quests.QuestProgress.t(), rewards: [map()]}} | {:error, term()}
  def claim(_user_id, _quest_key, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %{
           progress: %Gamend.Quests.QuestProgress{
             id: "",
             user_id: "",
             quest_key: "",
             period_key: "static",
             objective_progress: %{},
             status: "active",
             completed_at: nil,
             claimed_at: nil,
             rewards_granted_at: nil,
             metadata: %{},
             inserted_at: ~U[1970-01-01 00:00:00Z],
             updated_at: ~U[1970-01-01 00:00:00Z]
           },
           rewards: []
         }}

      _ ->
        raise "Gamend.Quests.claim/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Claims waiting for a user (badge count): every finished run of an active
    quest not yet claimed, whatever period it finished in, and each run a
    `repeat` row banked.
    
  """
  @spec claimable_count(user_id()) :: non_neg_integer()
  def claimable_count(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Quests.claimable_count/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count progress rows (same filters as `list_progress/1`).
  """
  @spec count_progress(keyword()) :: non_neg_integer()
  def count_progress(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Quests.count_progress/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count quest definitions (same filters as `list_quests/1`).
  """
  @spec count_quests(keyword()) :: non_neg_integer()
  def count_quests(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Quests.count_quests/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count of a user's completed quests (same filters as `list_user_completions/2`).
  """
  @spec count_user_completions(
          user_id(),
          keyword()
        ) :: non_neg_integer()
  def count_user_completions(_user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Quests.count_user_completions/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count of quests visible to the user (same filters as `list_user_quests/2`).
  """
  @spec count_user_quests(
          user_id(),
          keyword()
        ) :: non_neg_integer()
  def count_user_quests(_user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Quests.count_user_quests/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The number `%{n}` stands for: the resolved counter, else the first run's
    (`counter_start`, or 1). An unresolved counter is the anonymous catalog,
    which pairs no row: the run a visitor would start.
    
  """
  @spec counter(Gamend.Quests.Quest.t()) :: integer()
  def counter(_quest) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Quests.counter/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Creates a quest definition. Capped by the `max_quests` limit.
  """
  @spec create_quest(map()) :: {:ok, Gamend.Quests.Quest.t()} | {:error, term()}
  def create_quest(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Quests.Quest{
           id: "",
           key: "",
           title: "",
           description: "",
           icon_url: nil,
           sort_order: 0,
           hidden: false,
           kind: "achievement",
           objectives: [],
           rewards: [],
           auto_claim: false,
           prerequisite_quest_key: nil,
           starts_at: nil,
           ends_at: nil,
           active: true,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Quests.create_quest/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Quest statistics for the admin dashboard.
  """
  @spec dashboard_stats() :: map()
  def dashboard_stats() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Quests.dashboard_stats/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Deletes a quest definition and all related progress.
  """
  @spec delete_quest(Gamend.Quests.Quest.t()) ::
          {:ok, Gamend.Quests.Quest.t()} | {:error, Ecto.Changeset.t()}
  def delete_quest(_quest) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Quests.Quest{
           id: "",
           key: "",
           title: "",
           description: "",
           icon_url: nil,
           sort_order: 0,
           hidden: false,
           kind: "achievement",
           objectives: [],
           rewards: [],
           auto_claim: false,
           prerequisite_quest_key: nil,
           starts_at: nil,
           ends_at: nil,
           active: true,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Quests.delete_quest/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Per-status progress counts for one quest (admin completion funnel).
  """
  @spec funnel(String.t()) :: %{required(String.t()) => non_neg_integer()}
  def funnel(_quest_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Quests.funnel/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a user's progress row for a quest's current period.
  """
  @spec get_progress(user_id(), String.t()) :: Gamend.Quests.QuestProgress.t() | nil
  def get_progress(_user_id, _quest_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Quests.QuestProgress{
            id: "",
            user_id: "",
            quest_key: "",
            period_key: "static",
            objective_progress: %{},
            status: "active",
            completed_at: nil,
            claimed_at: nil,
            rewards_granted_at: nil,
            metadata: %{},
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Quests.get_progress/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a quest by ID.
  """
  @spec get_quest(Ecto.UUID.t()) :: Gamend.Quests.Quest.t() | nil
  def get_quest(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Quests.Quest{
            id: "",
            key: "",
            title: "",
            description: "",
            icon_url: nil,
            sort_order: 0,
            hidden: false,
            kind: "achievement",
            objectives: [],
            rewards: [],
            auto_claim: false,
            prerequisite_quest_key: nil,
            starts_at: nil,
            ends_at: nil,
            active: true,
            metadata: %{},
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Quests.get_quest/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a quest by key.
  """
  @spec get_quest_by_key(String.t()) :: Gamend.Quests.Quest.t() | nil
  def get_quest_by_key(_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Quests.Quest{
            id: "",
            key: "",
            title: "",
            description: "",
            icon_url: nil,
            sort_order: 0,
            hidden: false,
            kind: "achievement",
            objectives: [],
            rewards: [],
            auto_claim: false,
            prerequisite_quest_key: nil,
            starts_at: nil,
            ends_at: nil,
            active: true,
            metadata: %{},
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Quests.get_quest_by_key/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Every member of a group, with the viewer's progress — what a UI shows when the
    player opens the one entry the group collapsed into.
    
    Ordered by `sort_order` like any list; a group has no tiers, so unlike
    `chain/2` there is nothing locked and nothing to number. Members the quest
    list would not show this viewer (out of window, prerequisite unmet) are left
    out too, so the count on the collapsed entry matches what opening it reveals.
    
    Returns `[]` for a group key nothing carries.
    
  """
  @spec group(user_id() | nil, String.t()) :: [
          %{
            quest: Gamend.Quests.Quest.t(),
            progress: Gamend.Quests.QuestProgress.t() | nil,
            claimable: boolean()
          }
        ]
  def group(_user_id, _group_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Quests.group/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The groups this viewer's quests fall into, as `%{key, title}` in the order
    the list would show them — what a group selector offers. `title` is the
    stored `group_title` (the first member's when they disagree), untranslated,
    like every other stored string here. `category` narrows it the way the list
    filter does; `nil` is the signed-out catalog.
    
  """
  @spec groups(user_id() | nil, String.t() | nil) :: [%{key: String.t(), title: String.t()}]
  def groups(_user_id, _category \\ nil) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Quests.groups/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Where this viewer goes to work on this quest, as a path on this site — or
    `nil`. Set `config :gamend_core, :quest_action, {Module, :function}`; it is
    called as `function(user_id | nil, Quest.t())`.
    
    The quests page makes the whole card a link to it whenever there is nothing
    to claim: before the quest is done, the way to do it, and after it is
    claimed, the way back to more of it. A quest only says what to do ("Visit
    20 cities"), never where, and only the host knows its own pages.
    
    A path starts with one `/` (`"/games"`); a URL or `"//…"` is dropped. The
    page keeps the reader's locale prefix on it.
    
  """
  @spec host_action(Gamend.Quests.Quest.t(), user_id() | nil) :: String.t() | nil
  def host_action(_quest, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Quests.host_action/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Why this viewer cannot claim this quest yet, as a short label to draw — or
    `nil` when they can. Set `config :gamend_core, :quest_lock_filter,
    {Module, :function}`; it is called as `function(user_id | nil, Quest.t())`.
    
    The display counterpart of `before_quest_claim`. A quest can be worth showing
    and still not claimable — a premium tier a player has not bought is an offer,
    and hiding it means only the people who already took the offer ever see it.
    `host_visible/2` cannot express that: it keeps a quest or drops it, and
    `hidden` is a column, the same for everyone, that draws "???" over the very
    title the offer is made of.
    
    A label here changes nothing about what pays: the veto in `before_quest_claim`
    is still the authority, and a lock filter that disagrees with it only makes
    the page lie. Return the reason from the same condition the veto tests.
    
  """
  @spec host_lock_label(Gamend.Quests.Quest.t(), user_id() | nil) :: String.t() | nil
  def host_lock_label(_quest, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Quests.host_lock_label/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The host's say on which quest definitions one viewer may see at all — a
    premium-only daily, a quest for a country the player has not unlocked. Set
    `config :gamend_core, :quest_visibility_filter, {Module, :function}`; it is
    called as `function(user_id | nil, [Quest.t()])` and returns the quests to
    keep. Applied to every per-user listing (`list_user_quests/2`,
    `count_user_quests/2`, `visible_categories/1`) and to the signed-out catalog
    with `nil`. Progress is NOT filtered: an event still advances a quest the
    viewer cannot see, so a player who gains access later finds it where they
    left it; veto the claim in `before_quest_claim` if that must not pay.
    
  """
  @spec host_visible([Gamend.Quests.Quest.t()], user_id() | nil) :: [Gamend.Quests.Quest.t()]
  def host_visible(_quests, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Quests.host_visible/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists progress rows (admin viewer).
    
    ## Options
    - `:user_id` — exact UUID or username/display-name substring
    - `:quest_key`, `:status`
    - `:page` / `:page_size`
    
  """
  @spec list_progress(keyword()) :: [Gamend.Quests.QuestProgress.t()]
  def list_progress(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Quests.list_progress/1 is a stub - only available at runtime on Gamend"
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
  @spec list_quests(keyword()) :: [Gamend.Quests.Quest.t()]
  def list_quests(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Quests.list_quests/1 is a stub - only available at runtime on Gamend"
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
        ) :: [%{quest: Gamend.Quests.Quest.t(), progress: Gamend.Quests.QuestProgress.t()}]
  def list_user_completions(_user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Quests.list_user_completions/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists quests as seen by one user: active definitions in-window with the
    user's current-period progress and a claimable flag.
    
    Hidden quests are listed but carry no details until earned (callers obscure
    them). Chain quests only appear once their prerequisite is met. Grouped
    quests collapse to one entry carrying `:group_size` and `collapsed: true`;
    the members of a group listed in full carry the size alone.
    
    ## Options
    - `:category` — filter by category
    - `:group` — expand this one group's members; every other group stays
      collapsed
    - `:drop_groups` — group keys to leave out entirely, collapsed or not: what
      a page with a selector over some groups does with the ones not picked
    - `:status` — `"in_progress"` (not yet completed), `"claimable"`
      (completed, waiting to be claimed) or `"done"` (completed or claimed)
    - `:page` / `:page_size`
    
  """
  @spec list_user_quests(
          user_id(),
          keyword()
        ) :: [
          %{
            quest: Gamend.Quests.Quest.t(),
            progress: Gamend.Quests.QuestProgress.t() | nil,
            claimable: boolean()
          }
        ]
  def list_user_quests(_user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Quests.list_user_quests/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The reset bucket a quest is in at `now`, on the date `now` carries (UTC,
    or a player's own zone with `:quest_clock` `:player`; see "Resets").
    
    `"static"` when it never resets, else the current day (`"2026-07-22"`),
    ISO week (`"2026-W30"`), month (`"2026-07"`), or interval bucket
    (`"I14-1436"` — the 1436th 14-day window since the epoch). Derived purely
    from the clock, so a reset needs nothing to fire at midnight.
    
  """
  @spec period_key(Gamend.Quests.Quest.t() | String.t(), DateTime.t()) :: String.t()
  def period_key(_quest_or_reset, _now) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "Gamend.Quests.period_key/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    True when the quest's prerequisite (if any) is completed by the user.
  """
  @spec prerequisite_met?(user_id(), Gamend.Quests.Quest.t()) :: boolean()
  def prerequisite_met?(_user_id, _quest) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Quests.prerequisite_met?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Deletes daily/weekly progress rows whose period ended more than
    `max_quest_period_history` days ago (called from `Gamend.Retention`).
    A completed row stays until it is claimed: a finished run never expires.
    
  """
  @spec prune_old_periods() :: non_neg_integer()
  def prune_old_periods() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Quests.prune_old_periods/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Re-open `repeat` quests whose reward was paid but which never re-armed.
    
    Only reachable by crashing between the grant and the re-arm. Healing on read
    keeps that window from stranding a player on a quest that will never come
    back, without a job that has to be running for the feature to work.
    
  """
  @spec rearm_repeat_quests(keyword()) :: non_neg_integer()
  def rearm_repeat_quests(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Quests.rearm_repeat_quests/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Re-runs reward grants for rows that claimed but never finished granting
    (e.g. the process died mid-grant). Safe to run anywhere, any time — the
    per-entry idempotency keys dedupe. Pass `:user_id` to heal one user (done
    lazily when they list their quests). Returns the number of rows retried.
    
  """
  @spec recover_pending_rewards(keyword()) :: non_neg_integer()
  def recover_pending_rewards(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Quests.recover_pending_rewards/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The quest with `%{n}` replaced by its resolved counter, untranslated.
    
    For consumers that emit the stored string as-is. Anything that translates
    interpolates through Gettext instead, so the placeholder survives long
    enough to be looked up. An unresolved counter reads as the first run
    (`counter/1`).
    
  """
  @spec render_counter(Gamend.Quests.Quest.t()) :: Gamend.Quests.Quest.t()
  def render_counter(_quest) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Quests.render_counter/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Report a gameplay event for a user, advancing every matching active quest.
    
    `meta` narrows objective matching: an objective with `params` only advances
    when every param key/value is present in `meta`.
    
    Returns `{:ok, progress_rows}` for the quests that advanced.
    
  """
  @spec report_event(user_id(), String.t(), pos_integer(), map()) ::
          {:ok, [Gamend.Quests.QuestProgress.t()]}
  def report_event(_user_id, _event, _amount \\ 1, _meta \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, []}

      _ ->
        raise "Gamend.Quests.report_event/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Works out which run of a `repeat` quest a player is on, into `:counter`.
    
    A repeat quest is one definition and one row that re-arms forever, so it has
    no natural way to say *which* run the player is on — the card reads the same
    the tenth time as the first. `"Treasures x %{n}"` renders "Treasures x 1"
    before the first claim and "Treasures x 2" after it.
    
    Resolved here, at the point a definition is paired with a player's row,
    because the definition is global and the count is not: writing the number
    into the stored title would show every player the same one.
    
    The number lands on the virtual `:counter` field and `%{n}` stays in the
    title, because the title is also a **msgid**: `GamendWeb.ContentText` looks
    the translation up by it and hands `n` to Gettext as a binding, so a German
    card reads "Schätze x 3" instead of falling back to English. Filling it in
    here would leave "Treasures x 3", which matches no msgid in any locale.
    Callers that render the title without translating it — the JSON API — call
    `render_counter/1` to collapse the placeholder.
    
    Non-repeat quests and titles without the placeholder pass through untouched,
    so this is invisible to everything that does not opt in.
    
    ## Counting from somewhere else
    
    `metadata["counter_start"]` and `metadata["counter_step"]` (both default 1)
    turn the run into a number: run `r` reads `start + step * (r - 1)`. A
    ladder that pays every 50 wins after 100 says "Wins × 150", "Wins × 200"
    with `start: 150, step: 50`. A non-repeat quest has one run, so its `%{n}`
    is its `counter_start` (`counter/1`): every step of a chain can share one
    title, "Wins × %{n}", and one msgid with it.
    
  """
  @spec resolve_counter(Gamend.Quests.Quest.t(), Gamend.Quests.QuestProgress.t() | nil) ::
          Gamend.Quests.Quest.t()
  def resolve_counter(_quest, _progress) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Quests.resolve_counter/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Aggregate quest progress counts for the public stats endpoint.
    
    Grouped by status in one query — `quest_progress` carries a partial index on
    completed rows, and the group-by reads the same rows the listing already does.
    
  """
  @spec stats() :: %{
          quests_total: non_neg_integer(),
          completed: non_neg_integer(),
          claimed: non_neg_integer()
        }
  def stats() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Quests.stats/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to global quest events (definition changes, completions).
  """
  @spec subscribe_quests() :: :ok | {:error, term()}
  def subscribe_quests() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Quests.subscribe_quests/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Updates a quest definition.
  """
  @spec update_quest(Gamend.Quests.Quest.t(), map()) ::
          {:ok, Gamend.Quests.Quest.t()} | {:error, Ecto.Changeset.t()}
  def update_quest(_quest, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Quests.Quest{
           id: "",
           key: "",
           title: "",
           description: "",
           icon_url: nil,
           sort_order: 0,
           hidden: false,
           kind: "achievement",
           objectives: [],
           rewards: [],
           auto_claim: false,
           prerequisite_quest_key: nil,
           starts_at: nil,
           ends_at: nil,
           active: true,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Quests.update_quest/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    What a quest page draws, from one read of the user's progress: `:entries`,
    the page `list_user_quests/2` returns for these `opts`; `:total`, what
    `count_user_quests/2` counts for them; `:categories`, what
    `visible_categories/1` lists (the tabs, so every filter but none). The three
    separately read the same rows three times.
    
  """
  @spec user_quest_page(
          user_id(),
          keyword()
        ) :: %{
          entries: [
            %{
              quest: Gamend.Quests.Quest.t(),
              progress: Gamend.Quests.QuestProgress.t() | nil,
              claimable: boolean()
            }
          ],
          total: non_neg_integer(),
          categories: [String.t()]
        }
  def user_quest_page(_user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Quests.user_quest_page/2 is a stub - only available at runtime on Gamend"
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
  def visible_categories(_user_id \\ nil) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Quests.visible_categories/1 is a stub - only available at runtime on Gamend"
    end
  end
end
