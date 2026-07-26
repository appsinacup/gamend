defmodule GameServerWeb.Api.V1.NotificationController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.Accounts.Scope
  alias GameServer.Accounts.User
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
      icon_url: %Schema{type: :string, description: "Icon URL; empty when unset"},
      metadata: %Schema{type: :object, description: "Arbitrary metadata"},
      inserted_at: %Schema{
        type: :string,
        format: "date-time",
        description: "Timestamp (UTC) when the notification was created"
      }
    },
    example: %{
      id: "0198c0de-0001-7000-8000-000000000001",
      sender_id: "0198c0de-0002-7000-8000-000000000002",
      sender_name: "SomePlayer",
      recipient_id: 7,
      title: "Game invite",
      content: "Join my lobby!",
      icon_url: "",
      metadata: %{"lobby_id" => 10},
      inserted_at: "2026-02-22T12:00:00Z"
    }
  }

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
      ok:
        {"Paginated list of notifications", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @notification_schema},
             meta: %Schema{
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
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      created: {"Notification created", "application/json", @notification_schema},
      bad_request: {"Bad request", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok:
        {"Deleted count", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{
                 deleted: %Schema{type: :integer, description: "Number of notifications deleted"}
               }
             }
           }
         }},
      bad_request: {"Bad request", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  def index(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        {page, page_size} = GameServerWeb.Pagination.params(params)

        notifications =
          Notifications.list_notifications(user.id, page: page, page_size: page_size)

        total_count = Notifications.count_notifications(user.id)

        json(
          conn,
          Pagination.envelope(
            Enum.map(notifications, &Serializers.serialize_notification/1),
            page,
            page_size,
            total_count
          )
        )

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def create(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case Notifications.send_notification(user.id, params) do
          {:ok, notification} ->
            conn
            |> put_status(:created)
            |> json(Serializers.serialize_notification(notification))

          {:error, :missing_recipient} ->
            conn |> put_status(:bad_request) |> json(%{error: "missing_recipient"})

          {:error, :cannot_notify_self} ->
            conn |> put_status(:bad_request) |> json(%{error: "cannot_notify_self"})

          {:error, :not_friends} ->
            conn |> put_status(:bad_request) |> json(%{error: "not_friends"})

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

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
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
        json(conn, %{data: %{deleted: deleted}})

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def delete(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "ids parameter required (array)"})
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
end
