defmodule Gamend.Lock do
  @moduledoc ~S"""
  Serialized execution using database-level advisory locks.

  Wraps a function in a `Repo.transaction` with an advisory lock so that
  only one process at a time can execute the critical section for a given
  `(namespace, resource_id)` pair.

  This is useful for game RPCs where multiple players may trigger the same
  operation concurrently (e.g. guessing a word, claiming a reward) and the
  logic involves read-modify-write on KV entries or lobby metadata.

  ## How it works

  Serialized on **both** adapters, per key, by different mechanisms:

    * **PostgreSQL** — `pg_advisory_xact_lock` inside the transaction, taken
      after a node-local mutex so a node's own waiters queue in the BEAM rather
      than each holding a pooled connection while blocked.
    * **SQLite** — `Gamend.Lock.Local`, a `:global` mutex taken *around* the
      transaction, since SQLite has no advisory locks and its single-writer rule
      covers neither a read-modify-write across statements nor a critical
      section that never touches the database.

  `default_transaction_mode: :immediate` is a backstop for callers who forget
  this function, not the mechanism — it does nothing for ETS or process state.

  ## Nesting

  Take the lock at the outermost point. A `serialize/3` reached inside an open
  transaction cannot take the mutex — the caller holds the write lock, so
  waiting on a mutex whose holder wants that lock deadlocks — so it runs under
  the outer transaction and relies on the outer lock.

  ## Effects

  `serialize/3` is a `Gamend.AfterCommit` scope: broadcasts, hook tasks
  (`Gamend.Async.run/1`) and anything else deferred inside `fun` run once the
  transaction has committed and the lock is released. Keep `fun` to database
  work. Anything slow in it (hashing a password, a plugin's `before_*` hook,
  an HTTP call) holds the lock and, on SQLite, the only connection: do it
  before, and re-check inside only what the lock protects.

  ## Prefer an atomic write

  Prefer an atomic write where one exists: `Economy.spend/4` does
  `balance = balance - x where balance >= x` in one statement, which needs no
  lock at all.

  ## Multi-node safety

  Both paths are cluster-wide: the Postgres lock lives in the shared database,
  and `:global.trans` coordinates across connected nodes. A netsplit can produce
  two holders on either path, which is why value operations must also be atomic.

  ## Namespace conventions

  The `namespace` argument can be:

  - A **registered atom**: `:lobby` (1), `:group` (2), `:party` (3), … — the
    full list is `@namespaces` in `Gamend.Repo.AdvisoryLock`
  - An **arbitrary string**: hashed to a stable integer, e.g. `"word_guessed"`

  The `resource_id` is typically the lobby, group, or user id that scopes
  the lock.

  ## Examples

      # Serialize all "word_guessed" RPCs per lobby
      Gamend.Lock.serialize("word_guessed", lobby_id, fn ->
        {:ok, entry} = Gamend.KV.get("game_state", lobby_id: lobby_id)
        new_val = Map.update(entry.value, "guessed", [word], &[word | &1])
        Gamend.KV.put("game_state", new_val, %{}, lobby_id: lobby_id)
      end)

      # Using a predefined atom namespace
      Gamend.Lock.serialize(:lobby, lobby_id, fn ->
        # exclusive per-lobby operation
      end)

  ## Return value

  Returns `{:ok, result}` where `result` is the return value of the function,
  or `{:error, reason}` if the transaction rolls back.


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    Runs `fun` holding the `(namespace, resource_id)` lock but not inside a
    transaction: for a job that must run once cluster-wide and makes its own
    short writes, such as `Gamend.Tournaments.tick/1`. Each write inside commits,
    and runs its deferred effects, by itself.
    
    A transaction held across the whole job kept every row it touched locked
    until the end and, on SQLite, the database's single write lock with them.
    
      * **SQLite** — the mutex alone gives the once-only guarantee: SQLite is one
        node.
      * **Postgres** — a session-level advisory lock on a checked-out
        connection, which `fun` then runs on, committing as it goes. It holds one
        pooled connection for the job, not a transaction. If the caller dies,
        DBConnection closes that connection, which releases the lock.
    
    Returns `{:ok, result}`. Inside an open transaction it is `serialize/3`.
    
  """
  @spec exclusive(atom() | String.t(), String.t(), (-> result)) ::
          {:ok, result} | {:error, term()}
        when result: term()
  def exclusive(_namespace, _resource_id, _fun) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Lock.exclusive/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Execute `fun` inside a transaction with an advisory lock on `(namespace, resource_id)`.
    
    Only one process at a time can hold the lock for a given key pair. Other
    callers block until the lock is released (on transaction commit/rollback).
    
    Returns `{:ok, result}` on success or `{:error, reason}` on rollback.
    
    ## Parameters
    
    - `namespace` — atom (`:lobby`, `:group`, `:party`) or any string
    - `resource_id` — id of the specific resource (e.g. lobby id)
    - `fun` — zero-arity function to execute while holding the lock
    
  """
  @spec serialize(atom() | String.t(), String.t(), (-> result)) ::
          {:ok, result} | {:error, term()}
        when result: term()
  def serialize(_namespace, _resource_id, _fun) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Lock.serialize/3 is a stub - only available at runtime on Gamend"
    end
  end
end
