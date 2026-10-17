defmodule Gamend.Repo.SlowLog do
  @moduledoc """
  Names what is slow in the database, in the log.

    * **A slow query**: one that ran, or waited for a pool connection, longer
      than `GAMEND_DB_SLOW_QUERY_MS` (default 1000).
    * **A long transaction**: one that held its connection, from `begin` to
      `commit` or `rollback`, longer than `GAMEND_DB_SLOW_TRANSACTION_MS`
      (default 2000). On SQLite that connection holds the one write lock
      (transactions are `IMMEDIATE`), so this is the line that explains a
      "database is locked": those errors name the process that waited, never
      the one it waited for.

  Each line has the time, the table, the SQL (trimmed) and where in the code
  it came from: the first frames outside Ecto and DBConnection. `0` turns
  either off. The settings are read when the handler attaches, at boot
  (`GamendWeb.HostSupervision.init_runtime/1`); a change takes a restart.

  The handler runs inside every query, in the caller's process, so it only
  compares two integers unless something was slow.
  """

  require Logger

  alias Gamend.Settings

  @handler "gamend-repo-slow-log"
  @event [:gamend, :repo, :query]
  @began {__MODULE__, :began}
  @sql_max 300
  @frames 4
  @backtrace_depth 32

  @doc "Attach the handler with the current settings (detaching any earlier one)."
  @spec attach() :: :ok
  def attach do
    query_ms = Settings.get(Gamend.Database, :slow_query_ms)
    transaction_ms = Settings.get(Gamend.Database, :slow_transaction_ms)
    _ = :telemetry.detach(@handler)

    # The process's own stack is the fallback for where a query came from, and
    # the default depth (8) is spent inside Ecto and DBConnection before it
    # reaches the caller.
    if :erlang.system_flag(:backtrace_depth, @backtrace_depth) > @backtrace_depth,
      do: :erlang.system_flag(:backtrace_depth, :erlang.system_info(:backtrace_depth))

    if positive?(query_ms) or positive?(transaction_ms) do
      :ok =
        :telemetry.attach(@handler, @event, &__MODULE__.handle_event/4, %{
          query: native(query_ms),
          transaction: native(transaction_ms)
        })
    end

    :ok
  end

  @doc "Detach the handler."
  @spec detach() :: :ok
  def detach do
    _ = :telemetry.detach(@handler)
    :ok
  end

  @doc false
  def handle_event(_event, measurements, %{query: "begin" <> _}, config) do
    if config.transaction, do: Process.put(@began, System.monotonic_time())
    log_slow_query(measurements, nil, config)
  end

  def handle_event(_event, measurements, %{query: "commit" <> _} = metadata, config),
    do: end_transaction(measurements, metadata, config)

  def handle_event(_event, measurements, %{query: "rollback" <> _} = metadata, config),
    do: end_transaction(measurements, metadata, config)

  def handle_event(_event, measurements, metadata, config),
    do: log_slow_query(measurements, metadata, config)

  defp end_transaction(measurements, metadata, config) do
    case Process.delete(@began) do
      began when is_integer(began) and is_integer(config.transaction) ->
        held = System.monotonic_time() - began

        if held > config.transaction do
          Logger.warning(
            "slow transaction: held its connection #{ms(held)}ms " <>
              "(#{String.upcase(String.slice(metadata.query, 0, 8))}) at #{where(metadata)}"
          )
        end

      _ ->
        :ok
    end

    log_slow_query(measurements, nil, config)
  end

  # The time to run a query and the time spent waiting for a connection are
  # both what a page waits for; either over the line is worth a line.
  defp log_slow_query(_measurements, _metadata, %{query: nil}), do: :ok

  defp log_slow_query(measurements, metadata, %{query: limit}) do
    run = Map.get(measurements, :query_time, 0)
    queue = Map.get(measurements, :queue_time, 0)

    if run > limit or queue > limit do
      Logger.warning(
        "slow query: #{ms(run)}ms (waited #{ms(queue)}ms for a connection)" <>
          describe(metadata)
      )
    end

    :ok
  end

  # `nil` for a `begin`/`commit`, whose own wait is the lock: the SQL says
  # nothing more.
  defp describe(nil), do: " on BEGIN/COMMIT at #{where(%{})}"

  defp describe(metadata) do
    source = if metadata[:source], do: " #{metadata.source}", else: ""
    " on#{source}: #{String.slice(metadata.query || "", 0, @sql_max)} at #{where(metadata)}"
  end

  # The first frames outside the database layer: the stacktrace Ecto kept when
  # the repo has `stacktrace: true`, else the process's own, which the
  # handler runs inside.
  defp where(metadata) do
    stacktrace =
      case metadata[:stacktrace] do
        [_ | _] = stacktrace -> stacktrace
        _ -> self() |> Process.info(:current_stacktrace) |> elem(1)
      end

    stacktrace
    |> Enum.reject(&internal?/1)
    |> Enum.take(@frames)
    |> case do
      [] -> "(unknown)"
      frames -> Enum.map_join(frames, " < ", &Exception.format_stacktrace_entry/1)
    end
  end

  @internal_prefixes ~w(Elixir.Ecto. Elixir.DBConnection Elixir.Process telemetry erl)
  @internal_modules [Gamend.Repo, __MODULE__]

  defp internal?({module, _fun, _arity, _location}) do
    name = Atom.to_string(module)
    module in @internal_modules or Enum.any?(@internal_prefixes, &String.starts_with?(name, &1))
  end

  defp internal?(_frame), do: false

  defp positive?(value), do: is_integer(value) and value > 0

  defp native(ms) when is_integer(ms) and ms > 0,
    do: System.convert_time_unit(ms, :millisecond, :native)

  defp native(_ms), do: nil

  defp ms(native), do: System.convert_time_unit(native, :native, :millisecond)
end
