defmodule GameServerWeb.Api.V1.PushTokenController do
  @moduledoc """
  Device push-token registration for the current user. Sending pushes is
  server-authoritative (hooks / admin) and has no public endpoint.
  """
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Accounts.Scope
  alias GameServer.Push
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  tags(["Push"])

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @push_token_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      token: %Schema{type: :string},
      platform: %Schema{type: :string, enum: ["android", "ios", "web"]},
      provider: %Schema{type: :string, enum: ["fcm", "apns"]},
      device_id: %Schema{type: :string},
      disabled_at: %Schema{type: :string, format: :"date-time", nullable: true},
      last_used_at: %Schema{type: :string, format: :"date-time", nullable: true},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  }

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
           platform: %Schema{type: :string, enum: ["android", "ios", "web"]},
           provider: %Schema{type: :string, enum: ["fcm", "apns"]},
           device_id: %Schema{type: :string},
           metadata: %Schema{type: :object}
         }
       }},
    responses: [
      created: {"Registered token", "application/json", @push_token_schema},
      bad_request: {"Too many devices", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def create(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    case Push.register_token(user.id, params) do
      {:ok, token} ->
        conn
        |> put_status(:created)
        |> json(serialize(token))

      {:error, :too_many_tokens} ->
        conn |> put_status(:bad_request) |> json(%{error: "too_many_tokens"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", errors: changeset_errors(changeset)})
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
      ok:
        {"Tokens", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @push_token_schema},
             meta: %Schema{type: :object}
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def index(conn, params) do
    user = Scope.user(conn.assigns.current_scope)
    {page, page_size} = GameServerWeb.Pagination.params(params)

    tokens = Push.list_tokens(user.id, page: page, page_size: page_size)
    total = Push.count_tokens(user.id)

    json(conn, %{
      data: Enum.map(tokens, &serialize/1),
      meta: Pagination.meta(page, page_size, length(tokens), total)
    })
  end

  operation(:delete,
    operation_id: "delete_push_token",
    summary: "Unregister one of the current user's devices",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted token", "application/json", @push_token_schema},
      not_found: {"Unknown token", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def delete(conn, %{"id" => id}) do
    user = Scope.user(conn.assigns.current_scope)

    case GameServer.UUIDv7.cast_or_nil(id) && Push.delete_token(user.id, id) do
      {:ok, token} -> json(conn, serialize(token))
      _ -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
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

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
