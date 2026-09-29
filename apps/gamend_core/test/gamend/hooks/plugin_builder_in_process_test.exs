defmodule Gamend.Hooks.PluginBuilderInProcessTest do
  @moduledoc """
  The build a release runs: no Mix, the compiler inside this VM. Forced with
  `mode: :in_process`, since the test environment has `mix` on the PATH.
  """
  # Points the plugin manager at a temporary plugins directory, and empties
  # PATH in one test: both process-global.
  use Gamend.DataCase, async: false

  import ExUnit.CaptureIO

  alias Gamend.Hooks.PluginBuilder
  alias Gamend.Hooks.PluginManager
  alias Gamend.SettingsHelpers

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "plugins")
    File.mkdir_p!(root)
    SettingsHelpers.put(:gamend_core, Gamend.ContentSettings, :plugins_dir, root)

    on_exit(fn ->
      SettingsHelpers.delete(:gamend_core, Gamend.ContentSettings, :plugins_dir)
      _ = PluginManager.reload()
    end)

    n = System.unique_integer([:positive])
    %{root: root, name: "ipb_#{n}", module: Module.concat(Gamend.Modules, "Ipb#{n}"), n: n}
  end

  describe "an Elixir plugin" do
    test "builds into a bundle the manager loads", %{root: root, name: name, module: module} do
      dir = write_plugin(root, name, module)

      assert {:ok, result} = build(name)
      assert result.ok?, output(result)
      assert result.mode == :in_process

      assert Enum.map(result.steps, & &1.cmd) == [
               "read mix.exs",
               "deps (in-process)",
               "compile (in-process)",
               "plugin.bundle (in-process)"
             ]

      helper = Module.concat(module, Helper)

      # Nothing of the build stays loaded, and no build directory is left.
      refute :code.is_loaded(module)
      refute :code.is_loaded(helper)
      assert File.ls!(dir) |> Enum.sort() == ["ebin", "lib", "mix.exs"]

      assert ebin_files(dir) ==
               Enum.sort(["#{name}.app", "#{module}.beam", "#{helper}.beam"])

      _ = PluginManager.reload()

      assert {:ok, %{status: :ok, hooks_module: ^module, vsn: "0.2.0"}} =
               PluginManager.lookup(name)

      assert PluginManager.call_rpc(name, "hello", ["bob"]) == {:ok, "hi bob!"}
    end

    test "writes the .app mix plugin.bundle does", %{root: root, name: name, module: module} do
      dir = write_plugin(root, name, module)
      assert {:ok, %{ok?: true}} = build(name)

      assert {:ok, [{:application, app, props}]} =
               :file.consult(Path.join([dir, "ebin", "#{name}.app"]))

      assert app == String.to_atom(name)

      # Same keys in the same order as Mix's compile.app output.
      assert Keyword.keys(props) ==
               [
                 :modules,
                 :optional_applications,
                 :applications,
                 :description,
                 :registered,
                 :vsn,
                 :env
               ]

      assert props[:modules] == Enum.sort([module, Module.concat(module, Helper)])
      assert props[:optional_applications] == []
      # gamend_sdk is runtime: false and optional, so it is not an application.
      assert props[:applications] == [:kernel, :stdlib, :elixir, :logger, :jason]
      assert props[:description] == String.to_charlist(name)
      assert props[:registered] == []
      assert props[:vsn] == ~c"0.2.0"
      assert props[:env] == [hooks_module: module]
    end

    test "rebuilding a loaded plugin compiles against its new code and restarts it",
         %{root: root, name: name, module: module} do
      dir = write_plugin(root, name, module)
      assert {:ok, %{ok?: true}} = build(name)
      _ = PluginManager.reload()
      assert PluginManager.call_rpc(name, "hello", ["bob"]) == {:ok, "hi bob!"}

      # The suffix is a macro in a sibling module: a build compiled against the
      # loaded (old) sibling would still say "!". Loaded here as a release in
      # embedded mode loads every beam of a plugin.
      assert {:module, _} = Code.ensure_loaded(Module.concat(module, Helper))
      File.write!(Path.join([dir, "lib", "helper.ex"]), helper_source(module, "?"))

      assert {:ok, result} = build(name)
      assert result.ok?, output(result)
      assert List.last(result.steps).output =~ "restarted the plugin on the new bundle"

      assert {:ok, %{status: :ok}} = PluginManager.lookup(name)
      assert PluginManager.call_rpc(name, "hello", ["bob"]) == {:ok, "hi bob?"}

      # A later full reload works on top of it.
      _ = PluginManager.reload()
      assert PluginManager.call_rpc(name, "hello", ["bob"]) == {:ok, "hi bob?"}
    end

    test "a failed compile keeps the previous ebin", %{root: root, name: name, module: module} do
      dir = write_plugin(root, name, module)
      assert {:ok, %{ok?: true}} = build(name)
      before = ebin_contents(dir)

      File.write!(Path.join([dir, "lib", "hooks.ex"]), """
      defmodule #{inspect(module)} do
        use Gamend.Hooks
        def hello(name), do: not_a_function(name)
      end
      """)

      assert {:ok, result} = build(name)
      refute result.ok?

      compile = Enum.find(result.steps, &(&1.cmd == "compile (in-process)"))
      assert compile.status == 1
      assert compile.output =~ "undefined function not_a_function/1"
      assert compile.output =~ "lib/hooks.ex:3"

      assert ebin_contents(dir) == before
      assert File.ls!(dir) |> Enum.sort() == ["ebin", "lib", "mix.exs"]
    end

    test "a failed build of a loaded plugin brings the old one back",
         %{root: root, name: name, module: module} do
      dir = write_plugin(root, name, module)
      assert {:ok, %{ok?: true}} = build(name)
      _ = PluginManager.reload()

      File.write!(
        Path.join([dir, "lib", "hooks.ex"]),
        "defmodule Broken do\n  def x(, do: 1\nend\n"
      )

      assert {:ok, %{ok?: false} = result} = build(name)
      assert List.last(result.steps).output =~ "restarted the plugin on its previous bundle"
      assert PluginManager.call_rpc(name, "hello", ["bob"]) == {:ok, "hi bob!"}
    end

    test "a module the server already has is refused",
         %{root: root, name: name, module: module, n: n} do
      # Stands in for an engine module, without risking a real one.
      existing = Module.concat(Gamend, "ExistingModule#{n}")

      {:module, ^existing, _, _} =
        Module.create(existing, quote(do: def(hi, do: :engine)), __ENV__)

      dir = write_plugin(root, name, module)

      File.write!(Path.join([dir, "lib", "clash.ex"]), """
      defmodule #{inspect(existing)} do
        def hi, do: :plugin
      end
      """)

      assert {:ok, %{ok?: false} = result} = build(name)
      bundle = List.last(result.steps)
      assert bundle.cmd == "plugin.bundle (in-process)"

      assert bundle.output =~
               "cannot redefine a module the server already has: #{inspect(existing)}"

      refute File.exists?(Path.join(dir, "ebin"))
      # The loaded module is untouched.
      assert existing.hi() == :engine
    end
  end

  describe "hooks_module" do
    test "is detected from `use Gamend.Hooks` when mix.exs does not name it",
         %{root: root, name: name, module: module} do
      dir = write_plugin(root, name, module, env: nil)

      assert {:ok, result} = build(name)
      assert result.ok?, output(result)
      assert List.last(result.steps).output =~ "detected: @behaviour Gamend.Hooks"
      assert app_env(dir, name) == [hooks_module: module]
    end

    test "is an error when several modules implement Gamend.Hooks",
         %{root: root, name: name, module: module} do
      dir = write_plugin(root, name, module, env: nil)

      File.write!(Path.join([dir, "lib", "other.ex"]), """
      defmodule #{inspect(module)}.Other do
        use Gamend.Hooks
      end
      """)

      assert {:ok, %{ok?: false} = result} = build(name)
      assert List.last(result.steps).output =~ "several modules implement Gamend.Hooks"
      refute File.exists?(Path.join(dir, "ebin"))
    end
  end

  describe "dependencies" do
    test "one the engine does not ship fails the build, naming it",
         %{root: root, name: name, module: module} do
      dir =
        write_plugin(root, name, module,
          deps: ~s([{:jason, "~> 1.2"}, {:not_shipped_dep, "~> 1.0"}])
        )

      assert {:ok, %{ok?: false} = result} = build(name)
      deps = List.last(result.steps)
      assert deps.cmd == "deps (in-process)"
      assert deps.status == 1
      assert deps.output =~ "missing: :not_shipped_dep"
      assert deps.output =~ "jason: provided by the engine"
      refute File.exists?(Path.join(dir, "ebin"))
    end

    test "one carried prebuilt in deps/<dep>/ebin is on the code path while compiling",
         %{root: root, name: name, module: module, n: n} do
      dep_app = :"prebuilt_dep_#{n}"
      dep_module = Module.concat(PrebuiltDep, "M#{n}")
      dep_ebin = Path.join([root, name, "deps", Atom.to_string(dep_app), "ebin"])
      File.mkdir_p!(dep_ebin)

      {:module, ^dep_module, beam, _} =
        Module.create(dep_module, quote(do: defmacro(word, do: "from the dep")), __ENV__)

      :code.purge(dep_module)
      :code.delete(dep_module)
      File.write!(Path.join(dep_ebin, "#{dep_module}.beam"), beam)

      File.write!(
        Path.join(dep_ebin, "#{dep_app}.app"),
        :io_lib.format(~c"~p.~n", [
          {:application, dep_app,
           [vsn: ~c"1.0.0", modules: [dep_module], applications: [:kernel, :stdlib]]}
        ])
        |> IO.chardata_to_string()
      )

      dir = write_plugin(root, name, module, deps: "[{#{inspect(dep_app)}, \"~> 1.0\"}]")

      File.write!(Path.join([dir, "lib", "dep_user.ex"]), """
      defmodule #{inspect(module)}.DepUser do
        require #{inspect(dep_module)}
        def word, do: #{inspect(dep_module)}.word()
      end
      """)

      assert {:ok, result} = build(name)
      assert result.ok?, output(result)
      assert Enum.at(result.steps, 1).output =~ "prebuilt in deps/#{dep_app}/ebin"

      {:ok, [{:application, _, props}]} = :file.consult(Path.join([dir, "ebin", "#{name}.app"]))
      assert dep_app in props[:applications]

      # The dep's path was put on the code path for the compile only.
      refute Enum.member?(:code.get_path(), String.to_charlist(dep_ebin))
    end
  end

  describe "a GDScript plugin" do
    test "is transpiled into gen/ and built like example_gdscript",
         %{root: root, name: name, n: n} do
      dir = write_gdscript_plugin(root, name, n, hooks_module?: true)
      module = Module.concat(Gamend.Modules, Macro.camelize(name))

      assert {:ok, result} = build(name)
      assert result.ok?, output(result)

      assert Enum.map(result.steps, & &1.cmd) == [
               "read mix.exs",
               "gamend.gdscript.compile (in-process)",
               "deps (in-process)",
               "compile (in-process)",
               "plugin.bundle (in-process)"
             ]

      # The same files `mix gamend.gdscript.compile` writes from inside the
      # plugin, header included.
      gen = Path.join([dir, "gen", "gamend", "modules"])

      assert File.read!(Path.join(gen, "ipb#{n}.ex")) =~
               "# Generated from scripts/#{name}.gd by `mix gamend.gdscript.compile`"

      assert File.read!(Path.join(gen, "gd_rewards#{n}.ex")) =~
               "# Generated from scripts/gd_rewards_#{n}.gd"

      assert app_env(dir, name) == [hooks_module: module]

      _ = PluginManager.reload()
      assert {:ok, %{status: :ok, hooks_module: ^module}} = PluginManager.lookup(name)
      assert PluginManager.call_rpc(name, "greeting", ["bob"]) == {:ok, "Welcome, bob! 150 gold"}
    end

    test "without hooks_module in mix.exs uses the script named after the plugin",
         %{root: root, name: name, n: n} do
      dir = write_gdscript_plugin(root, name, n, hooks_module?: false)

      assert {:ok, result} = build(name)
      assert result.ok?, output(result)

      assert List.last(result.steps).output =~
               "detected: the GDScript module named after the plugin"

      assert app_env(dir, name) == [
               hooks_module: Module.concat(Gamend.Modules, Macro.camelize(name))
             ]
    end

    test "a script error is reported and nothing is built", %{root: root, name: name, n: n} do
      dir = write_gdscript_plugin(root, name, n, hooks_module?: true)
      File.write!(Path.join([dir, "scripts", "#{name}.gd"]), "func broken(:\n\treturn 1\n")

      assert {:ok, %{ok?: false} = result} = build(name)
      step = List.last(result.steps)
      assert step.cmd == "gamend.gdscript.compile (in-process)"
      assert step.output =~ "scripts/#{name}.gd"
      refute File.exists?(Path.join(dir, "ebin"))
    end
  end

  test "a defimpl of a consolidated protocol builds, with the compiler's warning",
       %{root: root, name: name, module: module} do
    dir = write_plugin(root, name, module)

    File.write!(Path.join([dir, "lib", "impl.ex"]), """
    defmodule #{inspect(module)}.Thing do
      defstruct [:x]
    end

    defimpl String.Chars, for: #{inspect(module)}.Thing do
      def to_string(_thing), do: "thing"
    end
    """)

    assert {:ok, result} = build(name)
    assert result.ok?, output(result)

    # The release consolidates protocols; the test environment does too.
    if Protocol.consolidated?(String.Chars) do
      assert Enum.find(result.steps, &(&1.cmd == "compile (in-process)")).output =~
               "the String.Chars protocol has already been consolidated"
    end
  end

  test "without mix on the PATH, build/1 builds in-process",
       %{root: root, name: name, module: module} do
    write_plugin(root, name, module)
    original = System.get_env("PATH")

    try do
      System.put_env("PATH", "")
      assert PluginBuilder.mode() == :in_process
      assert {:ok, %{ok?: true, mode: :in_process}} = build(name, [])
    after
      System.put_env("PATH", original || "")
    end
  end

  test "build_all builds every plugin in the sources directory",
       %{root: root, name: name, module: module} do
    other = name <> "_b"
    write_plugin(root, name, module)
    write_plugin(root, other, Module.concat(module, B))

    {results, _stderr} = with_io(:stderr, fn -> PluginBuilder.build_all(mode: :in_process) end)
    assert [{^name, {:ok, %{ok?: true}}}, {^other, {:ok, %{ok?: true}}}] = results
  end

  # The compiler also prints its diagnostics to stderr; keep the run readable.
  defp build(name, opts \\ [mode: :in_process]) do
    {result, _stderr} = with_io(:stderr, fn -> PluginBuilder.build(name, opts) end)
    result
  end

  ## Fixtures

  defp write_plugin(root, name, module, opts \\ []) do
    dir = Path.join(root, name)
    File.mkdir_p!(Path.join(dir, "lib"))

    deps =
      Keyword.get(
        opts,
        :deps,
        ~s([{:gamend_sdk, path: "../../../sdk", runtime: false, optional: true}, {:jason, "~> 1.2"}])
      )

    env =
      case Keyword.fetch(opts, :env) do
        {:ok, nil} -> ""
        _ -> ",\n      env: [hooks_module: #{inspect(module)}]"
      end

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      @version "0.2.0"

      def project do
        [
          app: :#{name},
          version: System.get_env("SOME_VERSION") || @version,
          elixir: "~> 1.20",
          elixirc_paths: elixirc_paths(Mix.env()),
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger]#{env}
        ]
      end

      defp elixirc_paths(:test), do: ["lib", "test/support"]
      defp elixirc_paths(_), do: ["lib"]

      defp deps do
        #{deps}
      end
    end
    """)

    File.write!(Path.join([dir, "lib", "hooks.ex"]), """
    defmodule #{inspect(module)} do
      use Gamend.Hooks
      require #{inspect(module)}.Helper

      def hello(name), do: "hi " <> name <> #{inspect(module)}.Helper.suffix()
    end
    """)

    File.write!(Path.join([dir, "lib", "helper.ex"]), helper_source(module, "!"))
    dir
  end

  defp helper_source(module, suffix) do
    """
    defmodule #{inspect(module)}.Helper do
      defmacro suffix, do: #{inspect(suffix)}
    end
    """
  end

  # Mirrors modules/plugins_examples/example_gdscript: two scripts, one
  # reaching the other by its class_name, compiled from gen/.
  defp write_gdscript_plugin(root, name, n, opts) do
    dir = Path.join(root, name)
    File.mkdir_p!(Path.join(dir, "scripts"))
    module = "Gamend.Modules." <> Macro.camelize(name)
    rewards = "GdRewards#{n}"

    env =
      if Keyword.fetch!(opts, :hooks_module?),
        do: ",\n      env: [hooks_module: #{module}]",
        else: ""

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{name},
          version: "0.1.0",
          elixir: "~> 1.20",
          elixirc_paths: ["gen"],
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          aliases: aliases()
        ]
      end

      def application do
        [
          extra_applications: [:logger]#{env}
        ]
      end

      defp deps do
        [
          {:gamend_sdk, path: "../../../sdk", runtime: false, optional: true},
          {:gamend_plugin_tools, path: "../../../sdk_tools", runtime: false}
        ]
      end

      defp aliases do
        [bundle: ["gamend.gdscript.compile", "plugin.bundle"]]
      end
    end
    """)

    File.write!(Path.join([dir, "scripts", "#{name}.gd"]), """
    # The plugin's hooks, reaching the other script by its class_name.

    func greeting(name):
    \treturn "Welcome, " + name + "! " + str(#{rewards}.starter_gold(true)) + " gold"
    """)

    File.write!(Path.join([dir, "scripts", "gd_rewards_#{n}.gd"]), """
    class_name #{rewards}

    const BASE_GOLD = 100

    func starter_gold(referred):
    \treturn BASE_GOLD + 50 if referred else BASE_GOLD
    """)

    dir
  end

  defp ebin_files(dir), do: dir |> Path.join("ebin") |> File.ls!() |> Enum.sort()

  defp ebin_contents(dir) do
    for file <- ebin_files(dir), into: %{} do
      {file, File.read!(Path.join([dir, "ebin", file]))}
    end
  end

  defp app_env(dir, name) do
    {:ok, [{:application, _, props}]} = :file.consult(Path.join([dir, "ebin", "#{name}.app"]))
    props[:env]
  end

  defp output(result), do: Enum.map_join(result.steps, "\n\n", &"$ #{&1.cmd}\n#{&1.output}")
end
