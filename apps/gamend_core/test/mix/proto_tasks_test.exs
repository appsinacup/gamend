defmodule Mix.Tasks.ProtoTasksTest do
  # The protobuf and SDK tasks, run from a scratch project: `host.proto.gen`
  # finds the protos where a plugin keeps them, skips a toolchain that is
  # not there and fails loudly when one breaks (a stand-in Godot plays
  # godobuf), `host.proto.check` reads a captured payload against a message
  # and names the keys it does not know, and `gen.sdk` writes a stub per
  # context, the GDScript API table and the hook defaults, all valid Elixir.
  use Gamend.DataCase, async: false

  defmodule Captured do
    use Protobuf, syntax: :proto3

    field :name, 1, type: :string
    field :count, 2, type: :int32
  end

  setup do
    Mix.shell(Mix.Shell.Process)
    root = Path.join(System.tmp_dir!(), "proto_tasks_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    godot = System.get_env("GODOT_BIN")
    godobuf = System.get_env("GODOBUF_DIR")

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      File.rm_rf(root)
      if godot, do: System.put_env("GODOT_BIN", godot), else: System.delete_env("GODOT_BIN")

      if godobuf,
        do: System.put_env("GODOBUF_DIR", godobuf),
        else: System.delete_env("GODOBUF_DIR")
    end)

    %{root: root}
  end

  defp run(root, task, args), do: File.cd!(root, fn -> Mix.Task.rerun(task, args) end)

  defp shell do
    Stream.repeatedly(fn ->
      receive do
        {:mix_shell, kind, [message]} when kind in [:info, :error] -> message
      after
        0 -> nil
      end
    end)
    |> Enum.take_while(& &1)
    |> Enum.join("\n")
  end

  defp plugin_proto(root, body \\ "") do
    dir = Path.join([root, "modules", "plugins", "demo", "proto"])
    File.mkdir_p!(dir)
    path = Path.join(dir, "demo.proto")

    File.write!(path, """
    syntax = "proto3";
    package demo;
    message Hello {
      #{body}
      string name = 1;
    }
    """)

    path
  end

  # A stand-in for Godot running godobuf: writes the file it is pointed at,
  # or fails the way `mode` says.
  defp fake_godot(root, mode) do
    godobuf = Path.join(root, "godobuf")
    File.mkdir_p!(Path.join(godobuf, "addons/godobuf"))
    File.write!(Path.join(godobuf, "addons/godobuf/godobuf_cmdln.gd"), "")

    script = Path.join(root, "godot.sh")

    body =
      case mode do
        :ok ->
          ~S"""
          for arg in "$@"; do
            case "$arg" in
              --output=*) out="${arg#--output=}" ;;
              --input=*) cp "${arg#--input=}" "$(dirname "$0")/seen.proto" ;;
            esac
          done
          printf 'func has_name() -> bool:\n\treturn __name.value != null\n' > "$out"
          echo done
          """

        :crash ->
          "echo boom; exit 3"

        :compile_error ->
          "echo 'Compilation failed'"

        :no_file ->
          "echo nothing written"
      end

    File.write!(script, "#!/bin/sh\n" <> body)
    File.chmod!(script, 0o755)
    System.put_env("GODOT_BIN", script)
    System.put_env("GODOBUF_DIR", godobuf)
  end

  describe "host.proto.gen" do
    test "with no proto anywhere, says where it looked", %{root: root} do
      run(root, "host.proto.gen", [])
      assert shell() =~ "No .proto files found in: proto/*.proto"
    end

    test "an unknown target or a missing file is refused", %{root: root} do
      assert_raise Mix.Error, ~r/unknown --only target\(s\): cobol/, fn ->
        run(root, "host.proto.gen", ["--only", "elixir,cobol"])
      end

      assert_raise Mix.Error, ~r/no such proto file/, fn ->
        run(root, "host.proto.gen", ["missing.proto"])
      end
    end

    test "Godot with no toolchain configured is skipped, not failed", %{root: root} do
      plugin_proto(root)
      System.delete_env("GODOT_BIN")
      run(root, "host.proto.gen", ["--only", "godot"])
      assert shell() =~ "godot   skipped — set GODOT_BIN and GODOBUF_DIR"

      System.put_env("GODOT_BIN", "/bin/true")
      System.put_env("GODOBUF_DIR", root)
      run(root, "host.proto.gen", ["--only", "godot"])
      assert shell() =~ "does not look like a godobuf checkout"
    end

    test "Godot writes the plugin's file, and its presence checks are looked at", %{root: root} do
      plugin_proto(root, "reserved 9;")
      fake_godot(root, :ok)
      run(root, "host.proto.gen", ["--only", "godot"])

      out = Path.join([root, "modules", "plugins", "demo", "godot", "demo_pb.gd"])
      assert File.exists?(out)
      assert shell() =~ "godot   modules/plugins/demo/godot/demo_pb.gd ("
      # godobuf cannot parse `reserved`, so it was handed a copy without it.
      refute File.read!(Path.join(root, "seen.proto")) =~ "reserved"
    end

    test "a Godot run that crashes, cannot compile or writes nothing fails the task", %{
      root: root
    } do
      proto = plugin_proto(root)

      for mode <- [:crash, :compile_error, :no_file] do
        fake_godot(root, mode)
        out = Path.join(root, "out_#{mode}.gd")

        assert catch_exit(
                 run(root, "host.proto.gen", ["--only", "godot", "--godot-out", out, proto])
               ) == {:shutdown, 1}

        assert shell() =~ "godot   FAILED"
      end
    end

    test "Elixir bindings are written where asked, or skipped without protoc", %{root: root} do
      proto = plugin_proto(root)
      out = Path.join(root, "lib_out")
      run(root, "host.proto.gen", ["--only", "elixir", "--elixir-out", out, proto])
      said = shell()

      if System.find_executable("protoc") do
        assert said =~ "elixir  #{out}" or said =~ "protoc-gen-elixir not found"
      else
        assert said =~ "protoc not on PATH"
      end
    end
  end

  describe "host.proto.check" do
    test "a captured payload the message describes encodes", %{root: root} do
      path = Path.join(root, "ok.json")
      File.write!(path, ~s({"name": "pirate", "count": 3}))

      assert run(root, "host.proto.check", ["--json", path, "--message", inspect(Captured)]) ==
               :ok

      assert shell() =~ "every sampled value encodes as protobuf"
    end

    test "one with a key the message lacks is named, and fails the check", %{root: root} do
      path = Path.join(root, "bad.json")
      File.write!(path, ~s({"name": "pirate", "hearts": 3}))

      assert catch_exit(
               run(root, "host.proto.check", ["--json", path, "--message", inspect(Captured)])
             ) == {:shutdown, 1}

      said = shell()
      assert said =~ "hearts"
      assert said =~ "falling back to JSON: bad.json"
    end

    test "a type the message disagrees with is an encode error", %{root: root} do
      path = Path.join(root, "type.json")
      File.write!(path, ~s({"count": "many"}))

      assert catch_exit(
               run(root, "host.proto.check", ["--json", path, "--message", inspect(Captured)])
             ) == {:shutdown, 1}
    end

    test "half the options, a missing file or no such message is refused", %{root: root} do
      assert_raise Mix.Error, ~r/must be given together/, fn ->
        run(root, "host.proto.check", ["--json", "x.json"])
      end

      assert_raise Mix.Error, ~r/no such file/, fn ->
        run(root, "host.proto.check", ["--json", "x.json", "--message", inspect(Captured)])
      end

      path = Path.join(root, "list.json")
      File.write!(path, "[1, 2]")

      assert_raise Mix.Error, ~r/not a JSON object/, fn ->
        run(root, "host.proto.check", ["--json", path, "--message", inspect(Captured)])
      end

      assert_raise Mix.Error, ~r/not a loaded protobuf message module/, fn ->
        run(root, "host.proto.check", ["--json", path, "--message", "Nope.Message"])
      end
    end

    test "with nothing registered, the registry says so and lists what is untyped", %{root: root} do
      user = Gamend.AccountsFixtures.user_fixture()
      {:ok, _} = Gamend.Accounts.update_user(user, %{metadata: %{"hat" => "tricorn"}})
      {:ok, _} = Gamend.KV.put("progress", %{"level" => 1}, %{}, user_id: user.id)

      assert run(root, "host.proto.check", ["--limit", "5"]) == :ok
      said = shell()
      assert said =~ "No KV schemas are registered"
      assert said =~ "NOT TYPED"
      assert said =~ "progress"
    end
  end

  describe "gen.sdk" do
    test "writes a stub per context, the API table and the hook defaults", %{root: root} do
      run(root, "gen.sdk", [])
      assert shell() =~ "SDK stubs generated in"

      sdk = Path.join([root, "sdk", "lib", "gamend"])

      for file <- ~w(accounts.ex economy.ex kv.ex lobbies.ex signals.ex) do
        source = File.read!(Path.join(sdk, file))
        assert source =~ "defmodule Gamend."
        assert {:ok, _} = Code.string_to_quoted(source), "#{file} is not valid Elixir"
      end

      defaults = File.read!(Path.join([sdk, "hooks", "defaults.ex"]))
      assert defaults =~ "Generated by `mix gen.sdk`"

      api = File.read!(Path.join([root, "sdk_tools", "lib", "gamend", "gdscript", "api.ex"]))
      assert {:ok, _} = Code.string_to_quoted(api)
      assert api =~ ~s("Economy")
      assert api =~ ~s("Hooks")
    end
  end
end
