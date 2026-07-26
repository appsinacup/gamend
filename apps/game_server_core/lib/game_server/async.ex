defmodule GameServer.Async do
  @moduledoc """
  Utilities for running best-effort background work.

  This is intentionally used for *non-critical* side effects (cache invalidation,
  notifications, hooks) where we want the caller to return quickly.

  Tasks are started under a `Task.Supervisor` bounded by `:max_children`
  (see the host application supervision tree). When the supervisor is at
  capacity, the work runs **inline in the caller** instead of spawning an
  unsupervised process — under overload the system degrades to synchronous
  execution, which applies natural back-pressure instead of growing an
  unbounded process count. If the supervisor isn't running at all (e.g.
  certain test setups), we fall back to `Task.start/1`.

  Telemetry: `[:game_server, :async, :overload]` is emitted each time a task
  is executed inline because the supervisor was full.
  """

  require Logger

  @supervisor GameServer.TaskSupervisor

  @type zero_arity_fun :: (-> any())

  @spec run(zero_arity_fun()) :: :ok
  def run(fun) when is_function(fun, 0) do
    wrapped = wrap(fun)

    if inline?() do
      wrapped.()
      :ok
    else
      spawn_task(wrapped)
    end
  end

  # Tests set `:async_inline` so side effects land before assertions run, and so
  # a fire-and-forget task can't outlive the DB sandbox owner (which surfaced as
  # a storm of "owner exited" DBConnection errors).
  defp inline?, do: Application.get_env(:game_server_core, :async_inline, false)

  defp spawn_task(wrapped) do
    case Process.whereis(@supervisor) do
      nil ->
        _ = Task.start(wrapped)
        :ok

      _pid ->
        case Task.Supervisor.start_child(@supervisor, wrapped) do
          {:ok, _pid} ->
            :ok

          {:error, :max_children} ->
            # Supervisor at capacity: run inline (back-pressure).
            :telemetry.execute([:game_server, :async, :overload], %{count: 1}, %{})
            Logger.warning("async supervisor at capacity — running task inline")
            wrapped.()
            :ok

          {:error, reason} ->
            Logger.error("async task could not be started: #{inspect(reason)}")
            :ok
        end
    end
  end

  defp wrap(fun) do
    fn ->
      try do
        fun.()
      rescue
        e ->
          Logger.error("async task crashed: " <> Exception.format(:error, e, __STACKTRACE__))
      catch
        kind, reason ->
          Logger.error("async task crashed: #{inspect({kind, reason})}")
      end
    end
  end
end
