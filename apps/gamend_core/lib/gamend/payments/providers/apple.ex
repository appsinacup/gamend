defmodule Gamend.Payments.Providers.Apple do
  @moduledoc """
  App Store Server API and StoreKit 2 adapter.

  Accepts either a StoreKit signed transaction JWS from the client or a
  transaction id that can be fetched from App Store Server API.
  """

  require Logger
  @behaviour Gamend.Payments.Provider

  alias Gamend.Payments.Params
  alias Gamend.Payments.ProviderConfig

  @production_base_url "https://api.storekit.itunes.apple.com/inApps/v1"
  @sandbox_base_url "https://api.storekit-sandbox.itunes.apple.com/inApps/v1"

  def config_status do
    %{
      provider: "apple",
      configured:
        present?(bundle_id_value()) and present?(issuer_id()) and present?(key_id()) and
          private_key_configured?(),
      bundle_id_configured: present?(bundle_id_value()),
      issuer_id_configured: present?(issuer_id()),
      key_id_configured: present?(key_id()),
      private_key_configured: private_key_configured?(),
      environment: apple_environment()
    }
  end

  def validate_purchase(_user, attrs) when is_map(attrs) do
    attrs = Params.normalize(attrs)

    with {:ok, transaction} <- transaction_payload(attrs),
         :ok <- validate_bundle_id(transaction) do
      {:ok, normalize_transaction(transaction)}
    end
  end

  def verify_notification(raw_body) when is_binary(raw_body) do
    with {:ok, body} <- Jason.decode(raw_body),
         {:ok, signed_payload} <- Params.required_binary(body, "signedPayload"),
         {:ok, notification} <- jws_verifier().verify_and_decode(signed_payload) do
      decode_notification_data(notification)
    end
  end

  defp transaction_payload(%{"signed_transaction_info" => signed}) when is_binary(signed) do
    decode_transaction_jws(signed)
  end

  defp transaction_payload(%{"signedTransactionInfo" => signed}) when is_binary(signed) do
    decode_transaction_jws(signed)
  end

  defp transaction_payload(%{"transaction_id" => transaction_id})
       when is_binary(transaction_id) do
    fetch_transaction(transaction_id)
  end

  defp transaction_payload(%{"transactionId" => transaction_id}) when is_binary(transaction_id) do
    fetch_transaction(transaction_id)
  end

  defp transaction_payload(_attrs), do: {:error, :missing_apple_transaction}

  defp fetch_transaction(transaction_id) do
    with {:ok, jwt} <- authorization_jwt(),
         {:ok, response} <- get_transaction(transaction_id, jwt),
         {:ok, signed_transaction} <- Params.required_binary(response, "signedTransactionInfo") do
      decode_transaction_jws(signed_transaction)
    end
  end

  defp get_transaction(transaction_id, jwt) do
    url =
      "#{server_base_url()}/transactions/#{URI.encode(transaction_id, &URI.char_unreserved?/1)}"

    case http_client().get(url, auth: {:bearer, jwt}) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, Params.normalize(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:apple_server_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_transaction_jws(signed_transaction) do
    with {:ok, transaction} <- jws_verifier().verify_and_decode(signed_transaction) do
      {:ok, Params.normalize(transaction)}
    end
  end

  defp decode_notification_data(notification) do
    notification = Params.normalize(notification)
    data = notification["data"] || %{}

    with {:ok, transaction_info} <- maybe_decode_jws(data["signedTransactionInfo"]),
         {:ok, renewal_info} <- maybe_decode_jws(data["signedRenewalInfo"]),
         # The notification envelope carries its own `bundleId`, and it was never
         # checked — only `validate_purchase/2` checked one. A signed
         # notification for a different app could therefore drive a refund or a
         # revocation here.
         :ok <- validate_bundle_id(data) do
      {:ok,
       notification
       |> Map.put("data", data)
       |> Map.put("decoded_transaction_info", transaction_info)
       |> Map.put("decoded_renewal_info", renewal_info)}
    end
  end

  defp maybe_decode_jws(nil), do: {:ok, nil}
  defp maybe_decode_jws(""), do: {:ok, nil}

  defp maybe_decode_jws(signed) when is_binary(signed) do
    jws_verifier().verify_and_decode(signed)
  end

  defp normalize_transaction(transaction) do
    %{
      "product_id" => transaction["productId"],
      "transaction_id" => transaction["transactionId"],
      "original_transaction_id" =>
        transaction["originalTransactionId"] || transaction["transactionId"],
      "status" => apple_transaction_status(transaction),
      "quantity" => Params.parse_positive_int(transaction["quantity"], 1),
      "environment" => apple_transaction_environment(transaction["environment"]),
      "expires_at" => Params.millis_to_iso8601(transaction["expiresDate"]),
      "raw_payload" => %{"apple_transaction" => transaction}
    }
  end

  defp apple_transaction_status(%{"revocationDate" => nil}), do: "completed"
  defp apple_transaction_status(%{"revocationDate" => _value}), do: "revoked"

  defp apple_transaction_status(_transaction), do: "completed"

  defp apple_transaction_environment("Sandbox"), do: "sandbox"
  defp apple_transaction_environment("Production"), do: "production"
  defp apple_transaction_environment("Xcode"), do: "test"
  defp apple_transaction_environment(_), do: ProviderConfig.environment()

  # Fails closed when no bundle id is configured.
  #
  # Product ids are per-app, so without this an Apple-signed transaction from
  # *any* app whose `productId` happens to match a catalog `external_id` was
  # accepted — and registering that same product id in an app of your own is
  # free. The JWS-only deployment shape needs no other Apple credential, so
  # nothing else prompted the operator to set this.
  defp validate_bundle_id(transaction) do
    case bundle_id_value() do
      value when is_binary(value) and value != "" ->
        if transaction["bundleId"] == value do
          :ok
        else
          {:error, :apple_bundle_id_mismatch}
        end

      _ ->
        {:error, :apple_bundle_id_not_configured}
    end
  end

  defp authorization_jwt do
    with {:ok, issuer} <- required_config("APPLE_ISSUER_ID", :apple_issuer_id),
         {:ok, kid} <- required_config("APPLE_KEY_ID", :apple_key_id),
         {:ok, bundle_id} <- required_config("APPLE_BUNDLE_ID", :apple_bundle_id),
         {:ok, private_key} <- private_key() do
      now = System.system_time(:second)

      claims = %{
        "iss" => issuer,
        "iat" => now,
        "exp" => now + 900,
        "aud" => "appstoreconnect-v1",
        "bid" => bundle_id
      }

      jwk = JOSE.JWK.from_pem(private_key)

      {_jws, jwt} =
        jwk
        |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => kid, "typ" => "JWT"}, claims)
        |> JOSE.JWS.compact()

      {:ok, jwt}
    end
  rescue
    e ->
      # A malformed .p8 is a config problem; without this the admin only ever
      # sees the opaque atom.
      Logger.error("Apple payments: could not sign JWT: #{Exception.message(e)}")
      {:error, :invalid_apple_private_key}
  end

  defp private_key do
    cond do
      present?(config_value("APPLE_PRIVATE_KEY", :apple_private_key)) ->
        {:ok,
         config_value("APPLE_PRIVATE_KEY", :apple_private_key) |> Params.normalize_private_key()}

      present?(config_value("APPLE_PRIVATE_KEY_PATH", :apple_private_key_path)) ->
        config_value("APPLE_PRIVATE_KEY_PATH", :apple_private_key_path)
        |> File.read()
        |> case do
          {:ok, key} -> {:ok, Params.normalize_private_key(key)}
          {:error, _reason} -> {:error, :apple_private_key_not_readable}
        end

      true ->
        {:error, :apple_private_key_not_configured}
    end
  end

  defp private_key_configured? do
    present?(config_value("APPLE_PRIVATE_KEY", :apple_private_key)) or
      present?(config_value("APPLE_PRIVATE_KEY_PATH", :apple_private_key_path))
  end

  defp required_config(env_key, app_key) do
    case config_value(env_key, app_key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, String.to_atom("#{String.downcase(env_key)}_not_configured")}
    end
  end

  defp server_base_url do
    config_value("APPLE_APP_STORE_SERVER_BASE_URL", :apple_app_store_server_base_url) ||
      case apple_environment() do
        "sandbox" -> @sandbox_base_url
        _ -> @production_base_url
      end
  end

  defp apple_environment do
    ProviderConfig.environment()
  end

  defp bundle_id_value, do: config_value("APPLE_BUNDLE_ID", :apple_bundle_id)
  defp issuer_id, do: config_value("APPLE_ISSUER_ID", :apple_issuer_id)
  defp key_id, do: config_value("APPLE_KEY_ID", :apple_key_id)

  defp http_client do
    Application.get_env(:gamend_core, :payments_http_client, Gamend.HTTP)
  end

  defp jws_verifier do
    Application.get_env(
      :gamend_core,
      :apple_jws_verifier,
      Gamend.Payments.Providers.Apple.JWS
    )
  end

  # The app_key is the declared setting name, so this resolves through
  # Gamend.Settings rather than reading the environment twice over.
  defp config_value(_env_key, app_key) do
    Gamend.Settings.get(Gamend.Payments.Settings, app_key)
  end

  defp present?(value), do: is_binary(value) and value != ""
end

defmodule Gamend.Payments.Providers.Apple.JWS do
  @moduledoc """
  Verifies App Store JWS payloads (StoreKit signed transactions and App Store
  Server Notifications V2).

  The signing key comes from the leaf certificate in the JWS `x5c` header, but
  only after the full certificate chain is validated against the pinned Apple
  Root CA - G3 trust anchor. A self-signed or otherwise unchained certificate is
  rejected, so a payload cannot be forged by placing an attacker-controlled key
  in the header. If the pinned root is not installed, verification fails closed.

  The pinned root lives at `priv/certs/apple_root_ca_g3.pem` — obtain it from
  https://www.apple.com/certificateauthority/AppleRootCA-G3.cer.
  """

  alias Gamend.Payments.Params

  @root_ca_filename "apple_root_ca_g3.pem"

  def verify_and_decode(compact_jws) when is_binary(compact_jws) do
    with {:ok, header} <- decode_header(compact_jws),
         {:ok, jwk} <- verified_leaf_jwk(header),
         {true, payload, _jws} <- JOSE.JWS.verify_strict(jwk, ["ES256"], compact_jws),
         {:ok, decoded} <- Jason.decode(payload) do
      {:ok, Params.normalize(decoded)}
    else
      {false, _payload, _jws} -> {:error, :invalid_apple_jws_signature}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_apple_jws}
    end
  end

  defp decode_header(compact_jws) do
    with [header_segment, _payload, _signature] <- String.split(compact_jws, ".", parts: 3),
         {:ok, json} <- Base.url_decode64(header_segment, padding: false),
         {:ok, header} <- Jason.decode(json) do
      {:ok, Params.normalize(header)}
    else
      _ -> {:error, :invalid_apple_jws_header}
    end
  end

  # Trust the leaf public key only after its certificate chain validates back to
  # the pinned Apple root — never trust a key taken from an unverified header.
  defp verified_leaf_jwk(%{"x5c" => [leaf | _] = x5c}) when is_binary(leaf) do
    with {:ok, der_chain} <- decode_x5c(x5c),
         :ok <- validate_chain(der_chain),
         :ok <- validate_marker_oids(der_chain) do
      {:ok, JOSE.JWK.from_pem(leaf_pem(leaf))}
    end
  rescue
    _ -> {:error, :invalid_apple_jws_certificate}
  end

  defp verified_leaf_jwk(_header), do: {:error, :missing_apple_jws_certificate}

  # Apple's verification procedure has two halves, and chaining to the root is
  # only the first.
  #
  # Apple issues plenty of other ECC certificates under Apple Root CA - G3 —
  # Apple Pay payment-processing certificates among them — and any of those
  # chains validates here just as well. What distinguishes a *transaction*
  # signing certificate is the marker extension Apple puts on it. Without this
  # check, a developer holding any other ES256 key under that root could sign a
  # JWS carrying whatever `productId`, `bundleId`, `transactionId` and
  # `environment` they liked, and it would be accepted as a genuine purchase or
  # a genuine refund notification.
  @leaf_marker_oid {1, 2, 840, 113_635, 100, 6, 11, 1}
  @intermediate_marker_oid {1, 2, 840, 113_635, 100, 6, 2, 1}

  defp validate_marker_oids([leaf_der, intermediate_der | _]) do
    cond do
      not has_extension?(leaf_der, @leaf_marker_oid) ->
        {:error, {:apple_cert_chain_invalid, :missing_leaf_marker}}

      not has_extension?(intermediate_der, @intermediate_marker_oid) ->
        {:error, {:apple_cert_chain_invalid, :missing_intermediate_marker}}

      true ->
        :ok
    end
  end

  defp validate_marker_oids(_short_chain),
    do: {:error, {:apple_cert_chain_invalid, :chain_too_short}}

  defp has_extension?(der, oid) do
    {:OTPCertificate, tbs, _sig_alg, _sig} = :public_key.pkix_decode_cert(der, :otp)
    {:OTPTBSCertificate, _v, _sn, _alg, _iss, _val, _subj, _spki, _iuid, _suid, extensions} = tbs

    case extensions do
      list when is_list(list) ->
        Enum.any?(list, &match?({:Extension, ^oid, _critical, _value}, &1))

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp decode_x5c(x5c) do
    {:ok, Enum.map(x5c, &Base.decode64!/1)}
  rescue
    _ -> {:error, :invalid_apple_jws_certificate}
  end

  defp validate_chain(der_chain) do
    case apple_root_der() do
      {:ok, root_der} ->
        # pkix_path_validation wants the chain ordered anchor-child-first down to
        # the leaf; x5c is leaf-first and may include the root (which is the anchor).
        chain = der_chain |> Enum.reverse() |> Enum.reject(&(&1 == root_der))

        case :public_key.pkix_path_validation(root_der, chain, []) do
          {:ok, _} -> :ok
          {:error, {:bad_cert, reason}} -> {:error, {:apple_cert_chain_invalid, reason}}
          {:error, reason} -> {:error, {:apple_cert_chain_invalid, reason}}
        end

      {:error, _} = err ->
        err
    end
  end

  defp apple_root_der do
    case :persistent_term.get({__MODULE__, :root_der}, :undefined) do
      :undefined ->
        with {:ok, der} <- load_root_der() do
          :persistent_term.put({__MODULE__, :root_der}, der)
          {:ok, der}
        end

      der ->
        {:ok, der}
    end
  end

  defp load_root_der do
    path = Path.join([:code.priv_dir(:gamend_core), "certs", @root_ca_filename])

    with {:ok, pem} <- File.read(path),
         [{:Certificate, der, :not_encrypted} | _] <- :public_key.pem_decode(pem) do
      {:ok, der}
    else
      _ -> {:error, :apple_root_ca_unavailable}
    end
  end

  defp leaf_pem(leaf) do
    [
      "-----BEGIN CERTIFICATE-----\n",
      leaf |> String.graphemes() |> Enum.chunk_every(64) |> Enum.map_join("\n", &Enum.join/1),
      "\n-----END CERTIFICATE-----\n"
    ]
    |> IO.iodata_to_binary()
  end
end
