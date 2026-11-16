defmodule Gamend.Payments.Providers.Apple.JWSTest do
  @moduledoc """
  Regression coverage for the App Store JWS forgery fix: a payload whose `x5c`
  leaf does not chain to the pinned Apple Root CA - G3 must be rejected, even
  when the JWS signature matches that attacker-controlled leaf.
  """
  use ExUnit.Case, async: true

  alias Gamend.Payments.Providers.Apple.JWS

  # A self-signed P-256 cert + its private key (CN=attacker). Not issued by
  # Apple, so it must never be trusted no matter how the JWS is signed.
  @forged_key_pem """
  -----BEGIN EC PRIVATE KEY-----
  MHcCAQEEIL1za0ClBwmtUkQP0yaReeyfFbTkHZXyrB4UxHKH4igpoAoGCCqGSM49
  AwEHoUQDQgAEXcvuMjIv2emYJFsID/lw2AaFkgnxObmmrp5Z7OwYN8GgR1Entg36
  BtzAXzvOdEEb4pI6ORjD073c5nBBeYG3gg==
  -----END EC PRIVATE KEY-----
  """

  @forged_cert_b64 "MIIBfDCCASGgAwIBAgIUdHbS0djVmMh9N1lRzHCe7UFjxKswCgYIKoZIzj0EAwIwEzERMA8GA1UEAwwIYXR0YWNrZXIwHhcNMjYwNzE2MTIwMTU2WhcNMzYwNzEzMTIwMTU2WjATMREwDwYDVQQDDAhhdHRhY2tlcjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABF3L7jIyL9npmCRbCA/5cNgGhZIJ8Tm5pq6eWezsGDfBoEdRJ7YN+gbcwF87znRBG+KSOjkYw9O93OZwQXmBt4KjUzBRMB0GA1UdDgQWBBQSLqHtmmf5y+vJNS6OFsCqB4/rfDAfBgNVHSMEGDAWgBQSLqHtmmf5y+vJNS6OFsCqB4/rfDAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0kAMEYCIQC4p/T7N8H0vseLRH5sAT8f+I++KPyuclfZ9WoMQKqE5gIhANJ37uj74opAzXQpnTr2PfIQR1pwYUcJzRcvBAPevJ9r"

  defp forged_jws do
    jwk = JOSE.JWK.from_pem(@forged_key_pem)

    payload =
      Jason.encode!(%{
        "bundleId" => "com.example.app",
        "productId" => "coins_100",
        "transactionId" => "tx_forged_123"
      })

    {_modules, compact} =
      jwk
      |> JOSE.JWS.sign(payload, %{"alg" => "ES256", "x5c" => [@forged_cert_b64]})
      |> JOSE.JWS.compact()

    compact
  end

  test "rejects a validly-signed JWS whose x5c does not chain to the Apple root" do
    assert {:error, {:apple_cert_chain_invalid, _reason}} = JWS.verify_and_decode(forged_jws())
  end

  test "rejects a JWS with no x5c certificate" do
    jwk = JOSE.JWK.from_pem(@forged_key_pem)

    {_modules, compact} =
      jwk
      |> JOSE.JWS.sign(Jason.encode!(%{"transactionId" => "x"}), %{"alg" => "ES256"})
      |> JOSE.JWS.compact()

    assert {:error, :missing_apple_jws_certificate} = JWS.verify_and_decode(compact)
  end
end
