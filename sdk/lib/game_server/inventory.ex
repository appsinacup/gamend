defmodule GameServer.Inventory do
  @moduledoc ~S"""
  Player item stacks — the non-fungible companion to `GameServer.Economy`.
  
  Items are free-form string codes (`"health_potion"`, `"sword"`, `"card_374"`);
  each `(user, item)` pair holds a quantity and per-stack `metadata`. Grants and
  consumes are atomic — a consume can never take a stack below zero — and every
  change is recorded in the `inventory_ledger`.
  
  ## Usage (server-side / hooks)
  
      Inventory.grant_item(user_id, "health_potion", 3)
      case Inventory.consume_item(user_id, "health_potion", 1) do
        {:ok, remaining} -> :ok
        {:error, :insufficient_items} -> :none_left
      end
  
      Inventory.quantity(user_id, "health_potion")  #=> 2
      Inventory.inventory(user_id)                  #=> %{"health_potion" => 2}
  
  ## Idempotency
  
  Pass `:idempotency_key` so a retried request (network retry, at-least-once
  job) can't double-apply — the second call is a no-op that returns the current
  quantity:
  
      Inventory.grant_item(user_id, "loot_crate", 1, idempotency_key: "quest:#{progress_id}:1")
  
  Like the economy these are **server-authoritative**: expose them from hooks and
  admin tools, never as a raw client "give me items" endpoint.
  

  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the GameServer.
  """

  @type item() :: String.t()
  @type user_id() :: Ecto.UUID.t()

  @doc ~S"""
    Remove `qty` of `item`, atomically. `{:error, :insufficient_items}` if the user
    doesn't hold enough — the stack never goes negative.
    
  """
  @spec consume_item(user_id(), item(), pos_integer(), keyword()) ::
  {:ok, non_neg_integer()} | {:error, :insufficient_items | term()}
  def consume_item(_user_id, _item, _qty, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Inventory.consume_item/4 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Add `qty` of `item` to a user's inventory.
    
    Options: `:reason` (ledger label), `:idempotency_key`, `:metadata`.
    Returns `{:ok, new_quantity}`.
    
  """
  @spec grant_item(user_id(), item(), pos_integer(), keyword()) ::
  {:ok, non_neg_integer()} | {:error, term()}
  def grant_item(_user_id, _item, _qty, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Inventory.grant_item/4 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    All held items for a user, as a `%{item => quantity}` map.
  """
  @spec inventory(user_id()) :: %{required(item()) => non_neg_integer()}
  def inventory(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Inventory.inventory/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Quantity of one item a user holds (0 when they have none).
  """
  @spec quantity(user_id(), item()) :: non_neg_integer()
  def quantity(_user_id, _item) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Inventory.quantity/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Set (overwrite) the per-stack metadata for a user's item.
  """
  @spec set_metadata(user_id(), item(), map()) :: {:ok, map()} | {:error, term()}
  def set_metadata(_user_id, _item, _metadata) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Inventory.set_metadata/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Subscribe the calling process to a user's live inventory updates.
  """
  @spec subscribe(user_id()) :: :ok | {:error, term()}
  def subscribe(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Inventory.subscribe/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Stop receiving a user's inventory updates.
  """
  @spec unsubscribe(user_id()) :: :ok
  def unsubscribe(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Inventory.unsubscribe/1 is a stub - only available at runtime on GameServer"
    end
  end

end
