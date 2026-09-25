defmodule Gamend.AfterCommit do
  @moduledoc """
  Side effects that wait for the enclosing transaction to commit.

  A broadcast, a hook dispatch or a spawned task inside a transaction runs
  while the transaction holds the database, which on SQLite (a single
  connection, `BEGIN IMMEDIATE`) is every other request's database too. It is
  also observed before the write is visible, and survives a rollback of the
  write it announces. `defer/1` queues the effect instead, and the queue runs
  once the outermost `transaction/2` (or `Gamend.Lock.serialize/3`) has
  committed and released its lock. A rollback or an exception drops it.

  Outside such a scope `defer/1` runs the effect at once, so a helper can
  always defer and stay correct whether or not its caller holds a
  transaction. Inside a transaction opened with a bare `Repo.transaction/2`
  there is no commit to wait for, and it also runs at once, as before.

  Queued effects run in order, in the calling process, after the lock is
  released. The write is committed by then, so one that raises or exits is
  logged and does not stop the rest or fail the caller. An effect run at once
  behaves as a plain call.
  """

  require Logger

  alias Gamend.Repo

  @queue {__MODULE__, :queue}

  @doc """
  `Repo.transaction/2` (a function or an `Ecto.Multi`), with `defer/1` inside
  it queued until it commits. Every transaction in core goes through here.
  """
  @spec transaction((-> term()) | Ecto.Multi.t(), keyword()) ::
          {:ok, term()} | {:error, term()} | {:error, term(), term(), map()}
  def transaction(fun_or_multi, opts \\ []) do
    collect(fn -> Repo.transaction(fun_or_multi, opts) end)
  end

  @doc "`Repo.transact/2`, with `defer/1` inside it queued until it commits."
  @spec transact((-> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()}
  def transact(fun, opts \\ []) when is_function(fun, 0) do
    collect(fn -> Repo.transact(fun, opts) end)
  end

  @doc """
  Runs `body`, which opens a transaction, as the scope `defer/1` queues into:
  the queue runs when `body` returns `{:ok, _}` and is dropped otherwise. For
  wrappers that take a lock around the transaction (`Gamend.Lock.serialize/3`),
  so the effects run after the lock is released as well.

  Inside an outer scope it only runs `body`; the outer scope decides.
  """
  @spec collect((-> result)) :: result when result: term()
  def collect(body) when is_function(body, 0) do
    cond do
      Process.get(@queue) != nil -> body.()
      # A bare `Repo.transaction/2` is open around us: its commit is not ours
      # to see, so effects cannot wait for it.
      Repo.in_transaction?() -> body.()
      true -> own_scope(body)
    end
  end

  @doc "Runs `fun` once the enclosing scope commits, or now when there is none."
  @spec defer((-> any())) :: :ok
  def defer(fun) when is_function(fun, 0) do
    case Process.get(@queue) do
      nil ->
        fun.()
        :ok

      queue ->
        Process.put(@queue, [fun | queue])
        :ok
    end
  end

  @doc "Whether `defer/1` would queue rather than run."
  @spec deferring?() :: boolean()
  def deferring?, do: Process.get(@queue) != nil

  defp own_scope(body) do
    Process.put(@queue, [])

    result =
      try do
        body.()
      rescue
        e ->
          Process.delete(@queue)
          reraise e, __STACKTRACE__
      catch
        kind, reason ->
          Process.delete(@queue)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    effects = @queue |> Process.delete() |> Enum.reverse()
    if match?({:ok, _}, result), do: Enum.each(effects, &run_committed/1)
    result
  end

  defp run_committed(fun) do
    fun.()
  rescue
    e ->
      Logger.error("after-commit effect failed: " <> Exception.format(:error, e, __STACKTRACE__))
  catch
    kind, reason ->
      Logger.error(
        "after-commit effect failed: " <> Exception.format(kind, reason, __STACKTRACE__)
      )
  end
end
