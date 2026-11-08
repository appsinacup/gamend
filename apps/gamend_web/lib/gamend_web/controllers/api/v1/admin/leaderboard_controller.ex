defmodule GamendWeb.Api.V1.Admin.LeaderboardController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Leaderboards
  alias Gamend.Leaderboards.ScoreOperator
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{LeaderboardResponse, OkResponse, UploadTicketResponse}
  alias GamendWeb.Serializers
  alias GamendWeb.Uploads
  alias OpenApiSpex.Schema

  require GamendWeb.OpenApiFormat, as: OpenApiFormat
  require Gamend.SortDirection, as: SortDirection
  require GamendWeb.UploadName, as: UploadName

  tags(["Admin – Leaderboards"])

  operation(:create,
    operation_id: "admin_create_leaderboard",
    summary: "Create leaderboard (admin)",
    security: [%{"authorization" => []}],
    request_body: {
      "Leaderboard",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          slug: %Schema{type: :string},
          title: %Schema{type: :string},
          description: %Schema{type: :string},
          icon_url: %Schema{type: :string},
          sort_order: %Schema{type: :string, enum: [SortDirection.desc(), SortDirection.asc()]},
          operator: %Schema{
            type: :string,
            enum: ScoreOperator.all()
          },
          starts_at: %Schema{type: :string, format: OpenApiFormat.date_time()},
          ends_at: %Schema{type: :string, format: OpenApiFormat.date_time()},
          metadata: %Schema{type: :object}
        },
        required: [:slug, :title]
      }
    },
    responses: [
      created: {"Leaderboard", "application/json", LeaderboardResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def create(conn, params) do
    case Leaderboards.create_leaderboard(params) do
      {:ok, lb} ->
        reply_data(conn, :created, serialize(lb))

      {:error, %Ecto.Changeset{} = cs} ->
        unprocessable(conn, cs)
    end
  end

  operation(:update,
    operation_id: "admin_update_leaderboard",
    summary: "Update leaderboard (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {
      "Leaderboard patch",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          title: %Schema{type: :string},
          description: %Schema{type: :string},
          icon_url: %Schema{type: :string},
          starts_at: %Schema{type: :string, format: OpenApiFormat.date_time()},
          ends_at: %Schema{type: :string, format: OpenApiFormat.date_time()},
          metadata: %Schema{type: :object}
        }
      }
    },
    responses: [
      ok: {"Leaderboard", "application/json", LeaderboardResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required"),
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def update(conn, %{"id" => id} = params) do
    with_leaderboard(conn, id, fn leaderboard ->
      case Leaderboards.update_leaderboard(leaderboard, Map.delete(params, "id")) do
        {:ok, lb} -> reply_data(conn, serialize(lb))
        {:error, %Ecto.Changeset{} = cs} -> changeset_error(conn, cs)
      end
    end)
  end

  operation(:end_leaderboard,
    operation_id: "admin_end_leaderboard",
    summary: "End leaderboard (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Leaderboard", "application/json", LeaderboardResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required"),
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def end_leaderboard(conn, %{"id" => id}) do
    id = to_string(id)

    case Leaderboards.end_leaderboard(id) do
      {:ok, lb} ->
        reply_data(conn, serialize(lb))

      {:error, :not_found} ->
        reply_error(conn, :not_found, "not_found")

      {:error, %Ecto.Changeset{} = cs} ->
        unprocessable(conn, cs)
    end
  end

  operation(:icon_upload_url,
    operation_id: "admin_leaderboard_icon_upload_url",
    summary: "Request an upload ticket for a leaderboard icon (admin)",
    description: """
    Step one of two. Returns a presigned ticket; PUT the image straight to
    `url`, then POST the returned `key` to the icon endpoint. Bytes never pass
    through the app server.
    """,
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    request_body:
      {"Declared content type", "application/json",
       %Schema{
         type: :object,
         properties: %{content_type: %Schema{type: :string, example: "image/png"}},
         required: [:content_type]
       }},
    responses: [
      ok: {"Upload ticket", "application/json", UploadTicketResponse},
      bad_request: Schemas.error("Unsupported content type"),
      not_found: Schemas.error("Not found")
    ]
  )

  def icon_upload_url(conn, %{"id" => id} = params) do
    with_leaderboard(conn, id, fn leaderboard ->
      Uploads.ticket(
        conn,
        "icons/leaderboards",
        leaderboard.id,
        UploadName.icon(),
        Uploads.content_type(params)
      )
    end)
  end

  operation(:set_icon,
    operation_id: "admin_set_leaderboard_icon",
    summary: "Confirm an uploaded leaderboard icon (admin)",
    description: "Step two: records a previously uploaded object as the icon.",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    request_body:
      {"Uploaded object key", "application/json",
       %Schema{type: :object, properties: %{key: %Schema{type: :string}}, required: [:key]}},
    responses: [
      ok: {"Updated leaderboard", "application/json", LeaderboardResponse},
      bad_request: Schemas.error("Object not found"),
      forbidden: Schemas.error("Key not owned by this leaderboard"),
      not_found: Schemas.error("Not found")
    ]
  )

  def set_icon(conn, %{"id" => id} = params) do
    with_leaderboard(conn, id, fn leaderboard ->
      Uploads.confirm(conn, "icons/leaderboards", leaderboard.id, params["key"], fn url ->
        case Leaderboards.update_leaderboard(leaderboard, %{"icon_url" => url}) do
          {:ok, updated} -> reply_data(conn, serialize(updated))
          {:error, %Ecto.Changeset{} = cs} -> changeset_error(conn, cs)
        end
      end)
    end)
  end

  operation(:delete,
    operation_id: "admin_delete_leaderboard",
    summary: "Delete leaderboard (admin)",
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
    id = to_string(id)

    case Leaderboards.get_leaderboard(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      leaderboard ->
        case Leaderboards.delete_leaderboard(leaderboard) do
          {:ok, _lb} ->
            reply_ok(conn)

          {:error, %Ecto.Changeset{} = cs} ->
            unprocessable(conn, cs)
        end
    end
  end

  defp with_leaderboard(conn, id, fun) do
    case Leaderboards.get_leaderboard(to_string(id)) do
      nil -> reply_error(conn, :not_found, "not_found")
      leaderboard -> fun.(leaderboard)
    end
  end

  defp changeset_error(conn, changeset), do: unprocessable(conn, changeset)

  defp serialize(leaderboard), do: Serializers.serialize_leaderboard(leaderboard)
end
