defmodule GameServerWeb.Api.V1.PaymentController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Accounts.Scope
  alias GameServer.Payments
  alias OpenApiSpex.Schema

  tags(["Payments"])

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  operation(:catalog,
    operation_id: "payments_catalog",
    summary: "List active payment catalog entries",
    parameters: [
      provider: [in: :query, schema: %Schema{type: :string}, required: false]
    ],
    responses: [
      ok: {"Catalog", "application/json", %Schema{type: :object}}
    ]
  )

  def catalog(conn, params) do
    provider = provider_param(params["provider"])

    data =
      provider
      |> Payments.list_catalog()
      |> Enum.map(&serialize_provider_product/1)

    json(conn, %{data: data})
  end

  operation(:entitlements,
    operation_id: "payments_entitlements",
    summary: "List current user's active entitlements",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Entitlements", "application/json", %Schema{type: :object}},
      unauthorized: {"Unauthorized", "application/json", @error_schema}
    ]
  )

  def entitlements(conn, _params) do
    user = Scope.user(conn.assigns.current_scope)

    data =
      user.id
      |> Payments.list_user_entitlements()
      |> Enum.map(&serialize_entitlement/1)

    json(conn, %{data: data})
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
    responses: [
      ok: {"Checkout Session", "application/json", %Schema{type: :object}},
      bad_request: {"Bad request", "application/json", @error_schema}
    ]
  )

  def stripe_checkout(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    case Payments.create_stripe_checkout(user, params) do
      {:ok, result} ->
        json(conn, %{
          data: %{
            purchase: serialize_purchase(result.purchase),
            checkout_url: result.checkout_url,
            provider_session_id: result.provider_session_id
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: normalize_error(reason)})
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
    responses: [
      ok: {"Steam transaction", "application/json", %Schema{type: :object}},
      bad_request: {"Bad request", "application/json", @error_schema}
    ]
  )

  def steam_checkout(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    case Payments.create_steam_checkout(user, params) do
      {:ok, result} ->
        json(conn, %{
          data: %{
            purchase: serialize_purchase(result.purchase),
            provider_transaction_id: result.provider_transaction_id || "",
            steam_url: result.steam_url
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: normalize_error(reason)})
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
    responses: [
      ok: {"Finalized purchase", "application/json", %Schema{type: :object}},
      bad_request: {"Bad request", "application/json", @error_schema}
    ]
  )

  def steam_finalize(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    case Payments.finalize_steam_purchase(user, params) do
      {:ok, result} ->
        json(conn, %{data: %{purchase: serialize_purchase(result.purchase)}})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: normalize_error(reason)})
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
    responses: [
      ok: {"Validated purchase", "application/json", %Schema{type: :object}},
      bad_request: {"Bad request", "application/json", @error_schema}
    ]
  )

  def validate(conn, %{"provider" => provider} = params) do
    user = Scope.user(conn.assigns.current_scope)
    attrs = Map.drop(params, ["provider"])

    if provider in ["apple", "google", "steam"] do
      case Payments.validate_store_purchase(user, provider, attrs) do
        {:ok, result} ->
          json(conn, %{
            data: %{
              purchase: serialize_purchase(result.purchase),
              seen_before: result.seen_before
            }
          })

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: normalize_error(reason)})
      end
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "unsupported_provider"})
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
        title: product.title,
        description: product.description,
        kind: product.kind,
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
      status: purchase.status,
      product_id: purchase.product_id,
      provider_product_id: purchase.provider_product_id,
      quantity: purchase.quantity,
      currency: purchase.currency || "",
      amount: purchase.amount,
      environment: purchase.environment,
      purchased_at: purchase.purchased_at,
      expires_at: purchase.expires_at,
      revoked_at: purchase.revoked_at
    }
  end

  defp serialize_entitlement(entitlement) do
    %{
      id: entitlement.id,
      key: entitlement.key || "",
      status: entitlement.status,
      product_id: entitlement.product_id,
      source_purchase_id: entitlement.source_purchase_id,
      starts_at: entitlement.starts_at,
      expires_at: entitlement.expires_at,
      revoked_at: entitlement.revoked_at,
      metadata: entitlement.metadata || %{}
    }
  end

  defp normalize_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_error(%Ecto.Changeset{}), do: "invalid_data"
  defp normalize_error({reason, _}) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_error(reason), do: inspect(reason)
end
