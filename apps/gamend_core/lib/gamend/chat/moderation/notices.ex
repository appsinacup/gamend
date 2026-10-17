defmodule Gamend.Chat.Moderation.Notices do
  @moduledoc """
  The notifications chat moderation sends: alerting admins that a report landed,
  warning a player, telling a player they were muted, and telling a reporter
  what came of their report.

  Every message has a `default_*` function so the admin console can prefill the
  box and let a moderator edit it before sending. The text is the moderator's,
  not core's — these are only sensible starting points.

  All of them go through `Notifications.admin_create_notification/3` with the
  recipient as their own sender. That is the same trick chat notifications use:
  the notification table upserts on `(sender_id, recipient_id, title)`, so a
  player who is muted twice keeps one "You have been muted" entry (re-marked
  unread) instead of collecting a pile, and an admin sees one standing "New
  chat reports" alert rather than one per report.
  """

  require Logger

  alias Gamend.Accounts
  alias Gamend.Chat.Mute
  alias Gamend.Notifications

  @report_title "New chat reports"
  @mute_title "You have been muted"
  @warning_title "Warning from the moderators"
  @report_resolved_title "Your report was reviewed"

  @doc "Title used for the admin report alert (constant, so alerts collapse)."
  @spec report_title() :: String.t()
  def report_title, do: @report_title

  @doc "Title used for the player mute notice."
  @spec mute_title() :: String.t()
  def mute_title, do: @mute_title

  @doc "Title used for a moderator warning."
  @spec warning_title() :: String.t()
  def warning_title, do: @warning_title

  @doc "Title used when telling a reporter their report was handled."
  @spec report_resolved_title() :: String.t()
  def report_resolved_title, do: @report_resolved_title

  @doc """
  Tell every admin that a report is waiting.

  Best-effort and fire-and-forget: a failure here must never take down the
  report that triggered it.
  """
  @spec notify_admins_of_report(non_neg_integer()) :: :ok
  def notify_admins_of_report(open_count) do
    content =
      case open_count do
        1 -> "1 chat report is waiting for review."
        n -> "#{n} chat reports are waiting for review."
      end

    Enum.each(Accounts.list_admin_ids(), fn admin_id ->
      deliver(admin_id, @report_title, content, %{
        "type" => "chat_report",
        "open_reports" => open_count,
        "url" => "/admin/chat/reports"
      })
    end)

    :ok
  end

  @doc "Default body for the notice a muted player receives."
  @spec default_mute_message(Mute.t()) :: String.t()
  def default_mute_message(%Mute{} = mute) do
    "You can no longer send messages in #{scope_phrase(mute.scope)}#{duration_phrase(mute.expires_at)}." <>
      reason_phrase(mute.reason)
  end

  @doc "Default body for a moderator warning about a reported message."
  @spec default_warning_message(String.t() | nil) :: String.t()
  def default_warning_message(content_snapshot) do
    base =
      "A message you sent was reported and reviewed by a moderator. " <>
        "Please keep chat civil — repeated reports can lead to a mute."

    case blank(content_snapshot) do
      nil -> base
      snippet -> base <> "\n\nReported message: \"#{snippet}\""
    end
  end

  @doc "Default body for the reply a reporter receives once their report is handled."
  @spec default_reporter_message(String.t()) :: String.t()
  def default_reporter_message("dismissed") do
    "Thanks for the report. A moderator reviewed it and decided no action was needed."
  end

  def default_reporter_message(_status) do
    "Thanks for the report. A moderator reviewed it and took action."
  end

  @doc "Send `message` to a muted player."
  @spec notify_muted(Ecto.UUID.t(), String.t()) :: :ok
  def notify_muted(user_id, message),
    do: deliver(user_id, @mute_title, message, %{"type" => "chat_mute"})

  @doc "Send a warning to a player."
  @spec notify_warning(Ecto.UUID.t(), String.t()) :: :ok
  def notify_warning(user_id, message),
    do: deliver(user_id, @warning_title, message, %{"type" => "chat_warning"})

  @doc "Tell a reporter what came of their report."
  @spec notify_reporter(Ecto.UUID.t(), String.t()) :: :ok
  def notify_reporter(user_id, message),
    do: deliver(user_id, @report_resolved_title, message, %{"type" => "chat_report_resolved"})

  # Best-effort, but never silent: an undelivered moderation notice is a bug
  # (an unregistered `metadata["type"]` is rejected at write time), and one that
  # returns :ok anyway is invisible until someone asks why nobody was told.
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
          "chat moderation notice #{inspect(title)} not delivered to #{user_id}: " <>
            inspect(reason)
        )

        :ok
    end
  rescue
    error ->
      Logger.warning("chat moderation notice failed: " <> Exception.message(error))
      :ok
  catch
    :exit, _reason -> :ok
  end

  defp deliver(_user_id, _title, _content, _metadata), do: :ok

  defp scope_phrase("global"), do: "chat"
  defp scope_phrase(scope), do: "this #{scope}'s chat"

  defp duration_phrase(nil), do: ""

  defp duration_phrase(%DateTime{} = expires_at) do
    " until #{Calendar.strftime(expires_at, "%Y-%m-%d %H:%M UTC")}"
  end

  defp reason_phrase(reason) do
    case blank(reason) do
      nil -> ""
      value -> " Reason: #{value}"
    end
  end

  defp blank(nil), do: nil
  defp blank(""), do: nil

  defp blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank(_value), do: nil
end
