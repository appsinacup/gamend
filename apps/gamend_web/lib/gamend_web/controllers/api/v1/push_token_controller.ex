defmodule GamendWeb.Api.V1.PushTokenController do
  @moduledoc """
  Device push-token registration for the current user. Sending pushes is
  server-authoritative (hooks / admin) and has no public endpoint.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Scope
  alias Gamend.Push
  alias Gamend.Push.Platform
  alias Gamend.Push.PushProvider
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{PushTokenPage, PushTokenResponse}
  alias OpenApiSpex.Schema

  tags(["Push"])

  operation(:create,
    operation_id: "register_push_token",
    summary: "Register a device push token",
    description:
      "Registers (or refreshes) the device's FCM/APNs token. Passing a stable " <>
        "device_id makes re-registration rotate the token in place. provider " <>
        "defaults from the platform: ios registers as apns, everything else as fcm.",
    security: [%{"authorization" => []}],
    request_body:
      {"Registration", "application/json",
       %Schema{
         type: :object,
         required: [:token, :platform],
         properties: %{
           token: %Schema{type: :string},
           platform: %Schema{
             type: :string,
             enum: Platform.all()
           },
           provider: %Schema{type: :string, enum: PushProvider.all()},
           device_id: %Schema{type: :string},
           metadata: %Schema{type: :object}
         }
       }},
    responses: [
      created: {"Registered token", "application/json", PushTokenResponse},
      bad_request: Schemas.error("Too many devices"),
      unprocessable_entity: Schemas.error("Validation failed"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def create(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    case Push.register_token(user.id, params) do
      {:ok, token} ->
        reply_data(conn, :created, serialize(token))

      {:error, :too_many_tokens} ->
        reply_error(conn, :bad_request, "too_many_tokens")

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)
    end
  end

  operation(:index,
    operation_id: "list_push_tokens",
    summary: "List the current user's registered devices",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
    ],
    responses: [
      ok: {"Tokens", "application/json", PushTokenPage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def index(conn, params) do
    user = Scope.user(conn.assigns.current_scope)
    {page, page_size} = Pagination.params(params)

    tokens = Push.list_tokens(user.id, page: page, page_size: page_size)
    total = Push.count_tokens(user.id)

    reply_page(conn, Enum.map(tokens, &serialize/1), page, page_size, total)
  end

  operation(:delete,
    operation_id: "delete_push_token",
    summary: "Unregister one of the current user's devices",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted token", "application/json", PushTokenResponse},
      not_found: Schemas.error("Unknown token"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def delete(conn, %{"id" => id}) do
    user = Scope.user(conn.assigns.current_scope)

    case Gamend.UUIDv7.cast_or_nil(id) && Push.delete_token(user.id, id) do
      {:ok, token} -> reply_data(conn, serialize(token))
      _ -> reply_error(conn, :not_found, "not_found")
    end
  end

  defp serialize(token) do
    %{
      id: token.id,
      token: token.token,
      platform: token.platform,
      provider: token.provider || "",
      device_id: token.device_id || "",
      disabled_at: token.disabled_at,
      last_used_at: token.last_used_at,
      metadata: token.metadata,
      inserted_at: token.inserted_at
    }
  end
end
