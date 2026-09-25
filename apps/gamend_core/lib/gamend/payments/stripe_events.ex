defmodule Gamend.Payments.StripeEvents do
  @moduledoc """
  Stripe: starting a checkout, and keeping purchases and entitlements in step
  with what Stripe says — webhooks as they arrive, reconciliation when one was
  missed, and cancelling a subscription at the end of its period.

  Split out of `Gamend.Payments`, which still exposes every function here under
  the same name.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Gamend.Accounts.User
  alias Gamend.Payments
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Params
  alias Gamend.Payments.Product
  alias Gamend.Payments.Purchase
  alias Gamend.Repo

  @spec create_stripe_checkout(User.t(), map()) ::
          {:ok,
           %{
             purchase: Purchase.t(),
             checkout_url: String.t() | nil,
             provider_session_id: String.t() | nil
           }}
          | {:error, term()}
  def create_stripe_checkout(%User{} = user, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Params.normalize()
      |> Payments.client_checkout_attrs()
      # Server-side and last, so a client can never name someone else's customer.
      |> Map.put("stripe_customer_id", stripe_customer_id(user))

    with {:ok, provider_product} <- Payments.resolve_provider_product("stripe", attrs),
         :ok <- Payments.ensure_checkout_allowed(user, provider_product, attrs),
         {:ok, purchase} <- Payments.create_purchase(user, provider_product, attrs) do
      case Payments.stripe_adapter().create_checkout_session(purchase, provider_product, attrs) do
        {:ok, session} ->
          with {:ok, updated_purchase} <-
                 Payments.mark_purchase_requires_action(purchase, session) do
            {:ok,
             %{
               purchase: updated_purchase,
               checkout_url: session["url"],
               provider_session_id: session["id"]
             }}
          end

        {:error, reason} ->
          Payments.mark_purchase_failed(purchase, "stripe_checkout_session_failed", reason)
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The Stripe customer this account has paid as, or nil: the newest Stripe
  purchase whose stored checkout session names one. Stripe creates the customer
  at checkout (subscriptions always; one-off payments since
  `customer_creation: "always"`), and `checkout.session.completed` stores the
  session on the purchase.
  """
  @spec stripe_customer_id(User.t()) :: String.t() | nil
  def stripe_customer_id(%User{id: user_id}) do
    from(p in Purchase,
      where: p.user_id == ^user_id and p.provider == "stripe",
      order_by: [desc: p.inserted_at],
      select: p.raw_provider_payload
    )
    |> Repo.all()
    |> Enum.find_value(&payload_customer_id/1)
  end

  defp payload_customer_id(%{} = payload) do
    [payload["stripe_session"], payload["stripe_subscription"]]
    |> Enum.find_value(fn
      %{"customer" => "cus_" <> _ = id} -> id
      %{"customer" => %{"id" => "cus_" <> _ = id}} -> id
      _ -> nil
    end)
  end

  defp payload_customer_id(_payload), do: nil

  @doc """
  Open Stripe's customer portal for this account: cancel, change card, download
  invoices. `{:error, :no_stripe_customer}` when the account never paid through
  Stripe Checkout.
  """
  @spec create_stripe_billing_portal(User.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def create_stripe_billing_portal(%User{} = user, return_url) when is_binary(return_url) do
    with customer_id when is_binary(customer_id) <- stripe_customer_id(user),
         {:ok, %{"url" => url}} when is_binary(url) <-
           Payments.stripe_adapter().create_billing_portal_session(customer_id, return_url) do
      {:ok, url}
    else
      nil -> {:error, :no_stripe_customer}
      {:ok, _session} -> {:error, :stripe_portal_without_url}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec handle_stripe_webhook(binary(), binary() | nil) :: {:ok, atom()} | {:error, term()}
  def handle_stripe_webhook(raw_body, signature) when is_binary(raw_body) do
    with {:ok, event} <- Payments.stripe_adapter().verify_webhook(raw_body, signature),
         event <- Params.normalize(event),
         {:ok, event_id} <- Params.required_value(event, "id"),
         event_type when is_binary(event_type) <- event["type"] do
      Payments.claim_provider_event("stripe", event_id, event_type, event, fn ->
        process_stripe_event(event)
      end)
    else
      nil -> {:error, :missing_event_type}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec reconcile_stripe_purchase(Purchase.t()) ::
          {:ok, %{purchase: Purchase.t(), result: atom(), stripe_session: map()}}
          | {:error, term()}
  def reconcile_stripe_purchase(
        %Purchase{
          provider: "stripe",
          provider_transaction_id: "cs_" <> _rest = session_id
        } = purchase
      ) do
    with {:ok, session} <- Payments.stripe_adapter().retrieve_checkout_session(session_id),
         session <- Params.normalize(session),
         :ok <- ensure_stripe_session_matches_purchase(purchase, session),
         {:ok, updated_purchase, result} <-
           reconcile_stripe_purchase_from_session(purchase, session) do
      {:ok, %{purchase: updated_purchase, result: result, stripe_session: session}}
    end
  end

  def reconcile_stripe_purchase(%Purchase{provider: "stripe"}),
    do: {:error, :missing_stripe_session_id}

  def reconcile_stripe_purchase(%Purchase{}), do: {:error, :not_stripe_purchase}

  @spec cancel_stripe_subscription_at_period_end(User.t(), Ecto.UUID.t()) ::
          {:ok,
           %{purchase: Purchase.t(), entitlement: Entitlement.t(), stripe_subscription: map()}}
          | {:error, term()}
  def cancel_stripe_subscription_at_period_end(%User{} = user, entitlement_id)
      when is_binary(entitlement_id) do
    with {:ok, %Entitlement{} = entitlement} <-
           Payments.get_user_subscription_entitlement(user, entitlement_id),
         %Purchase{} = purchase <- entitlement.source_purchase,
         {:ok, subscription_id} <- stripe_subscription_id(purchase),
         {:ok, subscription} <-
           Payments.stripe_adapter().cancel_subscription_at_period_end(subscription_id),
         subscription <- Params.normalize(subscription),
         {:ok, updated_purchase} <-
           update_purchase_from_stripe_subscription(
             purchase,
             subscription,
             "cancel_at_period_end"
           ),
         {:ok, updated_entitlements} <-
           update_entitlements_from_stripe_subscription(updated_purchase, subscription) do
      updated_entitlement =
        Enum.find(updated_entitlements, &(&1.id == entitlement.id)) ||
          Entitlement
          |> Repo.get(entitlement_id)
          |> Repo.preload([:product, :source_purchase])

      {:ok,
       %{
         purchase: updated_purchase,
         entitlement: updated_entitlement,
         stripe_subscription: subscription
       }}
    else
      %Purchase{} -> {:error, :not_stripe_subscription}
      {:error, reason} -> {:error, reason}
    end
  end

  def cancel_stripe_subscription_at_period_end(%User{}, _entitlement_id),
    do: {:error, :invalid_entitlement_id}

  defp process_stripe_event(%{
         "type" => "checkout.session.completed",
         "data" => %{"object" => object}
       })
       when is_map(object) do
    with {:ok, purchase} <- Payments.purchase_from_provider_object(object),
         {:ok, updated} <- update_purchase_from_stripe_session(purchase, object) do
      if stripe_session_paid?(object) do
        with {:ok, _purchase} <- Payments.fulfill_purchase(updated, %{"stripe_session" => object}) do
          {:ok, :processed}
        end
      else
        {:ok, :processed}
      end
    end
  end

  defp process_stripe_event(%{
         "type" => "checkout.session.async_payment_succeeded",
         "data" => %{"object" => object}
       })
       when is_map(object) do
    with {:ok, purchase} <- Payments.purchase_from_provider_object(object),
         {:ok, updated} <- update_purchase_from_stripe_session(purchase, object),
         {:ok, _purchase} <- Payments.fulfill_purchase(updated, %{"stripe_session" => object}) do
      {:ok, :processed}
    end
  end

  defp process_stripe_event(%{
         "type" => "checkout.session.async_payment_failed",
         "data" => %{"object" => object}
       })
       when is_map(object) do
    with {:ok, purchase} <- Payments.purchase_from_provider_object(object),
         {:ok, _purchase, :failed} <-
           update_purchase_from_stripe_reconciliation(purchase, object, "failed", :failed) do
      {:ok, :processed}
    end
  end

  defp process_stripe_event(%{"type" => "charge.succeeded", "data" => %{"object" => object}})
       when is_map(object) do
    with {:ok, purchase} <- Payments.purchase_from_provider_object(object),
         {:ok, _purchase} <- update_purchase_from_stripe_charge(purchase, object) do
      {:ok, :processed}
    else
      {:error, :purchase_not_found} -> {:ok, :ignored}
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_stripe_event(%{
         "type" => "checkout.session.expired",
         "data" => %{"object" => object}
       })
       when is_map(object) do
    with {:ok, purchase} <- Payments.purchase_from_provider_object(object) do
      _ =
        purchase
        |> Purchase.changeset(%{
          status: "cancelled",
          raw_provider_payload:
            Params.merge_payload(purchase.raw_provider_payload, %{
              "stripe_session" => object
            })
        })
        |> Repo.update()
        |> Payments.tap_bump({:payments, :purchase_version})

      {:ok, :processed}
    end
  end

  defp process_stripe_event(%{"type" => type, "data" => %{"object" => object}})
       when type in [
              "charge.refunded",
              "refund.created",
              "refund.updated",
              "charge.refund.updated",
              "charge.dispute.created",
              "charge.dispute.funds_withdrawn"
            ] and is_map(object) do
    # Only a refund that actually succeeded revokes.
    #
    # `refund.created` and `refund.updated` fire for pending, failed and
    # cancelled refunds too, and every one of them revoked the entitlement — so
    # a refund that failed left the customer charged *and* without the goods,
    # with nothing to put it back. A partial `charge.refunded` was treated as a
    # full one for the same reason.
    if Payments.reversal_effective?(type, object) do
      with {:ok, purchase} <- Payments.purchase_from_provider_object(object),
           {:ok, _purchase} <-
             Payments.revoke_purchase(purchase, %{
               "status" => stripe_reversal_status(type),
               "reason" => type,
               "payload" => %{"stripe_event_object" => object}
             }) do
        {:ok, :processed}
      else
        {:error, :purchase_not_found} -> {:ok, :ignored}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, :ignored}
    end
  end

  defp process_stripe_event(%{
         "type" => "customer.subscription.updated",
         "data" => %{"object" => object}
       })
       when is_map(object) do
    with {:ok, purchase} <- Payments.purchase_from_provider_object(object),
         {:ok, updated} <-
           update_purchase_from_stripe_subscription(purchase, object, "subscription_updated"),
         {:ok, _entitlements} <- update_entitlements_from_stripe_subscription(updated, object) do
      {:ok, :processed}
    else
      {:error, :purchase_not_found} -> {:ok, :ignored}
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_stripe_event(%{
         "type" => "customer.subscription.deleted",
         "data" => %{"object" => object}
       })
       when is_map(object) do
    with {:ok, purchase} <- Payments.purchase_from_provider_object(object),
         {:ok, updated} <-
           update_purchase_from_stripe_subscription(purchase, object, "subscription_deleted"),
         {:ok, _purchase} <-
           Payments.revoke_purchase(updated, %{
             "status" => "cancelled",
             "reason" => "customer.subscription.deleted",
             "payload" => %{"stripe_subscription" => object}
           }) do
      {:ok, :processed}
    else
      {:error, :purchase_not_found} -> {:ok, :ignored}
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_stripe_event(_event), do: {:ok, :ignored}

  defp ensure_stripe_session_matches_purchase(%Purchase{} = purchase, session) do
    metadata = session["metadata"] || %{}

    cond do
      stripe_metadata_purchase_mismatch?(metadata["purchase_id"], purchase.id) ->
        {:error, :stripe_session_purchase_mismatch}

      is_binary(metadata["order_id"]) and metadata["order_id"] != purchase.order_id ->
        {:error, :stripe_session_order_mismatch}

      true ->
        :ok
    end
  end

  defp stripe_metadata_purchase_mismatch?(nil, _purchase_id), do: false
  defp stripe_metadata_purchase_mismatch?("", _purchase_id), do: false
  defp stripe_metadata_purchase_mismatch?(purchase_id, purchase_id), do: false

  defp stripe_metadata_purchase_mismatch?(purchase_id, _expected_id)
       when is_binary(purchase_id),
       do: true

  defp stripe_metadata_purchase_mismatch?(_purchase_id, _expected_id), do: true

  defp reconcile_stripe_purchase_from_session(%Purchase{status: "completed"} = purchase, session) do
    if stripe_session_paid?(session) do
      with {:ok, updated} <- update_purchase_from_stripe_session(purchase, session),
           {:ok, _entitlements} <- maybe_update_entitlements_from_stripe_purchase(updated) do
        {:ok, Payments.preload_purchase(updated), :already_completed}
      end
    else
      {:ok, Payments.preload_purchase(purchase), :already_completed}
    end
  end

  defp reconcile_stripe_purchase_from_session(%Purchase{status: status} = purchase, _session)
       when status in ["refunded", "revoked"] do
    {:ok, Payments.preload_purchase(purchase), :unchanged}
  end

  defp reconcile_stripe_purchase_from_session(%Purchase{} = purchase, session) do
    cond do
      stripe_session_paid?(session) ->
        with {:ok, updated} <- update_purchase_from_stripe_session(purchase, session),
             {:ok, fulfilled} <-
               Payments.fulfill_purchase(
                 updated,
                 stripe_reconciliation_payload(session, "fulfilled")
               ) do
          {:ok, fulfilled, :fulfilled}
        end

      session["status"] == "expired" ->
        update_purchase_from_stripe_reconciliation(purchase, session, "cancelled", :cancelled)

      stripe_payment_failed?(session) ->
        update_purchase_from_stripe_reconciliation(purchase, session, "failed", :failed)

      session["status"] == "open" ->
        update_purchase_from_stripe_reconciliation(
          purchase,
          session,
          "requires_action",
          :still_open
        )

      true ->
        update_purchase_from_stripe_reconciliation(
          purchase,
          session,
          "requires_action",
          :payment_processing
        )
    end
  end

  defp stripe_session_paid?(%{"payment_status" => status})
       when status in ["paid", "no_payment_required"],
       do: true

  defp stripe_session_paid?(_session), do: false

  defp stripe_payment_failed?(session) do
    session["status"] == "complete" and
      stripe_payment_intent_status(session) in ["canceled", "requires_payment_method"]
  end

  defp stripe_payment_intent_status(%{"payment_intent" => %{"status" => status}}), do: status
  defp stripe_payment_intent_status(_session), do: nil

  defp update_purchase_from_stripe_reconciliation(%Purchase{} = purchase, session, status, result) do
    purchase
    |> Purchase.changeset(%{
      status: status,
      raw_provider_payload:
        Params.merge_payload(
          purchase.raw_provider_payload,
          stripe_reconciliation_payload(session, result)
        )
    })
    |> Repo.update()
    |> Payments.tap_bump({:payments, :purchase_version})
    |> case do
      {:ok, updated} -> {:ok, Payments.preload_purchase(updated), result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stripe_reconciliation_payload(session, result) do
    %{
      "stripe_session" => session,
      "stripe_reconciliation" => %{
        "result" => to_string(result),
        "reconciled_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
      }
    }
  end

  defp update_purchase_from_stripe_session(%Purchase{} = purchase, object) do
    subscription = stripe_session_subscription(purchase, object)
    amount = object["amount_total"] || purchase.amount
    currency = object["currency"] |> Params.normalize_currency() || purchase.currency

    metadata =
      purchase
      |> stripe_purchase_metadata(object)
      |> stripe_subscription_metadata(subscription)

    purchase
    |> Purchase.changeset(%{
      provider_transaction_id: object["id"] || purchase.provider_transaction_id,
      amount: amount,
      currency: currency,
      expires_at: stripe_subscription_period_end(subscription) || purchase.expires_at,
      metadata: metadata,
      raw_provider_payload:
        stripe_payload_with_subscription(
          purchase.raw_provider_payload,
          %{"stripe_session" => object},
          subscription
        )
    })
    |> Repo.update()
    |> Payments.tap_bump({:payments, :purchase_version})
  end

  defp update_purchase_from_stripe_subscription(
         %Purchase{} = purchase,
         subscription,
         reconciliation_result
       )
       when is_map(subscription) do
    metadata =
      purchase
      |> stripe_purchase_metadata(%{})
      |> stripe_subscription_metadata(subscription)

    purchase
    |> Purchase.changeset(%{
      expires_at: stripe_subscription_period_end(subscription) || purchase.expires_at,
      metadata: metadata,
      raw_provider_payload:
        Params.merge_payload(purchase.raw_provider_payload, %{
          "stripe_subscription" => subscription,
          "stripe_subscription_reconciliation" => %{
            "result" => reconciliation_result,
            "reconciled_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
          }
        })
    })
    |> Repo.update()
    |> Payments.tap_bump({:payments, :purchase_version})
    |> case do
      {:ok, updated} -> {:ok, Payments.preload_purchase(updated)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_entitlements_from_stripe_subscription(%Purchase{} = purchase, subscription)
       when is_map(subscription) do
    metadata = stripe_entitlement_subscription_metadata(subscription)
    expires_at = stripe_subscription_period_end(subscription)

    from(e in Entitlement, where: e.source_purchase_id == ^purchase.id)
    |> Repo.all()
    |> Enum.reduce_while({:ok, []}, fn entitlement, {:ok, updated_entitlements} ->
      attrs = %{
        metadata: Params.merge_payload(entitlement.metadata || %{}, metadata)
      }

      attrs =
        if expires_at do
          Map.put(attrs, :expires_at, expires_at)
        else
          attrs
        end

      case entitlement |> Entitlement.changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          Payments.after_entitlement_changed(updated)

          {:cont,
           {:ok, [Repo.preload(updated, [:product, :source_purchase]) | updated_entitlements]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entitlements} -> {:ok, Enum.reverse(entitlements)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_update_entitlements_from_stripe_purchase(%Purchase{} = purchase) do
    case subscription_object_id((purchase.raw_provider_payload || %{})["stripe_subscription"]) do
      nil ->
        {:ok, []}

      _subscription_id ->
        update_entitlements_from_stripe_subscription(
          purchase,
          purchase.raw_provider_payload["stripe_subscription"]
        )
    end
  end

  defp update_purchase_from_stripe_charge(%Purchase{} = purchase, object) do
    metadata = stripe_purchase_metadata(purchase, object)

    purchase
    |> Purchase.changeset(%{
      provider_original_transaction_id: object["id"] || purchase.provider_original_transaction_id,
      metadata: metadata,
      raw_provider_payload:
        Params.merge_payload(purchase.raw_provider_payload, %{
          "stripe_charge" => object
        })
    })
    |> Repo.update()
    |> Payments.tap_bump({:payments, :purchase_version})
  end

  defp stripe_reversal_status(type)
       when type in [
              "charge.refunded",
              "refund.created",
              "refund.updated",
              "charge.refund.updated"
            ],
       do: "refunded"

  defp stripe_reversal_status(_type), do: "revoked"

  defp stripe_purchase_metadata(%Purchase{} = purchase, object) do
    metadata = purchase.metadata || %{}

    metadata
    |> Params.put_if_present(
      "stripe_session_id",
      object["id"],
      object["object"] == "checkout.session"
    )
    |> Params.put_if_present("stripe_payment_intent_id", object["payment_intent"], true)
    |> Params.put_if_present("stripe_charge_id", object["id"], object["object"] == "charge")
    |> Params.put_if_present(
      "stripe_subscription_id",
      stripe_session_subscription_id(object),
      true
    )
  end

  defp stripe_subscription_metadata(metadata, nil), do: metadata

  defp stripe_subscription_metadata(metadata, subscription) when is_map(subscription) do
    metadata
    |> Params.put_if_present("stripe_subscription_id", subscription["id"], true)
    |> Params.put_if_present("stripe_subscription_status", subscription["status"], true)
    |> Params.put_if_present(
      "stripe_subscription_current_period_end",
      Params.datetime_iso(stripe_subscription_period_end(subscription)),
      true
    )
    |> Map.put(
      "stripe_subscription_cancel_at_period_end",
      subscription["cancel_at_period_end"] == true
    )
  end

  defp stripe_entitlement_subscription_metadata(subscription) when is_map(subscription) do
    %{
      "stripe_subscription_id" => subscription["id"],
      "stripe_subscription_status" => subscription["status"],
      "stripe_subscription_cancel_at_period_end" => subscription["cancel_at_period_end"] == true,
      "stripe_subscription_current_period_end" =>
        Params.datetime_iso(stripe_subscription_period_end(subscription))
    }
  end

  defp stripe_session_subscription(%Purchase{product: %Product{kind: "subscription"}}, object) do
    case object["subscription"] do
      %{} = subscription ->
        subscription

      subscription_id when is_binary(subscription_id) and subscription_id != "" ->
        case Payments.stripe_adapter().retrieve_subscription(subscription_id) do
          {:ok, subscription} ->
            Params.normalize(subscription)

          {:error, reason} ->
            Logger.warning(
              "Stripe subscription retrieve failed subscription_id=#{subscription_id} reason=#{inspect(reason)}"
            )

            %{"id" => subscription_id}
        end

      _ ->
        nil
    end
  end

  defp stripe_session_subscription(_purchase, _object), do: nil

  defp stripe_session_subscription_id(%{"subscription" => %{"id" => id}}) when is_binary(id),
    do: id

  defp stripe_session_subscription_id(%{"subscription" => id}) when is_binary(id), do: id
  defp stripe_session_subscription_id(_object), do: nil

  defp stripe_subscription_id(%Purchase{} = purchase) do
    metadata = purchase.metadata || %{}
    payload = purchase.raw_provider_payload || %{}

    candidates = [
      metadata["stripe_subscription_id"],
      stripe_session_subscription_id(payload["stripe_session"] || %{}),
      subscription_object_id(payload["stripe_subscription"]),
      purchase.provider_original_transaction_id
    ]

    case Enum.find(candidates, &stripe_subscription_id?/1) do
      nil -> {:error, :missing_stripe_subscription_id}
      subscription_id -> {:ok, subscription_id}
    end
  end

  defp subscription_object_id(%{"id" => id}) when is_binary(id), do: id
  defp subscription_object_id(_subscription), do: nil

  defp stripe_subscription_id?("sub_" <> _rest), do: true
  defp stripe_subscription_id?(_value), do: false

  defp stripe_payload_with_subscription(existing, incoming, nil),
    do: Params.merge_payload(existing, incoming)

  defp stripe_payload_with_subscription(existing, incoming, subscription)
       when is_map(subscription) do
    Params.merge_payload(existing, Map.put(incoming, "stripe_subscription", subscription))
  end

  defp stripe_subscription_period_end(nil), do: nil

  defp stripe_subscription_period_end(subscription) when is_map(subscription) do
    top_level_period_end =
      Params.unix_seconds_to_datetime(subscription["current_period_end"]) ||
        Params.unix_seconds_to_datetime(subscription["cancel_at"])

    top_level_period_end || stripe_subscription_item_period_end(subscription)
  end

  defp stripe_subscription_item_period_end(%{"items" => %{"data" => items}})
       when is_list(items) do
    items
    |> Enum.map(&Params.unix_seconds_to_datetime(&1["current_period_end"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix/1, fn -> nil end)
  end

  defp stripe_subscription_item_period_end(_subscription), do: nil
end
