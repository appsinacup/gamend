defmodule GameServer.Payments.Providers.Apple do
  @moduledoc """
  App Store Server API and StoreKit 2 adapter.

  Accepts either a StoreKit signed transaction JWS from the client or a
  transaction id that can be fetched from App Store Server API.
  """

  alias GameServer.Payments.ProviderConfig

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
    attrs = normalize_params(attrs)

    with {:ok, transaction} <- transaction_payload(attrs),
         :ok <- validate_bundle_id(transaction) do
      {:ok, normalize_transaction(transaction)}
    end
  end

  def verify_notification(raw_body) when is_binary(raw_body) do
    with {:ok, body} <- Jason.decode(raw_body),
         {:ok, signed_payload} <- required_binary(body, "signedPayload"),
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
         {:ok, signed_transaction} <- required_binary(response, "signedTransactionInfo") do
      decode_transaction_jws(signed_transaction)
    end
  end

  defp get_transaction(transaction_id, jwt) do
    url =
      "#{server_base_url()}/transactions/#{URI.encode(transaction_id, &URI.char_unreserved?/1)}"

    case http_client().get(url, auth: {:bearer, jwt}) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, normalize_params(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:apple_server_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_transaction_jws(signed_transaction) do
    with {:ok, transaction} <- jws_verifier().verify_and_decode(signed_transaction) do
      {:ok, normalize_params(transaction)}
    end
  end

  defp decode_notification_data(notification) do
    notification = normalize_params(notification)
    data = notification["data"] || %{}

    with {:ok, transaction_info} <- maybe_decode_jws(data["signedTransactionInfo"]),
         {:ok, renewal_info} <- maybe_decode_jws(data["signedRenewalInfo"]) do
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
      "quantity" => parse_positive_int(transaction["quantity"], 1),
      "environment" => apple_transaction_environment(transaction["environment"]),
      "expires_at" => millis_to_iso8601(transaction["expiresDate"]),
      "raw_payload" => %{"apple_transaction" => transaction}
    }
  end

  defp apple_transaction_status(%{"revocationDate" => nil}), do: "completed"
  defp apple_transaction_status(%{"revocationDate" => _value}), do: "revoked"

  defp apple_transaction_status(_transaction), do: "completed"

  defp apple_transaction_environment("Sandbox"), do: "sandbox"
  defp apple_transaction_environment("Production"), do: "production"
  defp apple_transaction_environment("Xcode"), do: "test"
  defp apple_transaction_environment(_), do: default_environment()

  defp validate_bundle_id(transaction) do
    case bundle_id_value() do
      value when is_binary(value) and value != "" ->
        if transaction["bundleId"] == value do
          :ok
        else
          {:error, :apple_bundle_id_mismatch}
        end

      _ ->
        :ok
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
    _ -> {:error, :invalid_apple_private_key}
  end

  defp private_key do
    cond do
      present?(config_value("APPLE_PRIVATE_KEY", :apple_private_key)) ->
        {:ok, config_value("APPLE_PRIVATE_KEY", :apple_private_key) |> normalize_private_key()}

      present?(config_value("APPLE_PRIVATE_KEY_PATH", :apple_private_key_path)) ->
        config_value("APPLE_PRIVATE_KEY_PATH", :apple_private_key_path)
        |> File.read()
        |> case do
          {:ok, key} -> {:ok, normalize_private_key(key)}
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

  defp required_binary(map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, String.to_atom("missing_#{key}")}
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
    Application.get_env(:game_server_core, :payments_http_client, Req)
  end

  defp jws_verifier do
    Application.get_env(
      :game_server_core,
      :apple_jws_verifier,
      GameServer.Payments.Providers.Apple.JWS
    )
  end

  # The app_key is the declared setting name, so this resolves through
  # GameServer.Settings rather than reading the environment twice over.
  defp config_value(_env_key, app_key) do
    GameServer.Settings.get(GameServer.Payments.Settings, app_key)
  end

  defp default_environment do
    ProviderConfig.environment()
  end

  defp normalize_private_key(value), do: String.replace(value, "\\n", "\n")

  defp millis_to_iso8601(nil), do: nil

  defp millis_to_iso8601(value) do
    with int when is_integer(int) <- parse_int(value),
         {:ok, dt} <- DateTime.from_unix(int, :millisecond) do
      DateTime.to_iso8601(dt)
    else
      _ -> nil
    end
  end

  defp parse_positive_int(value, default) do
    case parse_int(value) do
      int when is_integer(int) and int > 0 -> int
      _ -> default
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil

  defp present?(value), do: is_binary(value) and value != ""

  defp normalize_params(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_map(v) -> {k, normalize_params(v)}
      {k, v} when is_list(v) -> {k, Enum.map(v, &normalize_nested/1)}
      {k, v} -> {k, v}
    end)
  end

  defp normalize_nested(value) when is_map(value), do: normalize_params(value)
  defp normalize_nested(value), do: value
end

defmodule GameServer.Payments.Providers.Apple.JWS do
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

  @root_ca_filename "apple_root_ca_g3.pem"

  def verify_and_decode(compact_jws) when is_binary(compact_jws) do
    with {:ok, header} <- decode_header(compact_jws),
         {:ok, jwk} <- verified_leaf_jwk(header),
         {true, payload, _jws} <- JOSE.JWS.verify_strict(jwk, ["ES256"], compact_jws),
         {:ok, decoded} <- Jason.decode(payload) do
      {:ok, normalize_params(decoded)}
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
      {:ok, normalize_params(header)}
    else
      _ -> {:error, :invalid_apple_jws_header}
    end
  end

  # Trust the leaf public key only after its certificate chain validates back to
  # the pinned Apple root — never trust a key taken from an unverified header.
  defp verified_leaf_jwk(%{"x5c" => [leaf | _] = x5c}) when is_binary(leaf) do
    with {:ok, der_chain} <- decode_x5c(x5c),
         :ok <- validate_chain(der_chain) do
      {:ok, JOSE.JWK.from_pem(leaf_pem(leaf))}
    end
  rescue
    _ -> {:error, :invalid_apple_jws_certificate}
  end

  defp verified_leaf_jwk(_header), do: {:error, :missing_apple_jws_certificate}

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
    path = Path.join([:code.priv_dir(:game_server_core), "certs", @root_ca_filename])

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

  defp normalize_params(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_map(v) -> {k, normalize_params(v)}
      {k, v} when is_list(v) -> {k, Enum.map(v, &normalize_nested/1)}
      {k, v} -> {k, v}
    end)
  end

  defp normalize_nested(value) when is_map(value), do: normalize_params(value)
  defp normalize_nested(value), do: value
end
