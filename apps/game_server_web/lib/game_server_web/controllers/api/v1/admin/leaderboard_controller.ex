defmodule GameServerWeb.Api.V1.Admin.LeaderboardController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Leaderboards
  alias GameServerWeb.Uploads
  alias OpenApiSpex.Schema

  tags(["Admin – Leaderboards"])

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @leaderboard_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      slug: %Schema{type: :string},
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      icon_url: %Schema{type: :string, description: "Empty when unset"},
      sort_order: %Schema{type: :string, enum: ["desc", "asc"]},
      operator: %Schema{type: :string, enum: ["set", "best", "incr", "decr"]},
      starts_at: %Schema{type: :string, format: "date-time", nullable: true},
      ends_at: %Schema{type: :string, format: "date-time", nullable: true},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    }
  }

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
          sort_order: %Schema{type: :string, enum: ["desc", "asc"]},
          operator: %Schema{type: :string, enum: ["set", "best", "incr", "decr"]},
          starts_at: %Schema{type: :string, format: "date-time"},
          ends_at: %Schema{type: :string, format: "date-time"},
          metadata: %Schema{type: :object}
        },
        required: [:slug, :title]
      }
    },
    responses: [
      ok:
        {"Leaderboard", "application/json",
         %Schema{type: :object, properties: %{data: @leaderboard_schema}}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", %Schema{type: :object}}
    ]
  )

  def create(conn, params) do
    case Leaderboards.create_leaderboard(params) do
      {:ok, lb} ->
        json(conn, %{data: lb})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", errors: Ecto.Changeset.traverse_errors(cs, & &1)})
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
          starts_at: %Schema{type: :string, format: "date-time"},
          ends_at: %Schema{type: :string, format: "date-time"},
          metadata: %Schema{type: :object}
        }
      }
    },
    responses: [
      ok:
        {"Leaderboard", "application/json",
         %Schema{type: :object, properties: %{data: @leaderboard_schema}}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", %Schema{type: :object}}
    ]
  )

  def update(conn, %{"id" => id} = params) do
    with_leaderboard(conn, id, fn leaderboard ->
      case Leaderboards.update_leaderboard(leaderboard, Map.delete(params, "id")) do
        {:ok, lb} -> json(conn, %{data: lb})
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
      ok:
        {"Leaderboard", "application/json",
         %Schema{type: :object, properties: %{data: @leaderboard_schema}}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", %Schema{type: :object}}
    ]
  )

  def end_leaderboard(conn, %{"id" => id}) do
    id = to_string(id)

    case Leaderboards.end_leaderboard(id) do
      {:ok, lb} ->
        json(conn, %{data: lb})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", errors: Ecto.Changeset.traverse_errors(cs, & &1)})
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
      ok: {"Upload ticket", "application/json", %Schema{type: :object}},
      bad_request: {"Unsupported content type", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def icon_upload_url(conn, %{"id" => id} = params) do
    with_leaderboard(conn, id, fn leaderboard ->
      Uploads.ticket(
        conn,
        "icons/leaderboards",
        leaderboard.id,
        "icon",
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
      ok: {"Updated leaderboard", "application/json", %Schema{type: :object}},
      bad_request: {"Object not found", "application/json", @error_schema},
      forbidden: {"Key not owned by this leaderboard", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def set_icon(conn, %{"id" => id} = params) do
    with_leaderboard(conn, id, fn leaderboard ->
      Uploads.confirm(conn, "icons/leaderboards", leaderboard.id, params["key"], fn url ->
        case Leaderboards.update_leaderboard(leaderboard, %{"icon_url" => url}) do
          {:ok, updated} -> json(conn, %{data: updated})
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
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def delete(conn, %{"id" => id}) do
    id = to_string(id)

    case Leaderboards.get_leaderboard(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      leaderboard ->
        case Leaderboards.delete_leaderboard(leaderboard) do
          {:ok, _lb} ->
            json(conn, %{})

          {:error, %Ecto.Changeset{} = cs} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "validation_failed",
              errors: Ecto.Changeset.traverse_errors(cs, & &1)
            })
        end
    end
  end

  defp with_leaderboard(conn, id, fun) do
    case Leaderboards.get_leaderboard(to_string(id)) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
      leaderboard -> fun.(leaderboard)
    end
  end

  defp changeset_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "validation_failed",
      errors: Ecto.Changeset.traverse_errors(changeset, & &1)
    })
  end
end
