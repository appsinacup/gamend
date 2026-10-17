defmodule Gamend.Payments.UpgradesTest do
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.Upgrades

  defmodule NoopPaymentHooks do
    use Gamend.TestSupport.NoopHooks
  end

  # Every subscription started 10 days ago and runs 30 (20 left), its last
  # invoice paid 999. `pi_fail_` cannot be refunded.
  defmodule StripeAdapter do
    def retrieve_subscription_with_latest_invoice(subscription_id) do
      send(self(), {:stripe_retrieve_subscription, subscription_id})
      now = System.os_time(:second)
      "sub_" <> rest = subscription_id

      {:ok,
       %{
         "id" => subscription_id,
         "object" => "subscription",
         "status" => "active",
         "items" => %{
           "data" => [
             %{
               "current_period_start" => now - 10 * 86_400,
               "current_period_end" => now + 20 * 86_400
             }
           ]
         },
         "latest_invoice" => %{
           "id" => "in_" <> rest,
           "object" => "invoice",
           "status" => "paid",
           "amount_paid" => 999,
           "status_transitions" => %{"paid_at" => now - 10 * 86_400},
           "payments" => %{
             "data" => [%{"status" => "paid", "payment" => %{"payment_intent" => "pi_" <> rest}}]
           }
         }
       }}
    end

    def cancel_subscription_now(subscription_id, opts) do
      send(self(), {:stripe_cancel_now, subscription_id, opts})
      {:ok, %{"id" => subscription_id, "object" => "subscription", "status" => "canceled"}}
    end

    def cancel_subscription_at_period_end(subscription_id) do
      send(self(), {:stripe_cancel_at_period_end, subscription_id})

      {:ok,
       %{
         "id" => subscription_id,
         "object" => "subscription",
         "status" => "active",
         "cancel_at_period_end" => true
       }}
    end

    def create_refund("pi_fail_" <> _rest = payment_id, opts) do
      send(self(), {:stripe_refund, payment_id, opts})
      {:error, {:stripe_error, %{"message" => "Try again"}}}
    end

    def create_refund(payment_id, opts) do
      send(self(), {:stripe_refund, payment_id, opts})

      {:ok,
       %{
         "id" => "re_" <> payment_id,
         "object" => "refund",
         "amount" => opts[:amount],
         "status" => "succeeded",
         "metadata" => opts[:metadata]
       }}
    end

    def verify_webhook(raw_body, _signature), do: Jason.decode(raw_body)
  end

  @month 30 * 86_400
  @year 365 * 86_400

  setup do
    original_stripe = Application.get_env(:gamend_core, :stripe_adapter)
    original_hooks = Application.get_env(:gamend_core, :hooks_module)

    Application.put_env(:gamend_core, :stripe_adapter, StripeAdapter)
    Application.put_env(:gamend_core, :hooks_module, NoopPaymentHooks)

    on_exit(fn ->
      restore_env(:stripe_adapter, original_stripe)
      restore_env(:hooks_module, original_hooks)
    end)

    key = "pro_#{System.unique_integer([:positive])}"

    %{
      user: AccountsFixtures.user_fixture(),
      key: key,
      monthly: create_product(key, "monthly", "subscription", @month),
      yearly: create_product(key, "yearly", "subscription", @year),
      lifetime: create_product(key, "lifetime", "entitlement", nil)
    }
  end

  describe "longer?/2" do
    test "lifetime outlasts any plan that renews, a year outlasts a month", ctx do
      [monthly, yearly, lifetime] =
        Enum.map([ctx.monthly, ctx.yearly, ctx.lifetime], & &1.product)

      assert Upgrades.longer?(yearly, monthly)
      assert Upgrades.longer?(lifetime, monthly)
      assert Upgrades.longer?(lifetime, yearly)

      refute Upgrades.longer?(monthly, yearly)
      refute Upgrades.longer?(monthly, monthly)
      refute Upgrades.longer?(yearly, lifetime)
      refute Upgrades.longer?(lifetime, lifetime)

      unset = %{monthly | grant_config: %{"entitlement_key" => ctx.key}}
      refute Upgrades.longer?(yearly, unset)
      refute Upgrades.longer?(unset, monthly)
    end
  end

  describe "the checkout" do
    test "a longer plan is let through what the user owns; the same or a shorter one is not",
         ctx do
      paid_subscription(ctx.user, ctx.monthly, "sub_m1", 20)

      assert Payments.ensure_checkout_allowed(ctx.user, ctx.yearly, %{}) == :ok
      assert Payments.ensure_checkout_allowed(ctx.user, ctx.lifetime, %{}) == :ok

      assert Payments.ensure_checkout_allowed(ctx.user, ctx.monthly, %{}) ==
               {:error, :already_owned}
    end

    test "nothing is longer than lifetime", ctx do
      paid_lifetime(ctx.user, ctx.lifetime, "pi_life1")

      for plan <- [ctx.monthly, ctx.yearly, ctx.lifetime] do
        assert Payments.ensure_checkout_allowed(ctx.user, plan, %{}) == {:error, :already_owned}
      end
    end

    test "a plan granted with no purchase is not upgraded", ctx do
      {:ok, _row} =
        Payments.grant_entitlement(ctx.user.id, ctx.key,
          expires_at: DateTime.add(DateTime.utc_now(:second), @month)
        )

      assert Payments.ensure_checkout_allowed(ctx.user, ctx.lifetime, %{}) ==
               {:error, :already_owned}
    end
  end

  describe "first_charge_at/2" do
    test "a yearly plan bought on a monthly one waits for the paid month to end", ctx do
      old = paid_subscription(ctx.user, ctx.monthly, "sub_m2", 20)
      ends_at = DateTime.add(old.purchased_at, 20 * 86_400)

      assert_in_delta DateTime.to_unix(Upgrades.first_charge_at(ctx.user.id, ctx.yearly.product)),
                      DateTime.to_unix(ends_at),
                      5

      assert Upgrades.first_charge_at(ctx.user.id, ctx.lifetime.product) == nil

      given = DateTime.add(DateTime.utc_now(:second), 3 * 86_400)

      assert Upgrades.trial_end(ctx.user.id, ctx.yearly.product, given) ==
               Upgrades.first_charge_at(ctx.user.id, ctx.yearly.product)

      assert Upgrades.trial_end(ctx.user.id, ctx.lifetime.product, given) == given
    end

    test "with under two days left, it is charged now", ctx do
      paid_subscription(ctx.user, ctx.monthly, "sub_m3", 1)
      assert Upgrades.first_charge_at(ctx.user.id, ctx.yearly.product) == nil
    end
  end

  describe "a subscription to lifetime" do
    test "cancels the old plan now and refunds its unused part", ctx do
      old = paid_subscription(ctx.user, ctx.monthly, "sub_m4", 20)
      _ = stripe_calls()

      new = paid_lifetime(ctx.user, ctx.lifetime, "pi_life4")

      assert [
               {:stripe_retrieve_subscription, "sub_m4"},
               {:stripe_cancel_now, "sub_m4", cancel_opts},
               {:stripe_refund, "pi_m4", refund_opts}
             ] = stripe_calls()

      assert cancel_opts[:idempotency_key] == "supersede-cancel-#{old.id}"
      assert refund_opts[:idempotency_key] == "supersede-refund-#{old.id}"
      # 20 of 30 days left: two thirds of 999.
      assert_in_delta refund_opts[:amount], 666, 1

      assert refund_opts[:metadata] == %{
               "superseded_purchase_id" => old.id,
               "superseded_by" => new.id
             }

      superseded = Repo.get!(Purchase, old.id).metadata["superseded"]
      assert superseded["by"] == new.id
      assert superseded["mode"] == "now"
      assert superseded["refund_id"] == "re_pi_m4"
      assert is_binary(superseded["done_at"])
      # Never marked refunded the way a full refund marks it.
      refute Repo.get!(Purchase, old.id).metadata["stripe_refund"]

      assert Upgrades.holding_purchase(ctx.user.id, ctx.key).id == new.id

      # Stripe's events for the old plan take nothing from the new one.
      webhook("refund.created", %{
        "id" => "re_pi_m4",
        "object" => "refund",
        "amount" => refund_opts[:amount],
        "status" => "succeeded",
        "payment_intent" => "pi_m4",
        "metadata" => refund_opts[:metadata]
      })

      webhook("charge.refunded", %{
        "id" => "ch_m4",
        "object" => "charge",
        "amount" => 999,
        "amount_refunded" => refund_opts[:amount],
        "payment_intent" => "pi_m4"
      })

      webhook("customer.subscription.deleted", %{
        "id" => "sub_m4",
        "object" => "subscription",
        "status" => "canceled",
        "metadata" => %{"purchase_id" => old.id}
      })

      assert Repo.get!(Purchase, old.id).status == "cancelled"
      assert Payments.has_entitlement?(ctx.user.id, ctx.key)
      assert Upgrades.holding_purchase(ctx.user.id, ctx.key).id == new.id
    end

    test "runs once: a second call changes nothing", ctx do
      old = paid_subscription(ctx.user, ctx.monthly, "sub_m5", 20)
      new = paid_lifetime(ctx.user, ctx.lifetime, "pi_life5")
      _ = stripe_calls()

      assert {:ok, []} = Upgrades.supersede(new)
      assert stripe_calls() == []
      assert Repo.get!(Purchase, old.id).metadata["superseded"]["done_at"]
    end

    test "a refund Stripe refuses is finished by the sweep, for the same amount", ctx do
      old = paid_subscription(ctx.user, ctx.monthly, "sub_fail_6", 20)
      new = paid_lifetime(ctx.user, ctx.lifetime, "pi_life6")

      assert [_retrieve, {:stripe_cancel_now, _, _}, {:stripe_refund, _, first}] = stripe_calls()
      refute Repo.get!(Purchase, old.id).metadata["superseded"]["done_at"]

      assert %{failed: 1} = Upgrades.sweep()
      assert [_retrieve, {:stripe_cancel_now, _, _}, {:stripe_refund, _, again}] = stripe_calls()
      assert again[:amount] == first[:amount]
      assert again[:idempotency_key] == first[:idempotency_key]

      assert Upgrades.holding_purchase(ctx.user.id, ctx.key).id == new.id
    end
  end

  describe "a monthly plan to a yearly one" do
    test "bought to start when the month ends: the month is cancelled at its end, no refund",
         ctx do
      old = paid_subscription(ctx.user, ctx.monthly, "sub_m7", 20)
      starts_at = Upgrades.first_charge_at(ctx.user.id, ctx.yearly.product)
      _ = stripe_calls()

      new =
        paid_subscription(ctx.user, ctx.yearly, "sub_y7", 365, %{
          "stripe_subscription" => %{
            "id" => "sub_y7",
            "status" => "trialing",
            "trial_end" => DateTime.to_unix(starts_at)
          }
        })

      assert [{:stripe_cancel_at_period_end, "sub_m7"}] = stripe_calls()

      superseded = Repo.get!(Purchase, old.id).metadata["superseded"]
      assert superseded["mode"] == "at_period_end"
      assert superseded["by"] == new.id
      assert superseded["refund_amount"] == nil
      assert Upgrades.holding_purchase(ctx.user.id, ctx.key).id == new.id
    end

    test "charged now (under two days left): the month is cancelled now and refunded", ctx do
      paid_subscription(ctx.user, ctx.monthly, "sub_m8", 1)
      _ = stripe_calls()

      paid_subscription(ctx.user, ctx.yearly, "sub_y8", 365, %{
        "stripe_subscription" => %{"id" => "sub_y8", "status" => "active"}
      })

      assert [_retrieve, {:stripe_cancel_now, "sub_m8", _}, {:stripe_refund, "pi_m8", _}] =
               stripe_calls()
    end
  end

  test "a purchase that does not hold the row ends nothing", ctx do
    paid_subscription(ctx.user, ctx.monthly, "sub_m9", 20)

    {:ok, other} = Payments.create_purchase(ctx.user, ctx.lifetime, %{})
    _ = stripe_calls()

    assert {:ok, []} = Upgrades.supersede(other)
    assert stripe_calls() == []
  end

  test "unused_amount/4 is the time left, rounded down" do
    starts_at = ~U[2026-01-01 00:00:00Z]
    ends_at = ~U[2026-01-31 00:00:00Z]

    assert Upgrades.unused_amount(999, starts_at, ends_at, ~U[2026-01-11 00:00:00Z]) == 666
    assert Upgrades.unused_amount(999, starts_at, ends_at, starts_at) == 999
    assert Upgrades.unused_amount(999, starts_at, ends_at, ~U[2025-12-01 00:00:00Z]) == 999
    assert Upgrades.unused_amount(999, starts_at, ends_at, ends_at) == 0
    assert Upgrades.unused_amount(0, starts_at, ends_at, starts_at) == 0
    assert Upgrades.unused_amount(999, nil, ends_at, starts_at) == 0
  end

  # A Stripe subscription purchase, fulfilled, whose paid period ends in
  # `days_left` days.
  defp paid_subscription(user, provider_product, subscription_id, days_left, payload \\ %{}) do
    ends_at = DateTime.add(DateTime.utc_now(:second), days_left * 86_400)

    {:ok, purchase} =
      Payments.create_purchase(user, provider_product, %{
        "metadata" => %{
          "stripe_subscription_id" => subscription_id,
          "stripe_subscription_status" =>
            get_in(payload, ["stripe_subscription", "status"]) || "active",
          "stripe_subscription_current_period_end" => DateTime.to_iso8601(ends_at)
        }
      })

    {:ok, purchase} =
      purchase
      |> Purchase.changeset(%{expires_at: ends_at, raw_provider_payload: payload})
      |> Repo.update!()
      |> Payments.fulfill_purchase()

    purchase
  end

  defp paid_lifetime(user, provider_product, payment_intent) do
    {:ok, purchase} =
      Payments.create_purchase(user, provider_product, %{
        "metadata" => %{"stripe_payment_intent_id" => payment_intent}
      })

    {:ok, purchase} = Payments.fulfill_purchase(purchase)
    purchase
  end

  defp stripe_calls do
    collect([])
  end

  defp collect(acc) do
    receive do
      message
      when is_tuple(message) and
             elem(message, 0) in [
               :stripe_retrieve_subscription,
               :stripe_cancel_now,
               :stripe_cancel_at_period_end,
               :stripe_refund
             ] ->
        collect([message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp webhook(type, object) do
    body =
      Jason.encode!(%{
        "id" => "evt_#{System.unique_integer([:positive])}",
        "type" => type,
        "data" => %{"object" => object}
      })

    assert {:ok, _result} = Payments.handle_stripe_webhook(body, "sig")
  end

  defp create_product(key, name, kind, duration) do
    grant_config =
      if duration,
        do: %{"entitlement_key" => key, "duration_seconds" => duration},
        else: %{"entitlement_key" => key}

    {:ok, product} =
      Payments.create_product(%{
        "sku" => "#{key}_#{name}",
        "title" => "Pro #{name}",
        "kind" => kind,
        "grant_config" => grant_config
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => "stripe",
        "external_id" => "price_#{key}_#{name}",
        "currency" => "EUR",
        "unit_amount" => 999
      })

    Repo.preload(provider_product, :product)
  end

  defp restore_env(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore_env(key, value), do: Application.put_env(:gamend_core, key, value)
end
