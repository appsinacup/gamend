defmodule GamendWeb.Api.V1.PaymentWebhookController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Gamend.Payments
  alias GamendWeb.Api.V1.PaymentErrors
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.PaymentWebhookReceiptResponse

  tags(["Payments"])

  # Called by the provider, not a game client. A non-2xx answer makes it
  # retry, which is what a `*_not_configured` 503 is for.
  @responses [
    ok: {"Accepted", "application/json", PaymentWebhookReceiptResponse},
    bad_request: Schemas.error("Unverifiable or malformed event"),
    service_unavailable: Schemas.error("The provider is not configured on this server")
  ]

  operation(:stripe,
    operation_id: "payments_stripe_webhook",
    summary: "Receive Stripe webhook events",
    request_body: {"Stripe event", "application/json", %OpenApiSpex.Schema{type: :object}},
    responses: @responses
  )

  def stripe(conn, _params) do
    raw_body = conn.private[:raw_body] || ""
    signature = conn |> get_req_header("stripe-signature") |> List.first()

    case Payments.handle_stripe_webhook(raw_body, signature) do
      {:ok, status} ->
        reply_data(conn, %{status: to_string(status)})

      {:error, reason} ->
        PaymentErrors.reply(conn, reason)
    end
  end

  operation(:google,
    operation_id: "payments_google_webhook",
    summary: "Receive Google Play RTDN Pub/Sub push events",
    request_body: {"Google RTDN event", "application/json", %OpenApiSpex.Schema{type: :object}},
    responses: @responses
  )

  def google(conn, params) do
    raw_body = conn.private[:raw_body] || ""

    # Pub/Sub push subscriptions cannot send a custom `Authorization` header —
    # they send a Google-signed OIDC token instead — so a deployment configured
    # per our own docs had every real notification rejected, and voided
    # purchases and subscription revocations silently never landed. Pub/Sub
    # *can* carry a query string on the push endpoint URL, which is the
    # documented way to give it a shared secret, so accept the token there too:
    #
    #     https://your.host/api/v1/payments/webhooks/google?token=<GAMEND_PAYMENTS_GOOGLE_PLAY_RTDN_TOKEN>
    #
    # Verifying the OIDC token would be stronger and is the better long-term
    # answer; this makes the configured secret actually usable in the meantime.
    authorization =
      case get_req_header(conn, "authorization") do
        [header | _] -> header
        [] -> query_token(params)
      end

    case Payments.handle_google_webhook(raw_body, authorization) do
      {:ok, status} ->
        reply_data(conn, %{status: to_string(status)})

      {:error, reason} ->
        refused("google", reason)
        PaymentErrors.reply(conn, reason)
    end
  end

  operation(:apple,
    operation_id: "payments_apple_webhook",
    summary: "Receive App Store Server Notification v2 events",
    request_body: {"Apple notification", "application/json", %OpenApiSpex.Schema{type: :object}},
    responses: @responses
  )

  def apple(conn, _params) do
    raw_body = conn.private[:raw_body] || ""

    case Payments.handle_apple_webhook(raw_body) do
      {:ok, status} ->
        reply_data(conn, %{status: to_string(status)})

      {:error, reason} ->
        refused("apple", reason)
        PaymentErrors.reply(conn, reason)
    end
  end

  # A non-2xx answer makes the provider retry and, past its limit, give up:
  # an unverifiable token or a handler that failed is a lost notification
  # unless someone reads why. Stripe's are logged with the event in
  # `Gamend.Payments.StripeEvents`.
  defp refused(provider, reason) do
    Logger.warning(
      "Payment webhook #{provider} refused reason=#{inspect(reason) |> String.slice(0, 500)}"
    )
  end

  defp query_token(%{"token" => token}) when is_binary(token) and token != "",
    do: "Bearer " <> token

  defp query_token(_params), do: nil
end
