defmodule Gamend.Accounts.PresenceWriter do
  @moduledoc """
  Coalesces `users.is_online` transitions into one write per flush window.

  `Accounts.set_user_online/1` and `set_user_offline/1` already skip the write
  entirely when the flag is unchanged, so a reconnect or a second socket for an
  already-online player costs nothing. What is left is the storm: N *distinct*
  players connecting at once is N separate transactions, and on single-writer
  SQLite those serialize behind each other.

  This buffers the transitions and flushes them as one `SELECT` (which rows
  would actually change) plus one `UPDATE` per direction, then fires the same
  cache invalidation, broadcasts and hooks the synchronous path fires — once
  per user that really transitioned, never for a no-op.

  ## Buffered state is in ETS, not in the GenServer

  Callers have to read the buffer to decide whether they are making a real
  transition: a player who disconnects inside the flush window must see their
  own pending connect, or the disconnect reads as a no-op and the stale connect
  is what reaches the database. Routing that read through the process would put
  a `GenServer.call` on every socket join — the exact serialization this module
  exists to remove — so the buffer is a public ETS table and the process only
  owns the timer.

  ## Configuration

      config :gamend_core, Gamend.Accounts.PresenceWriter,
        flush_ms: 200      # 0 writes through synchronously

  `flush_ms: 0` writes each change as it comes and is what the test environment
  runs, so a test can assert on `is_online` immediately after the call. In
  production the flag lags by at most one window — `StalePresenceSweeper` is
  the backstop that already tolerates far more drift than that, and realtime
  subscribers are told over PubSub from the channel, not from this write.

  If the process is not running (some test setups start a partial tree),
  `flush_ms/0` reports 0 and callers write through rather than dropping the
  transition on the floor.
  """

  use GenServer

  import Ecto.Query

  require Logger

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Repo

  @default_flush_ms 200
  @table __MODULE__.Pending

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Milliseconds to buffer transitions. 0 means callers write through.
  """
  @spec flush_ms() :: non_neg_integer()
  def flush_ms do
    if Process.whereis(__MODULE__) do
      :gamend_core
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:flush_ms, @default_flush_ms)
    else
      0
    end
  end

  @doc """
  The state this user is buffered to become, or `default` when nothing is
  buffered for them.
  """
  @spec pending(Ecto.UUID.t(), boolean()) :: boolean()
  def pending(user_id, default) when is_binary(user_id) and is_boolean(default) do
    case :ets.lookup(@table, user_id) do
      [{^user_id, online?}] -> online?
      [] -> default
    end
  rescue
    ArgumentError -> default
  end

  @doc """
  Queues an online/offline transition for `user_id`.

  Later marks for the same user replace earlier ones, so a connect immediately
  followed by a disconnect flushes once, as the disconnect.
  """
  @spec mark(Ecto.UUID.t(), boolean()) :: :ok
  def mark(user_id, online?) when is_binary(user_id) and is_boolean(online?) do
    true = :ets.insert(@table, {user_id, online?})
    GenServer.cast(__MODULE__, :schedule)
  end

  @doc "Flushes everything buffered right now. Synchronous; used by tests."
  @spec flush() :: :ok
  def flush, do: GenServer.call(__MODULE__, :flush)

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    # Public + write_concurrency: every socket join writes to this table, and
    # every join reads it. The process owns it only so it dies with it.
    @table = :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    {:ok, %{timer: nil}}
  end

  @impl true
  def handle_cast(:schedule, state), do: {:noreply, schedule(state)}

  @impl true
  def handle_call(:flush, _from, state), do: {:reply, :ok, do_flush(state)}

  @impl true
  def handle_info(:flush, state), do: {:noreply, do_flush(state)}

  @impl true
  def terminate(_reason, state) do
    # A graceful shutdown still owes the database the transitions it buffered.
    _ = do_flush(state)
    :ok
  end

  # ── Flushing ────────────────────────────────────────────────────────────────

  defp schedule(%{timer: nil} = state) do
    case flush_ms() do
      ms when ms > 0 -> %{state | timer: Process.send_after(self(), :flush, ms)}
      _ -> do_flush(state)
    end
  end

  defp schedule(state), do: state

  defp do_flush(state) do
    case take_pending() do
      [] ->
        :ok

      pending ->
        now = DateTime.utc_now(:second)

        pending
        |> Enum.group_by(fn {_id, online?} -> online? end, fn {id, _online?} -> id end)
        |> Enum.each(fn {online?, ids} -> write(ids, online?, now) end)
    end

    %{state | timer: cancel(state.timer)}
  rescue
    error ->
      # Losing a presence flag must not take the writer (and every transition
      # buffered after it) down; StalePresenceSweeper reconciles.
      Logger.warning("PresenceWriter flush failed: #{inspect(error)}")
      %{state | timer: cancel(state.timer)}
  end

  # `delete_object`, not `delete`: a mark that lands between the read and the
  # delete has a different value and must survive into the next window rather
  # than be dropped as already-handled.
  defp take_pending do
    pending = :ets.tab2list(@table)
    Enum.each(pending, &:ets.delete_object(@table, &1))
    pending
  rescue
    ArgumentError -> []
  end

  defp cancel(nil), do: nil

  defp cancel(timer) do
    _ = Process.cancel_timer(timer)
    nil
  end

  # Read the rows that actually change before updating them: the side effects
  # below must fire once per real transition, and `update_all` cannot tell us
  # which rows it touched on every adapter.
  defp write(ids, online?, now) do
    users =
      from(u in User, where: u.id in ^ids and u.is_online != ^online?)
      |> Repo.all()

    case users do
      [] ->
        :ok

      users ->
        from(u in User, where: u.id in ^Enum.map(users, & &1.id))
        |> Repo.update_all(set: [is_online: online?, last_seen_at: now])

        Enum.each(users, fn user ->
          Accounts.after_presence_write(%{user | is_online: online?, last_seen_at: now})
        end)
    end
  end
end
