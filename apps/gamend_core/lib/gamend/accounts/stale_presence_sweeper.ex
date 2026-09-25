defmodule Gamend.Accounts.StalePresenceSweeper do
  @moduledoc """
  Periodically sweeps users whose `is_online` flag is `true` but whose
  `last_seen_at` timestamp is older than a configurable threshold.

  This is a safety net for node crashes or ungraceful disconnects where the
  `UserChannel.terminate/2` callback never fires. Without this, users would
  remain marked as online indefinitely.

  ## Configuration

  `interval_ms` and `stale_threshold_s` are settings (`GAMEND_PRESENCE_*`).
  `enabled: false` in the app config turns the sweep off entirely (tests).

  A connected socket refreshes `last_seen_at` on a heartbeat derived from the
  threshold (`heartbeat_ms/0`), so a live player is never swept.
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Repo

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :presence,
    label: "Presence"

  setting(:interval_ms, :integer,
    default: 120_000,
    doc: "How often users still marked online after a crash are looked for, in ms."
  )

  setting(:stale_threshold_s, :integer,
    default: 300,
    doc:
      "Mark a user offline once their last_seen_at is this many seconds old. Connected " <>
        "sockets refresh it at three fifths of this, at most every 3 minutes."
  )

  # A connected socket refreshes `last_seen_at` at least this often, whatever
  # the threshold: the abandoned-lobby reaper (15 minutes by default) reads the
  # same column, so a long threshold must not slow the refresh down.
  @max_heartbeat_ms :timer.minutes(3)

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current configuration used by the sweeper.
  """
  @spec config() :: keyword()
  def config do
    Application.get_env(:gamend_core, __MODULE__, [])
  end

  @doc """
  How often a connected socket refreshes `last_seen_at`: three fifths of
  `stale_threshold_s`, so two refreshes fit before a user reads as stale, and
  never less often than every 3 minutes.
  """
  @spec heartbeat_ms() :: pos_integer()
  def heartbeat_ms do
    (threshold_s() * 600) |> min(@max_heartbeat_ms) |> max(1_000)
  end

  defp interval_ms, do: max(Gamend.Settings.get(__MODULE__, :interval_ms), 1_000)
  defp threshold_s, do: max(Gamend.Settings.get(__MODULE__, :stale_threshold_s), 1)

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    conf = config()
    enabled = Keyword.get(conf, :enabled, true)

    if enabled do
      interval = interval_ms()
      # A hard stop skips every UserChannel.terminate/2, so the node comes
      # back with all previously connected users still is_online=true. Sweep
      # right away (as a message, so init never blocks the supervision tree
      # on the DB) instead of waiting a full interval — during that gap the
      # stale flags read as live presence to everything gating on them.
      schedule_sweep(0)
      Logger.info("StalePresenceSweeper started (interval=#{interval}ms)")
    else
      Logger.info("StalePresenceSweeper disabled by config")
    end

    {:ok, %{enabled: enabled}}
  end

  @impl true
  def handle_info(:sweep, %{enabled: false} = state) do
    {:noreply, state}
  end

  def handle_info(:sweep, state) do
    interval = interval_ms()
    swept = do_sweep(threshold_s())

    if swept > 0 do
      Logger.info("StalePresenceSweeper: marked #{swept} stale user(s) offline")
    end

    schedule_sweep(interval)
    {:noreply, state}
  end

  # ── Sweep logic ─────────────────────────────────────────────────────────────

  @doc false
  @spec do_sweep(non_neg_integer()) :: non_neg_integer()
  def do_sweep(threshold_s) do
    cutoff = DateTime.utc_now() |> DateTime.add(-threshold_s, :second)

    stale_users =
      from(u in User,
        where: u.is_online == true,
        where: is_nil(u.last_seen_at) or u.last_seen_at < ^cutoff,
        select: u.id
      )
      |> Repo.all()

    Enum.each(stale_users, fn user_id ->
      case Accounts.set_user_offline(user_id) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "StalePresenceSweeper: failed to mark user #{user_id} offline: #{inspect(reason)}"
          )
      end
    end)

    length(stale_users)
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp schedule_sweep(interval_ms) do
    Process.send_after(self(), :sweep, interval_ms)
  end
end
