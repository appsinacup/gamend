defmodule Gamend.Payments.DeletedAccountSubscriptionsTest do
  @moduledoc """
  What deleting an account does to what it pays for: a job per Stripe
  subscription ends it, what Stripe has already ended is left alone, an outage
  is retried, and later events about its purchases are ignored.

  Stripe is a fake adapter whose ids say what it would answer.
  """
  use Gamend.DataCase
  use Oban.Testing, repo: Gamend.Repo

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Payments.DeletedAccountSubscriptions
  alias Gamend.Payments.Purchase

  defmodule StripeAdapter do
    def retrieve_subscription("sub_over" <> _rest = id),
      do: {:ok, %{"id" => id, "status" => "canceled"}}

    def retrieve_subscription("sub_gone" <> _rest),
      do: {:error, {:stripe_error, %{"code" => "resource_missing"}}}

    def retrieve_subscription("sub_down" <> _rest),
      do: {:error, {:stripe_error, %{"code" => "api_connection_error"}}}

    def retrieve_subscription(id), do: {:ok, %{"id" => id, "status" => "past_due"}}

    def cancel_subscription_now(id, _opts) do
      send(self(), {:cancelled, id})
      {:ok, %{"id" => id, "status" => "canceled"}}
    end

    def verify_webhook(raw_body, _signature), do: Jason.decode(raw_body)
  end

  setup do
    original = Application.get_env(:gamend_core, :stripe_adapter)
    Application.put_env(:gamend_core, :stripe_adapter, StripeAdapter)

    on_exit(fn ->
      if is_nil(original),
        do: Application.delete_env(:gamend_core, :stripe_adapter),
        else: Application.put_env(:gamend_core, :stripe_adapter, original)
    end)

    %{user: AccountsFixtures.user_fixture()}
  end

  describe "deleting an account" do
    test "queues the end of each of its subscriptions", %{user: user} do
      subscribed(user, "sub_one")
      subscribed(user, "sub_two")

      assert {:ok, _user} = Accounts.delete_user(user)

      assert_enqueued(
        worker: DeletedAccountSubscriptions,
        args: %{"subscription_id" => "sub_one"}
      )

      assert_enqueued(
        worker: DeletedAccountSubscriptions,
        args: %{"subscription_id" => "sub_two"}
      )
    end

    test "queues nothing for a one-off purchase or another account's", %{user: user} do
      bought(user)
      subscribed(AccountsFixtures.user_fixture(), "sub_theirs")

      assert {:ok, _user} = Accounts.delete_user(user)

      refute_enqueued(worker: DeletedAccountSubscriptions)
    end

    test "keeps the purchase, with no owner", %{user: user} do
      purchase = subscribed(user, "sub_kept")

      assert {:ok, _user} = Accounts.delete_user(user)

      assert %Purchase{user_id: nil, status: "completed"} = Repo.get!(Purchase, purchase.id)
    end
  end

  describe "the job" do
    test "cancels a subscription still charging" do
      assert :ok = perform("sub_live")
      assert_received {:cancelled, "sub_live"}
    end

    test "leaves one that is already over" do
      assert :ok = perform("sub_over_1")
      refute_received {:cancelled, _id}
    end

    test "drops one Stripe does not have" do
      assert :ok = perform("sub_gone_1")
      refute_received {:cancelled, _id}
    end

    test "is retried while Stripe is down" do
      assert {:error, {:stripe_error, _error}} = perform("sub_down_1")
      refute_received {:cancelled, _id}
    end
  end

  describe "a later Stripe event about its purchase" do
    test "is ignored, not refused", %{user: user} do
      purchase = subscribed(user, "sub_event")
      {:ok, _user} = Accounts.delete_user(user)

      object = %{
        "id" => "sub_event",
        "object" => "subscription",
        "status" => "canceled",
        "metadata" => %{"purchase_id" => purchase.id}
      }

      assert {:ok, :ignored} = webhook("customer.subscription.deleted", object)
      assert {:ok, :ignored} = webhook("customer.subscription.updated", object)
    end
  end

  defp perform(subscription_id) do
    perform_job(DeletedAccountSubscriptions, %{"subscription_id" => subscription_id})
  end

  defp webhook(type, object) do
    body =
      Jason.encode!(%{
        "id" => "evt_#{System.unique_integer([:positive])}",
        "type" => type,
        "api_version" => "2025-11-17.clover",
        "data" => %{"object" => object}
      })

    Payments.handle_stripe_webhook(body, "sig")
  end

  defp subscribed(user, subscription_id) do
    purchase(user, "subscription", %{"metadata" => %{"stripe_subscription_id" => subscription_id}})
  end

  defp bought(user), do: purchase(user, "entitlement", %{})

  defp purchase(user, kind, attrs) do
    {:ok, purchase} = Payments.create_purchase(user, provider_product(kind), attrs)
    {:ok, purchase} = Payments.fulfill_purchase(purchase)
    purchase
  end

  defp provider_product(kind) do
    n = System.unique_integer([:positive])

    {:ok, product} =
      Payments.create_product(%{
        "sku" => "pro_#{kind}_#{n}",
        "title" => "Pro",
        "kind" => kind,
        "grant_config" => %{"entitlement_key" => "pro_#{n}"}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => "stripe",
        "external_id" => "price_#{n}",
        "currency" => "EUR",
        "unit_amount" => 999
      })

    Repo.preload(provider_product, :product)
  end
end
