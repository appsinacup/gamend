defmodule GameServerWeb.Api.V1.StorageController do
  @moduledoc """
  Receives local uploads and serves stored objects.

  For the S3 backend clients upload straight to the bucket via the presigned URL
  and these endpoints are unused; for the local backend the upload ticket points
  `PUT /storage/upload` here. Either way a client may only write keys under its
  own id (`avatars/<user_id>/...`).
  """

  use GameServerWeb, :controller

  alias GameServer.Accounts.Scope
  alias GameServer.Storage

  @doc "PUT /storage/upload?key=... — authenticated raw-body upload (local backend)."
  def upload(conn, %{"key" => key}) do
    user = Scope.user(conn.assigns.current_scope)
    content_type = request_content_type(conn)
    max = GameServer.Limits.get(:max_upload_bytes)

    with :ok <- authorize_key(user, key),
         {:ok, body, conn} <- read_full_body(conn, max),
         :ok <- Storage.validate_upload(content_type, byte_size(body)),
         {:ok, ^key} <- Storage.put(key, body, content_type: content_type) do
      json(conn, %{ok: true, key: key})
    else
      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :too_large} ->
        conn |> put_status(:request_entity_too_large) |> json(%{error: "too_large"})

      {:error, :unsupported_content_type} ->
        conn |> put_status(:unsupported_media_type) |> json(%{error: "unsupported_content_type"})

      _ ->
        conn |> put_status(:bad_request) |> json(%{error: "upload_failed"})
    end
  end

  def upload(conn, _), do: conn |> put_status(:bad_request) |> json(%{error: "missing_key"})

  @doc "GET /storage/*key — serve a stored object (local backend)."
  def show(conn, %{"key" => segments}) do
    key = Enum.join(segments, "/")

    case Storage.get(key) do
      {:ok, data} ->
        etag = etag_for(data)

        conn =
          conn
          |> put_resp_header("cache-control", Storage.cache_control(key))
          |> put_resp_header("etag", etag)

        if if_none_match_hit?(conn, etag) do
          send_resp(conn, 304, "")
        else
          conn
          |> put_resp_header("x-content-type-options", "nosniff")
          |> put_resp_content_type(MIME.from_path(key))
          |> send_resp(200, data)
        end

      {:error, _} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  # Strong ETag over the bytes. Lets revalidated (mutable) objects return a cheap
  # 304; immutable-cached objects (avatars) rarely revalidate at all.
  defp etag_for(data), do: ~s("#{:crypto.hash(:md5, data) |> Base.encode16(case: :lower)}")

  defp if_none_match_hit?(conn, etag) do
    case get_req_header(conn, "if-none-match") do
      [value | _] -> etag in String.split(value, ~r/\s*,\s*/)
      [] -> false
    end
  end

  # A client may only write objects under its own namespace.
  defp authorize_key(user, key) do
    if String.starts_with?(key, "avatars/#{user.id}/"), do: :ok, else: {:error, :forbidden}
  end

  defp request_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [ct | _] -> ct |> String.split(";") |> hd() |> String.trim()
      [] -> ""
    end
  end

  # Reads one byte past the cap so an oversized body is detected without buffering
  # the whole thing. Image bodies pass the endpoint parser unparsed (`pass: */*`).
  defp read_full_body(conn, max) do
    case read_body(conn, length: max + 1) do
      {:ok, body, conn} when byte_size(body) <= max -> {:ok, body, conn}
      {:ok, _body, _conn} -> {:error, :too_large}
      {:more, _partial, _conn} -> {:error, :too_large}
      {:error, _} = err -> err
    end
  end
end
