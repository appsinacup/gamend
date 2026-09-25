defmodule Gamend.Ledger do
  @moduledoc """
  The mechanics both ledgered balances share: `Gamend.Economy` (currency in a
  wallet) and `Gamend.Inventory` (quantity of an item).

  The two contexts are near-isomorphic — the same `run_change`, `apply_delta`,
  `record_ledger`, `idem_applied?` set, differing only in whether the noun is a
  currency or an item. Most of that difference is real: a wallet and an item
  stack are different tables with different constraints, and folding them into
  one generic ledger would trade a little duplication for a lot of indirection.

  What is *not* different is the transaction shape around them, which is what
  lives here:

    * apply the delta and write the ledger row in one transaction;
    * treat a duplicate `idempotency_key` as a replay rather than an error,
      because losing that race means the other request already applied it —
      so the caller should be told the resulting balance, not a failure;
    * roll back anything else.

  Getting that wrong is a double-spend or a phantom grant, so it is worth
  having exactly one copy of it.
  """

  import Ecto.Query, only: [order_by: 3, preload: 2]

  alias Gamend.Repo

  @doc """
  Runs `apply_fun` and `record_fun` in one transaction and normalises the
  result.

  `apply_fun` returns `{:ok, new_total}` or `{:error, reason}`. `record_fun`
  receives the new total and writes the ledger row; it is expected to
  `Repo.rollback(:idempotent_replay)` when the idempotency key already exists.

  `replay_fun` is called only on that replay, to read back the total the
  winning request produced.
  """
  @spec change(
          (-> {:ok, integer()} | {:error, term()}),
          (integer() -> term()),
          (-> integer())
        ) :: {:ok, integer()} | {:error, term()}
  def change(apply_fun, record_fun, replay_fun) do
    # A balance row and its ledger row reference only the user, so a foreign
    # key that fires here means the user was deleted after the context checked.
    Repo.rescue_foreign_key(:user_not_found, fn ->
      Gamend.AfterCommit.transaction(fn ->
        case apply_fun.() do
          {:ok, new_total} ->
            record_fun.(new_total)
            new_total

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
    end)
    |> case do
      {:ok, new_total} -> {:ok, new_total}
      # Lost the race to a concurrent request with the same idempotency key —
      # the other one applied it; return the total it produced.
      {:error, :idempotent_replay} -> {:ok, replay_fun.()}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  A page of ledger entries from `query`, newest first, with the user loaded —
  the admin listing both ledgers expose.
  """
  @spec list_entries(Ecto.Queryable.t(), keyword()) :: [struct()]
  def list_entries(query, opts) do
    query
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> Gamend.Query.page(opts)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Classifies a failed ledger insert: a duplicate idempotency key is a replay,
  anything else is a genuine error. Rolls back either way.
  """
  @spec rollback_insert_error(Ecto.Changeset.t(), atom()) :: no_return()
  def rollback_insert_error(%Ecto.Changeset{} = changeset, error_tag) do
    if Keyword.has_key?(changeset.errors, :idempotency_key),
      do: Repo.rollback(:idempotent_replay),
      else: Repo.rollback({error_tag, changeset})
  end
end
