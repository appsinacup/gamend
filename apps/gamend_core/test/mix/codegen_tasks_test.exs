defmodule Mix.Tasks.CodegenTasksTest do
  # The tasks that write generated files (`.env.example`, the settings guide,
  # the theme catalogue), run as CI runs them, from the umbrella root, in
  # `--check` mode: nothing is written, and each passes when its file is what
  # it would generate. Their `-o` path writes a fresh copy, which then checks
  # clean. And `gamend.api.lint --list` names every rule.
  use ExUnit.Case, async: false

  @root Path.expand("../../../..", __DIR__)

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp run(task, args), do: File.cd!(@root, fn -> Mix.Task.rerun(task, args) end)

  defp info do
    receive do
      {:mix_shell, :info, [message]} -> message
    after
      0 -> nil
    end
  end

  test "settings.env_example: written to a path, that path checks clean" do
    out = Path.join(System.tmp_dir!(), "env_example_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(out) end)

    run("gamend.settings.env_example", ["-o", out])
    assert info() =~ "wrote #{out}"
    assert File.read!(out) =~ "GAMEND_"

    run("gamend.settings.env_example", ["--check", "-o", out])
    assert info() =~ "up to date"
  end

  test "settings.env_example: a stale file fails the check, naming the task" do
    out = Path.join(System.tmp_dir!(), "env_example_stale_#{System.unique_integer([:positive])}")
    File.write!(out, "# stale\n")
    on_exit(fn -> File.rm(out) end)

    assert_raise Mix.Error, ~r/out of date|gamend\.settings\.env_example/, fn ->
      run("gamend.settings.env_example", ["--check", "-o", out])
    end
  end

  test "settings.guide: written to a path, that path checks clean" do
    out = Path.join(System.tmp_dir!(), "settings_guide_#{System.unique_integer([:positive])}.md")
    on_exit(fn -> File.rm(out) end)

    run("gamend.settings.guide", ["-o", out])
    assert File.read!(out) =~ "GAMEND_"
    run("gamend.settings.guide", ["--check", "-o", out])
    assert Enum.any?([info(), info()], &(&1 && &1 =~ "up to date"))
  end

  test "api.lint --list names every rule" do
    run("gamend.api.lint", ["--list"])
    messages = Stream.repeatedly(&info/0) |> Enum.take_while(& &1) |> Enum.join("\n")
    assert messages =~ "R1-null-string"
    assert messages =~ "R17-boundary-raise"
  end
end
