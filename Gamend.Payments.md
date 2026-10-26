# `Gamend.Payments`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments.ex#L1)

Payment catalog, purchase ledger, and entitlements.

Provider-specific integrations validate or create transactions, but this
context remains the source of truth for what a user owns inside the game.

# `admin_refund_stripe_purchase`

# `admin_stats`

# `admin_stripe_refundable?`

# `cancel_stripe_subscription_at_period_end`

# `change_stripe_subscription`

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

# `entitlement_ever?`

```elixir
@spec entitlement_ever?(Ecto.UUID.t(), String.t()) :: boolean()
```

Whether the user has EVER held `key`, active or not. What a once-per-account
grant (a trial) checks, since the row outlives its end.

# `entitlement_key`

```elixir
@spec entitlement_key(Gamend.Payments.Product.t(), String.t() | nil) :: String.t()
```

The entitlement key a purchase of `product` for `subject` grants: the
product's own, or `"<key>:<subject>"` for a per-subject product.

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

# `get_user_entitlement_by_key`

```elixir
@spec get_user_entitlement_by_key(Ecto.UUID.t(), String.t()) ::
  Gamend.Payments.Entitlement.t() | nil
```

The user's `key` row, active or not, or `nil`.

# `grant_entitlement`

```elixir
@spec grant_entitlement(Ecto.UUID.t(), String.t(), keyword()) ::
  {:ok, Gamend.Payments.Entitlement.t()} | {:error, term()}
```

Grant an entitlement without a purchase: a trial, a contributor's reward,
a support gesture. Upserts the one `(user, key)` row.

Never shortens what the user already has: an active row with no end (a
lifetime purchase) keeps no end, and an active row ending later than
`:expires_at` keeps its later end. A row a purchase created keeps its
`source_purchase_id`, so its provider sync still finds it.

Options: `:expires_at` (a `DateTime`, `nil` for no end), `:metadata` (a map
merged into the row's, e.g. `%{"source" => "trial", "granted_by" => id}`).

# `handle_apple_webhook`

# `handle_google_webhook`

# `handle_stripe_webhook`

# `has_entitlement?`

```elixir
@spec has_entitlement?(Ecto.UUID.t(), String.t()) :: boolean()
```

Whether the user holds `key` right now: an active row with no end, or an end
still ahead.

Answered from `entitlement_rows/1`, so a page asking about several keys (a
paid plan and its trial, on every render) costs one query between changes.

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

# `per_subject?`

```elixir
@spec per_subject?(Gamend.Payments.Product.t()) :: boolean()
```

Whether a product is sold once per subject rather than once per user
(`grant_config["per_subject"]`): a subscription per hosted server, a pass
per character. Its entitlement is `"<key>:<subject>"`, the subject being
the purchase's `metadata["subject"]`, so one user may hold it for several
subjects. Plan upgrades (`Upgrades`) never apply to one.

# `product_entitlement_key`

```elixir
@spec product_entitlement_key(Gamend.Payments.Product.t()) :: String.t()
```

# `provider_adapter_statuses`

# `provider_error_code`

```elixir
@spec provider_error_code(term()) :: String.t()
```

A short code for a failure, for a counter's dimension: Stripe's own error
code when it sent one (`card_declined`, `resource_missing`), the atom for
ours, never the message.

# `purchase_entitlement_key`

```elixir
@spec purchase_entitlement_key(Gamend.Payments.Purchase.t()) :: String.t()
```

The entitlement key a purchase grants (`entitlement_key/2`).

# `reconcile_stripe_purchase`

# `record_provider_event`

```elixir
@spec record_provider_event(String.t(), String.t(), String.t(), map(), map()) ::
  {:ok, Gamend.Payments.ProviderEvent.t(), boolean()}
  | {:error, Ecto.Changeset.t()}
```

# `refund_stripe_purchase`

# `refund_window_days`

# `restore_purchase`

```elixir
@spec restore_purchase(Gamend.Payments.Purchase.t(), map()) ::
  {:ok, Gamend.Payments.Purchase.t()} | {:ok, :unchanged} | {:error, term()}
```

Hand a purchase back after a dispute the seller won: the purchase completes
again and its entitlements are active again, with the end they had. Only a
purchase a dispute revoked (`metadata["revocation_reason"]` a
`charge.dispute.*` event) — a refund is final. `{:ok, :unchanged}` for any
other.

# `resume_stripe_subscription`

# `revoke_purchase`

```elixir
@spec revoke_purchase(Gamend.Payments.Purchase.t(), map()) ::
  {:ok, Gamend.Payments.Purchase.t()} | {:error, term()}
```

# `stripe_config_status`

# `stripe_customer_id`

# `stripe_refundable?`

# `subject`

```elixir
@spec subject(map() | nil) :: String.t() | nil
```

The subject a purchase's or a checkout's `metadata` names, or nil.

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
