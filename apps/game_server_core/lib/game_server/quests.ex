defmodule GameServer.Quests do
  @moduledoc """
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
  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: GameServer.Cache

  require Logger

  alias GameServer.Accounts.User
  alias GameServer.Quests.Quest
  alias GameServer.Quests.QuestProgress
  alias GameServer.Repo

  @type user_id :: Ecto.UUID.t()

  @cache_ttl_ms 60_000

  # Grace before the recovery sweep retries a claimed-but-ungranted row, so it
  # can't race the post-commit grants of an in-flight claim.
  @reward_retry_grace_s 60

  @statuses_done ~w(completed claimed)

  # ---------------------------------------------------------------------------
  # Cache helpers
  # ---------------------------------------------------------------------------

  defp quests_version do
    GameServer.Cache.get!({:quests, :version}) || 1
  end

  defp invalidate_quests_cache do
    GameServer.Async.run(fn ->
      _ = GameServer.Cache.bump_version({:quests, :version})
      :ok
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @pubsub GameServer.PubSub

  @doc "Subscribe to global quest events (definition changes, completions)."
  @spec subscribe_quests() :: :ok | {:error, term()}
  def subscribe_quests do
    Phoenix.PubSub.subscribe(@pubsub, "quests")
  end

  defp broadcast_definition_change do
    invalidate_quests_cache()
    Phoenix.PubSub.broadcast(@pubsub, "quests", {:quests_changed})
  end

  # Progress ticks go to the user's topic only — a global fan-out of every
  # objective increment would scale with total event volume across all
  # players. Completions/claims are rare enough to broadcast globally.
  defp broadcast_progress(:quest_progress = event, user_id, payload) do
    Phoenix.PubSub.broadcast(@pubsub, "user:#{user_id}", {event, payload})
  end

  defp broadcast_progress(event, user_id, payload) do
    Phoenix.PubSub.broadcast(@pubsub, "user:#{user_id}", {event, payload})
    Phoenix.PubSub.broadcast(@pubsub, "quests", {event, user_id, payload})
  end

  # ---------------------------------------------------------------------------
  # Definition CRUD (admin)
  # ---------------------------------------------------------------------------

  @doc "Creates a quest definition. Capped by the `max_quests` limit."
  @spec create_quest(map()) :: {:ok, Quest.t()} | {:error, term()}
  def create_quest(attrs) do
    # An uncast embed inserts NULL (not []), so default rewards explicitly on
    # create. Updates must not do this — a missing key there means "keep".
    attrs = attrs |> normalize_params() |> Map.put_new("rewards", [])
    max = GameServer.Limits.get(:max_quests)

    result =
      GameServer.Lock.serialize(:quest, "definitions", fn ->
        if Repo.aggregate(Quest, :count) >= max do
          Repo.rollback(:quest_limit_reached)
        else
          case %Quest{} |> Quest.changeset(attrs) |> Repo.insert() do
            {:ok, quest} -> quest
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end
      end)

    case result do
      {:ok, quest} ->
        broadcast_definition_change()
        {:ok, quest}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Updates a quest definition."
  @spec update_quest(Quest.t(), map()) :: {:ok, Quest.t()} | {:error, Ecto.Changeset.t()}
  def update_quest(%Quest{} = quest, attrs) do
    attrs = normalize_params(attrs)

    case quest |> Quest.changeset(attrs) |> Repo.update() do
      {:ok, _} = result ->
        broadcast_definition_change()
        result

      error ->
        error
    end
  end

  @doc "Deletes a quest definition and all related progress."
  @spec delete_quest(Quest.t()) :: {:ok, Quest.t()} | {:error, Ecto.Changeset.t()}
  def delete_quest(%Quest{} = quest) do
    case Repo.delete(quest) do
      {:ok, _} = result ->
        broadcast_definition_change()
        result

      error ->
        error
    end
  end

  @doc "Get a quest by ID."
  @spec get_quest(Ecto.UUID.t()) :: Quest.t() | nil
  @decorate cacheable(
              key: {:quests, :get, quests_version(), id},
              match: &(&1 != nil),
              opts: [ttl: @cache_ttl_ms]
            )
  def get_quest(id), do: Repo.get_uuid(Quest, id)

  @doc "Get a quest by key."
  @spec get_quest_by_key(String.t()) :: Quest.t() | nil
  def get_quest_by_key(key) when is_binary(key) do
    Repo.get_by(Quest, key: key)
  end

  @doc "Returns a changeset for tracking quest changes (used by forms)."
  @spec change_quest(Quest.t(), map()) :: Ecto.Changeset.t()
  def change_quest(%Quest{} = quest, attrs \\ %{}) do
    Quest.changeset(quest, normalize_params(attrs))
  end

  @doc """
  Lists quest definitions (admin view — no per-user state).

  ## Options
  - `:category` — filter by category
  - `:active` — filter by active flag
  - `:search` — substring match on key/title
  - `:page` / `:page_size`
  """
  @spec list_quests(keyword()) :: [Quest.t()]
  def list_quests(opts \\ []) do
    quest_query(opts)
    |> order_by([q], asc: q.sort_order, asc: q.key)
    |> paginate(opts)
    |> Repo.all()
  end

  @doc "Count quest definitions (same filters as `list_quests/1`)."
  @spec count_quests(keyword()) :: non_neg_integer()
  def count_quests(opts \\ []) do
    Repo.aggregate(quest_query(opts), :count, :id)
  end

  defp quest_query(opts) do
    Quest
    |> maybe_filter_category(Keyword.get(opts, :category))
    |> maybe_filter_active(Keyword.get(opts, :active))
    |> maybe_search(Keyword.get(opts, :search))
  end

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, category), do: where(query, [q], q.category == ^category)

  defp maybe_filter_active(query, nil), do: query
  defp maybe_filter_active(query, active), do: where(query, [q], q.active == ^active)

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, term) do
    pattern = "%" <> Repo.escape_like(String.downcase(term)) <> "%"

    where(
      query,
      [q],
      fragment("lower(?) LIKE ? ESCAPE '\\'", q.key, ^pattern) or
        fragment("lower(?) LIKE ? ESCAPE '\\'", q.title, ^pattern)
    )
  end

  @doc "All active quest definitions (cached — this backs event dispatch)."
  @spec active_quests() :: [Quest.t()]
  @decorate cacheable(
              key: {:quests, :active_all, quests_version()},
              opts: [ttl: @cache_ttl_ms]
            )
  def active_quests do
    from(q in Quest, where: q.active == true, order_by: [asc: q.sort_order, asc: q.key])
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Event dispatch (the engine)
  # ---------------------------------------------------------------------------

  @doc """
  Report a gameplay event for a user, advancing every matching active quest.

  `meta` narrows objective matching: an objective with `params` only advances
  when every param key/value is present in `meta`.

  Returns `{:ok, progress_rows}` for the quests that advanced.
  """
  @spec report_event(user_id(), String.t(), pos_integer(), map()) ::
          {:ok, [QuestProgress.t()]}
  def report_event(user_id, event, amount \\ 1, meta \\ %{})
      when is_binary(user_id) and is_binary(event) and is_integer(amount) and amount > 0 and
             is_map(meta) do
    now = DateTime.utc_now(:second)
    meta = stringify_keys(meta)

    advanced =
      active_quests()
      |> Enum.filter(fn quest ->
        within_window?(quest, now) and quest_listens_to?(quest, event, meta) and
          not done_cached?(user_id, quest, now)
      end)
      |> filter_prerequisites_met(user_id)
      |> Enum.flat_map(fn quest ->
        case advance_quest(user_id, quest, event, amount, meta, now) do
          {:ok, %QuestProgress{} = progress} -> [progress]
          _ -> []
        end
      end)

    {:ok, advanced}
  end

  # One query for every prerequisite instead of one per quest. Snapshotted
  # before anything advances, so one event can't both complete a prerequisite
  # and advance its dependent chain.
  defp filter_prerequisites_met(quests, user_id) do
    done = done_prerequisites(user_id, Enum.map(quests, & &1.prerequisite_quest_key))

    Enum.filter(quests, fn quest ->
      is_nil(quest.prerequisite_quest_key) or quest.prerequisite_quest_key in done
    end)
  end

  defp done_prerequisites(user_id, keys) do
    keys = keys |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if keys == [] do
      MapSet.new()
    else
      from(p in QuestProgress,
        where: p.user_id == ^user_id and p.quest_key in ^keys and p.status in ^@statuses_done,
        select: p.quest_key
      )
      |> Repo.all()
      |> MapSet.new()
    end
  end

  # Once a period's row is completed/claimed it can never advance again, so
  # later events skip the advisory lock entirely via a cached marker. For
  # never-resetting quests (achievements) this makes the steady state free:
  # after the first post-completion no-op, events cost one L1 cache read.
  # Keyed by quests_version so definition changes drop all markers; admin
  # resets invalidate the specific key across nodes.
  @done_marker_ttl_ms :timer.hours(1)

  defp done_marker_key(user_id, quest, now) do
    {:quests, :done, quests_version(), user_id, quest.key, period_key(quest, now)}
  end

  defp done_cached?(user_id, quest, now) do
    GameServer.Cache.get!(done_marker_key(user_id, quest, now)) == true
  end

  defp mark_done(user_id, quest, now) do
    _ = GameServer.Cache.put(done_marker_key(user_id, quest, now), true, ttl: @done_marker_ttl_ms)
    :ok
  end

  defp quest_listens_to?(%Quest{objectives: objectives}, event, meta) do
    Enum.any?(objectives, &objective_matches?(&1, event, meta))
  end

  defp objective_matches?(objective, event, meta) do
    objective.event == event and params_match?(objective.params, meta)
  end

  defp params_match?(params, _meta) when params == %{} or is_nil(params), do: true

  defp params_match?(params, meta) do
    Enum.all?(params, fn {k, v} -> Map.get(meta, k) == v end)
  end

  defp within_window?(%Quest{starts_at: starts_at, ends_at: ends_at}, now) do
    (is_nil(starts_at) or DateTime.compare(starts_at, now) != :gt) and
      (is_nil(ends_at) or DateTime.compare(ends_at, now) == :gt)
  end

  # Advance one quest for one user under the per-(user, quest) advisory lock;
  # the objective merge is a read-modify-write. Side effects run after the
  # lock's transaction commits.
  defp advance_quest(user_id, quest, event, amount, meta, now) do
    result =
      GameServer.Lock.serialize(:quest, "#{user_id}:#{quest.key}", fn ->
        do_advance(user_id, quest, event, amount, meta, now)
      end)

    case result do
      {:ok, {:advanced, progress}} ->
        broadcast_progress(:quest_progress, user_id, progress)
        {:ok, progress}

      {:ok, {:completed, progress}} ->
        mark_done(user_id, quest, now)
        on_completed(user_id, quest, progress)
        {:ok, progress}

      {:ok, :done} ->
        mark_done(user_id, quest, now)
        :noop

      {:ok, :noop} ->
        :noop

      {:error, reason} ->
        Logger.warning("quest advance failed for #{quest.key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_advance(user_id, quest, event, amount, meta, now) do
    period_key = period_key(quest, now)

    progress =
      Repo.get_by(QuestProgress,
        user_id: user_id,
        quest_key: quest.key,
        period_key: period_key
      )

    case progress do
      nil ->
        if under_user_cap?(user_id, now) do
          insert_progress(user_id, quest, event, amount, meta, now, period_key)
        else
          :noop
        end

      %QuestProgress{status: "active"} = progress ->
        update_progress(progress, quest, event, amount, meta, now)

      %QuestProgress{} ->
        :done
    end
  end

  defp insert_progress(user_id, quest, event, amount, meta, now, period_key) do
    objective_progress = merge_objectives(%{}, quest, event, amount, meta)
    completed? = all_objectives_met?(objective_progress, quest)

    %QuestProgress{}
    |> QuestProgress.changeset(%{
      user_id: user_id,
      quest_key: quest.key,
      period_key: period_key,
      objective_progress: objective_progress,
      status: if(completed?, do: "completed", else: "active"),
      completed_at: if(completed?, do: now)
    })
    |> Repo.insert()
    |> case do
      {:ok, progress} -> {if(completed?, do: :completed, else: :advanced), progress}
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_progress(progress, quest, event, amount, meta, now) do
    objective_progress = merge_objectives(progress.objective_progress, quest, event, amount, meta)

    if objective_progress == progress.objective_progress do
      :noop
    else
      completed? = all_objectives_met?(objective_progress, quest)

      progress
      |> QuestProgress.changeset(%{
        objective_progress: objective_progress,
        status: if(completed?, do: "completed", else: "active"),
        completed_at: if(completed?, do: now)
      })
      |> Repo.update()
      |> case do
        {:ok, updated} -> {if(completed?, do: :completed, else: :advanced), updated}
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
  end

  defp merge_objectives(current, quest, event, amount, meta) do
    quest.objectives
    |> Enum.with_index()
    |> Enum.reduce(current, fn {objective, index}, acc ->
      if objective_matches?(objective, event, meta) do
        key = Integer.to_string(index)
        count = Map.get(acc, key, 0)
        Map.put(acc, key, min(objective.target, count + amount))
      else
        acc
      end
    end)
  end

  defp all_objectives_met?(objective_progress, quest) do
    quest.objectives
    |> Enum.with_index()
    |> Enum.all?(fn {objective, index} ->
      Map.get(objective_progress, Integer.to_string(index), 0) >= objective.target
    end)
  end

  @doc "True when the quest's prerequisite (if any) is completed by the user."
  @spec prerequisite_met?(user_id(), Quest.t()) :: boolean()
  def prerequisite_met?(_user_id, %Quest{prerequisite_quest_key: nil}), do: true

  def prerequisite_met?(user_id, %Quest{prerequisite_quest_key: prereq}) do
    Repo.exists?(
      from p in QuestProgress,
        where: p.user_id == ^user_id and p.quest_key == ^prereq and p.status in ^@statuses_done
    )
  end

  # Caps how many in-flight progress rows a user can hold in the *current*
  # periods; excess events are ignored rather than erroring.
  defp under_user_cap?(user_id, now) do
    max = GameServer.Limits.get(:max_active_quests_per_user)

    periods = current_period_keys(now)

    count =
      from(p in QuestProgress,
        where: p.user_id == ^user_id and p.status == "active" and p.period_key in ^periods
      )
      |> Repo.aggregate(:count)

    count < max
  end

  # ---------------------------------------------------------------------------
  # Completion side effects
  # ---------------------------------------------------------------------------

  defp on_completed(user_id, quest, progress) do
    broadcast_progress(:quest_completed, user_id, progress)
    send_completion_notification(user_id, quest)

    GameServer.Async.run(fn ->
      GameServer.Hooks.internal_call(:after_quest_completed, [progress])
    end)

    if quest.auto_claim do
      case do_claim(user_id, quest, skip_hooks: true) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("auto-claim failed for #{quest.key}: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp send_completion_notification(user_id, quest) do
    # The stored title is the fallback; the notifications UI re-titles by
    # type + metadata (quests categorised "achievement" keep that flavor).
    title =
      if quest.category == "achievement",
        do: "Achievement unlocked: #{quest.title}",
        else: "Quest completed: #{quest.title}"

    GameServer.Async.run(fn ->
      GameServer.Notifications.admin_create_notification(user_id, user_id, %{
        title: title,
        content: "",
        metadata: %{
          type: "quest_completed",
          quest_key: quest.key,
          category: quest.category,
          quest_title: quest.title
        }
      })
    end)
  end

  # ---------------------------------------------------------------------------
  # Claiming & rewards
  # ---------------------------------------------------------------------------

  @doc """
  Claim a completed quest's rewards for the current period.

  Runs the `before_quest_claim` pipeline hook (veto), then transitions
  `completed → claimed` atomically — only the winner grants rewards.

  Returns `{:ok, %{progress: progress, rewards: rewards}}` or
  `{:error, :quest_not_found | :not_completed | :already_claimed | term()}`.
  """
  @spec claim(user_id(), String.t(), keyword()) ::
          {:ok, %{progress: QuestProgress.t(), rewards: [map()]}} | {:error, term()}
  def claim(user_id, quest_key, opts \\ [])
      when is_binary(user_id) and is_binary(quest_key) do
    case get_quest_by_key(quest_key) do
      nil -> {:error, :quest_not_found}
      quest -> do_claim(user_id, quest, opts)
    end
  end

  defp do_claim(user_id, quest, opts) do
    now = DateTime.utc_now(:second)
    period_key = period_key(quest, now)

    progress =
      Repo.get_by(QuestProgress,
        user_id: user_id,
        quest_key: quest.key,
        period_key: period_key
      )

    with {:ok, progress} <- claimable(progress),
         :ok <- run_before_claim(user_id, quest, progress, opts),
         {:ok, progress} <- transition_to_claimed(progress, now) do
      rewards = grant_rewards(user_id, quest, progress)
      progress = Repo.get_uuid(QuestProgress, progress.id)

      broadcast_progress(:quest_claimed, user_id, progress)

      GameServer.Async.run(fn ->
        GameServer.Hooks.internal_call(:after_quest_claimed, [progress])
      end)

      {:ok, %{progress: progress, rewards: rewards}}
    end
  end

  defp claimable(nil), do: {:error, :not_completed}
  defp claimable(%QuestProgress{status: "active"}), do: {:error, :not_completed}
  defp claimable(%QuestProgress{status: "claimed"}), do: {:error, :already_claimed}
  defp claimable(%QuestProgress{status: "completed"} = progress), do: {:ok, progress}

  defp run_before_claim(user_id, quest, progress, opts) do
    if Keyword.get(opts, :skip_hooks, false) do
      :ok
    else
      case GameServer.Hooks.internal_call(:before_quest_claim, [user_id, quest, progress]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # The single conditional UPDATE is the exactly-once gate: only one caller
  # ever sees the completed → claimed transition succeed.
  defp transition_to_claimed(progress, now) do
    {count, _} =
      from(p in QuestProgress, where: p.id == ^progress.id and p.status == "completed")
      |> Repo.update_all(set: [status: "claimed", claimed_at: now, updated_at: now])

    case count do
      1 -> {:ok, %{progress | status: "claimed", claimed_at: now}}
      0 -> {:error, :already_claimed}
    end
  end

  # Grants run post-transition with per-entry idempotency keys; a partial
  # failure leaves rewards_granted_at unset so recovery can retry safely.
  defp grant_rewards(user_id, quest, progress) do
    results =
      quest.rewards
      |> Enum.with_index()
      |> Enum.map(fn {reward, index} ->
        key = "quest:#{progress.id}:#{index}"

        result =
          case reward.type do
            "currency" ->
              GameServer.Economy.grant(user_id, reward.code, reward.amount,
                reason: "quest_reward",
                idempotency_key: key
              )

            "item" ->
              GameServer.Inventory.grant_item(user_id, reward.code, reward.amount,
                reason: "quest_reward",
                idempotency_key: key
              )
          end

        {reward, result}
      end)

    failed =
      Enum.filter(results, fn
        {_reward, {:ok, _}} -> false
        {_reward, _} -> true
      end)

    if failed == [] do
      now = DateTime.utc_now(:second)

      from(p in QuestProgress, where: p.id == ^progress.id)
      |> Repo.update_all(set: [rewards_granted_at: now, updated_at: now])
    else
      Enum.each(failed, fn {reward, error} ->
        Logger.error(
          "quest reward grant failed (quest=#{quest.key} user=#{user_id} " <>
            "reward=#{reward.type}:#{reward.code}): #{inspect(error)}"
        )
      end)
    end

    Enum.map(results, fn {reward, _} -> reward end)
  end

  @doc """
  Re-runs reward grants for rows that claimed but never finished granting
  (e.g. the process died mid-grant). Safe to run anywhere, any time — the
  per-entry idempotency keys dedupe. Pass `:user_id` to heal one user (done
  lazily when they list their quests). Returns the number of rows retried.
  """
  @spec recover_pending_rewards(keyword()) :: non_neg_integer()
  def recover_pending_rewards(opts \\ []) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -@reward_retry_grace_s)

    query =
      from p in QuestProgress,
        where: p.status == "claimed" and is_nil(p.rewards_granted_at) and p.claimed_at < ^cutoff,
        limit: 100

    query =
      case Keyword.get(opts, :user_id) do
        nil -> query
        user_id -> where(query, [p], p.user_id == ^user_id)
      end

    rows = Repo.all(query)

    Enum.each(rows, fn progress ->
      case get_quest_by_key(progress.quest_key) do
        nil -> :ok
        quest -> grant_rewards(progress.user_id, quest, progress)
      end
    end)

    length(rows)
  end

  # ---------------------------------------------------------------------------
  # Player reads
  # ---------------------------------------------------------------------------

  @doc """
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
  @spec chain(user_id() | nil, String.t()) ::
          [
            %{
              quest: Quest.t(),
              progress: QuestProgress.t() | nil,
              claimable: boolean(),
              locked: boolean(),
              tier: pos_integer()
            }
          ]
  def chain(user_id, quest_key) when is_binary(quest_key) do
    quests = active_quests()
    prereq_by_key = Map.new(quests, &{&1.key, &1.prerequisite_quest_key})

    if Map.has_key?(prereq_by_key, quest_key) do
      root = walk_to_root(quest_key, prereq_by_key)

      members =
        quests
        |> Enum.filter(&(walk_to_root(&1.key, prereq_by_key) == root))
        |> Enum.sort_by(&chain_hops(&1.key, prereq_by_key, 0))

      now = DateTime.utc_now(:second)
      rows = chain_progress(user_id, members)

      done =
        for {{key, _period}, progress} <- rows,
            progress.status in @statuses_done,
            into: MapSet.new(),
            do: key

      members
      |> Enum.with_index(1)
      |> Enum.map(fn {quest, tier} ->
        progress = Map.get(rows, {quest.key, period_key(quest, now)})
        prereq = quest.prerequisite_quest_key

        %{
          quest: quest,
          progress: progress,
          claimable: progress != nil and progress.status == "completed",
          locked: prereq != nil and prereq not in done,
          tier: tier
        }
      end)
    else
      []
    end
  end

  # The chain's earlier tiers may sit in past periods for resetting quests, so
  # this reads each member's *current* period only — the same window the quest
  # list uses. `done_prerequisites/2` is deliberately not reused here: it spans
  # all periods, which is the unlock rule, and that distinction matters — a
  # tier can be unlocked (prereq done once, ever) while its own current-period
  # progress starts empty.
  defp chain_progress(nil, _members), do: %{}

  defp chain_progress(user_id, members) do
    keys = Enum.map(members, & &1.key)

    from(p in QuestProgress, where: p.user_id == ^user_id and p.quest_key in ^keys)
    |> Repo.all()
    |> Map.new(fn p -> {{p.quest_key, p.period_key}, p} end)
  end

  defp walk_to_root(key, prereq_by_key, hops \\ 0)
  defp walk_to_root(key, _prereq_by_key, hops) when hops >= 20, do: key

  defp walk_to_root(key, prereq_by_key, hops) do
    case Map.get(prereq_by_key, key) do
      nil -> key
      prereq -> walk_to_root(prereq, prereq_by_key, hops + 1)
    end
  end

  defp chain_hops(key, prereq_by_key, hops) when hops < 20 do
    case Map.get(prereq_by_key, key) do
      nil -> hops
      prereq -> chain_hops(prereq, prereq_by_key, hops + 1)
    end
  end

  defp chain_hops(_key, _prereq_by_key, hops), do: hops

  @doc """
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
  @spec list_user_quests(user_id(), keyword()) ::
          [%{quest: Quest.t(), progress: QuestProgress.t() | nil, claimable: boolean()}]
  def list_user_quests(user_id, opts \\ []) when is_binary(user_id) do
    _ = recover_pending_rewards(user_id: user_id)

    now = DateTime.utc_now(:second)

    visible = visible_quests(user_id, now, opts)

    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = min(max(Keyword.get(opts, :page_size, 25), 1), 200)

    visible
    |> Enum.drop((page - 1) * page_size)
    |> Enum.take(page_size)
  end

  @doc "Count of quests visible to the user (same filters as `list_user_quests/2`)."
  @spec count_user_quests(user_id(), keyword()) :: non_neg_integer()
  def count_user_quests(user_id, opts \\ []) when is_binary(user_id) do
    now = DateTime.utc_now(:second)
    length(visible_quests(user_id, now, opts))
  end

  @doc """
  The categories that actually have something behind them for this viewer.

  Derived from the same visibility rule as `list_user_quests/2` rather than
  from every definition: a chain's later tiers are hidden until unlocked, so
  listing their category gives a tab that opens onto nothing. Pass `nil` for
  the signed-out catalog.
  """
  @spec visible_categories(user_id() | nil) :: [String.t()]
  def visible_categories(user_id \\ nil)

  def visible_categories(nil) do
    now = DateTime.utc_now(:second)

    active_quests()
    |> Enum.filter(&(within_window?(&1, now) and is_nil(&1.prerequisite_quest_key)))
    |> category_names()
  end

  def visible_categories(user_id) when is_binary(user_id) do
    user_id
    |> visible_quests(DateTime.utc_now(:second), [])
    |> Enum.map(& &1.quest)
    |> category_names()
  end

  defp category_names(quests) do
    quests |> Enum.map(& &1.category) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
  end

  # Definitions are few (capped by max_quests) and cached, so visibility and
  # pagination are resolved in memory; the user's rows come from one query.
  defp visible_quests(user_id, now, opts) do
    category = Keyword.get(opts, :category)

    quests =
      Enum.filter(active_quests(), fn q ->
        within_window?(q, now) and category in [nil, q.category]
      end)

    keys = Enum.map(quests, & &1.key)
    periods = current_period_keys(now)

    rows =
      from(p in QuestProgress,
        where: p.user_id == ^user_id and p.quest_key in ^keys and p.period_key in ^periods
      )
      |> Repo.all()
      |> Map.new(fn p -> {{p.quest_key, p.period_key}, p} end)

    done_prereqs = done_prerequisites(user_id, Enum.map(quests, & &1.prerequisite_quest_key))
    status = Keyword.get(opts, :status)

    prereq_by_key = Map.new(quests, &{&1.key, &1.prerequisite_quest_key})

    quests
    |> Enum.map(fn quest ->
      progress = Map.get(rows, {quest.key, period_key(quest, now)})

      %{
        quest: quest,
        progress: progress,
        claimable: progress != nil and progress.status == "completed"
      }
    end)
    |> Enum.filter(fn %{quest: quest, progress: progress} ->
      visible_to_user?(quest, progress, done_prereqs)
    end)
    |> collapse_chains(prereq_by_key)
    |> Enum.filter(&matches_status?(&1, status))
  end

  # One entry per chain: the earliest tier the player can still act on — in
  # progress or completed-but-unclaimed. Only claiming advances the card to
  # the next tier; once every tier is claimed the final one stands for the
  # chain. Without this, a finished tier and its unlocked successor listed
  # side by side and the chain appeared twice.
  defp collapse_chains(entries, prereq_by_key) do
    representatives =
      entries
      |> Enum.group_by(fn %{quest: quest} -> walk_to_root(quest.key, prereq_by_key) end)
      |> Map.new(fn {root, group} ->
        ordered =
          Enum.sort_by(group, fn %{quest: quest} ->
            chain_hops(quest.key, prereq_by_key, 0)
          end)

        representative = Enum.find(ordered, &(not claimed_entry?(&1))) || List.last(ordered)
        {root, representative.quest.key}
      end)

    Enum.filter(entries, fn %{quest: quest} ->
      representatives[walk_to_root(quest.key, prereq_by_key)] == quest.key
    end)
  end

  defp claimed_entry?(%{progress: progress}),
    do: progress != nil and progress.status == "claimed"

  defp matches_status?(_entry, nil), do: true

  defp matches_status?(%{progress: progress}, "in_progress"),
    do: progress == nil or progress.status == "active"

  defp matches_status?(%{claimable: claimable}, "claimable"), do: claimable

  defp matches_status?(%{progress: progress}, "done"),
    do: progress != nil and progress.status in @statuses_done

  defp matches_status?(_entry, _status), do: true

  # Hidden quests are listed but obscured by the serializer until earned (the
  # same teaser behavior achievements had) — a locked prerequisite, by
  # contrast, hides the quest outright.
  defp visible_to_user?(quest, _progress, done_prereqs) do
    is_nil(quest.prerequisite_quest_key) or quest.prerequisite_quest_key in done_prereqs
  end

  @doc """
  A user's completed quests, newest first — the public-profile view
  ("their achievements"). Hidden quests appear once earned.

  ## Options
  - `:category` — filter by category (a profile typically wants `"achievement"`)
  - `:page` / `:page_size`
  """
  @spec list_user_completions(user_id(), keyword()) ::
          [%{quest: Quest.t(), progress: QuestProgress.t()}]
  def list_user_completions(user_id, opts \\ []) when is_binary(user_id) do
    completions_query(user_id, opts)
    |> order_by([p], desc: p.completed_at)
    |> paginate(opts)
    |> select([p, q], {p, q})
    |> Repo.all()
    |> Enum.map(fn {progress, quest} -> %{quest: quest, progress: progress} end)
  end

  @doc "Count of a user's completed quests (same filters as `list_user_completions/2`)."
  @spec count_user_completions(user_id(), keyword()) :: non_neg_integer()
  def count_user_completions(user_id, opts \\ []) when is_binary(user_id) do
    Repo.aggregate(completions_query(user_id, opts), :count)
  end

  defp completions_query(user_id, opts) do
    query =
      from p in QuestProgress,
        join: q in Quest,
        on: q.key == p.quest_key,
        where: p.user_id == ^user_id and p.status in ^@statuses_done and q.active == true

    case Keyword.get(opts, :category) do
      nil -> query
      category -> where(query, [p, q], q.category == ^category)
    end
  end

  @doc "Number of completed-but-unclaimed quests for a user (badge count)."
  @spec claimable_count(user_id()) :: non_neg_integer()
  def claimable_count(user_id) when is_binary(user_id) do
    from(p in QuestProgress,
      join: q in Quest,
      on: q.key == p.quest_key,
      where: p.user_id == ^user_id and p.status == "completed" and q.active == true
    )
    |> Repo.aggregate(:count)
  end

  @doc "Get a user's progress row for a quest's current period."
  @spec get_progress(user_id(), String.t()) :: QuestProgress.t() | nil
  def get_progress(user_id, quest_key)
      when is_binary(user_id) and is_binary(quest_key) do
    case get_quest_by_key(quest_key) do
      nil ->
        nil

      quest ->
        period_key = period_key(quest, DateTime.utc_now(:second))
        Repo.get_by(QuestProgress, user_id: user_id, quest_key: quest_key, period_key: period_key)
    end
  end

  # ---------------------------------------------------------------------------
  # Admin progress operations
  # ---------------------------------------------------------------------------

  @doc """
  Lists progress rows (admin viewer).

  ## Options
  - `:user_id` — exact UUID or username/display-name substring
  - `:quest_key`, `:status`
  - `:page` / `:page_size`
  """
  @spec list_progress(keyword()) :: [QuestProgress.t()]
  def list_progress(opts \\ []) do
    progress_query(opts)
    |> order_by([p], desc: p.updated_at, desc: p.id)
    |> paginate(opts)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Count progress rows (same filters as `list_progress/1`)."
  @spec count_progress(keyword()) :: non_neg_integer()
  def count_progress(opts \\ []) do
    Repo.aggregate(progress_query(opts), :count, :id)
  end

  defp progress_query(opts) do
    QuestProgress
    |> maybe_filter_user(Keyword.get(opts, :user_id))
    |> maybe_filter_quest_key(Keyword.get(opts, :quest_key))
    |> maybe_filter_status(Keyword.get(opts, :status))
  end

  defp maybe_filter_quest_key(query, nil), do: query
  defp maybe_filter_quest_key(query, key), do: where(query, [p], p.quest_key == ^key)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [p], p.status == ^status)

  # Accept either an exact user id (UUID) or a username/display-name substring.
  defp maybe_filter_user(query, nil), do: query

  defp maybe_filter_user(query, value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} ->
        where(query, [p], p.user_id == ^uuid)

      :error ->
        pattern = "%" <> Repo.escape_like(String.downcase(value)) <> "%"

        query
        |> join(:inner, [p], u in User, on: u.id == p.user_id)
        |> where(
          [p, u],
          fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.username, ^pattern) or
            fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.display_name, ^pattern)
        )
    end
  end

  @doc """
  Force-complete a quest for a user (admin grant): every objective jumps to
  its target and the normal completion side effects fire (hooks, auto-claim).
  """
  @spec admin_complete(user_id(), String.t()) ::
          {:ok, QuestProgress.t()} | {:error, term()}
  def admin_complete(user_id, quest_key)
      when is_binary(user_id) and is_binary(quest_key) do
    case get_quest_by_key(quest_key) do
      nil ->
        {:error, :quest_not_found}

      quest ->
        now = DateTime.utc_now(:second)
        period_key = period_key(quest, now)

        full =
          quest.objectives
          |> Enum.with_index()
          |> Map.new(fn {objective, index} -> {Integer.to_string(index), objective.target} end)

        result =
          GameServer.Lock.serialize(:quest, "#{user_id}:#{quest.key}", fn ->
            progress =
              Repo.get_by(QuestProgress,
                user_id: user_id,
                quest_key: quest.key,
                period_key: period_key
              )

            case progress do
              %QuestProgress{status: status} when status in @statuses_done ->
                Repo.rollback(:already_completed)

              %QuestProgress{} = progress ->
                progress
                |> QuestProgress.changeset(%{
                  objective_progress: full,
                  status: "completed",
                  completed_at: now
                })
                |> Repo.update()
                |> unwrap_or_rollback()

              nil ->
                %QuestProgress{}
                |> QuestProgress.changeset(%{
                  user_id: user_id,
                  quest_key: quest.key,
                  period_key: period_key,
                  objective_progress: full,
                  status: "completed",
                  completed_at: now
                })
                |> Repo.insert()
                |> unwrap_or_rollback()
            end
          end)

        case result do
          {:ok, progress} ->
            on_completed(user_id, quest, progress)
            {:ok, progress}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc "Delete a user's current-period progress row for a quest (admin reset)."
  @spec admin_reset(user_id(), String.t()) ::
          {:ok, QuestProgress.t() | :not_found} | {:error, term()}
  def admin_reset(user_id, quest_key)
      when is_binary(user_id) and is_binary(quest_key) do
    with %Quest{} = quest <- get_quest_by_key(quest_key),
         %QuestProgress{} = progress <- get_progress(user_id, quest_key),
         {:ok, deleted} <- Repo.delete(progress) do
      # The done marker would otherwise keep suppressing events for up to
      # its TTL; invalidate propagates the delete to every node's cache.
      GameServer.Cache.invalidate(done_marker_key(user_id, quest, DateTime.utc_now(:second)))
      {:ok, deleted}
    else
      nil -> {:ok, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Claim on a user's behalf, skipping the `before_quest_claim` veto (admin)."
  @spec admin_claim(user_id(), String.t()) ::
          {:ok, %{progress: QuestProgress.t(), rewards: [map()]}} | {:error, term()}
  def admin_claim(user_id, quest_key) do
    claim(user_id, quest_key, skip_hooks: true)
  end

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, changeset}), do: Repo.rollback(changeset)

  # ---------------------------------------------------------------------------
  # Retention & stats
  # ---------------------------------------------------------------------------

  @doc """
  Deletes daily/weekly progress rows whose period ended more than
  `max_quest_period_history` days ago (called from `GameServer.Retention`).
  """
  @spec prune_old_periods() :: non_neg_integer()
  def prune_old_periods do
    days = GameServer.Limits.get(:max_quest_period_history)
    cutoff = DateTime.add(DateTime.utc_now(:second), -days * 86_400)

    {count, _} =
      from(p in QuestProgress,
        where: p.period_key != "static" and p.inserted_at < ^cutoff
      )
      |> Repo.delete_all()

    count
  end

  @doc "Quest statistics for the admin dashboard."
  @spec dashboard_stats() :: map()
  def dashboard_stats do
    today_start = DateTime.utc_now(:second) |> DateTime.to_date() |> DateTime.new!(~T[00:00:00])

    completions_today =
      from(p in QuestProgress, where: p.completed_at >= ^today_start)
      |> Repo.aggregate(:count)

    claims_today =
      from(p in QuestProgress, where: p.claimed_at >= ^today_start)
      |> Repo.aggregate(:count)

    claimable_now =
      from(p in QuestProgress, where: p.status == "completed")
      |> Repo.aggregate(:count)

    %{
      definitions: Repo.aggregate(Quest, :count),
      active_definitions: from(q in Quest, where: q.active == true) |> Repo.aggregate(:count),
      completions_today: completions_today,
      claims_today: claims_today,
      claimable_now: claimable_now
    }
  end

  @doc "Per-status progress counts for one quest (admin completion funnel)."
  @spec funnel(String.t()) :: %{String.t() => non_neg_integer()}
  def funnel(quest_key) when is_binary(quest_key) do
    from(p in QuestProgress,
      where: p.quest_key == ^quest_key,
      group_by: p.status,
      select: {p.status, count(p.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Period keys
  # ---------------------------------------------------------------------------

  @doc """
  The reset bucket a quest is in at `now` (UTC).

  `"static"` when it never resets, else the current day (`"2026-07-22"`),
  ISO week (`"2026-W30"`), month (`"2026-07"`), or interval bucket
  (`"I14-1436"` — the 1436th 14-day window since the epoch). Derived purely
  from the clock, so a reset needs nothing to fire at midnight.
  """
  @spec period_key(Quest.t() | String.t(), DateTime.t()) :: String.t()
  def period_key(quest_or_reset, now)

  def period_key(%Quest{reset: "interval", reset_interval_days: days}, now)
      when is_integer(days) and days > 0 do
    "I#{days}-#{div(Date.diff(DateTime.to_date(now), ~D[1970-01-01]), days)}"
  end

  def period_key(%Quest{reset: reset}, now), do: period_key(reset, now)

  def period_key("daily", now), do: now |> DateTime.to_date() |> Date.to_iso8601()

  def period_key("weekly", now) do
    date = DateTime.to_date(now)
    {year, week} = :calendar.iso_week_number({date.year, date.month, date.day})

    "#{String.pad_leading(Integer.to_string(year), 4, "0")}-W#{String.pad_leading(Integer.to_string(week), 2, "0")}"
  end

  def period_key("monthly", now) do
    date = DateTime.to_date(now)
    "#{date.year}-#{String.pad_leading(Integer.to_string(date.month), 2, "0")}"
  end

  def period_key(_reset, _now), do: "static"

  # Every bucket the currently-active definitions can be in right now — used
  # to scope per-user progress queries without enumerating all resets.
  defp current_period_keys(now) do
    active_quests() |> Enum.map(&period_key(&1, now)) |> Enum.uniq() |> add_static()
  end

  defp add_static(keys), do: if("static" in keys, do: keys, else: ["static" | keys])

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp paginate(query, opts) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 25)
    query |> limit(^page_size) |> offset(^((page - 1) * page_size))
  end

  defp normalize_params(attrs) when is_map(attrs) do
    stringify_keys(attrs)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
