defmodule GamendWeb.AdminLive.PaymentProviderStatus do
  @moduledoc """
  What each payment provider reads, for `/admin/payments`: the variable names,
  their values masked where they are secrets, and whether the provider has
  what it needs. The detected Stripe mode and key source are not settings; the
  rest is here so a store is checked in one place.
  """

  import GamendWeb.AdminLive.ServiceDiagnostics, only: [mask_secret: 1]

  alias Gamend.Payments
  alias Gamend.Payments.ProviderConfig
  alias Gamend.Payments.Providers.Apple
  alias Gamend.Payments.Providers.Google
  alias Gamend.Payments.Providers.Steam

  @doc "One `%{name:, configured:, details:}` per provider."
  @spec configs() :: [map()]
  def configs do
    stripe = Payments.stripe_config_status()
    google = Google.config_status()
    apple = Apple.config_status()
    steam = Steam.config_status()

    [
      %{
        name: "Stripe",
        configured: stripe.configured,
        details: [
          "Detected mode: #{stripe.mode}",
          env_line("GAMEND_PAYMENTS_ENVIRONMENT", payments_environment()),
          "Secret key source: #{stripe.selected_secret_key || Enum.join(stripe.expected_secret_keys, " or ")}",
          env_line(
            stripe.selected_secret_key || "GAMEND_PAYMENTS_STRIPE_*_SECRET_KEY",
            ProviderConfig.stripe_secret_key(),
            secret: true
          ),
          "Webhook secret source: #{stripe.selected_webhook_secret || Enum.join(stripe.expected_webhook_secrets, " or ")}",
          env_line(
            stripe.selected_webhook_secret || "GAMEND_PAYMENTS_STRIPE_*_WEBHOOK_SECRET",
            ProviderConfig.stripe_webhook_secret(),
            secret: true
          ),
          "API version: #{stripe.api_version} (pinned; the webhook endpoint must use the same release)"
        ]
      },
      %{
        name: "Google Play",
        configured: google.configured,
        details: [
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_PACKAGE_NAME",
            Gamend.Settings.get(Gamend.Payments.Settings, :google_play_package_name)
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
            Gamend.Settings.get(
              Gamend.Payments.Settings,
              :google_play_service_account_json
            ),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_ACCESS_TOKEN",
            Gamend.Settings.get(Gamend.Payments.Settings, :google_play_access_token),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_RTDN_TOKEN",
            Gamend.Settings.get(Gamend.Payments.Settings, :google_play_rtdn_token),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_AUTO_ACKNOWLEDGE",
            Gamend.Settings.get(Gamend.Payments.Settings, :google_play_auto_acknowledge)
          )
        ]
      },
      %{
        name: "App Store",
        configured: apple.configured,
        details: [
          env_line(
            "GAMEND_PAYMENTS_APPLE_BUNDLE_ID",
            Gamend.Settings.get(Gamend.Payments.Settings, :apple_bundle_id)
          ),
          env_line(
            "GAMEND_PAYMENTS_APPLE_ISSUER_ID",
            Gamend.Settings.get(Gamend.Payments.Settings, :apple_issuer_id),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_APPLE_KEY_ID",
            Gamend.Settings.get(Gamend.Payments.Settings, :apple_key_id)
          ),
          env_line(
            "GAMEND_PAYMENTS_APPLE_PRIVATE_KEY",
            Gamend.Settings.get(Gamend.Payments.Settings, :apple_private_key),
            secret: true
          ),
          env_line("GAMEND_PAYMENTS_ENVIRONMENT", payments_environment())
        ]
      },
      %{
        name: "Steam MicroTxn",
        configured: steam.configured,
        details: [
          env_line(
            "GAMEND_PAYMENTS_STEAM_WEB_API_KEY",
            Gamend.Settings.get(Gamend.Payments.Settings, :steam_web_api_key),
            secret: true
          ),
          env_line(
            "GAMEND_OAUTH_STEAM_API_KEY fallback",
            Gamend.Settings.get(Gamend.OAuth.Providers, :steam_api_key),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_STEAM_APP_ID",
            Gamend.Settings.get(Gamend.Payments.Settings, :steam_app_id)
          ),
          env_line("GAMEND_PAYMENTS_ENVIRONMENT", payments_environment())
        ]
      }
    ]
  end

  defp payments_environment, do: ProviderConfig.environment()

  defp env_line(key, value, opts \\ []) do
    display =
      cond do
        Keyword.get(opts, :secret, false) ->
          mask_secret(value)

        is_nil(value) or value == "" ->
          "<unset>"

        true ->
          to_string(value)
      end

    "#{key}: #{display}"
  end
end
