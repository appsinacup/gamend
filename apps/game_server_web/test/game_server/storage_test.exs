defmodule GameServer.StorageTest do
  use ExUnit.Case, async: false

  alias GameServer.Storage

  setup do
    dir = Path.join(System.tmp_dir!(), "gs_storage_test_#{System.unique_integer([:positive])}")
    old = Application.get_env(:game_server_core, GameServer.Storage.Local)
    Application.put_env(:game_server_core, GameServer.Storage.Local, dir: dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if old, do: Application.put_env(:game_server_core, GameServer.Storage.Local, old)
    end)

    :ok
  end

  test "build_key namespaces by owner, keeps the extension, and randomizes" do
    a = Storage.build_key("avatars", "user-1", "me.PNG")
    b = Storage.build_key("avatars", "user-1", "me.PNG")

    assert String.starts_with?(a, "avatars/user-1/")
    assert String.ends_with?(a, ".png")
    assert a != b
  end

  test "validate_upload enforces content type and size" do
    assert :ok = Storage.validate_upload("image/png", 100)
    assert {:error, :unsupported_content_type} = Storage.validate_upload("application/zip", 100)
    assert {:error, :too_large} = Storage.validate_upload("image/png", 999_999_999)
  end

  test "local put/get/exists/delete round-trip" do
    key = Storage.build_key("avatars", "user-2", "x.png")

    refute Storage.exists?(key)
    assert {:ok, ^key} = Storage.put(key, "BYTES", content_type: "image/png")
    assert Storage.exists?(key)
    assert {:ok, "BYTES"} = Storage.get(key)
    assert :ok = Storage.delete(key)
    refute Storage.exists?(key)
    # deleting a missing key is a no-op
    assert :ok = Storage.delete(key)
  end

  test "url and presigned_upload point at the local endpoints" do
    key = "avatars/user-3/abc.png"
    assert Storage.url(key) =~ "/storage/#{key}"

    assert {:ok, ticket} = Storage.presigned_upload(key, content_type: "image/png")
    assert ticket.method == "PUT"
    assert ticket.key == key
    assert ticket.headers["content-type"] == "image/png"
    assert ticket.url =~ "/storage/upload?key="
  end

  test "path traversal in a key cannot escape the storage root" do
    # A crafted key with .. segments resolves inside the root, not above it.
    key = "avatars/../../etc/passwd"
    assert {:ok, _} = Storage.put(key, "x", [])
    root = Application.get_env(:game_server_core, GameServer.Storage.Local)[:dir]

    # Where an unsanitized join would have landed (above the root) must stay empty.
    # (Constructed from the key so it doesn't accidentally probe a real system
    # file like /etc/passwd, which exists whenever the root is only two dirs deep.)
    escaped = Path.expand(Path.join(root, key))
    refute String.starts_with?(escaped, Path.expand(root) <> "/")
    refute File.exists?(escaped)

    # The bytes are retrievable, and live under the sanitized key inside the root.
    assert {:ok, "x"} = Storage.get(key)
    assert File.exists?(Path.join(root, "avatars/etc/passwd"))
  end

  describe "cache_control/1" do
    test "avatars default to immutable one-year caching" do
      assert Storage.cache_control("avatars/user-1/abc.png") ==
               "public, max-age=31536000, immutable"
    end

    test "entity icons do too — build_key/3 makes their URL content-unique" do
      assert Storage.cache_control("icons/groups/group-1/abc.png") ==
               "public, max-age=31536000, immutable"
    end

    test "everything else revalidates by default" do
      assert Storage.cache_control("uploads/report.pdf") == "public, max-age=0, must-revalidate"
    end

    test "policies and the default are configurable; first prefix wins" do
      old = Application.get_env(:game_server_core, GameServer.Storage, [])

      Application.put_env(
        :game_server_core,
        GameServer.Storage,
        Keyword.merge(old,
          cache_policies: [{"public/", "public, max-age=3600"}],
          default_cache_control: "no-store"
        )
      )

      on_exit(fn -> Application.put_env(:game_server_core, GameServer.Storage, old) end)

      assert Storage.cache_control("public/logo.png") == "public, max-age=3600"
      # the built-in avatars rule is replaced by the override, so it hits default
      assert Storage.cache_control("avatars/u/a.png") == "no-store"
    end
  end
end
