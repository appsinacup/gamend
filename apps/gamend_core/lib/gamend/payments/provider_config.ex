defmodule Gamend.Payments.ProviderConfig do
  @moduledoc """
  Runtime payment-provider configuration helpers.

  `PAYMENTS_ENVIRONMENT` is the single switch that selects sandbox versus
  production provider credentials for this host.
  """

  @environments ~w(production sandbox)

  # The one Stripe API version every request names: the version
  # stripity_stripe is generated against (`Stripe.API`'s `@api_version`), so
  # its parameters and Stripe's answers agree. Not a setting: the code reads
  # one shape of each object (a subscription's period on its items, an
  # invoice's payments in `payments`, its subscription under `parent`), and an
  # older version sends another. Bump it with the SDK, read the changelog for
  # the objects `Gamend.Payments.StripeEvents` reads, and move the webhook
  # endpoint to the same version in the Stripe Dashboard. Managed Payments
  # needs 2025-03-31.basil or later.
  @stripe_api_version "2025-11-17.clover"

  @type environment :: String.t()

  @spec environment() :: environment()
  def environment do
    # An unrecognised value falls back to sandbox rather than production:
    # a typo must never silently take real money.
    Gamend.Payments.Settings
    |> Gamend.Settings.get(:environment)
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

  @spec environments() :: [String.t()]
  def environments, do: @environments

  @doc "Whether checkouts go through Stripe Managed Payments (Stripe as merchant of record)."
  @spec stripe_managed_payments?() :: boolean()
  def stripe_managed_payments?,
    do: Gamend.Settings.get(Gamend.Payments.Settings, :stripe_managed_payments) == true

  @spec stripe_secret_key() :: String.t() | nil
  def stripe_secret_key, do: stripe_value(:secret_key)

  @spec stripe_webhook_secret() :: String.t() | nil
  def stripe_webhook_secret, do: stripe_value(:webhook_secret)

  @doc "The Stripe API version every request names, and webhooks are expected in."
  @spec stripe_api_version() :: String.t()
  def stripe_api_version, do: @stripe_api_version

  @doc """
  The release a Stripe API version belongs to (`"clover"` for
  `"2025-11-17.clover"`), or nil for a version older than the named releases.
  Inside one release Stripe only adds; a breaking change starts the next.
  """
  @spec stripe_api_release(String.t() | nil) :: String.t() | nil
  def stripe_api_release(version) when is_binary(version) do
    case String.split(version, ".", parts: 2) do
      [_date, release] when release != "" -> release
      _unnamed -> nil
    end
  end

  def stripe_api_release(_version), do: nil

  @spec stripe_secret_key_source() :: {String.t(), String.t()} | nil
  def stripe_secret_key_source, do: stripe_source(:secret_key)

  @spec stripe_webhook_secret_source() :: {String.t(), String.t()} | nil
  def stripe_webhook_secret_source, do: stripe_source(:webhook_secret)

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

  defp stripe_source(kind) do
    environment = environment()

    kind
    |> stripe_candidates(environment)
    |> Enum.find_value(fn {env_key, app_key} ->
      case Gamend.Settings.get(Gamend.Payments.Settings, app_key) do
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
