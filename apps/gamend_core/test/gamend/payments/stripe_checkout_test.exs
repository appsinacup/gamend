defmodule Gamend.Payments.StripeCheckoutTest do
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Payments.Purchase

  defmodule NoopPaymentHooks do
    use Gamend.TestSupport.NoopHooks
  end

  # Session ids say what Stripe would answer: `cs_open_` sessions can be
  # expired, `cs_paid_` ones were paid, `cs_paying_` ones are complete with the
  # payment still clearing.
  defmodule StripeAdapter do
    def create_checkout_session(purchase, _provider_product, attrs) do
      send(self(), {:stripe_checkout_attrs, attrs})

      {:ok,
       %{
         "id" => "cs_open_#{purchase.id}",
         "url" => "https://checkout.test/session/#{purchase.id}"
       }}
    end

    def expire_checkout_session("cs_open_" <> _rest = session_id) do
      send(self(), {:stripe_expire, session_id})

      {:ok,
       %{
         "id" => session_id,
         "object" => "checkout.session",
         "status" => "expired",
         "payment_status" => "unpaid"
       }}
    end

    def expire_checkout_session(session_id) do
      send(self(), {:stripe_expire, session_id})
      {:error, {:stripe_error, %{"code" => "checkout_session_not_open"}}}
    end

    def retrieve_checkout_session("cs_paid_" <> _rest = session_id) do
      {:ok,
       %{
         "id" => session_id,
         "object" => "checkout.session",
         "status" => "complete",
         "payment_status" => "paid"
       }}
    end

    def retrieve_checkout_session("cs_paying_" <> _rest = session_id) do
      {:ok,
       %{
         "id" => session_id,
         "object" => "checkout.session",
         "status" => "complete",
         "payment_status" => "unpaid",
         "payment_intent" => %{"status" => "processing"}
       }}
    end

    def verify_webhook(raw_body, _signature), do: Jason.decode(raw_body)
  end

  defmodule StoreAdapter do
    def validate_purchase(_user, _attrs), do: {:error, :not_used}

    def init_transaction(_purchase, _provider_product, _attrs) do
      send(self(), :steam_init_transaction)
      {:error, :not_used}
    end
  end

  @urls %{
    "success_url" => "https://example.test/success",
    "cancel_url" => "https://example.test/cancel"
  }

  setup do
    original_stripe = Application.get_env(:gamend_core, :stripe_adapter)
    original_adapters = Application.get_env(:gamend_core, :payment_provider_adapters)
    original_hooks = Application.get_env(:gamend_core, :hooks_module)

    Application.put_env(:gamend_core, :stripe_adapter, StripeAdapter)
    Application.put_env(:gamend_core, :payment_provider_adapters, steam: StoreAdapter)
    Application.put_env(:gamend_core, :hooks_module, NoopPaymentHooks)

    on_exit(fn ->
      restore_env(:stripe_adapter, original_stripe)
      restore_env(:payment_provider_adapters, original_adapters)
      restore_env(:hooks_module, original_hooks)
    end)

    :ok
  end

  test "a new checkout expires the open one for the same entitlement and goes ahead" do
    user = AccountsFixtures.user_fixture()
    key = unique_key()
    yearly = create_product(key, "subscription")
    lifetime = create_product(key, "entitlement")
    other = create_product(unique_key(), "entitlement")

    assert {:ok, %{purchase: other_open}} = checkout(user, other)
    assert {:ok, %{purchase: yearly_open}} = checkout(user, yearly)

    assert {:ok, %{purchase: lifetime_open, provider_session_id: session_id}} =
             checkout(user, lifetime)

    assert session_id == "cs_open_#{lifetime_open.id}"
    assert lifetime_open.status == "requires_action"

    expired_id = yearly_open.provider_transaction_id
    assert_received {:stripe_expire, ^expired_id}
    refute_received {:stripe_expire, _session_id}

    yearly_cancelled = Repo.get!(Purchase, yearly_open.id)
    assert yearly_cancelled.status == "cancelled"
    assert yearly_cancelled.raw_provider_payload["stripe_session"]["status"] == "expired"

    # An open checkout for another entitlement is not this one's to close.
    assert Repo.get!(Purchase, other_open.id).status == "requires_action"
  end

  test "a trial end comes from the server's options only, never the client's attrs" do
    user = AccountsFixtures.user_fixture()
    yearly = create_product(unique_key(), "subscription")
    trial_end = DateTime.add(DateTime.utc_now(), 10, :day)

    assert {:ok, %{purchase: first}} =
             checkout(user, yearly, %{"trial_end" => DateTime.to_unix(trial_end)})

    assert_received {:stripe_checkout_attrs, attrs}
    refute Map.has_key?(attrs, "trial_end")

    # Expire the first so the second may open.
    _ = Repo.update!(Purchase.changeset(first, %{status: "cancelled"}))

    assert {:ok, _} = checkout(user, yearly, %{}, trial_end: trial_end)
    assert_received {:stripe_checkout_attrs, attrs}
    assert attrs["trial_end"] == DateTime.to_unix(trial_end)
  end

  test "a session paid meanwhile is fulfilled, never cancelled, and the new checkout refused" do
    user = AccountsFixtures.user_fixture()
    key = unique_key()
    yearly = create_product(key, "entitlement")
    lifetime = create_product(key, "entitlement")
    paid = open_purchase(user, yearly, "cs_paid_")

    assert {:error, :already_owned} = checkout(user, lifetime)

    paid_id = paid.provider_transaction_id
    assert_received {:stripe_expire, ^paid_id}
    assert Repo.get!(Purchase, paid.id).status == "completed"
    assert Payments.has_entitlement?(user.id, key)
    assert [%Purchase{id: id}] = Payments.list_user_purchases(user.id)
    assert id == paid.id
  end

  test "a session whose payment is still clearing keeps refusing" do
    user = AccountsFixtures.user_fixture()
    key = unique_key()
    yearly = create_product(key, "entitlement")
    lifetime = create_product(key, "entitlement")
    paying = open_purchase(user, yearly, "cs_paying_")

    assert {:error, :purchase_already_in_progress} = checkout(user, lifetime)
    assert Repo.get!(Purchase, paying.id).status == "requires_action"
    assert length(Payments.list_user_purchases(user.id)) == 1
  end

  test "another provider's open purchase is left alone, and Steam closes no Stripe checkout" do
    user = AccountsFixtures.user_fixture()
    key = unique_key()
    yearly = create_product(key, "entitlement")
    lifetime = create_product(key, "entitlement")

    {:ok, steam_product} =
      Payments.create_provider_product(%{
        "product_id" => yearly.product.id,
        "provider" => "steam",
        "external_id" => to_string(System.unique_integer([:positive])),
        "currency" => "USD",
        "unit_amount" => 999
      })

    {:ok, steam_open} = Payments.create_purchase(user, steam_product, %{})

    {:ok, steam_open} =
      steam_open |> Purchase.changeset(%{status: "requires_action"}) |> Repo.update()

    assert {:error, :purchase_already_in_progress} = checkout(user, lifetime)
    refute_received {:stripe_expire, _session_id}
    assert Repo.get!(Purchase, steam_open.id).status == "requires_action"

    # The other way round: a Stripe checkout left open still holds a Steam one.
    {:ok, steam_open} =
      steam_open |> Purchase.changeset(%{status: "cancelled"}) |> Repo.update()

    assert {:ok, %{purchase: stripe_open}} = checkout(user, yearly)

    assert {:error, :purchase_already_in_progress} =
             Payments.create_steam_checkout(user, %{"provider_product_id" => steam_product.id})

    refute_received {:stripe_expire, _session_id}
    refute_received :steam_init_transaction
    assert Repo.get!(Purchase, stripe_open.id).status == "requires_action"
    assert Repo.get!(Purchase, steam_open.id).status == "cancelled"
  end

  test "Stripe's own expiry still cancels the purchase" do
    user = AccountsFixtures.user_fixture()
    product = create_product(unique_key(), "entitlement")
    assert {:ok, %{purchase: open}} = checkout(user, product)

    event = %{
      "id" => "evt_expired_#{System.unique_integer([:positive])}",
      "type" => "checkout.session.expired",
      "data" => %{
        "object" => %{
          "id" => open.provider_transaction_id,
          "object" => "checkout.session",
          "status" => "expired",
          "metadata" => %{"purchase_id" => open.id, "order_id" => open.order_id}
        }
      }
    }

    assert {:ok, :processed} = Payments.handle_stripe_webhook(Jason.encode!(event), "sig")

    cancelled = Repo.get!(Purchase, open.id)
    assert cancelled.status == "cancelled"
    assert cancelled.raw_provider_payload["stripe_session"]["status"] == "expired"
  end

  defp checkout(user, provider_product, extra \\ %{}, opts \\ []) do
    Payments.create_stripe_checkout(
      user,
      @urls |> Map.put("provider_product_id", provider_product.id) |> Map.merge(extra),
      opts
    )
  end

  defp open_purchase(user, provider_product, session_prefix) do
    {:ok, purchase} = Payments.create_purchase(user, provider_product, %{})

    {:ok, purchase} =
      Payments.mark_purchase_requires_action(purchase, %{
        "id" => session_prefix <> to_string(purchase.id),
        "url" => "https://checkout.test/session/#{purchase.id}"
      })

    purchase
  end

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
        "currency" => "USD",
        "unit_amount" => 999
      })

    Repo.preload(provider_product, :product)
  end

  defp unique_key, do: "pro_#{System.unique_integer([:positive])}"

  defp restore_env(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore_env(key, value), do: Application.put_env(:gamend_core, key, value)
end
