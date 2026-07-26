defmodule GameServer.Tournaments.Ticker do
  @moduledoc """
  Periodic driver for tournament lifecycles: state transitions, match-ready
  firing, deadline_at sweeps and recurrence spawns (`GameServer.Tournaments.tick/0`).

  Safe in multi-instance deployments: the tick body is serialized cluster-wide
  via `GameServer.Lock`.
  """

  use GenServer
  require Logger

  @interval_ms :timer.seconds(30)
  @initial_delay_ms :timer.seconds(5)

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

  defp enabled?, do: Application.get_env(:game_server_core, __MODULE__, [])[:enabled] != false

  @impl true
  def handle_info(:tick, state) do
    _ =
      try do
        GameServer.Tournaments.tick()
      rescue
        e -> Logger.error("tournaments tick failed: #{Exception.message(e)}")
      end

    Process.send_after(self(), :tick, @interval_ms)
    {:noreply, state}
  end
end
