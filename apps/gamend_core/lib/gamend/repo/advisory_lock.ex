defmodule Gamend.Repo.AdvisoryLock do
  @moduledoc """
  Advisory locking for protecting TOCTOU (Time-of-Check-Time-of-Use) patterns.

  On PostgreSQL, acquires a transaction-scoped advisory lock via
  `pg_advisory_xact_lock(namespace, resource_id)`. The lock is automatically
  released when the enclosing `Repo.transaction` commits or rolls back.

  On SQLite, this function is a no-op, because SQLite has no advisory locks.
  That is a fact about *this function*, not a claim that locking is unnecessary
  there: SQLite serializes each write, which is not the same as serializing a
  read-modify-write spanning statements, and does nothing at all for a critical
  section held over ETS or process state.

  Callers should not use this module directly for that reason. Go through
  `Gamend.Lock.serialize/3`, which picks this on Postgres and a keyed
  `:global` mutex (`Gamend.Lock.Local`) everywhere else, so the guarantee
  holds on both adapters.

  ## Usage

  Always call within a transaction, opened through `Gamend.AfterCommit` so
  broadcasts inside wait for the commit (or use `Gamend.Lock.serialize/3`):

      Gamend.AfterCommit.transaction(fn ->
        AdvisoryLock.lock(:lobby, lobby.id)
        count = count_members(lobby.id)
        if count >= lobby.max_users, do: Repo.rollback(:full)
        do_join(...)
      end)

  ## Namespaces

  Each resource type uses a distinct integer namespace to avoid collisions.
  The registered atoms (`namespaces/0` returns the same map):

  - `:lobby` → 1
  - `:group` → 2
  - `:party` → 3
  - `:friendship` → 4
  - `:tournament_draw` → 5
  - `:tournament_match` → 6
  - `:tournaments_tick` → 7
  - `:matchmaking_sweep` → 8
  - `:quest` → 9
  - `:push_tokens` → 10
  - `:ready_check` → 11
  - `:tournament_join` → 12

  A new atom namespace is added to `@namespaces` (ids 0..99 are reserved for
  atoms).

  You can also pass an arbitrary string as the namespace. The string is
  hashed to a stable 32-bit integer via `:erlang.phash2/2`, so any
  string (e.g. `"word_guessed"`, `"my_rpc"`) works without pre-registration.

  ## Examples

      # Atom namespace (predefined):
      AdvisoryLock.lock(:lobby, lobby_id)

      # String namespace (ad-hoc):
      AdvisoryLock.lock("word_guessed", lobby_id)
  """

  @namespaces %{
    lobby: 1,
    group: 2,
    party: 3,
    friendship: 4,
    tournament_draw: 5,
    tournament_match: 6,
    tournaments_tick: 7,
    matchmaking_sweep: 8,
    quest: 9,
    push_tokens: 10,
    ready_check: 11,
    tournament_join: 12
  }

  # Reserve 0..99 for atom namespaces; string hashes start at 100.
  @string_ns_offset 100

  @doc "The registered lock namespaces and their ids (for introspection)."
  def namespaces, do: @namespaces

  @doc """
  Acquire a transaction-scoped advisory lock for the given resource.

  `namespace` can be a registered atom (see `namespaces/0`) or any arbitrary
  string. `resource_id` is a UUID string; it is hashed to a stable
  32-bit integer for `pg_advisory_xact_lock` (a hash collision only causes
  extra serialization, never lost mutual exclusion).

  Must be called inside a `Repo.transaction`. On PostgreSQL, blocks until
  the lock is available. On SQLite, returns immediately — see the moduledoc.
  """
  @spec lock(atom() | String.t(), String.t()) :: :ok
  def lock(namespace, resource_id) when is_binary(resource_id) do
    maybe_advisory_lock(namespace_id(namespace), hash_resource_id(resource_id))
  end

  @doc """
  Takes the session-level lock for `(namespace, resource_id)` on the current
  connection, waiting as long as it takes. It is held until `unlock_session/2`
  or until the connection closes, not until a transaction ends, for a job that
  commits many transactions of its own under one lock (`Gamend.Lock.exclusive/3`).

  Postgres only. Call it inside `Repo.checkout/2`, so the lock, the work and
  the unlock share one connection. It shares its key space with `lock/2`.
  """
  @spec lock_session(atom() | String.t(), String.t()) :: :ok
  def lock_session(namespace, resource_id) when is_binary(resource_id) do
    Gamend.Repo.query!(
      "SELECT pg_advisory_lock($1, $2)",
      [namespace_id(namespace), hash_resource_id(resource_id)],
      timeout: :infinity
    )

    :ok
  end

  @doc "Releases a lock `lock_session/2` took on this connection."
  @spec unlock_session(atom() | String.t(), String.t()) :: :ok
  def unlock_session(namespace, resource_id) when is_binary(resource_id) do
    Gamend.Repo.query!("SELECT pg_advisory_unlock($1, $2)", [
      namespace_id(namespace),
      hash_resource_id(resource_id)
    ])

    :ok
  end

  @doc """
  The integer namespace `pg_advisory_xact_lock` is called with.

  Public so `Gamend.Lock.serialize/3` can resolve it on *every* adapter, not
  only Postgres. An unregistered atom is a programming error, and it used to
  surface as a `KeyError` from deep inside the Postgres branch — while the
  SQLite branch never calls `lock/2` at all and so never noticed. Anyone
  developing on the default SQLite setup could therefore add a lock with an
  unregistered namespace, watch every local test pass, and only find out on the
  Postgres CI job.
  """
  @spec namespace_id(atom() | String.t()) :: non_neg_integer()
  def namespace_id(namespace) when is_atom(namespace) do
    case Map.fetch(@namespaces, namespace) do
      {:ok, ns} ->
        ns

      :error ->
        raise ArgumentError, """
        unknown advisory-lock namespace #{inspect(namespace)}.

        Atom namespaces are pre-registered in Gamend.Repo.AdvisoryLock so their
        integer ids stay stable across releases. Either add it to @namespaces
        (next free id: #{next_namespace_id()}), or pass a string, which is
        hashed and needs no registration:

            Gamend.Lock.serialize("#{namespace}", resource_id, fun)
        """
    end
  end

  def namespace_id(namespace) when is_binary(namespace) do
    :erlang.phash2(namespace, 2_147_483_547) + @string_ns_offset
  end

  defp next_namespace_id do
    @namespaces |> Map.values() |> Enum.max() |> Kernel.+(1)
  end

  defp hash_resource_id(resource_id), do: :erlang.phash2(resource_id, 2_147_483_647)

  defp maybe_advisory_lock(ns, resource_id) do
    if postgres?() do
      # Use a SAVEPOINT so that if pg_advisory_xact_lock fails (e.g. permission
      # issues), we can ROLLBACK TO SAVEPOINT and leave the transaction valid.
      # Without this, Postgres marks the transaction as aborted and all subsequent
      # SQL in the same transaction fails with 25P02.
      Gamend.Repo.query!("SAVEPOINT advisory_lock")

      try do
        Gamend.Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [ns, resource_id])
        Gamend.Repo.query!("RELEASE SAVEPOINT advisory_lock")
      rescue
        e ->
          Gamend.Repo.query!("ROLLBACK TO SAVEPOINT advisory_lock")
          require Logger

          Logger.error(
            "[advisory_lock] pg_advisory_xact_lock(#{ns}, #{resource_id}) failed — " <>
              "falling back to no-op (no mutual exclusion). " <>
              "This means concurrent operations may race. " <>
              "Cause: #{Exception.message(e)}"
          )
      end
    end

    :ok
  end

  @doc "Returns true if the Repo was compiled with the PostgreSQL adapter."
  @spec postgres?() :: boolean()
  def postgres? do
    # Use Module.concat to build the expected adapter module name at runtime,
    # avoiding a compile-time constant comparison warning when SQLite is the
    # default adapter and Elixir's type checker sees the result as always false.
    postgres_adapter = Module.concat([Ecto, Adapters, Postgres])
    Gamend.Repo.__adapter__() == postgres_adapter
  end
end
