defmodule Gamend.Payments.StripeLifecycleTest do
  @moduledoc """
  What happens to a Stripe purchase after its checkout: webhooks this server
  did not start, refunds and disputes (on one-off payments and on a
  subscription's), a dispute won, a renewal that failed, the sweep for a lost
  webhook, and the counters each one leaves.
  """
  use Gamend.DataCase

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog

  alias Gamend.AccountsFixtures
  alias Gamend.Analytics
  alias Gamend.Payments
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.Settings
  alias Gamend.Payments.StripeSweeper
  alias Gamend.SettingsHelpers

  defmodule NoopPaymentHooks do
    use Gamend.TestSupport.NoopHooks
  end

  # Ids say what Stripe would answer: `cs_paid_` sessions were paid,
  # `cs_expired_` ones expired. `pi_sub_<sub>` was paid by an invoice of
  # subscription `<sub>`; any other PaymentIntent by no invoice.
  defmodule StripeAdapter do
    def create_checkout_session(purchase, _provider_product, _attrs),
      do: {:ok, %{"id" => "cs_open_#{purchase.id}", "url" => "https://checkout.test"}}

    def expire_checkout_session(session_id),
      do: {:error, {:stripe_error, %{"code" => "checkout_session_not_open", "id" => session_id}}}

    def retrieve_checkout_session("cs_paid_" <> _rest = id),
      do:
        {:ok,
         %{
           "id" => id,
           "object" => "checkout.session",
           "status" => "complete",
           "payment_status" => "paid"
         }}

    def retrieve_checkout_session("cs_expired_" <> _rest = id),
      do:
        {:ok,
         %{
           "id" => id,
           "object" => "checkout.session",
           "status" => "expired",
           "payment_status" => "unpaid"
         }}

    def list_invoice_payments("pi_sub_" <> subscription) do
      send(self(), {:stripe_list_invoice_payments, "pi_sub_" <> subscription})

      {:ok,
       %{
         "object" => "list",
         "data" => [
           %{
             "object" => "invoice_payment",
             "status" => "paid",
             "invoice" => %{
               "id" => "in_1",
               "object" => "invoice",
               "parent" => %{
                 "type" => "subscription_details",
                 "subscription_details" => %{"subscription" => subscription}
               }
             }
           }
         ]
       }}
    end

    def list_invoice_payments(_payment_intent), do: {:ok, %{"object" => "list", "data" => []}}

    def cancel_subscription_now(subscription_id, opts) do
      send(self(), {:stripe_cancel_now, subscription_id, opts})
      {:ok, %{"id" => subscription_id, "object" => "subscription", "status" => "canceled"}}
    end

    def verify_webhook(raw_body, _signature), do: Jason.decode(raw_body)
  end

  @settings [:stripe_past_due_grace_days, :stripe_sandbox_secret_key, :environment]

  setup do
    original_stripe = Application.get_env(:gamend_core, :stripe_adapter)
    original_hooks = Application.get_env(:gamend_core, :hooks_module)
    original_settings = Map.new(@settings, &{&1, SettingsHelpers.get(:gamend_core, Settings, &1)})

    Application.put_env(:gamend_core, :stripe_adapter, StripeAdapter)
    Application.put_env(:gamend_core, :hooks_module, NoopPaymentHooks)

    on_exit(fn ->
      restore_env(:stripe_adapter, original_stripe)
      restore_env(:hooks_module, original_hooks)

      for {key, value} <- original_settings do
        if is_nil(value),
          do: SettingsHelpers.delete(:gamend_core, Settings, key),
          else: SettingsHelpers.put(:gamend_core, Settings, key, value)
      end
    end)

    %{user: AccountsFixtures.user_fixture()}
  end

  describe "webhooks this server did not start" do
    test "a checkout session without our metadata is ignored, never refused" do
      for type <- ~w(checkout.session.completed checkout.session.expired) do
        assert {:ok, :ignored} =
                 webhook(type, %{
                   "id" => "cs_foreign_1",
                   "object" => "checkout.session",
                   "payment_status" => "paid",
                   "metadata" => %{}
                 })
      end
    end

    test "a refund made outside this server counts only through charge.refunded", %{user: user} do
      purchase = paid_one_off(user)

      # A Dashboard refund: no purchase id on it, and it may be partial.
      assert {:ok, :ignored} =
               webhook("refund.created", %{
                 "id" => "re_dash_1",
                 "object" => "refund",
                 "status" => "succeeded",
                 "amount" => 100,
                 "charge" => "ch_one_1"
               })

      assert Repo.get!(Purchase, purchase.id).status == "completed"

      # A partial charge.refunded is not a revocation either.
      assert {:ok, :ignored} =
               webhook("charge.refunded", %{
                 "id" => "ch_one_1",
                 "object" => "charge",
                 "amount" => 999,
                 "amount_refunded" => 100,
                 "metadata" => %{"purchase_id" => purchase.id}
               })

      assert {:ok, :processed} =
               webhook("charge.refunded", %{
                 "id" => "ch_one_1",
                 "object" => "charge",
                 "amount" => 999,
                 "amount_refunded" => 999,
                 "metadata" => %{"purchase_id" => purchase.id}
               })

      assert Repo.get!(Purchase, purchase.id).status == "refunded"
      refute Payments.has_entitlement?(user.id, key(purchase))
      assert count("payments.purchase.revoked.reason:refunded") >= 1
    end

    test "a charge no purchase owns is logged and ignored" do
      log =
        capture_log(fn ->
          assert {:ok, :ignored} =
                   webhook("charge.dispute.created", %{
                     "id" => "dp_nobody",
                     "object" => "dispute",
                     "charge" => "ch_nobody",
                     "payment_intent" => "pi_nobody"
                   })
        end)

      assert log =~ "charge.dispute.created matches no purchase"
    end

    test "an event in another API release is still handled, and said", %{user: user} do
      purchase = open_checkout(user, "cs_paid_old_1")

      log =
        capture_log(fn ->
          assert {:ok, :processed} =
                   webhook(
                     "checkout.session.completed",
                     session(purchase, "cs_paid_old_1"),
                     "2022-11-15"
                   )
        end)

      assert log =~ "API version 2022-11-15"
      assert Repo.get!(Purchase, purchase.id).status == "completed"
    end
  end

  describe "a subscription" do
    test "a dispute on one of its payments revokes it and ends the subscription", %{user: user} do
      purchase = paid_subscription(user, "sub_disputed_1")
      assert Repo.get!(Purchase, purchase.id).provider_original_transaction_id == "sub_disputed_1"

      # The dispute names only the charge and the PaymentIntent: no metadata.
      assert {:ok, :processed} =
               webhook("charge.dispute.created", %{
                 "id" => "dp_1",
                 "object" => "dispute",
                 "status" => "needs_response",
                 "charge" => "ch_renewal_1",
                 "payment_intent" => "pi_sub_sub_disputed_1"
               })

      assert_received {:stripe_list_invoice_payments, "pi_sub_sub_disputed_1"}
      assert_received {:stripe_cancel_now, "sub_disputed_1", opts}
      assert opts[:idempotency_key] == "refund-cancel-#{purchase.id}"

      revoked = Repo.get!(Purchase, purchase.id)
      assert revoked.status == "revoked"
      assert revoked.metadata["revocation_reason"] == "charge.dispute.created"
      refute Payments.has_entitlement?(user.id, key(purchase))

      # The cancellation's own webhook keeps the dispute as the end.
      assert {:ok, :processed} =
               webhook("customer.subscription.deleted", %{
                 "id" => "sub_disputed_1",
                 "object" => "subscription",
                 "status" => "canceled",
                 "metadata" => %{"purchase_id" => purchase.id}
               })

      ended = Repo.get!(Purchase, purchase.id)
      assert ended.status == "revoked"
      assert ended.metadata["revocation_reason"] == "charge.dispute.created"

      # Won later: the subscription is gone, so nothing comes back.
      assert {:ok, :ignored} =
               webhook("charge.dispute.closed", %{
                 "id" => "dp_1",
                 "object" => "dispute",
                 "status" => "won",
                 "charge" => "ch_renewal_1",
                 "payment_intent" => "pi_sub_sub_disputed_1"
               })

      refute Payments.has_entitlement?(user.id, key(purchase))
    end

    test "a refund is final: the subscription's end after it leaves it refunded", %{user: user} do
      purchase = paid_subscription(user, "sub_refunded_1")

      assert {:ok, :processed} =
               webhook("refund.updated", %{
                 "id" => "re_1",
                 "object" => "refund",
                 "status" => "succeeded",
                 "metadata" => %{"purchase_id" => purchase.id}
               })

      assert_received {:stripe_cancel_now, "sub_refunded_1", _opts}

      assert {:ok, :processed} =
               webhook("customer.subscription.deleted", %{
                 "id" => "sub_refunded_1",
                 "object" => "subscription",
                 "status" => "canceled",
                 "metadata" => %{"purchase_id" => purchase.id}
               })

      assert Repo.get!(Purchase, purchase.id).status == "refunded"
    end

    test "a failed renewal keeps the paid period and the grace days, and no more", %{user: user} do
      paid_end = DateTime.add(DateTime.utc_now(:second), 3, :day)
      next_end = DateTime.add(paid_end, 365, :day)
      purchase = paid_subscription(user, "sub_late_1", paid_end)
      SettingsHelpers.put(:gamend_core, Settings, :stripe_past_due_grace_days, 7)

      update_subscription(purchase, "sub_late_1", "past_due", next_end)
      assert entitlement(user, purchase).expires_at == DateTime.add(paid_end, 7, :day)
      assert count("payments.subscription.past_due") >= 1

      # A second past_due write does not add a second grace.
      update_subscription(purchase, "sub_late_1", "past_due", next_end)
      assert entitlement(user, purchase).expires_at == DateTime.add(paid_end, 7, :day)

      # The card went through: the new period, paid.
      update_subscription(purchase, "sub_late_1", "active", next_end)
      assert entitlement(user, purchase).expires_at == next_end
      assert count("payments.subscription.renewed") >= 1

      # Unpaid: the period Stripe moved on to was never paid for.
      update_subscription(purchase, "sub_late_1", "unpaid", DateTime.add(next_end, 365, :day))
      assert entitlement(user, purchase).expires_at == next_end
    end

    test "a cancellation scheduled and taken back is counted once each", %{user: user} do
      period_end = DateTime.add(DateTime.utc_now(:second), 30, :day)
      purchase = paid_subscription(user, "sub_flip_1", period_end)
      before = count("payments.subscription.cancel_scheduled")

      update_subscription(purchase, "sub_flip_1", "active", period_end, true)
      update_subscription(purchase, "sub_flip_1", "active", period_end, true)
      assert count("payments.subscription.cancel_scheduled") == before + 1

      update_subscription(purchase, "sub_flip_1", "active", period_end, false)
      assert count("payments.subscription.resumed") >= 1
    end
  end

  describe "a one-off purchase" do
    test "a dispute the seller won hands it back; a lost one does not", %{user: user} do
      purchase = paid_one_off(user)

      assert {:ok, :processed} =
               webhook("charge.dispute.created", %{
                 "id" => "dp_one_1",
                 "object" => "dispute",
                 "charge" => "ch_one_1"
               })

      refute Payments.has_entitlement?(user.id, key(purchase))

      assert {:ok, :ignored} =
               webhook("charge.dispute.closed", %{
                 "id" => "dp_one_1",
                 "object" => "dispute",
                 "status" => "lost",
                 "charge" => "ch_one_1"
               })

      refute Payments.has_entitlement?(user.id, key(purchase))

      assert {:ok, :processed} =
               webhook("charge.dispute.closed", %{
                 "id" => "dp_one_1",
                 "object" => "dispute",
                 "status" => "won",
                 "charge" => "ch_one_1"
               })

      restored = Repo.get!(Purchase, purchase.id)
      assert restored.status == "completed"
      refute restored.metadata["revocation_reason"]
      assert Payments.has_entitlement?(user.id, key(purchase))
      assert count("payments.purchase.restored") >= 1
    end

    test "a refunded purchase is never restored", %{user: user} do
      purchase = paid_one_off(user)

      {:ok, _} =
        Payments.revoke_purchase(purchase, %{"status" => "refunded", "reason" => "refund.updated"})

      assert {:ok, :unchanged} = Payments.restore_purchase(purchase)
    end

    test "a new purchase does not carry the last one's subscription state", %{user: user} do
      old = paid_subscription(user, "sub_old_state_1")

      update_subscription(
        old,
        "sub_old_state_1",
        "past_due",
        DateTime.add(DateTime.utc_now(), 30, :day)
      )

      {:ok, _} = Payments.revoke_purchase(old, %{"status" => "cancelled", "reason" => "ended"})

      {:ok, lifetime} =
        Payments.create_purchase(user, create_product(key(old), "entitlement"), %{})

      {:ok, _} = Payments.fulfill_purchase(lifetime)

      row = entitlement(user, old)
      assert row.status == "active"
      assert row.source_purchase_id == lifetime.id
      refute Map.has_key?(row.metadata, "stripe_subscription_status")
      refute Map.has_key?(row.metadata, "revocation_reason")
    end
  end

  describe "reconciling" do
    test "never revives a cancelled purchase", %{user: user} do
      purchase = open_checkout(user, "cs_paid_cancelled_1")
      {:ok, _} = purchase |> Purchase.changeset(%{status: "cancelled"}) |> Repo.update()

      assert {:ok, %{result: :unchanged}} =
               Payments.reconcile_stripe_purchase(Repo.get!(Purchase, purchase.id))

      assert Repo.get!(Purchase, purchase.id).status == "cancelled"
      refute Payments.has_entitlement?(user.id, key(purchase))
    end

    test "the sweep settles checkouts left open past their session's life", %{user: user} do
      SettingsHelpers.put(:gamend_core, Settings, :environment, :sandbox)
      SettingsHelpers.put(:gamend_core, Settings, :stripe_sandbox_secret_key, "sk_test_sweep")

      paid = open_checkout(user, "cs_paid_lost_1") |> aged(40)
      expired = open_checkout(AccountsFixtures.user_fixture(), "cs_expired_lost_1") |> aged(40)
      fresh = open_checkout(AccountsFixtures.user_fixture(), "cs_paid_fresh_1")

      assert %{fulfilled: 1, cancelled: 1} = StripeSweeper.sweep()

      assert Repo.get!(Purchase, paid.id).status == "completed"
      assert Payments.has_entitlement?(user.id, key(paid))
      assert Repo.get!(Purchase, expired.id).status == "cancelled"
      assert Repo.get!(Purchase, fresh.id).status == "requires_action"
      assert count("payments.sweep.result:fulfilled") >= 1
    end

    test "the sweep does nothing while Stripe is not configured", %{user: user} do
      SettingsHelpers.put(:gamend_core, Settings, :environment, :sandbox)
      SettingsHelpers.delete(:gamend_core, Settings, :stripe_sandbox_secret_key)
      purchase = open_checkout(user, "cs_paid_unconfigured_1") |> aged(40)

      assert StripeSweeper.sweep() == %{}
      assert Repo.get!(Purchase, purchase.id).status == "requires_action"
    end
  end

  test "a SKU with several active rows has to be bought by row id", %{user: user} do
    provider_product = create_product("pro_#{System.unique_integer([:positive])}", "entitlement")

    {:ok, _cheaper} =
      Payments.create_provider_product(%{
        "product_id" => provider_product.product_id,
        "provider" => "stripe",
        "external_id" => "price_cheaper_#{System.unique_integer([:positive])}",
        "currency" => "EUR",
        "unit_amount" => 100
      })

    attrs = %{
      "product_sku" => provider_product.product.sku,
      "success_url" => "https://example.test/ok",
      "cancel_url" => "https://example.test/no"
    }

    assert {:error, :ambiguous_product_sku} = Payments.create_stripe_checkout(user, attrs)

    assert {:ok, _} =
             Payments.create_stripe_checkout(
               user,
               attrs
               |> Map.delete("product_sku")
               |> Map.put("provider_product_id", provider_product.id)
             )

    assert count("payments.checkout.refused.reason:ambiguous_product_sku") >= 1
    assert count("payments.checkout.opened.provider:stripe") >= 1
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp webhook(type, object, api_version \\ "2025-11-17.clover") do
    body =
      Jason.encode!(%{
        "id" => "evt_#{System.unique_integer([:positive])}",
        "type" => type,
        "api_version" => api_version,
        "data" => %{"object" => object}
      })

    Payments.handle_stripe_webhook(body, "sig")
  end

  defp session(%Purchase{} = purchase, session_id, extra \\ %{}) do
    Map.merge(
      %{
        "id" => session_id,
        "object" => "checkout.session",
        "status" => "complete",
        "payment_status" => "paid",
        "metadata" => %{"purchase_id" => purchase.id, "order_id" => purchase.order_id}
      },
      extra
    )
  end

  defp open_checkout(user, session_id, kind \\ "entitlement") do
    provider_product = create_product("pro_#{System.unique_integer([:positive])}", kind)
    {:ok, purchase} = Payments.create_purchase(user, provider_product, %{})

    {:ok, purchase} =
      Payments.mark_purchase_requires_action(purchase, %{"id" => session_id, "url" => "https://x"})

    purchase
  end

  defp aged(%Purchase{} = purchase, minutes) do
    at = DateTime.add(DateTime.utc_now(:second), -minutes * 60)

    {1, _} =
      Repo.update_all(from(p in Purchase, where: p.id == ^purchase.id), set: [updated_at: at])

    Repo.get!(Purchase, purchase.id)
  end

  # Paid through a checkout webhook, as Stripe sends it: the session carries
  # the subscription, whose period is on its items.
  defp paid_subscription(user, subscription_id, period_end \\ nil) do
    period_end = period_end || DateTime.add(DateTime.utc_now(:second), 30, :day)
    purchase = open_checkout(user, "cs_sub_#{subscription_id}", "subscription")

    assert {:ok, :processed} =
             webhook(
               "checkout.session.completed",
               session(purchase, "cs_sub_#{subscription_id}", %{
                 "subscription" =>
                   subscription_object(purchase, subscription_id, "active", period_end, false)
               })
             )

    Payments.get_purchase(purchase.id)
  end

  defp update_subscription(purchase, subscription_id, status, period_end, cancel? \\ false) do
    assert {:ok, :processed} =
             webhook(
               "customer.subscription.updated",
               subscription_object(purchase, subscription_id, status, period_end, cancel?)
             )
  end

  defp subscription_object(purchase, subscription_id, status, period_end, cancel?) do
    %{
      "id" => subscription_id,
      "object" => "subscription",
      "status" => status,
      "cancel_at_period_end" => cancel?,
      "metadata" => %{"purchase_id" => purchase.id},
      "items" => %{"data" => [%{"current_period_end" => DateTime.to_unix(period_end)}]}
    }
  end

  defp paid_one_off(user) do
    provider_product = create_product("pro_#{System.unique_integer([:positive])}", "entitlement")

    {:ok, purchase} =
      Payments.create_purchase(user, provider_product, %{
        "provider_original_transaction_id" => "ch_one_1"
      })

    {:ok, purchase} = Payments.fulfill_purchase(purchase)
    purchase
  end

  defp entitlement(user, %Purchase{} = purchase),
    do: Repo.get_by!(Entitlement, user_id: user.id, key: key(purchase))

  defp key(%Purchase{} = purchase),
    do:
      purchase
      |> Payments.preload_purchase()
      |> Map.fetch!(:product)
      |> Payments.product_entitlement_key()

  defp count(key),
    do: key |> Analytics.counts(1) |> Map.get(key, %{}) |> Map.values() |> Enum.sum()

  defp create_product(entitlement_key, kind) do
    {:ok, product} =
      Payments.create_product(%{
        "sku" => "pro_#{kind}_#{System.unique_integer([:positive])}",
        "title" => "Pro",
        "kind" => kind,
        "grant_config" => %{"entitlement_key" => entitlement_key}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => "stripe",
        "external_id" => "price_#{System.unique_integer([:positive])}",
        "currency" => "EUR",
        "unit_amount" => 999
      })

    Repo.preload(provider_product, :product)
  end

  defp restore_env(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore_env(key, value), do: Application.put_env(:gamend_core, key, value)
end
