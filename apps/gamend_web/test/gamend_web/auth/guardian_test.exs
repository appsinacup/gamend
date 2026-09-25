defmodule GamendWeb.Auth.GuardianTest do
  use GamendWeb.ConnCase

  alias Gamend.AccountsFixtures
  alias GamendWeb.Auth.Guardian

  describe "encode_and_sign/1" do
    test "creates a valid JWT token for a user" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, token, claims} = Guardian.encode_and_sign(user)
      assert is_binary(token)
      assert claims["sub"] == to_string(user.id)
      assert claims["iss"] == "gamend"
    end

    test "fails when user has no id" do
      assert {:error, :no_id_provided} = Guardian.encode_and_sign(%{})
    end
  end

  describe "resource_from_claims/1" do
    test "retrieves user from valid token claims" do
      user = AccountsFixtures.user_fixture()
      {:ok, _token, claims} = Guardian.encode_and_sign(user)

      assert {:ok, retrieved_user} = Guardian.resource_from_claims(claims)
      assert retrieved_user.id == user.id
      assert retrieved_user.email == user.email
    end

    test "returns error for unknown user id" do
      assert {:error, :user_not_found} =
               Guardian.resource_from_claims(%{"sub" => Ecto.UUID.generate()})
    end

    test "returns error for non-UUID user id" do
      assert {:error, :invalid_id} = Guardian.resource_from_claims(%{"sub" => "999999"})
    end

    test "returns error for missing subject" do
      assert {:error, :no_subject} = Guardian.resource_from_claims(%{})
    end

    test "returns error for malformed id" do
      assert {:error, :invalid_id} = Guardian.resource_from_claims(%{"sub" => "not-a-number"})
    end
  end

  describe "decode_and_verify/1" do
    test "decodes a valid token" do
      user = AccountsFixtures.user_fixture()
      {:ok, token, _claims} = Guardian.encode_and_sign(user)

      assert {:ok, claims} = Guardian.decode_and_verify(token)
      assert claims["sub"] == to_string(user.id)
    end

    test "fails for invalid token" do
      assert {:error, _reason} = Guardian.decode_and_verify("invalid.token.here")
    end
  end

  describe "token expiration" do
    test "an access token lasts 15 minutes and a refresh token 30 days by default" do
      user = AccountsFixtures.user_fixture()
      {:ok, _token, access} = Guardian.encode_and_sign(user)
      {:ok, _token, refresh} = Guardian.encode_and_sign(user, %{}, token_type: "refresh")

      assert access["exp"] - access["iat"] == 15 * 60
      assert refresh["exp"] - refresh["iat"] == 30 * 86_400
    end
  end
end
