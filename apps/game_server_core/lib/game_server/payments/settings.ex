defmodule GameServer.Payments.Settings do
  @moduledoc """
  Store credentials, per provider.

  `environment` is the global switch between sandbox and real money; each
  provider's keys are selected from it, so a sandbox key in production (or the
  reverse) is a configuration error rather than a silent test transaction.

  These are namespaced away from `GameServer.OAuth.Providers` deliberately:
  Apple issues *different* keys for Sign in with Apple and the App Store Server
  API, from different portals, and the two used to collide on one name.
  """

  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :payments,
    label: "Payments"

  setting(:environment, :atom,
    default: :production,
    doc: "sandbox while validating, production for real transactions."
  )

  # ── Stripe ──────────────────────────────────────────────
  setting(:stripe_api_version, :string, default: "2022-11-15")

  setting(:stripe_sandbox_secret_key, :string,
    secret: true,
    doc: "sk_test_... key, used when environment is sandbox."
  )

  setting(:stripe_sandbox_webhook_secret, :string, secret: true)

  setting(:stripe_production_secret_key, :string,
    secret: true,
    required: :warn,
    when: {[:payments, :environment], :production},
    doc: "sk_live_... key, used when environment is production."
  )

  setting(:stripe_production_webhook_secret, :string, secret: true)

  # ── Google Play ─────────────────────────────────────────
  @play [:google_play_package_name, :google_play_service_account_json]

  setting(:google_play_package_name, :string,
    required: :warn,
    with: @play
  )

  setting(:google_play_service_account_json, :string,
    secret: true,
    required: :warn,
    with: @play,
    doc: "Inline service-account JSON. Use the _PATH variant to read it from a file instead."
  )

  setting(:google_play_service_account_json_path, :string)

  setting(:google_play_access_token, :string, secret: true)

  setting(:google_play_rtdn_token, :string,
    secret: true,
    doc:
      "Shared bearer token on the Pub/Sub push webhook. Without it the RTDN endpoint fails closed in production."
  )

  setting(:google_play_auto_acknowledge, :boolean, default: false)

  # ── Apple App Store Server API ──────────────────────────
  @app_store [:apple_bundle_id, :apple_issuer_id, :apple_key_id]

  setting(:apple_bundle_id, :string,
    required: :warn,
    with: @app_store
  )

  setting(:apple_issuer_id, :string,
    secret: true,
    required: :warn,
    with: @app_store,
    doc: "Issuer id from App Store Connect -> Users and Access -> Integrations."
  )

  setting(:apple_key_id, :string,
    required: :warn,
    with: @app_store,
    doc: "Key id of the App Store Connect API key — not the Sign in with Apple key."
  )

  setting(:apple_private_key, :string,
    secret: true,
    doc: "Inline .p8 contents for the App Store Connect API key."
  )

  setting(:apple_private_key_path, :string)

  # ── Steam MicroTxn ──────────────────────────────────────
  setting(:steam_web_api_key, :string,
    secret: true,
    doc: "Falls back to the OAuth Steam key when unset."
  )

  setting(:steam_app_id, :string)

  # Overridable endpoints, so tests and sandboxes can point at a local stub.
  setting(:apple_app_store_server_base_url, :string)
  setting(:google_play_publisher_base_url, :string)
  setting(:steam_microtxn_base_url, :string)
end
