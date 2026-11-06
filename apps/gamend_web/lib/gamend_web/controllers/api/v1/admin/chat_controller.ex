defmodule GamendWeb.Api.V1.Admin.ChatController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Chat
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{ChatMessagePage, DeletedCountResponse, OkResponse}
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Admin – Chat"])

  operation(:index,
    operation_id: "admin_list_chat_messages",
    summary: "List all chat messages (admin)",
    description:
      "List all chat messages with optional filters. Returns paginated results sorted by newest first.",
    security: [%{"authorization" => []}],
    parameters: [
      sender_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      chat_type: [
        in: :query,
        schema: %Schema{type: :string, enum: ["lobby", "group", "friend", "party"]}
      ],
      chat_ref_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      content: [in: :query, schema: %Schema{type: :string}],
      sort_by: [
        in: :query,
        schema: %Schema{
          type: :string,
          enum: ["inserted_at", "inserted_at_asc"]
        }
      ],
      page: [in: :query, schema: %Schema{type: :integer}],
      page_size: [in: :query, schema: %Schema{type: :integer}]
    ],
    responses: [
      ok: {"Chat messages list", "application/json", ChatMessagePage}
    ]
  )

  operation(:delete,
    operation_id: "admin_delete_chat_message",
    summary: "Delete a chat message (admin)",
    description: "Admin-level message deletion by ID.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      not_found: Schemas.error("Not found")
    ]
  )

  operation(:delete_conversation,
    operation_id: "admin_delete_chat_conversation",
    summary: "Delete all messages in a conversation (admin)",
    description: "Delete all messages for a given chat_type and chat_ref_id.",
    security: [%{"authorization" => []}],
    parameters: [
      chat_type: [
        in: :query,
        schema: %Schema{type: :string, enum: ["lobby", "group", "friend", "party"]},
        required: true
      ],
      chat_ref_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted count", "application/json", DeletedCountResponse},
      bad_request: Schemas.error("chat_type and chat_ref_id are required (missing_param)")
    ]
  )

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  def index(conn, params) do
    filters =
      %{}
      |> maybe_put_param_filter(:sender_id, params)
      |> maybe_put_param_filter(:chat_type, params)
      |> maybe_put_param_filter(:chat_ref_id, params)
      |> maybe_put_param_filter(:content, params)

    {page, page_size} = GamendWeb.Pagination.params(params)
    sort_by = Map.get(params, "sort_by")

    messages =
      Chat.list_all_messages(filters,
        page: page,
        page_size: page_size,
        sort_by: sort_by
      )

    serialized = Enum.map(messages, &serialize_message/1)
    total_count = Chat.count_all_messages(filters)

    reply_page(conn, serialized, page, page_size, total_count)
  end

  def delete(conn, %{"id" => id}) do
    case parse_id(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      message_id ->
        case Chat.admin_delete_message(message_id) do
          {:ok, _} -> reply_ok(conn)
          {:error, reason} -> reply_reason(conn, reason)
        end
    end
  end

  def delete_conversation(conn, params) do
    chat_type = Map.get(params, "chat_type")
    chat_ref_id = Map.get(params, "chat_ref_id")

    if is_nil(chat_type) or is_nil(chat_ref_id) do
      reply_error(conn, :bad_request, "missing_param", "chat_type and chat_ref_id are required")
    else
      {deleted, _} = Chat.delete_messages(chat_type, parse_id(chat_ref_id) || 0)
      reply_data(conn, %{deleted: deleted})
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp serialize_message(message),
    do:
      Serializers.serialize_chat_message(message,
        include_updated_at: true,
        include_sender_email: true
      )
end
