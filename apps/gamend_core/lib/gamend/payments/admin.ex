defmodule Gamend.Payments.Admin do
  @moduledoc """
  What the admin payments pages and API read: the stats, provider configuration
  status, and filtered listings of products, purchases, entitlements, provider
  events and reconciliation cursors.

  Split out of `Gamend.Payments`, which still exposes every function here under
  the same name.
  """

  import Ecto.Query, warn: false
  alias Gamend.Payments
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Params
  alias Gamend.Payments.Product
  alias Gamend.Payments.ProviderConfig
  alias Gamend.Payments.ProviderEvent
  alias Gamend.Payments.ProviderProduct
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.ReconciliationCursor
  alias Gamend.Repo

  @spec admin_stats() :: map()
  def admin_stats do
    %{
      products: count_products(),
      provider_products: count_provider_products(),
      purchases: count_purchases(),
      completed_purchases: count_purchases(status: "completed"),
      entitlements: count_entitlements(),
      active_entitlements: count_entitlements(status: "active"),
      provider_events: count_provider_events()
    }
  end

  @spec stripe_config_status() :: map()
  def stripe_config_status do
    secret_key = ProviderConfig.stripe_secret_key()
    webhook_secret = ProviderConfig.stripe_webhook_secret()
    secret_key_source = ProviderConfig.stripe_secret_key_source()
    webhook_secret_source = ProviderConfig.stripe_webhook_secret_source()

    %{
      configured: Params.present?(secret_key) and Params.present?(webhook_secret),
      secret_key_configured: Params.present?(secret_key),
      webhook_secret_configured: Params.present?(webhook_secret),
      mode: stripe_key_mode(secret_key),
      selected_secret_key: Payments.source_label(secret_key_source),
      selected_webhook_secret: Payments.source_label(webhook_secret_source),
      expected_secret_keys: ProviderConfig.stripe_candidate_labels(:secret_key),
      expected_webhook_secrets: ProviderConfig.stripe_candidate_labels(:webhook_secret),
      api_version: ProviderConfig.stripe_api_version(),
      api_version_source: "pinned in Gamend.Payments.ProviderConfig",
      masked_secret_key: mask_secret(secret_key),
      masked_webhook_secret: mask_secret(webhook_secret),
      environment: ProviderConfig.environment()
    }
  end

  @spec provider_adapter_statuses() :: [map()]
  def provider_adapter_statuses do
    adapters = Application.get_env(:gamend_core, :payment_provider_adapters, [])
    stripe_status = stripe_config_status()

    stripe = %{
      provider: "stripe",
      module: Gamend.Payments.Providers.Stripe,
      configured: stripe_status.configured,
      status: Map.put(stripe_status, :provider, "stripe")
    }

    store_adapters =
      for {provider, default_module} <- [
            {"apple", Gamend.Payments.Providers.Apple},
            {"google", Gamend.Payments.Providers.Google},
            {"steam", Gamend.Payments.Providers.Steam}
          ] do
        key = String.to_existing_atom(provider)
        module = Keyword.get(adapters, key, default_module)
        status = provider_module_status(module)

        %{
          provider: provider,
          module: module,
          configured: Map.get(status, :configured, module != default_module),
          status: status
        }
      end

    [stripe | store_adapters]
  end

  @spec list_admin_products(keyword()) :: [Product.t()]
  def list_admin_products(opts \\ []) do
    from(p in Product,
      order_by: [desc: p.inserted_at, desc: p.id]
    )
    |> Gamend.Query.page(opts)
    |> Repo.all()
  end

  @spec count_products(keyword()) :: non_neg_integer()
  def count_products(_opts \\ []) do
    Repo.aggregate(Product, :count, :id)
  end

  @spec list_admin_provider_products(keyword()) :: [ProviderProduct.t()]
  def list_admin_provider_products(opts \\ []) do
    from(pp in ProviderProduct,
      order_by: [desc: pp.inserted_at, desc: pp.id],
      preload: [:product]
    )
    |> Gamend.Query.page(opts)
    |> Repo.all()
  end

  @spec count_provider_products(keyword()) :: non_neg_integer()
  def count_provider_products(_opts \\ []) do
    Repo.aggregate(ProviderProduct, :count, :id)
  end

  @spec list_admin_purchases(keyword()) :: [Purchase.t()]
  def list_admin_purchases(opts \\ []) do
    Purchase
    |> admin_purchase_filters(opts)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> preload([:product, :provider_product, :user])
    |> Gamend.Query.page(opts)
    |> Repo.all()
  end

  @spec count_purchases(keyword()) :: non_neg_integer()
  def count_purchases(opts \\ []) do
    Purchase
    |> admin_purchase_filters(opts)
    |> Repo.aggregate(:count, :id)
  end

  @spec list_admin_entitlements(keyword()) :: [Entitlement.t()]
  def list_admin_entitlements(opts \\ []) do
    Entitlement
    |> admin_entitlement_filters(opts)
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> preload([:product, :source_purchase, :user])
    |> Gamend.Query.page(opts)
    |> Repo.all()
  end

  @spec count_entitlements(keyword()) :: non_neg_integer()
  def count_entitlements(opts \\ []) do
    Entitlement
    |> admin_entitlement_filters(opts)
    |> Repo.aggregate(:count, :id)
  end

  @spec list_provider_events(keyword()) :: [ProviderEvent.t()]
  def list_provider_events(opts \\ []) do
    ProviderEvent
    |> provider_event_filters(opts)
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> Gamend.Query.page(opts)
    |> Repo.all()
  end

  @spec count_provider_events(keyword()) :: non_neg_integer()
  def count_provider_events(opts \\ []) do
    ProviderEvent
    |> provider_event_filters(opts)
    |> Repo.aggregate(:count, :id)
  end

  @spec list_reconciliation_cursors(keyword()) :: [ReconciliationCursor.t()]
  def list_reconciliation_cursors(opts \\ []) do
    from(c in ReconciliationCursor,
      order_by: [asc: c.provider, asc: c.name]
    )
    |> Gamend.Query.page(opts)
    |> Repo.all()
  end

  @spec count_reconciliation_cursors(keyword()) :: non_neg_integer()
  def count_reconciliation_cursors(_opts \\ []) do
    Repo.aggregate(ReconciliationCursor, :count, :id)
  end

  defp provider_module_status(nil), do: %{configured: false}

  defp provider_module_status(module) do
    # `config_status/0` is an optional callback of `Gamend.Payments.Provider`.
    if function_exported?(module, :config_status, 0) do
      module.config_status()
    else
      %{configured: true}
    end
  end

  defp admin_purchase_filters(query, opts) do
    query
    |> maybe_where_string(:provider, Keyword.get(opts, :provider))
    |> maybe_where_string(:status, Keyword.get(opts, :status))
    |> maybe_where_id(:user_id, Keyword.get(opts, :user_id))
    |> maybe_where_like(:order_id, Keyword.get(opts, :order_id))
  end

  defp admin_entitlement_filters(query, opts) do
    query
    |> maybe_where_string(:status, Keyword.get(opts, :status))
    |> maybe_where_id(:user_id, Keyword.get(opts, :user_id))
    |> maybe_where_like(:key, Keyword.get(opts, :key))
  end

  defp provider_event_filters(query, opts) do
    query
    |> maybe_where_string(:provider, Keyword.get(opts, :provider))
    |> maybe_where_like(:event_type, Keyword.get(opts, :event_type))
  end

  defp maybe_where_string(query, _field, value) when value in [nil, ""], do: query

  defp maybe_where_string(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp maybe_where_id(query, _field, value) when value in [nil, ""], do: query

  defp maybe_where_id(query, field, value) do
    case Gamend.UUIDv7.cast_or_nil(value) do
      nil -> query
      uuid -> where(query, [row], field(row, ^field) == ^uuid)
    end
  end

  defp maybe_where_like(query, _field, value) when value in [nil, ""], do: query

  defp maybe_where_like(query, field, value) when is_binary(value) do
    pattern = "%#{Repo.escape_like(value)}%"
    where(query, [row], fragment("? LIKE ? ESCAPE '\\'", field(row, ^field), ^pattern))
  end

  defp stripe_key_mode("sk_test_" <> _rest), do: "test"
  defp stripe_key_mode("rk_test_" <> _rest), do: "test"
  defp stripe_key_mode("sk_live_" <> _rest), do: "live"
  defp stripe_key_mode("rk_live_" <> _rest), do: "live"
  defp stripe_key_mode(value) when is_binary(value) and value != "", do: "unknown"
  defp stripe_key_mode(_value), do: "not_configured"

  defp mask_secret(value) when is_binary(value) and value != "" do
    len = byte_size(value)

    if len <= 8 do
      String.duplicate("*", len)
    else
      "#{String.slice(value, 0, 7)}...#{String.slice(value, -4, 4)}"
    end
  end

  defp mask_secret(_value), do: "<unset>"
end
