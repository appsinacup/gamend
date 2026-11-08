defmodule GamendWeb.Api.V1.ProviderController do
  @moduledoc """
  The signed-in player's ways to sign in: linking and unlinking providers and
  the device id. Signing in through a provider is `GamendWeb.AuthController`;
  what the two share is `GamendWeb.Auth.OAuthExchange`.

  Every change here answers the whole current user, whose
  `linked_providers` is what changed.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.OAuth.Providers
  alias Gamend.OAuthSessions
  alias GamendWeb.Auth.OAuthExchange
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    CurrentUserResponse,
    OAuthAuthorizationResponse,
    ProviderLinkStatusResponse
  }

  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  require Gamend.OAuth.AuthProvider, as: AuthProvider

  @session_id "session_id"

  tags(["Authentication"])

  @provider_param [
    in: :path,
    name: "provider",
    schema: %Schema{
      type: :string,
      enum: ["discord", "apple", "google", "facebook", "github", "steam"]
    },
    required: true
  ]

  operation(:link,
    operation_id: "link_provider",
    summary: "Link a provider with a code",
    description:
      "Links a provider to the signed-in account: an authorization code, or for Steam " <>
        "a session ticket from `ISteamUser::GetAuthTicketForWebApi`. Signing in with one " <>
        "is `POST /api/v1/auth/{provider}/callback`.",
    security: [%{"authorization" => []}],
    parameters: [provider: @provider_param],
    request_body:
      {"Provider code", "application/json",
       %Schema{
         type: :object,
         required: [:code],
         properties: %{
           code: %Schema{
             type: :string,
             description: "Authorization code; for Steam, a Steam auth ticket (hex)"
           }
         }
       }},
    responses: [
      ok: {"Linked", "application/json", CurrentUserResponse},
      bad_request: Schemas.error("Missing code, or the provider refused it"),
      unauthorized: Schemas.error("Not authenticated"),
      not_found: Schemas.error("Unknown or disabled provider"),
      conflict: Schemas.error("Linked to another account"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def link(conn, %{"provider" => provider} = params) do
    with :ok <- enabled(provider),
         {:ok, user_params} <- OAuthExchange.code_params(provider, params["code"]) do
      link_with(conn, provider, user_params)
    else
      {:error, :unknown_provider} -> unknown_provider(conn)
      {:error, reason} -> OAuthExchange.reply_refused(conn, reason)
    end
  end

  operation(:link_google_id_token,
    operation_id: "link_google_id_token",
    summary: "Link Google with an ID token",
    description:
      "Links Google to the signed-in account from a Google OpenID Connect `id_token` " <>
        "(Android Credential Manager, One Tap). Signing in with one is " <>
        "`POST /api/v1/auth/google/id_token`.",
    security: [%{"authorization" => []}],
    request_body:
      {"Google ID token", "application/json",
       %Schema{
         type: :object,
         required: [:id_token],
         properties: %{id_token: %Schema{type: :string, description: "Google id_token JWT"}}
       }},
    responses: [
      ok: {"Linked", "application/json", CurrentUserResponse},
      bad_request: Schemas.error("Missing or invalid token"),
      unauthorized: Schemas.error("Not authenticated"),
      not_found: Schemas.error("Google sign-in disabled"),
      conflict: Schemas.error("Linked to another account"),
      unprocessable_entity: Schemas.error("Validation failed"),
      service_unavailable: Schemas.error("Google sign-in not configured")
    ]
  )

  def link_google_id_token(conn, params) do
    with :ok <- enabled(AuthProvider.google()),
         {:ok, user_params} <- OAuthExchange.google_params(params["id_token"]) do
      link_with(conn, AuthProvider.google(), user_params)
    else
      {:error, :unknown_provider} -> unknown_provider(conn)
      {:error, reason} -> OAuthExchange.reply_refused(conn, reason)
    end
  end

  operation(:link_apple_ios,
    operation_id: "link_apple_ios",
    summary: "Link Apple (native iOS)",
    description:
      "Links Apple to the signed-in account from a native Sign in with Apple code. " <>
        "Signing in with one is `POST /api/v1/auth/apple/ios/callback`.",
    security: [%{"authorization" => []}],
    request_body:
      {"Apple authorization code", "application/json",
       %Schema{
         type: :object,
         required: [:code],
         properties: %{
           code: %Schema{type: :string, description: "Apple authorization code"},
           given_name: %Schema{type: :string, description: "Ignored: a legal name is not kept"},
           family_name: %Schema{type: :string, description: "Ignored, as `given_name`"}
         }
       }},
    responses: [
      ok: {"Linked", "application/json", CurrentUserResponse},
      bad_request: Schemas.error("Missing code, or Apple refused it"),
      unauthorized: Schemas.error("Not authenticated"),
      not_found: Schemas.error("Apple sign-in disabled"),
      conflict: Schemas.error("Linked to another account"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def link_apple_ios(conn, params) do
    with :ok <- enabled(AuthProvider.apple()),
         {:ok, user_params} <- OAuthExchange.apple_ios_params(params["code"]) do
      link_with(conn, AuthProvider.apple(), user_params)
    else
      {:error, :unknown_provider} -> unknown_provider(conn)
      {:error, reason} -> OAuthExchange.reply_refused(conn, reason)
    end
  end

  operation(:authorize,
    operation_id: "link_provider_request",
    summary: "Start linking a provider",
    description:
      "Answers the provider page to open and a session to poll with " <>
        "`GET /api/v1/me/providers/sessions/{session_id}` until the player finishes " <>
        "there. Signing in that way is `GET /api/v1/auth/{provider}`.",
    security: [%{"authorization" => []}],
    parameters: [provider: @provider_param],
    responses: [
      ok: {"Provider page and session", "application/json", OAuthAuthorizationResponse},
      unauthorized: Schemas.error("Not authenticated"),
      not_found: Schemas.error("Unknown or disabled provider")
    ]
  )

  def authorize(conn, %{"provider" => provider}) do
    case enabled(provider) do
      :ok ->
        user = Scope.user(conn.assigns.current_scope)
        reply_data(conn, OAuthExchange.start_session(provider, %{link_user_id: user.id}))

      {:error, :unknown_provider} ->
        unknown_provider(conn)
    end
  end

  operation(:link_session_status,
    operation_id: "link_session_status",
    summary: "Poll a provider link",
    description:
      "The state of a link started with `POST /api/v1/me/providers/{provider}/authorize`. " <>
        "Once `completed`, `GET /api/v1/me` (or the `user_updated` event) carries the new " <>
        "`linked_providers`.",
    security: [%{"authorization" => []}],
    parameters: [
      session_id: [in: :path, name: @session_id, schema: %Schema{type: :string}, required: true]
    ],
    responses: [
      ok: {"Link status", "application/json", ProviderLinkStatusResponse},
      unauthorized: Schemas.error("Not authenticated"),
      not_found: Schemas.error("No such link for this account")
    ]
  )

  def link_session_status(conn, %{"session_id" => session_id}) do
    user = Scope.user(conn.assigns.current_scope)

    case OAuthSessions.get_session(session_id) do
      %Gamend.OAuthSession{data: %{"link_user_id" => owner} = data} = session
      when owner == user.id ->
        reply_data(conn, %{
          status: session.status,
          error: Map.get(data, "error", ""),
          message: Map.get(data, "message", ""),
          provider: session.provider || ""
        })

      _ ->
        reply_error(conn, :not_found, "session_not_found", "No such link for this account")
    end
  end

  operation(:link_device,
    operation_id: "link_device",
    summary: "Link device ID",
    description: "Links a device_id to the current authenticated user's account.",
    security: [%{"authorization" => []}],
    request_body:
      {"Device ID", "application/json",
       %Schema{
         type: :object,
         properties: %{device_id: %Schema{type: :string}},
         required: [:device_id]
       }},
    responses: [
      ok: {"Linked", "application/json", CurrentUserResponse},
      bad_request: Schemas.error("Bad request"),
      unauthorized: Schemas.error("Unauthorized"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def link_device(conn, %{"device_id" => device_id}) when is_binary(device_id) do
    user = Scope.user(conn.assigns.current_scope)

    case Accounts.link_device_id(user, device_id) do
      {:ok, user} ->
        reply_data(conn, Serializers.serialize_current_user(user))

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)
    end
  end

  def link_device(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "device_id is required")
  end

  operation(:unlink_device,
    operation_id: "unlink_device",
    summary: "Unlink device ID",
    description:
      "Unlinks the device_id from the current authenticated user. Requires at least one OAuth provider or password to remain.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Unlinked", "application/json", CurrentUserResponse},
      bad_request: Schemas.error("Bad request"),
      unauthorized: Schemas.error("Unauthorized"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def unlink_device(conn, _params) do
    user = Scope.user(conn.assigns.current_scope)

    case Accounts.unlink_device_id(user) do
      {:ok, user} ->
        reply_data(conn, Serializers.serialize_current_user(user))

      {:error, :last_auth_method} ->
        reply_error(
          conn,
          :bad_request,
          "last_auth_method",
          "Cannot unlink the last way to sign in"
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)
    end
  end

  operation(:unlink,
    operation_id: "unlink_provider",
    summary: "Unlink OAuth provider",
    description: "Unlinks a provider from the current authenticated user.",
    security: [%{"authorization" => []}],
    parameters: [provider: @provider_param],
    responses: [
      ok: {"Unlinked", "application/json", CurrentUserResponse},
      bad_request: Schemas.error("Bad request"),
      unauthorized: Schemas.error("Unauthorized"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def unlink(conn, %{"provider" => provider}) do
    user = Scope.user(conn.assigns.current_scope)

    case provider_atom(provider) do
      nil ->
        reply_error(conn, :bad_request, "unknown_provider")

      atom ->
        case Accounts.unlink_provider(user, atom) do
          {:ok, user} ->
            reply_data(conn, Serializers.serialize_current_user(user))

          {:error, :last_provider} ->
            reply_error(
              conn,
              :bad_request,
              "last_auth_method",
              "Cannot unlink the last way to sign in"
            )

          {:error, %Ecto.Changeset{} = changeset} ->
            unprocessable(conn, changeset)
        end
    end
  end

  defp link_with(conn, provider, user_params) do
    user = Scope.user(conn.assigns.current_scope)
    config = OAuthExchange.provider!(provider)

    case Accounts.link_account(user, user_params, config.id_field, config.changeset) do
      {:ok, user} ->
        reply_data(conn, Serializers.serialize_current_user(user))

      {:error, {:conflict, _other_user}} ->
        reply_error(
          conn,
          :conflict,
          "provider_already_linked",
          "This provider is already linked to another account"
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)
    end
  end

  # As on the sign-in side, a provider that is switched off does not exist.
  defp enabled(provider) do
    case provider_atom(provider) do
      nil -> {:error, :unknown_provider}
      atom -> if Providers.enabled?(atom), do: :ok, else: {:error, :unknown_provider}
    end
  end

  defp unknown_provider(conn) do
    reply_error(conn, :not_found, "unknown_provider", "Unknown or disabled provider")
  end

  defp provider_atom(provider) do
    if provider in OAuthExchange.providers(), do: String.to_existing_atom(provider)
  end
end
