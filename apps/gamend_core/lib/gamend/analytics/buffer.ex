defmodule Gamend.Analytics.Buffer do
  @moduledoc """
  Gathers `Gamend.Analytics` writes in ETS and lands them in batches: one
  upsert per `(key, day)` counter and one `insert_all` for the events, every
  `flush_ms`. A page view at twenty requests a second is otherwise a
  database write per request, on the request's own connection.

  The table is public with write concurrency: the request process does one
  `update_counter` or one insert and never sends this process a message.
  Up to one window of counts and events is lost on a crash or a kill, which
  a daily number can bear; a graceful stop flushes.

  ## Configuration

      config :gamend_core, Gamend.Analytics.Buffer,
        flush_ms: 10_000    # 0 writes through synchronously

  `flush_ms: 0` is what the test environment runs: a test reads a counter
  the moment the page wrote it, and nothing buffered can outlive the sandbox
  owner. When the process is not running (a partial tree) callers write
  through too, rather than drop the write.

  Events are capped at `max_events/0` waiting rows; past that a new event is
  dropped and `analytics.dropped` counted, so a database outage costs memory
  bounded in megabytes, never the node.
  """

  use GenServer

  alias Gamend.Analytics

  @table __MODULE__.Pending
  @default_flush_ms 10_000
  @max_events 50_000
  @insert_chunk 500

  # ── API ────────────────────────────────────────────────────────────────────

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Milliseconds between flushes; 0 means callers write through."
  @spec flush_ms() :: non_neg_integer()
  def flush_ms do
    if Process.whereis(__MODULE__), do: configured_flush_ms(), else: 0
  end

  @doc "Whether writes are gathered here (`flush_ms/0` > 0 and the table exists)."
  @spec buffered?() :: boolean()
  def buffered?, do: flush_ms() > 0 and :ets.whereis(@table) != :undefined

  @doc "The cap on events waiting to be written."
  @spec max_events() :: pos_integer()
  def max_events, do: @max_events

  @doc "Adds `n` to the counter `key` for `day`. Caller must have checked `buffered?/0`."
  @spec bump(String.t(), pos_integer(), Date.t()) :: :ok
  def bump(key, n, %Date{} = day) when is_binary(key) and is_integer(n) do
    _ = :ets.update_counter(@table, {:count, key, day}, n, {{:count, key, day}, 0})
    :ok
  end

  @doc """
  Queues one event row (`%{name, dims, user_id, inserted_at}`). Dropped, and
  counted as `analytics.dropped`, past `max_events/0`.
  """
  @spec event(map()) :: :ok
  def event(%{name: _, inserted_at: at} = row) do
    if :ets.info(@table, :size) < @max_events do
      true = :ets.insert(@table, {{:event, System.unique_integer([:monotonic, :positive])}, row})
    else
      bump("analytics.dropped", 1, DateTime.to_date(at))
    end

    :ok
  end

  @doc """
  Writes everything gathered so far, in the caller's process: the counters
  as one upsert per `(key, day)`, the events in chunks of #{@insert_chunk}.
  The timer calls it; the admin pages call it before reading; a test calls
  it when it set a window. Answers `{counters, events}` written.
  """
  @spec flush() :: {non_neg_integer(), non_neg_integer()}
  def flush do
    {flush_counts(), flush_events()}
  rescue
    ArgumentError -> {0, 0}
  end

  @doc "Drops everything gathered, unwritten. For a test that set a window."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  # ── Flushing ───────────────────────────────────────────────────────────────

  defp flush_counts do
    rows =
      :ets.select(@table, [
        {{{:count, :"$1", :"$2"}, :"$3"}, [{:>, :"$3", 0}], [{{:"$1", :"$2", :"$3"}}]}
      ])

    Enum.each(rows, fn {key, day, n} ->
      # Subtract what is written rather than delete the row: an increment
      # between the read and the write is kept for the next flush.
      :ets.update_counter(@table, {:count, key, day}, -n)
      Analytics.write_count(key, n, day)
    end)

    # A row at zero is one nobody wrote since: drop it. Per object the match
    # is atomic, so an increment either kept it or recreates it.
    :ets.select_delete(@table, [{{{:count, :_, :_}, 0}, [], [true]}])
    length(rows)
  end

  defp flush_events do
    rows = :ets.select(@table, [{{{:event, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}])

    rows
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.reduce(0, fn chunk, written ->
      case Analytics.write_events(Enum.map(chunk, &elem(&1, 1))) do
        :ok ->
          # Deleted only once written: a chunk the database refused stays
          # for the next flush, bounded by the cap.
          Enum.each(chunk, fn {id, _row} -> :ets.delete(@table, {:event, id}) end)
          written + length(chunk)

        :error ->
          written
      end
    end)
  end

  # ── The process ────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    @table = :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule(configured_flush_ms())
    {:ok, %{}}
  end

  @impl true
  def handle_info(:flush, state) do
    _ = flush()
    schedule(configured_flush_ms())
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    # A graceful stop still owes the database what it gathered.
    _ = flush()
    :ok
  end

  defp configured_flush_ms do
    case Application.get_env(:gamend_core, __MODULE__, [])[:flush_ms] do
      ms when is_integer(ms) and ms > 0 -> ms
      nil -> @default_flush_ms
      _ -> 0
    end
  end

  defp schedule(ms) when is_integer(ms) and ms > 0, do: Process.send_after(self(), :flush, ms)
  defp schedule(_off), do: :ok
end
