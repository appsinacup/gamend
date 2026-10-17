defmodule GamendWeb.Api.V1.QuestController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Quests
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{QuestClaimResponse, QuestPage, QuestStatsResponse}
  alias OpenApiSpex.Schema

  tags(["Quests"])

  # ---------------------------------------------------------------------------
  # GET /api/v1/me/quests
  # ---------------------------------------------------------------------------

  operation(:me,
    operation_id: "my_quests",
    security: [%{"authorization" => []}],
    summary: "List my quests",
    description:
      "List active quests with the authenticated user's progress for the current " <>
        "reset period and a claimable flag. Hidden quests appear once completed; " <>
        "chain quests appear once their prerequisite is met. Grouped quests " <>
        "collapse to one entry carrying group_size; pass ?group=<key> to list " <>
        "that group's members instead.",
    parameters: [
      category: [in: :query, schema: %Schema{type: :string}, required: false],
      group: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: [
      ok: {"Quest list", "application/json", QuestPage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def me(conn, params) do
    case conn.assigns[:current_scope] do
      %{user_id: user_id} ->
        {page, page_size} = Pagination.params(params)
        category = category_filter(params)
        group = blank_filter(params, "group")
        opts = [page: page, page_size: page_size, category: category, group: group]

        %{entries: entries, total: total_count} = Quests.user_quest_page(user_id, opts)

        reply_page(conn, Enum.map(entries, &serialize_entry/1), page, page_size, total_count)

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/me/quests/:key/claim
  # ---------------------------------------------------------------------------

  operation(:claim,
    operation_id: "claim_quest",
    security: [%{"authorization" => []}],
    summary: "Claim a completed quest",
    description:
      "Claim the rewards of a completed quest for the current reset period. " <>
        "Claiming is exactly-once: a repeated or concurrent claim answers 409 " <>
        "`already_claimed` and never double-pays. A quest not yet completed answers " <>
        "403 `not_completed`; a guest, where the server requires an account to claim, " <>
        "403 `account_required` (the quest stays completed and pays once they " <>
        "register); a `before_quest_claim` hook's veto 403 `rejected`, its " <>
        "reason in `message`.",
    parameters: [
      key: [in: :path, schema: %Schema{type: :string}, required: true]
    ],
    responses: [
      ok: {"Claimed", "application/json", QuestClaimResponse},
      forbidden: Schemas.error("Not completed, a guest that must register, or vetoed by a hook"),
      not_found: Schemas.error("No quest with that key"),
      conflict: Schemas.error("Already claimed"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def claim(conn, %{"key" => key}) do
    case conn.assigns[:current_scope] do
      %{user_id: user_id} ->
        case Quests.claim(user_id, key) do
          {:ok, %{progress: progress, rewards: rewards}} ->
            reply_data(conn, %{
              progress: serialize_progress(progress),
              rewards: Enum.map(rewards, &serialize_reward/1)
            })

          {:error, :quest_not_found} ->
            reply_error(conn, :not_found, "not_found")

          {:error, :not_completed} ->
            reply_error(conn, :forbidden, "not_completed")

          {:error, :account_required} ->
            reply_error(conn, :forbidden, "account_required")

          {:error, :already_claimed} ->
            reply_error(conn, :conflict, "already_claimed")

          # Anything else is the `before_quest_claim` hook's veto, in its words.
          {:error, reason} ->
            message = if is_binary(reason), do: reason, else: inspect(reason)
            reply_error(conn, :forbidden, "rejected", message)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/quests (catalog, gated)
  # ---------------------------------------------------------------------------

  operation(:index,
    operation_id: "list_quests",
    security: [%{}, %{"authorization" => []}],
    summary: "List quests",
    description:
      "Public quest catalog: active, in-window quest definitions. If authenticated, " <>
        "includes user progress (same shape as /me/quests).",
    parameters: [
      category: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Quest list", "application/json", QuestPage}]
  )

  operation(:stats,
    operation_id: "quest_stats",
    summary: "Quest progress counts",
    description:
      "Aggregate quest progress. Public, and cached — treat the numbers as up to a minute old.",
    responses: [ok: {"Quest stats", "application/json", QuestStatsResponse}]
  )

  def stats(conn, _params), do: reply_data(conn, Quests.stats())

  def index(conn, params) do
    case conn.assigns[:current_scope] do
      %{user_id: _} ->
        me(conn, params)

      _ ->
        {page, page_size} = Pagination.params(params)
        now = DateTime.utc_now(:second)

        category = category_filter(params)

        visible =
          Quests.active_quests()
          |> Enum.filter(fn q ->
            within_window?(q, now) and category in [nil, q.category]
          end)

        entries =
          visible
          |> Enum.drop((page - 1) * page_size)
          |> Enum.take(page_size)
          |> Enum.map(fn quest -> %{quest: quest, progress: nil, claimable: false} end)

        reply_page(conn, Enum.map(entries, &serialize_entry/1), page, page_size, length(visible))
    end
  end

  # `?category=` decodes to "" rather than nil, and "" is nobody's category, so
  # the filter dropped every quest — a client asking for ALL categories got an
  # empty list back. Blank means no filter, the same as leaving the param off.
  defp category_filter(params), do: blank_filter(params, "category")

  defp blank_filter(params, name) do
    case params[name] do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end
  end

  defp within_window?(quest, now) do
    (is_nil(quest.starts_at) or DateTime.compare(quest.starts_at, now) != :gt) and
      (is_nil(quest.ends_at) or DateTime.compare(quest.ends_at, now) == :gt)
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/quests/user/:user_id (public completions, gated)
  # ---------------------------------------------------------------------------

  operation(:user_quests,
    operation_id: "user_quests",
    security: [%{}, %{"authorization" => []}],
    summary: "List a user's completed quests",
    description:
      "Publicly visible completions for a specific user, newest first — " <>
        "defaults to category \"achievement\" (the replacement for the old " <>
        "/achievements/user/:user_id endpoint). Hidden quests appear once earned.",
    parameters: [
      user_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true],
      category: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: [
      ok: {"Completed quests", "application/json", QuestPage},
      bad_request: Schemas.error("`user_id` is not a UUID (invalid_id)")
    ]
  )

  def user_quests(conn, %{"user_id" => user_id_str} = params) do
    case Ecto.UUID.cast(user_id_str) do
      {:ok, user_id} ->
        {page, page_size} = Pagination.params(params)
        category = category_filter(params) || "achievement"
        opts = [page: page, page_size: page_size, category: category]

        entries = Quests.list_user_completions(user_id, opts)
        total_count = Quests.count_user_completions(user_id, category: category)

        rows =
          Enum.map(entries, fn %{quest: quest, progress: progress} ->
            serialize_entry(%{quest: quest, progress: progress, claimable: false})
          end)

        reply_page(conn, rows, page, page_size, total_count)

      _ ->
        reply_error(conn, :bad_request, "invalid_id")
    end
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  defp serialize_entry(%{quest: quest} = entry) do
    entry
    |> serialize_quest()
    |> Map.put(:group_key, quest.group_key || "")
    |> Map.put(:group_title, quest.group_title || "")
    |> Map.put(:group_size, Map.get(entry, :group_size, 1))
  end

  defp serialize_quest(%{quest: quest, progress: progress, claimable: claimable}) do
    completed? = progress != nil and progress.status in ["completed", "claimed"]

    # The API ships the stored string, so a repeat quest's `%{n}` has to be
    # collapsed here. The web pages leave it in place until Gettext fills it,
    # which is why `resolve_counter/2` no longer does this for everyone.
    quest = Quests.render_counter(quest)

    base =
      if quest.hidden and not completed? do
        # Hidden + not completed: obscure all details
        %{
          id: quest.id,
          key: quest.key,
          title: "???",
          description: "???",
          icon_url: "",
          sort_order: quest.sort_order,
          hidden: true,
          reset: quest.reset,
          reset_interval_days: quest.reset_interval_days,
          category: quest.category || "",
          objectives: [],
          rewards: [],
          auto_claim: quest.auto_claim,
          prerequisite_quest_key: quest.prerequisite_quest_key || "",
          starts_at: quest.starts_at,
          ends_at: quest.ends_at,
          metadata: %{}
        }
      else
        %{
          id: quest.id,
          key: quest.key,
          title: quest.title,
          description: quest.description || "",
          icon_url: quest.icon_url || "",
          sort_order: quest.sort_order,
          hidden: quest.hidden,
          reset: quest.reset,
          reset_interval_days: quest.reset_interval_days,
          category: quest.category || "",
          objectives: Enum.map(quest.objectives, &serialize_objective/1),
          rewards: Enum.map(quest.rewards, &serialize_reward/1),
          auto_claim: quest.auto_claim,
          prerequisite_quest_key: quest.prerequisite_quest_key || "",
          starts_at: quest.starts_at,
          ends_at: quest.ends_at,
          metadata: quest.metadata || %{}
        }
      end

    Map.merge(base, %{progress: serialize_progress(progress), claimable: claimable})
  end

  defp serialize_objective(objective) do
    %{event: objective.event, target: objective.target, params: objective.params || %{}}
  end

  defp serialize_reward(reward) do
    %{type: reward.type, code: reward.code, amount: reward.amount}
  end

  defp serialize_progress(nil), do: nil

  defp serialize_progress(progress) do
    %{
      period_key: progress.period_key || "",
      objective_progress: progress.objective_progress || %{},
      status: progress.status,
      completed_at: progress.completed_at,
      claimed_at: progress.claimed_at,
      claim_count: progress.claim_count
    }
  end
end
