defmodule Gamend.Reports.Notices do
  @moduledoc """
  The notifications reports send: one standing "N reports waiting" alert per
  admin, and a reply to a reporter who had an account.

  Same trick as `Gamend.Chat.Moderation.Notices`: the notification table
  upserts on `(sender_id, recipient_id, title)` and each notice is sent with
  the recipient as its own sender, so an admin keeps one alert whose count
  moves rather than one per report, and a reporter one "reviewed" entry.
  """

  require Logger

  alias Gamend.Accounts
  alias Gamend.Notifications

  @admin_title "New reports"
  @reporter_title "Your report was reviewed"

  @doc "Title of the admin alert (constant, so alerts collapse into one)."
  @spec admin_title() :: String.t()
  def admin_title, do: @admin_title

  @doc "Title of the reply a reporter receives."
  @spec reporter_title() :: String.t()
  def reporter_title, do: @reporter_title

  @doc """
  Tell every admin how many reports are open, with a link to the queue
  (`"url"`, which `/notifications` and a push open). Nothing is sent at zero:
  an emptied queue leaves the last alert as it was, read or not.
  """
  @spec notify_admins(non_neg_integer()) :: :ok
  def notify_admins(0), do: :ok

  def notify_admins(open_count) when is_integer(open_count) do
    content =
      case open_count do
        1 -> "1 report is waiting for review."
        n -> "#{n} reports are waiting for review."
      end

    Enum.each(Accounts.list_admin_ids(), fn admin_id ->
      deliver(admin_id, @admin_title, content, %{
        "type" => "report",
        "open_reports" => open_count,
        "url" => "/admin/reports"
      })
    end)
  end

  @doc "Send `message` to the player who filed a report."
  @spec notify_reporter(Ecto.UUID.t(), String.t()) :: :ok
  def notify_reporter(user_id, message),
    do: deliver(user_id, @reporter_title, message, %{"type" => "report_resolved"})

  @doc """
  A starting point for the reply, by the status the report was closed with.
  A fixed one ends on what the host pays for it (`Gamend.Reports.reward_text/1`).
  """
  @spec default_reporter_message(String.t(), String.t() | nil) :: String.t()
  def default_reporter_message(status, about \\ nil)

  def default_reporter_message("fixed", about) do
    fixed = "Thanks for your report#{about(about)}. It is fixed now."

    case Gamend.Reports.reward_text(:paid) do
      nil -> fixed
      paid -> fixed <> " " <> paid
    end
  end

  def default_reporter_message("duplicate", about),
    do: "Thanks for your report#{about(about)}. Someone reported it before you, and we are on it."

  def default_reporter_message(_status, about),
    do: "Thanks for your report#{about(about)}. We looked at it and are leaving it as it is."

  defp about(nil), do: ""
  defp about(""), do: ""
  defp about(text), do: " about \"#{text}\""

  # Best-effort, but never silent: an undelivered notice is a bug somewhere.
  defp deliver(user_id, title, content, metadata) when is_binary(user_id) do
    case Notifications.admin_create_notification(user_id, user_id, %{
           "title" => title,
           "content" => content,
           "metadata" => metadata
         }) do
      {:ok, _notification} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "report notice #{inspect(title)} not delivered to #{user_id}: #{inspect(reason)}"
        )

        :ok
    end
  rescue
    error ->
      Logger.warning("report notice failed: " <> Exception.message(error))
      :ok
  catch
    :exit, _reason -> :ok
  end

  defp deliver(_user_id, _title, _content, _metadata), do: :ok
end
