defmodule Gamend.Payments.StripeRefundTest do
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.Settings
  alias Gamend.SettingsHelpers

  defmodule NoopPaymentHooks do
    use Gamend.TestSupport.NoopHooks
  end

  # Ids say what Stripe would answer. Subscriptions: `sub_paid_` was charged
  # just now, `sub_old_` 20 days ago, `sub_free_` paid its invoice with
  # nothing (a trial), `sub_basil_` lists its payments the 2025-03-31 way,
  # `sub_canceled_` is cancelled already, `sub_cancelfail_` cannot be
  # cancelled. Payments: `pi_fail_` cannot be refunded, `pi_done_` was
  # refunded already.
  defmodule StripeAdapter do
    def retrieve_subscription_with_latest_invoice(subscription_id) do
      send(self(), {:stripe_retrieve_subscription, subscription_id})
      {:ok, subscription(subscription_id)}
    end

    def cancel_subscription_now("sub_cancelfail_" <> _rest = subscription_id, opts) do
      send(self(), {:stripe_cancel_now, subscription_id, opts})
      {:error, {:stripe_error, %{"message" => "Cannot cancel"}}}
    end

    def cancel_subscription_now(subscription_id, opts) do
      send(self(), {:stripe_cancel_now, subscription_id, opts})
      {:ok, %{"id" => subscription_id, "object" => "subscription", "status" => "canceled"}}
    end

    def create_refund("pi_fail_" <> _rest = payment_id, opts) do
      send(self(), {:stripe_refund, payment_id, opts})
      {:error, {:stripe_error, %{"message" => "Your card was declined"}}}
    end

    def create_refund("pi_done_" <> _rest = payment_id, opts) do
      send(self(), {:stripe_refund, payment_id, opts})

      {:error,
       {:stripe_error,
        %{
          "code" => :invalid_request_error,
          "extra" => %{"raw_error" => %{"code" => "charge_already_refunded"}}
        }}}
    end

    def create_refund(payment_id, opts) do
      send(self(), {:stripe_refund, payment_id, opts})

      {:ok,
       %{
         "id" => "re_" <> payment_id,
         "object" => "refund",
         "amount" => 999,
         "status" => "succeeded"
       }}
    end

    def verify_webhook(raw_body, _signature), do: Jason.decode(raw_body)

    defp subscription("sub_old_" <> rest = id),
      do: active(id, invoice("pi_sub_" <> rest, ago(20)))

    defp subscription("sub_free_" <> _rest = id),
      do: active(id, %{invoice(nil, ago(0)) | "amount_paid" => 0})

    defp subscription("sub_basil_" <> rest = id) do
      invoice =
        nil
        |> invoice(ago(0))
        |> Map.put("payments", %{
          "data" => [
            %{"status" => "open", "payment" => %{"payment_intent" => "pi_open_" <> rest}},
            %{"status" => "paid", "payment" => %{"payment_intent" => "pi_basil_" <> rest}}
          ]
        })

      active(id, invoice)
    end

    defp subscription("sub_canceled_" <> rest = id),
      do: %{active(id, invoice("pi_sub_" <> rest, ago(0))) | "status" => "canceled"}

    defp subscription("sub_" <> rest = id), do: active(id, invoice("pi_sub_" <> rest, ago(0)))

    defp active(id, invoice),
      do: %{
        "id" => id,
        "object" => "subscription",
        "status" => "active",
        "latest_invoice" => invoice
      }

    # The pinned version's shape: an invoice lists what paid it in `payments`.
    defp invoice(payment_intent, paid_at) do
      payments =
        if payment_intent,
          do: [%{"status" => "paid", "payment" => %{"payment_intent" => payment_intent}}],
          else: []

      %{
        "id" => "in_test",
        "object" => "invoice",
        "status" => "paid",
        "amount_paid" => 999,
        "payments" => %{"data" => payments},
        "status_transitions" => %{"paid_at" => paid_at}
      }
    end

    defp ago(days), do: System.os_time(:second) - days * 86_400
  end

  setup do
    original_stripe = Application.get_env(:gamend_core, :stripe_adapter)
    original_hooks = Application.get_env(:gamend_core, :hooks_module)
    original_window = SettingsHelpers.get(:gamend_core, Settings, :refund_window_days)
    original_limit = SettingsHelpers.get(:gamend_core, Settings, :self_refunds_per_account)

    Application.put_env(:gamend_core, :stripe_adapter, StripeAdapter)
    Application.put_env(:gamend_core, :hooks_module, NoopPaymentHooks)

    on_exit(fn ->
      restore_env(:stripe_adapter, original_stripe)
      restore_env(:hooks_module, original_hooks)

      if original_window,
        do: SettingsHelpers.put(:gamend_core, Settings, :refund_window_days, original_window),
        else: SettingsHelpers.delete(:gamend_core, Settings, :refund_window_days)

      if original_limit,
        do:
          SettingsHelpers.put(:gamend_core, Settings, :self_refunds_per_account, original_limit),
        else: SettingsHelpers.delete(:gamend_core, Settings, :self_refunds_per_account)
    end)

    %{user: AccountsFixtures.user_fixture()}
  end

  describe "a one-off purchase" do
    test "is refunded once, and the charge.refunded webhook takes it back", %{user: user} do
      purchase = paid_lifetime(user, "pi_life_1")
      assert Payments.stripe_refundable?(purchase)

      assert {:ok, %{purchase: refunded, refund: refund}} =
               Payments.refund_stripe_purchase(user, purchase.id)

      assert refund["id"] == "re_pi_life_1"
      assert_received {:stripe_refund, "pi_life_1", opts}
      assert opts[:idempotency_key] == "refund-#{purchase.id}"
      assert opts[:metadata] == %{"purchase_id" => purchase.id, "order_id" => purchase.order_id}

      # Recorded, not revoked: the webhook does that.
      assert refunded.status == "completed"
      assert refunded.metadata["stripe_refund"]["refund_id"] == "re_pi_life_1"
      assert refunded.metadata["stripe_refund"]["by"] == "buyer"
      assert Payments.has_entitlement?(user.id, entitlement_key(purchase))

      refute Payments.stripe_refundable?(refunded)
      assert {:error, :already_refunded} = Payments.refund_stripe_purchase(user, purchase.id)
      assert {:error, :already_refunded} = Payments.admin_refund_stripe_purchase(purchase.id)
      refute_received {:stripe_refund, _payment_id, _opts}

      webhook("charge.refunded", %{
        "id" => "ch_life_1",
        "object" => "charge",
        "amount" => 999,
        "amount_refunded" => 999,
        "payment_intent" => "pi_life_1",
        "metadata" => %{"purchase_id" => purchase.id}
      })

      assert Repo.get!(Purchase, purchase.id).status == "refunded"
      refute Payments.has_entitlement?(user.id, entitlement_key(purchase))
    end

    test "only within the window from the day it was paid", %{user: user} do
      purchase = paid_lifetime(user, "pi_late_1") |> paid_days_ago(15)

      refute Payments.stripe_refundable?(purchase)

      assert {:error, :refund_window_closed} =
               Payments.refund_stripe_purchase(user, purchase.id)

      refute_received {:stripe_refund, _payment_id, _opts}

      SettingsHelpers.put(:gamend_core, Settings, :refund_window_days, 30)
      assert Payments.refund_window_days() == 30
      assert Payments.stripe_refundable?(purchase)

      SettingsHelpers.put(:gamend_core, Settings, :refund_window_days, 0)
      fresh = paid_lifetime(user, "pi_off_1")
      refute Payments.stripe_refundable?(fresh)
      assert {:error, :refund_window_closed} = Payments.refund_stripe_purchase(user, fresh.id)
    end

    test "a buyer refunds themselves a set number of times; an admin is not held to it", %{
      user: user
    } do
      SettingsHelpers.put(:gamend_core, Settings, :self_refunds_per_account, 1)
      first = paid_lifetime(user, "pi_once_1")
      assert {:ok, _} = Payments.refund_stripe_purchase(user, first.id)

      second = paid_lifetime(user, "pi_once_2")
      refute Payments.stripe_refundable?(second)
      assert {:error, :refund_limit_reached} = Payments.refund_stripe_purchase(user, second.id)
      refute_received {:stripe_refund, "pi_once_2", _opts}

      assert {:ok, _} = Payments.admin_refund_stripe_purchase(second.id)

      # An admin's refund does not count against the buyer, and 0 is no limit.
      SettingsHelpers.put(:gamend_core, Settings, :self_refunds_per_account, 0)
      third = paid_lifetime(user, "pi_once_3")
      assert Payments.stripe_refundable?(third)
    end

    test "only the buyer's own", %{user: user} do
      purchase = paid_lifetime(user, "pi_mine_1")
      other = AccountsFixtures.user_fixture()

      assert {:error, :purchase_not_found} = Payments.refund_stripe_purchase(other, purchase.id)
      assert {:error, :purchase_not_found} = Payments.refund_stripe_purchase(other, "not-a-uuid")
      refute_received {:stripe_refund, _payment_id, _opts}
    end

    test "never a consumable, an unpaid or another provider's purchase by the buyer", %{
      user: user
    } do
      coins = paid_purchase(user, create_product("consumable"), "pi_coins_1")
      refute Payments.stripe_refundable?(coins)
      assert {:error, :not_refundable} = Payments.refund_stripe_purchase(user, coins.id)

      {:ok, open} = Payments.create_purchase(user, create_product("entitlement"))
      assert {:error, :not_refundable} = Payments.refund_stripe_purchase(user, open.id)

      apple = paid_purchase(user, create_product("entitlement", "apple"), "pi_apple_1")
      refute Payments.admin_stripe_refundable?(apple)
      assert {:error, :not_stripe_purchase} = Payments.refund_stripe_purchase(user, apple.id)

      refute_received {:stripe_refund, _payment_id, _opts}
    end

    test "a refund Stripe refuses is reported, and can be tried again", %{user: user} do
      purchase = paid_lifetime(user, "pi_fail_1")

      assert {:error, {:stripe_error, %{"message" => "Your card was declined"}}} =
               Payments.refund_stripe_purchase(user, purchase.id)

      failed = Repo.get!(Purchase, purchase.id)
      assert failed.metadata["stripe_refund"]["requested_at"]
      refute failed.metadata["stripe_refund"]["refund_id"]
      assert Payments.stripe_refundable?(Payments.get_purchase(purchase.id))
    end

    test "a payment Stripe already refunded answers already_refunded", %{user: user} do
      purchase = paid_lifetime(user, "pi_done_1")
      assert {:error, :already_refunded} = Payments.refund_stripe_purchase(user, purchase.id)
    end

    test "with no payment on record, nothing is sent", %{user: user} do
      {:ok, purchase} = Payments.create_purchase(user, create_product("entitlement"))
      {:ok, purchase} = Payments.fulfill_purchase(purchase)

      assert {:error, :missing_stripe_payment_id} =
               Payments.refund_stripe_purchase(user, purchase.id)

      refute_received {:stripe_refund, _payment_id, _opts}
    end
  end

  describe "a subscription" do
    test "is cancelled now, then its last payment refunded", %{user: user} do
      purchase = paid_subscription(user, "sub_paid_1")
      assert Payments.stripe_refundable?(purchase)

      assert {:ok, %{refund: %{"id" => "re_pi_sub_paid_1"}}} =
               Payments.refund_stripe_purchase(user, purchase.id)

      # In this order: the cancel goes before the refund.
      assert [
               {:stripe_retrieve_subscription, "sub_paid_1"},
               {:stripe_cancel_now, "sub_paid_1", cancel_opts},
               {:stripe_refund, "pi_sub_paid_1", refund_opts}
             ] = stripe_calls()

      assert cancel_opts[:idempotency_key] == "refund-cancel-#{purchase.id}"
      assert refund_opts[:idempotency_key] == "refund-#{purchase.id}"

      # Pro is still on until Stripe's deletion arrives.
      assert Payments.has_entitlement?(user.id, entitlement_key(purchase))

      webhook("customer.subscription.deleted", %{
        "id" => "sub_paid_1",
        "object" => "subscription",
        "status" => "canceled",
        "metadata" => %{"purchase_id" => purchase.id}
      })

      refute Payments.has_entitlement?(user.id, entitlement_key(purchase))
      ended = Repo.get!(Purchase, purchase.id)
      assert ended.status == "cancelled"
      assert ended.metadata["stripe_refund"]["refund_id"] == "re_pi_sub_paid_1"
      refute Payments.stripe_refundable?(Payments.get_purchase(purchase.id))
    end

    test "cancels before it refunds: a cancel Stripe refuses refunds nothing", %{user: user} do
      purchase = paid_subscription(user, "sub_cancelfail_1")

      assert {:error, {:stripe_error, %{"message" => "Cannot cancel"}}} =
               Payments.refund_stripe_purchase(user, purchase.id)

      refute_received {:stripe_refund, _payment_id, _opts}
    end

    test "a refund that failed after the cancel is finished by a retry", %{user: user} do
      purchase = paid_subscription(user, "sub_canceled_1")

      # The first try cancelled it and the webhook ended the purchase.
      {:ok, _} =
        purchase
        |> Purchase.changeset(%{
          status: "cancelled",
          metadata:
            Map.put(purchase.metadata, "stripe_refund", %{
              "requested_at" => DateTime.to_iso8601(DateTime.utc_now()),
              "by" => "buyer"
            })
        })
        |> Repo.update()

      cancelled = Payments.get_purchase(purchase.id)
      assert Payments.stripe_refundable?(cancelled)

      assert {:ok, %{refund: %{"id" => "re_pi_sub_1"}}} =
               Payments.refund_stripe_purchase(user, purchase.id)

      refute_received {:stripe_cancel_now, _subscription_id, _opts}
    end

    test "still in a free trial has nothing to refund", %{user: user} do
      purchase =
        user
        |> paid_subscription("sub_paid_2")
        |> put_payload(%{
          "stripe_subscription" => %{"id" => "sub_paid_2", "status" => "trialing"}
        })

      refute Payments.stripe_refundable?(purchase)

      assert {:error, :nothing_to_refund} = Payments.refund_stripe_purchase(user, purchase.id)
      refute_received {:stripe_retrieve_subscription, _subscription_id}
    end

    test "a latest invoice paid with nothing refunds and cancels nothing", %{user: user} do
      purchase = paid_subscription(user, "sub_free_1")

      assert {:error, :nothing_to_refund} = Payments.refund_stripe_purchase(user, purchase.id)
      refute_received {:stripe_cancel_now, _subscription_id, _opts}
      refute_received {:stripe_refund, _payment_id, _opts}
    end

    test "the window runs from the last payment: a renewal opens it again", %{user: user} do
      purchase = user |> paid_subscription("sub_paid_3") |> paid_days_ago(40)
      refute Payments.stripe_refundable?(purchase)

      renewed =
        put_payload(purchase, %{
          "stripe_subscription" => %{
            "id" => "sub_paid_3",
            "status" => "active",
            "items" => %{
              "data" => [%{"current_period_start" => System.os_time(:second) - 2 * 86_400}]
            }
          }
        })

      assert Payments.stripe_refundable?(renewed)
    end

    test "Stripe's own payment date is checked again before anything changes", %{user: user} do
      purchase = paid_subscription(user, "sub_old_1")
      assert Payments.stripe_refundable?(purchase)

      assert {:error, :refund_window_closed} =
               Payments.refund_stripe_purchase(user, purchase.id)

      refute_received {:stripe_cancel_now, _subscription_id, _opts}
      refute Repo.get!(Purchase, purchase.id).metadata["stripe_refund"]

      # An admin is not held to the window.
      assert {:ok, %{refund: %{"id" => "re_pi_sub_1"}}} =
               Payments.admin_refund_stripe_purchase(purchase.id)

      assert Repo.get!(Purchase, purchase.id).metadata["stripe_refund"]["by"] == "admin"
    end

    test "reads the payment from an invoice's payments list", %{user: user} do
      purchase = paid_subscription(user, "sub_basil_1")

      assert {:ok, %{refund: %{"id" => "re_pi_basil_1"}}} =
               Payments.refund_stripe_purchase(user, purchase.id)
    end
  end

  test "an admin refunds any Stripe purchase at any time, consumables too", %{user: user} do
    coins =
      user
      |> paid_purchase(create_product("consumable"), "pi_admin_1")
      |> paid_days_ago(100)

    assert Payments.admin_stripe_refundable?(coins)

    assert {:ok, %{refund: %{"id" => "re_pi_admin_1"}}} =
             Payments.admin_refund_stripe_purchase(coins.id)

    assert {:error, :purchase_not_found} =
             Payments.admin_refund_stripe_purchase(Ecto.UUID.generate())
  end

  defp paid_lifetime(user, payment_intent),
    do: paid_purchase(user, create_product("entitlement"), payment_intent)

  defp paid_purchase(user, provider_product, payment_intent) do
    {:ok, purchase} =
      Payments.create_purchase(user, provider_product, %{
        "metadata" => %{"stripe_payment_intent_id" => payment_intent}
      })

    {:ok, purchase} = Payments.fulfill_purchase(purchase)
    purchase
  end

  defp paid_subscription(user, subscription_id) do
    {:ok, purchase} =
      Payments.create_purchase(user, create_product("subscription"), %{
        "metadata" => %{"stripe_subscription_id" => subscription_id}
      })

    {:ok, purchase} = Payments.fulfill_purchase(purchase)
    purchase
  end

  defp paid_days_ago(%Purchase{} = purchase, days) do
    purchase
    |> Purchase.changeset(%{
      purchased_at: DateTime.add(DateTime.utc_now(:second), -days * 86_400)
    })
    |> Repo.update!()
    |> Payments.preload_purchase()
  end

  defp put_payload(%Purchase{} = purchase, payload) do
    purchase
    |> Purchase.changeset(%{
      raw_provider_payload: Map.merge(purchase.raw_provider_payload || %{}, payload)
    })
    |> Repo.update!()
    |> Payments.preload_purchase()
  end

  defp stripe_calls do
    {:messages, messages} = Process.info(self(), :messages)

    Enum.filter(messages, fn message ->
      is_tuple(message) and
        elem(message, 0) in [:stripe_retrieve_subscription, :stripe_cancel_now, :stripe_refund]
    end)
  end

  defp webhook(type, object) do
    body =
      Jason.encode!(%{
        "id" => "evt_#{System.unique_integer([:positive])}",
        "type" => type,
        "data" => %{"object" => object}
      })

    assert {:ok, :processed} = Payments.handle_stripe_webhook(body, "sig")
  end

  defp entitlement_key(%Purchase{} = purchase),
    do: Payments.product_entitlement_key(purchase.product)

  defp create_product(kind, provider \\ "stripe") do
    key = "pro_#{System.unique_integer([:positive])}"

    {:ok, product} =
      Payments.create_product(%{
        "sku" => "#{key}_#{kind}",
        "title" => "Pro",
        "kind" => kind,
        "grant_config" => %{"entitlement_key" => key}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => provider,
        "external_id" => "price_#{key}",
        "currency" => "EUR",
        "unit_amount" => 999
      })

    provider_product
  end

  defp restore_env(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore_env(key, value), do: Application.put_env(:gamend_core, key, value)
end
