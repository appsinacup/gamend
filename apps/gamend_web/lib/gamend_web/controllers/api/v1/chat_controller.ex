defmodule GamendWeb.Api.V1.ChatController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Chat
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    ChatMessagePage,
    ChatMessageResponse,
    ChatReadCursorResponse,
    ChatUnreadResponse,
    OkResponse
  }

  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  require Gamend.Chat.ChatType, as: ChatType

  tags(["Chat"])

  # What `Gamend.Chat.authorize_access/3` refuses, for the endpoints that read
  # a conversation.
  @bad_conversation Schemas.error("Bad chat type or id (invalid_chat_type, invalid_chat_ref)")
  @conversation_refused Schemas.error("Not in the group (not_in_group), not friends, or blocked")
  @conversation_not_found Schemas.error("Not in that lobby or party (not_in_lobby, not_in_party)")

  # ---------------------------------------------------------------------------
  # Send message
  # ---------------------------------------------------------------------------

  operation(:send,
    operation_id: "send_chat_message",
    security: [%{"authorization" => []}],
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
             enum: ChatType.all(),
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
      created: {"Message sent", "application/json", ChatMessageResponse},
      bad_request: @bad_conversation,
      forbidden:
        Schemas.error(
          "Not in the group (not_in_group), not friends (not_friends), blocked, muted, " <>
            "or a game hook refused the message (rejected, its words in message)"
        ),
      not_found: Schemas.error("Not in that lobby or party (not_in_lobby, not_in_party)"),
      unprocessable_entity:
        Schemas.error("Validation failed, or the word filter blocked it (blocked_content)"),
      too_many_requests:
        Schemas.error("Slow mode (slowdown) or the daily message cap (chat_daily_limit)")
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

    with :ok <- GamendWeb.RateLimit.check_chat_daily(scope.user_id),
         {:ok, message} <- Chat.send_message(%{user: Scope.user(scope)}, attrs) do
      reply_data(conn, :created, serialize_message(message))
    else
      {:error, :slowdown} ->
        reply_error(conn, :too_many_requests, "slowdown", "You are sending messages too quickly")

      {:error, %Ecto.Changeset{} = cs} ->
        unprocessable(conn, cs)

      {:error, reason} ->
        reply_reason(conn, reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Get single message
  # ---------------------------------------------------------------------------

  operation(:show,
    operation_id: "get_chat_message",
    security: [%{"authorization" => []}],
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
      ok: {"Chat message", "application/json", ChatMessageResponse},
      not_found: Schemas.error("Message not found")
    ]
  )

  def show(conn, %{"id" => id}) do
    message_id = parse_id(id)
    user = Scope.user(conn.assigns.current_scope)

    case Chat.get_message(message_id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      message ->
        if can_access_message?(user, message) do
          reply_data(conn, serialize_message(message))
        else
          reply_error(conn, :not_found, "not_found")
        end
    end
  end

  defp ensure_can_report(conn, message_id) do
    user = Scope.user(conn.assigns.current_scope)

    case Chat.get_message(message_id) do
      nil -> {:error, :not_found}
      message -> if can_access_message?(user, message), do: :ok, else: {:error, :not_found}
    end
  end

  defp can_access_message?(user, message) do
    case message.chat_type do
      ChatType.friend() ->
        message.sender_id == user.id || message.chat_ref_id == user.id

      ChatType.lobby() ->
        user.lobby_id != nil && user.lobby_id == message.chat_ref_id

      ChatType.group() ->
        Gamend.Groups.member?(message.chat_ref_id, user.id)

      ChatType.party() ->
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
    security: [%{"authorization" => []}],
    summary: "List chat messages",
    description:
      "List messages for a lobby, group, party, or friend conversation. Paginated, newest first.",
    parameters: [
      chat_type: [
        in: :query,
        required: true,
        schema: %Schema{
          type: :string,
          enum: ChatType.all()
        },
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
      ok: {"Chat messages", "application/json", ChatMessagePage},
      bad_request: @bad_conversation,
      forbidden: @conversation_refused,
      not_found: @conversation_not_found
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
          if chat_type == ChatType.friend() do
            msgs =
              Chat.list_friend_messages(user_id, chat_ref_id, page: page, page_size: page_size)

            total = Chat.count_friend_messages(user_id, chat_ref_id)
            {msgs, total}
          else
            msgs = Chat.list_messages(chat_type, chat_ref_id, page: page, page_size: page_size)
            total = Chat.count_messages(chat_type, chat_ref_id)
            {msgs, total}
          end

        reply_page(conn, Enum.map(messages, &serialize_message/1), page, page_size, total_count)

      {:error, conn} ->
        conn
    end
  end

  # ---------------------------------------------------------------------------
  # Mark read
  # ---------------------------------------------------------------------------

  operation(:mark_read,
    operation_id: "mark_chat_read",
    security: [%{"authorization" => []}],
    summary: "Mark chat as read",
    description: "Update the read cursor for the current user in a chat conversation.",
    request_body:
      {"Read cursor", "application/json",
       %Schema{
         type: :object,
         required: [:chat_type, :chat_ref_id, :message_id],
         properties: %{
           chat_type: %Schema{
             type: :string,
             enum: ChatType.all()
           },
           chat_ref_id: %Schema{type: :string, format: :uuid},
           message_id: %Schema{type: :string, format: :uuid, description: "Last read message ID"}
         }
       }},
    responses: [
      ok: {"Read cursor updated", "application/json", ChatReadCursorResponse},
      bad_request:
        Schemas.error(
          "Bad chat type or id (invalid_chat_type, invalid_chat_ref) or message id (invalid_message)"
        ),
      forbidden: @conversation_refused,
      not_found:
        Schemas.error(
          "No such message (message_not_found), or not in that lobby or party " <>
            "(not_in_lobby, not_in_party)"
        ),
      unprocessable_entity: Schemas.error("The message is in another chat (message_not_in_chat)")
    ]
  )

  def mark_read(conn, params) do
    user_id = conn.assigns[:current_scope].user_id
    chat_type = params["chat_type"]
    chat_ref_id = parse_id(params["chat_ref_id"])
    message_id = parse_id(params["message_id"])

    case Chat.mark_read(user_id, chat_type, chat_ref_id, message_id) do
      {:ok, cursor} ->
        reply_data(conn, %{
          chat_type: cursor.chat_type,
          chat_ref_id: cursor.chat_ref_id,
          last_read_message_id: cursor.last_read_message_id,
          updated_at: cursor.updated_at
        })

      {:error, :invalid_message} ->
        reply_error(conn, :bad_request, "invalid_message")

      {:error, reason} ->
        reply_reason(conn, reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Unread count
  # ---------------------------------------------------------------------------

  operation(:unread,
    operation_id: "chat_unread_count",
    security: [%{"authorization" => []}],
    summary: "Get unread message count",
    description: "Get the number of unread messages for the current user in a chat conversation.",
    parameters: [
      chat_type: [
        in: :query,
        required: true,
        schema: %Schema{
          type: :string,
          enum: ChatType.all()
        }
      ],
      chat_ref_id: [
        in: :query,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: [
      ok: {"Unread count", "application/json", ChatUnreadResponse},
      bad_request: @bad_conversation,
      forbidden: @conversation_refused,
      not_found: @conversation_not_found
    ]
  )

  def unread(conn, params) do
    user_id = conn.assigns[:current_scope].user_id
    chat_type = params["chat_type"]
    chat_ref_id = parse_id(params["chat_ref_id"])

    case authorize_conversation(conn, user_id, chat_type, chat_ref_id) do
      :ok ->
        count =
          if chat_type == ChatType.friend() do
            Chat.count_unread_friend(user_id, chat_ref_id)
          else
            Chat.count_unread(user_id, chat_type, chat_ref_id)
          end

        reply_data(conn, %{unread_count: count})

      {:error, conn} ->
        conn
    end
  end

  # ---------------------------------------------------------------------------
  # Update own message
  # ---------------------------------------------------------------------------

  operation(:update,
    operation_id: "update_chat_message",
    security: [%{"authorization" => []}],
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
      ok: {"Updated message", "application/json", ChatMessageResponse},
      not_found: Schemas.error("Message not found"),
      forbidden: Schemas.error("Not message sender"),
      unprocessable_entity: Schemas.error("Validation error")
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
        reply_data(conn, serialize_message(message))

      {:error, reason} ->
        reply_reason(conn, reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Delete own message
  # ---------------------------------------------------------------------------

  operation(:delete,
    operation_id: "delete_chat_message",
    security: [%{"authorization" => []}],
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
      ok: {"Deleted", "application/json", OkResponse},
      not_found: Schemas.error("Message not found"),
      forbidden: Schemas.error("Not message sender")
    ]
  )

  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns[:current_scope].user_id
    message_id = parse_id(id)

    case Chat.delete_own_message(user_id, message_id) do
      {:ok, _message} ->
        reply_ok(conn)

      {:error, reason} ->
        reply_reason(conn, reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Report a message
  # ---------------------------------------------------------------------------

  operation(:report,
    operation_id: "report_chat_message",
    summary: "Report a chat message",
    description:
      "Flag a message for moderator review. One report per player per message; " <>
        "capped per day by the `max_chat_reports_per_user_per_day` limit.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid},
        description: "Message ID"
      ]
    ],
    request_body:
      {"Report", "application/json",
       %Schema{
         type: :object,
         properties: %{
           reason: %Schema{type: :string, description: "Why the message is being reported"}
         }
       }},
    responses: [
      ok: {"Reported", "application/json", OkResponse},
      bad_request: Schemas.error("Invalid id or own message"),
      not_found: Schemas.error("Message not found"),
      conflict: Schemas.error("Already reported"),
      too_many_requests: Schemas.error("Daily report limit reached")
    ]
  )

  def report(conn, %{"id" => id} = params) do
    user_id = conn.assigns[:current_scope].user_id
    reason = Map.get(params, "reason") || Map.get(params, :reason)

    case parse_id(id) do
      nil ->
        reply_error(conn, :bad_request, "invalid_id")

      message_id ->
        # Reporting requires being able to read the message.
        #
        # Without this, any user could report any message id in any conversation
        # — including ones they cannot see — and each report alerts admins. The
        # daily quota bounded the volume but not the reach.
        with :ok <- GamendWeb.RateLimit.check_report_daily(user_id),
             :ok <- ensure_can_report(conn, message_id),
             {:ok, _report} <- Chat.report_message(user_id, message_id, reason) do
          reply_ok(conn)
        else
          {:error, :report_daily_limit} ->
            reply_error(conn, :too_many_requests, "report_daily_limit")

          {:error, :not_found} ->
            reply_error(conn, :not_found, "not_found")

          {:error, :own_message} ->
            reply_error(conn, :bad_request, "own_message")

          {:error, :already_reported} ->
            reply_error(conn, :conflict, "already_reported")

          # No catch-all: the clauses above cover everything
          # `check_report_daily/1` and `report_message/3` can return, and
          # dialyzer fails the build on the unreachable branch.
          {:error, %Ecto.Changeset{} = changeset} ->
            unprocessable(conn, changeset)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp serialize_message(msg),
    do: Serializers.serialize_chat_message(msg, include_updated_at: true)

  defp authorize_conversation(conn, user_id, chat_type, chat_ref_id) do
    case Chat.authorize_access(user_id, chat_type, chat_ref_id) do
      :ok -> :ok
      {:error, reason} -> {:error, reply_reason(conn, reason)}
    end
  end
end
