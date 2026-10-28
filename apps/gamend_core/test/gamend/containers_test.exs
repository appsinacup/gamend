defmodule Gamend.ContainersTest do
  @moduledoc """
  The flags a container spec becomes. Podman itself is not needed: what is
  pinned here is that the hardening floor is always there, a limit is spelt
  the way podman reads it, and a value that would forge a second env line is
  refused before anything is written.
  """
  use ExUnit.Case, async: true

  alias Gamend.Containers

  @spec_base %{name: "gc-1", image: "ghcr.io/appsinacup/gamend:latest-slim"}

  test "the floor is always there, and the image comes last before the command" do
    args =
      Containers.create_args(
        Map.put(@spec_base, :command, ["bin/gamend_host", "start"]),
        "/tmp/env"
      )

    assert Enum.take(args, 5) == ["create", "--name", "gc-1", "--env-file", "/tmp/env"]
    assert "--cap-drop=ALL" in args
    assert "--security-opt=no-new-privileges" in args
    assert "--pids-limit=1024" in args
    assert Enum.take(args, -3) == [@spec_base.image, "bin/gamend_host", "start"]
    refute Enum.any?(args, &String.starts_with?(&1, "--runtime"))
  end

  test "a failure's reason is podman's line, not a usage error's closing hint" do
    assert Containers.failure_line("Error: unknown flag: --runtime\nSee 'podman create --help'\n") ==
             "Error: unknown flag: --runtime"

    assert Containers.failure_line("pulling\nError: no space left on device\n") ==
             "Error: no space left on device"

    assert Containers.failure_line("") == ""
  end

  test "limits, ports, mounts and labels are spelt as podman reads them" do
    spec =
      Map.merge(@spec_base, %{
        memory_mb: 512,
        cpus: 0.5,
        runtime: "runsc",
        read_only: true,
        tmpfs: ["/tmp:rw,size=64m"],
        ports: [{"127.0.0.1", 20_001, 4000}],
        volumes: [{"gc-1-data", "/data", :rw}],
        labels: %{"gamend.cloud" => "1"}
      })

    args = Containers.create_args(spec, "/tmp/env")

    for flag <- [
          "--memory=512m",
          "--memory-swap=512m",
          "--cpus=0.50",
          "--runtime=runsc",
          "--read-only"
        ],
        do: assert(flag in args)

    assert ["--tmpfs", "/tmp:rw,size=64m"] == pair(args, "--tmpfs")
    assert ["--publish", "127.0.0.1:20001:4000"] == pair(args, "--publish")
    assert ["--volume", "gc-1-data:/data:rw"] == pair(args, "--volume")
    assert ["--label", "gamend.cloud=1"] == pair(args, "--label")
  end

  test "networks replace the default, and the alias is spelt once" do
    spec = Map.merge(@spec_base, %{networks: ["podman", "gc-1"], network_alias: "gc-1-app"})
    args = Containers.create_args(spec, "/tmp/env")

    assert [["--network", "podman"], ["--network", "gc-1"]] ==
             args |> Enum.chunk_every(2, 1) |> Enum.filter(&match?(["--network", _], &1))

    assert ["--network-alias", "gc-1-app"] == pair(args, "--network-alias")
    refute "--network" in Containers.create_args(@spec_base, "/tmp/env")
  end

  test "a user replaces the image's own, under the same floor" do
    args = Containers.create_args(Map.put(@spec_base, :user, "postgres"), "/tmp/env")

    assert ["--user", "postgres"] == pair(args, "--user")
    assert "--cap-drop=ALL" in args
    refute "--user" in Containers.create_args(@spec_base, "/tmp/env")
  end

  test "a volume taken over by the container's user is chowned as it is mounted" do
    spec =
      Map.merge(@spec_base, %{user: "20001:20001", volumes: [{"gc-1-data", "/data", :chown}]})

    assert ["--volume", "gc-1-data:/data:rw,U"] ==
             pair(Containers.create_args(spec, "/tmp/env"), "--volume")
  end

  test "a one-off run keeps the floor, as a user and on a chowned volume" do
    args =
      Containers.output_args("img", ["true"], [],
        user: "20001:20001",
        volumes: [{"gc-1-data", "/data", :chown}, {"gc-tools", "/opt/tools", :ro}]
      )

    for flag <- [
          "--network=none",
          "--read-only",
          "--cap-drop=ALL",
          "--security-opt=no-new-privileges"
        ],
        do: assert(flag in args)

    assert ["--user", "20001:20001"] == pair(args, "--user")

    assert [["--volume", "gc-1-data:/data:rw,U"], ["--volume", "gc-tools:/opt/tools:ro"]] ==
             args |> Enum.chunk_every(2, 1) |> Enum.filter(&match?(["--volume", _], &1))

    assert Enum.take(args, -2) == ["img", "true"]
  end

  test "a volume is made once, owned by a user when asked" do
    assert Containers.create_volume_args("gc-1-data", %{}, []) ==
             ["volume", "create", "--ignore", "gc-1-data"]

    assert Containers.create_volume_args("gc-1-data", %{"gamend.cloud" => "1"},
             owner: {20_001, 20_001}
           ) ==
             [
               "volume",
               "create",
               "--ignore",
               "--label",
               "gamend.cloud=1",
               "--opt",
               "o=uid=20001,gid=20001",
               "gc-1-data"
             ]
  end

  test "a network is made once, internal when asked" do
    assert Containers.create_network_args("gc-1", []) ==
             ["network", "create", "--ignore", "gc-1"]

    assert Containers.create_network_args("gc-1",
             internal: true,
             labels: %{"gamend.cloud" => "1"}
           ) ==
             ["network", "create", "--ignore", "--internal", "--label", "gamend.cloud=1", "gc-1"]
  end

  describe "build" do
    setup do
      context =
        Path.join(System.tmp_dir!(), "containers-build-#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(context, "docker"))
      File.write!(Path.join(context, "Dockerfile"), "FROM scratch\n")
      File.write!(Path.join(context, "docker/Dockerfile.release"), "FROM scratch\n")
      on_exit(fn -> File.rm_rf(context) end)

      %{context: context}
    end

    test "every option is spelt as podman build reads it, the context last", %{context: context} do
      args =
        Containers.build_args(
          context,
          [
            tag: "localhost/gc/1:abc",
            dockerfile: "docker/Dockerfile.release",
            target: "release",
            args: %{"GAMEND_DB_ADAPTER" => "postgres"},
            labels: %{"gamend.cloud.server" => "1"},
            memory_mb: 8192,
            cpus: 4,
            runtime: "runsc",
            network: false
          ],
          "/tmp/iid"
        )

      assert Enum.take(args, 5) == [
               "build",
               "--tag",
               "localhost/gc/1:abc",
               "--iidfile",
               "/tmp/iid"
             ]

      assert ["--file", Path.join(context, "docker/Dockerfile.release")] == pair(args, "--file")
      assert ["--target", "release"] == pair(args, "--target")
      assert ["--build-arg", "GAMEND_DB_ADAPTER=postgres"] == pair(args, "--build-arg")
      assert ["--label", "gamend.cloud.server=1"] == pair(args, "--label")

      for flag <- [
            "--memory=8192m",
            "--memory-swap=8192m",
            "--cpu-period=100000",
            "--cpu-quota=400000",
            "--runtime=runsc",
            "--network=none"
          ],
          do: assert(flag in args)

      assert List.last(args) == context
    end

    test "by default podman finds the Dockerfile, and the network is on", %{context: context} do
      args = Containers.build_args(context, [tag: "t"], "/tmp/iid")

      refute "--file" in args
      refute "--target" in args
      refute Enum.any?(args, &String.starts_with?(&1, "--network"))
      refute Enum.any?(args, &String.starts_with?(&1, "--cpu"))
    end

    test "a Dockerfile outside the context is refused before podman is asked", %{context: context} do
      assert {:error, {:unsafe_dockerfile, "../Dockerfile"}} =
               Containers.build(context, tag: "t", dockerfile: "../Dockerfile")

      assert {:error, {:unsafe_dockerfile, "/etc/hosts"}} =
               Containers.build(context, tag: "t", dockerfile: "/etc/hosts")

      assert {:error, {:unsafe_dockerfile, "docker"}} =
               Containers.build(context, tag: "t", dockerfile: "docker")
    end

    test "a symlink on the way to the Dockerfile is refused", %{context: context} do
      outside = Path.join(context <> "-outside", "etc")
      File.mkdir_p!(outside)
      File.write!(Path.join(outside, "passwd"), "FROM scratch\n")
      on_exit(fn -> File.rm_rf(context <> "-outside") end)

      File.ln_s!(outside, Path.join(context, "linked"))
      File.ln_s!(Path.join(outside, "passwd"), Path.join(context, "Dockerfile.link"))

      assert {:error, {:unsafe_dockerfile, "linked/passwd"}} =
               Containers.build(context, tag: "t", dockerfile: "linked/passwd")

      assert {:error, {:unsafe_dockerfile, "Dockerfile.link"}} =
               Containers.build(context, tag: "t", dockerfile: "Dockerfile.link")
    end

    test "a missing context or Dockerfile is not found", %{context: context} do
      assert {:error, :not_found} = Containers.build(context <> "-missing", tag: "t")

      assert {:error, :not_found} =
               Containers.build(context, tag: "t", dockerfile: "nope/Dockerfile")
    end
  end

  describe "run_port" do
    test "answers the exit status and the output, and hands each piece over as it comes" do
      parent = self()

      assert {:exited, 3, "one\ntwo\n"} =
               Containers.run_port("/bin/sh", ["-c", "echo one; echo two >&2; exit 3"],
                 on_output: &send(parent, {:piece, &1})
               )

      assert_received {:piece, _}
    end

    test "past its time a program is stopped, and what it printed is kept" do
      started = System.monotonic_time(:millisecond)

      assert {:timeout, "started\n"} =
               Containers.run_port("/bin/sh", ["-c", "echo started; exec sleep 30"],
                 timeout_ms: 300
               )

      assert System.monotonic_time(:millisecond) - started < 5_000
      refute_receive {_port, {:exit_status, _}}, 100
    end

    test "a program that ignores SIGTERM is killed after the grace" do
      script = "trap '' TERM; echo started; exec sleep 30"

      assert {:timeout, "started\n"} =
               Containers.run_port("/bin/sh", ["-c", script], timeout_ms: 300, kill_grace_ms: 300)

      refute_receive {_port, {:exit_status, _}}, 100
    end

    test "only the end of a long output is kept, from a whole line" do
      script = "i=0; while [ $i -lt 20000 ]; do echo line-$i; i=$((i+1)); done"

      assert {:exited, 0, log} = Containers.run_port("/bin/sh", ["-c", script], [])
      assert byte_size(log) <= 64 * 1024
      assert String.starts_with?(log, "line-")
      assert String.ends_with?(log, "line-19999\n")
    end
  end

  test "a newline in a value is refused before podman is asked" do
    spec = Map.put(@spec_base, :env, %{"OK" => "1", "BAD" => "a\nINJECTED=1"})

    assert {:error, {:unsafe_env, "BAD"}} = Containers.create(spec)
  end

  test "an env file is its owner's only, and holds one line a variable" do
    path = Path.join(System.tmp_dir!(), "containers-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)

    assert :ok = Containers.write_env_file(path, %{"A" => "1", "B" => "two words"})
    assert %File.Stat{mode: mode} = File.stat!(path)
    assert Bitwise.band(mode, 0o777) == 0o600
    assert path |> File.read!() |> String.split("\n") |> Enum.sort() == ["A=1", "B=two words"]
  end

  defp pair(args, flag) do
    index = Enum.find_index(args, &(&1 == flag))
    Enum.slice(args, index, 2)
  end
end
