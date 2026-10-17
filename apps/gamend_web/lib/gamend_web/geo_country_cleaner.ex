defmodule GamendWeb.GeoCountryCleaner do
  @moduledoc """
  Periodic cleaner for old geo traffic minute buckets.

  Runs every hour and removes ETS entries older than the retention period
  (7 days by default) to prevent unbounded memory growth, and the expired
  crawler DNS verdicts (`GamendWeb.Crawlers.Verify`).

  Started as part of the application supervision tree.
  """

  use GenServer

  alias GamendWeb.Crawlers.Verify
  alias GamendWeb.Plugs.GeoCountry

  # Run cleanup every hour
  @cleanup_interval :timer.hours(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    removed = GeoCountry.cleanup_old_buckets()
    Verify.cleanup()

    if removed > 0 do
      require Logger
      Logger.debug("GeoCountryCleaner: removed #{removed} expired minute buckets")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
