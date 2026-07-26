defmodule GameServerWeb.Api.V1.MeController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Accounts.Scope
  alias GameServer.Accounts.User
  alias GameServerWeb.Uploads
  alias OpenApiSpex.Schema

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @validation_error_schema %Schema{
    type: :object,
    properties: %{error: %Schema{type: :string}, errors: %Schema{type: :object}}
  }

  tags(["Users"])

  operation(:show,
    operation_id: "get_current_user",
    summary: "Return current user info",
    description: "Returns the current authenticated user's basic information.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {
        "User info",
        "application/json",
        %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            email: %Schema{type: :string},
            profile_url: %Schema{type: :string},
            username: %Schema{type: :string},
            display_name: %Schema{type: :string},
            metadata: %Schema{type: :object},
            lobby_id: %Schema{
              type: :string,
              format: :uuid,
              nullable: false,
              description:
                "Lobby ID when user is currently in a lobby. -1 means not currently in a lobby."
            },
            party_id: %Schema{
              type: :string,
              format: :uuid,
              nullable: false,
              description:
                "Party ID when user is currently in a party. -1 means not currently in a party."
            },
            is_online: %Schema{type: :boolean},
            last_seen_at: %Schema{type: :string, format: :date_time, nullable: false},
            linked_providers: %Schema{
              type: :object,
              description: "Shows which OAuth providers are linked to this account",
              properties: %{
                google: %Schema{type: :boolean},
                facebook: %Schema{type: :boolean},
                discord: %Schema{type: :boolean},
                apple: %Schema{type: :boolean},
                steam: %Schema{type: :boolean},
                device: %Schema{type: :boolean}
              }
            },
            has_password: %Schema{
              type: :boolean,
              description: "Whether the user has a password set"
            }
          }
        }
      },
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def show(conn, _params) do
    # Guardian pipeline has already authenticated and loaded the user
    # into current_scope via AssignCurrentScope plug
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        json(conn, %{
          id: user.id,
          email: user.email || "",
          profile_url: user.profile_url || "",
          metadata: user.metadata || %{},
          username: user.username || "",
          display_name: user.display_name || "",
          lobby_id: user.lobby_id || "",
          party_id: user.party_id || "",
          is_online: user.is_online || false,
          last_seen_at: User.last_seen_at_or_fallback(user),
          linked_providers: GameServer.Accounts.get_linked_providers(user),
          has_password: GameServer.Accounts.has_password?(user)
        })

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})
    end
  end

  operation(:update_password,
    operation_id: "update_current_user_password",
    summary: "Update current user password",
    request_body: {
      "New password payload",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          password: %Schema{type: :string},
          current_password: %Schema{
            type: :string,
            description: "Required when the account already has a password."
          }
        },
        required: [:password]
      }
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Password updated", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid data", "application/json", @validation_error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def update_password(conn, %{"password" => _} = params) do
    user = Scope.user(conn.assigns.current_scope)

    if password_change_authorized?(user, params) do
      case GameServer.Accounts.update_user_password(user, params) do
        {:ok, {user, _tokens}} ->
          json(conn, %{ok: true, id: user.id})

        {:error, changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{
            error: "invalid_data",
            errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          })
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        error: "invalid_current_password",
        message: "current_password is required and must match your existing password"
      })
    end
  end

  # Accounts with an existing password must prove it to change it (a stolen
  # access token must not be escalatable into a permanent password reset).
  # OAuth/device accounts with no password yet may set one without re-auth.
  defp password_change_authorized?(user, params) do
    if is_nil(user.hashed_password) do
      true
    else
      GameServer.Accounts.valid_password?(user, params["current_password"])
    end
  end

  operation(:update_display_name,
    operation_id: "update_current_user_display_name",
    summary: "Update current user's display name",
    request_body: {
      "Display name payload",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          display_name: %Schema{type: :string}
        },
        required: [:display_name]
      }
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Display name updated", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid data", "application/json", @validation_error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def update_display_name(conn, %{"display_name" => _} = params) do
    user = Scope.user(conn.assigns.current_scope)

    case GameServer.Accounts.update_user_display_name(user, params) do
      {:ok, user} ->
        json(conn, %{ok: true, id: user.id, display_name: user.display_name || ""})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_data",
          errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        })
    end
  end

  operation(:update_username,
    operation_id: "update_current_user_username",
    summary: "Update current user's username",
    description:
      "Sets the unique username handle. Lowercased on save; 3-32 chars of a-z, 0-9 and " <>
        "non-consecutive . _ - separators, starting and ending alphanumeric. " <>
        "Returns invalid_data when the username is malformed or already taken.",
    request_body: {
      "Username payload",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          username: %Schema{type: :string}
        },
        required: [:username]
      }
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Username updated", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid data", "application/json", @validation_error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def update_username(conn, %{"username" => _} = params) do
    user = Scope.user(conn.assigns.current_scope)

    case GameServer.Accounts.update_username(user, params) do
      {:ok, user} ->
        json(conn, %{ok: true, id: user.id, username: user.username || ""})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_data",
          errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        })

      {:error, reason} when is_atom(reason) or is_binary(reason) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_data", errors: %{username: [to_string(reason)]}})

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_data"})
    end
  end

  operation(:avatar_upload_url,
    operation_id: "create_current_user_avatar_upload_url",
    summary: "Request an avatar upload ticket",
    description:
      "Returns an upload ticket. Upload the image bytes to `url` with `method`/`headers`, " <>
        "then confirm with `POST /me/avatar` using the returned `key`.",
    request_body: {
      "Upload metadata",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          content_type: %Schema{type: :string, example: "image/png"},
          filename: %Schema{type: :string, example: "avatar.png"}
        },
        required: [:content_type]
      }
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Upload ticket", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid content type or size", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def avatar_upload_url(conn, params) do
    user = Scope.user(conn.assigns.current_scope)
    Uploads.ticket(conn, "avatars", user.id, "avatar", Uploads.content_type(params))
  end

  operation(:set_avatar,
    operation_id: "set_current_user_avatar",
    summary: "Confirm an uploaded avatar",
    description: "Records a previously uploaded object (`key`) as the user's avatar.",
    request_body: {
      "Uploaded object key",
      "application/json",
      %Schema{type: :object, properties: %{key: %Schema{type: :string}}, required: [:key]}
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Avatar updated", "application/json", %Schema{type: :object}},
      bad_request: {"Object not found", "application/json", @error_schema},
      forbidden: {"Key not owned by user", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def set_avatar(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    Uploads.confirm(conn, "avatars", user.id, params["key"], fn url ->
      case GameServer.Accounts.update_user_avatar(user, url) do
        {:ok, updated} -> json(conn, %{ok: true, profile_url: updated.profile_url})
        {:error, _} -> conn |> put_status(:bad_request) |> json(%{error: "invalid_data"})
      end
    end)
  end

  operation(:delete,
    operation_id: "delete_current_user",
    summary: "Delete current user",
    description: "Deletes the authenticated user's account",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Account deleted", "application/json", %Schema{type: :object}},
      bad_request: {"Failed to delete account", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def delete(conn, _params) do
    user = Scope.user(conn.assigns.current_scope)

    case GameServer.Accounts.delete_user(user) do
      {:ok, _} ->
        json(conn, %{})

      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to delete account"})
    end
  end
end
