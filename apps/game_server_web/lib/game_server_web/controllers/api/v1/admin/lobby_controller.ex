defmodule GameServerWeb.Api.V1.Admin.LobbyController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.Lobbies
  alias GameServerWeb.Pagination
  alias GameServerWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Admin – Lobbies"])

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @lobby_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      title: %Schema{type: :string},
      host_id: %Schema{type: :string, format: :uuid, nullable: true},
      host_name: %Schema{type: :string},
      hostless: %Schema{type: :boolean},
      max_users: %Schema{type: :integer},
      is_hidden: %Schema{type: :boolean},
      is_locked: %Schema{type: :boolean},
      is_passworded: %Schema{type: :boolean},
      metadata: %Schema{type: :object},
      slowdown: %Schema{type: :integer, description: "Chat slowdown in seconds (0 = disabled)"},
      spectator_count: %Schema{type: :integer, description: "Number of current spectators"}
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

  operation(:index,
    operation_id: "admin_list_lobbies",
    summary: "List all lobbies (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      title: [in: :query, schema: %Schema{type: :string}, required: false],
      is_hidden: [
        in: :query,
        schema: %Schema{type: :boolean},
        required: false
      ],
      is_locked: [
        in: :query,
        schema: %Schema{type: :boolean},
        required: false
      ],
      has_password: [
        in: :query,
        schema: %Schema{type: :boolean},
        required: false
      ],
      min_users: [in: :query, schema: %Schema{type: :integer}, required: false],
      max_users: [in: :query, schema: %Schema{type: :integer}, required: false],
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: [
      ok:
        {"Lobbies (paginated)", "application/json",
         %Schema{
           type: :object,
           properties: %{data: %Schema{type: :array, items: @lobby_schema}, meta: @meta_schema}
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def index(conn, params) do
    {page, page_size} = GameServerWeb.Pagination.params(params)

    filters =
      %{}
      |> maybe_put_string_filter(:title, params["title"])
      |> maybe_put_bool_filter(:is_hidden, params["is_hidden"])
      |> maybe_put_bool_filter(:is_locked, params["is_locked"])
      |> maybe_put_bool_filter(:has_password, params["has_password"])
      |> maybe_put_int_filter(:min_users, params["min_users"])
      |> maybe_put_int_filter(:max_users, params["max_users"])

    lobbies = Lobbies.list_all_lobbies(filters, page: page, page_size: page_size)
    total_count = Lobbies.count_list_all_lobbies(filters)

    json(conn, %{
      data: Enum.map(lobbies, &serialize_lobby/1),
      meta: Pagination.meta(page, page_size, length(lobbies), total_count)
    })
  end

  operation(:update,
    operation_id: "admin_update_lobby",
    summary: "Update lobby by id (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {
      "Lobby patch",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          title: %Schema{type: :string},
          max_users: %Schema{type: :integer},
          is_hidden: %Schema{type: :boolean},
          is_locked: %Schema{type: :boolean},
          password: %Schema{type: :string},
          metadata: %Schema{type: :object},
          slowdown: %Schema{
            type: :integer,
            description: "Chat slowdown in seconds (0 = disabled)"
          }
        }
      }
    },
    responses: [
      ok:
        {"Lobby", "application/json", %Schema{type: :object, properties: %{data: @lobby_schema}}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", %Schema{type: :object}},
      bad_request: {"Bad request", "application/json", @error_schema}
    ]
  )

  def update(conn, %{"id" => id} = params) do
    case Lobbies.get_lobby(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      lobby ->
        attrs = Map.delete(params, "id")

        case Lobbies.update_lobby(lobby, attrs) do
          {:ok, updated} ->
            json(conn, %{data: serialize_lobby(updated)})

          {:error, %Ecto.Changeset{} = cs} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "validation_failed",
              errors: Ecto.Changeset.traverse_errors(cs, & &1)
            })

          {:error, {:hook_rejected, _}} ->
            conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

          {:error, reason} ->
            conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
        end
    end
  end

  operation(:delete,
    operation_id: "admin_delete_lobby",
    summary: "Delete lobby by id (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def delete(conn, %{"id" => id}) do
    case Lobbies.get_lobby(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      lobby ->
        case Lobbies.delete_lobby(lobby) do
          {:ok, _} ->
            json(conn, %{})

          {:error, {:hook_rejected, _}} ->
            conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

          {:error, %Ecto.Changeset{} = cs} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "validation_failed",
              errors: Ecto.Changeset.traverse_errors(cs, & &1)
            })

          {:error, reason} ->
            conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
        end
    end
  end

  defp serialize_lobby(lobby) do
    Serializers.serialize_lobby(lobby,
      include_passworded: true,
      include_slowdown: true,
      include_spectator_count: true
    )
  end
end
