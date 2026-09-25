defmodule GamendWeb.Api.V1.MeController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{CurrentUserResponse, OkResponse, UploadTicketResponse}
  alias GamendWeb.Serializers
  alias GamendWeb.Uploads
  alias OpenApiSpex.Schema

  tags(["Users"])

  operation(:show,
    operation_id: "get_current_user",
    summary: "Return current user info",
    description: "Returns the current authenticated user's basic information.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"User info", "application/json", CurrentUserResponse},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def show(conn, _params) do
    # Guardian pipeline has already authenticated and loaded the user
    # into current_scope via AssignCurrentScope plug
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        reply_data(conn, current_user(user))

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
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
      ok: {"Password updated", "application/json", CurrentUserResponse},
      unprocessable_entity: Schemas.error("Validation failed"),
      unauthorized: Schemas.error("Not authenticated, or wrong current password")
    ]
  )

  def update_password(conn, %{"password" => _} = params) do
    user = Scope.user(conn.assigns.current_scope)

    if password_change_authorized?(user, params) do
      case Gamend.Accounts.update_user_password(user, params) do
        {:ok, {user, _tokens}} ->
          reply_data(conn, current_user(user))

        {:error, changeset} ->
          unprocessable(conn, changeset)
      end
    else
      reply_error(
        conn,
        :unauthorized,
        "invalid_current_password",
        "current_password is required and must match your existing password"
      )
    end
  end

  # Accounts with an existing password must prove it to change it (a stolen
  # access token must not be escalatable into a permanent password reset).
  # OAuth/device accounts with no password yet may set one without re-auth.
  defp password_change_authorized?(user, params) do
    if is_nil(user.hashed_password) do
      true
    else
      Gamend.Accounts.valid_password?(user, params["current_password"])
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
      ok: {"Display name updated", "application/json", CurrentUserResponse},
      unprocessable_entity: Schemas.error("Validation failed"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def update_display_name(conn, %{"display_name" => _} = params) do
    user = Scope.user(conn.assigns.current_scope)

    case Gamend.Accounts.update_user_display_name(user, params) do
      {:ok, user} ->
        reply_data(conn, current_user(user))

      {:error, changeset} ->
        unprocessable(conn, changeset)
    end
  end

  operation(:update_username,
    operation_id: "update_current_user_username",
    summary: "Update current user's username",
    description:
      "Sets the unique username handle. Lowercased on save; 3-32 letters or digits and " <>
        "non-consecutive . _ - separators, starting and ending on a letter or digit. Letters keep to " <>
        "one script, except that Latin mixes with Chinese, Japanese or Korean; a host may replace " <>
        "these rules. " <>
        "Answers 422 validation_failed when the username is malformed or already taken.",
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
      ok: {"Username updated", "application/json", CurrentUserResponse},
      unprocessable_entity: Schemas.error("Validation failed"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def update_username(conn, %{"username" => _} = params) do
    user = Scope.user(conn.assigns.current_scope)

    case Gamend.Accounts.update_username(user, params) do
      {:ok, user} ->
        reply_data(conn, current_user(user))

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)

      {:error, reason} when is_atom(reason) or is_binary(reason) ->
        user
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:username, to_string(reason))
        |> then(&unprocessable(conn, &1))

      {:error, _reason} ->
        reply_error(conn, :unprocessable_entity, "invalid_username")
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
      ok: {"Upload ticket", "application/json", UploadTicketResponse},
      bad_request: Schemas.error("Invalid content type or size"),
      forbidden: Schemas.error("Avatars are disabled for anonymous accounts"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def avatar_upload_url(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    if Accounts.can_upload_avatar?(user) do
      Uploads.ticket(conn, "avatars", user.id, "avatar", Uploads.content_type(params))
    else
      avatar_forbidden(conn)
    end
  end

  # Refused at both ends: the ticket is where a well-behaved client stops, and
  # confirm is where an old ticket or a direct-to-S3 upload would otherwise slip
  # a stored object onto the account.
  defp avatar_forbidden(conn) do
    reply_error(conn, :forbidden, "anonymous_avatar_disabled")
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
      ok: {"Avatar updated", "application/json", CurrentUserResponse},
      bad_request: Schemas.error("Object not found, or missing key"),
      forbidden: Schemas.error("Key not owned by user, or avatars disabled"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def set_avatar(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    if Accounts.can_upload_avatar?(user),
      do: do_set_avatar(conn, user, params),
      else: avatar_forbidden(conn)
  end

  defp do_set_avatar(conn, user, params) do
    Uploads.confirm(conn, "avatars", user.id, params["key"], fn url ->
      case Gamend.Accounts.update_user_avatar(user, url) do
        {:ok, updated} -> reply_data(conn, current_user(updated))
        {:error, changeset} -> unprocessable(conn, changeset)
      end
    end)
  end

  operation(:delete,
    operation_id: "delete_current_user",
    summary: "Delete current user",
    description:
      "Deletes the authenticated user's account. An account with a password sends " <>
        "it as `current_password`; a device or OAuth-only one sends nothing. When the " <>
        "server keeps a grace period (`GAMEND_AUTH_DELETION_GRACE_DAYS`), the account is " <>
        "instead scheduled for deletion that many days out and signed out everywhere; " <>
        "API sign-ins answer 403 `deletion_scheduled` until then, and signing in on the " <>
        "website keeps the account.",
    security: [%{"authorization" => []}],
    request_body: {
      "Current password, for an account that has one",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          current_password: %Schema{
            type: :string,
            format: :password,
            description: "The account's password"
          }
        }
      },
      required: false
    },
    responses: [
      ok: {"Account deleted", "application/json", OkResponse},
      bad_request: Schemas.error("Failed to delete account"),
      unauthorized: Schemas.error("Not authenticated, or wrong current password")
    ]
  )

  def delete(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    # Deleting the account requires the password, when there is one.
    #
    # Changing a password already demands `current_password` on the reasoning
    # that a stolen access token must not become a permanent takeover — and
    # permanently destroying the account, its stored objects, KV entries and
    # wallet is the larger of the two actions. Accounts with no password (device
    # and OAuth-only) have nothing to prove, exactly as for setting one.
    if password_change_authorized?(user, params) do
      case Gamend.Accounts.request_deletion(user) do
        {:ok, :deleted} ->
          reply_ok(conn)

        {:ok, {:scheduled, _user, expired_tokens}} ->
          GamendWeb.UserAuth.disconnect_sessions(expired_tokens)
          reply_ok(conn)

        {:error, _} ->
          reply_error(conn, :bad_request, "delete_failed")
      end
    else
      reply_error(conn, :unauthorized, "invalid_current_password")
    end
  end

  defp current_user(%User{} = user), do: Serializers.serialize_current_user(user)
end
