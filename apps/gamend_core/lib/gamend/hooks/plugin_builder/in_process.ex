defmodule Gamend.Hooks.PluginBuilder.InProcess do
  @moduledoc """
  Builds a plugin bundle inside the running VM, without Mix.

  A release (the downloadable engine, the Dockerfile's `release` image) ships
  the Elixir compiler but no `mix` executable, so `Gamend.Hooks.PluginBuilder`
  falls back to this. It produces what `mix plugin.bundle` does for the
  plugin's own code: `ebin/*.beam` plus `ebin/<app>.app`, loadable by
  `Gamend.Hooks.PluginManager` unchanged.

  Steps, each reported as a `t:Gamend.Hooks.PluginBuilder.step_result/0`:

    1. Read `mix.exs` without evaluating it (`Gamend.Hooks.PluginBuilder.Project`).
    2. GDScript plugins (`scripts/*.gd`): transpile into `gen/` with
       `Gamend.GDScript`, as `mix gamend.gdscript.compile` does.
    3. Check dependencies. One the engine ships (phoenix, jason, req, ecto…)
       or that sits prebuilt in `deps/<dep>/ebin` is fine; `gamend_sdk` and
       `gamend_plugin_tools` are compile-time only and ignored. Anything else
       fails the build naming it: there is no Hex here to fetch it.
    4. Compile `elixirc_paths/**/*.ex` with `Kernel.ParallelCompiler` into a
       temporary directory, then write the `.app` and swap it in as `ebin/`.
       A failed build leaves the previous `ebin/` untouched.

  The compiler runs in this VM, so a plugin that is loaded is stopped for the
  build (`PluginManager.suspend/1`) and started again afterwards
  (`PluginManager.resume/1`), on the new bundle when the build succeeded and on
  the old one when it failed. Unloading first matters: the compiler takes a
  module that is already loaded as the one to compile against, so a sibling's
  old macros and structs would end up in the new build.

  Limits: no Hex dependencies beyond what the engine ships or the plugin
  carries prebuilt, no Erlang sources (`src/*.erl`), no Gleam, no
  `config/config.exs`, and the engine's protocols are consolidated, so a
  `defimpl` of an engine protocol (`Jason.Encoder`, `String.Chars`…) has no
  effect; the compiler's warning saying so is in the compile step's output.
  The compiler also prints its diagnostics to the server's stderr.
  """

  alias Gamend.Hooks.PluginBuilder.Project
  alias Gamend.Hooks.PluginManager

  # Compile-time stubs and tooling: never needed, never loaded, at runtime.
  @ignored_deps [:gamend_sdk, :gamend_plugin_tools]
  @base_apps [:kernel, :stdlib, :elixir]

  @doc """
  Whether this VM can compile Elixir: the `elixir` and `compiler` applications
  are loadable. True in any release, since `elixir` depends on `compiler`.
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(Kernel.ParallelCompiler) and Code.ensure_loaded?(:compile)
  end

  @doc """
  Builds the plugin in `plugin_dir` (named `plugin_name` by the loader).
  Returns the steps it ran; the build succeeded when every status is `0`.

  Builds of one plugin directory run one at a time on this node.
  """
  @spec run(String.t(), Path.t()) :: [Gamend.Hooks.PluginBuilder.step_result()]
  def run(plugin_name, plugin_dir) do
    plugin_dir = Path.expand(plugin_dir)

    case :global.trans(
           {{__MODULE__, plugin_dir}, self()},
           fn -> do_run(plugin_name, plugin_dir) end,
           [node()],
           :infinity
         ) do
      :aborted -> [step("lock", 1, ["another build of #{plugin_name} did not let go"])]
      steps -> steps
    end
  end

  defp do_run(plugin_name, dir) do
    state = %{name: plugin_name, dir: dir, project: nil, dep_apps: [], optional_apps: []}

    [&read_step/1, &gdscript_step/1, &deps_step/1, &compile_steps/1]
    |> Enum.reduce_while({state, []}, fn step, {state, steps} ->
      case step.(state) do
        {:ok, state, new_steps} -> {:cont, {state, steps ++ new_steps}}
        {:error, new_steps} -> {:halt, {state, steps ++ new_steps}}
      end
    end)
    |> elem(1)
  end

  ## 1. mix.exs

  defp read_step(state) do
    case Project.read(state.dir) do
      {:ok, project} ->
        lines =
          [
            "app=#{inspect(project.app)} vsn=#{project.version} " <>
              "elixirc_paths=#{inspect(project.elixirc_paths)}",
            "deps: #{project.deps |> Enum.map(& &1.name) |> inspect()}"
          ] ++
            name_mismatch(project.app, state.name) ++
            Enum.map(project.warnings, &("warning: " <> &1))

        {:ok, %{state | project: project}, [step("read mix.exs", 0, lines)]}

      {:error, message} ->
        {:error, [step("read mix.exs", 1, [message])]}
    end
  end

  # The loader finds `<dir>/ebin/<dir>.app`, so an app named otherwise builds
  # but never loads — with Mix too.
  defp name_mismatch(app, name) do
    if Atom.to_string(app) == name,
      do: [],
      else: [
        "warning: app #{inspect(app)} is not the directory name #{name}; " <>
          "the server loads ebin/#{name}.app"
      ]
  end

  ## 2. GDScript

  defp gdscript_step(state) do
    case gdscript_scripts(state.dir) do
      [] -> {:ok, state, []}
      scripts -> transpile(state, scripts)
    end
  end

  @doc false
  # Relative to the plugin, as `mix gamend.gdscript.compile` sees them from
  # inside it: the path is what the generated header names.
  @spec gdscript_scripts(Path.t()) :: [Path.t()]
  def gdscript_scripts(dir) do
    dir
    |> Path.join("scripts/*.gd")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, dir))
  end

  @label_gdscript "gamend.gdscript.compile (in-process)"

  defp transpile(state, scripts) do
    transpiler = gdscript_module()

    if Code.ensure_loaded?(transpiler) and function_exported?(transpiler, :source_path, 1) do
      written =
        scripts
        |> transpiler.compile_all(root: state.dir)
        |> Enum.map(fn {module, source} ->
          target = Path.join("gen", transpiler.source_path(module))
          path = Path.join(state.dir, target)
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, source)
          "compiled -> #{target}"
        end)

      unused =
        if "gen" in state.project.elixirc_paths,
          do: [],
          else: ["warning: elixirc_paths does not include gen/, so none of it compiles"]

      {:ok, state, [step(@label_gdscript, 0, [written, unused])]}
    else
      {:error,
       [
         step(@label_gdscript, 1, [
           "this engine does not ship the GDScript transpiler (the gamend_plugin_tools " <>
             "package); build the plugin with `mix bundle` instead"
         ])
       ]}
    end
  rescue
    e -> {:error, [step(@label_gdscript, 1, [Exception.message(e)])]}
  end

  # Resolved at runtime: the transpiler ships with the host app, not with
  # gamend_core, so a literal call would not compile warning-free here.
  defp gdscript_module, do: Module.concat(Gamend, GDScript)

  ## 3. Dependencies

  @label_deps "deps (in-process)"

  defp deps_step(state) do
    required =
      Enum.filter(state.project.deps, fn dep ->
        dep.name not in @ignored_deps and dep.runtime? and dep.prod?
      end)

    checked = Enum.map(required, &check_dep(&1, state.dir))

    lines =
      Enum.map(state.project.deps -- required, &"#{&1.name}: compile-time only, skipped") ++
        Enum.map(checked, &elem(&1, 1))

    case for({:missing, _line, dep} <- checked, do: dep.name) do
      [] ->
        state = %{
          state
          | dep_apps: for({status, _, dep} <- checked, status != :missing, do: dep.name),
            optional_apps: for(dep <- required, dep.optional?, do: dep.name)
        }

        {:ok, state, [step(@label_deps, 0, lines)]}

      missing ->
        {:error,
         [
           step(
             @label_deps,
             1,
             lines ++
               [
                 "",
                 "missing: #{Enum.map_join(missing, ", ", &inspect/1)}. This engine does not ship " <>
                   "#{if length(missing) == 1, do: "it", else: "them"} and there is no Hex here to " <>
                   "fetch from. Bundle the plugin where Mix is available (`mix plugin.bundle` " <>
                   "copies runtime deps into deps/<dep>/ebin), or drop the dependency."
               ]
           )
         ]}
    end
  end

  defp check_dep(dep, dir) do
    prebuilt = Path.join([dir, "deps", Atom.to_string(dep.name), "ebin"])

    cond do
      engine_app?(dep.name, dir) -> {:engine, "#{dep.name}: provided by the engine", dep}
      File.dir?(prebuilt) -> {:prebuilt, "#{dep.name}: prebuilt in deps/#{dep.name}/ebin", dep}
      dep.optional? -> {:optional, "#{dep.name}: optional and not available", dep}
      true -> {:missing, "#{dep.name}: MISSING", dep}
    end
  end

  # An app the engine's own code path provides. A plugin's bundled deps are on
  # the path too while it is loaded, and do not count.
  defp engine_app?(app, dir) do
    case :code.lib_dir(app) do
      lib when is_list(lib) -> not under?(Path.expand(List.to_string(lib)), dir)
      _ -> false
    end
  end

  ## 4. Compile and bundle

  @label_compile "compile (in-process)"
  @label_bundle "plugin.bundle (in-process)"

  defp compile_steps(state) do
    files = source_files(state)
    erlang = Path.wildcard(Path.join(state.dir, "src/**/*.erl"))

    cond do
      erlang != [] ->
        {:error,
         [
           step(@label_compile, 1, [
             "Erlang sources under src/ need Mix (erlc); build this plugin with `mix plugin.bundle`"
           ])
         ]}

      files == [] ->
        {:error,
         [
           step(@label_compile, 1, [
             "no .ex files under #{inspect(state.project.elixirc_paths)}"
           ])
         ]}

      true ->
        with_plugin_unloaded(state, fn -> compile_and_bundle(state, files) end)
    end
  end

  defp source_files(state) do
    state.project.elixirc_paths
    |> Enum.flat_map(&Path.wildcard(Path.join([state.dir, &1, "**", "*.ex"])))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Stop the plugin (and drop anything of it still loaded), take the plugin's
  # own ebin off the code path and put its prebuilt deps on it, run `fun`,
  # then undo all of that and start the plugin again if it was running.
  defp with_plugin_unloaded(state, fun) do
    suspended? = PluginManager.suspend(state.name)
    own_ebin = Path.join(state.dir, "ebin")
    had_own_ebin? = Code.delete_path(own_ebin)

    dep_paths =
      state.dir |> Path.join("deps/*/ebin") |> Path.wildcard() |> Enum.filter(&File.dir?/1)

    on_path = MapSet.new(:code.get_path(), &List.to_string/1)
    added = Enum.reject(dep_paths, &MapSet.member?(on_path, &1))

    result =
      try do
        evict_loaded(state.dir)
        Enum.each(added, &Code.append_path/1)
        # A release may run the code server in embedded mode, where nothing
        # loads on first use; the compiler needs the deps' modules loaded.
        _ = PluginManager.load_beams(dep_paths, :code.get_mode())
        fun.()
      catch
        kind, reason -> {:caught, kind, reason, __STACKTRACE__}
      after
        Enum.each(added, &Code.delete_path/1)
        if had_own_ebin?, do: Code.append_path(own_ebin)
        evict_loaded(state.dir)
      end

    resumed = if suspended?, do: PluginManager.resume(state.name)

    case result do
      {:caught, kind, reason, stacktrace} -> :erlang.raise(kind, reason, stacktrace)
      result when suspended? -> add_note(result, resume_note(result, resumed))
      result -> result
    end
  end

  defp resume_note(_result, %{status: {:error, reason}}),
    do: "the plugin was loaded when the build began and did not start again: #{inspect(reason)}"

  defp resume_note(_result, nil),
    do: "the plugin was loaded when the build began and could not be loaded again"

  defp resume_note({:ok, _state, _steps}, _plugin),
    do: "restarted the plugin on the new bundle (it was loaded when the build began)"

  defp resume_note(_result, _plugin),
    do: "restarted the plugin on its previous bundle (it was loaded when the build began)"

  defp add_note({:ok, state, steps}, line), do: {:ok, state, append_to_last(steps, line)}
  defp add_note({:error, steps}, line), do: {:error, append_to_last(steps, line)}

  defp append_to_last(steps, line) do
    List.update_at(steps, -1, fn step -> %{step | output: step.output <> "\n" <> line} end)
  end

  # Unload every module loaded from inside the plugin directory, except its
  # prebuilt deps: the previous bundle's (a plugin the manager failed to start
  # keeps its beams loaded) and what the compiler loaded from the build
  # directory while compiling (a module another one needed at compile time).
  # After this nothing of the plugin's own code is loaded, so the loader reads
  # the new bundle from disk like any other.
  defp evict_loaded(dir) do
    dir = Path.expand(dir)
    deps = Path.join(dir, "deps")

    for {module, file} <- :code.all_loaded(),
        is_list(file),
        path = Path.expand(List.to_string(file)),
        under?(path, dir),
        not under?(path, deps) do
      _ = :code.purge(module)
      _ = :code.delete(module)
      _ = :code.purge(module)
    end

    :ok
  end

  defp compile_and_bundle(state, files) do
    tmp = Path.join(state.dir, ".ebin-build-#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    try do
      case compile(files, tmp, state.dir) do
        {:ok, modules, compile_step} ->
          # compile_to_path/3 prepends the build directory to the code path,
          # and loads a module another one needed at compile time. Neither may
          # outlive the build: the loader reads the bundle from ebin/.
          Code.delete_path(tmp)
          evict_loaded(state.dir)

          case bundle(state, modules, tmp) do
            {:ok, bundle_step} -> {:ok, state, [compile_step, bundle_step]}
            {:error, bundle_step} -> {:error, [compile_step, bundle_step]}
          end

        {:error, compile_step} ->
          {:error, [compile_step]}
      end
    after
      Code.delete_path(tmp)
      File.rm_rf(tmp)
    end
  end

  defp compile(files, tmp, dir) do
    case Kernel.ParallelCompiler.compile_to_path(files, tmp, return_diagnostics: true) do
      {:ok, modules, info} ->
        warnings = format_diagnostics(info.compile_warnings ++ info.runtime_warnings, dir)
        summary = "Compiled #{length(files)} file(s), #{length(modules)} module(s)"
        {:ok, Enum.sort(modules), step(@label_compile, 0, [warnings, summary])}

      {:error, errors, info} ->
        diagnostics =
          format_diagnostics(errors ++ info.compile_warnings ++ info.runtime_warnings, dir)

        {:error, step(@label_compile, 1, [diagnostics, "Compilation failed"])}
    end
  rescue
    e -> {:error, step(@label_compile, 1, [Exception.message(e)])}
  end

  defp format_diagnostics(diagnostics, dir) do
    diagnostics
    |> Enum.uniq_by(&{&1.severity, &1.message, &1.file, &1.position})
    |> Enum.map(fn diagnostic ->
      location =
        case {diagnostic.file, line(diagnostic.position)} do
          {nil, _} -> ""
          {file, nil} -> "\n  " <> Path.relative_to(file, dir)
          {file, line} -> "\n  #{Path.relative_to(file, dir)}:#{line}"
        end

      "#{diagnostic.severity}: #{String.trim(diagnostic.message)}#{location}"
    end)
  end

  defp line({line, _column}), do: line
  defp line(line) when is_integer(line) and line > 0, do: line
  defp line(_position), do: nil

  defp bundle(state, modules, tmp) do
    project = state.project
    attributes = Map.new(modules, &{&1, beam_attributes(tmp, &1)})

    with :ok <- check_clashes(modules),
         {:ok, hooks_module, how} <- hooks_module(state, modules, attributes) do
      app_file = Path.join(tmp, "#{project.app}.app")
      File.write!(app_file, app_contents(state, modules, hooks_module))
      :ok = swap_in(tmp, Path.join(state.dir, "ebin"))

      {:ok,
       step(@label_bundle, 0, [
         "hooks_module=#{inspect(hooks_module)} (#{how})",
         missing_hooks_module(hooks_module, modules),
         "Bundled plugin #{project.app}: ebin/ (#{length(modules)} modules)"
       ])}
    else
      {:error, message} -> {:error, step(@label_bundle, 1, [message, "ebin/ left as it was"])}
    end
  rescue
    e -> {:error, step(@label_bundle, 1, [Exception.message(e), "ebin/ left as it was"])}
  end

  # A module the engine (or another plugin) already defines would shadow it or
  # be shadowed by it, depending on load order.
  defp check_clashes(modules) do
    clashes =
      for module <- modules, (where = :code.which(module)) != :non_existing do
        "#{inspect(module)} (already defined by #{format_where(where)})"
      end

    case clashes do
      [] ->
        :ok

      _ ->
        {:error,
         "a plugin cannot redefine a module the server already has: " <> Enum.join(clashes, ", ")}
    end
  end

  defp format_where(where) when is_list(where), do: List.to_string(where)
  defp format_where(where), do: inspect(where)

  defp hooks_module(%{project: %{hooks_module: module}}, _modules, _attributes)
       when module != nil,
       do: {:ok, module, "from mix.exs"}

  defp hooks_module(state, modules, attributes) do
    behaviours =
      Enum.filter(modules, fn module ->
        Gamend.Hooks in Keyword.get(attributes[module], :behaviour, []) or
          Gamend.Hooks in Keyword.get(attributes[module], :behavior, [])
      end)

    case {behaviours, gdscript_hooks_module(state, modules)} do
      {[module], _} ->
        {:ok, module, "detected: @behaviour Gamend.Hooks"}

      {[], module} when module != nil ->
        {:ok, module, "detected: the GDScript module named after the plugin"}

      {[], nil} ->
        {:error,
         "cannot tell which module is the hooks module: set `env: [hooks_module: MyModule]` " <>
           "in application/0 of mix.exs, or `use Gamend.Hooks` in exactly one module"}

      {several, _} ->
        {:error,
         "several modules implement Gamend.Hooks (#{Enum.map_join(several, ", ", &inspect/1)}); " <>
           "set `env: [hooks_module: MyModule]` in application/0 of mix.exs"}
    end
  end

  # GDScript output declares no behaviour. The plugin's main script is the one
  # named after the plugin (what `mix gamend.gdscript.new` scaffolds), or the
  # only one.
  defp gdscript_hooks_module(state, modules) do
    transpiler = gdscript_module()

    candidates =
      case gdscript_scripts(state.dir) do
        [] ->
          []

        [only] ->
          [only]

        scripts ->
          Enum.filter(scripts, &(Path.basename(&1, ".gd") == Atom.to_string(state.project.app)))
      end

    with [script] <- candidates,
         true <- Code.ensure_loaded?(transpiler),
         module = Module.concat([transpiler.default_module(script)]),
         true <- module in modules do
      module
    else
      _ -> nil
    end
  end

  defp missing_hooks_module(module, modules) do
    if module in modules,
      do: [],
      else: [
        "warning: hooks_module #{inspect(module)} is not one of the modules this build compiled"
      ]
  end

  defp beam_attributes(dir, module) do
    beam = dir |> Path.join("#{module}.beam") |> String.to_charlist()

    case :beam_lib.chunks(beam, [:attributes]) do
      {:ok, {_module, [attributes: attributes]}} -> attributes
      _ -> []
    end
  end

  # The shape `mix plugin.bundle` copies out of `_build`: what Mix's
  # compile.app writes for the project.
  defp app_contents(state, modules, hooks_module) do
    project = state.project

    applications =
      Enum.uniq(
        @base_apps ++ project.extra_applications ++ (project.applications || state.dep_apps)
      )

    properties =
      Enum.concat([
        [
          modules: modules,
          optional_applications: state.optional_apps,
          applications: applications,
          description: String.to_charlist(project.description || Atom.to_string(project.app)),
          registered: [],
          vsn: String.to_charlist(project.version)
        ],
        if(project.mod, do: [mod: project.mod], else: []),
        [env: Keyword.put(project.env, :hooks_module, hooks_module)]
      ])

    [:io_lib.format(~c"~p.~n", [{:application, project.app, properties}])]
    |> IO.chardata_to_string()
  end

  # Replace `ebin/` by the new build: the old one moves aside first and comes
  # back if the new one cannot be put in place.
  defp swap_in(new, ebin) do
    old = ebin <> ".old-#{System.unique_integer([:positive])}"
    had_old? = File.exists?(ebin)

    if had_old?, do: File.rename!(ebin, old)

    case File.rename(new, ebin) do
      :ok ->
        if had_old?, do: File.rm_rf(old)
        :ok

      {:error, reason} ->
        if had_old?, do: File.rename(old, ebin)
        raise File.RenameError, source: new, destination: ebin, reason: reason
    end
  end

  # Both paths absolute and expanded.
  defp under?(path, dir), do: path == dir or String.starts_with?(path, dir <> "/")

  # `lines` may nest lists of lines; they are flattened in order.
  defp step(cmd, status, lines),
    do: %{cmd: cmd, status: status, output: lines |> List.flatten() |> Enum.join("\n")}
end
