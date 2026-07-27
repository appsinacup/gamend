defmodule GameServer.Payments do
  @moduledoc ~S"""
  Payment catalog, purchase ledger, and entitlements.
  
  Provider-specific integrations validate or create transactions, but this
  context remains the source of truth for what a user owns inside the game.
  

  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the GameServer.
  """



  @doc false
  @spec admin_stats() :: map()
  def admin_stats() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "GameServer.Payments.admin_stats/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec cancel_stripe_subscription_at_period_end(GameServer.Accounts.User.t(), Ecto.UUID.t()) ::
  {:ok,
   %{
     purchase: GameServer.Payments.Purchase.t(),
     entitlement: GameServer.Payments.Entitlement.t(),
     stripe_subscription: map()
   }}
  | {:error, term()}
  def cancel_stripe_subscription_at_period_end(_user, _entitlement_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Payments.cancel_stripe_subscription_at_period_end/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec count_entitlements(keyword()) :: non_neg_integer()
  def count_entitlements(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Payments.count_entitlements/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec count_products(keyword()) :: non_neg_integer()
  def count_products(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Payments.count_products/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec count_provider_events(keyword()) :: non_neg_integer()
  def count_provider_events(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Payments.count_provider_events/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec count_provider_products(keyword()) :: non_neg_integer()
  def count_provider_products(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Payments.count_provider_products/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec count_purchases(keyword()) :: non_neg_integer()
  def count_purchases(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Payments.count_purchases/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec count_reconciliation_cursors(keyword()) :: non_neg_integer()
  def count_reconciliation_cursors(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Payments.count_reconciliation_cursors/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec create_product(map()) :: {:ok, GameServer.Payments.Product.t()} | {:error, Ecto.Changeset.t()}
  def create_product(_attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.create_product/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec create_provider_product(map()) ::
  {:ok, GameServer.Payments.ProviderProduct.t()} | {:error, Ecto.Changeset.t()}
  def create_provider_product(_attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.create_provider_product/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec create_purchase(GameServer.Accounts.User.t(), GameServer.Payments.ProviderProduct.t(), map()) ::
  {:ok, GameServer.Payments.Purchase.t()} | {:error, Ecto.Changeset.t()}
  def create_purchase(_user, _provider_product, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.create_purchase/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec create_steam_checkout(GameServer.Accounts.User.t(), map()) ::
  {:ok,
   %{
     purchase: GameServer.Payments.Purchase.t(),
     provider_transaction_id: String.t() | nil,
     steam_url: String.t() | nil
   }}
  | {:error, term()}
  def create_steam_checkout(_user, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.create_steam_checkout/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec create_stripe_checkout(GameServer.Accounts.User.t(), map()) ::
  {:ok,
   %{
     purchase: GameServer.Payments.Purchase.t(),
     checkout_url: String.t(),
     provider_session_id: String.t()
   }}
  | {:error, term()}
  def create_stripe_checkout(_user, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.create_stripe_checkout/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec finalize_steam_purchase(GameServer.Accounts.User.t(), map()) ::
  {:ok, %{purchase: GameServer.Payments.Purchase.t()}} | {:error, term()}
  def finalize_steam_purchase(_user, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.finalize_steam_purchase/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec fulfill_purchase(GameServer.Payments.Purchase.t(), map()) ::
  {:ok, GameServer.Payments.Purchase.t()} | {:error, term()}
  def fulfill_purchase(_purchase, _provider_payload) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.fulfill_purchase/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_product(Ecto.UUID.t()) :: GameServer.Payments.Product.t() | nil
  def get_product(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Payments.Product{id: "", sku: "", title: "", description: "", kind: "entitlement", active: true, grant_config: %{}, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Payments.get_product/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_product_by_sku(String.t()) :: GameServer.Payments.Product.t() | nil
  def get_product_by_sku(_sku) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Payments.Product{id: "", sku: "", title: "", description: "", kind: "entitlement", active: true, grant_config: %{}, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Payments.get_product_by_sku/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_provider_product(Ecto.UUID.t()) :: GameServer.Payments.ProviderProduct.t() | nil
  def get_provider_product(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Payments.get_provider_product/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_provider_product(String.t(), String.t()) :: GameServer.Payments.ProviderProduct.t() | nil
  def get_provider_product(_provider, _external_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Payments.get_provider_product/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_purchase(Ecto.UUID.t()) :: GameServer.Payments.Purchase.t() | nil
  def get_purchase(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Payments.get_purchase/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_purchase_by_order_id(String.t()) :: GameServer.Payments.Purchase.t() | nil
  def get_purchase_by_order_id(_order_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Payments.get_purchase_by_order_id/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_purchase_by_provider_original_transaction(String.t(), String.t()) ::
  GameServer.Payments.Purchase.t() | nil
  def get_purchase_by_provider_original_transaction(_provider, _transaction_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Payments.get_purchase_by_provider_original_transaction/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_purchase_by_provider_transaction(String.t(), String.t()) ::
  GameServer.Payments.Purchase.t() | nil
  def get_purchase_by_provider_transaction(_provider, _transaction_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Payments.get_purchase_by_provider_transaction/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec handle_apple_webhook(binary()) :: {:ok, atom()} | {:error, term()}
  def handle_apple_webhook(_raw_body) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.handle_apple_webhook/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec handle_google_webhook(binary(), binary() | nil) :: {:ok, atom()} | {:error, term()}
  def handle_google_webhook(_raw_body, _authorization_header) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.handle_google_webhook/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec handle_stripe_webhook(binary(), binary() | nil) :: {:ok, atom()} | {:error, term()}
  def handle_stripe_webhook(_raw_body, _signature) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.handle_stripe_webhook/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec has_entitlement?(Ecto.UUID.t(), String.t()) :: boolean()
  def has_entitlement?(_user_id, _key) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "GameServer.Payments.has_entitlement?/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_admin_entitlements(keyword()) :: [GameServer.Payments.Entitlement.t()]
  def list_admin_entitlements(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Payments.list_admin_entitlements/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_admin_products(keyword()) :: [GameServer.Payments.Product.t()]
  def list_admin_products(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Payments.list_admin_products/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_admin_provider_products(keyword()) :: [GameServer.Payments.ProviderProduct.t()]
  def list_admin_provider_products(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Payments.list_admin_provider_products/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_admin_purchases(keyword()) :: [GameServer.Payments.Purchase.t()]
  def list_admin_purchases(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Payments.list_admin_purchases/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_catalog(String.t() | nil) :: [GameServer.Payments.ProviderProduct.t()]
  def list_catalog(_provider) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Payments.list_catalog/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_products(keyword()) :: [GameServer.Payments.Product.t()]
  def list_products(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Payments.list_products/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_provider_events(keyword()) :: [GameServer.Payments.ProviderEvent.t()]
  def list_provider_events(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Payments.list_provider_events/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_reconciliation_cursors(keyword()) :: [GameServer.Payments.ReconciliationCursor.t()]
  def list_reconciliation_cursors(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Payments.list_reconciliation_cursors/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_user_entitlements(
  Ecto.UUID.t(),
  keyword()
) :: [GameServer.Payments.Entitlement.t()]
  def list_user_entitlements(_user_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Payments.list_user_entitlements/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_user_purchases(
  Ecto.UUID.t(),
  keyword()
) :: [GameServer.Payments.Purchase.t()]
  def list_user_purchases(_user_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Payments.list_user_purchases/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec product_entitlement_key(GameServer.Payments.Product.t()) :: String.t()
  def product_entitlement_key(_product) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "GameServer.Payments.product_entitlement_key/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec provider_adapter_statuses() :: [map()]
  def provider_adapter_statuses() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "GameServer.Payments.provider_adapter_statuses/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec reconcile_stripe_purchase(GameServer.Payments.Purchase.t()) ::
  {:ok, %{purchase: GameServer.Payments.Purchase.t(), result: atom(), stripe_session: map()}}
  | {:error, term()}
  def reconcile_stripe_purchase(_purchase) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Payments.reconcile_stripe_purchase/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec record_provider_event(String.t(), String.t(), String.t(), map(), map()) ::
  {:ok, GameServer.Payments.ProviderEvent.t(), boolean()} | {:error, Ecto.Changeset.t()}
  def record_provider_event(_provider, _event_id, _event_type, _payload, _metadata) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.record_provider_event/5 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec revoke_purchase(GameServer.Payments.Purchase.t(), map()) ::
  {:ok, GameServer.Payments.Purchase.t()} | {:error, term()}
  def revoke_purchase(_purchase, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.revoke_purchase/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec stripe_config_status() :: map()
  def stripe_config_status() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "GameServer.Payments.stripe_config_status/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec update_product(GameServer.Payments.Product.t(), map()) ::
  {:ok, GameServer.Payments.Product.t()} | {:error, Ecto.Changeset.t()}
  def update_product(_product, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.update_product/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec update_provider_product(GameServer.Payments.ProviderProduct.t(), map()) ::
  {:ok, GameServer.Payments.ProviderProduct.t()} | {:error, Ecto.Changeset.t()}
  def update_provider_product(_provider_product, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.update_provider_product/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec validate_store_purchase(GameServer.Accounts.User.t(), String.t(), map()) ::
  {:ok, %{purchase: GameServer.Payments.Purchase.t(), seen_before: boolean()}} | {:error, term()}
  def validate_store_purchase(_user, _provider, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Payments.validate_store_purchase/3 is a stub - only available at runtime on GameServer"
    end
  end

end
