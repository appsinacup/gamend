defmodule Gamend.Lock.Local do
  @moduledoc """
  Reentrant, cluster-wide keyed mutex — the non-Postgres half of
  `Gamend.Lock.serialize/3`.

  `:global` shares a lock between holders with the same *requester*, so the
  resource goes in the resource slot and `self()` in the requester slot. Putting
  the protected id in the requester slot lets two concurrent requests for it
  both acquire — the exact case the lock exists to prevent.

  `self()` also makes it reentrant, which core needs: the matchmaking sweep
  takes a lock and then creates a match, which takes one again. `:global`
  releases on process death.
  """

  @doc "Runs `fun` holding the lock for `key`. Blocks; reentrant within a process."
  @spec trans(term(), (-> result)) :: result when result: term()
  def trans(key, fun) when is_function(fun, 0) do
    :global.trans({{__MODULE__, key}, self()}, fun)
  end

  @doc """
  As `trans/2`, on this node only. On Postgres the advisory lock is the
  cluster-wide one; this queues a node's own callers in the BEAM, where waiting
  is free, instead of each holding a pooled connection blocked on the database.
  """
  @spec trans_on_node(term(), (-> result)) :: result when result: term()
  def trans_on_node(key, fun) when is_function(fun, 0) do
    :global.trans({{__MODULE__, key}, self()}, fun, [node()])
  end
end
