defmodule GamendWeb.BrotliCompressorTest do
  @moduledoc """
  `mix phx.digest` calls the compressor once per asset, and anything it raises
  aborts the digest, so `mix assets.deploy` fails with it. Every way brotli can
  fail has to come back as `:error`, which keeps the gzip and moves on.

  The missing-binary case swaps `PATH` for an empty directory, which is global
  to the VM: the module is not async, and `PATH` comes back before the test ends.
  """
  use ExUnit.Case, async: false

  alias GamendWeb.BrotliCompressor

  @brotli System.find_executable("brotli")
  @needs_brotli if(@brotli, do: false, else: "brotli is not on PATH")

  # Repetitive enough that brotli always wins over the original.
  @asset String.duplicate("export function hello(name) { return `hello ${name}`; }\n", 200)

  describe "compress_file/2" do
    @tag :tmp_dir
    test "keeps the gzip when brotli is not on PATH", %{tmp_dir: empty_dir} do
      before = leftover_tmp_files()

      assert without_path(empty_dir, fn ->
               BrotliCompressor.compress_file("app.js", @asset)
             end) == :error

      assert leftover_tmp_files() == before
    end

    test "skips a file whose extension is not gzippable" do
      assert BrotliCompressor.compress_file("logo.png", @asset) == :error
    end

    @tag skip: @needs_brotli
    test "writes a brotli copy that decompresses to the original" do
      before = leftover_tmp_files()

      assert {:ok, compressed} = BrotliCompressor.compress_file("app.js", @asset)
      assert byte_size(compressed) < byte_size(@asset)
      assert leftover_tmp_files() == before

      path =
        Path.join(
          System.tmp_dir!(),
          "brotli_compressor_test_#{System.unique_integer([:positive])}.br"
        )

      try do
        File.write!(path, compressed)
        assert {@asset, 0} = System.cmd(@brotli, ["-d", "-c", path])
      after
        File.rm(path)
      end
    end

    @tag skip: @needs_brotli
    test "keeps the gzip when brotli output is no smaller than the input" do
      assert BrotliCompressor.compress_file("tiny.js", "a") == :error
    end
  end

  defp without_path(dir, fun) do
    original = System.get_env("PATH")
    System.put_env("PATH", dir)

    try do
      fun.()
    after
      System.put_env("PATH", original)
    end
  end

  defp leftover_tmp_files do
    System.tmp_dir!()
    |> Path.join("gamend_brotli_*")
    |> Path.wildcard()
    |> Enum.sort()
  end
end
