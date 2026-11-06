defmodule GamendWeb.Api.V1.Admin.PushController do
  @moduledoc """
  Admin API parity for the admin Push page: list registered device tokens,
  delete one, and send a push to a user.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Push
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{AdminPushTokenPage, OkResponse}
  alias OpenApiSpex.Schema

  tags(["Admin – Push"])

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
      ok: {"Tokens", "application/json", AdminPushTokenPage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def index(conn, params) do
    {page, page_size} = GamendWeb.Pagination.params(params)
    filters = Map.take(params, ["user_id", "platform", "provider", "status"])

    tokens = Push.list_all_tokens(filters, page: page, page_size: page_size)
    total = Push.count_all_tokens(filters)

    reply_page(conn, Enum.map(tokens, &serialize/1), page, page_size, total)
  end

  operation(:delete,
    operation_id: "admin_delete_push_token",
    summary: "Delete a device push token (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      not_found: Schemas.error("Unknown token"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def delete(conn, %{"id" => id}) do
    case Gamend.UUIDv7.cast_or_nil(id) && Push.admin_delete_token(id) do
      {:ok, _token} -> reply_ok(conn)
      _ -> reply_error(conn, :not_found, "not_found")
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
      ok: {"Queued", "application/json", OkResponse},
      bad_request: Schemas.error("No user_id (missing_param)"),
      unprocessable_entity: Schemas.error("Invalid message (validation_failed)"),
      not_found: Schemas.error("Unknown user"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def send(conn, %{"user_id" => user_id} = params) do
    with user_id when is_binary(user_id) <- Gamend.UUIDv7.cast_or_nil(user_id),
         %Gamend.Accounts.User{} <- Gamend.Repo.get(Gamend.Accounts.User, user_id) do
      message =
        Map.take(params, ["title", "body", "data", "image", "sound", "badge", "collapse_key"])

      case Push.send_to_user(user_id, message) do
        :ok ->
          reply_ok(conn)

        {:error, errors} ->
          unprocessable(conn, errors)
      end
    else
      # Not an id, or no user has it.
      nil -> reply_error(conn, :not_found, "user_not_found")
    end
  end

  def send(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "user_id is required")
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

  defp user_name(%{user: %Gamend.Accounts.User{} = user}),
    do: Gamend.Accounts.display_name(user)

  defp user_name(_), do: ""
end
