defmodule Gamend.Tournaments.Ticker do
  @moduledoc """
  Periodic driver for tournament lifecycles: state transitions, match-ready
  firing, deadline_at sweeps and recurrence spawns (`Gamend.Tournaments.tick/0`).

  Safe in multi-instance deployments: the tick body is serialized cluster-wide
  via `Gamend.Lock`.
  """

  use GenServer
  require Logger

  @initial_delay_ms :timer.seconds(5)

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :tournaments,
    label: "Tournaments"

  setting(:tick_interval_seconds, :integer,
    default: 30,
    doc:
      "Seconds between tournament ticks: state transitions, match-ready, deadline " <>
        "sweeps and recurrence. A round can start or time out up to this late."
  )

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Stays supervised but idle when disabled (tests): the tick has no sandbox
    # connection to check out, so it would just stall and then error.
    if enabled?(), do: Process.send_after(self(), :tick, @initial_delay_ms)
    {:ok, %{}}
  end

  defp enabled?, do: Application.get_env(:gamend_core, __MODULE__, [])[:enabled] != false

  @impl true
  def handle_info(:tick, state) do
    _ =
      try do
        Gamend.Tournaments.tick()
      rescue
        e -> Logger.error("tournaments tick failed: #{Exception.message(e)}")
      end

    seconds = max(Gamend.Settings.get(__MODULE__, :tick_interval_seconds), 1)
    Process.send_after(self(), :tick, :timer.seconds(seconds))
    {:noreply, state}
  end
end
