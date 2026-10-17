defmodule Gamend.Payments.GooglePlayTest do
  @moduledoc """
  The Google Play adapter past a plain one-time purchase
  (`Payments.Providers.Google`): a subscription read from its first line item
  (status per state, the price in cents, a test purchase marked test), a
  product refunded or pending, an access token signed from a service account
  (inline or from a file) when none is configured, the inputs it needs and
  the errors Google answers, the RTDN push's shared token, and what the admin
  page is told is configured.
  """
  use ExUnit.Case, async: false

  alias Gamend.Payments.Providers.Google
  alias Gamend.Payments.Settings

  # The Android Publisher and OAuth endpoints, answered by the test.
  defmodule PlayAPI do
    def get(url, opts), do: answer(:get, url, opts)
    def post(url, opts), do: answer(:post, url, opts)

    defp answer(method, url, opts) do
      send(self(), {:play, method, url, opts})
      Process.get(:play_api).(method, url, opts)
    end
  end

  @env_keys ~w(
    GAMEND_PAYMENTS_GOOGLE_PLAY_PACKAGE_NAME
    GAMEND_PAYMENTS_GOOGLE_PLAY_ACCESS_TOKEN
    GAMEND_PAYMENTS_GOOGLE_PLAY_AUTO_ACKNOWLEDGE
    GAMEND_PAYMENTS_GOOGLE_PLAY_RTDN_TOKEN
    GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
    GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH
    GAMEND_PAYMENTS_GOOGLE_PLAY_PUBLISHER_BASE_URL
  )

  setup do
    settings = Application.get_env(:gamend_core, Settings)
    client = Application.get_env(:gamend_core, :payments_http_client)
    web_env = Application.get_env(:gamend_web, :environment)
    env = Map.new(@env_keys, &{&1, System.get_env(&1)})
    Enum.each(@env_keys, &System.delete_env/1)

    on_exit(fn ->
      restore(:gamend_core, Settings, settings)
      restore(:gamend_core, :payments_http_client, client)
      restore(:gamend_web, :environment, web_env)
      for {key, value} <- env, value, do: System.put_env(key, value)
    end)

    Application.put_env(:gamend_core, Settings, google_play_package_name: "com.example.game")
    Application.put_env(:gamend_core, :payments_http_client, PlayAPI)
    :ok
  end

  defp restore(app, key, nil), do: Application.delete_env(app, key)
  defp restore(app, key, value), do: Application.put_env(app, key, value)

  defp put_setting(key, value) do
    settings = Application.get_env(:gamend_core, Settings, [])
    Application.put_env(:gamend_core, Settings, Keyword.put(settings, key, value))
  end

  defp answer(fun), do: Process.put(:play_api, fun)
  defp ok(body), do: {:ok, %{status: 200, body: body}}

  defp subscription(state, extra \\ %{}) do
    Map.merge(
      %{
        "subscriptionState" => state,
        "latestOrderId" => "GPA.order",
        "lineItems" => [
          %{
            "productId" => "pro_monthly",
            "expiryTime" => "2026-11-17T00:00:00Z",
            "autoRenewingPlan" => %{
              "recurringPrice" => %{
                "currencyCode" => "EUR",
                "units" => "4",
                "nanos" => 990_000_000
              }
            }
          }
        ]
      },
      extra
    )
  end

  defp validate_subscription(body) do
    answer(fn :get, _url, _opts -> ok(body) end)
    Google.validate_purchase(nil, %{"purchase_token" => "sub_token", "type" => "subscription"})
  end

  describe "a subscription" do
    setup do
      put_setting(:google_play_access_token, "ya29_token")
      :ok
    end

    test "is read from its first line item: product, price in cents, expiry" do
      assert {:ok, result} = validate_subscription(subscription("SUBSCRIPTION_STATE_ACTIVE"))
      assert result["status"] == "completed"
      assert result["product_id"] == "pro_monthly"
      assert result["transaction_id"] == "GPA.order"
      assert result["original_transaction_id"] == "sub_token"
      assert result["currency"] == "EUR"
      assert result["amount"] == 499
      assert result["expires_at"] == "2026-11-17T00:00:00Z"

      assert_received {:play, :get, url, [auth: {:bearer, "ya29_token"}]}
      assert url =~ "/applications/com.example.game/purchases/subscriptionsv2/tokens/sub_token"
    end

    test "each state maps to a status" do
      for {state, status} <- [
            {"SUBSCRIPTION_STATE_IN_GRACE_PERIOD", "completed"},
            {"SUBSCRIPTION_STATE_CANCELED", "cancelled"},
            {"SUBSCRIPTION_STATE_EXPIRED", "revoked"},
            {"SUBSCRIPTION_STATE_ON_HOLD", "pending"},
            {"SUBSCRIPTION_STATE_PENDING", "pending"}
          ] do
        assert {:ok, %{"status" => ^status}} = validate_subscription(subscription(state))
      end
    end

    test "a test purchase is marked test; a renewal keeps its linked token" do
      body =
        subscription("SUBSCRIPTION_STATE_ACTIVE", %{
          "testPurchase" => %{},
          "linkedPurchaseToken" => "first_token"
        })

      assert {:ok, result} = validate_subscription(body)
      assert result["environment"] == "test"
      assert result["original_transaction_id"] == "first_token"
    end

    test "one with no line item, or no price, says what is missing" do
      assert validate_subscription(%{"subscriptionState" => "SUBSCRIPTION_STATE_ACTIVE"}) ==
               {:error, :missing_google_subscription_line_item}

      body = %{"lineItems" => [%{"productId" => "p"}], "subscriptionState" => "x"}
      assert {:ok, %{"amount" => nil, "currency" => nil}} = validate_subscription(body)
    end

    test "a token with no product named is a subscription" do
      answer(fn :get, _url, _opts -> ok(subscription("SUBSCRIPTION_STATE_ACTIVE")) end)
      assert {:ok, _} = Google.validate_purchase(nil, %{"purchaseToken" => "t"})
      assert_received {:play, :get, url, _}
      assert url =~ "subscriptionsv2"
    end
  end

  describe "a one-time product" do
    setup do
      put_setting(:google_play_access_token, "ya29_token")
      :ok
    end

    test "refunded or pending says so; acknowledged ones are not acknowledged again" do
      put_setting(:google_play_auto_acknowledge, "true")

      for {state, status} <- [{1, "cancelled"}, {2, "pending"}, {9, "pending"}] do
        answer(fn :get, _url, _opts ->
          ok(%{"purchaseState" => state, "acknowledgementState" => 1})
        end)

        assert {:ok, %{"status" => ^status}} =
                 Google.validate_purchase(nil, %{"product_id" => "coins", "token" => "t"})
      end

      refute_received {:play, :post, _, _}
    end

    test "Google's error answer is handed back with its status" do
      answer(fn :get, _url, _opts -> {:ok, %{status: 410, body: %{"error" => "gone"}}} end)

      assert Google.validate_purchase(nil, %{"sku" => "coins", "token" => "t"}) ==
               {:error, {:google_play_error, 410, %{"error" => "gone"}}}

      answer(fn :get, _url, _opts -> {:error, :timeout} end)

      assert Google.validate_purchase(nil, %{"sku" => "coins", "token" => "t"}) ==
               {:error, :timeout}
    end

    test "a failed acknowledgement fails the purchase" do
      put_setting(:google_play_auto_acknowledge, "yes")

      answer(fn
        :get, _url, _opts -> ok(%{"purchaseState" => 0, "acknowledgementState" => 0})
        :post, _url, _opts -> {:ok, %{status: 500, body: "boom"}}
      end)

      assert Google.validate_purchase(nil, %{"productId" => "coins", "token" => "t"}) ==
               {:error, {:google_play_error, 500, "boom"}}
    end
  end

  describe "what a validation needs" do
    test "a token, a product, a package and a credential" do
      assert Google.validate_purchase(nil, %{}) == {:error, :missing_purchase_token}

      put_setting(:google_play_package_name, "")

      assert Google.validate_purchase(nil, %{"token" => "t"}) ==
               {:error, :google_play_package_name_not_configured}

      put_setting(:google_play_package_name, "com.example.game")

      assert Google.validate_purchase(nil, %{"token" => "t", "product_id" => "c"}) ==
               {:error, :google_service_account_not_configured}

      put_setting(:google_play_access_token, "ya29")

      # A product named but empty: a token with no product at all is a
      # subscription.
      assert Google.validate_purchase(nil, %{"token" => "t", "product_id" => ""}) ==
               {:error, :missing_product_id}
    end
  end

  describe "a service account" do
    setup do
      jwk = JOSE.JWK.generate_key({:rsa, 2048})
      {_, pem} = JOSE.JWK.to_pem(jwk)

      account = %{
        "client_email" => "billing@example.iam.gserviceaccount.com",
        "private_key" => pem,
        "token_uri" => "https://oauth.test/token"
      }

      %{jwk: jwk, account: account}
    end

    defp signs_in(jwk) do
      answer(fn
        :post, "https://oauth.test/token", opts ->
          send(self(), {:assertion, Map.new(opts[:form])["assertion"]})
          ok(%{"access_token" => "from-service-account"})

        :get, _url, _opts ->
          ok(%{"purchaseState" => 0, "acknowledgementState" => 1})
      end)

      assert {:ok, _} = Google.validate_purchase(nil, %{"product_id" => "c", "token" => "t"})
      assert_received {:play, :get, _url, [auth: {:bearer, "from-service-account"}]}
      assert_received {:assertion, assertion}

      assert {true, %JOSE.JWT{fields: claims}, _} =
               JOSE.JWT.verify_strict(jwk, ["RS256"], assertion)

      claims
    end

    test "signs an assertion for a token, inline", %{jwk: jwk, account: account} do
      put_setting(:google_play_service_account_json, Jason.encode!(account))
      claims = signs_in(jwk)
      assert claims["iss"] == account["client_email"]
      assert claims["aud"] == "https://oauth.test/token"
      assert claims["scope"] =~ "androidpublisher"
      assert claims["exp"] - claims["iat"] == 3600
    end

    test "or read from a file", %{jwk: jwk, account: account} do
      path = Path.join(System.tmp_dir!(), "svc_#{System.unique_integer([:positive])}.json")
      File.write!(path, Jason.encode!(account))
      on_exit(fn -> File.rm(path) end)
      put_setting(:google_play_service_account_json_path, path)
      assert signs_in(jwk)["iss"] == account["client_email"]
      assert Google.config_status().service_account_configured
    end

    test "a token answer with no token, or a bad key, is refused", %{account: account} do
      put_setting(:google_play_service_account_json, Jason.encode!(account))
      answer(fn :post, _url, _opts -> ok(%{"token_type" => "Bearer"}) end)

      assert Google.validate_purchase(nil, %{"product_id" => "c", "token" => "t"}) ==
               {:error, :google_access_token_missing}

      answer(fn :post, _url, _opts ->
        {:ok, %{status: 401, body: %{"error" => "invalid_grant"}}}
      end)

      assert Google.validate_purchase(nil, %{"product_id" => "c", "token" => "t"}) ==
               {:error, {:google_oauth_error, 401, %{"error" => "invalid_grant"}}}

      put_setting(
        :google_play_service_account_json,
        Jason.encode!(%{account | "private_key" => "not a key"})
      )

      assert Google.validate_purchase(nil, %{"product_id" => "c", "token" => "t"}) ==
               {:error, :invalid_google_service_account_key}

      put_setting(
        :google_play_service_account_json,
        Jason.encode!(Map.delete(account, "client_email"))
      )

      assert {:error, _} = Google.validate_purchase(nil, %{"product_id" => "c", "token" => "t"})
    end

    test "a file that is not there is an error", _ do
      put_setting(:google_play_service_account_json_path, "/nonexistent/svc.json")

      assert Google.validate_purchase(nil, %{"product_id" => "c", "token" => "t"}) ==
               {:error, :enoent}
    end
  end

  describe "the RTDN push" do
    defp push(data \\ %{"version" => "1.0"}) do
      Jason.encode!(%{
        "message" => %{"message_id" => "m1", "data" => Base.encode64(Jason.encode!(data))}
      })
    end

    test "with a shared token configured, only that bearer gets in" do
      put_setting(:google_play_rtdn_token, "rtdn-secret")
      assert {:ok, %{"message_id" => "m1"}} = Google.verify_webhook(push(), "Bearer rtdn-secret")
      assert Google.verify_webhook(push(), "Bearer wrong") == {:error, :invalid_google_rtdn_token}
      assert Google.verify_webhook(push(), nil) == {:error, :invalid_google_rtdn_token}
      assert Google.verify_webhook(push(), "Basic x") == {:error, :invalid_google_rtdn_token}
    end

    test "with none configured, production refuses and elsewhere it is let in" do
      Application.put_env(:gamend_web, :environment, :prod)
      assert Google.verify_webhook(push(), nil) == {:error, :google_rtdn_not_configured}
      assert Google.verify_webhook(push(), "Bearer x") == {:error, :google_rtdn_not_configured}

      Application.put_env(:gamend_web, :environment, :test)
      assert {:ok, _} = Google.verify_webhook(push(), nil)
    end

    test "a push with no message, or no data, says what is missing" do
      Application.put_env(:gamend_web, :environment, :test)
      assert Google.verify_webhook(Jason.encode!(%{}), nil) == {:error, :missing_message}
      assert {:error, _} = Google.verify_webhook(Jason.encode!(%{"message" => %{}}), nil)

      assert Google.verify_webhook(Jason.encode!(%{"message" => %{"data" => "!!"}}), nil) ==
               :error
    end
  end

  test "the admin page is told what is configured" do
    status = Google.config_status()
    assert status.provider == "google"
    assert status.package_name_configured
    refute status.configured
    refute status.rtdn_token_configured

    put_setting(:google_play_access_token, "ya29")
    put_setting(:google_play_rtdn_token, "x")
    put_setting(:google_play_auto_acknowledge, "1")
    status = Google.config_status()
    assert status.configured
    assert status.rtdn_token_configured
    assert status.auto_acknowledge
  end
end
