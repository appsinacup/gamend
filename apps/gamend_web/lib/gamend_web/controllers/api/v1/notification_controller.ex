defmodule GamendWeb.Api.V1.NotificationController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.ControllerScope
  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Notifications
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    DeletedCountResponse,
    FreeForm,
    NotificationPage,
    NotificationResponse,
    NotificationsReadResponse,
    UnreadCountResponse
  }

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
          metadata:
            FreeForm.metadata(
              description: "Arbitrary metadata (optional)",
              nullable: true
            )
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
            items: %Schema{type: :string, format: :uuid},
            description: "Array of notification IDs to delete"
          }
        },
        required: [:ids]
      }
    },
    responses: [
      ok: {"Deleted count", "application/json", DeletedCountResponse},
      bad_request:
        Schemas.error("No ids (missing_param), or more than an inbox holds (too_many_ids)"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:mark_read,
    operation_id: "mark_notifications_read",
    summary: "Mark notifications read by IDs",
    description:
      "Mark one or more of the authenticated user's notifications read. Others' ids and those " <>
        "already read are skipped. The user's connections hear `notifications_read` with the " <>
        "ids marked and the unread count.",
    security: [%{"authorization" => []}],
    request_body: {
      "Notification IDs to mark read",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          ids: %Schema{
            type: :array,
            items: %Schema{type: :string, format: :uuid},
            description: "Array of notification IDs to mark read"
          }
        },
        required: [:ids]
      }
    },
    responses: [
      ok: {"Marked, and the unread count", "application/json", NotificationsReadResponse},
      bad_request:
        Schemas.error("No ids (missing_param), or more than an inbox holds (too_many_ids)"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:mark_all_read,
    operation_id: "mark_all_notifications_read",
    summary: "Mark every notification read",
    description:
      "Mark all of the authenticated user's notifications read, as opening the site's " <>
        "notifications page does. The user's connections hear `notifications_read`.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Marked, and the unread count", "application/json", NotificationsReadResponse},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:unread_count,
    operation_id: "count_unread_notifications",
    summary: "Count unread notifications",
    description:
      "How many of the authenticated user's notifications are unread: the count on the " <>
        "site's account button.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Unread count", "application/json", UnreadCountResponse},
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
    with_ids(conn, ids, fn user, ids ->
      {deleted, _} = Notifications.delete_notifications(user.id, ids)
      reply_data(conn, %{deleted: deleted})
    end)
  end

  def delete(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "ids is required (an array)")
  end

  def mark_read(conn, %{"ids" => ids}) when is_list(ids) do
    with_ids(conn, ids, &reply_read(conn, Notifications.mark_notifications_read(&1.id, &2)))
  end

  def mark_read(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "ids is required (an array)")
  end

  def mark_all_read(conn, _params),
    do: with_user(conn, &reply_read(conn, Notifications.mark_all_notifications_read(&1.id)))

  def unread_count(conn, _params) do
    with_user(conn, fn user ->
      reply_data(conn, %{unread_count: Notifications.count_unread_notifications(user.id)})
    end)
  end

  defp reply_read(conn, {marked, unread}),
    do: reply_data(conn, %{marked: marked, unread_count: unread})

  # The signed-in user and the ids they name, those that are ids; more than
  # an inbox holds (`max_notifications_per_user`) is refused, so one
  # statement never binds an unbounded list.
  defp with_ids(conn, ids, fun) do
    with_user(conn, fn user ->
      if length(ids) > Gamend.Limits.get(:max_notifications_per_user),
        do: reply_error(conn, :bad_request, "too_many_ids"),
        else: fun.(user, ids |> Enum.map(&parse_id/1) |> Enum.reject(&is_nil/1))
    end)
  end
end
