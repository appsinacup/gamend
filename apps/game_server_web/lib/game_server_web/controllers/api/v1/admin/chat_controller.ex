defmodule GameServerWeb.Api.V1.Admin.ChatController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.Chat
  alias GameServerWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Admin – Chat"])

  @error_schema %Schema{
    type: :object,
    properties: %{error: %Schema{type: :string}}
  }

  @meta_schema %Schema{
    type: :object,
    properties: %{
      page: %Schema{type: :integer},
      page_size: %Schema{type: :integer},
      count: %Schema{type: :integer},
      total_count: %Schema{type: :integer},
      total_pages: %Schema{type: :integer},
      has_more: %Schema{type: :boolean}
    }
  }

  @message_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      sender_id: %Schema{type: :string, format: :uuid},
      sender_name: %Schema{type: :string},
      sender_email: %Schema{type: :string},
      content: %Schema{type: :string},
      metadata: %Schema{type: :object},
      chat_type: %Schema{type: :string, enum: ["lobby", "group", "friend", "party"]},
      chat_ref_id: %Schema{type: :string, format: :uuid},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    }
  }

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
      ok:
        {"Chat messages list", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @message_schema},
             meta: @meta_schema
           }
         }}
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
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      not_found: {"Not found", "application/json", @error_schema}
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
      ok:
        {"Deleted count", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :object, properties: %{deleted: %Schema{type: :integer}}}
           }
         }},
      unprocessable_entity: {"Missing params", "application/json", @error_schema}
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

    {page, page_size} = GameServerWeb.Pagination.params(params)
    sort_by = Map.get(params, "sort_by")

    messages =
      Chat.list_all_messages(filters,
        page: page,
        page_size: page_size,
        sort_by: sort_by
      )

    serialized = Enum.map(messages, &serialize_message/1)
    count = length(serialized)
    total_count = Chat.count_all_messages(filters)

    json(conn, %{
      data: serialized,
      meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
    })
  end

  def delete(conn, %{"id" => id}) do
    case parse_id(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      message_id ->
        case Chat.admin_delete_message(message_id) do
          {:ok, _} -> json(conn, %{})
          {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
          {:error, _} -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
        end
    end
  end

  def delete_conversation(conn, params) do
    chat_type = Map.get(params, "chat_type")
    chat_ref_id = Map.get(params, "chat_ref_id")

    if is_nil(chat_type) or is_nil(chat_ref_id) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "chat_type and chat_ref_id are required"})
    else
      {deleted, _} = Chat.delete_messages(chat_type, parse_id(chat_ref_id) || 0)
      json(conn, %{data: %{deleted: deleted}})
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
