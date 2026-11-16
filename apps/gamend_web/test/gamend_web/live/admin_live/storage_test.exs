defmodule GamendWeb.AdminLive.StorageTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.Repo
  alias Gamend.Storage

  setup %{conn: conn} do
    dir =
      Path.join(System.tmp_dir!(), "gs_admin_storage_live_#{System.unique_integer([:positive])}")

    old = Application.get_env(:gamend_core, Gamend.Storage.Local)
    Application.put_env(:gamend_core, Gamend.Storage.Local, dir: dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if old, do: Application.put_env(:gamend_core, Gamend.Storage.Local, old)
    end)

    admin = Gamend.AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    %{conn: log_in_user(conn, admin)}
  end

  test "lists an object with the adapter it is on, and deletes it", %{conn: conn} do
    Storage.put("avatars/a/1.png", "xx", content_type: "image/png")
    {:ok, view, html} = live(conn, "/admin/storage")
    assert html =~ "Local disk"
    assert html =~ "avatars/a/1.png"

    view |> element(~s(button[phx-value-key="avatars/a/1.png"])) |> render_click()

    refute Storage.exists?("avatars/a/1.png")
    refute render(view) =~ "avatars/a/1.png"
  end

  test "prefix filter narrows the list", %{conn: conn} do
    Storage.put("avatars/a/1.png", "x", content_type: "image/png")
    Storage.put("uploads/admin/x.png", "x", content_type: "image/png")

    {:ok, view, _html} = live(conn, "/admin/storage")
    html = view |> form("#storage-filter-form", %{prefix: "uploads/"}) |> render_change()

    assert html =~ "uploads/admin/x.png"
    refute html =~ "avatars/a/1.png"
  end

  test "uploads a non-image file to a custom path", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/storage")

    file =
      file_input(view, "#storage-upload-form", :object, [
        %{name: "notes.txt", content: "hello", type: "text/plain"}
      ])

    render_upload(file, "notes.txt")
    view |> form("#storage-upload-form", %{path: "docs/notes.txt"}) |> render_submit()

    assert {:ok, "hello"} = Storage.get("docs/notes.txt")
  end
end
