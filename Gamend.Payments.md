# `Gamend.Payments`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments.ex#L1)

Payment catalog, purchase ledger, and entitlements.

Provider-specific integrations validate or create transactions, but this
context remains the source of truth for what a user owns inside the game.

# `admin_stats`

# `cancel_stripe_subscription_at_period_end`

# `count_catalog`

```elixir
@spec count_catalog(String.t() | nil) :: non_neg_integer()
```

Counts `list_catalog/2`'s entries.

# `count_entitlements`

# `count_products`

# `count_provider_events`

# `count_provider_products`

# `count_purchases`

# `count_reconciliation_cursors`

# `count_user_entitlements`

```elixir
@spec count_user_entitlements(Ecto.UUID.t(), keyword()) :: non_neg_integer()
```

Counts `list_user_entitlements/2`'s entitlements; takes `:include_inactive`.

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

# `create_stripe_billing_portal`

# `create_stripe_checkout`

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

# `handle_google_webhook`

# `handle_stripe_webhook`

# `has_entitlement?`

```elixir
@spec has_entitlement?(Ecto.UUID.t(), String.t()) :: boolean()
```

# `list_admin_entitlements`

# `list_admin_products`

# `list_admin_provider_products`

# `list_admin_purchases`

# `list_catalog`

```elixir
@spec list_catalog(String.t() | nil, keyword()) :: [
  Gamend.Payments.ProviderProduct.t()
]
```

Active catalog entries, optionally for one provider. Pass `:page` and
`:page_size` for one page; without them, every entry.

# `list_products`

```elixir
@spec list_products(keyword()) :: [Gamend.Payments.Product.t()]
```

# `list_provider_events`

# `list_reconciliation_cursors`

# `list_user_entitlements`

```elixir
@spec list_user_entitlements(Ecto.UUID.t(), keyword()) :: [
  Gamend.Payments.Entitlement.t()
]
```

The user's entitlements, by key: active ones only unless
`include_inactive: true`. Pass `:page` and `:page_size` for one page.

# `list_user_purchases`

```elixir
@spec list_user_purchases(Ecto.UUID.t(), keyword()) :: [Gamend.Payments.Purchase.t()]
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

# `reconcile_stripe_purchase`

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

# `stripe_customer_id`

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
