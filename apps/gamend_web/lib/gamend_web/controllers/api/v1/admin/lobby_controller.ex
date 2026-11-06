defmodule GamendWeb.Api.V1.Admin.LobbyController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Lobbies
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{LobbyPage, LobbyResponse, OkResponse}
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Admin – Lobbies"])

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
      ok: {"Lobbies (paginated)", "application/json", LobbyPage},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def index(conn, params) do
    {page, page_size} = GamendWeb.Pagination.params(params)

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

    reply_page(conn, Enum.map(lobbies, &serialize_lobby/1), page, page_size, total_count)
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
      ok: {"Lobby", "application/json", LobbyResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required, or a game hook refused it (rejected)"),
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def update(conn, %{"id" => id} = params) do
    case Lobbies.get_lobby(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      lobby ->
        attrs = Map.delete(params, "id")

        case Lobbies.update_lobby(lobby, attrs) do
          {:ok, updated} ->
            reply_data(conn, serialize_lobby(updated))

          {:error, %Ecto.Changeset{} = cs} ->
            unprocessable(conn, cs)

          # A game hook's veto is 403 `rejected`; a lobby deleted since it was
          # read is 404 `not_found`.
          {:error, reason} ->
            reply_reason(conn, reason)
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
      ok: {"Deleted", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required"),
      not_found: Schemas.error("Not found")
    ]
  )

  def delete(conn, %{"id" => id}) do
    case Lobbies.get_lobby(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      lobby ->
        case Lobbies.delete_lobby(lobby) do
          {:ok, _} ->
            reply_ok(conn)

          {:error, {:hook_rejected, reason}} ->
            reply_rejected(conn, reason)

          # Deleted since it was read.
          {:error, :not_found} ->
            reply_error(conn, :not_found, "not_found")
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
