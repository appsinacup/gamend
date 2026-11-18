defmodule Gamend.Notifications.AnnouncementWorker do
  @moduledoc """
  Sends one batch of an announcement (`Gamend.Notifications.Announcements`)
  and queues the next. Unique per announcement (`"id"`) and cursor
  (`"after"`), forever: a job rescued after a crash cannot start a second
  chain behind the first.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:id, :after]]

  alias Gamend.Notifications.Announcements

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: Announcements.send_batch(args)
end
