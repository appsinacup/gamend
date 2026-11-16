defmodule Gamend.StorageLocalDirTest do
  @moduledoc """
  Where the local adapter puts objects.

  This resolved two different ways: the declared setting said `priv/storage`,
  while the code fell back to the *application's* priv directory. Inside a
  release that second path is a versioned directory a deploy replaces, so
  mirrored avatars vanished while the URLs in the database kept pointing at
  them — the admin storage page showed zero objects and nobody could see why.
  """

  use ExUnit.Case, async: false

  alias Gamend.Settings
  alias Gamend.Storage.Local

  setup do
    previous = Application.get_env(:gamend_core, Local)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, Local, previous),
        else: Application.delete_env(:gamend_core, Local)
    end)

    :ok
  end

  test "with nothing configured, the directory is the declared default" do
    Application.delete_env(:gamend_core, Local)

    assert Local.root_dir() == Settings.get(Local, :dir),
           "the code default and the documented default must be the same path"
  end

  test "objects written anywhere under the root are listed, not just top level" do
    dir = Path.join(System.tmp_dir!(), "gs_storage_#{System.unique_integer([:positive])}")
    Application.put_env(:gamend_core, Local, dir: dir)
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, _} = Gamend.Storage.put("avatars/user-1/deep/avatar.png", "bytes")

    keys = Gamend.Storage.list_objects() |> Enum.map(& &1.key)

    assert "avatars/user-1/deep/avatar.png" in keys,
           "a nested object must appear in the admin listing"

    assert Gamend.Storage.usage().count == 1
  end
end
