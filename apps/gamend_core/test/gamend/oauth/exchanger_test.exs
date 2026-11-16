defmodule Gamend.OAuth.ExchangerTest do
  use ExUnit.Case, async: false

  alias Gamend.OAuth.Exchanger

  defmodule AppleKeysClient do
    def get("https://appleid.apple.com/auth/keys") do
      jwk = Application.fetch_env!(:gamend_core, :apple_test_jwk)
      {_, public_jwk} = JOSE.JWK.to_public_map(jwk)

      {:ok,
       %{
         status: 200,
         body: %{"keys" => [Map.merge(public_jwk, %{"kid" => "test-key", "alg" => "RS256"})]}
       }}
    end
  end

  # An RSA key takes a while to make, and is only read.
  setup_all do
    %{jwk: JOSE.JWK.generate_key({:rsa, 2048})}
  end

  setup %{jwk: jwk} do
    Application.put_env(:gamend_core, :apple_test_jwk, jwk)
    Application.put_env(:gamend_core, :oauth_exchanger_client, AppleKeysClient)

    on_exit(fn ->
      Application.delete_env(:gamend_core, :apple_test_jwk)
      Application.delete_env(:gamend_core, :oauth_exchanger_client)
    end)

    :ok
  end

  describe "parse_apple_id_token/1" do
    test "verifies a signed token and returns claims", %{jwk: jwk} do
      token =
        apple_token(jwk, %{
          "sub" => "user1",
          "email" => "u@example.com",
          "iss" => "https://appleid.apple.com",
          "aud" => "client-id",
          "exp" => DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix()
        })

      assert {:ok, %{"sub" => "user1", "email" => "u@example.com"}} =
               Exchanger.parse_apple_id_token(token, audience: "client-id")
    end

    test "rejects wrong audience", %{jwk: jwk} do
      token =
        apple_token(jwk, %{
          "sub" => "user1",
          "iss" => "https://appleid.apple.com",
          "aud" => "other-client",
          "exp" => DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix()
        })

      assert {:error, :invalid_audience} =
               Exchanger.parse_apple_id_token(token, audience: "client-id")
    end

    test "rejects expired token", %{jwk: jwk} do
      token =
        apple_token(jwk, %{
          "sub" => "user1",
          "iss" => "https://appleid.apple.com",
          "aud" => "client-id",
          "exp" => DateTime.utc_now() |> DateTime.add(-300, :second) |> DateTime.to_unix()
        })

      assert {:error, :expired} = Exchanger.parse_apple_id_token(token, audience: "client-id")
    end

    test "rejects nonce mismatch", %{jwk: jwk} do
      token =
        apple_token(jwk, %{
          "sub" => "user1",
          "iss" => "https://appleid.apple.com",
          "aud" => "client-id",
          "nonce" => "nonce-a",
          "exp" => DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix()
        })

      assert {:error, :invalid_nonce} =
               Exchanger.parse_apple_id_token(token, audience: "client-id", nonce: "nonce-b")
    end

    test "returns error for malformed token" do
      assert {:error, _} = Exchanger.parse_apple_id_token("not-a.jwt")
    end
  end

  defp apple_token(jwk, claims) do
    jwk
    |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "test-key"}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end
end
