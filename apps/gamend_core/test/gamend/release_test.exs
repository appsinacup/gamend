defmodule Gamend.ReleaseTest do
  # async: false — changes the working directory.
  use ExUnit.Case, async: false

  alias Gamend.Release

  describe "seeds_file/0" do
    @describetag :tmp_dir

    test "is the working directory's priv/repo/seeds.exs", %{tmp_dir: dir} do
      path = Path.join(dir, "priv/repo/seeds.exs")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, ":ok")

      assert File.cd!(dir, &Release.seeds_file/0) == path
    end

    test "is nil when the project has none", %{tmp_dir: dir} do
      assert File.cd!(dir, &Release.seeds_file/0) == nil
    end
  end
end
