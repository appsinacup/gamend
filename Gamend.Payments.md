# `Gamend.Payments`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments.ex#L1)

Payment catalog, purchase ledger, and entitlements.

Provider-specific integrations validate or create transactions, but this
context remains the source of truth for what a user owns inside the game.

# `admin_stats`

```elixir
@spec admin_stats() :: map()
```

# `cancel_stripe_subscription_at_period_end`

```elixir
@spec cancel_stripe_subscription_at_period_end(
  Gamend.Accounts.User.t(),
  Ecto.UUID.t()
) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     entitlement: Gamend.Payments.Entitlement.t(),
     stripe_subscription: map()
   }}
  | {:error, term()}
```

# `count_entitlements`

```elixir
@spec count_entitlements(keyword()) :: non_neg_integer()
```

# `count_products`

```elixir
@spec count_products(keyword()) :: non_neg_integer()
```

# `count_provider_events`

```elixir
@spec count_provider_events(keyword()) :: non_neg_integer()
```

# `count_provider_products`

```elixir
@spec count_provider_products(keyword()) :: non_neg_integer()
```

# `count_purchases`

```elixir
@spec count_purchases(keyword()) :: non_neg_integer()
```

# `count_reconciliation_cursors`

```elixir
@spec count_reconciliation_cursors(keyword()) :: non_neg_integer()
```

# `create_product`

```elixir
@spec create_product(map()) ::
  {:ok, Gamend.Payments.Product.t()} | {:error, Ecto.Changeset.t()}
```

# `create_provider_product`

```elixir
@spec create_provider_product(map()) ::
  {:ok, Gamend.Payments.ProviderProduct.t()} | {:error, Ecto.Changeset.t()}
```

# `create_purchase`

```elixir
@spec create_purchase(
  Gamend.Accounts.User.t(),
  Gamend.Payments.ProviderProduct.t(),
  map()
) ::
  {:ok, Gamend.Payments.Purchase.t()} | {:error, Ecto.Changeset.t()}
```

# `create_steam_checkout`

```elixir
@spec create_steam_checkout(Gamend.Accounts.User.t(), map()) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     provider_transaction_id: String.t() | nil,
     steam_url: String.t() | nil
   }}
  | {:error, term()}
```

# `create_stripe_checkout`

```elixir
@spec create_stripe_checkout(Gamend.Accounts.User.t(), map()) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     checkout_url: String.t(),
     provider_session_id: String.t()
   }}
  | {:error, term()}
```

# `finalize_steam_purchase`

```elixir
@spec finalize_steam_purchase(Gamend.Accounts.User.t(), map()) ::
  {:ok, %{purchase: Gamend.Payments.Purchase.t()}} | {:error, term()}
```

# `fulfill_purchase`

```elixir
@spec fulfill_purchase(Gamend.Payments.Purchase.t(), map()) ::
  {:ok, Gamend.Payments.Purchase.t()} | {:error, term()}
```

# `get_product`

```elixir
@spec get_product(Ecto.UUID.t()) :: Gamend.Payments.Product.t() | nil
```

# `get_product_by_sku`

```elixir
@spec get_product_by_sku(String.t()) :: Gamend.Payments.Product.t() | nil
```

# `get_provider_product`

```elixir
@spec get_provider_product(Ecto.UUID.t()) :: Gamend.Payments.ProviderProduct.t() | nil
```

# `get_provider_product`

```elixir
@spec get_provider_product(String.t(), String.t()) ::
  Gamend.Payments.ProviderProduct.t() | nil
```

# `get_purchase`

```elixir
@spec get_purchase(Ecto.UUID.t()) :: Gamend.Payments.Purchase.t() | nil
```

# `get_purchase_by_order_id`

```elixir
@spec get_purchase_by_order_id(String.t()) :: Gamend.Payments.Purchase.t() | nil
```

# `get_purchase_by_provider_original_transaction`

```elixir
@spec get_purchase_by_provider_original_transaction(String.t(), String.t()) ::
  Gamend.Payments.Purchase.t() | nil
```

# `get_purchase_by_provider_transaction`

```elixir
@spec get_purchase_by_provider_transaction(String.t(), String.t()) ::
  Gamend.Payments.Purchase.t() | nil
```

# `handle_apple_webhook`

```elixir
@spec handle_apple_webhook(binary()) :: {:ok, atom()} | {:error, term()}
```

# `handle_google_webhook`

```elixir
@spec handle_google_webhook(binary(), binary() | nil) ::
  {:ok, atom()} | {:error, term()}
```

# `handle_stripe_webhook`

```elixir
@spec handle_stripe_webhook(binary(), binary() | nil) ::
  {:ok, atom()} | {:error, term()}
```

# `has_entitlement?`

```elixir
@spec has_entitlement?(Ecto.UUID.t(), String.t()) :: boolean()
```

# `list_admin_entitlements`

```elixir
@spec list_admin_entitlements(keyword()) :: [Gamend.Payments.Entitlement.t()]
```

# `list_admin_products`

```elixir
@spec list_admin_products(keyword()) :: [Gamend.Payments.Product.t()]
```

# `list_admin_provider_products`

```elixir
@spec list_admin_provider_products(keyword()) :: [Gamend.Payments.ProviderProduct.t()]
```

# `list_admin_purchases`

```elixir
@spec list_admin_purchases(keyword()) :: [Gamend.Payments.Purchase.t()]
```

# `list_catalog`

```elixir
@spec list_catalog(String.t() | nil) :: [Gamend.Payments.ProviderProduct.t()]
```

# `list_products`

```elixir
@spec list_products(keyword()) :: [Gamend.Payments.Product.t()]
```

# `list_provider_events`

```elixir
@spec list_provider_events(keyword()) :: [Gamend.Payments.ProviderEvent.t()]
```

# `list_reconciliation_cursors`

```elixir
@spec list_reconciliation_cursors(keyword()) :: [
  Gamend.Payments.ReconciliationCursor.t()
]
```

# `list_user_entitlements`

```elixir
@spec list_user_entitlements(
  Ecto.UUID.t(),
  keyword()
) :: [Gamend.Payments.Entitlement.t()]
```

# `list_user_purchases`

```elixir
@spec list_user_purchases(
  Ecto.UUID.t(),
  keyword()
) :: [Gamend.Payments.Purchase.t()]
```

# `mark_event_processed`

```elixir
@spec mark_event_processed(Gamend.Payments.ProviderEvent.t()) ::
  {:ok, Gamend.Payments.ProviderEvent.t()} | {:error, Ecto.Changeset.t()}
```

Stamp a provider event as fully handled. Only then does a retry of the same
event id count as a duplicate.

# `product_entitlement_key`

```elixir
@spec product_entitlement_key(Gamend.Payments.Product.t()) :: String.t()
```

# `provider_adapter_statuses`

```elixir
@spec provider_adapter_statuses() :: [map()]
```

# `reconcile_stripe_purchase`

```elixir
@spec reconcile_stripe_purchase(Gamend.Payments.Purchase.t()) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     result: atom(),
     stripe_session: map()
   }}
  | {:error, term()}
```

# `record_provider_event`

```elixir
@spec record_provider_event(String.t(), String.t(), String.t(), map(), map()) ::
  {:ok, Gamend.Payments.ProviderEvent.t(), boolean()}
  | {:error, Ecto.Changeset.t()}
```

# `revoke_purchase`

```elixir
@spec revoke_purchase(Gamend.Payments.Purchase.t(), map()) ::
  {:ok, Gamend.Payments.Purchase.t()} | {:error, term()}
```

# `stripe_config_status`

```elixir
@spec stripe_config_status() :: map()
```

# `update_product`

```elixir
@spec update_product(Gamend.Payments.Product.t(), map()) ::
  {:ok, Gamend.Payments.Product.t()} | {:error, Ecto.Changeset.t()}
```

# `update_provider_product`

```elixir
@spec update_provider_product(Gamend.Payments.ProviderProduct.t(), map()) ::
  {:ok, Gamend.Payments.ProviderProduct.t()} | {:error, Ecto.Changeset.t()}
```

# `validate_store_purchase`

```elixir
@spec validate_store_purchase(Gamend.Accounts.User.t(), String.t(), map()) ::
  {:ok, %{purchase: Gamend.Payments.Purchase.t(), seen_before: boolean()}}
  | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
