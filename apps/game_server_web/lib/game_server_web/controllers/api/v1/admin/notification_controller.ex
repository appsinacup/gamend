defmodule GameServerWeb.Api.V1.Admin.NotificationController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.Notifications
  alias GameServerWeb.Pagination
  alias GameServerWeb.Serializers
  alias OpenApiSpex.Schema

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @notification_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Notification ID"},
      sender_id: %Schema{type: :string, format: :uuid, description: "User ID of the sender"},
      sender_name: %Schema{type: :string, description: "Display name of the sender"},
      recipient_id: %Schema{type: :string, format: :uuid, description: "User ID of the recipient"},
      title: %Schema{type: :string, description: "Notification title"},
      content: %Schema{type: :string, description: "Notification body text"},
      metadata: %Schema{type: :object, description: "Arbitrary metadata"},
      inserted_at: %Schema{
        type: :string,
        format: "date-time",
        description: "Timestamp (UTC) when the notification was created"
      }
    }
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
      ok:
        {"Paginated list of notifications", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @notification_schema},
             meta: @meta_schema
           }
         }}
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
      created: {"Notification created", "application/json", @notification_schema},
      bad_request: {"Bad request", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", @error_schema}
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
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  def index(conn, params) do
    {page, page_size} = GameServerWeb.Pagination.params(params)

    filters =
      %{}
      |> maybe_put_filter("user_id", params["user_id"])
      |> maybe_put_filter("sender_id", params["sender_id"])
      |> maybe_put_filter("title", params["title"])

    notifications =
      Notifications.list_all_notifications(filters, page: page, page_size: page_size)

    total_count = Notifications.count_all_notifications(filters)
    count = length(notifications)

    json(conn, %{
      data: Enum.map(notifications, &Serializers.serialize_notification/1),
      meta: Pagination.meta(page, page_size, count, total_count)
    })
  end

  def create(conn, params) do
    sender_id = parse_id(params["sender_id"])
    recipient_id = parse_id(params["recipient_id"])

    cond do
      is_nil(sender_id) ->
        conn |> put_status(:bad_request) |> json(%{error: "sender_id is required"})

      is_nil(recipient_id) ->
        conn |> put_status(:bad_request) |> json(%{error: "recipient_id is required"})

      true ->
        case Notifications.admin_create_notification(sender_id, recipient_id, params) do
          {:ok, notification} ->
            conn
            |> put_status(:created)
            |> json(Serializers.serialize_notification(notification))

          {:error, %Ecto.Changeset{} = cs} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "validation_failed",
              errors:
                Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
                  Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
                    opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
                  end)
                end)
            })

          {:error, reason} ->
            conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    notification_id = parse_id(id)

    case Notifications.admin_delete_notification(notification_id) do
      {:ok, _} ->
        json(conn, %{})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, _} ->
        conn |> put_status(:bad_request) |> json(%{error: "delete_failed"})
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
end
