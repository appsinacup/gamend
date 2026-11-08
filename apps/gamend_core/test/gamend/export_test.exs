defmodule Gamend.ExportTest do
  # async: false: it changes where the local storage adapter keeps its files.
  use ExUnit.Case, async: false

  alias Gamend.Export
  alias Gamend.Repo

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    before = Application.get_env(:gamend_core, Gamend.Storage.Local)
    root = Path.join(tmp, "objects")
    Application.put_env(:gamend_core, Gamend.Storage.Local, dir: root)

    on_exit(fn ->
      if before,
        do: Application.put_env(:gamend_core, Gamend.Storage.Local, before),
        else: Application.delete_env(:gamend_core, Gamend.Storage.Local)
    end)

    {:ok, root: root, out: Path.join(tmp, "export"), database: start_database(tmp)}
  end

  describe "the stored files" do
    test "go in files.tar under storage/, whatever the folder is called, and stay",
         %{root: root, out: out} do
      File.mkdir_p!(Path.join(root, "a"))
      File.write!(Path.join(root, "a/one.txt"), "one")

      assert {:ok, written} = Export.write(out)
      assert "files.tar" in written

      assert {:ok, names} = :erl_tar.table(String.to_charlist(Path.join(out, "files.tar")))
      assert ~c"storage/a/one.txt" in names

      assert File.read!(Path.join(root, "a/one.txt")) == "one"
      assert mode(Path.join(out, "files.tar")) == 0o600
      assert File.ls!(out) |> Enum.sort() == Enum.sort(written)
    end

    test "are left out when asked, and when there are none", %{root: root, out: out} do
      assert {:ok, written} = Export.write(out)
      refute "files.tar" in written

      File.mkdir_p!(root)
      File.write!(Path.join(root, "one.txt"), "one")

      assert {:ok, written} = Export.write(out, files: false)
      refute "files.tar" in written
      assert mode(out) == 0o700
    end
  end

  describe "the database" do
    unless Gamend.Export.database?(), do: @describetag(:skip)

    test "is a whole copy, made beside the open database", %{out: out, database: database} do
      Repo.query!("CREATE TABLE things (name TEXT)")
      Repo.query!("INSERT INTO things VALUES ('kept')")

      assert {:ok, ["gamend.db"]} = Export.write(out, files: false)
      assert mode(Path.join(out, "gamend.db")) == 0o600
      refute File.exists?(Path.join(out, "gamend.db.part"))

      copy = start_repo(Path.join(out, "gamend.db"))
      Repo.put_dynamic_repo(copy)
      assert %{rows: [["kept"]]} = Repo.query!("SELECT name FROM things")
      Repo.put_dynamic_repo(database)
    end

    test "a second export replaces the first", %{out: out} do
      assert {:ok, ["gamend.db"]} = Export.write(out, files: false)
      assert {:ok, ["gamend.db"]} = Export.write(out, files: false)
    end
  end

  defp mode(path), do: Bitwise.band(File.stat!(path).mode, 0o777)

  # VACUUM cannot run in the sandbox's transaction: a database of its own.
  defp start_database(tmp) do
    if Export.database?() do
      pid = start_repo(Path.join(tmp, "source.db"))
      Repo.put_dynamic_repo(pid)
      pid
    end
  end

  defp start_repo(path) do
    start_supervised!(
      {Repo, name: nil, database: path, pool: DBConnection.ConnectionPool, pool_size: 1},
      id: path
    )
  end
end
