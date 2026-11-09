defmodule Mix.Tasks.Host.Proto.Gen do
  @moduledoc """
  Generates protobuf bindings for every target from a `.proto` file.

  A gamend protobuf schema is consumed by three runtimes — the Elixir plugin,
  the JavaScript client and the Godot client — each with its own generator.
  Running them by hand means three commands with different flag conventions,
  and a downstream game has no copy of this repo's shell scripts. This task
  ships with `gamend_core`, so any host application or plugin can run it.

  ## Usage

      mix host.proto.gen                    # every discovered .proto
      mix host.proto.gen path/to/my.proto   # just this one

  ## Options

      --only elixir,js,godot   Restrict targets (default: all available)
      --elixir-out DIR         Elixir output dir     (default: <plugin>/lib)
      --js-out FILE            JavaScript output     (default: <plugin>/clients/<name>.pb.js)
      --godot-out FILE         Godot output          (default: <plugin>/godot/<name>_pb.gd)

  ## Requirements

  Each target is skipped with a note when its toolchain is absent, so a project
  that only ships an Elixir plugin needs nothing extra:

    * Elixir — `protoc` plus `protoc-gen-elixir` (`mix escript.install hex protobuf`)
    * JavaScript — `npx` (fetches the pinned `protobufjs-cli` on demand)
    * Godot — `GODOT_BIN` and `GODOBUF_DIR` environment variables

  Discovery looks in `proto/`, `modules/plugins/*/proto/` and
  `modules/plugins_examples/*/proto/`, which covers the server itself and the
  plugin layout used by gamend games.
  """
  use Mix.Task

  alias Gamend.Proto.GodobufPresence

  @proto "proto"
  @clients "clients"
  # literal-ok: a folder of a different tree
  @lib "lib"

  @shortdoc "Generate protobuf bindings (Elixir, JS, Godot) from .proto files"

  @search_globs [
    "proto/*.proto",
    "modules/plugins/*/proto/*.proto",
    "modules/plugins_examples/*/proto/*.proto"
  ]

  @targets ~w(elixir js godot)

  # One pbjs for every machine: an unpinned `npx -p protobufjs-cli` fetched
  # whatever was newest, and two machines wrote two different files from one
  # schema (2.7 decodes with `reader.size()`, which the 8.x runtime the JS
  # client ships has; older ones with `reader.uint32()`). Keep it in step
  # with `clients/package.json`'s `proto` script.
  @pbjs "protobufjs-cli@2.7.1"

  @impl Mix.Task
  def run(args) do
    {opts, files} =
      OptionParser.parse!(args,
        strict: [only: :string, elixir_out: :string, js_out: :string, godot_out: :string]
      )

    targets = parse_targets(opts[:only])

    case files_to_generate(files) do
      [] ->
        Mix.shell().info("No .proto files found in: #{Enum.join(@search_globs, ", ")}")

      protos ->
        # Exit 1 on a failed target. Printing FAILED and exiting 0 is the same
        # silent success one level up: the godobuf breakage below went unnoticed
        # partly because `mix host.proto.gen` always looked like it worked. A
        # SKIP is different and stays green — missing protoc or GODOT_BIN means
        # "not generating that here", not "generation is broken".
        results = Enum.flat_map(protos, &generate(&1, targets, opts))

        if Enum.any?(results, &(&1 == :error)), do: exit({:shutdown, 1})
    end
  end

  defp parse_targets(nil), do: @targets

  defp parse_targets(only) do
    requested = only |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    case requested -- @targets do
      [] -> requested
      unknown -> Mix.raise("unknown --only target(s): #{Enum.join(unknown, ", ")}")
    end
  end

  defp files_to_generate([]), do: Enum.flat_map(@search_globs, &Path.wildcard/1)

  defp files_to_generate(files) do
    Enum.map(files, fn file ->
      if File.exists?(file), do: file, else: Mix.raise("no such proto file: #{file}")
    end)
  end

  defp generate(proto, targets, opts) do
    Mix.shell().info("\n#{proto}")

    [
      if("elixir" in targets, do: gen_elixir(proto, opts)),
      if("js" in targets, do: gen_js(proto, opts)),
      if("godot" in targets, do: gen_godot(proto, opts))
    ]
    |> Enum.reject(&is_nil/1)
  end

  # ── Elixir ──────────────────────────────────────────────────────────────

  defp gen_elixir(proto, opts) do
    out = opts[:elixir_out] || Path.join(plugin_root(proto), @lib)

    cond do
      is_nil(System.find_executable("protoc")) ->
        skip("elixir", "protoc not on PATH")

      is_nil(protoc_gen_elixir()) ->
        skip("elixir", "protoc-gen-elixir not found (mix escript.install hex protobuf)")

      true ->
        File.mkdir_p!(out)
        env = [{"PATH", "#{Path.dirname(protoc_gen_elixir())}:#{System.get_env("PATH")}"}]

        result =
          cmd(
            "protoc",
            ["--elixir_out=#{out}", "-I", Path.dirname(proto), proto],
            env,
            "elixir",
            out
          )

        if result == :ok, do: format_elixir(out)
        result
    end
  end

  # protoc-gen-elixir emits `field :key, 1, ...`; a project that formats its
  # `lib/**` rewrites that to `field(:key, 1, ...)` the first time anyone runs
  # `mix format`. After that every regeneration reverses it again, and a
  # three-line proto change arrives as a six-hundred-line diff that nobody can
  # review. Formatting here means the generated file is already in the shape
  # the project keeps it in.
  defp format_elixir(out) do
    plugin_dir = Path.dirname(out)

    if File.exists?(Path.join(plugin_dir, ".formatter.exs")) do
      # Absolute: `cd:` moves mix into the plugin, so a path relative to the
      # caller would resolve against the wrong directory and match nothing —
      # silently, since `mix format` on zero files is not an error.
      System.cmd("mix", ["format", Path.join(Path.expand(out), "**/*.pb.ex")],
        cd: plugin_dir,
        stderr_to_stdout: true
      )
    end

    :ok
  rescue
    _ -> :ok
  end

  defp protoc_gen_elixir do
    System.find_executable("protoc-gen-elixir") ||
      [System.user_home(), ".mix", "escripts", "protoc-gen-elixir"]
      |> Path.join()
      |> then(&if File.exists?(&1), do: &1)
  end

  # ── JavaScript ──────────────────────────────────────────────────────────

  defp gen_js(proto, opts) do
    out = opts[:js_out] || Path.join([plugin_root(proto), @clients, "#{base(proto)}.pb.js"])

    if System.find_executable("npx") do
      File.mkdir_p!(Path.dirname(out))

      args =
        ["-p", @pbjs] ++
          ~w(pbjs -t static-module -w es6 --keep-case --no-create --no-verify --no-delimited -o) ++
          [out, proto]

      cmd("npx", args, [], "js", out)
    else
      skip("js", "npx not on PATH")
    end
  end

  # ── Godot ───────────────────────────────────────────────────────────────

  defp gen_godot(proto, opts) do
    out = opts[:godot_out] || Path.join([plugin_root(proto), "godot", "#{base(proto)}_pb.gd"])
    godot = System.get_env("GODOT_BIN")
    godobuf = System.get_env("GODOBUF_DIR")

    cond do
      is_nil(godot) or is_nil(godobuf) ->
        skip("godot", "set GODOT_BIN and GODOBUF_DIR (github.com/oniksan/godobuf)")

      not File.exists?(Path.join(godobuf, "addons/godobuf/godobuf_cmdln.gd")) ->
        skip("godot", "GODOBUF_DIR does not look like a godobuf checkout")

      true ->
        File.mkdir_p!(Path.dirname(out))
        args = ~w(--headless -s addons/godobuf/godobuf_cmdln.gd)
        args = args ++ ["--input=#{godobuf_input(proto)}", "--output=#{Path.expand(out)}"]

        {output, code} = System.cmd(godot, args, cd: godobuf, stderr_to_stdout: true)

        # Godot's headless script runner exits 0 whether or not the script
        # succeeded, so the exit code proves nothing on its own. A `reserved`
        # field godobuf cannot parse fails the whole file this way, and did:
        # it went unnoticed for weeks while every proto change reached the
        # Elixir and JS bindings and never reached Godot. What godobuf
        # actually wrote is the honest signal, so that is what is checked.
        cond do
          code != 0 ->
            Mix.shell().error("  godot   FAILED (#{code})\n#{output}")
            :error

          String.contains?(output, "Compilation failed") ->
            Mix.shell().error("  godot   FAILED (godobuf could not compile the proto)\n#{output}")
            :error

          not File.exists?(out) ->
            Mix.shell().error("  godot   FAILED (godobuf wrote no #{out})\n#{output}")
            :error

          true ->
            # godobuf's proto3-optional presence checks are wrong; see the module.
            rewritten = GodobufPresence.fix_file!(out)
            Mix.shell().info("  godot   #{out} (#{rewritten} presence checks fixed)")
            :ok
        end
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp cmd(exe, args, env, label, out) do
    case System.cmd(exe, args, env: env, stderr_to_stdout: true) do
      {_output, 0} ->
        Mix.shell().info("  #{String.pad_trailing(label, 7)} #{out}")
        :ok

      {output, code} ->
        Mix.shell().error("  #{label} FAILED (#{code})\n#{output}")
        :error
    end
  end

  # godobuf cannot parse `reserved` and fails the ENTIRE file when it meets
  # one — which is how a single `reserved 4;` froze this game's Godot bindings
  # for weeks while Elixir and JS kept regenerating fine.
  #
  # `reserved` is a compile-time guard (these tag numbers must never be reused)
  # and emits no code, so godobuf loses nothing by not seeing it. Stripping it
  # for godobuf alone is what keeps the .proto able to carry the guard at all:
  # the alternative, and what was done before, is deleting `reserved` from the
  # source of truth so that protoc stops protecting the tags too.
  defp godobuf_input(proto) do
    source = File.read!(proto)
    stripped = Regex.replace(~r/^[ \t]*reserved\b[^;]*;[ \t]*\R?/m, source, "")

    if stripped == source do
      Path.expand(proto)
    else
      # Same basename, temp directory: godobuf is given a file that differs
      # from the real one only by the lines it cannot read.
      dir = Path.join(System.tmp_dir!(), "gamend-proto-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, Path.basename(proto))
      File.write!(path, stripped)
      path
    end
  end

  # `:skip`, not `:error`: missing protoc or GODOT_BIN means this machine does
  # not generate that target, which is a setup fact, not a broken proto.
  defp skip(label, reason) do
    Mix.shell().info("  #{String.pad_trailing(label, 7)} skipped — #{reason}")
    :skip
  end

  defp base(proto), do: proto |> Path.basename(".proto")

  # A proto usually lives at <plugin>/proto/x.proto; outputs go next to the
  # plugin rather than next to the proto file itself.
  defp plugin_root(proto) do
    dir = Path.dirname(proto)
    if Path.basename(dir) == @proto, do: Path.dirname(dir), else: dir
  end
end
