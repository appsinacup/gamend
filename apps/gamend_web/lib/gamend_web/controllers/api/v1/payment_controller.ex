defmodule GamendWeb.Api.V1.PaymentController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Scope
  alias Gamend.Payments
  alias GamendWeb.Api.V1.PaymentErrors
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    EntitlementPage,
    PaymentCatalogEntryPage,
    PurchaseResponse,
    PurchaseValidationResponse,
    SteamCheckoutResponse,
    StripeCheckoutResponse
  }

  alias OpenApiSpex.Schema

  require Gamend.Payments.ProviderId, as: ProviderId

  tags(["Payments"])

  @page_params [
    page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
    page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
  ]

  @checkout_errors [
    bad_request: Schemas.error("The provider or the request refused the purchase"),
    not_found: Schemas.error("No such product (`provider_product_not_found`, ...)"),
    conflict: Schemas.error("Already in progress, or the receipt was already used"),
    unprocessable_entity: Schemas.error("Validation failed"),
    service_unavailable: Schemas.error("The provider is not configured on this server"),
    unauthorized: Schemas.error("Not authenticated")
  ]

  operation(:catalog,
    operation_id: "payments_catalog",
    summary: "List active payment catalog entries",
    parameters:
      [provider: [in: :query, schema: %Schema{type: :string}, required: false]] ++ @page_params,
    responses: [
      ok: {"Catalog, by provider then SKU", "application/json", PaymentCatalogEntryPage}
    ]
  )

  def catalog(conn, params) do
    provider = provider_param(params["provider"])
    {page, page_size} = Pagination.params(params)

    entries =
      provider
      |> Payments.list_catalog(page: page, page_size: page_size)
      |> Enum.map(&serialize_provider_product/1)

    reply_page(conn, entries, page, page_size, Payments.count_catalog(provider))
  end

  operation(:entitlements,
    operation_id: "payments_entitlements",
    summary: "List current user's active entitlements",
    security: [%{"authorization" => []}],
    parameters: @page_params,
    responses: [
      ok: {"Active entitlements, by key", "application/json", EntitlementPage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def entitlements(conn, params) do
    user = Scope.user(conn.assigns.current_scope)
    {page, page_size} = Pagination.params(params)

    entitlements =
      user.id
      |> Payments.list_user_entitlements(page: page, page_size: page_size)
      |> Enum.map(&serialize_entitlement/1)

    reply_page(conn, entitlements, page, page_size, Payments.count_user_entitlements(user.id))
  end

  operation(:stripe_checkout,
    operation_id: "payments_stripe_checkout",
    summary: "Create a Stripe Checkout Session",
    security: [%{"authorization" => []}],
    request_body:
      {"Checkout request", "application/json",
       %Schema{
         type: :object,
         properties: %{
           provider_product_id: %Schema{type: :string, format: :uuid},
           product_sku: %Schema{type: :string},
           quantity: %Schema{type: :integer},
           success_url: %Schema{type: :string},
           cancel_url: %Schema{type: :string}
         }
       }},
    responses:
      [ok: {"Checkout session", "application/json", StripeCheckoutResponse}] ++ @checkout_errors
  )

  def stripe_checkout(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    case Payments.create_stripe_checkout(user, params) do
      {:ok, result} ->
        reply_data(conn, %{
          purchase: serialize_purchase(result.purchase),
          checkout_url: result.checkout_url || "",
          provider_session_id: result.provider_session_id || ""
        })

      {:error, reason} ->
        PaymentErrors.reply(conn, reason)
    end
  end

  operation(:steam_checkout,
    operation_id: "payments_steam_checkout",
    summary: "Create a Steam MicroTxn transaction",
    security: [%{"authorization" => []}],
    request_body:
      {"Steam checkout request", "application/json",
       %Schema{
         type: :object,
         properties: %{
           provider_product_id: %Schema{type: :string, format: :uuid},
           product_sku: %Schema{type: :string},
           quantity: %Schema{type: :integer},
           steam_id: %Schema{type: :string},
           language: %Schema{type: :string},
           currency: %Schema{type: :string},
           usersession: %Schema{type: :string},
           ipaddress: %Schema{type: :string}
         }
       }},
    responses:
      [ok: {"Steam transaction", "application/json", SteamCheckoutResponse}] ++ @checkout_errors
  )

  def steam_checkout(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    case Payments.create_steam_checkout(user, params) do
      {:ok, result} ->
        reply_data(conn, %{
          purchase: serialize_purchase(result.purchase),
          provider_transaction_id: result.provider_transaction_id || "",
          steam_url: result.steam_url || ""
        })

      {:error, reason} ->
        PaymentErrors.reply(conn, reason)
    end
  end

  operation(:steam_finalize,
    operation_id: "payments_steam_finalize",
    summary: "Finalize an authorized Steam MicroTxn transaction",
    security: [%{"authorization" => []}],
    request_body:
      {"Steam finalize request", "application/json",
       %Schema{
         type: :object,
         properties: %{
           order_id: %Schema{type: :string}
         },
         required: [:order_id]
       }},
    responses:
      [ok: {"The finalized purchase", "application/json", PurchaseResponse}] ++ @checkout_errors
  )

  def steam_finalize(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    case Payments.finalize_steam_purchase(user, params) do
      {:ok, result} ->
        reply_data(conn, serialize_purchase(result.purchase))

      {:error, reason} ->
        PaymentErrors.reply(conn, reason)
    end
  end

  operation(:validate,
    operation_id: "payments_validate_store_purchase",
    summary: "Validate an Apple, Google, or Steam purchase",
    security: [%{"authorization" => []}],
    parameters: [
      provider: [in: :path, schema: %Schema{type: :string}, required: true]
    ],
    request_body:
      {"Provider receipt payload", "application/json",
       %Schema{type: :object, additionalProperties: true}},
    responses:
      [ok: {"Validated purchase", "application/json", PurchaseValidationResponse}] ++
        @checkout_errors
  )

  def validate(conn, %{"provider" => provider} = params) do
    user = Scope.user(conn.assigns.current_scope)
    attrs = Map.drop(params, ["provider"])

    if provider in [ProviderId.apple(), ProviderId.google(), ProviderId.steam()] do
      case Payments.validate_store_purchase(user, provider, attrs) do
        {:ok, result} ->
          reply_data(conn, %{
            purchase: serialize_purchase(result.purchase),
            seen_before: result.seen_before
          })

        {:error, reason} ->
          PaymentErrors.reply(conn, reason)
      end
    else
      reply_error(conn, :bad_request, "unknown_provider")
    end
  end

  defp provider_param(nil), do: nil
  defp provider_param(""), do: nil
  defp provider_param(provider), do: provider

  defp serialize_provider_product(provider_product) do
    product = provider_product.product

    %{
      id: provider_product.id,
      provider: provider_product.provider || "",
      external_id: provider_product.external_id || "",
      currency: provider_product.currency || "",
      unit_amount: provider_product.unit_amount,
      metadata: provider_product.metadata || %{},
      product: %{
        id: product.id,
        sku: product.sku,
        title: product.title || "",
        description: product.description || "",
        kind: product.kind || "",
        metadata: product.metadata || %{}
      }
    }
  end

  defp serialize_purchase(purchase) do
    %{
      id: purchase.id,
      order_id: purchase.order_id || "",
      provider: purchase.provider || "",
      provider_transaction_id: purchase.provider_transaction_id || "",
      status: purchase.status || "",
      product_id: purchase.product_id,
      provider_product_id: purchase.provider_product_id || "",
      quantity: purchase.quantity,
      currency: purchase.currency || "",
      amount: purchase.amount,
      environment: purchase.environment || "",
      purchased_at: purchase.purchased_at,
      expires_at: purchase.expires_at,
      revoked_at: purchase.revoked_at
    }
  end

  defp serialize_entitlement(entitlement) do
    %{
      id: entitlement.id,
      key: entitlement.key || "",
      status: entitlement.status || "",
      product_id: entitlement.product_id || "",
      source_purchase_id: entitlement.source_purchase_id || "",
      starts_at: entitlement.starts_at,
      expires_at: entitlement.expires_at,
      revoked_at: entitlement.revoked_at,
      metadata: entitlement.metadata || %{}
    }
  end
end
