defmodule Gamend.Economy do
  @moduledoc ~S"""
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

      Economy.grant(user_id, "gems", 5, idempotency_key: "purchase:#{order_id}")

  ## Safety

  These are **server-authoritative**: expose them from hooks and admin tools,
  never as a raw client "add currency" endpoint. Clients only read their wallet.


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @type currency() :: String.t()
  @type user_id() :: Ecto.UUID.t()

  @doc ~S"""
    Current balance of one currency (0 when the user has no wallet for it).
  """
  @spec balance(user_id(), currency()) :: non_neg_integer()
  def balance(_user_id, _currency) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Economy.balance/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    All of a user's balances, as a `%{currency => balance}` map.
  """
  @spec balances(user_id()) :: %{required(currency()) => non_neg_integer()}
  def balances(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Economy.balances/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Add `amount` of `currency` to a user's wallet.
    
    Options: `:reason` (ledger label), `:idempotency_key`, `:metadata`.
    Returns `{:ok, new_balance}`.
    
  """
  @spec grant(user_id(), currency(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def grant(_user_id, _currency, _amount, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Economy.grant/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Remove `amount` of `currency` from a user's wallet, atomically.
    
    Returns `{:ok, new_balance}` or `{:error, :insufficient_funds}` — the balance
    is never left negative.
    
  """
  @spec spend(user_id(), currency(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :insufficient_funds | term()}
  def spend(_user_id, _currency, _amount, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Economy.spend/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe the calling process to a user's live wallet updates.
  """
  @spec subscribe(user_id()) :: :ok | {:error, term()}
  def subscribe(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Economy.subscribe/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Stop receiving a user's wallet updates.
  """
  @spec unsubscribe(user_id()) :: :ok
  def unsubscribe(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Economy.unsubscribe/1 is a stub - only available at runtime on Gamend"
    end
  end
end
