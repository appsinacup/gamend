defmodule GameServerWeb.Api.V1.Admin.StorageController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Storage
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  tags(["Admin – Storage"])

  @object_schema %Schema{
    type: :object,
    properties: %{
      key: %Schema{type: :string},
      size: %Schema{type: :integer},
      last_modified: %Schema{type: :string, format: "date-time", nullable: true}
    }
  }

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  operation(:index,
    operation_id: "admin_list_storage_objects",
    summary: "List stored objects with usage (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      prefix: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
    ],
    responses: [
      ok:
        {"Objects", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @object_schema},
             usage: %Schema{
               type: :object,
               properties: %{count: %Schema{type: :integer}, bytes: %Schema{type: :integer}}
             },
             meta: %Schema{type: :object}
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def index(conn, params) do
    {page, page_size} = GameServerWeb.Pagination.params(params)
    prefix = params["prefix"] || ""
    offset = (page - 1) * page_size

    objects = Storage.list_objects(prefix: prefix, offset: offset, limit: page_size)
    usage = Storage.usage(prefix: prefix)

    json(conn, %{
      data: Enum.map(objects, &serialize/1),
      usage: usage,
      meta: Pagination.meta(page, page_size, length(objects), usage.count)
    })
  end

  operation(:delete,
    operation_id: "admin_delete_storage_object",
    summary: "Delete a stored object (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      key: [in: :query, schema: %Schema{type: :string}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      bad_request: {"Missing key / delete failed", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def delete(conn, %{"key" => key}) when is_binary(key) and key != "" do
    case Storage.delete(key) do
      :ok -> json(conn, %{ok: true, key: key})
      {:error, _} -> conn |> put_status(:bad_request) |> json(%{error: "delete_failed"})
    end
  end

  def delete(conn, _), do: conn |> put_status(:bad_request) |> json(%{error: "missing_key"})

  operation(:upload,
    operation_id: "admin_upload_storage_object",
    summary: "Upload or overwrite an object at any key (admin)",
    security: [%{"authorization" => []}],
    parameters: [key: [in: :query, schema: %Schema{type: :string}, required: true]],
    request_body:
      {"Raw file bytes", "application/octet-stream", %Schema{type: :string, format: :binary}},
    responses: [
      ok: {"Uploaded", "application/json", %Schema{type: :object}},
      bad_request: {"Missing key / upload failed", "application/json", @error_schema},
      request_entity_too_large: {"Too large", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def upload(conn, %{"key" => key}) when is_binary(key) and key != "" do
    content_type = request_content_type(conn)

    with {:ok, body, conn} <- read_full_body(conn, GameServer.Limits.get(:max_upload_bytes)),
         {:ok, ^key} <- Storage.put(key, body, content_type: content_type) do
      json(conn, %{ok: true, key: key})
    else
      {:error, :too_large} ->
        conn |> put_status(:request_entity_too_large) |> json(%{error: "too_large"})

      _ ->
        conn |> put_status(:bad_request) |> json(%{error: "upload_failed"})
    end
  end

  def upload(conn, _), do: conn |> put_status(:bad_request) |> json(%{error: "missing_key"})

  operation(:download,
    operation_id: "admin_download_storage_object",
    summary: "Download an object by key (admin)",
    security: [%{"authorization" => []}],
    parameters: [key: [in: :query, schema: %Schema{type: :string}, required: true]],
    responses: [
      ok: {"Object bytes", "application/octet-stream", %Schema{type: :string, format: :binary}},
      not_found: {"Not found", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def download(conn, %{"key" => key}) when is_binary(key) and key != "" do
    case Storage.get(key) do
      {:ok, data} ->
        conn
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_content_type(MIME.from_path(key))
        |> send_resp(200, data)

      {:error, _} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  def download(conn, _), do: conn |> put_status(:bad_request) |> json(%{error: "missing_key"})

  defp request_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [ct | _] -> ct |> String.split(";") |> hd() |> String.trim()
      [] -> "application/octet-stream"
    end
  end

  defp read_full_body(conn, max) do
    case read_body(conn, length: max + 1) do
      {:ok, body, conn} when byte_size(body) <= max -> {:ok, body, conn}
      {:ok, _body, _conn} -> {:error, :too_large}
      {:more, _partial, _conn} -> {:error, :too_large}
      {:error, _} = err -> err
    end
  end

  defp serialize(obj) do
    %{
      key: obj.key,
      size: obj.size,
      last_modified: obj.last_modified && DateTime.to_iso8601(obj.last_modified)
    }
  end
end
