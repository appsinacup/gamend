defmodule Gamend.Payments.Providers.Stripe do
  @moduledoc """
  Minimal Stripe Checkout and webhook adapter.
  """

  alias Gamend.Payments.ProviderConfig

  @webhook_tolerance_seconds 300

  # How long a new Checkout Session can be paid. Stripe's default is 24 hours,
  # and until it sends `checkout.session.expired` the purchase stays
  # `requires_action`, which holds the entitlement's one open checkout. Stripe's
  # floor is 30 minutes from creation, on its own clock: the extra minute keeps
  # a slow request or a server clock running a little behind from being refused.
  @checkout_session_ttl_seconds 31 * 60

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
        |> put_trial_end(mode, attrs["trial_end"])
        |> put_managed_payments(ProviderConfig.stripe_managed_payments?())

      case create_checkout_session_with_sdk(params, stripe_request_opts(secret_key, purchase)) do
        {:ok, session} ->
          {:ok, normalize_stripe_payload(session)}

        {:error, reason} ->
          {:error, {:stripe_error, normalize_stripe_payload(reason)}}
      end
    end
  end

  @doc """
  Expires an open Checkout Session, so it can no longer be paid, and returns
  it. Stripe answers an error when the session is not open any more: paid,
  being paid, or expired already.
  """
  def expire_checkout_session(session_id) when is_binary(session_id) do
    with {:ok, secret_key} <- secret_key() do
      case expire_checkout_session_with_sdk(session_id, %{}, stripe_request_opts(secret_key)) do
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

  def cancel_subscription_at_period_end(subscription_id) when is_binary(subscription_id),
    do: put_cancel_at_period_end(subscription_id, true)

  @doc """
  Takes back a cancellation scheduled for the period end: the subscription
  renews again. Stripe refuses it once the subscription has ended.
  """
  def resume_subscription(subscription_id) when is_binary(subscription_id),
    do: put_cancel_at_period_end(subscription_id, false)

  defp put_cancel_at_period_end(subscription_id, cancel?) do
    with {:ok, secret_key} <- secret_key() do
      case update_subscription_with_sdk(
             subscription_id,
             %{cancel_at_period_end: cancel?},
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
  Cancels a subscription now, not at the period end. No proration credit and
  no final invoice (`prorate`/`invoice_now` false, Stripe's defaults, sent so
  a changed default cannot add a credit on top of a refund). Stripe then
  sends `customer.subscription.deleted`.
  """
  def cancel_subscription_now(subscription_id, opts \\ []) when is_binary(subscription_id) do
    with {:ok, secret_key} <- secret_key() do
      case cancel_subscription_with_sdk(
             subscription_id,
             %{prorate: false, invoice_now: false},
             secret_key
             |> stripe_request_opts()
             |> put_idempotency_key(opts[:idempotency_key])
           ) do
        {:ok, subscription} ->
          {:ok, normalize_stripe_payload(subscription)}

        {:error, reason} ->
          {:error, {:stripe_error, normalize_stripe_payload(reason)}}
      end
    end
  end

  @doc """
  A subscription with its latest invoice and that invoice's payments
  expanded: what the subscription last charged, and when.
  """
  def retrieve_subscription_with_latest_invoice(subscription_id)
      when is_binary(subscription_id) do
    with {:ok, secret_key} <- secret_key() do
      case retrieve_subscription_with_sdk(
             subscription_id,
             %{expand: ["latest_invoice", "latest_invoice.payments"]},
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
  The invoice payments a PaymentIntent paid, each with its invoice expanded:
  what a refund or dispute on a subscription's payment is traced back to its
  subscription through (a charge does not name its invoice). Returns the list
  object; `"data"` holds the payments.
  """
  def list_invoice_payments(payment_intent_id) when is_binary(payment_intent_id) do
    with {:ok, secret_key} <- secret_key() do
      case list_invoice_payments_with_sdk(
             %{
               payment: %{type: "payment_intent", payment_intent: payment_intent_id},
               expand: ["data.invoice"]
             },
             stripe_request_opts(secret_key)
           ) do
        {:ok, list} ->
          {:ok, normalize_stripe_payload(list)}

        {:error, reason} ->
          {:error, {:stripe_error, normalize_stripe_payload(reason)}}
      end
    end
  end

  @doc """
  Refunds a payment: a PaymentIntent (`pi_`) or a charge (`ch_`, `py_`).
  In full, or `:amount` of it (minor units; a plan given up for a longer
  one, `Upgrades`). Other `opts`: `:idempotency_key`, so a repeat within
  Stripe's 24 hours answers the same refund instead of trying a second, and
  `:metadata`, which the refund's own webhooks carry.
  """
  def create_refund(payment_id, opts \\ []) when is_binary(payment_id) do
    with {:ok, secret_key} <- secret_key(),
         {:ok, target} <- refund_target(payment_id) do
      params =
        target
        |> Map.put(:reason, "requested_by_customer")
        |> put_refund_amount(opts[:amount])
        |> put_refund_metadata(opts[:metadata])

      case create_refund_with_sdk(
             params,
             secret_key
             |> stripe_request_opts()
             |> put_idempotency_key(opts[:idempotency_key])
           ) do
        {:ok, refund} ->
          {:ok, normalize_stripe_payload(refund)}

        {:error, reason} ->
          {:error, {:stripe_error, normalize_stripe_payload(reason)}}
      end
    end
  end

  defp refund_target("pi_" <> _rest = id), do: {:ok, %{payment_intent: id}}
  defp refund_target("ch_" <> _rest = id), do: {:ok, %{charge: id}}
  defp refund_target("py_" <> _rest = id), do: {:ok, %{charge: id}}
  defp refund_target(_id), do: {:error, :invalid_stripe_payment_id}

  defp put_refund_amount(params, amount) when is_integer(amount) and amount > 0,
    do: Map.put(params, :amount, amount)

  defp put_refund_amount(params, _amount), do: params

  defp put_refund_metadata(params, metadata) when is_map(metadata) and metadata != %{},
    do: Map.put(params, :metadata, metadata)

  defp put_refund_metadata(params, _metadata), do: params

  defp put_idempotency_key(opts, key) when is_binary(key) and key != "",
    do: Keyword.put(opts, :idempotency_key, key)

  defp put_idempotency_key(opts, _key), do: opts

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
      expires_at: System.os_time(:second) + @checkout_session_ttl_seconds,
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

  # A subscription's first charge put off to `trial_end` (unix seconds): the
  # checkout collects the card, Stripe starts the subscription `trialing` and
  # bills it then. Server-supplied only (`StripeEvents.create_stripe_checkout/3`
  # sets it after the client's attrs are filtered), so a client cannot grant
  # itself free days. Stripe refuses a trial ending within 48 hours or past
  # two years; outside that window the checkout charges now instead, the
  # five minutes covering the time between here and Stripe's clock.
  @min_trial_seconds 48 * 3600 + 5 * 60
  @max_trial_seconds 730 * 86_400

  defp put_trial_end(%{subscription_data: data} = params, "subscription", trial_end)
       when is_integer(trial_end) do
    now = System.os_time(:second)

    if trial_end >= now + @min_trial_seconds and trial_end <= now + @max_trial_seconds,
      do: %{params | subscription_data: Map.put(data, :trial_end, trial_end)},
      else: params
  end

  defp put_trial_end(params, _mode, _trial_end), do: params

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

  # `response_as: :map` on every call: the decoded JSON, every field. The
  # SDK's structs are generated from one API version's schema and drop any
  # field it lacks: while this server sent 2022-11-15, a subscription came
  # back without `current_period_end` and an invoice without `payment_intent`
  # or `charge`, so no renewal date and no payment to refund. The version is
  # the SDK's own now (`ProviderConfig.stripe_api_version/0`), and a map still
  # keeps a field Stripe adds before the SDK does.
  defp stripe_request_opts(secret_key, purchase) do
    [
      api_key: secret_key,
      api_version: ProviderConfig.stripe_api_version(),
      idempotency_key: purchase.order_id,
      response_as: :map
    ]
  end

  defp stripe_request_opts(secret_key) do
    [
      api_key: secret_key,
      api_version: ProviderConfig.stripe_api_version(),
      response_as: :map
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

  defp expire_checkout_session_with_sdk(session_id, params, opts) do
    stripe_client().expire_checkout_session(session_id, params, opts)
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

  defp cancel_subscription_with_sdk(subscription_id, params, opts) do
    stripe_client().cancel_subscription(subscription_id, params, opts)
  rescue
    exception -> {:error, exception}
  end

  defp list_invoice_payments_with_sdk(params, opts) do
    stripe_client().list_invoice_payments(params, opts)
  rescue
    exception -> {:error, exception}
  end

  defp create_refund_with_sdk(params, opts) do
    stripe_client().create_refund(params, opts)
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
    alias Stripe.InvoicePayment
    alias Stripe.Refund
    alias Stripe.Subscription
    alias Stripe.Webhook

    def create_checkout_session(params, opts) do
      Session.create(params, opts)
    end

    def expire_checkout_session(session_id, params, opts) do
      Session.expire(session_id, params, opts)
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

    def cancel_subscription(subscription_id, params, opts) do
      Subscription.cancel(subscription_id, params, opts)
    end

    def list_invoice_payments(params, opts) do
      InvoicePayment.list(params, opts)
    end

    def create_refund(params, opts) do
      Refund.create(params, opts)
    end

    def create_billing_portal_session(params, opts) do
      PortalSession.create(params, opts)
    end

    # As a map, for the reason `stripe_request_opts/1` gives: the event's
    # object is in the webhook endpoint's API version, which the SDK's structs
    # need not match.
    def construct_webhook_event(raw_body, signature_header, secret, tolerance_seconds) do
      Webhook.construct_event(raw_body, signature_header, secret, tolerance_seconds,
        response_as: :map
      )
    end
  end
end
