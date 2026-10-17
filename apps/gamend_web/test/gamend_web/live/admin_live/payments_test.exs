defmodule GamendWeb.AdminLive.PaymentsTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Repo

  defmodule StripeReconcileAdapter do
    def retrieve_checkout_session("cs_paid_" <> _rest = session_id) do
      {:ok,
       %{
         "id" => session_id,
         "object" => "checkout.session",
         "status" => "complete",
         "payment_status" => "paid",
         "amount_total" => 199,
         "currency" => "usd",
         "metadata" => %{},
         "payment_intent" => %{"id" => "pi_paid", "status" => "succeeded"}
       }}
    end

    def retrieve_checkout_session("cs_expired_" <> _rest = session_id) do
      {:ok,
       %{
         "id" => session_id,
         "object" => "checkout.session",
         "status" => "expired",
         "payment_status" => "unpaid",
         "amount_total" => 199,
         "currency" => "usd",
         "metadata" => %{}
       }}
    end

    def retrieve_checkout_session("cs_sub_completed_" <> _rest = session_id) do
      {:ok,
       %{
         "id" => session_id,
         "object" => "checkout.session",
         "status" => "complete",
         "payment_status" => "paid",
         "amount_total" => 999,
         "currency" => "usd",
         "metadata" => %{},
         "subscription" => %{
           "id" => "sub_admin_reconcile",
           "object" => "subscription",
           "status" => "active",
           "cancel_at_period_end" => false,
           "items" => %{"data" => [%{"current_period_end" => 1_900_000_000}]}
         }
       }}
    end

    def retrieve_checkout_session(_session_id) do
      {:error, {:stripe_error, %{"message" => "No such checkout session"}}}
    end

    def create_refund("pi_admin_refund", _opts) do
      {:ok, %{"id" => "re_admin", "object" => "refund", "status" => "succeeded"}}
    end
  end

  setup do
    original_secret =
      Gamend.SettingsHelpers.get(
        :gamend_core,
        Gamend.Payments.Settings,
        :stripe_sandbox_secret_key
      )

    original_webhook =
      Gamend.SettingsHelpers.get(
        :gamend_core,
        Gamend.Payments.Settings,
        :stripe_sandbox_webhook_secret
      )

    original_environment =
      Gamend.SettingsHelpers.get(
        :gamend_core,
        Gamend.Payments.Settings,
        :environment
      )

    original_stripe_adapter = Application.get_env(:gamend_core, :stripe_adapter)

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.Payments.Settings,
      :stripe_sandbox_secret_key,
      "sk_test_admin_payments_123456"
    )

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.Payments.Settings,
      :stripe_sandbox_webhook_secret,
      "whsec_admin_payments_123456"
    )

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.Payments.Settings,
      :environment,
      :sandbox
    )

    Application.put_env(:gamend_core, :stripe_adapter, StripeReconcileAdapter)

    on_exit(fn ->
      restore_env("GAMEND_PAYMENTS_STRIPE_SANDBOX_SECRET_KEY", original_secret)
      restore_env("GAMEND_PAYMENTS_STRIPE_SANDBOX_WEBHOOK_SECRET", original_webhook)

      Gamend.SettingsHelpers.put(
        :gamend_core,
        Gamend.Payments.Settings,
        :environment,
        original_environment
      )

      restore_app_env(:stripe_adapter, original_stripe_adapter)
    end)

    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    %{admin: admin}
  end

  test "admin can view payment config and purchase data", %{conn: conn, admin: admin} do
    {product, provider_product} = create_provider_product("stripe", "price_admin_view")
    {:ok, purchase} = Payments.create_purchase(admin, provider_product)
    {:ok, _purchase} = Payments.fulfill_purchase(purchase)

    {:ok, _view, html} = conn |> log_in_user(admin) |> live(~p"/admin/payments")

    assert html =~ "Payments"
    assert html =~ "Payment Providers"
    assert html =~ "configured"
    assert html =~ "sandbox"
    refute html =~ "sk_test_admin_payments"
    refute html =~ "whsec_admin_payments"
    assert html =~ product.sku
    assert html =~ provider_product.external_id
    assert html =~ purchase.order_id
    assert html =~ "completed"
    refute html =~ "Wallet Ledger"
  end

  test "admin can create product and provider SKU", %{conn: conn, admin: admin} do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/payments")

    view |> element(~S(button[phx-click="new_product"])) |> render_click()

    product_sku = "admin_created_#{System.unique_integer([:positive])}"

    view
    |> form("#admin-payment-product-form",
      product: %{
        "id" => "",
        "sku" => product_sku,
        "title" => "Admin Created",
        "description" => "Created from admin",
        "kind" => "consumable",
        "active" => "true",
        "grant_config_json" => ~s({"hook_payload":{"coins":25}}),
        "metadata_json" => "{}"
      }
    )
    |> render_submit()

    product = Payments.get_product_by_sku(product_sku)
    assert product.title == "Admin Created"

    view |> element(~S(button[phx-click="new_provider_product"])) |> render_click()

    external_id = "price_admin_created_#{System.unique_integer([:positive])}"

    view
    |> form("#admin-payment-provider-product-form",
      provider_product: %{
        "id" => "",
        "product_id" => to_string(product.id),
        "provider" => "stripe",
        "external_id" => external_id,
        "currency" => "USD",
        "unit_amount" => "250",
        "active" => "true",
        "metadata_json" => "{}"
      }
    )
    |> render_submit()

    assert %Gamend.Payments.ProviderProduct{} =
             Payments.get_provider_product("stripe", external_id)
  end

  test "admin can reconcile paid Stripe checkout", %{conn: conn, admin: admin} do
    {_product, provider_product} = create_provider_product("stripe", "price_reconcile_paid")

    {:ok, purchase} =
      Payments.create_purchase(admin, provider_product, %{
        "status" => "requires_action",
        "provider_transaction_id" => "cs_paid_#{System.unique_integer([:positive])}"
      })

    {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/admin/payments")

    assert html =~ "Reconcile Stripe"

    html =
      view
      |> element("#admin-purchase-#{purchase.id} button", "Reconcile Stripe")
      |> render_click()

    assert html =~ "Stripe purchase fulfilled"
    assert Payments.get_purchase(purchase.id).status == "completed"
  end

  test "admin can reconcile expired Stripe checkout", %{conn: conn, admin: admin} do
    {_product, provider_product} = create_provider_product("stripe", "price_reconcile_expired")

    {:ok, purchase} =
      Payments.create_purchase(admin, provider_product, %{
        "status" => "requires_action",
        "provider_transaction_id" => "cs_expired_#{System.unique_integer([:positive])}"
      })

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/payments")

    html =
      view
      |> element("#admin-purchase-#{purchase.id} button", "Reconcile Stripe")
      |> render_click()

    assert html =~ "Stripe purchase cancelled"
    assert Payments.get_purchase(purchase.id).status == "cancelled"
  end

  test "admin can reconcile completed Stripe subscription period metadata", %{
    conn: conn,
    admin: admin
  } do
    {_product, provider_product} =
      create_subscription_provider_product("stripe", "price_reconcile_sub")

    {:ok, purchase} =
      Payments.create_purchase(admin, provider_product, %{
        "provider_transaction_id" => "cs_sub_completed_#{System.unique_integer([:positive])}"
      })

    {:ok, _purchase} = Payments.fulfill_purchase(purchase)
    assert [entitlement] = Payments.list_user_entitlements(admin.id)
    assert entitlement.expires_at == nil

    {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/admin/payments")

    assert html =~ "Reconcile Stripe"

    html =
      view
      |> element("#admin-purchase-#{purchase.id} button", "Reconcile Stripe")
      |> render_click()

    assert html =~ "Stripe purchase already completed"
    assert [entitlement] = Payments.list_user_entitlements(admin.id)
    assert entitlement.expires_at == DateTime.from_unix!(1_900_000_000, :second)
  end

  test "admin refunds any Stripe purchase, with no window", %{conn: conn, admin: admin} do
    {_product, provider_product} = create_provider_product("stripe", "price_admin_refund")

    {:ok, purchase} =
      Payments.create_purchase(admin, provider_product, %{
        "metadata" => %{"stripe_payment_intent_id" => "pi_admin_refund"}
      })

    {:ok, purchase} = Payments.fulfill_purchase(purchase)

    purchase
    |> Payments.Purchase.changeset(%{
      purchased_at: DateTime.add(DateTime.utc_now(:second), -90 * 86_400)
    })
    |> Repo.update!()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/payments")

    html =
      view
      |> element("#admin-purchase-#{purchase.id} button", "Refund")
      |> render_click()

    assert html =~ "Stripe refund re_admin created (succeeded)"
    refute has_element?(view, "#admin-purchase-#{purchase.id} button", "Refund")

    assert Payments.get_purchase(purchase.id).metadata["stripe_refund"]["by"] == "admin"
  end

  defp create_provider_product(provider, external_id) do
    sku = "admin_pay_#{System.unique_integer([:positive])}"

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "Admin Pay Product",
        "kind" => "consumable",
        "grant_config" => %{"hook_payload" => %{"coins" => 100}}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => provider,
        "external_id" => external_id <> "_" <> to_string(System.unique_integer([:positive])),
        "currency" => "USD",
        "unit_amount" => 199
      })

    {product, provider_product}
  end

  defp create_subscription_provider_product(provider, external_id) do
    sku = "admin_sub_#{System.unique_integer([:positive])}"

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "Admin Subscription",
        "kind" => "subscription",
        "grant_config" => %{"entitlement_key" => "admin_subscription"}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => provider,
        "external_id" => external_id <> "_" <> to_string(System.unique_integer([:positive])),
        "currency" => "USD",
        "unit_amount" => 999
      })

    {product, provider_product}
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
  defp restore_app_env(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore_app_env(key, value), do: Application.put_env(:gamend_core, key, value)

  test "each section pages on its own through the shared pagination bar", %{
    conn: conn,
    admin: admin
  } do
    for _ <- 1..26 do
      {:ok, _} =
        Payments.create_product(%{
          "sku" => "admin_pay_page_#{System.unique_integer([:positive])}",
          "title" => "Paged Product",
          "kind" => "consumable",
          "grant_config" => %{}
        })
    end

    {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/admin/payments")

    assert html =~ "1 / 2 (26)"

    html =
      view
      |> element(~S(button[phx-click="section_next_page"][phx-value-section="products"]))
      |> render_click()

    assert html =~ "2 / 2 (26)"
  end

  test "admin opens provider SKU edit form via its UUID id", %{conn: conn, admin: admin} do
    {_product, provider_product} = create_provider_product("stripe", "price_edit_form_test")

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/payments")

    html = render_click(view, "edit_provider_product", %{"id" => provider_product.id})

    refute html =~ "Provider SKU not found"
    assert html =~ "price_edit_form_test"
  end
end
