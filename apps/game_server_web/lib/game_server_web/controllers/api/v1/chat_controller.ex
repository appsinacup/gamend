defmodule GameServerWeb.Api.V1.ChatController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.Accounts.Scope
  alias GameServer.Chat
  alias GameServerWeb.Pagination
  alias GameServerWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Chat"])

  @message_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Message ID"},
      content: %Schema{type: :string, description: "Message text"},
      metadata: %Schema{type: :object, description: "Arbitrary metadata"},
      sender_id: %Schema{type: :string, format: :uuid, description: "User ID of the sender"},
      sender_name: %Schema{type: :string, description: "Display name of the sender"},
      chat_type: %Schema{
        type: :string,
        enum: ["lobby", "group", "friend", "party"],
        description: "Type of chat conversation"
      },
      chat_ref_id: %Schema{
        type: :string,
        format: :uuid,
        description: "Reference ID (lobby_id, group_id, party_id, or friend user_id)"
      },
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    example: %{
      id: "0198c0de-0001-7000-8000-000000000001",
      content: "Hello everyone!",
      metadata: %{},
      sender_id: "0198c0de-0002-7000-8000-000000000002",
      sender_name: "Player1",
      chat_type: "lobby",
      chat_ref_id: "0198c0de-0002-7000-8000-000000000002",
      inserted_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-01T00:00:00Z"
    }
  }

  # ---------------------------------------------------------------------------
  # Send message
  # ---------------------------------------------------------------------------

  operation(:send,
    operation_id: "send_chat_message",
    summary: "Send a chat message",
    description:
      "Send a message to a lobby, group, party, or friend conversation. Requires authentication and membership/friendship.",
    request_body:
      {"Chat message", "application/json",
       %Schema{
         type: :object,
         required: [:chat_type, :chat_ref_id, :content],
         properties: %{
           chat_type: %Schema{
             type: :string,
             enum: ["lobby", "group", "friend", "party"],
             description: "Type of chat"
           },
           chat_ref_id: %Schema{
             type: :string,
             format: :uuid,
             description: "Reference ID (lobby_id, group_id, party_id, or friend user_id)"
           },
           content: %Schema{type: :string, description: "Message text (1-4096 chars)"},
           metadata: %Schema{type: :object, description: "Optional metadata"}
         }
       }},
    responses: [
      created: {"Message sent", "application/json", @message_schema},
      bad_request: {"Invalid input", "application/json", %Schema{type: :object}},
      forbidden: {"Not allowed", "application/json", %Schema{type: :object}},
      unprocessable_entity:
        {"Validation or hook error", "application/json", %Schema{type: :object}}
    ]
  )

  def send(conn, params) do
    scope = conn.assigns[:current_scope]

    attrs = %{
      "chat_type" => params["chat_type"],
      "chat_ref_id" => parse_id(params["chat_ref_id"]),
      "content" => params["content"],
      "metadata" => params["metadata"] || %{}
    }

    with :ok <- GameServerWeb.RateLimit.check_chat_daily(scope.user_id),
         {:ok, message} <- Chat.send_message(%{user: Scope.user(scope)}, attrs) do
      conn |> put_status(:created) |> json(serialize_message(message))
    else
      {:error, :chat_daily_limit} ->
        conn |> put_status(:too_many_requests) |> json(%{error: "chat_daily_limit"})

      {:error, :not_in_lobby} ->
        conn |> put_status(:forbidden) |> json(%{error: "not_in_lobby"})

      {:error, :not_in_group} ->
        conn |> put_status(:forbidden) |> json(%{error: "not_in_group"})

      {:error, :not_friends} ->
        conn |> put_status(:forbidden) |> json(%{error: "not_friends"})

      {:error, :not_in_party} ->
        conn |> put_status(:forbidden) |> json(%{error: "not_in_party"})

      {:error, :blocked} ->
        conn |> put_status(:forbidden) |> json(%{error: "blocked"})

      {:error, :slowdown} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "slowdown", message: "You are sending messages too quickly"})

      {:error, :invalid_chat_type} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_chat_type"})

      {:error, {:hook_rejected, reason}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "hook_rejected", reason: to_string(reason)})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", details: changeset_errors(cs)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  # ---------------------------------------------------------------------------
  # Get single message
  # ---------------------------------------------------------------------------

  operation(:show,
    operation_id: "get_chat_message",
    summary: "Get a single chat message",
    description:
      "Retrieve a single chat message by ID. Useful for refreshing a message after an update notification.",
    parameters: [
      id: [
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid},
        description: "Message ID"
      ]
    ],
    responses: [
      ok: {"Chat message", "application/json", @message_schema},
      not_found: {"Message not found", "application/json", %Schema{type: :object}}
    ]
  )

  def show(conn, %{"id" => id}) do
    message_id = parse_id(id)
    user = Scope.user(conn.assigns.current_scope)

    case Chat.get_message(message_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      message ->
        if can_access_message?(user, message) do
          json(conn, serialize_message(message))
        else
          conn |> put_status(:not_found) |> json(%{error: "not_found"})
        end
    end
  end

  defp can_access_message?(user, message) do
    case message.chat_type do
      "friend" ->
        message.sender_id == user.id || message.chat_ref_id == user.id

      "lobby" ->
        user.lobby_id != nil && user.lobby_id == message.chat_ref_id

      "group" ->
        GameServer.Groups.member?(message.chat_ref_id, user.id)

      "party" ->
        user.party_id != nil && user.party_id == message.chat_ref_id

      _ ->
        false
    end
  end

  # ---------------------------------------------------------------------------
  # List messages
  # ---------------------------------------------------------------------------

  operation(:index,
    operation_id: "list_chat_messages",
    summary: "List chat messages",
    description:
      "List messages for a lobby, group, party, or friend conversation. Paginated, newest first.",
    parameters: [
      chat_type: [
        in: :query,
        required: true,
        schema: %Schema{type: :string, enum: ["lobby", "group", "friend", "party"]},
        description: "Type of chat"
      ],
      chat_ref_id: [
        in: :query,
        required: true,
        schema: %Schema{type: :string, format: :uuid},
        description: "Reference ID (lobby_id, group_id, party_id, or friend user_id)"
      ],
      page: [
        in: :query,
        schema: %Schema{type: :integer, default: 1},
        description: "Page number"
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, default: 25},
        description: "Items per page (max 100)"
      ]
    ],
    responses: [
      ok:
        {"Chat messages", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @message_schema},
             meta: %Schema{type: :object}
           }
         }}
    ]
  )

  def index(conn, params) do
    scope = conn.assigns[:current_scope]
    user_id = scope.user_id
    chat_type = params["chat_type"]
    chat_ref_id = parse_id(params["chat_ref_id"])
    {page, page_size} = Pagination.params(params)

    case authorize_conversation(conn, user_id, chat_type, chat_ref_id) do
      :ok ->
        {messages, total_count} =
          if chat_type == "friend" do
            msgs =
              Chat.list_friend_messages(user_id, chat_ref_id, page: page, page_size: page_size)

            total = Chat.count_friend_messages(user_id, chat_ref_id)
            {msgs, total}
          else
            msgs = Chat.list_messages(chat_type, chat_ref_id, page: page, page_size: page_size)
            total = Chat.count_messages(chat_type, chat_ref_id)
            {msgs, total}
          end

        count = length(messages)

        json(conn, %{
          data: Enum.map(messages, &serialize_message/1),
          meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
        })

      {:error, conn} ->
        conn
    end
  end

  # ---------------------------------------------------------------------------
  # Mark read
  # ---------------------------------------------------------------------------

  operation(:mark_read,
    operation_id: "mark_chat_read",
    summary: "Mark chat as read",
    description: "Update the read cursor for the current user in a chat conversation.",
    request_body:
      {"Read cursor", "application/json",
       %Schema{
         type: :object,
         required: [:chat_type, :chat_ref_id, :message_id],
         properties: %{
           chat_type: %Schema{type: :string, enum: ["lobby", "group", "friend", "party"]},
           chat_ref_id: %Schema{type: :string, format: :uuid},
           message_id: %Schema{type: :string, format: :uuid, description: "Last read message ID"}
         }
       }},
    responses: [
      ok: {"Read cursor updated", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def mark_read(conn, params) do
    user_id = conn.assigns[:current_scope].user_id
    chat_type = params["chat_type"]
    chat_ref_id = parse_id(params["chat_ref_id"])
    message_id = parse_id(params["message_id"])

    case Chat.mark_read(user_id, chat_type, chat_ref_id, message_id) do
      {:ok, cursor} ->
        json(conn, %{
          chat_type: cursor.chat_type,
          chat_ref_id: cursor.chat_ref_id,
          last_read_message_id: cursor.last_read_message_id,
          updated_at: cursor.updated_at
        })

      {:error, reason} when reason in [:invalid_chat_ref, :invalid_chat_type, :invalid_message] ->
        conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})

      {:error, reason}
      when reason in [:not_in_lobby, :not_in_group, :not_friends, :not_in_party, :blocked] ->
        conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})

      {:error, :message_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "message_not_found"})

      {:error, :message_not_in_chat} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "message_not_in_chat"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  # ---------------------------------------------------------------------------
  # Unread count
  # ---------------------------------------------------------------------------

  operation(:unread,
    operation_id: "chat_unread_count",
    summary: "Get unread message count",
    description: "Get the number of unread messages for the current user in a chat conversation.",
    parameters: [
      chat_type: [
        in: :query,
        required: true,
        schema: %Schema{type: :string, enum: ["lobby", "group", "friend", "party"]}
      ],
      chat_ref_id: [
        in: :query,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: [
      ok:
        {"Unread count", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{unread_count: %Schema{type: :integer}}
             }
           }
         }}
    ]
  )

  def unread(conn, params) do
    user_id = conn.assigns[:current_scope].user_id
    chat_type = params["chat_type"]
    chat_ref_id = parse_id(params["chat_ref_id"])

    case authorize_conversation(conn, user_id, chat_type, chat_ref_id) do
      :ok ->
        count =
          if chat_type == "friend" do
            Chat.count_unread_friend(user_id, chat_ref_id)
          else
            Chat.count_unread(user_id, chat_type, chat_ref_id)
          end

        json(conn, %{data: %{unread_count: count}})

      {:error, conn} ->
        conn
    end
  end

  # ---------------------------------------------------------------------------
  # Update own message
  # ---------------------------------------------------------------------------

  operation(:update,
    operation_id: "update_chat_message",
    summary: "Update your own chat message",
    description:
      "Edit the content or metadata of a message you sent. Only the sender can update their own message.",
    parameters: [
      id: [
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid},
        description: "Message ID"
      ]
    ],
    request_body:
      {"Message update", "application/json",
       %Schema{
         type: :object,
         properties: %{
           content: %Schema{type: :string, description: "New message text (1-4096 chars)"},
           metadata: %Schema{type: :object, description: "Optional metadata"}
         }
       }},
    responses: [
      ok: {"Updated message", "application/json", @message_schema},
      not_found: {"Message not found", "application/json", %Schema{type: :object}},
      forbidden: {"Not message sender", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Validation error", "application/json", %Schema{type: :object}}
    ]
  )

  def update(conn, %{"id" => id} = params) do
    user_id = conn.assigns[:current_scope].user_id
    message_id = parse_id(id)

    attrs =
      params
      |> Map.take(["content", "metadata"])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    case Chat.update_message(user_id, message_id, attrs) do
      {:ok, message} ->
        json(conn, serialize_message(message))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", details: changeset_errors(cs)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  # ---------------------------------------------------------------------------
  # Delete own message
  # ---------------------------------------------------------------------------

  operation(:delete,
    operation_id: "delete_chat_message",
    summary: "Delete your own chat message",
    description:
      "Permanently delete a message you sent. Only the sender can delete their own message.",
    parameters: [
      id: [
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid},
        description: "Message ID"
      ]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      not_found: {"Message not found", "application/json", %Schema{type: :object}},
      forbidden: {"Not message sender", "application/json", %Schema{type: :object}}
    ]
  )

  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns[:current_scope].user_id
    message_id = parse_id(id)

    case Chat.delete_own_message(user_id, message_id) do
      {:ok, _message} ->
        json(conn, %{ok: true})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp serialize_message(msg),
    do: Serializers.serialize_chat_message(msg, include_updated_at: true)

  defp authorize_conversation(conn, user_id, chat_type, chat_ref_id) do
    case Chat.authorize_access(user_id, chat_type, chat_ref_id) do
      :ok ->
        :ok

      {:error, reason} when reason in [:invalid_chat_ref, :invalid_chat_type] ->
        {:error, conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})}

      {:error, reason} ->
        {:error, conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})}
    end
  end

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
