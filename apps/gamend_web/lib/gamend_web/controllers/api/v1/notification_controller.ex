defmodule GamendWeb.Api.V1.NotificationController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Notifications
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{DeletedCountResponse, NotificationPage, NotificationResponse}
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Notifications"])

  operation(:index,
    operation_id: "list_notifications",
    summary: "List own notifications",
    description:
      "Return all undeleted notifications for the authenticated user, ordered oldest-first. Supports pagination.",
    security: [%{"authorization" => []}],
    parameters: [
      page: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page number (1-based)",
        required: false
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page size (max results per page)",
        required: false
      ]
    ],
    responses: [
      ok: {"Paginated list of notifications", "application/json", NotificationPage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:create,
    operation_id: "send_notification",
    summary: "Send a notification to a friend",
    description:
      "Send a notification to an accepted friend. The recipient will receive it in real-time (if connected) and it persists until deleted.",
    security: [%{"authorization" => []}],
    request_body: {
      "Notification payload",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          user_id: %Schema{
            type: :string,
            format: :uuid,
            description: "Recipient user ID (must be an accepted friend)"
          },
          title: %Schema{type: :string, description: "Notification title (required)"},
          content: %Schema{
            type: :string,
            description: "Notification body text (optional)",
            nullable: true
          },
          icon_url: %Schema{
            type: :string,
            description: "Icon URL (optional)",
            nullable: true
          },
          metadata: %Schema{
            type: :object,
            description: "Arbitrary metadata (optional)",
            nullable: true
          }
        },
        required: [:user_id, :title]
      }
    },
    responses: [
      created: {"Notification created", "application/json", NotificationResponse},
      bad_request:
        Schemas.error("No recipient (missing_recipient), or yourself (cannot_notify_self)"),
      forbidden:
        Schemas.error(
          "Not friends (not_friends), or the recipient's inbox is full (too_many_notifications)"
        ),
      unprocessable_entity: Schemas.error("Validation failed"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:delete,
    operation_id: "delete_notifications",
    summary: "Delete notifications by IDs",
    description:
      "Delete one or more notifications belonging to the authenticated user. Pass an array of notification IDs.",
    security: [%{"authorization" => []}],
    request_body: {
      "Notification IDs to delete",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          ids: %Schema{
            type: :array,
            items: %Schema{type: :integer},
            description: "Array of notification IDs to delete"
          }
        },
        required: [:ids]
      }
    },
    responses: [
      ok: {"Deleted count", "application/json", DeletedCountResponse},
      bad_request: Schemas.error("Bad request"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  def index(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        {page, page_size} = Pagination.params(params)

        notifications =
          Notifications.list_notifications(user.id, page: page, page_size: page_size)

        total_count = Notifications.count_notifications(user.id)

        reply_page(
          conn,
          Enum.map(notifications, &Serializers.serialize_notification/1),
          page,
          page_size,
          total_count
        )

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def create(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case Notifications.send_notification(user.id, params) do
          {:ok, notification} ->
            reply_data(conn, :created, Serializers.serialize_notification(notification))

          {:error, %Ecto.Changeset{} = cs} ->
            unprocessable(conn, cs)

          {:error, reason} ->
            reply_reason(conn, reason)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def delete(conn, %{"ids" => ids}) when is_list(ids) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        int_ids =
          ids
          |> Enum.map(&parse_id/1)
          |> Enum.reject(&is_nil/1)

        {deleted, _} = Notifications.delete_notifications(user.id, int_ids)
        reply_data(conn, %{deleted: deleted})

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def delete(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "ids is required (an array)")
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
end
