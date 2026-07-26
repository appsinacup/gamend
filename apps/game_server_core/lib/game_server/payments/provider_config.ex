defmodule GameServer.Payments.ProviderConfig do
  @moduledoc """
  Runtime payment-provider configuration helpers.

  `PAYMENTS_ENVIRONMENT` is the single switch that selects sandbox versus
  production provider credentials for this host.
  """

  @environments ~w(production sandbox)
  @stripe_sdk_api_version "2022-11-15"

  @type environment :: String.t()

  @spec environment() :: environment()
  def environment do
    # An unrecognised value falls back to sandbox rather than production:
    # a typo must never silently take real money.
    GameServer.Payments.Settings
    |> GameServer.Settings.get(:environment)
    |> normalize_environment("sandbox")
  end

  @spec normalize_environment(term()) :: environment()
  def normalize_environment(value, fallback \\ "production")

  def normalize_environment(value, fallback) when is_atom(value) do
    value |> Atom.to_string() |> normalize_environment(fallback)
  end

  def normalize_environment(value, fallback) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      value when value in ["production", "prod", "live", "real"] -> "production"
      value when value in ["sandbox", "test"] -> "sandbox"
      _ -> fallback
    end
  end

  def normalize_environment(_value, fallback), do: fallback

  @spec production?() :: boolean()
  def production?, do: environment() == "production"

  @spec sandbox_like?() :: boolean()
  def sandbox_like?, do: environment() == "sandbox"

  @spec environments() :: [String.t()]
  def environments, do: @environments

  @spec stripe_secret_key() :: String.t() | nil
  def stripe_secret_key, do: stripe_value(:secret_key)

  @spec stripe_webhook_secret() :: String.t() | nil
  def stripe_webhook_secret, do: stripe_value(:webhook_secret)

  @spec stripe_api_version() :: String.t()
  def stripe_api_version do
    case stripe_api_version_source() do
      {_source, value} -> value
      nil -> @stripe_sdk_api_version
    end
  end

  @spec stripe_default_api_version() :: String.t()
  def stripe_default_api_version, do: @stripe_sdk_api_version

  @spec stripe_secret_key_source() :: {String.t(), String.t()} | nil
  def stripe_secret_key_source, do: stripe_source(:secret_key)

  @spec stripe_webhook_secret_source() :: {String.t(), String.t()} | nil
  def stripe_webhook_secret_source, do: stripe_source(:webhook_secret)

  @spec stripe_api_version_source() :: {String.t(), String.t()} | nil
  def stripe_api_version_source do
    cond do
      present_string?(GameServer.Settings.get(GameServer.Payments.Settings, :stripe_api_version)) ->
        {"GAMEND_PAYMENTS_STRIPE_API_VERSION",
         GameServer.Payments.Settings
         |> then(&GameServer.Settings.get(&1, :stripe_api_version))
         |> String.trim()}

      present_string?(Application.get_env(:game_server_core, :stripe_api_version)) ->
        {"app :stripe_api_version",
         String.trim(Application.get_env(:game_server_core, :stripe_api_version))}

      true ->
        nil
    end
  end

  @spec stripe_candidate_labels(:secret_key | :webhook_secret) :: [String.t()]
  def stripe_candidate_labels(kind) do
    kind
    |> stripe_candidates(environment())
    |> Enum.map(fn {label, _app_key} -> label end)
  end

  defp stripe_value(kind) do
    case stripe_source(kind) do
      {_source, value} -> value
      nil -> nil
    end
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp stripe_source(kind) do
    environment = environment()

    kind
    |> stripe_candidates(environment)
    |> Enum.find_value(fn {env_key, app_key} ->
      case GameServer.Settings.get(GameServer.Payments.Settings, app_key) do
        value when is_binary(value) and value != "" ->
          if stripe_value_allowed?(kind, environment, value), do: {env_key, value}

        _ ->
          nil
      end
    end)
  end

  defp stripe_value_allowed?(:secret_key, "production", "sk_live_" <> _rest), do: true
  defp stripe_value_allowed?(:secret_key, "production", "rk_live_" <> _rest), do: true
  defp stripe_value_allowed?(:secret_key, "sandbox", "sk_test_" <> _rest), do: true
  defp stripe_value_allowed?(:secret_key, "sandbox", "rk_test_" <> _rest), do: true
  defp stripe_value_allowed?(:secret_key, _environment, _value), do: false
  defp stripe_value_allowed?(:webhook_secret, _environment, _value), do: true

  defp stripe_candidates(:secret_key, "production") do
    [{"GAMEND_PAYMENTS_STRIPE_PRODUCTION_SECRET_KEY", :stripe_production_secret_key}]
  end

  defp stripe_candidates(:secret_key, "sandbox") do
    [{"GAMEND_PAYMENTS_STRIPE_SANDBOX_SECRET_KEY", :stripe_sandbox_secret_key}]
  end

  defp stripe_candidates(:webhook_secret, "production") do
    [{"GAMEND_PAYMENTS_STRIPE_PRODUCTION_WEBHOOK_SECRET", :stripe_production_webhook_secret}]
  end

  defp stripe_candidates(:webhook_secret, "sandbox") do
    [{"GAMEND_PAYMENTS_STRIPE_SANDBOX_WEBHOOK_SECRET", :stripe_sandbox_webhook_secret}]
  end
end
