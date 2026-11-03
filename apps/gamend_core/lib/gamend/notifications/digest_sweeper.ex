defmodule Gamend.Notifications.DigestSweeper do
  @moduledoc """
  Hourly, queues the digest emails that are due
  (`Gamend.Notifications.Digest.sweep/1`). `enabled: false` in the app config
  keeps it supervised but idle, for test suites. Safe on several nodes at
  once: the job is unique per user and group.
  """

  use GenServer

  require Logger

  alias Gamend.Notifications.Digest

  @interval :timer.hours(1)
  @first :timer.minutes(11)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if Keyword.get(Application.get_env(:gamend_core, __MODULE__, []), :enabled, true),
      do: Process.send_after(self(), :sweep, @first)

    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    try do
      case Digest.sweep() do
        0 -> :ok
        count -> Logger.info("notification digests: queued #{count}")
      end
    rescue
      error ->
        Logger.error("notification digest sweep failed: " <> Exception.message(error))
    end

    Process.send_after(self(), :sweep, @interval)
    {:noreply, state}
  end
end
