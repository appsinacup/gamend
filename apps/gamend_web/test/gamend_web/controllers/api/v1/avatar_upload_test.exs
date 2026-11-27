defmodule GamendWeb.Api.V1.AvatarUploadTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Storage.Local
  alias GamendWeb.Auth.Guardian

  # Smallest thing that passes a PNG magic-byte check.
  @png <<0x89, "PNG\r\n", 0x1A, "\n", "rest-of-the-file">>

  setup %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "gs_avatar_test_#{System.unique_integer([:positive])}")
    old = Application.get_env(:gamend_core, Gamend.Storage.Local)
    Application.put_env(:gamend_core, Gamend.Storage.Local, dir: dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if old, do: Application.put_env(:gamend_core, Gamend.Storage.Local, old)
    end)

    user = Gamend.AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)
    authed = put_req_header(conn, "authorization", "Bearer " <> token)
    %{conn: authed, user: user}
  end

  defp ticket(conn, content_type) do
    conn
    |> post("/api/v1/me/avatar/upload_url", %{content_type: content_type})
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp upload_path(key, token) do
    "/api/v1/storage/upload?key=#{URI.encode_www_form(key)}&token=#{URI.encode_www_form(token)}"
  end

  describe "POST /api/v1/me/avatar/upload_url" do
    test "returns a ticket with an owned key", %{conn: conn, user: user} do
      conn = post(conn, "/api/v1/me/avatar/upload_url", %{content_type: "image/png"})
      body = json_response(conn, 200)["data"]

      assert body["method"] == "PUT"
      assert body["key"] =~ "avatars/#{user.id}/"
      assert String.ends_with?(body["key"], ".png")
    end

    test "rejects an unsupported content type", %{conn: conn} do
      conn = post(conn, "/api/v1/me/avatar/upload_url", %{content_type: "application/zip"})
      assert json_response(conn, 400)["error"] == "unsupported_content_type"
    end
  end

  describe "upload → serve → confirm flow" do
    test "uploads via the ticket, serves it, and sets the avatar", %{conn: conn} do
      %{"key" => key, "token" => token} = ticket(conn, "image/png")

      up =
        conn
        |> put_req_header("content-type", "image/png")
        |> put(upload_path(key, token), @png)

      assert json_response(up, 200) == %{"ok" => true}

      # served publicly, with immutable caching + an ETag (avatar keys are
      # content-unique, so the URL changes whenever the image does)
      served = get(build_conn(), "/storage/#{key}")
      assert served.status == 200
      assert served.resp_body == @png
      assert get_resp_header(served, "content-type") == ["image/png; charset=utf-8"]
      assert get_resp_header(served, "cache-control") == ["public, max-age=31536000, immutable"]
      assert [etag] = get_resp_header(served, "etag")

      # revalidating with the ETag returns a bodiless 304
      not_modified =
        build_conn() |> put_req_header("if-none-match", etag) |> get("/storage/#{key}")

      assert not_modified.status == 304
      assert not_modified.resp_body == ""

      # confirm sets profile_url
      confirm = post(conn, "/api/v1/me/avatar", %{key: key})
      body = json_response(confirm, 200)["data"]
      assert body["profile_url"] =~ "/storage/#{key}"
    end

    # What a game client does: the ticket's own url and headers, no session,
    # as it PUTs to an S3 presigned URL; then confirm, and the account reads
    # the picture back. A second picture takes the first one's place.
    test "a client PUTs to the ticket's url with no session, confirms, and GET /me shows it",
         %{conn: conn} do
      put_ticket = fn ->
        %{"url" => url, "method" => "PUT", "headers" => headers, "key" => key} =
          ticket(conn, "image/png")

        assert String.starts_with?(url, "/api/v1/storage/upload?key=")

        up =
          headers
          |> Enum.reduce(build_conn(), fn {name, value}, c -> put_req_header(c, name, value) end)
          |> put(url, @png)

        assert json_response(up, 200) == %{"ok" => true}
        assert json_response(post(conn, "/api/v1/me/avatar", %{key: key}), 200)
        key
      end

      first = put_ticket.()
      assert json_response(get(conn, "/api/v1/me"), 200)["data"]["profile_url"] =~ first

      second = put_ticket.()
      assert json_response(get(conn, "/api/v1/me"), 200)["data"]["profile_url"] =~ second
      assert Gamend.Storage.exists?(second)
      refute Gamend.Storage.exists?(first)
    end

    test "rejects an unsigned key", %{conn: conn, user: user} do
      up =
        conn
        |> put_req_header("content-type", "image/png")
        |> put("/api/v1/storage/upload?key=avatars/#{user.id}/x.png", @png)

      # No `token`, which the upload's operation requires: refused before the action.
      assert json_response(up, 422)["error"] == "validation_failed"
    end

    test "rejects a token that does not match the requested key", %{conn: conn} do
      %{"token" => token} = ticket(conn, "image/png")

      up =
        conn
        |> put_req_header("content-type", "image/png")
        |> put(upload_path("avatars/someone-else/x.png", token), @png)

      assert json_response(up, 403)["error"] == "key_mismatch"
    end

    test "rejects a ticket past its expires_in", %{conn: conn} do
      %{"key" => key, "expires_in" => ttl} = ticket(conn, "image/png")

      token =
        Phoenix.Token.sign(GamendWeb.Endpoint, "storage upload", {key, "image/png"},
          signed_at: System.system_time(:second) - ttl - 1
        )

      up =
        build_conn()
        |> put_req_header("content-type", "image/png")
        |> put(upload_path(key, token), @png)

      assert json_response(up, 403)["error"] == "ticket_expired"
      refute Gamend.Storage.exists?(key)
    end

    # The key carries the ticket's extension, so the bytes must be the
    # ticket's type, even when they are another image.
    test "rejects a content type other than the ticket's", %{conn: conn} do
      %{"key" => key, "token" => token} = ticket(conn, "image/png")

      up =
        build_conn()
        |> put_req_header("content-type", "image/jpeg")
        |> put(upload_path(key, token), <<0xFF, 0xD8, 0xFF, "jpeg">>)

      assert json_response(up, 415)["error"] == "content_type_mismatch"
      refute Gamend.Storage.exists?(key)
    end

    test "rejects a forged token", %{conn: conn, user: user} do
      up =
        conn
        |> put_req_header("content-type", "image/png")
        |> put(upload_path("avatars/#{user.id}/x.html", "not-a-real-token"), @png)

      assert json_response(up, 403)["error"] == "invalid_token"
    end

    # The key is server-chosen, so a client can never land an object under an
    # extension we would serve back as HTML or JavaScript from our own origin.
    test "the ticket key always carries the image extension", %{conn: conn, user: user} do
      for {content_type, ext} <- [
            {"image/png", ".png"},
            {"image/jpeg", ".jpg"},
            {"image/webp", ".webp"},
            {"image/gif", ".gif"}
          ] do
        %{"key" => key} = ticket(conn, content_type)
        assert String.starts_with?(key, "avatars/#{user.id}/")
        assert String.ends_with?(key, ext)
      end
    end

    test "rejects bytes that are not the image they claim to be", %{conn: conn} do
      %{"key" => key, "token" => token} = ticket(conn, "image/png")

      up =
        conn
        |> put_req_header("content-type", "image/png")
        |> put(upload_path(key, token), "<script>alert(document.domain)</script>")

      assert json_response(up, 415)["error"] == "content_mismatch"
      refute Gamend.Storage.exists?(key)
    end

    test "rejects a body over the size cap", %{conn: conn} do
      %{"key" => key, "token" => token} = ticket(conn, "image/png")
      oversized = @png <> :binary.copy("x", Gamend.Limits.get(:max_upload_bytes))

      up =
        conn
        |> put_req_header("content-type", "image/png")
        |> put(upload_path(key, token), oversized)

      assert json_response(up, 413)["error"] == "too_large"
    end

    test "rejects an upload that would push the owner over their storage quota", %{conn: conn} do
      old = Application.get_env(:gamend_core, Gamend.Limits, [])
      Application.put_env(:gamend_core, Gamend.Limits, max_upload_bytes_per_owner: 1)
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.Limits, old) end)

      %{"key" => key, "token" => token} = ticket(conn, "image/png")

      up =
        conn
        |> put_req_header("content-type", "image/png")
        |> put(upload_path(key, token), @png)

      assert json_response(up, 507)["error"] == "quota_exceeded"
      refute Gamend.Storage.exists?(key)
    end

    # Was 400 `upload_failed`: the request was fine, and the disk refused it.
    test "a write the backend refuses answers 503 storage_unavailable", %{conn: conn} do
      %{"key" => key, "token" => token} = ticket(conn, "image/png")
      # A directory where the object would go.
      File.mkdir_p!(Local.path_for(key))

      up =
        conn
        |> put_req_header("content-type", "image/png")
        |> put(upload_path(key, token), @png)

      assert json_response(up, 503)["error"] == "storage_unavailable"
      # Serving that key is a miss, not a backend failure.
      assert json_response(get(build_conn(), "/storage/#{key}"), 404)["error"] == "not_found"
    end

    # Objects written before keys were signed, or by any future server-side
    # caller, must still never come back as a renderable type.
    test "serves a non-image key as an opaque download" do
      {:ok, _} = Gamend.Storage.put("avatars/legacy/x.html", "<h1>hi</h1>")

      served = get(build_conn(), "/storage/avatars/legacy/x.html")

      assert served.status == 200
      assert get_resp_header(served, "content-type") == ["application/octet-stream"]
      assert get_resp_header(served, "content-disposition") == ["attachment"]
    end
  end

  describe "POST /api/v1/me/avatar" do
    test "rejects confirming a key owned by someone else", %{conn: conn} do
      conn = post(conn, "/api/v1/me/avatar", %{key: "avatars/someone-else/x.png"})
      assert json_response(conn, 403)["error"] == "key_not_owned"
    end

    test "rejects confirming a non-existent object", %{conn: conn, user: user} do
      conn = post(conn, "/api/v1/me/avatar", %{key: "avatars/#{user.id}/missing.png"})
      assert json_response(conn, 400)["error"] == "object_not_found"
    end
  end
end
