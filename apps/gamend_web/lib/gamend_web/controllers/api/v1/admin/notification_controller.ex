defmodule GamendWeb.Api.V1.Admin.NotificationController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Notifications
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    AnnouncementResponse,
    NotificationPage,
    NotificationResponse,
    OkResponse
  }

  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  require GamendWeb.UrlParam, as: UrlParam

  tags(["Admin – Notifications"])

  operation(:index,
    operation_id: "admin_list_notifications",
    summary: "List all notifications (admin)",
    description:
      "Return all notifications across all users. Supports filtering by recipient user_id, sender_id, and title.",
    security: [%{"authorization" => []}],
    parameters: [
      user_id: [
        in: :query,
        schema: %Schema{type: :string, format: :uuid},
        description: "Filter by recipient user ID",
        required: false
      ],
      sender_id: [
        in: :query,
        schema: %Schema{type: :string, format: :uuid},
        description: "Filter by sender user ID",
        required: false
      ],
      title: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Filter by title (partial match)",
        required: false
      ],
      page: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page number (1-based)",
        required: false
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page size",
        required: false
      ]
    ],
    responses: [
      ok: {"Paginated list of notifications", "application/json", NotificationPage}
    ]
  )

  operation(:create,
    operation_id: "admin_create_notification",
    summary: "Create a notification (admin)",
    description:
      "Create a notification from any sender to any recipient. No friendship check is performed.",
    security: [%{"authorization" => []}],
    request_body: {
      "Notification payload",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          sender_id: %Schema{type: :string, format: :uuid, description: "Sender user ID"},
          recipient_id: %Schema{type: :string, format: :uuid, description: "Recipient user ID"},
          title: %Schema{type: :string, description: "Notification title (required)"},
          content: %Schema{
            type: :string,
            description: "Notification body text (optional)",
            nullable: true
          },
          metadata: %Schema{
            type: :object,
            description: "Arbitrary metadata (optional)",
            nullable: true
          }
        },
        required: [:sender_id, :recipient_id, :title]
      }
    },
    responses: [
      created: {"Notification created", "application/json", NotificationResponse},
      bad_request: Schemas.error("Bad request"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  operation(:announce,
    operation_id: "admin_announce_notification",
    summary: "Send a notification to every player (admin)",
    description:
      "Queues one notification for every activated account that is not banned, in the " <>
        "`announcements` group: always on the site, by phone and email as each player chose " <>
        "for that group. Delivery is asynchronous, in batches. Sending the same title again " <>
        "refreshes each player's earlier row instead of adding a second.",
    security: [%{"authorization" => []}],
    request_body: {
      "Announcement",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          title: %Schema{type: :string, description: "Notification title (required)"},
          content: %Schema{type: :string, description: "Body text (optional)"},
          url: %Schema{
            type: :string,
            description:
              "A path on this site the notification leads to, such as `/news` (optional)"
          },
          site_only: %Schema{
            type: :boolean,
            description: "Only the site's row: no push and no email (default false)"
          }
        },
        required: [:title]
      }
    },
    responses: [
      accepted: {"Queued", "application/json", AnnouncementResponse},
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  operation(:delete,
    operation_id: "admin_delete_notification",
    summary: "Delete a notification (admin)",
    description: "Delete a notification by ID (no ownership check).",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Notification ID"
      ]
    ],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      bad_request: Schemas.error("Not a notification id (invalid_id)"),
      not_found: Schemas.error("Not found")
    ]
  )

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  def index(conn, params) do
    {page, page_size} = GamendWeb.Pagination.params(params)

    filters =
      %{}
      |> maybe_put_filter(UrlParam.user_id(), params["user_id"])
      |> maybe_put_filter(UrlParam.sender_id(), params["sender_id"])
      |> maybe_put_filter(UrlParam.title(), params["title"])

    notifications =
      Notifications.list_all_notifications(filters, page: page, page_size: page_size)

    total_count = Notifications.count_all_notifications(filters)

    reply_page(
      conn,
      Enum.map(notifications, &Serializers.serialize_notification/1),
      page,
      page_size,
      total_count
    )
  end

  def create(conn, params) do
    sender_id = parse_id(params["sender_id"])
    recipient_id = parse_id(params["recipient_id"])

    cond do
      is_nil(sender_id) ->
        reply_error(conn, :bad_request, "missing_param", "sender_id is required")

      is_nil(recipient_id) ->
        reply_error(conn, :bad_request, "missing_param", "recipient_id is required")

      true ->
        case Notifications.admin_create_notification(sender_id, recipient_id, params) do
          {:ok, notification} ->
            reply_data(conn, :created, Serializers.serialize_notification(notification))

          {:error, %Ecto.Changeset{} = cs} ->
            unprocessable(conn, cs)
        end
    end
  end

  def announce(conn, params) do
    case Notifications.announce_to_all(params) do
      {:ok, recipients} -> reply_data(conn, :accepted, %{recipients: recipients})
      {:error, %Ecto.Changeset{} = cs} -> unprocessable(conn, cs)
    end
  end

  def delete(conn, %{"id" => id}) do
    with notification_id when is_binary(notification_id) <- parse_id(id),
         {:ok, _} <- Notifications.admin_delete_notification(notification_id) do
      reply_ok(conn)
    else
      nil -> reply_error(conn, :bad_request, "invalid_id")
      {:error, reason} -> reply_reason(conn, reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
end
