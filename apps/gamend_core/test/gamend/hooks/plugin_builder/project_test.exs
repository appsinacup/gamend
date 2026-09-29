defmodule Gamend.Hooks.PluginBuilder.ProjectTest do
  use ExUnit.Case, async: true

  alias Gamend.Hooks.PluginBuilder.Project

  @moduletag :tmp_dir

  defp read(tmp_dir, source) do
    dir = Path.join(tmp_dir, "my_plugin")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "mix.exs"), source)
    Project.read(dir)
  end

  test "reads the literals a plugin's mix.exs declares, without running it", %{tmp_dir: tmp_dir} do
    {:ok, project} =
      read(tmp_dir, """
      defmodule MyPlugin.MixProject do
        use Mix.Project

        @version "1.2.3"
        # Evaluating this file would raise; reading it must not.
        raise "evaluated"

        def project do
          [
            app: :my_plugin,
            version: System.get_env("APP_VERSION") || @version,
            elixirc_paths: elixirc_paths(Mix.env()),
            deps: deps()
          ]
        end

        def application do
          [
            mod: {MyPlugin.Application, []},
            extra_applications: [:logger, :crypto],
            env: [hooks_module: Gamend.Modules.MyPlugin, greeting: "hi", limits: %{max: 3}]
          ]
        end

        defp elixirc_paths(:test), do: ["lib", "test/support"]
        defp elixirc_paths(_), do: ["lib", "gen"]

        defp deps do
          [
            shared_dep(:gamend_sdk, "../sdk"),
            {:phoenix, "~> 1.8"},
            {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
            {:bunt, "~> 1.0", optional: true}
          ]
        end

        defp shared_dep(app, path), do: {app, path: path, runtime: false}
      end
      """)

    assert project.app == :my_plugin
    assert project.version == "1.2.3"
    assert project.elixirc_paths == ["lib", "gen"]
    assert project.extra_applications == [:logger, :crypto]
    assert project.mod == {MyPlugin.Application, []}
    assert project.hooks_module == Gamend.Modules.MyPlugin
    assert project.env == [greeting: "hi", limits: %{max: 3}]
    assert project.warnings == []

    assert Enum.map(project.deps, &{&1.name, &1.runtime?, &1.prod?, &1.optional?}) == [
             {:gamend_sdk, true, true, false},
             {:phoenix, true, true, false},
             {:credo, false, false, false},
             {:bunt, true, true, true}
           ]
  end

  test "falls back, and says so, where a value is not a literal", %{tmp_dir: tmp_dir} do
    {:ok, project} =
      read(tmp_dir, """
      defmodule MyPlugin.MixProject do
        use Mix.Project

        def project do
          [app: String.to_atom("x"), version: version(), elixirc_paths: paths()]
        end

        def application, do: [env: [hooks_module: Module.concat(["A"])]]

        defp version, do: File.read!("VERSION")
        defp paths, do: Enum.map(["lib"], & &1)
      end
      """)

    assert project.app == :my_plugin
    assert project.version == "0.0.0"
    assert project.elixirc_paths == ["lib"]
    assert project.hooks_module == nil
    assert length(project.warnings) == 4
  end

  test "a string hooks_module becomes a module", %{tmp_dir: tmp_dir} do
    {:ok, project} =
      read(tmp_dir, """
      defmodule P.MixProject do
        def project, do: [app: :my_plugin]
        def application, do: [env: [hooks_module: "Elixir.Gamend.Modules.P"]]
      end
      """)

    assert project.hooks_module == Gamend.Modules.P
  end

  test "a file that does not parse is an error", %{tmp_dir: tmp_dir} do
    assert {:error, message} = read(tmp_dir, "defmodule P do\n  def project, do: [\nend\n")
    assert message =~ "mix.exs"
  end
end
