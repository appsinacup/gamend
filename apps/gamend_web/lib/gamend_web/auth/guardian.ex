defmodule GamendWeb.Auth.Guardian do
  @moduledoc """
  Guardian implementation for JWT-based authentication.

  This module handles encoding and decoding JWT tokens for API authentication.
  It works alongside the existing session-based authentication for browser flows.
  """

  # Token lifetimes follow the `auth.*_token_ttl_*` settings, in every
  # environment. An option here wins over the app config, so a host cannot
  # shadow the settings with a literal `ttl` or `token_ttl`.
  use Guardian, otp_app: :gamend_web, token_ttl: {GamendWeb.Auth.Tokens, :ttls, []}

  alias Gamend.Accounts

  @doc """
  Encodes the user ID into the JWT token as the subject.
  """
  def subject_for_token(%{id: id}, _claims) do
    {:ok, to_string(id)}
  end

  def subject_for_token(_, _) do
    {:error, :no_id_provided}
  end

  @doc """
  Embeds the user's `token_version` as the `"tv"` claim.

  Bumping `users.token_version` (password change, email change,
  `Accounts.revoke_all_tokens/1`) therefore invalidates every previously
  issued access and refresh token.
  """
  def build_claims(claims, %{token_version: version}, _opts) when is_integer(version) do
    {:ok, Map.put(claims, "tv", version)}
  end

  @doc """
  Retrieves the user from the database using the subject (user ID) from the
  token, rejecting tokens issued before the user's last credential revocation.

  Tokens without a `"tv"` claim are always rejected.
  """
  def resource_from_claims(%{"sub" => id} = claims) do
    case Ecto.UUID.cast(id) do
      {:ok, user_id} ->
        case Accounts.get_user(user_id) do
          %{} = user ->
            cond do
              Map.get(claims, "tv") != user.token_version ->
                {:error, :token_revoked}

              # Deactivating an account has to end its API access too, not only
              # block new logins — otherwise an admin who un-approves someone
              # leaves them refreshing tokens for the whole refresh TTL.
              not Accounts.user_activated?(user) ->
                {:error, :account_deactivated}

              true ->
                {:ok, user}
            end

          nil ->
            {:error, :user_not_found}
        end

      _ ->
        {:error, :invalid_id}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :no_subject}
  end
end
