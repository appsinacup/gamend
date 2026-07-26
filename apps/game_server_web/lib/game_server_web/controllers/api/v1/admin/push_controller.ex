defmodule GameServerWeb.Api.V1.Admin.PushController do
  @moduledoc """
  Admin API parity for the admin Push page: list registered device tokens,
  delete one, and send a push to a user.
  """
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Push
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  tags(["Admin – Push"])

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @push_token_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      user_name: %Schema{type: :string},
      token: %Schema{type: :string},
      platform: %Schema{type: :string, enum: ["android", "ios", "web"]},
      provider: %Schema{type: :string, enum: ["fcm", "apns"]},
      device_id: %Schema{type: :string},
      disabled_at: %Schema{type: :string, format: :"date-time", nullable: true},
      last_used_at: %Schema{type: :string, format: :"date-time", nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  operation(:index,
    operation_id: "admin_list_push_tokens",
    summary: "List registered device push tokens (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      platform: [
        in: :query,
        schema: %Schema{type: :string, enum: ["android", "ios", "web"]},
        required: false
      ],
      provider: [
        in: :query,
        schema: %Schema{type: :string, enum: ["fcm", "apns"]},
        required: false
      ],
      status: [
        in: :query,
        schema: %Schema{type: :string, enum: ["live", "disabled"]},
        required: false
      ],
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
    {page, page_size} = GameServerWeb.Pagination.params(params)
    filters = Map.take(params, ["user_id", "platform", "provider", "status"])

    tokens = Push.list_all_tokens(filters, page: page, page_size: page_size)
    total = Push.count_all_tokens(filters)

    json(conn, %{
      data: Enum.map(tokens, &serialize/1),
      meta: Pagination.meta(page, page_size, length(tokens), total)
    })
  end

  operation(:delete,
    operation_id: "admin_delete_push_token",
    summary: "Delete a device push token (admin)",
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
    case GameServer.UUIDv7.cast_or_nil(id) && Push.admin_delete_token(id) do
      {:ok, token} -> json(conn, serialize(token))
      _ -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  operation(:send,
    operation_id: "admin_send_push",
    summary: "Send a push notification to a user (admin)",
    description:
      "Queues the message to every live device of the user. Delivery is " <>
        "asynchronous; with no provider configured it lands in the server log.",
    security: [%{"authorization" => []}],
    request_body:
      {"Message", "application/json",
       %Schema{
         type: :object,
         required: [:user_id, :title],
         properties: %{
           user_id: %Schema{type: :string, format: :uuid},
           title: %Schema{type: :string},
           body: %Schema{type: :string},
           data: %Schema{type: :object},
           image: %Schema{type: :string},
           sound: %Schema{type: :string},
           badge: %Schema{type: :integer},
           collapse_key: %Schema{type: :string}
         }
       }},
    responses: [
      ok:
        {"Queued", "application/json",
         %Schema{type: :object, properties: %{status: %Schema{type: :string}}}},
      bad_request: {"Invalid message", "application/json", @error_schema},
      not_found: {"Unknown user", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def send(conn, %{"user_id" => user_id} = params) do
    with true <- GameServer.UUIDv7.cast_or_nil(user_id) != nil,
         %GameServer.Accounts.User{} <- GameServer.Repo.get(GameServer.Accounts.User, user_id) do
      message =
        Map.take(params, ["title", "body", "data", "image", "sound", "badge", "collapse_key"])

      case Push.send_to_user(user_id, message) do
        :ok ->
          json(conn, %{status: "queued"})

        {:error, errors} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "invalid_message", errors: errors})
      end
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "user_not_found"})
    end
  end

  def send(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing_user_id"})
  end

  defp serialize(token) do
    %{
      id: token.id,
      user_id: token.user_id,
      user_name: user_name(token),
      token: token.token,
      platform: token.platform,
      provider: token.provider || "",
      device_id: token.device_id || "",
      disabled_at: token.disabled_at,
      last_used_at: token.last_used_at,
      inserted_at: token.inserted_at
    }
  end

  defp user_name(%{user: %GameServer.Accounts.User{} = user}),
    do: user.display_name || user.username

  defp user_name(_), do: nil
end
