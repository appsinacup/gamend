defmodule Gamend.Payments.Providers.Stripe do
  @moduledoc """
  Minimal Stripe Checkout and webhook adapter.
  """

  alias Gamend.Payments.ProviderConfig

  @webhook_tolerance_seconds 300

  def create_checkout_session(purchase, provider_product, attrs) do
    with {:ok, secret_key} <- secret_key(),
         {:ok, success_url} <- required_attr(attrs, "success_url"),
         {:ok, cancel_url} <- required_attr(attrs, "cancel_url") do
      metadata = checkout_metadata(purchase, provider_product)
      mode = stripe_mode(provider_product.product.kind)

      params =
        provider_product
        |> checkout_params(purchase, success_url, cancel_url, mode, metadata)
        |> put_checkout_customer(mode, attrs["stripe_customer_id"])
        |> put_managed_payments(ProviderConfig.stripe_managed_payments?())

      case create_checkout_session_with_sdk(
             params,
             secret_key
             |> stripe_request_opts(purchase)
             |> Keyword.put(:api_version, ProviderConfig.stripe_checkout_api_version())
           ) do
        {:ok, session} ->
          {:ok, normalize_stripe_payload(session)}

        {:error, reason} ->
          {:error, {:stripe_error, normalize_stripe_payload(reason)}}
      end
    end
  end

  def retrieve_checkout_session(session_id) when is_binary(session_id) do
    with {:ok, secret_key} <- secret_key() do
      case retrieve_checkout_session_with_sdk(
             session_id,
             %{expand: ["payment_intent", "subscription"]},
             stripe_request_opts(secret_key)
           ) do
        {:ok, session} ->
          {:ok, normalize_stripe_payload(session)}

        {:error, reason} ->
          {:error, {:stripe_error, normalize_stripe_payload(reason)}}
      end
    end
  end

  def retrieve_subscription(subscription_id) when is_binary(subscription_id) do
    with {:ok, secret_key} <- secret_key() do
      case retrieve_subscription_with_sdk(subscription_id, %{}, stripe_request_opts(secret_key)) do
        {:ok, subscription} ->
          {:ok, normalize_stripe_payload(subscription)}

        {:error, reason} ->
          {:error, {:stripe_error, normalize_stripe_payload(reason)}}
      end
    end
  end

  def cancel_subscription_at_period_end(subscription_id) when is_binary(subscription_id) do
    with {:ok, secret_key} <- secret_key() do
      case update_subscription_with_sdk(
             subscription_id,
             %{cancel_at_period_end: true},
             stripe_request_opts(secret_key)
           ) do
        {:ok, subscription} ->
          {:ok, normalize_stripe_payload(subscription)}

        {:error, reason} ->
          {:error, {:stripe_error, normalize_stripe_payload(reason)}}
      end
    end
  end

  @doc """
  A Stripe customer-portal session for `customer_id`: the Stripe-hosted page
  where the buyer cancels, changes card and downloads invoices. Returns the
  session; its `"url"` is single-use and short-lived, so open it right away.
  """
  def create_billing_portal_session(customer_id, return_url)
      when is_binary(customer_id) and is_binary(return_url) do
    with {:ok, secret_key} <- secret_key() do
      case create_billing_portal_session_with_sdk(
             %{customer: customer_id, return_url: return_url},
             stripe_request_opts(secret_key)
           ) do
        {:ok, session} ->
          {:ok, normalize_stripe_payload(session)}

        {:error, reason} ->
          {:error, {:stripe_error, normalize_stripe_payload(reason)}}
      end
    end
  end

  def verify_webhook(_raw_body, nil), do: {:error, :missing_stripe_signature}

  def verify_webhook(raw_body, signature_header)
      when is_binary(raw_body) and is_binary(signature_header) do
    with {:ok, secret} <- webhook_secret() do
      case construct_webhook_event_with_sdk(
             raw_body,
             signature_header,
             secret,
             @webhook_tolerance_seconds
           ) do
        {:ok, event} ->
          {:ok, normalize_stripe_payload(event)}

        {:error, reason} ->
          {:error, stripe_webhook_error(reason)}
      end
    end
  end

  def verify_webhook(_raw_body, _signature_header), do: {:error, :invalid_stripe_payload}

  defp stripe_mode("subscription"), do: "subscription"
  defp stripe_mode(_kind), do: "payment"

  defp checkout_metadata(purchase, provider_product) do
    %{
      "purchase_id" => to_string(purchase.id),
      "order_id" => purchase.order_id,
      "user_id" => to_string(purchase.user_id),
      "product_sku" => provider_product.product.sku
    }
  end

  defp checkout_params(provider_product, purchase, success_url, cancel_url, mode, metadata) do
    %{
      mode: mode,
      line_items: [
        %{
          price: provider_product.external_id,
          quantity: purchase.quantity
        }
      ],
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: metadata
    }
    |> put_checkout_payment_metadata(mode, metadata)
  end

  # One Stripe customer per account, so the portal shows every purchase. A
  # returning buyer's checkout reuses their customer; a first one-off payment
  # asks Stripe to create one (subscription mode always does), without which a
  # lifetime buyer would have no portal and no receipts in it. The id is
  # server-supplied (`StripeEvents.create_stripe_checkout/2`), never a
  # client's, and only a `cus_` id is ever passed through.
  defp put_checkout_customer(params, _mode, "cus_" <> _rest = customer_id),
    do: Map.put(params, :customer, customer_id)

  defp put_checkout_customer(params, "payment", _customer_id),
    do: Map.put(params, :customer_creation, "always")

  defp put_checkout_customer(params, _mode, _customer_id), do: params

  # Stripe as merchant of record. None of the parameters Managed Payments
  # rejects (automatic_tax, payment_method_types, invoice_creation, shipping,
  # statement descriptors, Connect fields) is ever sent here, so the flag is
  # the whole change; the products need a Managed-Payments-eligible tax code
  # in the Dashboard.
  defp put_managed_payments(params, true),
    do: Map.put(params, :managed_payments, %{enabled: true})

  defp put_managed_payments(params, _enabled), do: params

  defp put_checkout_payment_metadata(params, "subscription", metadata) do
    Map.put(params, :subscription_data, %{metadata: metadata})
  end

  defp put_checkout_payment_metadata(params, _mode, metadata) do
    Map.put(params, :payment_intent_data, %{metadata: metadata})
  end

  defp stripe_request_opts(secret_key, purchase) do
    [
      api_key: secret_key,
      api_version: ProviderConfig.stripe_api_version(),
      idempotency_key: purchase.order_id
    ]
  end

  defp stripe_request_opts(secret_key) do
    [
      api_key: secret_key,
      api_version: ProviderConfig.stripe_api_version()
    ]
  end

  defp secret_key do
    case ProviderConfig.stripe_secret_key() do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :stripe_not_configured}
    end
  end

  defp webhook_secret do
    case ProviderConfig.stripe_webhook_secret() do
      secret when is_binary(secret) and secret != "" -> {:ok, secret}
      _ -> {:error, :stripe_webhook_not_configured}
    end
  end

  defp required_attr(attrs, key) do
    case attrs[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, String.to_atom("missing_#{key}")}
    end
  end

  defp stripe_client do
    Application.get_env(:gamend_core, :stripe_client, __MODULE__.Client)
  end

  defp create_checkout_session_with_sdk(params, opts) do
    stripe_client().create_checkout_session(params, opts)
  rescue
    exception -> {:error, exception}
  end

  defp retrieve_checkout_session_with_sdk(session_id, params, opts) do
    stripe_client().retrieve_checkout_session(session_id, params, opts)
  rescue
    exception -> {:error, exception}
  end

  defp retrieve_subscription_with_sdk(subscription_id, params, opts) do
    stripe_client().retrieve_subscription(subscription_id, params, opts)
  rescue
    exception -> {:error, exception}
  end

  defp update_subscription_with_sdk(subscription_id, params, opts) do
    stripe_client().update_subscription(subscription_id, params, opts)
  rescue
    exception -> {:error, exception}
  end

  defp create_billing_portal_session_with_sdk(params, opts) do
    stripe_client().create_billing_portal_session(params, opts)
  rescue
    exception -> {:error, exception}
  end

  defp construct_webhook_event_with_sdk(raw_body, signature_header, secret, tolerance_seconds) do
    stripe_client().construct_webhook_event(raw_body, signature_header, secret, tolerance_seconds)
  rescue
    exception -> {:error, {:stripe_webhook_error, Exception.message(exception)}}
  end

  defp stripe_webhook_error({:stripe_webhook_error, _reason} = error), do: error
  defp stripe_webhook_error(reason), do: {:invalid_stripe_signature, reason}

  defp normalize_stripe_payload(%_module{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize_stripe_payload()
  end

  defp normalize_stripe_payload(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), normalize_stripe_payload(value)}
    end)
  end

  defp normalize_stripe_payload(list) when is_list(list) do
    Enum.map(list, &normalize_stripe_payload/1)
  end

  defp normalize_stripe_payload(value), do: value

  defmodule Client do
    @moduledoc false

    alias Stripe.BillingPortal.Session, as: PortalSession
    alias Stripe.Checkout.Session
    alias Stripe.Subscription
    alias Stripe.Webhook

    def create_checkout_session(params, opts) do
      Session.create(params, opts)
    end

    def retrieve_checkout_session(session_id, params, opts) do
      Session.retrieve(session_id, params, opts)
    end

    def retrieve_subscription(subscription_id, params, opts) do
      Subscription.retrieve(subscription_id, params, opts)
    end

    def update_subscription(subscription_id, params, opts) do
      Subscription.update(subscription_id, params, opts)
    end

    def create_billing_portal_session(params, opts) do
      PortalSession.create(params, opts)
    end

    def construct_webhook_event(raw_body, signature_header, secret, tolerance_seconds) do
      Webhook.construct_event(raw_body, signature_header, secret, tolerance_seconds)
    end
  end
end
