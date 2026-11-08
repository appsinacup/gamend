defmodule Gamend.Payments.StoreEvents do
  @moduledoc """
  Apple App Store and Google Play server notifications: verifying them, recording
  them once, and applying what they say to purchases and entitlements.

  Split out of `Gamend.Payments`, which still exposes every function here under
  the same name.
  """

  import Ecto.Query, warn: false
  alias Gamend.Payments
  alias Gamend.Payments.Params
  alias Gamend.Payments.ProviderConfig
  alias Gamend.Payments.Purchase

  require Gamend.Payments.PaymentEnvironment, as: PaymentEnvironment
  require Gamend.Payments.ProviderId, as: ProviderId
  require Gamend.Payments.PurchaseStatus, as: PurchaseStatus

  @unknown "unknown"

  @apple_reversal_notifications ~w(REFUND REVOKE EXPIRED)

  @apple_activation_notifications ~w(
    SUBSCRIBED
    DID_RENEW
    DID_RECOVER
    INTERACTIVE_RENEWAL
    DID_CHANGE_RENEWAL_PREF
    DID_CHANGE_RENEWAL_STATUS
  )

  # Cached catalog/ledger reads keyed by per-entity version counters bumped on
  # every write to that table via tap_bump/2. Products/provider-products change
  # rarely (kept warm through frequent purchases); purchases have their own
  # version so a buy doesn't evict the catalog.

  @spec handle_google_webhook(binary(), binary() | nil) :: {:ok, atom()} | {:error, term()}
  def handle_google_webhook(raw_body, authorization_header) when is_binary(raw_body) do
    with {:ok, event} <-
           Payments.provider_adapter(ProviderId.google()).verify_webhook(
             raw_body,
             authorization_header
           ),
         event <- Params.normalize(event),
         event_id <-
           event["message_id"] || Payments.provider_event_hash(ProviderId.google(), raw_body),
         event_type <- google_event_type(event) do
      Payments.claim_provider_event(ProviderId.google(), event_id, event_type, event, fn ->
        process_google_event(event)
      end)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec handle_apple_webhook(binary()) :: {:ok, atom()} | {:error, term()}
  def handle_apple_webhook(raw_body) when is_binary(raw_body) do
    with {:ok, event} <-
           Payments.provider_adapter(ProviderId.apple()).verify_notification(raw_body),
         event <- Params.normalize(event),
         event_id <-
           event["notificationUUID"] || Payments.provider_event_hash(ProviderId.apple(), raw_body),
         event_type when is_binary(event_type) <- event["notificationType"] do
      Payments.claim_provider_event(ProviderId.apple(), event_id, event_type, event, fn ->
        process_apple_event(event)
      end)
    else
      nil -> {:error, :missing_event_type}
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_google_event(%{"testNotification" => _notification}), do: {:ok, :processed}

  defp process_google_event(%{"voidedPurchaseNotification" => notification})
       when is_map(notification) do
    purchase =
      Payments.find_provider_purchase(
        ProviderId.google(),
        notification["orderId"],
        notification["purchaseToken"]
      )

    case purchase do
      %Purchase{} ->
        Payments.revoke_purchase(purchase, %{
          "status" => PurchaseStatus.refunded(),
          "reason" => "google_voided_purchase",
          "payload" => %{"google_notification" => notification}
        })
        |> Payments.processed_result()

      nil ->
        {:ok, :ignored}
    end
  end

  defp process_google_event(%{"oneTimeProductNotification" => notification})
       when is_map(notification) do
    purchase =
      Payments.find_provider_purchase(ProviderId.google(), nil, notification["purchaseToken"])

    case {notification["notificationType"], purchase} do
      {2, %Purchase{} = purchase} ->
        Payments.revoke_purchase(purchase, %{
          "status" => PurchaseStatus.cancelled(),
          "reason" => "google_one_time_product_cancelled",
          "payload" => %{"google_notification" => notification}
        })
        |> Payments.processed_result()

      {_type, %Purchase{} = purchase} ->
        Payments.fulfill_purchase(purchase, %{"google_notification" => notification})
        |> Payments.processed_result()

      _ ->
        {:ok, :ignored}
    end
  end

  defp process_google_event(%{"subscriptionNotification" => notification})
       when is_map(notification) do
    purchase =
      Payments.find_provider_purchase(ProviderId.google(), nil, notification["purchaseToken"])

    case {notification["notificationType"], purchase} do
      {type, %Purchase{} = purchase} when type in [12, 13, 20] ->
        Payments.revoke_purchase(purchase, %{
          "status" => google_subscription_reversal_status(type),
          "reason" => "google_subscription_notification_#{type}",
          "payload" => %{"google_notification" => notification}
        })
        |> Payments.processed_result()

      {_type, %Purchase{} = purchase} ->
        Payments.fulfill_purchase(purchase, %{"google_notification" => notification})
        |> Payments.processed_result()

      _ ->
        {:ok, :ignored}
    end
  end

  defp process_google_event(_event), do: {:ok, :ignored}

  defp process_apple_event(event) do
    transaction = event["decoded_transaction_info"] || %{}
    type = event["notificationType"]

    purchase =
      Payments.find_provider_purchase(
        ProviderId.apple(),
        transaction["transactionId"],
        transaction["originalTransactionId"]
      )

    cond do
      is_nil(purchase) ->
        {:ok, :ignored}

      type in @apple_reversal_notifications or not is_nil(transaction["revocationDate"]) ->
        Payments.revoke_purchase(purchase, %{
          "status" => PurchaseStatus.revoked(),
          "reason" => "apple_#{type}",
          "payload" => %{"apple_notification" => event}
        })
        |> Payments.processed_result()

      type in @apple_activation_notifications ->
        with {:ok, updated} <-
               Payments.update_purchase_from_validation(
                 purchase,
                 apple_validation_from_transaction(transaction)
               ),
             {:ok, _purchase} <-
               Payments.fulfill_purchase(updated, %{"apple_notification" => event}) do
          {:ok, :processed}
        end

      true ->
        {:ok, :ignored}
    end
  end

  defp google_subscription_reversal_status(20), do: PurchaseStatus.cancelled()
  defp google_subscription_reversal_status(_type), do: PurchaseStatus.revoked()

  defp apple_validation_from_transaction(transaction) do
    %{
      "transaction_id" => transaction["transactionId"],
      "original_transaction_id" => transaction["originalTransactionId"],
      "status" => PurchaseStatus.completed(),
      "quantity" => transaction["quantity"] || 1,
      "environment" => apple_event_environment(transaction["environment"]),
      "expires_at" => Params.millis_to_iso8601(transaction["expiresDate"]),
      "raw_payload" => %{"apple_transaction" => transaction}
    }
  end

  defp apple_event_environment("Sandbox"), do: PaymentEnvironment.sandbox()
  defp apple_event_environment("Production"), do: PaymentEnvironment.production()
  defp apple_event_environment("Xcode"), do: PaymentEnvironment.test()
  defp apple_event_environment(_environment), do: ProviderConfig.environment()

  defp google_event_type(%{"voidedPurchaseNotification" => notification})
       when is_map(notification) do
    "voided_purchase:#{notification["refundType"] || @unknown}"
  end

  defp google_event_type(%{"oneTimeProductNotification" => notification})
       when is_map(notification) do
    "one_time_product:#{notification["notificationType"] || @unknown}"
  end

  defp google_event_type(%{"subscriptionNotification" => notification})
       when is_map(notification) do
    "subscription:#{notification["notificationType"] || @unknown}"
  end

  defp google_event_type(%{"testNotification" => _notification}), do: PaymentEnvironment.test()
  defp google_event_type(_event), do: @unknown
end
