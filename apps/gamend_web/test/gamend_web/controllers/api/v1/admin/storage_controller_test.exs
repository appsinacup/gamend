defmodule GamendWeb.Api.V1.Admin.StorageControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts.User
  alias Gamend.Repo
  alias Gamend.Storage
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "gs_admin_storage_#{System.unique_integer([:positive])}")
    old = Application.get_env(:gamend_core, Gamend.Storage.Local)
    Application.put_env(:gamend_core, Gamend.Storage.Local, dir: dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if old, do: Application.put_env(:gamend_core, Gamend.Storage.Local, old)
    end)

    admin = Gamend.AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    {:ok, token, _} = Guardian.encode_and_sign(admin)
    %{conn: put_req_header(conn, "authorization", "Bearer " <> token)}
  end

  test "requires admin", %{conn: _conn} do
    user = Gamend.AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)
    conn = build_conn() |> put_req_header("authorization", "Bearer " <> token)
    assert json_response(get(conn, "/api/v1/admin/storage"), 403)
  end

  test "lists objects with usage + meta", %{conn: conn} do
    Storage.put("avatars/a/1.png", "xx", content_type: "image/png")
    Storage.put("avatars/b/2.png", "xxxx", content_type: "image/png")

    body = json_response(get(conn, "/api/v1/admin/storage"), 200)

    assert body["meta"]["total_count"] == 2

    usage = json_response(get(conn, "/api/v1/admin/storage/usage"), 200)["data"]
    assert usage == %{"count" => 2, "bytes" => 6}
    assert length(body["data"]) == 2
    assert body["meta"]["total_count"] == 2
    assert Enum.all?(body["data"], &Map.has_key?(&1, "key"))
  end

  test "filters by prefix", %{conn: conn} do
    Storage.put("avatars/a/1.png", "x", content_type: "image/png")
    Storage.put("uploads/admin/x.png", "x", content_type: "image/png")

    body = json_response(get(conn, "/api/v1/admin/storage?prefix=avatars/"), 200)
    assert body["meta"]["total_count"] == 1

    usage = json_response(get(conn, "/api/v1/admin/storage/usage?prefix=avatars/"), 200)["data"]
    assert usage["count"] == 1
    assert hd(body["data"])["key"] == "avatars/a/1.png"
  end

  test "deletes an object", %{conn: conn} do
    Storage.put("avatars/a/1.png", "x", content_type: "image/png")
    assert Storage.exists?("avatars/a/1.png")

    assert json_response(delete(conn, "/api/v1/admin/storage?key=avatars/a/1.png"), 200) ==
             %{"ok" => true}

    refute Storage.exists?("avatars/a/1.png")
  end

  test "uploads to an arbitrary key and downloads it back", %{conn: conn} do
    key = "custom/path/notes.txt"

    up =
      conn
      |> put_req_header("content-type", "text/plain")
      |> put("/api/v1/admin/storage/object?key=#{URI.encode_www_form(key)}", "ADMIN BYTES")

    assert %{"key" => ^key, "size" => _} = json_response(up, 201)["data"]
    assert Storage.exists?(key)

    down = get(conn, "/api/v1/admin/storage/object?key=#{URI.encode_www_form(key)}")
    assert down.status == 200
    assert down.resp_body == "ADMIN BYTES"
    assert get_resp_header(down, "content-type") |> hd() =~ "text/plain"
  end

  test "download of a missing key is 404", %{conn: conn} do
    assert json_response(get(conn, "/api/v1/admin/storage/object?key=nope/x.txt"), 404)
  end

  test "a key below an object is not there, not a backend failure", %{conn: conn} do
    Storage.put("custom/a.txt", "x")

    assert %{"error" => "not_found"} =
             json_response(get(conn, "/api/v1/admin/storage/object?key=custom/a.txt/b.txt"), 404)
  end

  # Each was a 400 (`delete_failed`, `upload_failed`): the request was fine,
  # and the disk refused it.
  describe "a backend that fails" do
    test "a delete answers 503 storage_unavailable", %{conn: conn} do
      # A directory where the object would be: the disk refuses to unlink it.
      Storage.put("custom/dir/inner.txt", "x")

      assert %{"error" => "storage_unavailable"} =
               json_response(delete(conn, "/api/v1/admin/storage?key=custom/dir"), 503)

      assert Storage.exists?("custom/dir/inner.txt")
    end

    test "an upload answers 503 storage_unavailable", %{conn: conn} do
      # A file where a directory of the key should be.
      Storage.put("custom/a.txt", "x")

      conn =
        conn
        |> put_req_header("content-type", "text/plain")
        |> put("/api/v1/admin/storage/object?key=custom/a.txt/b.txt", "BYTES")

      assert %{"error" => "storage_unavailable"} = json_response(conn, 503)
    end
  end

  test "each action without a key answers 400 missing_param", %{conn: conn} do
    assert %{"error" => "missing_param"} =
             json_response(delete(conn, "/api/v1/admin/storage"), 400)

    assert %{"error" => "missing_param"} =
             json_response(get(conn, "/api/v1/admin/storage/object"), 400)

    up =
      conn
      |> put_req_header("content-type", "text/plain")
      |> put("/api/v1/admin/storage/object", "BYTES")

    assert %{"error" => "missing_param"} = json_response(up, 400)
  end
end
