defmodule GameServer.Payments.Providers.Google do
  @moduledoc """
  Google Play Billing adapter.

  Validates one-time purchases and subscriptions through Android Publisher API.
  Real-time developer notifications are decoded here and processed by
  `GameServer.Payments`.
  """

  @androidpublisher_scope "https://www.googleapis.com/auth/androidpublisher"
  @token_url "https://oauth2.googleapis.com/token"
  alias GameServer.Payments.ProviderConfig

  @publisher_base_url "https://androidpublisher.googleapis.com/androidpublisher/v3"

  @active_subscription_states ~w(
    SUBSCRIPTION_STATE_ACTIVE
    SUBSCRIPTION_STATE_IN_GRACE_PERIOD
  )

  def config_status do
    package_name = config_value("GOOGLE_PLAY_PACKAGE_NAME", :google_play_package_name)
    service_json = service_account_json()

    service_path =
      config_value(
        "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH",
        :google_play_service_account_json_path
      )

    access_token = config_value("GOOGLE_PLAY_ACCESS_TOKEN", :google_play_access_token)
    rtdn_token = config_value("GOOGLE_PLAY_RTDN_TOKEN", :google_play_rtdn_token)

    auth_configured =
      present?(access_token) or
        match?({:ok, _}, service_json) or
        present?(service_path)

    %{
      provider: "google",
      configured: present?(package_name) and auth_configured,
      package_name_configured: present?(package_name),
      service_account_configured: auth_configured,
      rtdn_token_configured: present?(rtdn_token),
      auto_acknowledge: auto_acknowledge?()
    }
  end

  def validate_purchase(_user, attrs) when is_map(attrs) do
    attrs = normalize_params(attrs)

    with {:ok, token} <- purchase_token(attrs),
         {:ok, package_name} <- package_name(),
         {:ok, access_token} <- access_token(attrs) do
      if subscription_purchase?(attrs) do
        validate_subscription(package_name, token, access_token)
      else
        with {:ok, product_id} <- product_id(attrs) do
          validate_one_time_product(package_name, product_id, token, access_token)
        end
      end
    end
  end

  def verify_webhook(raw_body, authorization_header) when is_binary(raw_body) do
    with :ok <- verify_rtdn_token(authorization_header),
         {:ok, envelope} <- Jason.decode(raw_body),
         {:ok, message} <- required_map(envelope, "message"),
         {:ok, data} <- required_binary(message, "data"),
         {:ok, decoded} <- Base.decode64(data),
         {:ok, notification} <- Jason.decode(decoded) do
      {:ok,
       notification
       |> normalize_params()
       |> Map.put("message_id", message["messageId"] || message["message_id"])
       |> Map.put("subscription", envelope["subscription"])}
    end
  end

  defp validate_one_time_product(package_name, product_id, token, access_token) do
    encoded_package = URI.encode(package_name, &URI.char_unreserved?/1)
    encoded_product = URI.encode(product_id, &URI.char_unreserved?/1)
    encoded_token = URI.encode(token, &URI.char_unreserved?/1)

    url =
      "#{publisher_base_url()}/applications/#{encoded_package}/purchases/products/#{encoded_product}/tokens/#{encoded_token}"

    with {:ok, body} <- get_json(url, access_token),
         :ok <- maybe_acknowledge_product(package_name, product_id, token, access_token, body) do
      {:ok,
       %{
         "product_id" => body["productId"] || product_id,
         "transaction_id" => body["orderId"] || token,
         "original_transaction_id" => body["purchaseToken"] || token,
         "status" => google_product_status(body["purchaseState"]),
         "quantity" => body["quantity"] || 1,
         "environment" => google_product_environment(body),
         "raw_payload" => %{"google_product_purchase" => body}
       }}
    end
  end

  defp validate_subscription(package_name, token, access_token) do
    encoded_package = URI.encode(package_name, &URI.char_unreserved?/1)
    encoded_token = URI.encode(token, &URI.char_unreserved?/1)

    url =
      "#{publisher_base_url()}/applications/#{encoded_package}/purchases/subscriptionsv2/tokens/#{encoded_token}"

    with {:ok, body} <- get_json(url, access_token),
         {:ok, line_item} <- first_line_item(body) do
      {:ok,
       %{
         "product_id" => line_item["productId"],
         "transaction_id" =>
           line_item["latestSuccessfulOrderId"] || body["latestOrderId"] || token,
         "original_transaction_id" => body["linkedPurchaseToken"] || token,
         "status" => google_subscription_status(body["subscriptionState"]),
         "quantity" => 1,
         "currency" => recurring_currency(line_item),
         "amount" => recurring_amount(line_item),
         "environment" => google_subscription_environment(body),
         "expires_at" => line_item["expiryTime"],
         "raw_payload" => %{"google_subscription_purchase" => body}
       }}
    end
  end

  defp maybe_acknowledge_product(package_name, product_id, token, access_token, body) do
    if auto_acknowledge?() and body["acknowledgementState"] == 0 do
      encoded_package = URI.encode(package_name, &URI.char_unreserved?/1)
      encoded_product = URI.encode(product_id, &URI.char_unreserved?/1)
      encoded_token = URI.encode(token, &URI.char_unreserved?/1)

      url =
        "#{publisher_base_url()}/applications/#{encoded_package}/purchases/products/#{encoded_product}/tokens/#{encoded_token}:acknowledge"

      case post_json(url, access_token, %{}) do
        {:ok, _body} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp google_product_status(0), do: "completed"
  defp google_product_status(1), do: "cancelled"
  defp google_product_status(2), do: "pending"
  defp google_product_status(_state), do: "pending"

  defp google_subscription_status(state) when state in @active_subscription_states,
    do: "completed"

  defp google_subscription_status("SUBSCRIPTION_STATE_CANCELED"), do: "cancelled"
  defp google_subscription_status("SUBSCRIPTION_STATE_EXPIRED"), do: "revoked"
  defp google_subscription_status("SUBSCRIPTION_STATE_ON_HOLD"), do: "pending"
  defp google_subscription_status(_state), do: "pending"

  defp google_product_environment(%{"purchaseType" => 0}), do: "test"
  defp google_product_environment(_body), do: default_environment()

  defp google_subscription_environment(%{"testPurchase" => nil}), do: default_environment()
  defp google_subscription_environment(%{"testPurchase" => _value}), do: "test"

  defp google_subscription_environment(_body), do: default_environment()

  defp first_line_item(%{"lineItems" => [line_item | _]}) when is_map(line_item),
    do: {:ok, line_item}

  defp first_line_item(_body), do: {:error, :missing_google_subscription_line_item}

  defp recurring_currency(%{
         "autoRenewingPlan" => %{"recurringPrice" => %{"currencyCode" => currency}}
       }),
       do: currency

  defp recurring_currency(_line_item), do: nil

  defp recurring_amount(%{"autoRenewingPlan" => %{"recurringPrice" => price}}) do
    units = price["units"] |> parse_int(0)
    nanos = price["nanos"] |> parse_int(0)
    units * 100 + div(nanos, 10_000_000)
  end

  defp recurring_amount(_line_item), do: nil

  defp subscription_purchase?(attrs) do
    attrs["purchase_type"] in ["subscription", "subs"] or
      attrs["type"] in ["subscription", "subs"] or
      attrs["subscription"] == true or
      (is_nil(attrs["product_id"]) and is_nil(attrs["productId"]) and is_nil(attrs["sku"]))
  end

  defp purchase_token(attrs) do
    case attrs["purchase_token"] || attrs["purchaseToken"] || attrs["token"] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_purchase_token}
    end
  end

  defp product_id(attrs) do
    case attrs["product_id"] || attrs["productId"] || attrs["sku"] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_product_id}
    end
  end

  defp package_name do
    case config_value("GOOGLE_PLAY_PACKAGE_NAME", :google_play_package_name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :google_play_package_name_not_configured}
    end
  end

  defp access_token(%{"access_token" => token}) when is_binary(token) and token != "",
    do: {:ok, token}

  defp access_token(_attrs) do
    case config_value("GOOGLE_PLAY_ACCESS_TOKEN", :google_play_access_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> service_account_access_token()
    end
  end

  defp service_account_access_token do
    with {:ok, account} <- service_account_json(),
         {:ok, assertion} <- service_account_assertion(account),
         {:ok, body} <-
           post_form(account["token_uri"] || @token_url, [
             {"grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"},
             {"assertion", assertion}
           ]),
         token when is_binary(token) <- body["access_token"] do
      {:ok, token}
    else
      nil -> {:error, :google_access_token_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp service_account_assertion(account) do
    with {:ok, client_email} <- required_binary(account, "client_email"),
         {:ok, private_key} <- required_binary(account, "private_key") do
      token_url = account["token_uri"] || @token_url
      now = System.system_time(:second)

      claims = %{
        "iss" => client_email,
        "scope" => @androidpublisher_scope,
        "aud" => token_url,
        "iat" => now,
        "exp" => now + 3600
      }

      jwk = JOSE.JWK.from_pem(normalize_private_key(private_key))

      {_jws, assertion} =
        jwk
        |> JOSE.JWT.sign(%{"alg" => "RS256", "typ" => "JWT"}, claims)
        |> JOSE.JWS.compact()

      {:ok, assertion}
    end
  rescue
    _ -> {:error, :invalid_google_service_account_key}
  end

  defp service_account_json do
    cond do
      present?(
        config_value("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", :google_play_service_account_json)
      ) ->
        config_value("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", :google_play_service_account_json)
        |> Jason.decode()

      present?(
        config_value(
          "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH",
          :google_play_service_account_json_path
        )
      ) ->
        path =
          config_value(
            "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH",
            :google_play_service_account_json_path
          )

        with {:ok, contents} <- File.read(path) do
          Jason.decode(contents)
        end

      true ->
        {:error, :google_service_account_not_configured}
    end
  end

  defp verify_rtdn_token(nil) do
    case configured_rtdn_token() do
      value when is_binary(value) and value != "" -> {:error, :invalid_google_rtdn_token}
      _ -> unconfigured_rtdn_result()
    end
  end

  defp verify_rtdn_token("Bearer " <> token) do
    case configured_rtdn_token() do
      value when is_binary(value) and value != "" ->
        if Plug.Crypto.secure_compare(token, value),
          do: :ok,
          else: {:error, :invalid_google_rtdn_token}

      _ ->
        unconfigured_rtdn_result()
    end
  end

  defp verify_rtdn_token(_header), do: {:error, :invalid_google_rtdn_token}

  defp configured_rtdn_token do
    config_value("GOOGLE_PLAY_RTDN_TOKEN", :google_play_rtdn_token)
  end

  # Fail closed in production when no shared token is configured — an unset token
  # would otherwise leave the RTDN webhook unauthenticated. Dev/test stay lenient.
  defp unconfigured_rtdn_result do
    if Application.get_env(:game_server_web, :environment) == :prod do
      {:error, :google_rtdn_not_configured}
    else
      :ok
    end
  end

  defp get_json(url, access_token) do
    case http_client().get(url, auth: {:bearer, access_token}) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, normalize_params(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:google_play_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp post_json(url, access_token, body) do
    case http_client().post(url, auth: {:bearer, access_token}, json: body) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, if(is_map(body), do: normalize_params(body), else: %{})}

      {:ok, %{status: status, body: body}} ->
        {:error, {:google_play_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp post_form(url, form) do
    case http_client().post(url, form: form) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, normalize_params(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:google_oauth_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp required_map(map, key) do
    case map[key] do
      value when is_map(value) -> {:ok, normalize_params(value)}
      _ -> {:error, String.to_atom("missing_#{key}")}
    end
  end

  defp required_binary(map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, String.to_atom("missing_#{key}")}
    end
  end

  defp auto_acknowledge? do
    value = config_value("GOOGLE_PLAY_AUTO_ACKNOWLEDGE", :google_play_auto_acknowledge)
    value in [true, "true", "1", "yes"]
  end

  defp publisher_base_url do
    config_value("GOOGLE_PLAY_PUBLISHER_BASE_URL", :google_play_publisher_base_url) ||
      @publisher_base_url
  end

  defp http_client do
    Application.get_env(:game_server_core, :payments_http_client, Req)
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

  defp present?(value), do: is_binary(value) and value != ""

  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp parse_int(_value, default), do: default

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
