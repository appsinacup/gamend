defmodule Gamend.Chat.Reports do
  @moduledoc """
  The chat report queue.

  Players report a message through `report_message/3`; the word filter files its
  own reports (with `reporter_id` nil) when a `flag` word matches. Moderators
  work the queue from the admin console via `list_reports/2` and
  `resolve_report/3`.

  Reports keep a denormalized `reported_user_id` and `content_snapshot`, so the
  queue still makes sense after the message itself is deleted.
  """

  import Ecto.Query

  alias Gamend.Chat.Message
  alias Gamend.Chat.Moderation.Notices
  alias Gamend.Chat.Report
  alias Gamend.Lock
  alias Gamend.Repo

  @doc """
  File a report about `message_id` on behalf of `reporter_id`.

  Returns `{:error, :not_found}` for an unknown message, `{:error, :own_message}`
  when a player reports themselves, `{:error, :already_reported}` when they have
  already reported that message, and `{:error, :report_daily_limit}` once they
  are over `max_chat_reports_per_user_per_day`.

  The daily cap is enforced here rather than only at the HTTP edge so that a
  plugin calling this directly is bounded too. The edge keeps its own rate-limit
  check: that one is a cheap in-memory gate, while this counts committed rows,
  so it survives a restart and is shared by every instance. Either can reject.
  """
  @spec report_message(Ecto.UUID.t(), Ecto.UUID.t(), String.t() | nil) ::
          {:ok, Report.t()} | {:error, term()}
  def report_message(reporter_id, message_id, reason \\ nil) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      %Message{sender_id: ^reporter_id} ->
        {:error, :own_message}

      %Message{} = message ->
        attrs = %{
          "reporter_id" => reporter_id,
          "message_id" => message.id,
          "reported_user_id" => message.sender_id,
          "content_snapshot" => message.content,
          "reason" => reason
        }

        # The cap is the reporter's, so the count and the insert run under the
        # reporter's lock: reports sent at once each counted the others as not
        # there yet, and all of them landed past the cap.
        Lock.serialize("chat_reports_reporter", reporter_id, fn ->
          if over_daily_cap?(reporter_id), do: Repo.rollback(:report_daily_limit)

          case insert_report_row(attrs) do
            {:ok, report} -> report
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, report} -> reported(report)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # 0 or nil disables the cap, matching how the other limits read.
  defp over_daily_cap?(reporter_id) do
    case Gamend.Limits.get(:max_chat_reports_per_user_per_day) do
      limit when is_integer(limit) and limit > 0 ->
        count_recent_by_reporter(reporter_id) >= limit

      _ ->
        false
    end
  end

  @doc """
  File a report on the word filter's behalf (`reporter_id` stays nil).

  Called after the flagged message is committed — at filter time it has no id
  yet.
  """
  @spec report_flagged_message(Message.t(), [String.t()]) :: {:ok, Report.t()} | {:error, term()}
  def report_flagged_message(%Message{} = message, flagged_words) do
    insert_report(%{
      "message_id" => message.id,
      "reported_user_id" => message.sender_id,
      "content_snapshot" => message.content,
      "reason" => "Filter: " <> Enum.join(flagged_words, ", ")
    })
  end

  defp insert_report(attrs) do
    with {:ok, report} <- insert_report_row(attrs), do: reported(report)
  end

  defp reported(report) do
    dispatch(:after_chat_message_reported, [report])
    alert_admins()
    {:ok, report}
  end

  # The message was read before this, and may have been deleted since.
  defp insert_report_row(attrs) do
    Repo.rescue_foreign_key(:not_found, fn ->
      %Report{}
      |> Report.changeset(attrs)
      |> Repo.insert()
    end)
    |> case do
      {:ok, report} ->
        {:ok, report}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :reporter_id) or Keyword.has_key?(errors, :message_id) do
          {:error, :already_reported}
        else
          {:error, changeset}
        end

      {:error, :not_found} = gone ->
        gone
    end
  end

  @doc "Fetch one report with its associations loaded."
  @spec get_report(Ecto.UUID.t()) :: Report.t() | nil
  def get_report(id) do
    Report
    |> Repo.get(id)
    |> Repo.preload([:reporter, :reported_user, :resolved_by_user])
  end

  @doc """
  List reports, newest first. Filters: `:status`, `:reported_user_id`,
  `:reporter_id`.
  """
  @spec list_reports(map(), keyword()) :: [Report.t()]
  def list_reports(filters \\ %{}, opts \\ []) do
    filters
    |> reports_query()
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> Gamend.Query.page(opts)
    |> preload([:reporter, :reported_user, :resolved_by_user])
    |> Repo.all()
  end

  @doc "Count reports matching `filters`."
  @spec count_reports(map()) :: non_neg_integer()
  def count_reports(filters \\ %{}) do
    filters |> reports_query() |> Repo.aggregate(:count, :id)
  end

  @doc "Count reports still awaiting a moderator."
  @spec count_open_reports() :: non_neg_integer()
  def count_open_reports, do: count_reports(%{status: "open"})

  @doc """
  Count reports filed by `reporter_id` in the last 24 hours.

  Backs the per-player daily cap; unlike the rate limiter this is durable, so
  it holds across restarts and every instance.
  """
  @spec count_recent_by_reporter(Ecto.UUID.t()) :: non_neg_integer()
  def count_recent_by_reporter(reporter_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

    from(r in Report, where: r.reporter_id == ^reporter_id and r.inserted_at > ^cutoff)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Resolve a report: set its status, note who resolved it and when.

  `status` is one of `Gamend.Chat.Report.statuses/0` other than `"open"`.
  """
  @spec resolve_report(Report.t() | Ecto.UUID.t(), String.t(), map()) ::
          {:ok, Report.t()} | {:error, term()}
  def resolve_report(report, status, attrs \\ %{})

  def resolve_report(%Report{} = report, status, attrs) do
    attrs = %{
      "status" => status,
      "resolution_note" => Map.get(attrs, :note) || Map.get(attrs, "note"),
      "resolved_by" => Map.get(attrs, :resolved_by) || Map.get(attrs, "resolved_by"),
      "resolved_at" => DateTime.utc_now(:second)
    }

    report
    |> Report.resolve_changeset(attrs)
    |> Repo.update()
  end

  def resolve_report(report_id, status, attrs) when is_binary(report_id) do
    case Repo.get(Report, report_id) do
      nil -> {:error, :not_found}
      report -> resolve_report(report, status, attrs)
    end
  end

  @doc """
  Claim a report for review (`"open"` → `"reviewing"`).

  Purely a signal to other moderators that someone has picked this one up; it
  sets no resolution, so the report stays in the queue until it is dismissed or
  actioned.
  """
  @spec review_report(Report.t() | Ecto.UUID.t()) :: {:ok, Report.t()} | {:error, term()}
  def review_report(%Report{} = report) do
    report
    |> Report.resolve_changeset(%{"status" => "reviewing"})
    |> Repo.update()
  end

  def review_report(report_id) when is_binary(report_id) do
    case Repo.get(Report, report_id) do
      nil -> {:error, :not_found}
      report -> review_report(report)
    end
  end

  @doc "Delete a report outright (admin)."
  @spec delete_report(Report.t()) :: {:ok, Report.t()} | {:error, Ecto.Changeset.t()}
  def delete_report(%Report{} = report), do: Repo.delete(report)

  @doc "Count reports grouped by status, as `%{status => count}`."
  @spec count_by_status() :: map()
  def count_by_status do
    from(r in Report, group_by: r.status, select: {r.status, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp reports_query(filters) do
    query = from(r in Report)

    query =
      case Gamend.Parse.blank_to_nil(Map.get(filters, :status) || Map.get(filters, "status")) do
        nil -> query
        value -> where(query, [r], r.status == ^value)
      end

    query =
      case Gamend.Parse.blank_to_nil(
             Map.get(filters, :reported_user_id) || Map.get(filters, "reported_user_id")
           ) do
        nil -> query
        value -> where_id(query, :reported_user_id, value)
      end

    case Gamend.Parse.blank_to_nil(
           Map.get(filters, :reporter_id) || Map.get(filters, "reporter_id")
         ) do
      nil -> query
      value -> where_id(query, :reporter_id, value)
    end
  end

  # An admin filter typed by hand: an id that is not one matches nothing.
  defp where_id(query, field, value) do
    case Gamend.UUIDv7.cast_or_nil(to_string(value)) do
      nil -> where(query, [_], false)
      id -> where(query, [r], field(r, ^field) == ^id)
    end
  end

  # Hooks never run inside the write — they are queued and flushed after it.
  defp dispatch(hook, args) do
    Gamend.Async.run(fn -> Gamend.Hooks.internal_call(hook, args) end)
    :ok
  end

  # A standing "you have reports waiting" alert per admin. The notification
  # table upserts on (sender, recipient, title), so this stays one unread entry
  # that keeps its count current rather than one notification per report.
  defp alert_admins do
    Gamend.Async.run(fn ->
      Notices.notify_admins_of_report(count_open_reports())
    end)

    :ok
  end
end
