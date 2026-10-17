defmodule GamendWeb.Api.V1.PaymentControllerTest do
  use GamendWeb.ConnCase

  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias GamendWeb.Auth.Guardian

  defmodule NoopPaymentHooks do
    use Gamend.TestSupport.NoopHooks
  end

  defmodule StripeAdapter do
    def create_checkout_session(_purchase, %{external_id: "price_fail" <> _rest}, _attrs) do
      {:error, :stripe_not_configured}
    end

    def create_checkout_session(purchase, _provider_product, _attrs) do
      {:ok,
       %{
         "id" => "cs_test_#{purchase.id}",
         "url" => "https://checkout.test/session/#{purchase.id}"
       }}
    end

    def expire_checkout_session(session_id) do
      {:ok, %{"id" => session_id, "object" => "checkout.session", "status" => "expired"}}
    end

    def verify_webhook(raw_body, _signature), do: Jason.decode(raw_body)
  end

  defmodule StoreAdapter do
    def validate_purchase(_user, attrs) do
      attrs = normalize(attrs)

      {:ok,
       %{
         "product_id" => attrs["product_id"],
         "transaction_id" => attrs["transaction_id"],
         "status" => attrs["status"] || "completed",
         "environment" => "test",
         "raw_payload" => attrs
       }}
    end

    def verify_webhook(raw_body, _authorization), do: Jason.decode(raw_body)
    def verify_notification(raw_body), do: Jason.decode(raw_body)

    def init_transaction(purchase, _provider_product, _attrs) do
      {:ok,
       %{
         "response" => %{
           "result" => "OK",
           "params" => %{
             "orderid" => purchase.order_id,
             "transid" => "steam_tx_#{purchase.id}",
             "steamurl" => "https://steam.test/checkout/#{purchase.order_id}"
           }
         }
       }}
    end

    def finalize_transaction(purchase, _attrs) do
      {:ok,
       %{
         "product_id" => purchase.provider_product.external_id,
         "transaction_id" => purchase.provider_transaction_id || "steam_tx_#{purchase.id}",
         "original_transaction_id" => purchase.order_id,
         "status" => "completed",
         "environment" => "test",
         "raw_payload" => %{"steam_finalize" => %{"ok" => true}}
       }}
    end

    defp normalize(attrs) do
      Map.new(attrs, fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
        pair -> pair
      end)
    end
  end

  setup do
    original_stripe = Application.get_env(:gamend_core, :stripe_adapter)
    original_adapters = Application.get_env(:gamend_core, :payment_provider_adapters)
    original_hooks = Application.get_env(:gamend_core, :hooks_module)

    Application.put_env(:gamend_core, :stripe_adapter, StripeAdapter)

    Application.put_env(:gamend_core, :payment_provider_adapters,
      apple: StoreAdapter,
      google: StoreAdapter,
      steam: StoreAdapter
    )

    Application.put_env(:gamend_core, :hooks_module, NoopPaymentHooks)

    on_exit(fn ->
      restore_env(:stripe_adapter, original_stripe)
      restore_env(:payment_provider_adapters, original_adapters)
      restore_env(:hooks_module, original_hooks)
    end)

    :ok
  end

  describe "GET /api/v1/payments/catalog" do
    test "lists active provider products", %{conn: conn} do
      {product, provider_product} = create_provider_product("stripe", "price_catalog")

      response =
        conn
        |> get("/api/v1/payments/catalog", %{provider: "stripe"})
        |> json_response(200)

      assert [
               %{
                 "provider" => "stripe",
                 "external_id" => external_id,
                 "product" => %{"sku" => sku}
               }
             ] = response["data"]

      assert external_id == provider_product.external_id
      assert sku == product.sku
    end
  end

  describe "GET /api/v1/payments/catalog paging" do
    test "is a page", %{conn: conn} do
      create_provider_product("stripe", "price_page_a")
      create_provider_product("stripe", "price_page_b")

      body =
        conn
        |> get("/api/v1/payments/catalog", %{provider: "stripe", page_size: 1})
        |> json_response(200)

      assert [%{"product" => %{"sku" => _}}] = body["data"]
      assert body["meta"]["total_count"] >= 2
      assert body["meta"]["has_more"] == true
    end
  end

  describe "GET /api/v1/payments/entitlements" do
    test "lists the caller's active entitlements as a page", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {product, provider_product} = create_entitlement_provider_product("stripe", "price_owned")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "cs_owned_list"
        })

      {:ok, _completed} = Payments.fulfill_purchase(purchase)

      body =
        conn |> auth_conn(user) |> get("/api/v1/payments/entitlements") |> json_response(200)

      assert [entitlement] = body["data"]
      assert entitlement["key"] == product.sku
      assert entitlement["product_id"] == product.id
      assert entitlement["source_purchase_id"] == purchase.id
      assert body["meta"]["total_count"] == 1
    end
  end

  describe "POST /api/v1/payments/checkout/stripe" do
    test "creates a pending purchase and returns checkout session", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {product, _provider_product} = create_provider_product("stripe", "price_checkout")

      response =
        conn
        |> auth_conn(user)
        |> post("/api/v1/payments/checkout/stripe", %{
          "product_sku" => product.sku,
          "success_url" => "https://example.test/success",
          "cancel_url" => "https://example.test/cancel"
        })
        |> json_response(200)

      assert response["data"]["checkout_url"] =~ "https://checkout.test/session/"
      assert response["data"]["provider_session_id"] =~ "cs_test_"
      assert response["data"]["purchase"]["status"] == "requires_action"
    end

    test "rejects multi-quantity checkout for entitlement products", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      {product, _provider_product} =
        create_entitlement_provider_product("stripe", "price_artbook")

      response =
        conn
        |> auth_conn(user)
        |> post("/api/v1/payments/checkout/stripe", %{
          "product_sku" => product.sku,
          "quantity" => 100,
          "success_url" => "https://example.test/success",
          "cancel_url" => "https://example.test/cancel"
        })
        |> json_response(400)

      assert response["error"] == "quantity_not_allowed"
    end

    test "rejects checkout for already-owned entitlement products", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {product, provider_product} = create_entitlement_provider_product("stripe", "price_artbook")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "cs_owned_artbook"
        })

      {:ok, _completed} = Payments.fulfill_purchase(purchase)

      response =
        conn
        |> auth_conn(user)
        |> post("/api/v1/payments/checkout/stripe", %{
          "product_sku" => product.sku,
          "success_url" => "https://example.test/success",
          "cancel_url" => "https://example.test/cancel"
        })
        |> json_response(409)

      assert response["error"] == "already_owned"
    end

    test "a second checkout for an entitlement replaces the open one", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      {product, _provider_product} =
        create_entitlement_provider_product("stripe", "price_artbook")

      params = %{
        "product_sku" => product.sku,
        "success_url" => "https://example.test/success",
        "cancel_url" => "https://example.test/cancel"
      }

      first =
        conn
        |> auth_conn(user)
        |> post("/api/v1/payments/checkout/stripe", params)
        |> json_response(200)

      assert first["data"]["purchase"]["status"] == "requires_action"

      second =
        build_conn()
        |> auth_conn(user)
        |> post("/api/v1/payments/checkout/stripe", params)
        |> json_response(200)

      assert second["data"]["purchase"]["status"] == "requires_action"
      assert second["data"]["purchase"]["id"] != first["data"]["purchase"]["id"]

      statuses = user.id |> Payments.list_user_purchases() |> Enum.map(& &1.status)
      assert Enum.sort(statuses) == ["cancelled", "requires_action"]
    end

    test "rejects checkout while another provider's purchase is in progress", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      {product, _provider_product} =
        create_entitlement_provider_product("stripe", "price_artbook")

      {:ok, steam_product} =
        Payments.create_provider_product(%{
          "product_id" => product.id,
          "provider" => "steam",
          "external_id" => "steam_artbook_#{System.unique_integer([:positive])}",
          "currency" => "USD",
          "unit_amount" => 999
        })

      {:ok, _steam_open} =
        Payments.create_purchase(user, steam_product, %{"status" => "requires_action"})

      response =
        conn
        |> auth_conn(user)
        |> post("/api/v1/payments/checkout/stripe", %{
          "product_sku" => product.sku,
          "success_url" => "https://example.test/success",
          "cancel_url" => "https://example.test/cancel"
        })
        |> json_response(409)

      assert response["error"] == "purchase_already_in_progress"
    end

    test "failed checkout creation marks purchase failed and allows retry", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {product, _provider_product} = create_provider_product("stripe", "price_fail")

      params = %{
        "product_sku" => product.sku,
        "success_url" => "https://example.test/success",
        "cancel_url" => "https://example.test/cancel"
      }

      first =
        conn
        |> auth_conn(user)
        |> post("/api/v1/payments/checkout/stripe", params)
        |> json_response(503)

      assert first["error"] == "stripe_not_configured"

      second =
        build_conn()
        |> auth_conn(user)
        |> post("/api/v1/payments/checkout/stripe", params)
        |> json_response(503)

      assert second["error"] == "stripe_not_configured"

      purchases = Payments.list_user_purchases(user.id)
      assert length(purchases) == 2
      assert Enum.all?(purchases, &(&1.status == "failed"))
    end
  end

  describe "POST /api/v1/payments/checkout/steam" do
    test "creates and finalizes a Steam MicroTxn purchase", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_provider_product("steam", "100")

      checkout =
        conn
        |> auth_conn(user)
        |> post("/api/v1/payments/checkout/steam", %{
          "provider_product_id" => provider_product.id,
          "steam_id" => "76561197972751825",
          "currency" => "USD"
        })
        |> json_response(200)

      assert checkout["data"]["steam_url"] =~ "https://steam.test/checkout/"
      assert checkout["data"]["purchase"]["status"] == "requires_action"

      order_id = checkout["data"]["purchase"]["order_id"]

      finalized =
        build_conn()
        |> auth_conn(user)
        |> post("/api/v1/payments/steam/finalize", %{"order_id" => order_id})
        |> json_response(200)

      assert finalized["data"]["status"] == "completed"
    end
  end

  describe "POST /api/v1/payments/webhooks/stripe" do
    test "fulfills checkout session and ignores duplicate event", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_provider_product("stripe", "price_webhook")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "status" => "requires_action",
          "provider_transaction_id" => "cs_paid"
        })

      body =
        Jason.encode!(%{
          "id" => "evt_checkout_paid",
          "type" => "checkout.session.completed",
          "data" => %{
            "object" => %{
              "id" => "cs_paid",
              "payment_status" => "paid",
              "amount_total" => 199,
              "currency" => "usd",
              "metadata" => %{
                "purchase_id" => to_string(purchase.id),
                "order_id" => purchase.order_id
              }
            }
          }
        })

      response =
        conn
        |> json_webhook_conn()
        |> post("/api/v1/payments/webhooks/stripe", body)
        |> json_response(200)

      assert response == %{"data" => %{"status" => "processed"}}

      charge_body =
        Jason.encode!(%{
          "id" => "evt_charge_succeeded",
          "type" => "charge.succeeded",
          "data" => %{
            "object" => %{
              "id" => "ch_paid",
              "object" => "charge",
              "metadata" => %{"purchase_id" => to_string(purchase.id)}
            }
          }
        })

      charge_response =
        build_conn()
        |> json_webhook_conn()
        |> post("/api/v1/payments/webhooks/stripe", charge_body)
        |> json_response(200)

      assert charge_response == %{"data" => %{"status" => "processed"}}
      assert Payments.get_purchase(purchase.id).provider_original_transaction_id == "ch_paid"

      refund_body =
        Jason.encode!(%{
          "id" => "evt_refund_created",
          "type" => "charge.refunded",
          "data" => %{
            "object" => %{
              "id" => "ch_paid",
              "object" => "charge",
              "amount" => 999,
              "amount_refunded" => 999
            }
          }
        })

      refund_response =
        build_conn()
        |> json_webhook_conn()
        |> post("/api/v1/payments/webhooks/stripe", refund_body)
        |> json_response(200)

      assert refund_response == %{"data" => %{"status" => "processed"}}
      assert Payments.get_purchase(purchase.id).status == "refunded"

      duplicate_response =
        build_conn()
        |> json_webhook_conn()
        |> post("/api/v1/payments/webhooks/stripe", body)
        |> json_response(200)

      assert duplicate_response == %{"data" => %{"status" => "duplicate"}}
    end

    test "marks async checkout payment failure without fulfilling", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_entitlement_provider_product("stripe", "price_async")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "status" => "requires_action",
          "provider_transaction_id" => "cs_async_failed"
        })

      body =
        Jason.encode!(%{
          "id" => "evt_checkout_async_failed",
          "type" => "checkout.session.async_payment_failed",
          "data" => %{
            "object" => %{
              "id" => "cs_async_failed",
              "payment_status" => "unpaid",
              "metadata" => %{
                "purchase_id" => to_string(purchase.id),
                "order_id" => purchase.order_id
              }
            }
          }
        })

      response =
        conn
        |> json_webhook_conn()
        |> post("/api/v1/payments/webhooks/stripe", body)
        |> json_response(200)

      assert response == %{"data" => %{"status" => "processed"}}
      assert Payments.get_purchase(purchase.id).status == "failed"
      assert Payments.list_user_entitlements(user.id) == []
    end

    test "refreshes and revokes Stripe subscription from subscription events", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_subscription_provider_product("stripe", "price_sub")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "status" => "requires_action",
          "provider_transaction_id" => "cs_sub"
        })

      checkout_body =
        Jason.encode!(%{
          "id" => "evt_checkout_sub_paid",
          "type" => "checkout.session.completed",
          "data" => %{
            "object" => %{
              "id" => "cs_sub",
              "payment_status" => "paid",
              "subscription" => %{
                "id" => "sub_webhook",
                "status" => "active",
                "cancel_at_period_end" => false,
                "items" => %{"data" => [%{"current_period_end" => 1_900_000_000}]}
              },
              "metadata" => %{
                "purchase_id" => to_string(purchase.id),
                "order_id" => purchase.order_id
              }
            }
          }
        })

      assert %{"data" => %{"status" => "processed"}} =
               conn
               |> json_webhook_conn()
               |> post("/api/v1/payments/webhooks/stripe", checkout_body)
               |> json_response(200)

      [entitlement] = Payments.list_user_entitlements(user.id)
      assert entitlement.expires_at == DateTime.from_unix!(1_900_000_000, :second)

      update_body =
        Jason.encode!(%{
          "id" => "evt_sub_updated",
          "type" => "customer.subscription.updated",
          "data" => %{
            "object" => %{
              "id" => "sub_webhook",
              "status" => "active",
              "cancel_at_period_end" => true,
              "items" => %{"data" => [%{"current_period_end" => 1_901_000_000}]},
              "metadata" => %{"purchase_id" => to_string(purchase.id)}
            }
          }
        })

      assert %{"data" => %{"status" => "processed"}} =
               build_conn()
               |> json_webhook_conn()
               |> post("/api/v1/payments/webhooks/stripe", update_body)
               |> json_response(200)

      [entitlement] = Payments.list_user_entitlements(user.id)
      assert entitlement.expires_at == DateTime.from_unix!(1_901_000_000, :second)
      assert entitlement.metadata["stripe_subscription_cancel_at_period_end"] == true

      deleted_body =
        Jason.encode!(%{
          "id" => "evt_sub_deleted",
          "type" => "customer.subscription.deleted",
          "data" => %{
            "object" => %{
              "id" => "sub_webhook",
              "status" => "canceled",
              "cancel_at_period_end" => true,
              "items" => %{"data" => [%{"current_period_end" => 1_901_000_000}]},
              "metadata" => %{"purchase_id" => to_string(purchase.id)}
            }
          }
        })

      assert %{"data" => %{"status" => "processed"}} =
               build_conn()
               |> json_webhook_conn()
               |> post("/api/v1/payments/webhooks/stripe", deleted_body)
               |> json_response(200)

      assert Payments.get_purchase(purchase.id).status == "cancelled"
      assert Payments.list_user_entitlements(user.id) == []
    end
  end

  describe "POST /api/v1/payments/webhooks/stripe outcomes" do
    test "an event type the server does not act on is ignored", %{conn: conn} do
      body = Jason.encode!(%{"id" => "evt_other", "type" => "customer.created", "data" => %{}})

      response =
        conn
        |> json_webhook_conn()
        |> post("/api/v1/payments/webhooks/stripe", body)
        |> json_response(200)

      assert response == %{"data" => %{"status" => "ignored"}}
    end

    test "an event with no type is refused with a code", %{conn: conn} do
      body = Jason.encode!(%{"id" => "evt_untyped", "data" => %{}})

      response =
        conn
        |> json_webhook_conn()
        |> post("/api/v1/payments/webhooks/stripe", body)
        |> json_response(400)

      assert response["error"] =~ ~r/^[a-z][a-z0-9_]*$/
    end
  end

  describe "POST /api/v1/payments/webhooks/google" do
    test "revokes purchase from voided purchase notification", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_provider_product("google", "coins_google_webhook")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "GPA.1",
          "provider_original_transaction_id" => "google_token_1"
        })

      {:ok, _purchase} = Payments.fulfill_purchase(purchase)

      body =
        Jason.encode!(%{
          "message_id" => "google_msg_1",
          "voidedPurchaseNotification" => %{
            "purchaseToken" => "google_token_1",
            "orderId" => "GPA.1",
            "productType" => 2,
            "refundType" => 1
          }
        })

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/payments/webhooks/google", body)
        |> json_response(200)

      assert response == %{"data" => %{"status" => "processed"}}
      assert Payments.get_purchase(purchase.id).status == "refunded"
    end
  end

  describe "POST /api/v1/payments/webhooks/apple" do
    test "revokes purchase from App Store notification", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_provider_product("apple", "coins_apple_webhook")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "apple_tx_1",
          "provider_original_transaction_id" => "apple_orig_1"
        })

      {:ok, _purchase} = Payments.fulfill_purchase(purchase)

      body =
        Jason.encode!(%{
          "notificationUUID" => "apple_note_1",
          "notificationType" => "REFUND",
          "decoded_transaction_info" => %{
            "transactionId" => "apple_tx_1",
            "originalTransactionId" => "apple_orig_1",
            "productId" => provider_product.external_id,
            "revocationDate" => "1700000000000"
          }
        })

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/payments/webhooks/apple", body)
        |> json_response(200)

      assert response == %{"data" => %{"status" => "processed"}}
      assert Payments.get_purchase(purchase.id).status == "revoked"
    end
  end

  describe "POST /api/v1/payments/validate/:provider" do
    test "validates store purchase through provider adapter", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_provider_product("google", "coins_google")

      response =
        conn
        |> auth_conn(user)
        |> post("/api/v1/payments/validate/google", %{
          "product_id" => provider_product.external_id,
          "transaction_id" => "google_tx_1"
        })
        |> json_response(200)

      assert response["data"]["seen_before"] == false
      assert response["data"]["purchase"]["status"] == "completed"
    end

    test "an unknown provider is refused", %{conn: conn} do
      response =
        conn
        |> auth_conn(AccountsFixtures.user_fixture())
        |> post("/api/v1/payments/validate/paypal", %{"transaction_id" => "x"})
        |> json_response(400)

      assert response["error"] == "unknown_provider"
    end
  end

  defp create_provider_product(provider, external_id) do
    sku = "coins_#{System.unique_integer([:positive])}"

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "100 Coins",
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

  defp create_entitlement_provider_product(provider, external_id) do
    sku = "artbook_#{System.unique_integer([:positive])}"

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "Digital Artbook",
        "kind" => "entitlement",
        "grant_config" => %{"entitlement_key" => sku}
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

  defp create_subscription_provider_product(provider, external_id) do
    sku = "premium_#{System.unique_integer([:positive])}"

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "Premium Monthly",
        "kind" => "subscription",
        "grant_config" => %{"entitlement_key" => "premium"}
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

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp json_webhook_conn(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", "test")
  end

  defp restore_env(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore_env(key, value), do: Application.put_env(:gamend_core, key, value)
end
