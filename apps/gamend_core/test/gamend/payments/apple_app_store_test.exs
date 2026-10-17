defmodule Gamend.Payments.AppleAppStoreTest do
  @moduledoc """
  The Apple adapter past a StoreKit signed transaction
  (`Payments.Providers.Apple`): a transaction id fetched from the App Store
  Server API under an ES256 JWT signed from the .p8 key (inline or from a
  file), the sandbox or production host by environment, a revoked
  transaction, each environment Apple names, a transaction for another app
  or with no bundle configured refused, the API's errors, a notification
  with its renewal info, and what the admin page is told is configured.
  """
  use ExUnit.Case, async: false

  alias Gamend.Payments.Providers.Apple
  alias Gamend.Payments.Settings

  defmodule ServerAPI do
    def get(url, opts) do
      send(self(), {:apple_get, url, opts})

      Process.get(:apple_api, fn ->
        {:ok, %{status: 200, body: %{"signedTransactionInfo" => "fetched_tx"}}}
      end).()
    end
  end

  # Stands in for the x5c chain check; the payloads are the test's.
  defmodule Verifier do
    def verify_and_decode(signed) do
      case Process.get({:apple_jws, signed}) do
        nil -> {:error, :invalid_apple_jws}
        payload -> {:ok, payload}
      end
    end
  end

  setup do
    settings = Application.get_env(:gamend_core, Settings)
    client = Application.get_env(:gamend_core, :payments_http_client)
    verifier = Application.get_env(:gamend_core, :apple_jws_verifier)

    on_exit(fn ->
      restore(:gamend_core, Settings, settings)
      restore(:gamend_core, :payments_http_client, client)
      restore(:gamend_core, :apple_jws_verifier, verifier)
    end)

    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = JOSE.JWK.to_pem(jwk)

    Application.put_env(:gamend_core, Settings,
      apple_bundle_id: "com.example.game",
      apple_issuer_id: "issuer-1",
      apple_key_id: "KEY123",
      apple_private_key: pem,
      environment: :sandbox
    )

    Application.put_env(:gamend_core, :payments_http_client, ServerAPI)
    Application.put_env(:gamend_core, :apple_jws_verifier, Verifier)
    signs("fetched_tx", transaction())
    %{jwk: jwk, pem: pem}
  end

  defp restore(app, key, nil), do: Application.delete_env(app, key)
  defp restore(app, key, value), do: Application.put_env(app, key, value)

  defp put_setting(key, value) do
    settings = Application.get_env(:gamend_core, Settings, [])
    Application.put_env(:gamend_core, Settings, Keyword.put(settings, key, value))
  end

  defp signs(signed, payload), do: Process.put({:apple_jws, signed}, payload)

  defp transaction(extra \\ %{}) do
    Map.merge(
      %{
        "productId" => "coins",
        "transactionId" => "tx_1",
        "bundleId" => "com.example.game",
        "environment" => "Sandbox"
      },
      extra
    )
  end

  describe "a transaction id" do
    test "is fetched under a JWT signed from the key, from the sandbox", %{jwk: jwk} do
      assert {:ok, result} = Apple.validate_purchase(nil, %{"transaction_id" => "tx 1"})
      assert result["transaction_id"] == "tx_1"
      assert result["original_transaction_id"] == "tx_1"
      assert result["status"] == "completed"
      assert result["quantity"] == 1

      assert_received {:apple_get, url, [auth: {:bearer, jwt}]}
      assert url == "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/tx%201"

      assert {true, %JOSE.JWT{fields: claims}, %JOSE.JWS{fields: header}} =
               JOSE.JWT.verify_strict(jwk, ["ES256"], jwt)

      assert claims["iss"] == "issuer-1"
      assert claims["aud"] == "appstoreconnect-v1"
      assert claims["bid"] == "com.example.game"
      assert claims["exp"] - claims["iat"] == 900
      assert header["kid"] == "KEY123"
    end

    test "is fetched from production in production, or the host configured" do
      put_setting(:environment, :production)
      assert {:ok, _} = Apple.validate_purchase(nil, %{"transactionId" => "tx_1"})

      assert_received {:apple_get,
                       "https://api.storekit.itunes.apple.com/inApps/v1/transactions/tx_1", _}

      put_setting(:apple_app_store_server_base_url, "https://apple.test/v1")
      assert {:ok, _} = Apple.validate_purchase(nil, %{"transactionId" => "tx_1"})
      assert_received {:apple_get, "https://apple.test/v1/transactions/tx_1", _}
    end

    test "with the key in a file, or a file not there", %{pem: pem} do
      path = Path.join(System.tmp_dir!(), "apple_#{System.unique_integer([:positive])}.p8")
      File.write!(path, pem)
      on_exit(fn -> File.rm(path) end)
      put_setting(:apple_private_key, nil)
      put_setting(:apple_private_key_path, path)
      assert {:ok, _} = Apple.validate_purchase(nil, %{"transaction_id" => "tx_1"})

      put_setting(:apple_private_key_path, "/nonexistent/key.p8")

      assert Apple.validate_purchase(nil, %{"transaction_id" => "tx_1"}) ==
               {:error, :apple_private_key_not_readable}
    end

    test "needs every credential, and a key that is a key" do
      put_setting(:apple_private_key, "not a pem")

      assert Apple.validate_purchase(nil, %{"transaction_id" => "tx_1"}) ==
               {:error, :invalid_apple_private_key}

      put_setting(:apple_private_key, nil)

      assert Apple.validate_purchase(nil, %{"transaction_id" => "tx_1"}) ==
               {:error, :apple_private_key_not_configured}

      put_setting(:apple_key_id, "")

      assert Apple.validate_purchase(nil, %{"transaction_id" => "tx_1"}) ==
               {:error, :apple_key_id_not_configured}

      put_setting(:apple_issuer_id, nil)

      assert Apple.validate_purchase(nil, %{"transaction_id" => "tx_1"}) ==
               {:error, :apple_issuer_id_not_configured}
    end

    test "the API's errors are handed back" do
      Process.put(:apple_api, fn -> {:ok, %{status: 404, body: %{"errorCode" => 4_040_010}}} end)

      assert {:error, {:apple_server_error, 404, _}} =
               Apple.validate_purchase(nil, %{"transaction_id" => "x"})

      Process.put(:apple_api, fn -> {:error, :nxdomain} end)
      assert Apple.validate_purchase(nil, %{"transaction_id" => "x"}) == {:error, :nxdomain}

      Process.put(:apple_api, fn -> {:ok, %{status: 200, body: %{}}} end)
      assert {:error, _} = Apple.validate_purchase(nil, %{"transaction_id" => "x"})
    end
  end

  describe "a signed transaction" do
    test "a revoked one is revoked; a quantity and expiry are read" do
      signs("revoked", transaction(%{"revocationDate" => 1_700_000_000_000, "quantity" => 2}))
      assert {:ok, result} = Apple.validate_purchase(nil, %{"signedTransactionInfo" => "revoked"})
      assert result["status"] == "revoked"
      assert result["quantity"] == 2

      signs("live", transaction(%{"revocationDate" => nil}))

      assert {:ok, %{"status" => "completed"}} =
               Apple.validate_purchase(nil, %{"signed_transaction_info" => "live"})
    end

    test "each environment Apple names maps to ours" do
      for {apple, ours} <- [
            {"Production", "production"},
            {"Xcode", "test"},
            {"Sandbox", "sandbox"},
            {nil, "sandbox"}
          ] do
        signs("env", transaction(%{"environment" => apple}))

        assert {:ok, %{"environment" => ^ours}} =
                 Apple.validate_purchase(nil, %{"signedTransactionInfo" => "env"})
      end
    end

    test "one for another app, or with no bundle configured, is refused" do
      signs("other", transaction(%{"bundleId" => "com.someone.else"}))

      assert Apple.validate_purchase(nil, %{"signedTransactionInfo" => "other"}) ==
               {:error, :apple_bundle_id_mismatch}

      put_setting(:apple_bundle_id, "")

      assert Apple.validate_purchase(nil, %{"signedTransactionInfo" => "fetched_tx"}) ==
               {:error, :apple_bundle_id_not_configured}
    end

    test "nothing to validate says so; a signature that does not verify is refused" do
      assert Apple.validate_purchase(nil, %{}) == {:error, :missing_apple_transaction}

      assert Apple.validate_purchase(nil, %{"signedTransactionInfo" => "forged"}) ==
               {:error, :invalid_apple_jws}
    end
  end

  test "a notification carries its decoded renewal info; an empty transaction is none" do
    signs("renewal", %{"autoRenewStatus" => 1})

    signs("note", %{
      "notificationType" => "DID_RENEW",
      "data" => %{
        "bundleId" => "com.example.game",
        "signedTransactionInfo" => "",
        "signedRenewalInfo" => "renewal"
      }
    })

    assert {:ok, note} = Apple.verify_notification(Jason.encode!(%{"signedPayload" => "note"}))
    assert note["decoded_renewal_info"] == %{"autoRenewStatus" => 1}
    assert note["decoded_transaction_info"] == nil

    assert {:error, _} = Apple.verify_notification(Jason.encode!(%{}))
    assert {:error, _} = Apple.verify_notification("not json")
  end

  test "the admin page is told what is configured" do
    assert %{configured: true, environment: "sandbox", private_key_configured: true} =
             Apple.config_status()

    put_setting(:apple_private_key, nil)
    put_setting(:apple_key_id, nil)
    status = Apple.config_status()
    refute status.configured
    refute status.key_id_configured
    assert status.bundle_id_configured
  end
end
