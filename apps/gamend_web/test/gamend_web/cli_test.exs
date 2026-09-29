defmodule GamendWeb.CLITest do
  # async: false — changes the working directory.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GamendWeb.CLI

  describe "run/1" do
    test "no command, or help, prints the usage" do
      assert capture_io(fn -> assert CLI.run([]) == 0 end) =~ "Usage: gamend COMMAND"
      assert capture_io(fn -> assert CLI.run(["help"]) == 0 end) =~ "db.migrate"
    end

    test "an unknown command fails with the usage on stderr" do
      output = capture_io(:stderr, fn -> assert CLI.run(["nope"]) == 1 end)

      assert output =~ "unknown command: nope"
      assert output =~ "Usage: gamend COMMAND"
    end

    @tag :tmp_dir
    test "db.seed without a seeds file says so and starts nothing", %{tmp_dir: dir} do
      output = capture_io(fn -> File.cd!(dir, fn -> assert CLI.run(["db.seed"]) == 0 end) end)

      assert output =~ "No seeds file at priv/repo/seeds.exs"
    end

    test "every mix alias the CLI mirrors is documented in the usage" do
      for command <- ~w(db.setup db.migrate db.rollback db.reset db.seed demo.seed plugin.bundle) do
        assert CLI.usage() =~ command
      end
    end
  end

  describe "starter" do
    setup :project

    @tag :tmp_dir
    test "copies a template into the working directory and writes a .env", ctx do
      output = in_project(ctx, fn -> assert CLI.run(["starter", ctx.template]) == 0 end)

      assert File.read!(Path.join(ctx.project, "theme/config.json")) == ~s({"title": "T"})
      assert File.read!(Path.join(ctx.project, ".gitignore")) == ".env\n"
      assert File.read!(Path.join(ctx.project, ".env")) =~ ~r/GAMEND_AUTH_SECRET_KEY_BASE=\S{80,}/
      assert output =~ "created  theme/config.json"
      assert output =~ "created  .env"
    end

    @tag :tmp_dir
    test "never overwrites a file unless --force", ctx do
      File.mkdir_p!(Path.join(ctx.project, "theme"))
      File.write!(Path.join(ctx.project, "theme/config.json"), "mine")
      File.write!(Path.join(ctx.project, ".env"), "GAMEND_AUTH_SECRET_KEY_BASE=mine\n")

      output = in_project(ctx, fn -> CLI.run(["starter", ctx.template]) end)

      assert File.read!(Path.join(ctx.project, "theme/config.json")) == "mine"
      assert File.read!(Path.join(ctx.project, ".env")) == "GAMEND_AUTH_SECRET_KEY_BASE=mine\n"
      assert output =~ "kept     theme/config.json"

      in_project(ctx, fn -> CLI.run(["starter", ctx.template, "--force"]) end)

      assert File.read!(Path.join(ctx.project, "theme/config.json")) == ~s({"title": "T"})
      # --force is about the template's files; the secret is never replaced.
      assert File.read!(Path.join(ctx.project, ".env")) == "GAMEND_AUTH_SECRET_KEY_BASE=mine\n"
    end

    @tag :tmp_dir
    test "adds a secret to an existing .env that has none, keeping the rest", ctx do
      File.write!(Path.join(ctx.project, ".env"), "GAMEND_HTTP_PORT=4001")

      output = in_project(ctx, fn -> CLI.run(["starter", ctx.template]) end)
      env = File.read!(Path.join(ctx.project, ".env"))

      assert env =~ ~r/\AGAMEND_HTTP_PORT=4001\nGAMEND_AUTH_SECRET_KEY_BASE=\S{80,}\n\z/
      assert output =~ "updated  .env"
    end

    @tag :tmp_dir
    test "takes a .tar.gz of a project, unwrapping its top directory", ctx do
      archive = Path.join(ctx.tmp_dir, "site.tar.gz")

      File.cd!(Path.dirname(ctx.template), fn ->
        :ok =
          :erl_tar.create(String.to_charlist(archive), [~c"template"], [:compressed])
      end)

      in_project(ctx, fn -> assert CLI.run(["starter", archive]) == 0 end)

      assert File.read!(Path.join(ctx.project, "theme/config.json")) == ~s({"title": "T"})
      refute File.exists?(Path.join(ctx.project, "template"))
    end

    @tag :tmp_dir
    test "an unknown template fails without touching the project", ctx do
      capture_io(:stderr, fn ->
        in_project(ctx, fn -> assert CLI.run(["starter", "no-such-template"]) == 1 end)
      end)

      assert File.ls!(ctx.project) == []
    end
  end

  defp project(%{tmp_dir: dir}) do
    template = Path.join(dir, "template")
    project = Path.join(dir, "project")

    File.mkdir_p!(Path.join(template, "theme"))
    File.write!(Path.join(template, "theme/config.json"), ~s({"title": "T"}))
    File.write!(Path.join(template, ".gitignore"), ".env\n")
    File.mkdir_p!(project)

    %{template: template, project: project}
  end

  defp in_project(%{project: project}, fun) do
    capture_io(fn -> File.cd!(project, fun) end)
  end
end
