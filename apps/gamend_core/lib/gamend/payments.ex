defmodule Gamend.Payments do
  @moduledoc """
  Payment catalog, purchase ledger, and entitlements.

  Provider-specific integrations validate or create transactions, but this
  context remains the source of truth for what a user owns inside the game.
  """

  import Ecto.Query, warn: false
  require Logger

  use Nebulex.Caching, cache: Gamend.Cache

  alias Gamend.Accounts.User
  alias Gamend.Payments.Admin
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Params
  alias Gamend.Payments.Product
  alias Gamend.Payments.ProviderConfig
  alias Gamend.Payments.ProviderEvent
  alias Gamend.Payments.ProviderProduct
  alias Gamend.Payments.Providers
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.StoreEvents
  alias Gamend.Payments.StripeEvents
  alias Gamend.Repo
  alias Gamend.Repo.AdvisoryLock

  @store_validation_providers ~w(apple google steam)

  # Cached catalog/ledger reads keyed by per-entity version counters bumped on
  # every write to that table via tap_bump/2. Products/provider-products change
  # rarely (kept warm through frequent purchases); purchases have their own
  # version so a buy doesn't evict the catalog.
  defp product_version, do: Gamend.Cache.get!({:payments, :product_version}) || 1

  defp provider_product_version,
    do: Gamend.Cache.get!({:payments, :provider_product_version}) || 1

  defp purchase_version, do: Gamend.Cache.get!({:payments, :purchase_version}) || 1

  @doc false
  def tap_bump({:ok, _} = result, version_key) do
    _ = Gamend.Cache.bump_version(version_key)
    result
  end

  def tap_bump(other, _version_key), do: other

  # ---------------------------------------------------------------------------
  # Catalog
  # ---------------------------------------------------------------------------

  @spec create_product(map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def create_product(attrs) when is_map(attrs) do
    %Product{}
    |> Product.changeset(Params.normalize(attrs))
    |> Repo.insert()
    |> tap_bump({:payments, :product_version})
  end

  @spec update_product(Product.t(), map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def update_product(%Product{} = product, attrs) when is_map(attrs) do
    product
    |> Product.changeset(Params.normalize(attrs))
    |> Repo.update()
    |> tap_bump({:payments, :product_version})
  end

  @spec get_product(Ecto.UUID.t()) :: Product.t() | nil
  @decorate cacheable(
              key: {:payments, :product, product_version(), id},
              match: &(&1 != nil),
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_product(id), do: Repo.get_uuid(Product, id)

  @spec get_product_by_sku(String.t()) :: Product.t() | nil
  def get_product_by_sku(sku) when is_binary(sku), do: Repo.get_by(Product, sku: sku)

  @spec list_products(keyword()) :: [Product.t()]
  def list_products(opts \\ []) do
    include_inactive = Keyword.get(opts, :include_inactive, false)

    Product
    |> maybe_active_only(include_inactive)
    |> order_by([p], asc: p.sku)
    |> Repo.all()
  end

  @spec create_provider_product(map()) ::
          {:ok, ProviderProduct.t()} | {:error, Ecto.Changeset.t()}
  def create_provider_product(attrs) when is_map(attrs) do
    %ProviderProduct{}
    |> ProviderProduct.changeset(Params.normalize(attrs))
    |> Repo.insert()
    |> tap_bump({:payments, :provider_product_version})
  end

  @spec update_provider_product(ProviderProduct.t(), map()) ::
          {:ok, ProviderProduct.t()} | {:error, Ecto.Changeset.t()}
  def update_provider_product(%ProviderProduct{} = provider_product, attrs)
      when is_map(attrs) do
    provider_product
    |> ProviderProduct.changeset(Params.normalize(attrs))
    |> Repo.update()
    |> tap_bump({:payments, :provider_product_version})
  end

  @spec get_provider_product(Ecto.UUID.t()) :: ProviderProduct.t() | nil
  @decorate cacheable(
              key: {:payments, :provider_product, provider_product_version(), id},
              match: &(&1 != nil),
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_provider_product(id) do
    ProviderProduct
    |> Repo.get_uuid(id)
    |> preload_product()
  end

  @spec get_provider_product(String.t(), String.t()) :: ProviderProduct.t() | nil
  def get_provider_product(provider, external_id)
      when is_binary(provider) and is_binary(external_id) do
    ProviderProduct
    |> Repo.get_by(provider: provider, external_id: external_id)
    |> preload_product()
  end

  @doc """
  Active catalog entries, optionally for one provider. Pass `:page` and
  `:page_size` for one page; without them, every entry.
  """
  @spec list_catalog(String.t() | nil, keyword()) :: [ProviderProduct.t()]
  def list_catalog(provider \\ nil, opts \\ []) do
    provider
    |> catalog_query()
    |> order_by([pp, p], asc: pp.provider, asc: p.sku)
    |> preload([pp, p], product: p)
    |> maybe_page(opts)
    |> Repo.all()
  end

  @doc "Counts `list_catalog/2`'s entries."
  @spec count_catalog(String.t() | nil) :: non_neg_integer()
  def count_catalog(provider \\ nil) do
    provider |> catalog_query() |> Repo.aggregate(:count)
  end

  defp catalog_query(provider) do
    query =
      from pp in ProviderProduct,
        join: p in assoc(pp, :product),
        where: pp.active == true and p.active == true

    if is_binary(provider) and provider != "" do
      from pp in query, where: pp.provider == ^provider
    else
      query
    end
  end

  # Paging is opt-in: the store page and downloads want every row.
  defp maybe_page(query, opts) do
    if Keyword.has_key?(opts, :page), do: Gamend.Query.page(query, opts), else: query
  end

  # ---------------------------------------------------------------------------
  # Purchases and fulfillment
  # ---------------------------------------------------------------------------

  # Everything a checkout request may carry. Everything else — amount, currency,
  # status, environment, expiry, order id, the provider transaction ids, the raw
  # provider payload — is ours to decide, and is dropped here.
  #
  # Both checkout controllers pass the whole request body through. With no
  # allowlist, `POST /api/v1/payments/checkout/steam` accepted `"amount": 1` and
  # a cheap `"currency"`, and Steam was asked to charge that: any product, for
  # effectively nothing, ending in a real entitlement and real hook-granted
  # currency. `expires_at` was accepted the same way, turning a subscription
  # into a permanent grant.
  @client_checkout_fields ~w(
    product_sku provider_product_id external_id quantity
    success_url cancel_url steam_id language usersession ipaddress metadata
  )

  @doc false
  def client_checkout_attrs(attrs) when is_map(attrs),
    do: Map.take(attrs, @client_checkout_fields)

  @spec create_purchase(User.t(), ProviderProduct.t(), map()) ::
          {:ok, Purchase.t()} | {:error, Ecto.Changeset.t()}
  def create_purchase(user, %ProviderProduct{} = provider_product, attrs \\ %{}) do
    user_id = user.id
    provider_product = Repo.preload(provider_product, :product)
    attrs = Params.normalize(attrs)
    quantity = Params.parse_positive_int(attrs["quantity"], 1)
    unit_amount = provider_product.unit_amount

    # NOTE: `attrs` here is trusted. The receipt-validation path
    # (`record_validated_purchase/3`) legitimately supplies amount, currency,
    # status, environment and expiry read out of a provider-signed receipt.
    # Attributes that arrive from a *client* are stripped at the checkout entry
    # points instead — see `client_checkout_attrs/1`.
    purchase_attrs =
      attrs
      |> Map.merge(%{
        "user_id" => user_id,
        "product_id" => provider_product.product_id,
        "provider_product_id" => provider_product.id,
        "provider" => provider_product.provider,
        "order_id" => attrs["order_id"] || generate_order_id(),
        "status" => attrs["status"] || "pending",
        "quantity" => quantity,
        "currency" => attrs["currency"] || provider_product.currency,
        "amount" => attrs["amount"] || total_amount(unit_amount, quantity),
        "environment" => attrs["environment"] || ProviderConfig.environment()
      })

    %Purchase{}
    |> Purchase.changeset(purchase_attrs)
    |> Repo.insert()
    |> tap_bump({:payments, :purchase_version})
  end

  @spec get_purchase(Ecto.UUID.t()) :: Purchase.t() | nil
  @decorate cacheable(
              key: {:payments, :purchase, purchase_version(), id},
              match: &(&1 != nil),
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_purchase(id), do: Repo.get_uuid(Purchase, id) |> preload_purchase()

  @spec get_purchase_by_order_id(String.t()) :: Purchase.t() | nil
  def get_purchase_by_order_id(order_id) when is_binary(order_id) do
    Purchase
    |> Repo.get_by(order_id: order_id)
    |> preload_purchase()
  end

  @spec get_purchase_by_provider_transaction(String.t(), String.t()) :: Purchase.t() | nil
  def get_purchase_by_provider_transaction(provider, transaction_id)
      when is_binary(provider) and is_binary(transaction_id) do
    Purchase
    |> Repo.get_by(provider: provider, provider_transaction_id: transaction_id)
    |> preload_purchase()
  end

  @spec get_purchase_by_provider_original_transaction(String.t(), String.t()) ::
          Purchase.t() | nil
  def get_purchase_by_provider_original_transaction(provider, transaction_id)
      when is_binary(provider) and is_binary(transaction_id) do
    Purchase
    |> Repo.get_by(provider: provider, provider_original_transaction_id: transaction_id)
    |> preload_purchase()
  end

  @spec list_user_purchases(Ecto.UUID.t(), keyword()) :: [Purchase.t()]
  def list_user_purchases(user_id, opts \\ []) when is_binary(user_id) do
    limit = opts |> Keyword.get(:limit, 100) |> min(250)

    from(p in Purchase,
      where: p.user_id == ^user_id,
      order_by: [desc: p.inserted_at],
      limit: ^limit,
      preload: [:product, :provider_product]
    )
    |> Repo.all()
  end

  @spec fulfill_purchase(Purchase.t(), map()) :: {:ok, Purchase.t()} | {:error, term()}
  def fulfill_purchase(%Purchase{} = purchase, provider_payload \\ %{})
      when is_map(provider_payload) do
    # Durable, not just transactional: the provider has already taken the
    # player's money by the time this runs, so this commit is the one write in
    # the app that must survive a crash even when `db.postgres_synchronous_commit`
    # is `off` for everything else.
    result =
      Repo.durable_transaction(fn ->
        purchase =
          Purchase
          |> lock_for_update()
          |> Repo.get!(purchase.id)
          |> Repo.preload([:product, :provider_product])

        case purchase.status do
          "completed" ->
            {:ok, purchase, :already_fulfilled}

          status when status in ["refunded", "revoked"] ->
            Repo.rollback({:not_fulfillable, status})

          _ ->
            with {:ok, updated} <- complete_purchase(purchase, provider_payload),
                 :ok <- grant_purchase(updated) do
              {:ok, updated, :fulfilled}
            else
              {:error, reason} -> Repo.rollback(reason)
            end
        end
      end)

    case result do
      {:ok, {:ok, purchase, :fulfilled}} ->
        after_purchase_fulfilled(purchase)
        {:ok, preload_purchase(purchase)}

      {:ok, {:ok, purchase, :already_fulfilled}} ->
        {:ok, preload_purchase(purchase)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec revoke_purchase(Purchase.t(), map()) :: {:ok, Purchase.t()} | {:error, term()}
  def revoke_purchase(%Purchase{} = purchase, attrs \\ %{}) when is_map(attrs) do
    now = DateTime.utc_now(:second)
    attrs = Params.normalize(attrs)

    # A revocation removes entitlements the player paid for; losing it to a
    # crash leaves them holding goods a refund already took back.
    Repo.durable_transaction(fn ->
      purchase =
        Purchase
        |> Repo.get!(purchase.id)
        |> Repo.preload(:product)

      status = attrs["status"] || "revoked"

      {:ok, updated} =
        purchase
        |> Purchase.changeset(%{
          status: status,
          revoked_at: now,
          raw_provider_payload:
            Params.merge_payload(purchase.raw_provider_payload, attrs["payload"] || %{})
        })
        |> Repo.update()
        |> tap_bump({:payments, :purchase_version})

      entitlements = revoke_entitlements_for_purchase(updated, now, attrs["reason"])
      {updated, entitlements}
    end)
    |> case do
      {:ok, {purchase, entitlements}} ->
        after_purchase_revoked(purchase)
        Enum.each(entitlements, &after_entitlement_changed/1)
        {:ok, purchase}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Store receipt validation
  # ---------------------------------------------------------------------------

  @spec validate_store_purchase(User.t(), String.t(), map()) ::
          {:ok, %{purchase: Purchase.t(), seen_before: boolean()}} | {:error, term()}
  def validate_store_purchase(%User{} = user, provider, attrs)
      when provider in @store_validation_providers and is_map(attrs) do
    with {:ok, validation} <- provider_adapter(provider).validate_purchase(user, attrs),
         validation <- Params.normalize(validation),
         {:ok, external_id} <- Params.required_value(validation, "product_id"),
         {:ok, transaction_id} <- Params.required_value(validation, "transaction_id"),
         %ProviderProduct{} = provider_product <- get_provider_product(provider, external_id) do
      case get_purchase_by_provider_transaction(provider, transaction_id) do
        %Purchase{user_id: existing_user_id} = purchase when existing_user_id == user.id ->
          {:ok, %{purchase: purchase, seen_before: true}}

        %Purchase{} ->
          {:error, :receipt_already_used}

        nil ->
          # Also check the *original* transaction id before creating anything.
          #
          # Deduping on `transaction_id` alone is enough for a one-time
          # purchase, but a subscription mints a fresh transaction id at every
          # renewal — so user B could take user A's receipt, wait for the next
          # renewal, and validate it as a brand-new purchase. The original id is
          # stable across the whole subscription and is already stored and
          # indexed; it just was not consulted.
          with :ok <- ensure_original_transaction_unclaimed(user, provider, validation),
               :ok <- ensure_checkout_allowed(user, provider_product, validation) do
            create_validated_store_purchase(user, provider_product, validation)
          end
      end
    else
      nil -> {:error, :provider_product_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Stripe
  # ---------------------------------------------------------------------------

  @doc delegate_to: {StripeEvents, :create_stripe_checkout, 2}
  defdelegate create_stripe_checkout(user, attrs), to: StripeEvents

  @doc delegate_to: {StripeEvents, :handle_stripe_webhook, 2}
  defdelegate handle_stripe_webhook(raw_body, signature), to: StripeEvents

  @doc delegate_to: {StripeEvents, :reconcile_stripe_purchase, 1}
  defdelegate reconcile_stripe_purchase(purchase), to: StripeEvents

  @doc delegate_to: {StripeEvents, :cancel_stripe_subscription_at_period_end, 2}
  defdelegate cancel_stripe_subscription_at_period_end(user, entitlement_id), to: StripeEvents

  @doc delegate_to: {StripeEvents, :stripe_customer_id, 1}
  defdelegate stripe_customer_id(user), to: StripeEvents

  @doc delegate_to: {StripeEvents, :create_stripe_billing_portal, 2}
  defdelegate create_stripe_billing_portal(user, return_url), to: StripeEvents

  # ---------------------------------------------------------------------------
  # Steam
  # ---------------------------------------------------------------------------

  @spec create_steam_checkout(User.t(), map()) ::
          {:ok,
           %{
             purchase: Purchase.t(),
             provider_transaction_id: String.t() | nil,
             steam_url: String.t() | nil
           }}
          | {:error, term()}
  def create_steam_checkout(%User{} = user, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Params.normalize()
      |> client_checkout_attrs()
      |> Map.put("order_id", generate_steam_order_id())

    with {:ok, provider_product} <- resolve_provider_product("steam", attrs),
         :ok <- ensure_checkout_allowed(user, provider_product, attrs),
         {:ok, purchase} <- create_purchase(user, provider_product, attrs) do
      case provider_adapter("steam").init_transaction(purchase, provider_product, attrs) do
        {:ok, result} ->
          with {:ok, updated_purchase} <- mark_steam_purchase_requires_action(purchase, result) do
            params = steam_response_params(result)

            {:ok,
             %{
               purchase: updated_purchase,
               provider_transaction_id: params["transid"],
               steam_url: params["steamurl"]
             }}
          end

        {:error, reason} ->
          mark_purchase_failed(purchase, "steam_checkout_session_failed", reason)
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec finalize_steam_purchase(User.t(), map()) ::
          {:ok, %{purchase: Purchase.t()}} | {:error, term()}
  def finalize_steam_purchase(%User{} = user, attrs) when is_map(attrs) do
    attrs = Params.normalize(attrs)

    with {:ok, order_id} <- Params.required_value(attrs, "order_id"),
         %Purchase{provider: "steam", user_id: user_id} = purchase when user_id == user.id <-
           get_purchase_by_order_id(order_id),
         {:ok, validation} <- provider_adapter("steam").finalize_transaction(purchase, attrs),
         validation <- Params.normalize(validation),
         {:ok, updated} <- update_purchase_from_validation(purchase, validation),
         {:ok, final_purchase} <- apply_validated_status(updated, validation) do
      {:ok, %{purchase: final_purchase}}
    else
      nil -> {:error, :purchase_not_found}
      %Purchase{} -> {:error, :purchase_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Provider webhooks
  # ---------------------------------------------------------------------------

  @doc delegate_to: {StoreEvents, :handle_google_webhook, 2}
  defdelegate handle_google_webhook(raw_body, authorization_header), to: StoreEvents

  @doc delegate_to: {StoreEvents, :handle_apple_webhook, 1}
  defdelegate handle_apple_webhook(raw_body), to: StoreEvents

  # ---------------------------------------------------------------------------
  # Entitlements
  # ---------------------------------------------------------------------------

  @doc """
  The user's entitlements, by key: active ones only unless
  `include_inactive: true`. Pass `:page` and `:page_size` for one page.
  """
  @spec list_user_entitlements(Ecto.UUID.t(), keyword()) :: [Entitlement.t()]
  def list_user_entitlements(user_id, opts \\ []) when is_binary(user_id) do
    user_id
    |> entitlements_query(opts)
    |> order_by([e], asc: e.key)
    |> preload([:product, :source_purchase])
    |> maybe_page(opts)
    |> Repo.all()
  end

  @doc "Counts `list_user_entitlements/2`'s entitlements; takes `:include_inactive`."
  @spec count_user_entitlements(Ecto.UUID.t(), keyword()) :: non_neg_integer()
  def count_user_entitlements(user_id, opts \\ []) when is_binary(user_id) do
    user_id |> entitlements_query(opts) |> Repo.aggregate(:count)
  end

  defp entitlements_query(user_id, opts) do
    query = from e in Entitlement, where: e.user_id == ^user_id

    if Keyword.get(opts, :include_inactive, false) do
      query
    else
      now = DateTime.utc_now(:second)

      from e in query,
        where: e.status == "active" and (is_nil(e.expires_at) or e.expires_at > ^now)
    end
  end

  @spec has_entitlement?(Ecto.UUID.t(), String.t()) :: boolean()
  def has_entitlement?(user_id, key) when is_binary(user_id) and is_binary(key) do
    now = DateTime.utc_now(:second)

    from(e in Entitlement,
      where:
        e.user_id == ^user_id and e.key == ^key and e.status == "active" and
          (is_nil(e.expires_at) or e.expires_at > ^now),
      select: count(e.id)
    )
    |> Repo.one()
    |> Kernel.>(0)
  end

  @spec product_entitlement_key(Product.t()) :: String.t()
  def product_entitlement_key(%Product{grant_config: config, sku: sku}) do
    config = config || %{}
    config["entitlement_key"] || config[:entitlement_key] || sku
  end

  # ---------------------------------------------------------------------------
  # Admin
  # ---------------------------------------------------------------------------

  @doc delegate_to: {Admin, :admin_stats, 0}
  defdelegate admin_stats(), to: Admin

  @doc delegate_to: {Admin, :stripe_config_status, 0}
  defdelegate stripe_config_status(), to: Admin

  @doc delegate_to: {Admin, :provider_adapter_statuses, 0}
  defdelegate provider_adapter_statuses(), to: Admin

  @doc delegate_to: {Admin, :list_admin_products, 1}
  defdelegate list_admin_products(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :count_products, 1}
  defdelegate count_products(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :list_admin_provider_products, 1}
  defdelegate list_admin_provider_products(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :count_provider_products, 1}
  defdelegate count_provider_products(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :list_admin_purchases, 1}
  defdelegate list_admin_purchases(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :count_purchases, 1}
  defdelegate count_purchases(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :list_admin_entitlements, 1}
  defdelegate list_admin_entitlements(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :count_entitlements, 1}
  defdelegate count_entitlements(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :list_provider_events, 1}
  defdelegate list_provider_events(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :count_provider_events, 1}
  defdelegate count_provider_events(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :list_reconciliation_cursors, 1}
  defdelegate list_reconciliation_cursors(opts \\ []), to: Admin

  @doc delegate_to: {Admin, :count_reconciliation_cursors, 1}
  defdelegate count_reconciliation_cursors(opts \\ []), to: Admin

  @spec record_provider_event(String.t(), String.t(), String.t(), map(), map()) ::
          {:ok, ProviderEvent.t(), boolean()} | {:error, Ecto.Changeset.t()}
  def record_provider_event(provider, event_id, event_type, payload, metadata \\ %{})
      when is_binary(provider) and is_binary(event_id) and is_binary(event_type) and
             is_map(payload) and is_map(metadata) do
    case Repo.get_by(ProviderEvent, provider: provider, event_id: event_id) do
      %ProviderEvent{} = event ->
        {:ok, event, false}

      nil ->
        %ProviderEvent{}
        |> ProviderEvent.changeset(%{
          provider: provider,
          event_id: event_id,
          event_type: event_type,
          payload: payload,
          metadata: metadata,
          # Deliberately nil. This used to be stamped at insert, *before* the
          # handler ran, so a handler that failed (a database blip, an upstream
          # timeout while fetching the subscription) returned an error to the
          # provider, and the provider's retry then matched this row and was
          # dismissed as a duplicate. The event was lost for good: the customer
          # had paid and was never fulfilled, or a refund never withdrew the
          # entitlement, with no path to recovery.
          processed_at: nil
        })
        |> Repo.insert()
        |> case do
          {:ok, event} -> {:ok, event, true}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Stamp a provider event as fully handled. Only then does a retry of the same
  event id count as a duplicate.
  """
  @spec mark_event_processed(ProviderEvent.t()) ::
          {:ok, ProviderEvent.t()} | {:error, Ecto.Changeset.t()}
  def mark_event_processed(%ProviderEvent{} = event) do
    event
    |> ProviderEvent.changeset(%{processed_at: DateTime.utc_now(:second)})
    |> Repo.update()
  end

  # Decide whether a webhook delivery should run, and stamp it when it does.
  #
  # `record_provider_event/5` answers "have I seen this event id before?".
  # That is not the same question as "has it been handled?", and treating it as
  # such lost events: the row used to be written with `processed_at` already
  # set, *before* the handler ran, so a handler that failed returned an error to
  # the provider and the provider's retry was then dismissed as a duplicate.
  # A paid checkout could go permanently unfulfilled, a refund permanently
  # un-revoked, with nothing to recover from.
  #
  # Now the row is written unprocessed, and only a *completed* delivery counts
  # as a duplicate. A retry of an event we recorded but never finished runs
  # again — webhook handlers are idempotent (`fulfill_purchase/2` locks the row
  # and returns `:already_fulfilled`), so re-running one is safe and losing one
  # is not.
  @doc false
  def claim_provider_event(provider, event_id, event_type, event, fun) do
    case record_provider_event(provider, event_id, event_type, event) do
      {:ok, %ProviderEvent{processed_at: %DateTime{}}, false} ->
        {:ok, :duplicate}

      {:ok, %ProviderEvent{} = record, _new_or_unprocessed} ->
        case fun.() do
          {:error, _reason} = error ->
            error

          result ->
            _ = mark_event_processed(record)
            result
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp maybe_active_only(query, true), do: query
  defp maybe_active_only(query, false), do: from(p in query, where: p.active == true)

  defp preload_product(nil), do: nil
  defp preload_product(provider_product), do: Repo.preload(provider_product, :product)

  @doc false
  def preload_purchase(nil), do: nil
  def preload_purchase(purchase), do: Repo.preload(purchase, [:product, :provider_product])

  @doc false
  def resolve_provider_product(provider, %{"provider_product_id" => id}) do
    case Gamend.UUIDv7.cast_or_nil(id) do
      nil ->
        {:error, :invalid_provider_product_id}

      provider_product_id ->
        case get_provider_product(provider_product_id) do
          %ProviderProduct{provider: ^provider, active: true, product: %Product{active: true}} =
              provider_product ->
            {:ok, provider_product}

          _ ->
            {:error, :provider_product_not_found}
        end
    end
  end

  def resolve_provider_product(provider, %{"product_sku" => sku}) when is_binary(sku) do
    query =
      from pp in ProviderProduct,
        join: p in assoc(pp, :product),
        where:
          pp.provider == ^provider and pp.active == true and p.active == true and p.sku == ^sku,
        preload: [product: p],
        limit: 1

    case Repo.one(query) do
      %ProviderProduct{} = provider_product -> {:ok, provider_product}
      nil -> {:error, :provider_product_not_found}
    end
  end

  def resolve_provider_product(_provider, _attrs), do: {:error, :missing_product_reference}

  @doc false
  def ensure_checkout_allowed(
        %User{} = user,
        %ProviderProduct{product: %Product{} = product},
        attrs
      ) do
    with :ok <- ensure_single_ownership_quantity(product, attrs),
         :ok <- ensure_single_ownership_available(user, product) do
      ensure_game_allows_purchase(user, product)
    end
  end

  def ensure_checkout_allowed(_user, _provider_product, _attrs), do: :ok

  # The game's veto, and the last one before money moves: a plugin can refuse to
  # sell to this player — an unlinked account whose entitlement would be
  # stranded on one device, a region it does not ship to, a player it has
  # banned. Runs on every provider path, because a gate only one of them
  # respects is not a gate.
  defp ensure_game_allows_purchase(%User{} = user, %Product{} = product) do
    case Gamend.Hooks.internal_call(:before_purchase, [user, product]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_single_ownership_quantity(%Product{kind: kind}, attrs)
       when kind in ["entitlement", "subscription"] do
    if Params.parse_positive_int(attrs["quantity"], 1) == 1 do
      :ok
    else
      {:error, :quantity_not_allowed}
    end
  end

  defp ensure_single_ownership_quantity(_product, _attrs), do: :ok

  defp ensure_single_ownership_available(%User{} = user, %Product{kind: kind} = product)
       when kind in ["entitlement", "subscription"] do
    key = product_entitlement_key(product)

    cond do
      has_entitlement?(user.id, key) ->
        {:error, :already_owned}

      purchase_in_progress?(user.id, key) ->
        {:error, :purchase_already_in_progress}

      true ->
        :ok
    end
  end

  defp ensure_single_ownership_available(_user, _product), do: :ok

  defp purchase_in_progress?(user_id, entitlement_key) do
    from(p in Purchase,
      where: p.user_id == ^user_id and p.status == "requires_action",
      preload: [:product]
    )
    |> Repo.all()
    |> Enum.any?(fn %Purchase{product: product} ->
      product_entitlement_key(product) == entitlement_key
    end)
  end

  @doc false
  def mark_purchase_failed(%Purchase{} = purchase, reason, provider_reason) do
    payload = %{
      "failure_reason" => reason,
      "provider_reason" => inspect(provider_reason) |> String.slice(0, 1_000)
    }

    result =
      purchase
      |> Purchase.changeset(%{
        status: "failed",
        raw_provider_payload: Params.merge_payload(purchase.raw_provider_payload, payload)
      })
      |> Repo.update()
      |> tap_bump({:payments, :purchase_version})

    Logger.warning(
      "Payment checkout failed",
      purchase_id: purchase.id,
      order_id: purchase.order_id,
      provider: purchase.provider,
      reason: reason,
      provider_reason: inspect(provider_reason)
    )

    result
  end

  @doc false
  def mark_purchase_requires_action(%Purchase{} = purchase, session) when is_map(session) do
    metadata =
      purchase.metadata
      |> Map.put("stripe_checkout_url", session["url"])
      |> Map.put("stripe_session_id", session["id"])

    purchase
    |> Purchase.changeset(%{
      status: "requires_action",
      provider_transaction_id: session["id"],
      metadata: metadata,
      raw_provider_payload:
        Params.merge_payload(purchase.raw_provider_payload, %{"stripe_session" => session})
    })
    |> Repo.update()
    |> tap_bump({:payments, :purchase_version})
  end

  defp mark_steam_purchase_requires_action(%Purchase{} = purchase, result) when is_map(result) do
    params = steam_response_params(result)

    metadata =
      purchase.metadata
      |> Map.put("steam_url", params["steamurl"])
      |> Map.put("steam_transaction_id", params["transid"])
      |> Params.put_if_present(
        "steam_agreements",
        params["agreements"],
        not is_nil(params["agreements"])
      )

    purchase
    |> Purchase.changeset(%{
      status: "requires_action",
      provider_transaction_id: params["transid"] || purchase.provider_transaction_id,
      metadata: metadata,
      raw_provider_payload:
        Params.merge_payload(purchase.raw_provider_payload, %{"steam_init" => result})
    })
    |> Repo.update()
    |> tap_bump({:payments, :purchase_version})
  end

  @doc false
  def update_purchase_from_validation(%Purchase{} = purchase, validation) do
    validated_status = validation["status"] || "completed"

    attrs = %{
      # A completed purchase is never moved back to pending.
      #
      # `status_before_fulfillment/1` maps "completed" to "pending" so that a
      # *new* purchase can go through `fulfill_purchase/2` once. Applied to an
      # already-completed row it re-armed fulfilment, so an Apple activation
      # notification arriving after the client had already validated the same
      # transaction fulfilled it a second time — firing
      # `after_purchase_fulfilled` twice, which for the bundled example hook
      # means granting the currency twice. Renewals extend the entitlement via
      # `expires_at` below; they do not need a second fulfilment.
      status: next_validated_status(purchase, validated_status),
      provider_transaction_id: validation["transaction_id"] || purchase.provider_transaction_id,
      provider_original_transaction_id:
        validation["original_transaction_id"] || purchase.provider_original_transaction_id,
      quantity: validation["quantity"] || purchase.quantity,
      currency: validation["currency"] || purchase.currency,
      amount: validation["amount"] || purchase.amount,
      environment: validation["environment"] || purchase.environment,
      expires_at: Params.parse_datetime(validation["expires_at"]) || purchase.expires_at,
      raw_provider_payload:
        Params.merge_payload(
          purchase.raw_provider_payload,
          validation["raw_payload"] || validation
        )
    }

    purchase
    |> Purchase.changeset(attrs)
    |> Repo.update()
    |> tap_bump({:payments, :purchase_version})
  end

  defp apply_validated_status(%Purchase{} = purchase, %{"status" => status})
       when status in ["refunded", "revoked"] do
    revoke_purchase(purchase, %{
      "status" => status,
      "reason" => "provider_validation",
      "payload" => purchase.raw_provider_payload || %{}
    })
  end

  defp apply_validated_status(%Purchase{} = purchase, %{"status" => "completed"}) do
    fulfill_purchase(purchase, purchase.raw_provider_payload || %{})
  end

  defp apply_validated_status(%Purchase{} = purchase, _validation), do: {:ok, purchase}

  defp complete_purchase(%Purchase{} = purchase, provider_payload) do
    purchase
    |> Purchase.changeset(%{
      status: "completed",
      purchased_at: purchase.purchased_at || DateTime.utc_now(:second),
      raw_provider_payload: Params.merge_payload(purchase.raw_provider_payload, provider_payload)
    })
    |> Repo.update()
    |> tap_bump({:payments, :purchase_version})
  end

  defp grant_purchase(%Purchase{product: %Product{kind: "consumable"}}), do: :ok

  defp grant_purchase(%Purchase{product: %Product{} = product} = purchase) do
    key = product_entitlement_key(product)
    expires_at = purchase.expires_at || entitlement_expiry(product)
    now = DateTime.utc_now(:second)

    attrs = %{
      user_id: purchase.user_id,
      product_id: product.id,
      source_purchase_id: purchase.id,
      key: key,
      status: "active",
      starts_at: now,
      expires_at: expires_at,
      revoked_at: nil,
      metadata: %{"product_sku" => product.sku, "provider" => purchase.provider}
    }

    entitlement =
      case Repo.get_by(Entitlement, user_id: purchase.user_id, key: key) do
        nil ->
          %Entitlement{}

        %Entitlement{} = existing ->
          existing
      end

    case entitlement |> Entitlement.changeset(attrs) |> Repo.insert_or_update() do
      {:ok, entitlement} ->
        after_entitlement_changed(entitlement)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp create_validated_store_purchase(%User{} = user, provider_product, validation) do
    validated_status =
      if test_purchase?(validation) do
        # Recorded, never fulfilled.
        #
        # A sandbox or TestFlight transaction is signed by Apple exactly like a
        # real one, and a Google test purchase verifies exactly like a real one,
        # so every other check passes. The environment was decoded and stored
        # but never compared against the server's own — which meant anyone with
        # a TestFlight build or a sandbox tester account got every in-app
        # purchase for free on the production server.
        "failed"
      else
        validation["status"] || "completed"
      end

    attrs = %{
      "status" => status_before_fulfillment(validated_status),
      "provider_transaction_id" => validation["transaction_id"],
      "provider_original_transaction_id" => validation["original_transaction_id"],
      "quantity" => validation["quantity"] || 1,
      "currency" => validation["currency"],
      "amount" => validation["amount"],
      "environment" => validation["environment"] || ProviderConfig.environment(),
      "expires_at" => Params.parse_datetime(validation["expires_at"]),
      "raw_provider_payload" => validation["raw_payload"] || validation
    }

    with {:ok, purchase} <- create_purchase(user, provider_product, attrs),
         {:ok, fulfilled_purchase} <- maybe_fulfill_validated_purchase(purchase, validated_status) do
      {:ok, %{purchase: fulfilled_purchase, seen_before: false}}
    end
  end

  defp ensure_original_transaction_unclaimed(user, provider, validation) do
    case validation["original_transaction_id"] do
      original when is_binary(original) and original != "" ->
        case get_purchase_by_provider_original_transaction(provider, original) do
          %Purchase{user_id: owner_id} when owner_id != user.id -> {:error, :receipt_already_used}
          _ -> :ok
        end

      _no_original ->
        :ok
    end
  end

  # A transaction from an environment this server does not serve.
  #
  # Apple reports `Sandbox` for both the sandbox and TestFlight; Google reports
  # `purchaseType` 0 for a test purchase and 1 for a promo. None of them
  # represent money, so on a production server they must not produce goods.
  # A non-production deployment accepts them, which is the whole point of one.
  # Both adapters already normalise their provider's own field into
  # `"environment"` — Apple maps `Sandbox`/`Xcode`, Google maps `purchaseType`
  # 0 — so one comparison covers all of them.
  defp test_purchase?(validation) do
    reported = validation["environment"]

    ProviderConfig.production?() and is_binary(reported) and
      String.downcase(reported) != "production"
  end

  # Row-level lock for the fulfilment read, so two confirmations of the same
  # purchase cannot both see "pending" and both fulfil it. That race is
  # reachable in normal operation: a client `POST /payments/validate/:provider`
  # arriving alongside the provider's own webhook for the same transaction, or
  # a webhook alongside an admin reconcile. Each winner fires
  # `after_purchase_fulfilled`, which is where games grant currency.
  #
  # Postgres only. SQLite has no row locks — `FOR UPDATE` raises rather than
  # being ignored — but its single writer plus `default_transaction_mode:
  # :immediate` already serialises the whole transaction, so the guarantee holds
  # there for a different reason.
  defp lock_for_update(query) do
    if AdvisoryLock.postgres?() do
      lock(query, "FOR UPDATE")
    else
      query
    end
  end

  # Terminal states a re-validation must not walk back out of.
  defp next_validated_status(%Purchase{status: "completed"}, "completed"), do: "completed"
  defp next_validated_status(_purchase, status), do: status_before_fulfillment(status)

  defp status_before_fulfillment("completed"), do: "pending"
  defp status_before_fulfillment(status), do: status

  defp maybe_fulfill_validated_purchase(%Purchase{} = purchase, "completed") do
    fulfill_purchase(purchase, purchase.raw_provider_payload)
  end

  defp maybe_fulfill_validated_purchase(%Purchase{} = purchase, _status), do: {:ok, purchase}

  @doc false
  def processed_result({:ok, _purchase}), do: {:ok, :processed}
  def processed_result({:error, reason}), do: {:error, reason}

  @doc false
  def purchase_from_provider_object(object) do
    metadata = object["metadata"] || %{}

    cond do
      is_binary(metadata["purchase_id"]) ->
        purchase_by_id_result(metadata["purchase_id"])

      is_binary(metadata["order_id"]) ->
        case get_purchase_by_order_id(metadata["order_id"]) do
          %Purchase{} = purchase -> {:ok, purchase}
          nil -> {:error, :purchase_not_found}
        end

      is_binary(object["charge"]) ->
        purchase_from_original_transaction(object["charge"])

      is_binary(object["charge_id"]) ->
        purchase_from_original_transaction(object["charge_id"])

      is_binary(object["id"]) ->
        case get_purchase_by_provider_transaction("stripe", object["id"]) do
          %Purchase{} = purchase ->
            {:ok, purchase}

          nil ->
            object["id"]
            |> purchase_from_original_transaction()
        end

      true ->
        {:error, :purchase_not_found}
    end
  end

  defp purchase_by_id_result(id) do
    case get_purchase(id) do
      %Purchase{} = purchase -> {:ok, purchase}
      nil -> {:error, :purchase_not_found}
    end
  end

  @doc false
  def get_user_subscription_entitlement(%User{} = user, entitlement_id) do
    Entitlement
    |> Repo.get(entitlement_id)
    |> Repo.preload([:product, source_purchase: [:product, :provider_product]])
    |> case do
      %Entitlement{
        user_id: user_id,
        product: %Product{kind: "subscription"},
        source_purchase: %Purchase{provider: "stripe"}
      } = entitlement
      when user_id == user.id ->
        {:ok, entitlement}

      %Entitlement{user_id: user_id, product: %Product{kind: "subscription"}}
      when user_id == user.id ->
        {:error, :not_stripe_subscription}

      %Entitlement{user_id: user_id} when user_id == user.id ->
        {:error, :not_subscription_entitlement}

      _ ->
        {:error, :entitlement_not_found}
    end
  end

  # A dispute always takes effect. A refund object counts only when its status
  # says the money actually moved; a `charge.refunded` counts only when the
  # charge was refunded in full, since a partial refund is not a revocation.
  @doc false
  def reversal_effective?("charge.dispute" <> _rest, _object), do: true

  def reversal_effective?("charge.refunded", object) do
    case {object["amount"], object["amount_refunded"]} do
      {amount, refunded} when is_integer(amount) and is_integer(refunded) -> refunded >= amount
      _unknown -> true
    end
  end

  def reversal_effective?(_refund_event, object) do
    case object["status"] do
      status when is_binary(status) -> status == "succeeded"
      _unknown -> true
    end
  end

  defp purchase_from_original_transaction(nil), do: {:error, :purchase_not_found}

  defp purchase_from_original_transaction(transaction_id) when is_binary(transaction_id) do
    case get_purchase_by_provider_original_transaction("stripe", transaction_id) do
      %Purchase{} = purchase -> {:ok, purchase}
      nil -> {:error, :purchase_not_found}
    end
  end

  @doc false
  def find_provider_purchase(provider, transaction_id, original_transaction_id) do
    [
      fn ->
        if is_binary(transaction_id) and transaction_id != "" do
          get_purchase_by_provider_transaction(provider, transaction_id)
        end
      end,
      fn ->
        if is_binary(original_transaction_id) and original_transaction_id != "" do
          get_purchase_by_provider_original_transaction(provider, original_transaction_id)
        end
      end
    ]
    |> Enum.reduce_while(nil, fn finder, _acc ->
      case finder.() do
        %Purchase{} = purchase -> {:halt, purchase}
        _ -> {:cont, nil}
      end
    end)
  end

  @doc false
  def provider_event_hash(provider, raw_body) do
    digest = :crypto.hash(:sha256, raw_body) |> Base.encode16(case: :lower)
    "#{provider}_#{digest}"
  end

  defp steam_response_params(%{"response" => %{"params" => params}}) when is_map(params),
    do: params

  defp steam_response_params(%{"response" => params}) when is_map(params), do: params
  defp steam_response_params(params) when is_map(params), do: params

  defp revoke_entitlements_for_purchase(%Purchase{} = purchase, now, reason) do
    query = from(e in Entitlement, where: e.source_purchase_id == ^purchase.id)

    query
    |> Repo.update_all(
      set: [
        status: "revoked",
        revoked_at: now,
        updated_at: now,
        metadata: %{"revocation_reason" => reason || "purchase_revoked"}
      ]
    )

    Repo.all(query)
  end

  defp after_purchase_fulfilled(%Purchase{} = purchase) do
    Gamend.Broadcast.publish("user:#{purchase.user_id}", {:purchase_updated, purchase})

    Gamend.Async.run(fn ->
      Gamend.Hooks.internal_call(:after_purchase_fulfilled, [purchase])
    end)
  end

  defp after_purchase_revoked(%Purchase{} = purchase) do
    Gamend.Broadcast.publish("user:#{purchase.user_id}", {:purchase_updated, purchase})

    Gamend.Async.run(fn ->
      Gamend.Hooks.internal_call(:after_purchase_revoked, [purchase])
    end)
  end

  @doc false
  def after_entitlement_changed(%Entitlement{} = entitlement) do
    Gamend.Broadcast.publish(
      "user:#{entitlement.user_id}",
      {:entitlement_changed, entitlement}
    )

    Gamend.Async.run(fn ->
      Gamend.Hooks.internal_call(:after_entitlement_changed, [entitlement])
    end)
  end

  @doc false
  def provider_adapter(provider) do
    adapters =
      Application.get_env(:gamend_core, :payment_provider_adapters, [])

    # A `case` with no catch-all raised CaseClauseError on any other string,
    # which is a 500 for what is really "no such provider".
    case provider do
      "apple" -> Keyword.get(adapters, :apple, Providers.Apple)
      "google" -> Keyword.get(adapters, :google, Providers.Google)
      "steam" -> Keyword.get(adapters, :steam, Providers.Steam)
      _other -> nil
    end
  end

  @doc false
  def stripe_adapter do
    Application.get_env(
      :gamend_core,
      :stripe_adapter,
      Gamend.Payments.Providers.Stripe
    )
  end

  defp entitlement_expiry(%Product{kind: "subscription", grant_config: config}) do
    duration = Params.parse_positive_int((config || %{})["duration_seconds"], 0)

    if duration > 0 do
      DateTime.utc_now(:second) |> DateTime.add(duration, :second)
    end
  end

  defp entitlement_expiry(_product), do: nil

  defp total_amount(nil, _quantity), do: nil

  defp total_amount(unit_amount, quantity) when is_integer(unit_amount),
    do: unit_amount * quantity

  defp generate_order_id do
    "ord_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end

  defp generate_steam_order_id do
    int = :crypto.strong_rand_bytes(8) |> :binary.decode_unsigned()

    int |> rem(9_000_000_000_000_000_000) |> Kernel.+(1_000_000_000_000_000_000) |> to_string()
  end

  @doc false
  def source_label({label, _value}), do: label
  def source_label(nil), do: nil
end
