defmodule GameServerWeb.Api.V1.AvatarUploadTest do
  use GameServerWeb.ConnCase, async: false

  alias GameServerWeb.Auth.Guardian

  setup %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "gs_avatar_test_#{System.unique_integer([:positive])}")
    old = Application.get_env(:game_server_core, GameServer.Storage.Local)
    Application.put_env(:game_server_core, GameServer.Storage.Local, dir: dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if old, do: Application.put_env(:game_server_core, GameServer.Storage.Local, old)
    end)

    user = GameServer.AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)
    authed = put_req_header(conn, "authorization", "Bearer " <> token)
    %{conn: authed, user: user}
  end

  describe "POST /api/v1/me/avatar/upload_url" do
    test "returns a ticket with an owned key", %{conn: conn, user: user} do
      conn = post(conn, "/api/v1/me/avatar/upload_url", %{content_type: "image/png"})
      body = json_response(conn, 200)

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
    test "uploads to an owned key, serves it, and sets the avatar", %{conn: conn, user: user} do
      key = "avatars/#{user.id}/pic.png"

      up =
        conn
        |> put_req_header("content-type", "image/png")
        |> put("/api/v1/storage/upload?key=#{URI.encode_www_form(key)}", "PNGBYTES")

      assert json_response(up, 200)["key"] == key

      # served publicly, with immutable caching + an ETag (avatar keys are
      # content-unique, so the URL changes whenever the image does)
      served = get(build_conn(), "/storage/#{key}")
      assert served.status == 200
      assert served.resp_body == "PNGBYTES"
      assert get_resp_header(served, "cache-control") == ["public, max-age=31536000, immutable"]
      assert [etag] = get_resp_header(served, "etag")

      # revalidating with the ETag returns a bodiless 304
      not_modified =
        build_conn() |> put_req_header("if-none-match", etag) |> get("/storage/#{key}")

      assert not_modified.status == 304
      assert not_modified.resp_body == ""

      # confirm sets profile_url
      confirm = post(conn, "/api/v1/me/avatar", %{key: key})
      body = json_response(confirm, 200)
      assert body["profile_url"] =~ "/storage/#{key}"
    end

    test "rejects uploading to a key owned by someone else", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "image/png")
        |> put("/api/v1/storage/upload?key=avatars/someone-else/x.png", "X")

      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end

  describe "POST /api/v1/me/avatar" do
    test "rejects confirming a key owned by someone else", %{conn: conn} do
      conn = post(conn, "/api/v1/me/avatar", %{key: "avatars/someone-else/x.png"})
      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "rejects confirming a non-existent object", %{conn: conn, user: user} do
      conn = post(conn, "/api/v1/me/avatar", %{key: "avatars/#{user.id}/missing.png"})
      assert json_response(conn, 400)["error"] == "object_not_found"
    end
  end
end
