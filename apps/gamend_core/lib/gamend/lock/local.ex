defmodule Gamend.Lock.Local do
  @moduledoc """
  Reentrant keyed mutex, first come first served: the non-Postgres half of
  `Gamend.Lock.serialize/3`, and the node-local line in front of the Postgres
  advisory lock.

  Callers wait in `Gamend.Lock.Queue`, in the order they asked, and the key
  passes to the next one when the holder finishes or dies. It was a bare
  `:global.trans`, whose waiters retry after a random sleep that doubles up to
  8 s: with fifty callers on one key the lock sat free while they slept, and
  the last of them waited seconds for a section that takes milliseconds.

  `trans/2` also takes the `:global` lock, so the section stays exclusive across
  connected nodes; only the head of each node's line asks for it, so on a single
  node it never waits there. `:global` shares a lock between holders with the
  same *requester*, so the resource goes in the resource slot and `self()` in
  the requester slot.

  Reentrant within a process: the matchmaking sweep takes a lock and then
  creates a match, which takes one again. Before `Gamend.Lock.Queue` is running
  (it starts with the host's supervision tree) both fall back to `:global`.
  """

  alias Gamend.Lock.Queue

  @doc "Runs `fun` holding the lock for `key`. Blocks; reentrant within a process."
  @spec trans(term(), (-> result)) :: result when result: term()
  def trans(key, fun) when is_function(fun, 0) do
    hold(key, fn -> :global.trans({{__MODULE__, key}, self()}, fun) end, fn ->
      :global.trans({{__MODULE__, key}, self()}, fun)
    end)
  end

  @doc """
  As `trans/2`, on this node only. On Postgres the advisory lock is the
  cluster-wide one; this queues a node's own callers in the BEAM, where waiting
  is free, instead of each holding a pooled connection blocked on the database.
  """
  @spec trans_on_node(term(), (-> result)) :: result when result: term()
  def trans_on_node(key, fun) when is_function(fun, 0) do
    hold(key, fun, fn -> :global.trans({{__MODULE__, key}, self()}, fun, [node()]) end)
  end

  @doc """
  Runs `fun` after this node's earlier callers of `key`, holding no database
  lock: for an optimistic read-modify-write (read, ask a `before_*` hook with
  no lock held, then write under `Gamend.Lock.serialize/3` only if the row is
  unchanged). Without it, concurrent callers read together, and each round
  only one write lands while the rest find the row changed and read again in
  lockstep, so a burst of ten exhausts a few attempts. In line, each reads what
  the one before it wrote; the compare still catches other writers and nodes.

  Inside a transaction it runs `fun` at once: waiting in a line while holding
  the write lock can deadlock against whoever is first in it (see
  `Gamend.Lock.serialize/3`).
  """
  @spec in_turn(term(), (-> result)) :: result when result: term()
  def in_turn(key, fun) when is_function(fun, 0) do
    if Gamend.Repo.in_transaction?(), do: fun.(), else: trans_on_node(key, fun)
  end

  defp hold(key, fun, fallback) do
    held = Process.get(__MODULE__, %{})

    cond do
      Map.has_key?(held, key) ->
        fun.()

      Queue.running?() ->
        :ok = Queue.acquire(key)
        Process.put(__MODULE__, Map.put(held, key, true))

        try do
          fun.()
        after
          Process.put(__MODULE__, Map.delete(Process.get(__MODULE__, %{}), key))
          Queue.release(key)
        end

      true ->
        fallback.()
    end
  end
end
