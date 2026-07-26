defmodule GameServer.Economy do
  @moduledoc """
  Virtual-currency wallets with an append-only ledger.

  Currencies are free-form string codes (`"gold"`, `"gems"`, `"energy"`) — the
  game decides which exist. Every balance change is atomic and recorded in the
  ledger, so two concurrent spends can never overspend and every mutation is
  auditable.

  ## Usage (server-side / hooks)

      Economy.grant(user_id, "gold", 100, reason: "match_reward")
      case Economy.spend(user_id, "gold", 30, reason: "store_purchase") do
        {:ok, balance} -> :ok
        {:error, :insufficient_funds} -> :not_enough_gold
      end

      Economy.balance(user_id, "gold")   #=> 70
      Economy.balances(user_id)          #=> %{"gold" => 70}

  ## Idempotency

  Pass `:idempotency_key` so a retried request (network retry, at-least-once job)
  can't double-apply — the second call is a no-op that returns the current
  balance:

      Economy.grant(user_id, "gems", 5, idempotency_key: "purchase:\#{order_id}")

  ## Safety

  These are **server-authoritative**: expose them from hooks and admin tools,
  never as a raw client "add currency" endpoint. Clients only read their wallet.
  """

  import Ecto.Query

  alias GameServer.Accounts.User
  alias GameServer.Economy.LedgerEntry
  alias GameServer.Economy.Wallet
  alias GameServer.Repo

  @type user_id :: Ecto.UUID.t()
  @type currency :: String.t()

  # ── Reads ───────────────────────────────────────────────────────────────

  @doc "Current balance of one currency (0 when the user has no wallet for it)."
  @spec balance(user_id(), currency()) :: non_neg_integer()
  def balance(user_id, currency) do
    Repo.one(
      from w in Wallet,
        where: w.user_id == ^user_id and w.currency == ^currency,
        select: w.balance
    ) || 0
  end

  @doc "All non-zero balances for a user, as a `%{currency => balance}` map."
  @spec balances(user_id()) :: %{currency() => non_neg_integer()}
  def balances(user_id) do
    from(w in Wallet, where: w.user_id == ^user_id, select: {w.currency, w.balance})
    |> Repo.all()
    |> Map.new()
  end

  # ── Mutations ───────────────────────────────────────────────────────────

  @doc """
  Add `amount` of `currency` to a user's wallet.

  Options: `:reason` (ledger label), `:idempotency_key`, `:metadata`.
  Returns `{:ok, new_balance}`.
  """
  @spec grant(user_id(), currency(), pos_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def grant(user_id, currency, amount, opts \\ []) when is_integer(amount) and amount > 0 do
    change_balance(user_id, currency, amount, opts)
  end

  @doc """
  Remove `amount` of `currency` from a user's wallet, atomically.

  Returns `{:ok, new_balance}` or `{:error, :insufficient_funds}` — the balance
  is never left negative.
  """
  @spec spend(user_id(), currency(), pos_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :insufficient_funds | term()}
  def spend(user_id, currency, amount, opts \\ []) when is_integer(amount) and amount > 0 do
    change_balance(user_id, currency, -amount, opts)
  end

  # Apply a signed delta atomically and record it. The wallet write is a single
  # SQL statement (upsert-inc for grants, conditional decrement for spends), so
  # it's race-free on both Postgres and SQLite without an application lock.
  defp change_balance(user_id, currency, delta, opts) do
    reason = opts |> Keyword.get(:reason, "unspecified") |> to_string()
    idem = Keyword.get(opts, :idempotency_key)
    metadata = Keyword.get(opts, :metadata, %{})

    cond do
      not valid_currency?(currency) ->
        {:error, :invalid_currency}

      idem && idem_applied?(idem) ->
        {:ok, balance(user_id, currency)}

      true ->
        case run_change(user_id, currency, delta, reason, idem, metadata) do
          {:ok, new_balance} = ok ->
            # Post-commit: push to the user's socket and fire the plugin hook.
            broadcast_wallet(user_id, currency, new_balance, delta)

            change = %{
              user_id: user_id,
              currency: currency,
              balance: new_balance,
              delta: delta,
              reason: reason
            }

            GameServer.Async.run(fn ->
              GameServer.Hooks.internal_call(:after_wallet_changed, [change])
            end)

            ok

          other ->
            other
        end
    end
  end

  @topic_prefix "economy:user:"

  @doc "Subscribe the calling process to a user's live wallet updates."
  @spec subscribe(user_id()) :: :ok | {:error, term()}
  def subscribe(user_id), do: Phoenix.PubSub.subscribe(GameServer.PubSub, topic(user_id))

  @doc "Stop receiving a user's wallet updates."
  @spec unsubscribe(user_id()) :: :ok
  def unsubscribe(user_id), do: Phoenix.PubSub.unsubscribe(GameServer.PubSub, topic(user_id))

  defp topic(user_id), do: @topic_prefix <> user_id

  defp broadcast_wallet(user_id, currency, balance, delta) do
    Phoenix.PubSub.broadcast(
      GameServer.PubSub,
      topic(user_id),
      {:wallet_updated, %{currency: currency, balance: balance, delta: delta}}
    )
  end

  defp run_change(user_id, currency, delta, reason, idem, metadata) do
    result =
      Repo.transaction(fn ->
        case apply_delta(user_id, currency, delta) do
          {:ok, new_balance} ->
            record_ledger(user_id, currency, delta, new_balance, reason, idem, metadata)
            new_balance

          {:error, err} ->
            Repo.rollback(err)
        end
      end)

    case result do
      {:ok, new_balance} -> {:ok, new_balance}
      # Lost the race to a concurrent request with the same idempotency key —
      # the other one applied it; return the resulting balance.
      {:error, :idempotent_replay} -> {:ok, balance(user_id, currency)}
      {:error, err} -> {:error, err}
    end
  end

  defp apply_delta(user_id, currency, delta) when delta > 0 do
    on_conflict = from(w in Wallet, update: [inc: [balance: ^delta]])

    %Wallet{}
    |> Wallet.changeset(%{user_id: user_id, currency: currency, balance: delta})
    |> Repo.insert(on_conflict: on_conflict, conflict_target: [:user_id, :currency])
    |> case do
      {:ok, _} -> {:ok, read_balance(user_id, currency)}
      {:error, changeset} -> {:error, {:wallet_error, changeset}}
    end
  end

  defp apply_delta(user_id, currency, delta) when delta < 0 do
    amount = -delta

    {count, _} =
      Repo.update_all(
        from(w in Wallet,
          where: w.user_id == ^user_id and w.currency == ^currency and w.balance >= ^amount
        ),
        inc: [balance: delta]
      )

    case count do
      1 -> {:ok, read_balance(user_id, currency)}
      0 -> {:error, :insufficient_funds}
    end
  end

  defp read_balance(user_id, currency) do
    Repo.one(
      from w in Wallet,
        where: w.user_id == ^user_id and w.currency == ^currency,
        select: w.balance
    ) || 0
  end

  defp record_ledger(user_id, currency, delta, balance_after, reason, idem, metadata) do
    %LedgerEntry{}
    |> LedgerEntry.changeset(%{
      user_id: user_id,
      currency: currency,
      delta: delta,
      balance_after: balance_after,
      reason: reason,
      idempotency_key: idem,
      metadata: metadata
    })
    |> Repo.insert()
    |> case do
      {:ok, entry} ->
        entry

      {:error, changeset} ->
        if Keyword.has_key?(changeset.errors, :idempotency_key),
          do: Repo.rollback(:idempotent_replay),
          else: Repo.rollback({:ledger_error, changeset})
    end
  end

  defp idem_applied?(idem) do
    Repo.exists?(from l in LedgerEntry, where: l.idempotency_key == ^idem)
  end

  defp valid_currency?(currency) do
    is_binary(currency) and byte_size(currency) in 1..64
  end

  # ── Ledger / admin reads ────────────────────────────────────────────────

  @doc false
  @spec list_ledger(keyword()) :: [LedgerEntry.t()]
  def list_ledger(opts \\ []) do
    ledger_query(opts)
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> paginate(opts)
    |> preload(:user)
    |> Repo.all()
  end

  @doc false
  @spec count_ledger(keyword()) :: non_neg_integer()
  def count_ledger(opts \\ []) do
    Repo.aggregate(ledger_query(opts), :count, :id)
  end

  defp ledger_query(opts) do
    LedgerEntry
    |> maybe_filter(:user_id, Keyword.get(opts, :user_id))
    |> maybe_filter(:currency, Keyword.get(opts, :currency))
  end

  @doc false
  @spec list_wallets(keyword()) :: [Wallet.t()]
  def list_wallets(opts \\ []) do
    wallet_query(opts)
    |> order_by([w], asc: w.currency)
    |> paginate(opts)
    |> preload(:user)
    |> Repo.all()
  end

  @doc false
  @spec count_wallets(keyword()) :: non_neg_integer()
  def count_wallets(opts \\ []) do
    Repo.aggregate(wallet_query(opts), :count, :id)
  end

  defp wallet_query(opts) do
    Wallet
    |> maybe_filter(:user_id, Keyword.get(opts, :user_id))
    |> maybe_filter(:currency, Keyword.get(opts, :currency))
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :user_id, value), do: filter_user(query, value)
  defp maybe_filter(query, :currency, value), do: where(query, [q], q.currency == ^value)

  # Accept either an exact user id (UUID) or a username/display-name substring,
  # so an admin can find a wallet without knowing the raw id.
  defp filter_user(query, value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} ->
        where(query, [q], q.user_id == ^uuid)

      :error ->
        pattern = "%" <> Repo.escape_like(String.downcase(value)) <> "%"

        query
        |> join(:inner, [q], u in User, on: u.id == q.user_id)
        |> where(
          [q, u],
          fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.username, ^pattern) or
            fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.display_name, ^pattern)
        )
    end
  end

  defp paginate(query, opts) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 25)
    offset = (page - 1) * page_size

    query |> limit(^page_size) |> offset(^offset)
  end
end
