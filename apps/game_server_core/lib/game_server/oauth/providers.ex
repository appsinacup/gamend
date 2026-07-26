defmodule GameServer.OAuth.Providers do
  @moduledoc """
  Credentials for the social sign-in providers.

  Each provider is opt-in: with nothing set, its buttons simply do not work.
  The id and secret are declared as a pair, so half-configuring one is a
  warning rather than a silent failure at the first login attempt.
  """

  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :oauth,
    label: "OAuth providers"

  for provider <- [:discord, :google, :facebook] do
    id_key = :"#{provider}_client_id"
    secret_key = :"#{provider}_client_secret"

    setting(id_key, :string, required: :warn, with: [secret_key])

    setting(secret_key, :string,
      secret: true,
      required: :warn,
      with: [id_key]
    )
  end

  setting(:google_web_client_id, :string,
    doc: "Native-app client id used to verify Google ID tokens from SDK sign-in."
  )

  # Sign in with Apple needs all four together: the client secret is a JWT this
  # server signs from the .p8 key, so a missing piece means no login at all.
  @apple [:apple_client_id, :apple_team_id, :apple_key_id, :apple_private_key]

  setting(:apple_client_id, :string,
    required: :warn,
    with: @apple,
    doc: "Services id (web audience) for Sign in with Apple."
  )

  setting(:apple_ios_client_id, :string,
    doc: "Bundle id (iOS audience) used when verifying Apple ID tokens."
  )

  setting(:apple_team_id, :string, required: :warn, with: @apple)

  setting(:apple_key_id, :string,
    required: :warn,
    with: @apple,
    doc: "Key id of the Sign in with Apple auth key (Apple Developer -> Keys)."
  )

  setting(:apple_private_key, :string,
    secret: true,
    required: :warn,
    with: @apple,
    doc: "Contents of the Sign in with Apple .p8 key."
  )

  setting(:steam_api_key, :string,
    secret: true,
    doc: "Steam Web API key, used for OpenID sign-in."
  )

  setting(:steam_app_id, :string)
end
