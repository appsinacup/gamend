defmodule GamendWeb.Api.V1.StorageController do
  @moduledoc """
  Receives local uploads and serves stored objects.

  For the S3 backend clients upload straight to the bucket via the presigned URL
  and these endpoints are unused; for the local backend the upload ticket points
  at `PUT /api/v1/storage/upload` here.

  ## Why the ticket is signed

  The key decides both where the object lands and, on the way back out, what
  extension it carries. Deriving it from the query string made it
  client-controlled: a user could PUT `avatars/<own_id>/x.html` and have it
  served back from our own origin as `text/html`. So the key and the content
  type come from a token `GamendWeb.Uploads` signed when it issued the ticket,
  and `?key=` is only ever a cross-check. Authorization happened at ticket
  time, so the token is all this route takes, as an S3 presigned URL is: no
  session, which also lets non-avatar prefixes (entity icons) upload here.
  """

  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Storage
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.OkResponse
  alias GamendWeb.Uploads
  alias OpenApiSpex.Schema

  # Content types this route will name in a response. Everything else is served
  # as an opaque download.
  @servable_types ~w(image/png image/jpeg image/webp image/gif)

  # What an upload is refused for, each its own code (`GamendWeb.ErrorStatus`).
  @refusals ~w(ticket_expired key_mismatch content_type_mismatch content_mismatch too_large
               quota_exceeded)a

  tags(["Storage"])

  operation(:upload,
    operation_id: "storage_upload",
    summary: "Upload a file's bytes to an upload ticket (local storage)",
    description:
      "The URL an upload ticket names when storage is local: the client PUTs the raw " <>
        "bytes there with the ticket's `content-type`, and the ticket's `token` is all " <>
        "it takes, as an S3 presigned URL is (no session). Then the ticket's confirm " <>
        "call records the key. An S3 backend's ticket names the bucket instead.",
    parameters: [
      token: [
        in: :query,
        schema: %Schema{type: :string},
        required: true,
        description: "The ticket's signed token; it names the key and the content type"
      ],
      key: [
        in: :query,
        schema: %Schema{type: :string},
        description: "The ticket's key, a cross-check of the token's"
      ]
    ],
    request_body:
      {"Raw file bytes", "application/octet-stream", %Schema{type: :string, format: :binary}},
    responses: [
      ok: {"Stored", "application/json", OkResponse},
      bad_request: Schemas.error("No token (missing_param)"),
      forbidden:
        Schemas.error(
          "Not a ticket this server signed (invalid_token), past its expires_in " <>
            "(ticket_expired), or `key` is not the ticket's (key_mismatch)"
        ),
      request_entity_too_large: Schemas.error("Over the upload cap (too_large)"),
      unsupported_media_type:
        Schemas.error(
          "Sent as another content type than the ticket's (content_type_mismatch), or the " <>
            "bytes are not that type (content_mismatch)"
        ),
      insufficient_storage: Schemas.error("The owner's quota is full (quota_exceeded)"),
      service_unavailable: Schemas.error("The storage backend failed (storage_unavailable)")
    ]
  )

  # A browser route, the object's own URL: not part of the API document.
  operation(:show, false)

  @doc """
  PUT /api/v1/storage/upload?key=...&token=... — a local ticket's raw-body
  upload, authorized by the token alone. Answers `{"ok": true}`: the client
  already holds the key from its ticket, and an S3 presigned PUT answers with
  no body at all. Each refusal has its own code, so a client can say which.
  """
  def upload(conn, %{"token" => token} = params) do
    with {:ok, {key, content_type}} <- Uploads.verify_ticket(token),
         :ok <- same_key(key, params["key"]),
         :ok <- same_content_type(Uploads.request_content_type(conn), content_type),
         {:ok, body, conn} <- Uploads.read_full_body(conn, Gamend.Limits.get(:max_upload_bytes)),
         :ok <- verify_magic_bytes(body, content_type),
         :ok <- check_owner_quota(key, byte_size(body)),
         {:ok, ^key} <- Storage.put(key, body, content_type: content_type) do
      reply_ok(conn)
    else
      # A ticket this server did not sign; a provider's `invalid_token` is a 400.
      {:error, :invalid_token} ->
        reply_error(conn, :forbidden, "invalid_token")

      {:error, reason} when reason in @refusals ->
        reply_reason(conn, reason)

      # Every check before it is answered above: this is the write failing.
      {:error, reason} ->
        Uploads.storage_unavailable(conn, reason)
    end
  end

  def upload(conn, _params),
    do: reply_error(conn, :bad_request, "missing_param", "token is required")

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
  # Not *any* key in the store. Avatar and icon keys carry 16 bytes
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

      {:error, :not_found} ->
        reply_error(conn, :not_found, "not_found")

      {:error, reason} ->
        Uploads.storage_unavailable(conn, reason)
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

  # `?key=` is optional, and when given it must be the ticket's own.
  defp same_key(key, requested) when requested in [nil, key], do: :ok
  defp same_key(_key, _requested), do: {:error, :key_mismatch}

  # The ticket named one content type, and its key that type's extension. A
  # media type is the same in any case.
  defp same_content_type(sent, ticket) do
    if String.downcase(sent) == ticket, do: :ok, else: {:error, :content_type_mismatch}
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
