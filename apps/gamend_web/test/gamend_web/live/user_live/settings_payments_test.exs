defmodule GamendWeb.UserLive.SettingsPaymentsTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.AccountsFixtures
  alias Gamend.Payments

  defmodule NoopPaymentHooks do
    use Gamend.TestSupport.NoopHooks
  end

  defmodule StripeAdapter do
    # Runs in the LiveView process, so the return URL rides back in the
    # redirect target rather than a message to the test.
    def create_billing_portal_session("cus_settings_portal", return_url) do
      {:ok,
       %{
         "id" => "bps_settings",
         "url" => "https://billing.stripe.test/p/session?back=" <> URI.encode_www_form(return_url)
       }}
    end

    def cancel_subscription_at_period_end("sub_settings_cancel") do
      {:ok,
       %{
         "id" => "sub_settings_cancel",
         "object" => "subscription",
         "status" => "active",
         "cancel_at_period_end" => true,
         "current_period_end" => 1_900_000_000
       }}
    end
  end

  setup do
    original_stripe = Application.get_env(:gamend_core, :stripe_adapter)
    original_hooks = Application.get_env(:gamend_core, :hooks_module)

    Application.put_env(:gamend_core, :stripe_adapter, StripeAdapter)
    Application.put_env(:gamend_core, :hooks_module, NoopPaymentHooks)

    on_exit(fn ->
      restore_env(:stripe_adapter, original_stripe)
      restore_env(:hooks_module, original_hooks)
    end)

    :ok
  end

  test "regular user can view purchases and owned entitlements", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {_coins_product, coins_provider_product} = create_consumable_provider_product("stripe")
    {_pass_product, pass_provider_product} = create_downloadable_provider_product("stripe")

    {:ok, coins_purchase} = Payments.create_purchase(user, coins_provider_product)
    {:ok, _coins_purchase} = Payments.fulfill_purchase(coins_purchase)

    {:ok, pass_purchase} = Payments.create_purchase(user, pass_provider_product)
    {:ok, _pass_purchase} = Payments.fulfill_purchase(pass_purchase)

    {:ok, view, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    assert html =~ "Payments"

    view
    |> element(~s(button[phx-click="settings_tab"][phx-value-tab="payments"]))
    |> render_click()

    rendered = render(view)
    assert rendered =~ coins_purchase.order_id
    assert rendered =~ pass_purchase.order_id
    assert rendered =~ "Completed"
    assert rendered =~ "Starter Pack"
    assert rendered =~ "starter_pack"
    assert rendered =~ "Download"
    refute rendered =~ "Game Wallet"
  end

  test "regular user can schedule Stripe subscription cancellation", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {_product, provider_product} = create_subscription_provider_product("stripe")

    {:ok, purchase} =
      Payments.create_purchase(user, provider_product, %{
        "metadata" => %{"stripe_subscription_id" => "sub_settings_cancel"}
      })

    {:ok, _purchase} = Payments.fulfill_purchase(purchase)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings?tab=payments")

    html = render(view)
    assert html =~ "Premium"
    assert html =~ "Auto-renews"
    assert html =~ "Cancel renewal"

    html =
      view
      |> element(~s(button[phx-click="cancel_stripe_subscription"]), "Cancel renewal")
      |> render_click()

    assert html =~ "Subscription will cancel at the end of the period."
    assert html =~ "Cancels at period end"
    refute html =~ "Cancel renewal"

    [entitlement] = Payments.list_user_entitlements(user.id)
    assert entitlement.expires_at == DateTime.from_unix!(1_900_000_000, :second)
    assert entitlement.metadata["stripe_subscription_cancel_at_period_end"] == true
  end

  test "Manage billing opens the Stripe portal for an account that paid through Stripe", %{
    conn: conn
  } do
    user = AccountsFixtures.user_fixture()
    {_product, provider_product} = create_consumable_provider_product("stripe")
    {:ok, purchase} = Payments.create_purchase(user, provider_product)

    {:ok, _purchase} =
      Payments.fulfill_purchase(purchase, %{
        "stripe_session" => %{"id" => "cs_portal", "customer" => "cus_settings_portal"}
      })

    assert Payments.stripe_customer_id(user) == "cus_settings_portal"

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings?tab=payments")

    assert {:error, {:redirect, %{to: "https://billing.stripe.test/p/session?back=" <> back}}} =
             view |> element("#open-stripe-portal") |> render_click()

    assert back |> URI.decode_www_form() |> String.ends_with?("/users/settings?tab=payments")
  end

  test "no Manage billing button for an account that never paid through Stripe", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {_product, provider_product} = create_consumable_provider_product("apple")
    {:ok, purchase} = Payments.create_purchase(user, provider_product)
    {:ok, _purchase} = Payments.fulfill_purchase(purchase)

    assert Payments.stripe_customer_id(user) == nil

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings?tab=payments")

    refute has_element?(view, "#open-stripe-portal")
  end

  defp create_consumable_provider_product(provider) do
    sku = "coins_#{System.unique_integer([:positive])}"

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "250 Coins",
        "kind" => "consumable",
        "grant_config" => %{"hook_payload" => %{"coins" => 250}}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => provider,
        "external_id" => "price_#{sku}",
        "currency" => "USD",
        "unit_amount" => 299
      })

    {product, provider_product}
  end

  defp create_downloadable_provider_product(provider) do
    sku = "starter_pack_#{System.unique_integer([:positive])}"

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "Starter Pack",
        "kind" => "entitlement",
        "grant_config" => %{
          "entitlement_key" => "starter_pack",
          "download" => %{"asset_key" => "starter_pack.zip", "filename" => "starter_pack.zip"}
        }
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => provider,
        "external_id" => "price_#{sku}",
        "currency" => "USD",
        "unit_amount" => 499
      })

    {product, provider_product}
  end

  defp create_subscription_provider_product(provider) do
    sku = "premium_#{System.unique_integer([:positive])}"

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "Premium",
        "kind" => "subscription",
        "grant_config" => %{"entitlement_key" => "premium"}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => provider,
        "external_id" => "price_#{sku}",
        "currency" => "USD",
        "unit_amount" => 999
      })

    {product, provider_product}
  end

  defp restore_env(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore_env(key, value), do: Application.put_env(:gamend_core, key, value)
end
