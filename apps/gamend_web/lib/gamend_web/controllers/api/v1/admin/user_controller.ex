defmodule GamendWeb.Api.V1.Admin.UserController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Async
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{AdminUserResponse, OkResponse}
  alias OpenApiSpex.Schema

  tags(["Admin – Users"])

  operation(:update,
    operation_id: "admin_update_user",
    summary: "Update user (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {
      "User patch",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          is_admin: %Schema{type: :boolean},
          is_activated: %Schema{type: :boolean},
          display_name: %Schema{type: :string},
          metadata: %Schema{type: :object}
        }
      }
    },
    responses: [
      ok: {"User", "application/json", AdminUserResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required, or would demote the last admin (last_admin)"),
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def update(conn, %{"id" => id} = params) do
    case Accounts.get_user(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      user ->
        attrs =
          params
          |> Map.delete("id")
          |> ensure_is_admin_present(user)

        if demoting_last_admin?(user, attrs) do
          reply_error(conn, :forbidden, "last_admin")
        else
          do_update(conn, user, attrs)
        end
    end
  end

  # An installation with no administrators cannot be administered: `/admin` is
  # gated on `is_admin`, and nothing else can set the flag. There was no guard
  # at all, so an admin could demote themselves — or the only other admin — and
  # lock everyone out of the console permanently.
  defp demoting_last_admin?(user, attrs) do
    demoting? = Map.get(attrs, "is_admin") in [false, "false"]

    demoting? and user.is_admin and Accounts.count_admins() <= 1
  end

  defp do_update(conn, user, attrs) do
    case Accounts.update_user(user, attrs) do
      {:ok, updated} ->
        maybe_notify_activation(user, updated)
        reply_data(conn, serialize_user(updated))

      {:error, %Ecto.Changeset{} = cs} ->
        unprocessable(conn, cs)

      # Deleted between the lookup above and the write.
      {:error, :not_found} ->
        reply_error(conn, :not_found, "not_found")
    end
  end

  # Send activation email when user transitions from deactivated to activated
  defp maybe_notify_activation(old_user, updated_user) do
    if not old_user.is_activated and updated_user.is_activated do
      Async.run(fn ->
        Accounts.UserNotifier.deliver_account_activated(updated_user)
      end)
    end
  end

  operation(:delete,
    operation_id: "admin_delete_user",
    summary: "Delete user (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required"),
      not_found: Schemas.error("Not found")
    ]
  )

  def delete(conn, %{"id" => id}) do
    case Accounts.get_user(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      user ->
        case Accounts.delete_user(user) do
          {:ok, _} ->
            reply_ok(conn)

          # Deleted since it was read.
          {:error, :not_found} ->
            reply_error(conn, :not_found, "not_found")

          {:error, %Ecto.Changeset{} = cs} ->
            unprocessable(conn, cs)
        end
    end
  end

  defp ensure_is_admin_present(attrs, user) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :is_admin) -> attrs
      Map.has_key?(attrs, "is_admin") -> attrs
      true -> Map.put(attrs, :is_admin, user.is_admin)
    end
  end

  defp serialize_user(user) do
    %{
      id: user.id,
      email: user.email || "",
      username: user.username || "",
      display_name: user.display_name || "",
      is_admin: user.is_admin,
      is_activated: user.is_activated,
      metadata: user.metadata || %{},
      lobby_id: user.lobby_id || "",
      party_id: user.party_id || "",
      is_online: user.is_online,
      last_seen_at: User.last_seen_at_or_fallback(user),
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end
end
