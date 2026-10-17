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
  alias Gamend.Payments.Counters
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Params
  alias Gamend.Payments.Product
  alias Gamend.Payments.ProviderConfig
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.Upgrades
  alias Gamend.Repo

  # What takes money back: a refund, or a dispute. `charge.dispute.closed`
  # is handled apart (a dispute the seller won gives it back).
  @reversal_types ~w(
    charge.refunded refund.created refund.updated charge.refund.updated
    charge.dispute.created charge.dispute.funds_withdrawn
  )

  @doc """
  Open a Stripe Checkout for `attrs` (a client's: product, quantity, return
  URLs). Options are the server's own and never read from `attrs`:

    * `:trial_end` — a `DateTime` a subscription's first charge waits for
      (the card is taken now, the subscription starts `trialing`). Ignored for
      a one-off product, and when it is under 48 hours or over two years
      away, where Stripe would refuse it. For a host that grants a free
      period of its own: buying during it keeps the days already given.

  A subscription bought to replace a shorter one (`Upgrades`, monthly to
  yearly) waits for the period already paid for: its `trial_end` is the
  later of `:trial_end` and that period's end (`Upgrades.trial_end/3`).
  """
  @spec create_stripe_checkout(User.t(), map(), keyword()) ::
          {:ok,
           %{
             purchase: Purchase.t(),
             checkout_url: String.t() | nil,
             provider_session_id: String.t() | nil
           }}
          | {:error, term()}
  def create_stripe_checkout(%User{} = user, attrs, opts \\ []) when is_map(attrs) do
    attrs =
      attrs
      |> Params.normalize()
      |> Payments.client_checkout_attrs()
      # Server-side and last, so a client can never name someone else's
      # customer or grant itself a trial.
      |> Map.put("stripe_customer_id", stripe_customer_id(user))

    Payments.with_checkout_lock(user, fn -> open_checkout(user, attrs, opts) end)
  end

  defp open_checkout(%User{} = user, attrs, opts) do
    with {:ok, provider_product} <- Payments.resolve_provider_product("stripe", attrs),
         attrs =
           put_trial_end(
             attrs,
             Upgrades.trial_end(user.id, provider_product.product, opts[:trial_end])
           ),
         :ok <- ensure_stripe_checkout_allowed(user, provider_product, attrs),
         {:ok, purchase} <- Payments.create_purchase(user, provider_product, attrs) do
      case Payments.stripe_adapter().create_checkout_session(purchase, provider_product, attrs) do
        {:ok, session} ->
          with {:ok, updated_purchase} <-
                 Payments.mark_purchase_requires_action(purchase, session) do
            Counters.count("checkout.opened", Payments.purchase_dims(updated_purchase))

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
      {:error, reason} ->
        Payments.count_checkout_refused("stripe", reason)
        {:error, reason}
    end
  end

  defp put_trial_end(attrs, %DateTime{} = trial_end),
    do: Map.put(attrs, "trial_end", DateTime.to_unix(trial_end))

  defp put_trial_end(attrs, _trial_end), do: attrs

  # An entitlement has one open checkout at a time, and an abandoned Stripe one
  # (Back from the payment page, a closed tab) stayed open until Stripe expired
  # it, 24 hours by default: the buyer who left the yearly plan for lifetime got
  # `:purchase_already_in_progress`. A new request is the buyer's intent now, so
  # each open Stripe session for that entitlement is expired at Stripe and its
  # purchase cancelled, and the checks run again. Stripe expires only an open
  # session, so one paid (or being paid) meanwhile stays and still refuses, or
  # answers `:already_owned` once fulfilled. Another provider's open purchase
  # is left as it is, and refuses as before.
  defp ensure_stripe_checkout_allowed(%User{} = user, provider_product, attrs) do
    case Payments.ensure_checkout_allowed(user, provider_product, attrs) do
      {:error, :purchase_already_in_progress} ->
        key = Payments.product_entitlement_key(provider_product.product)

        user.id
        |> Payments.purchases_in_progress(key)
        |> Enum.each(&release_stripe_checkout/1)

        Payments.ensure_checkout_allowed(user, provider_product, attrs)

      result ->
        result
    end
  end

  defp release_stripe_checkout(
         %Purchase{provider: "stripe", provider_transaction_id: "cs_" <> _rest = session_id} =
           purchase
       ) do
    with {:ok, session} <- Payments.stripe_adapter().expire_checkout_session(session_id),
         %{"status" => "expired"} = session <- Params.normalize(session) do
      mark_stripe_checkout_expired(purchase, session)
    else
      _not_open ->
        # Read it back and let the purchase follow Stripe: cancelled if it had
        # expired, fulfilled if it was paid, left open while a payment clears.
        with {:error, reason} <- reconcile_stripe_purchase(purchase) do
          Logger.warning(
            "Stripe checkout could not be released",
            purchase_id: purchase.id,
            order_id: purchase.order_id,
            reason: inspect(reason)
          )
        end
    end
  end

  defp release_stripe_checkout(%Purchase{}), do: :ok

  defp mark_stripe_checkout_expired(%Purchase{} = purchase, session) do
    purchase
    |> Purchase.changeset(%{
      status: "cancelled",
      raw_provider_payload:
        Params.merge_payload(purchase.raw_provider_payload, %{"stripe_session" => session})
    })
    |> Repo.update()
    |> Payments.tap_bump({:payments, :purchase_version})
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
      Counters.count("portal.opened")
      {:ok, url}
    else
      nil ->
        {:error, :no_stripe_customer}

      {:ok, _session} ->
        Logger.warning("Stripe portal session came back without a url user_id=#{user.id}")
        {:error, :stripe_portal_without_url}

      {:error, reason} ->
        # Usually the portal is not activated in the Stripe Dashboard.
        Logger.warning(
          "Stripe portal session failed user_id=#{user.id} reason=#{inspect(reason) |> String.slice(0, 500)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Verify, record and handle one Stripe webhook delivery.

  Every answer is logged and counted (`payments.webhook`): a refused
  signature at warning (a wrong signing secret refuses every delivery, and
  only the logs say so), a handler that failed at error with the event's id
  and type (Stripe retries it, and it stays unprocessed in `provider_events`
  until one succeeds), and a processed or ignored one at info.
  """
  @spec handle_stripe_webhook(binary(), binary() | nil) :: {:ok, atom()} | {:error, term()}
  def handle_stripe_webhook(raw_body, signature) when is_binary(raw_body) do
    with {:ok, event} <- Payments.stripe_adapter().verify_webhook(raw_body, signature),
         event <- Params.normalize(event),
         {:ok, event_id} <- Params.required_value(event, "id"),
         event_type when is_binary(event_type) <- event["type"] do
      check_event_version(event, event_id)

      "stripe"
      |> Payments.claim_provider_event(event_id, event_type, event, fn ->
        process_stripe_event(event)
      end)
      |> report_webhook(event_id, event_type)
    else
      nil -> refused_webhook(:missing_event_type)
      {:error, reason} -> refused_webhook(reason)
    end
  end

  # An event's object comes in the webhook endpoint's API version, set in the
  # Stripe Dashboard, not in the version this server asks with. Inside one
  # release Stripe only adds fields, so another date of the same release is
  # fine; another release reads other shapes (a period moved, a field gone).
  # Still handled, since refusing it would lose a payment, but said loudly.
  defp check_event_version(event, event_id) do
    expected = ProviderConfig.stripe_api_version()
    sent = event["api_version"]

    if is_binary(sent) and
         ProviderConfig.stripe_api_release(sent) != ProviderConfig.stripe_api_release(expected) do
      Logger.warning(
        "Stripe webhook in API version #{sent}, expected the #{ProviderConfig.stripe_api_release(expected)} release " <>
          "(#{expected}) event_id=#{event_id}: set the webhook endpoint's version in the Stripe Dashboard"
      )

      Counters.count("webhook", provider: "stripe", result: "version_mismatch")
    end
  end

  defp report_webhook({:ok, result} = answer, event_id, event_type) do
    Logger.info("Stripe webhook #{result} type=#{event_type} event_id=#{event_id}")
    Counters.count("webhook", provider: "stripe", type: event_type, result: result)
    answer
  end

  defp report_webhook({:error, reason} = answer, event_id, event_type) do
    Logger.error(
      "Stripe webhook failed type=#{event_type} event_id=#{event_id} " <>
        "reason=#{inspect(reason) |> String.slice(0, 1_000)}"
    )

    Counters.count("webhook", provider: "stripe", type: event_type, result: "failed")
    answer
  end

  defp refused_webhook(reason) do
    Logger.warning(
      "Stripe webhook refused reason=#{inspect(reason) |> String.slice(0, 500)} " <>
        "(check the endpoint's signing secret)"
    )

    Counters.count("webhook",
      provider: "stripe",
      result: "refused",
      reason: Payments.provider_error_code(reason)
    )

    {:error, reason}
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
  def cancel_stripe_subscription_at_period_end(%User{} = user, entitlement_id),
    do: put_stripe_cancel_at_period_end(user, entitlement_id, :cancel)

  @doc """
  Takes back a cancellation scheduled for the period end, so the
  subscription renews again. Stripe refuses it once the subscription ended.
  """
  @spec resume_stripe_subscription(User.t(), Ecto.UUID.t()) ::
          {:ok,
           %{purchase: Purchase.t(), entitlement: Entitlement.t(), stripe_subscription: map()}}
          | {:error, term()}
  def resume_stripe_subscription(%User{} = user, entitlement_id),
    do: put_stripe_cancel_at_period_end(user, entitlement_id, :resume)

  defp put_stripe_cancel_at_period_end(user, entitlement_id, action)
       when is_binary(entitlement_id) do
    with {:ok, %Entitlement{} = entitlement} <-
           Payments.get_user_subscription_entitlement(user, entitlement_id),
         %Purchase{} = purchase <- entitlement.source_purchase,
         {:ok, subscription_id} <- stripe_subscription_id(purchase),
         {:ok, subscription} <- stripe_put_cancel_at_period_end(subscription_id, action),
         subscription <- Params.normalize(subscription),
         {:ok, updated_purchase} <-
           update_purchase_from_stripe_subscription(
             purchase,
             subscription,
             stripe_cancel_result(action)
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

  defp put_stripe_cancel_at_period_end(%User{}, _entitlement_id, _action),
    do: {:error, :invalid_entitlement_id}

  defp stripe_put_cancel_at_period_end(subscription_id, :cancel),
    do: Payments.stripe_adapter().cancel_subscription_at_period_end(subscription_id)

  defp stripe_put_cancel_at_period_end(subscription_id, :resume),
    do: Payments.stripe_adapter().resume_subscription(subscription_id)

  defp stripe_cancel_result(:cancel), do: "cancel_at_period_end"
  defp stripe_cancel_result(:resume), do: "resume"

  # A checkout session this server did not open (a Payment Link, a product
  # sold another way, another app on the same Stripe account) carries none of
  # the metadata `Providers.Stripe` puts on ours. It used to answer 404, which
  # Stripe retries for three days and, past that, can disable the endpoint
  # over, taking every real delivery with it.
  defp process_stripe_event(%{
         "type" => "checkout.session." <> step,
         "data" => %{"object" => object}
       })
       when is_map(object) do
    if ours?(object), do: process_checkout_session(step, object), else: {:ok, :ignored}
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

  defp process_stripe_event(%{"type" => type, "data" => %{"object" => object}})
       when type in @reversal_types and is_map(object) do
    # Only a reversal that took the money revokes: a refund that succeeded in
    # full, or a dispute. `Payments.reversal_effective?/2` says which.
    if Payments.reversal_effective?(type, object) do
      case reversal_purchase(object) do
        {:ok, purchase} ->
          reverse_purchase(type, purchase, object)

        {:error, :purchase_not_found} ->
          unlinked_reversal(type, object)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, :ignored}
    end
  end

  # A dispute the seller won hands a one-off purchase back. A subscription's
  # was cancelled when the dispute opened (`end_subscription/1`), so there is
  # nothing to resume; the buyer can subscribe again.
  defp process_stripe_event(%{"type" => "charge.dispute.closed", "data" => %{"object" => object}})
       when is_map(object) do
    with true <- object["status"] in ["won", "warning_closed"],
         {:ok, purchase} <- reversal_purchase(object),
         {:ok, %Purchase{}} <- Payments.restore_purchase(purchase, %{"stripe_dispute" => object}) do
      {:ok, :processed}
    else
      false -> {:ok, :ignored}
      {:ok, :unchanged} -> {:ok, :ignored}
      {:error, :purchase_not_found} -> {:ok, :ignored}
      {:error, reason} -> {:error, reason}
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

  defp process_checkout_session("completed", object) do
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

  defp process_checkout_session("async_payment_succeeded", object) do
    with {:ok, purchase} <- Payments.purchase_from_provider_object(object),
         {:ok, updated} <- update_purchase_from_stripe_session(purchase, object),
         {:ok, _purchase} <- Payments.fulfill_purchase(updated, %{"stripe_session" => object}) do
      {:ok, :processed}
    end
  end

  defp process_checkout_session("async_payment_failed", object) do
    with {:ok, purchase} <- Payments.purchase_from_provider_object(object),
         {:ok, _purchase, :failed} <-
           update_purchase_from_stripe_reconciliation(purchase, object, "failed", :failed) do
      {:ok, :processed}
    end
  end

  defp process_checkout_session("expired", object) do
    with {:ok, purchase} <- Payments.purchase_from_provider_object(object) do
      _ = mark_stripe_checkout_expired(purchase, object)
      {:ok, :processed}
    end
  end

  defp process_checkout_session(_step, _object), do: {:ok, :ignored}

  defp ours?(%{"metadata" => %{} = metadata}),
    do: is_binary(metadata["purchase_id"]) or is_binary(metadata["order_id"])

  defp ours?(_object), do: false

  # The purchase a refund or dispute is about. A one-off payment's charge
  # carries the purchase id (`payment_intent_data.metadata`), or was linked by
  # `charge.succeeded`. A subscription's invoice charge carries neither:
  # Stripe copies `subscription_data.metadata` onto the subscription only. So
  # those were never found, and a dispute on a subscription payment revoked
  # nothing. The payment is traced to its invoice (`InvoicePayment`), whose
  # subscription is the purchase's `provider_original_transaction_id`.
  defp reversal_purchase(object) do
    case Payments.purchase_from_provider_object(object) do
      {:error, :purchase_not_found} -> purchase_from_invoice_subscription(object)
      other -> other
    end
  end

  defp purchase_from_invoice_subscription(object) do
    adapter = Payments.stripe_adapter()

    with "pi_" <> _ = payment_intent <- object_ref(object["payment_intent"]),
         true <-
           Code.ensure_loaded?(adapter) and function_exported?(adapter, :list_invoice_payments, 1),
         {:ok, %{"data" => [_ | _] = payments}} <- adapter.list_invoice_payments(payment_intent),
         "sub_" <> _ = subscription_id <- Enum.find_value(payments, &payment_subscription_id/1),
         %Purchase{} = purchase <-
           Payments.get_purchase_by_provider_original_transaction("stripe", subscription_id) do
      {:ok, purchase}
    else
      {:error, reason} -> {:error, reason}
      _not_found -> {:error, :purchase_not_found}
    end
  end

  defp payment_subscription_id(%{"invoice" => %{} = invoice}),
    do: object_ref(get_in(invoice, ["parent", "subscription_details", "subscription"]))

  defp payment_subscription_id(_payment), do: nil

  defp object_ref(%{"id" => id}) when is_binary(id), do: id
  defp object_ref(id) when is_binary(id), do: id
  defp object_ref(_value), do: nil

  defp reversal_charge_id(%{"object" => "charge", "id" => id}) when is_binary(id), do: id
  defp reversal_charge_id(%{"charge" => charge}), do: object_ref(charge)
  defp reversal_charge_id(_object), do: nil

  defp reverse_purchase(type, %Purchase{} = purchase, object) do
    with {:ok, revoked} <-
           Payments.revoke_purchase(purchase, %{
             "status" => stripe_reversal_status(type),
             "reason" => type,
             "payload" => %{"stripe_event_object" => object}
           }) do
      end_subscription(revoked)
      {:ok, :processed}
    end
  end

  # Money taken back from a subscription ends the subscription too. Revoking
  # the entitlement alone left Stripe renewing it: charged every period, with
  # nothing to show for it. A refund through `StripeRefunds` cancelled it
  # already, and the shared idempotency key makes this call answer that same
  # cancellation instead of trying a second. A failure is logged and left: the
  # entitlement is gone either way, and the subscription can be cancelled in
  # the Dashboard.
  defp end_subscription(%Purchase{product: %Product{kind: "subscription"}} = purchase) do
    adapter = Payments.stripe_adapter()

    with {:ok, subscription_id} <- stripe_subscription_id(purchase),
         false <-
           (purchase.metadata || %{})["stripe_subscription_status"] in ~w(canceled incomplete_expired),
         true <- function_exported?(adapter, :cancel_subscription_now, 2) do
      case adapter.cancel_subscription_now(subscription_id,
             idempotency_key: "refund-cancel-#{purchase.id}"
           ) do
        {:ok, _subscription} ->
          Logger.info(
            "Stripe subscription cancelled after a reversal subscription_id=#{subscription_id} purchase_id=#{purchase.id}"
          )

        {:error, reason} ->
          Logger.warning(
            "Stripe subscription not cancelled after a reversal subscription_id=#{subscription_id} " <>
              "purchase_id=#{purchase.id} reason=#{inspect(reason) |> String.slice(0, 500)}"
          )
      end
    end

    :ok
  end

  defp end_subscription(_purchase), do: :ok

  # Money moved on a charge no purchase here owns. Normal for a Stripe account
  # shared with something else; for this server's own sale it means a
  # purchase lost its link, and the goods were not taken back.
  defp unlinked_reversal(type, object) do
    Logger.warning(
      "Stripe #{type} matches no purchase id=#{object["id"]} charge=#{inspect(reversal_charge_id(object))}"
    )

    {:ok, :ignored}
  end

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

  # "cancelled" is final too. A session cannot be paid once it expired, and a
  # subscription that ended (or was cancelled by a refund) still reads paid
  # here: fulfilling it again would hand back what its end took away, until a
  # period end Stripe has already left behind.
  defp reconcile_stripe_purchase_from_session(%Purchase{status: status} = purchase, _session)
       when status in ["refunded", "revoked", "cancelled"] do
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
      # The subscription is what a renewal's charge leads back to
      # (`purchase_from_charge_subscription/1`): its invoices carry none of the
      # checkout's metadata.
      provider_original_transaction_id:
        purchase.provider_original_transaction_id ||
          subscription_object_id(subscription) || stripe_session_subscription_id(object),
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
      provider_original_transaction_id:
        purchase.provider_original_transaction_id || subscription_object_id(subscription),
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

  # Each write of a subscription moves its entitlements' end with it, as far
  # as the subscription has paid. Moving it to the new period end whatever the
  # status gave a renewal that failed (`past_due`, `unpaid`) the whole next
  # period free, for as long as Stripe kept the subscription. Now:
  #
  #   * active or trialing — the period end, and that is paid through;
  #   * past_due — what was paid through plus the grace days
  #     (`stripe_past_due_grace_days`) while Stripe retries the card;
  #   * anything else (unpaid, incomplete, paused) — what was paid through.
  #
  # "Paid through" rides on the row (`metadata["paid_through"]`), so a second
  # past_due write does not stack a second grace on the first.
  defp update_entitlements_from_stripe_subscription(%Purchase{} = purchase, subscription)
       when is_map(subscription) do
    metadata = stripe_entitlement_subscription_metadata(subscription)
    period_end = stripe_subscription_period_end(subscription)

    from(e in Entitlement, where: e.source_purchase_id == ^purchase.id)
    |> Repo.all()
    |> Enum.reduce_while({:ok, []}, fn entitlement, {:ok, updated_entitlements} ->
      {expires_at, paid_through} =
        subscription_access(entitlement, subscription["status"], period_end)

      attrs = %{
        metadata:
          (entitlement.metadata || %{})
          |> Params.merge_payload(metadata)
          |> Params.put_if_present("paid_through", Params.datetime_iso(paid_through), true)
      }

      attrs = if expires_at, do: Map.put(attrs, :expires_at, expires_at), else: attrs

      case entitlement |> Entitlement.changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          report_subscription_change(purchase, entitlement, updated)
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

  # `{expires_at, paid_through}` for a subscription status; a nil
  # `expires_at` leaves the row's end as it is.
  defp subscription_access(%Entitlement{} = entitlement, status, period_end) do
    paid_through =
      Params.parse_datetime((entitlement.metadata || %{})["paid_through"]) ||
        entitlement.expires_at

    cond do
      # No status on the object (a bare id) or a plan that pays: Stripe's end.
      is_nil(status) or status in ["active", "trialing"] ->
        {period_end, period_end || paid_through}

      is_nil(paid_through) ->
        {period_end, nil}

      status == "past_due" ->
        grace_end = DateTime.add(paid_through, past_due_grace_days(), :day)
        {earlier(period_end, grace_end), paid_through}

      true ->
        {earlier(period_end, paid_through), paid_through}
    end
  end

  defp earlier(nil, other), do: other
  defp earlier(%DateTime{} = one, %DateTime{} = other), do: Enum.min([one, other], DateTime)

  defp past_due_grace_days do
    case Gamend.Settings.get(Gamend.Payments.Settings, :stripe_past_due_grace_days) do
      days when is_integer(days) and days >= 0 -> days
      _unset -> 7
    end
  end

  # What changed on this write, logged and counted once: the old row is
  # compared with the new, so the webhook that repeats a change the player
  # made on the settings page counts nothing twice.
  defp report_subscription_change(
         %Purchase{} = purchase,
         %Entitlement{} = before,
         %Entitlement{} = now
       ) do
    old = before.metadata || %{}
    new = now.metadata || %{}
    status = new["stripe_subscription_status"]
    dims = [sku: (purchase.product && purchase.product.sku) || nil]

    changes =
      [
        {status == "past_due" and old["stripe_subscription_status"] != "past_due", "past_due"},
        {new["stripe_subscription_cancel_at_period_end"] == true and
           old["stripe_subscription_cancel_at_period_end"] != true, "cancel_scheduled"},
        {new["stripe_subscription_cancel_at_period_end"] == false and
           old["stripe_subscription_cancel_at_period_end"] == true, "resumed"},
        {status == "active" and later?(now.expires_at, before.expires_at), "renewed"}
      ]
      |> Enum.filter(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    Enum.each(changes, fn change ->
      Logger.info(
        "Stripe subscription #{change} subscription_id=#{new["stripe_subscription_id"]} " <>
          "purchase_id=#{purchase.id} user_id=#{purchase.user_id} expires_at=#{Params.datetime_iso(now.expires_at)}"
      )

      Counters.count("subscription." <> change, dims)
    end)
  end

  # Later by more than a day: a renewal moves the end a period on, while the
  # same period read twice (two clocks, a rounding) moves it by seconds.
  defp later?(%DateTime{} = now, %DateTime{} = before), do: DateTime.diff(now, before) > 86_400
  defp later?(_now, _before), do: false

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

  @doc false
  def stripe_subscription_id(%Purchase{} = purchase) do
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

  # A subscription's period is on its items (the latest, when they differ).
  defp stripe_subscription_period_end(subscription) when is_map(subscription),
    do: stripe_subscription_item_period_end(subscription)

  defp stripe_subscription_item_period_end(%{"items" => %{"data" => items}})
       when is_list(items) do
    items
    |> Enum.map(&Params.unix_seconds_to_datetime(&1["current_period_end"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix/1, fn -> nil end)
  end

  defp stripe_subscription_item_period_end(_subscription), do: nil
end
