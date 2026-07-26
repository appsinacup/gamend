defmodule GameServer.Payments.Providers.Steam do
  @moduledoc """
  Steam MicroTxn adapter.

  Supports InitTxn, FinalizeTxn, QueryTxn, and GetReport through Steamworks Web
  API. Use `PAYMENTS_ENVIRONMENT=sandbox` while testing.
  """

  alias GameServer.Payments.ProviderConfig

  @production_base_url "https://partner.steam-api.com/ISteamMicroTxn"
  @sandbox_base_url "https://partner.steam-api.com/ISteamMicroTxnSandbox"

  @reversed_statuses ~w(Refunded PartialRefund Chargedback RefundedSuspectedFraud RefundedFriendlyFraud)

  def config_status do
    %{
      provider: "steam",
      configured: present?(api_key()) and present?(app_id()),
      api_key_configured: present?(api_key()),
      app_id_configured: present?(app_id()),
      environment: steam_environment()
    }
  end

  def init_transaction(purchase, provider_product, attrs) do
    attrs = normalize_params(attrs)

    with {:ok, key} <- required_api_key(),
         {:ok, appid} <- required_app_id(),
         {:ok, steamid} <- required_attr(attrs, "steam_id"),
         {:ok, itemid} <- steam_item_id(provider_product.external_id),
         {:ok, amount} <- required_amount(purchase.amount),
         {:ok, currency} <- required_currency(attrs["currency"] || purchase.currency) do
      form =
        [
          {"key", key},
          {"orderid", purchase.order_id},
          {"steamid", steamid},
          {"appid", appid},
          {"itemcount", "1"},
          {"language", attrs["language"] || "en"},
          {"currency", currency},
          {"usersession", attrs["usersession"] || attrs["user_session"] || "client"},
          {"itemid[0]", to_string(itemid)},
          {"qty[0]", to_string(purchase.quantity)},
          {"amount[0]", to_string(amount)},
          {"description[0]",
           String.slice(provider_product.product.title || provider_product.external_id, 0, 128)}
        ]
        |> maybe_put_form("ipaddress", attrs["ipaddress"] || attrs["ip_address"])
        |> maybe_put_form("category[0]", provider_product.product.kind)

      steam_post("InitTxn/v3", form)
    end
  end

  def finalize_transaction(purchase, _attrs \\ %{}) do
    with {:ok, key} <- required_api_key(),
         {:ok, appid} <- required_app_id(),
         {:ok, body} <-
           steam_post("FinalizeTxn/v2", [
             {"key", key},
             {"orderid", purchase.order_id},
             {"appid", appid}
           ]) do
      {:ok, normalize_finalized_purchase(body, purchase)}
    end
  end

  def validate_purchase(_user, attrs) when is_map(attrs) do
    attrs = normalize_params(attrs)

    with {:ok, body} <- query_transaction(attrs) do
      {:ok, normalize_query_purchase(body)}
    end
  end

  def query_transaction(attrs) when is_map(attrs) do
    attrs = normalize_params(attrs)

    with {:ok, key} <- required_api_key(),
         {:ok, appid} <- required_app_id() do
      params =
        [
          {"key", key},
          {"appid", appid}
        ]
        |> maybe_put_form("orderid", attrs["order_id"] || attrs["orderid"])
        |> maybe_put_form("transid", attrs["transaction_id"] || attrs["transid"])

      if Enum.any?(params, fn {key, _value} -> key in ["orderid", "transid"] end) do
        steam_get("QueryTxn/v3", params)
      else
        {:error, :missing_steam_transaction_reference}
      end
    end
  end

  def get_report(attrs \\ %{}) do
    attrs = normalize_params(attrs)

    with {:ok, key} <- required_api_key(),
         {:ok, appid} <- required_app_id(),
         {:ok, time} <- required_attr(attrs, "time") do
      params =
        [
          {"key", key},
          {"appid", appid},
          {"time", time}
        ]
        |> maybe_put_form("type", attrs["type"])
        |> maybe_put_form("maxresults", attrs["maxresults"] || attrs["max_results"])

      steam_get("GetReport/v5", params)
    end
  end

  defp normalize_finalized_purchase(body, purchase) do
    params = response_params(body)

    %{
      "product_id" => purchase.provider_product.external_id,
      "transaction_id" =>
        params["transid"] || purchase.provider_transaction_id || purchase.order_id,
      "original_transaction_id" => params["orderid"] || purchase.order_id,
      "status" => "completed",
      "environment" => steam_environment(),
      "raw_payload" => %{"steam_finalize" => body}
    }
  end

  defp normalize_query_purchase(body) do
    params = response_params(body)
    item = first_item(params)

    %{
      "product_id" => item["itemid"] |> to_string(),
      "transaction_id" => params["transid"] || params["orderid"],
      "original_transaction_id" => params["orderid"],
      "status" => steam_status(params["status"]),
      "quantity" => item["qty"] || 1,
      "currency" => params["currency"],
      "amount" => item["amount"],
      "environment" => steam_environment(),
      "raw_payload" => %{"steam_query" => body}
    }
  end

  defp first_item(%{"items" => [item | _]}) when is_map(item), do: item
  defp first_item(_params), do: %{}

  defp response_params(%{"response" => %{"params" => params}}) when is_map(params), do: params
  defp response_params(%{"response" => params}) when is_map(params), do: params
  defp response_params(params) when is_map(params), do: params

  defp steam_status("Succeeded"), do: "completed"
  defp steam_status("Approved"), do: "pending"
  defp steam_status("Failed"), do: "failed"
  defp steam_status(status) when status in @reversed_statuses, do: "refunded"
  defp steam_status(_status), do: "pending"

  defp steam_post(path, form) do
    url = "#{base_url()}/#{path}/"

    case http_client().post(url, form: form) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        body = normalize_params(body)

        if steam_ok?(body) do
          {:ok, body}
        else
          {:error, {:steam_error, body}}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:steam_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp steam_get(path, params) do
    url = "#{base_url()}/#{path}/"

    case http_client().get(url, params: params) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        body = normalize_params(body)

        if steam_ok?(body) do
          {:ok, body}
        else
          {:error, {:steam_error, body}}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:steam_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp steam_ok?(%{"response" => %{"result" => "OK"}}), do: true
  defp steam_ok?(%{"response" => %{"result" => "Failure"}}), do: false
  defp steam_ok?(%{"response" => %{"result" => result}}), do: result in [1, "1", true]
  defp steam_ok?(_body), do: true

  defp base_url do
    config_value("STEAM_MICROTXN_BASE_URL", :steam_microtxn_base_url) ||
      case steam_environment() do
        "sandbox" -> @sandbox_base_url
        _ -> @production_base_url
      end
  end

  defp required_api_key do
    case api_key() do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :steam_api_key_not_configured}
    end
  end

  defp required_app_id do
    case app_id() do
      value when is_binary(value) and value != "" -> {:ok, value}
      value when is_integer(value) -> {:ok, to_string(value)}
      _ -> {:error, :steam_app_id_not_configured}
    end
  end

  defp required_attr(attrs, key) do
    case attrs[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      value when is_integer(value) -> {:ok, to_string(value)}
      _ -> {:error, String.to_atom("missing_#{key}")}
    end
  end

  defp required_amount(amount) when is_integer(amount) and amount >= 0, do: {:ok, amount}
  defp required_amount(_amount), do: {:error, :missing_steam_amount}

  defp required_currency(currency) when is_binary(currency) and byte_size(currency) == 3,
    do: {:ok, String.upcase(currency)}

  defp required_currency(_currency), do: {:error, :missing_steam_currency}

  defp steam_item_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp steam_item_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> {:error, :invalid_steam_item_id}
    end
  end

  defp steam_item_id(_value), do: {:error, :invalid_steam_item_id}

  defp maybe_put_form(form, _key, value) when value in [nil, ""], do: form
  defp maybe_put_form(form, key, value), do: List.keystore(form, key, 0, {key, to_string(value)})

  defp api_key do
    config_value("STEAM_WEB_API_KEY", :steam_web_api_key) ||
      GameServer.Settings.get(GameServer.OAuth.Providers, :steam_api_key)
  end

  defp app_id, do: config_value("STEAM_APP_ID", :steam_app_id)

  defp steam_environment do
    ProviderConfig.environment()
  end

  defp http_client do
    Application.get_env(:game_server_core, :payments_http_client, Req)
  end

  # The app_key is the declared setting name, so this resolves through
  # GameServer.Settings rather than reading the environment twice over.
  defp config_value(_env_key, app_key) do
    GameServer.Settings.get(GameServer.Payments.Settings, app_key)
  end

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
