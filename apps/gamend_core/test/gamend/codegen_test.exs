defmodule Gamend.CodegenTest do
  # The generated-file tasks' shared pieces (`Gamend.Codegen`): a `--check`
  # passes on an exact match and fails naming the task to run otherwise, and
  # PO values are quoted the way gettext tools read them back.
  use ExUnit.Case, async: true

  alias Gamend.Codegen

  setup do
    path = Path.join(System.tmp_dir!(), "codegen_#{System.unique_integer([:positive])}.txt")
    on_exit(fn -> File.rm(path) end)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    %{path: path}
  end

  test "a file that holds exactly what is generated is up to date", %{path: path} do
    File.write!(path, "abc")
    assert Codegen.check!(path, ["a", "bc"], "my.task") == :ok
    assert_received {:mix_shell, :info, [message]}
    assert message =~ "up to date"
  end

  test "a stale or missing file fails, naming the task", %{path: path} do
    File.write!(path, "old")

    assert_raise Mix.Error, ~r/out of date\. Run: mix my\.task/, fn ->
      Codegen.check!(path, "new", "my.task")
    end

    File.rm!(path)

    assert_raise Mix.Error, ~r/does not exist\. Run: mix my\.task/, fn ->
      Codegen.check!(path, "new", "my.task")
    end
  end

  test "a one-line value is one quoted string, quotes and backslashes escaped" do
    assert Codegen.quote_po("plain") == ~s("plain")
    assert Codegen.quote_po(~s(say "hi" \\ there)) == ~s("say \\"hi\\" \\\\ there")
  end

  test "a multi-line value is an empty string then one quoted line each" do
    assert Codegen.quote_po("one\ntwo\nthree") ==
             ~s("") <> "\n" <> ~s("one\\n"\n"two\\n"\n"three")
  end
end
