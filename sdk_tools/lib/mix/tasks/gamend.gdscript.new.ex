defmodule Mix.Tasks.Gamend.Gdscript.New do
  use Mix.Task

  @shortdoc "Scaffolds a GDScript hooks plugin"

  @moduledoc """
  Creates a plugin whose hooks are written in GDScript.

      mix gamend.gdscript.new my_game

  Produces a directory that already compiles and loads:

      my_game/
        scripts/my_game.gd    # write hooks here
        gen/                  # generated Elixir, committed
        mix.exs               # hooks_module already wired
        .formatter.exs
        .gitignore

  Then:

      cd my_game
      mix deps.get
      mix bundle

  and copy the directory into the server's plugin directory (`modules/plugins/`
  by default, or wherever `GAMEND_CONTENT_PLUGINS_DIR` points).
  """

  alias Gamend.GDScript

  @scripts "scripts"

  @impl true
  def run(args) do
    {opts, rest, _invalid} = OptionParser.parse(args, strict: [sdk_path: :string])

    name =
      case rest do
        [name] -> name
        _ -> Mix.raise("usage: mix gamend.gdscript.new <plugin_name>")
      end

    unless name =~ ~r/^[a-z][a-z0-9_]*$/ do
      Mix.raise("plugin name must be lower_snake_case, got #{inspect(name)}")
    end

    if File.exists?(name), do: Mix.raise("#{name}/ already exists")

    module = GDScript.default_module("#{name}.gd")

    File.mkdir_p!(Path.join(name, @scripts))
    write(Path.join([name, @scripts, "#{name}.gd"]), script(module))
    write(Path.join(name, "mix.exs"), mix_exs(name, module, opts))
    write(Path.join(name, ".formatter.exs"), formatter())
    write(Path.join(name, ".gitignore"), gitignore())

    Mix.shell().info("""

    Created #{name}/. Next:

        cd #{name}
        mix deps.get
        mix bundle
    """)
  end

  defp write(path, contents) do
    File.write!(path, contents)
    Mix.shell().info("* creating #{path}")
  end

  defp script(module) do
    """
    # Hooks for #{module}, written in GDScript.
    #
    # `mix bundle` compiles this to gen/ and then to BEAM bytecode -- nothing is
    # interpreted at run time. Unsupported syntax is a compile error naming the
    # line, never a surprise later.

    func after_user_register(user):
    \tvar bonus = 100

    \tif user.metadata:
    \t\tbonus += 50

    \t# `opts({...})` spells a keyword list; without it the argument is a map.
    \tEconomy.grant(user.id, "gold", bonus, opts({"reason": "welcome"}))
    """
  end

  defp mix_exs(name, module, opts) do
    sdk_dep =
      case Keyword.get(opts, :sdk_path) do
        nil -> ~s({:gamend_sdk, "~> 1.0", runtime: false, optional: true})
        path -> ~s({:gamend_sdk, path: "#{path}", runtime: false, optional: true})
      end

    tools_dep =
      case Keyword.get(opts, :sdk_path) do
        nil ->
          ~s({:gamend_plugin_tools, "~> 1.0", runtime: false})

        path ->
          tools = path |> Path.join("../sdk_tools") |> Path.expand()
          ~s({:gamend_plugin_tools, path: "#{tools}", runtime: false})
      end

    """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{name},
          version: "0.1.0",
          elixir: "~> 1.20",
          # Source comes from gen/, which is generated from scripts/*.gd.
          elixirc_paths: ["gen"],
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          aliases: aliases()
        ]
      end

      def application do
        [
          extra_applications: [:logger],
          env: [hooks_module: #{module}]
        ]
      end

      defp deps do
        [
          #{sdk_dep},
          #{tools_dep}
        ]
      end

      defp aliases do
        # One command: GDScript -> Elixir -> BEAM -> bundle.
        [bundle: ["gamend.gdscript.compile", "plugin.bundle"]]
      end
    end
    """
  end

  defp formatter do
    """
    # gen/ is included deliberately: the compiler emits through
    # `Code.format_string!/1`, so `mix format` and `mix gamend.gdscript.compile`
    # must agree, or the two `--check` gates would fight each other.
    [
      inputs: ["{mix,.formatter}.exs", "gen/**/*.ex"]
    ]
    """
  end

  defp gitignore do
    """
    /_build/
    /deps/
    /ebin/
    """
  end
end
