defmodule GamendWeb.ProjectStaticTest do
  @moduledoc """
  A project's static overlay: which directories it is, which file a URL path
  resolves to, and that the endpoint and the `?v=` hashes agree with it.

  Not async: the overlay is resolved from the working directory and a setting,
  both global, and cached in `:persistent_term`.
  """
  use GamendWeb.ConnCase, async: false

  alias GamendWeb.ProjectStatic
  alias GamendWeb.SRI

  setup do
    previous = Application.get_env(:gamend_core, Gamend.ContentSettings)
    ProjectStatic.reset()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, Gamend.ContentSettings, previous),
        else: Application.delete_env(:gamend_core, Gamend.ContentSettings)

      ProjectStatic.reset()
    end)

    :ok
  end

  defp put_static_dirs(dirs) do
    settings = Application.get_env(:gamend_core, Gamend.ContentSettings, [])

    Application.put_env(
      :gamend_core,
      Gamend.ContentSettings,
      Keyword.put(settings, :static_dirs, dirs)
    )

    ProjectStatic.reset()
  end

  defp write!(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end

  # A file in the app's own priv/static, the stand-in for what the engine ships.
  defp write_builtin!(rel, content) do
    path = write!(Path.join(Application.app_dir(:gamend_web, "priv/static"), rel), content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp unique(name), do: "#{System.unique_integer([:positive])}-#{name}"

  describe "dirs/0 with the default GAMEND_CONTENT_STATIC_DIRS" do
    @describetag :tmp_dir

    test "static/ then priv/static/ in the working directory", %{tmp_dir: tmp} do
      File.mkdir_p!(Path.join(tmp, "static"))
      File.mkdir_p!(Path.join(tmp, "priv/static"))

      dirs = File.cd!(tmp, fn -> ProjectStatic.dirs() end)

      assert dirs == [Path.join(tmp, "static"), Path.join(tmp, "priv/static")]
    end

    test "only the directories that exist", %{tmp_dir: tmp} do
      File.mkdir_p!(Path.join(tmp, "priv/static"))

      assert File.cd!(tmp, fn -> ProjectStatic.dirs() end) == [Path.join(tmp, "priv/static")]
    end

    test "none at all is an empty overlay", %{tmp_dir: tmp} do
      assert File.cd!(tmp, fn -> ProjectStatic.dirs() end) == []
    end

    test "resolved once: a directory created later waits for a reset", %{tmp_dir: tmp} do
      File.cd!(tmp, fn ->
        assert ProjectStatic.dirs() == []
        File.mkdir_p!("static")
        assert ProjectStatic.dirs() == []

        ProjectStatic.reset()
        assert ProjectStatic.dirs() == [Path.join(tmp, "static")]
      end)
    end

    test "priv/static that is the app's own priv is skipped", %{tmp_dir: tmp} do
      # What `mix phx.server` from the repository root sees: `priv/static` in the
      # working directory and the host app's static dir are one directory, the
      # second reached through `_build`'s priv symlink.
      File.mkdir_p!(Path.join(tmp, "priv"))

      :ok =
        File.ln_s(Application.app_dir(:gamend_web, "priv/static"), Path.join(tmp, "priv/static"))

      assert File.cd!(tmp, fn -> ProjectStatic.dirs() end) == []
    end
  end

  describe "dirs/0 with GAMEND_CONTENT_STATIC_DIRS set" do
    @describetag :tmp_dir

    test "is the listed directories that exist, in order, instead of the default", %{
      tmp_dir: tmp
    } do
      for dir <- ~w(static public assets), do: File.mkdir_p!(Path.join(tmp, dir))
      put_static_dirs(["public", "missing", "assets"])

      assert File.cd!(tmp, fn -> ProjectStatic.dirs() end) ==
               [Path.join(tmp, "public"), Path.join(tmp, "assets")]
    end

    test "naming the app's own priv/static serves nothing twice" do
      put_static_dirs([Application.app_dir(:gamend_web, "priv/static")])

      assert ProjectStatic.dirs() == []
    end
  end

  describe "path_for/1" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp} do
      overlay = Path.join(tmp, "overlay")
      File.mkdir_p!(overlay)
      put_static_dirs([overlay])
      %{overlay: overlay}
    end

    test "the overlay wins over the built-in file at the same path", %{overlay: overlay} do
      name = unique("pic.png")
      builtin = write_builtin!("images/" <> name, "engine")
      own = write!(Path.join(overlay, "images/" <> name), "project")

      assert ProjectStatic.path_for("/images/" <> name) == own
      assert ProjectStatic.lookup("/images/#{name}?v=1") == {overlay, own}

      File.rm!(own)
      assert ProjectStatic.path_for("/images/" <> name) == builtin
    end

    test "a built-in file is found when the overlay does not have it" do
      name = unique("only-builtin.png")
      builtin = write_builtin!("images/" <> name, "engine")

      assert ProjectStatic.path_for("/images/" <> name) == builtin
      assert ProjectStatic.overlay_path_for("/images/" <> name) == nil
    end

    test "never assets/, nor a top-level entry outside :host_static_paths", %{overlay: overlay} do
      write!(Path.join(overlay, "assets/js/app.js"), "shadow")
      write!(Path.join(overlay, "secrets/key.txt"), "no")

      refute ProjectStatic.path_for("/assets/js/app.js") ==
               Path.join(overlay, "assets/js/app.js")

      assert ProjectStatic.path_for("/secrets/key.txt") == nil
      refute ProjectStatic.overlay_servable?("/assets/js/app.js")
      assert ProjectStatic.overlay_servable?("/images/anything.png")
    end

    test "an absolute URL, a data: URI or a climbing path is never a local file", %{
      overlay: overlay
    } do
      write!(Path.join(overlay, "images/x.png"), "x")

      assert ProjectStatic.path_for("/images/x.png")
      assert ProjectStatic.path_for("https://cdn.example.com/images/x.png") == nil
      assert ProjectStatic.path_for("//cdn.example.com/images/x.png") == nil
      assert ProjectStatic.path_for("data:image/png;base64,AAAA") == nil
      assert ProjectStatic.path_for("/images/../images/x.png") == nil
      assert ProjectStatic.path_for("") == nil
      assert ProjectStatic.path_for(nil) == nil
    end

    test "a derived file only counts from its original's directory", %{overlay: overlay} do
      name = unique("banner")
      write_builtin!("images/#{name}.webp", "engine art")
      write_builtin!("images/#{name}-480.webp", "engine art, smaller")

      assert ProjectStatic.derived_from?("/images/#{name}-480.webp", "/images/#{name}.webp")

      write!(Path.join(overlay, "images/#{name}.webp"), "project art")

      refute ProjectStatic.derived_from?("/images/#{name}-480.webp", "/images/#{name}.webp")
    end
  end

  describe "the endpoint" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp} do
      overlay = Path.join(tmp, "overlay")
      File.mkdir_p!(overlay)
      put_static_dirs([overlay])
      %{overlay: overlay}
    end

    test "serves the project's file over the built-in one, cached like it", %{
      conn: conn,
      overlay: overlay
    } do
      name = unique("served.png")
      write_builtin!("images/" <> name, "engine")
      write!(Path.join(overlay, "images/" <> name), "project")

      conn = get(conn, "/images/" <> name)

      assert response(conn, 200) == "project"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end

    test "serves a project-only file, and the game build revalidates", %{
      conn: conn,
      overlay: overlay
    } do
      name = unique("index.pck")
      write!(Path.join(overlay, "game/" <> name), "build")

      conn = get(conn, "/game/" <> name)

      assert response(conn, 200) == "build"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=0, must-revalidate"]
    end

    test "crawler files keep revalidating", %{conn: conn, overlay: overlay} do
      write!(Path.join(overlay, "robots.txt"), "User-agent: *\nDisallow: /\n")

      conn = get(conn, "/robots.txt")

      assert response(conn, 200) =~ "Disallow: /"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=0, must-revalidate"]
    end

    test "the project's app-association file is served as JSON", %{conn: conn, overlay: overlay} do
      write!(Path.join(overlay, ".well-known/apple-app-site-association"), ~s({"project":1}))

      conn = get(conn, "/.well-known/apple-app-site-association")

      assert response(conn, 200) == ~s({"project":1})
      assert [content_type | _] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/json"
    end

    test "never serves assets/, which stays the engine's", %{conn: conn, overlay: overlay} do
      name = unique("y.css")
      write!(Path.join(overlay, "assets/" <> name), "body{}")

      conn = get(conn, "/assets/" <> name)

      assert conn.status == 404
      refute conn.resp_body == "body{}"
    end
  end

  describe "SRI" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp} do
      overlay = Path.join(tmp, "overlay")
      File.mkdir_p!(overlay)
      put_static_dirs([overlay])
      %{overlay: overlay}
    end

    test "?v= hashes the project's file, not the engine's at the same path", %{
      overlay: overlay
    } do
      name = unique("logo.png")
      write_builtin!("images/" <> name, "engine")
      write!(Path.join(overlay, "images/" <> name), "project")

      project_hash = :crypto.hash(:sha384, "project") |> Base.encode64()

      assert SRI.versioned_path("/images/" <> name) ==
               "/images/#{name}?" <> URI.encode_query(%{"v" => project_hash})
    end

    test "no integrity for a path the overlay can answer", %{overlay: overlay} do
      # The endpoint checks the overlay on every request while the hash is
      # cached, so an integrity would block a file edited or added later.
      name = unique("theme.css")
      write!(Path.join(overlay, "images/" <> name), "a{}")

      assert SRI.integrity("/images/" <> name) == nil
      assert SRI.versioned_path("/images/" <> name) =~ "?v="
    end

    test "a path with no file anywhere is linked as written" do
      name = unique("gone.webp")

      assert SRI.versioned_path("/images/" <> name) == "/images/" <> name
      assert SRI.integrity("/images/" <> name) == nil
    end
  end
end
