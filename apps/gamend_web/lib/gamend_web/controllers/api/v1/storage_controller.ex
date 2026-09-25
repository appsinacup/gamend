defmodule GamendWeb.Api.V1.StorageController do
  @moduledoc """
  Receives local uploads and serves stored objects.

  For the S3 backend clients upload straight to the bucket via the presigned URL
  and these endpoints are unused; for the local backend the upload ticket points
  `PUT /storage/upload` here.

  ## Why the key is signed

  The key decides both where the object lands and, on the way back out, what
  extension it carries. Deriving it from the query string made it
  client-controlled: an authenticated user could PUT `avatars/<own_id>/x.html`
  and have it served back from our own origin as `text/html`. So the key comes
  from a token `GamendWeb.Uploads` signed when it issued the ticket, and
  `?key=` is only ever a cross-check. Authorization happened at ticket time,
  which is also what lets non-avatar prefixes (entity icons) upload here at all.
  """

  use GamendWeb, :controller

  alias Gamend.Storage
  alias GamendWeb.Uploads

  # Content types this route will name in a response. Everything else is served
  # as an opaque download.
  @servable_types ~w(image/png image/jpeg image/webp image/gif)

  @doc """
  PUT /storage/upload?key=...&token=... — authenticated raw-body upload (local
  backend). Answers `{"ok": true}`: the client already holds the key from its
  ticket, and an S3 presigned PUT answers with no body at all.
  """
  def upload(conn, %{"token" => token} = params) do
    content_type = Uploads.request_content_type(conn)
    max = Gamend.Limits.get(:max_upload_bytes)

    with {:ok, key} <- verify_token(token, params["key"]),
         {:ok, body, conn} <- Uploads.read_full_body(conn, max),
         :ok <- Storage.validate_upload(content_type, byte_size(body)),
         :ok <- verify_magic_bytes(body, content_type),
         :ok <- check_owner_quota(key, byte_size(body)),
         {:ok, ^key} <- Storage.put(key, body, content_type: content_type) do
      reply_ok(conn)
    else
      {:error, :forbidden} ->
        reply_error(conn, :forbidden, "forbidden")

      {:error, :content_mismatch} ->
        reply_error(conn, :unsupported_media_type, "content_mismatch")

      {:error, :too_large} ->
        reply_error(conn, :request_entity_too_large, "too_large")

      {:error, :quota_exceeded} ->
        reply_error(conn, :insufficient_storage, "quota_exceeded")

      {:error, :unsupported_content_type} ->
        reply_error(conn, :unsupported_media_type, "unsupported_content_type")

      _ ->
        reply_error(conn, :bad_request, "upload_failed")
    end
  end

  def upload(conn, _), do: reply_error(conn, :bad_request, "missing_param", "token is required")

  @doc """
  GET /storage/*key — serve a stored object. The local backend serves the
  bytes; any other backend redirects to a signed link (`Storage.url/2` hands
  out this path for a private S3 bucket, since a signed link expires).
  """
  def show(conn, %{"key" => segments}) do
    key = Enum.join(segments, "/")

    cond do
      not publicly_servable?(key) -> reply_error(conn, :not_found, "not_found")
      Storage.adapter() == Storage.Local -> serve_object(conn, key)
      true -> redirect_to_object(conn, key)
    end
  end

  # Cached for half the link's life, so a cached redirect never points at an
  # expired link.
  defp redirect_to_object(conn, key) do
    max_age = div(Storage.signed_url_seconds(), 2)

    conn
    |> put_resp_header("cache-control", "public, max-age=#{max_age}")
    |> redirect(external: Storage.url(key, signed: true))
  end

  # Prefixes this unauthenticated route may serve: `Storage.public_prefixes/0`,
  # `avatars/` and `icons/` unless a host adds its own.
  #
  # It used to serve *any* key in the store. Avatar and icon keys carry 16 bytes
  # of entropy so they are effectively unguessable, but the admin uploader
  # writes operator-chosen keys at any path (`PUT /api/v1/admin/storage/object`,
  # and the admin page advertises "any file type, at any path") — and a
  # hand-written key like `backups/db.sql` is guessable by construction.
  # Everything outside these prefixes is reachable only through the
  # authenticated admin download route.
  defp publicly_servable?(key) do
    Enum.any?(Storage.public_prefixes(), &String.starts_with?(key, &1))
  end

  defp serve_object(conn, key) do
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
          |> serve_type(key)
          |> send_resp(200, data)
        end

      {:error, _} ->
        reply_error(conn, :not_found, "not_found")
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

  # Belt and braces for objects already on disk from before keys were signed, and
  # for anything a future caller writes server-side: this route hands attacker-
  # supplied bytes back from our own origin, so it may only ever label them as an
  # image. Anything else downloads instead of rendering.
  defp serve_type(conn, key) do
    type = MIME.from_path(key)

    if type in @servable_types do
      put_resp_content_type(conn, type)
    else
      conn
      |> put_resp_header("content-disposition", "attachment")
      |> put_resp_content_type("application/octet-stream", nil)
    end
  end

  # Every ticket mints a fresh random key, and only a confirmed one is ever
  # linked to a row - so a client that requests tickets in a loop and uploads to
  # each leaves orphans behind. Cap what one owner can hold under its prefix.
  defp check_owner_quota(key, incoming) do
    %{bytes: used} = Storage.usage(prefix: Path.dirname(key) <> "/")

    if used + incoming > Gamend.Limits.get(:max_upload_bytes_per_owner),
      do: {:error, :quota_exceeded},
      else: :ok
  end

  defp verify_token(token, requested_key) do
    case Phoenix.Token.verify(GamendWeb.Endpoint, Uploads.token_salt(), token,
           max_age: Uploads.token_max_age()
         ) do
      {:ok, key} when requested_key in [nil, key] -> {:ok, key}
      {:ok, _mismatched} -> {:error, :forbidden}
      {:error, _} -> {:error, :forbidden}
    end
  end

  # The declared content type is just a header. Check the bytes actually start
  # like the image they claim to be, so the stored object can never be a
  # different format wearing an image's extension.
  defp verify_magic_bytes(body, content_type) do
    if Storage.sniff_content_type(body) == content_type,
      do: :ok,
      else: {:error, :content_mismatch}
  end
end
