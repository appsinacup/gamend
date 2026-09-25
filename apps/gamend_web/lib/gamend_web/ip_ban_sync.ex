defmodule GamendWeb.IpBanSync do
  @moduledoc """
  Keeps the node-local IP-ban ETS table in sync with the database and the
  other app instances.

  After init it loads persisted bans (`Gamend.IpBans`) into ETS;
  afterwards it applies ban/unban events broadcast by other instances on the
  `GamendWeb.Plugs.IpBan.topic/0` PubSub topic. Events originating on
  this node are skipped — the plug already applied them locally.

  The initial load runs in `handle_continue` and retries on failure instead
  of failing the boot: `init/1` must not couple application startup to the
  database being reachable (e.g. during rolling restarts). Every failed
  attempt logs an error, so an unmigrated `ip_bans` table stays loudly
  visible without crash-looping the whole application.
  """

  use GenServer

  require Logger

  alias GamendWeb.Plugs.IpBan

  @retry_ms :timer.seconds(10)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # `enabled: false` in the app config keeps it supervised but idle, for test
  # suites: the load at boot holds a database connection the tests need, and
  # they call `IpBan.load_persisted/0` and `apply_remote/3` themselves.
  @impl true
  def init(_opts) do
    if Keyword.get(Application.get_env(:gamend_web, __MODULE__, []), :enabled, true) do
      Phoenix.PubSub.subscribe(Gamend.PubSub, IpBan.topic())
      {:ok, %{loaded?: false}, {:continue, :load_persisted}}
    else
      {:ok, %{loaded?: true}}
    end
  end

  @impl true
  def handle_continue(:load_persisted, state), do: {:noreply, attempt_load(state)}

  @impl true
  def handle_info({:ip_ban, event, ip, expires_at_utc, from_node}, state) do
    if from_node != Node.self() do
      IpBan.apply_remote(event, ip, expires_at_utc)
    end

    {:noreply, state}
  end

  def handle_info(:retry_load, state), do: {:noreply, attempt_load(state)}

  def handle_info(_message, state), do: {:noreply, state}

  defp attempt_load(%{loaded?: true} = state), do: state

  defp attempt_load(state) do
    IpBan.load_persisted()
    %{state | loaded?: true}
  rescue
    e ->
      Logger.error(
        "could not load persisted IP bans (retrying in #{div(@retry_ms, 1000)}s): " <>
          Exception.message(e)
      )

      Process.send_after(self(), :retry_load, @retry_ms)
      state
  end
end
