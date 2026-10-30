defmodule Gamend.Containers do
  @moduledoc """
  Long-lived OCI containers, and the images they run, through the `podman` CLI.

  For a host that runs other programs beside itself on the machine it is on:
  a hosted Gamend per customer, a build sandbox. It is the CLI's verbs and
  nothing about what runs in them, so a host decides the limits, the mounts
  and the network, and this module only spells them as flags.

  Podman rather than Docker because it is rootless and has no root daemon to
  talk to. `:runtime` in a spec (`"runsc"`, `"kata-runtime"`) is how a host
  raises isolation without another driver: the same flags, a different OCI
  runtime.

  ## Errors

  Every call answers `{:error, reason}` on an expected failure:

    * `:podman_not_found` — no `podman` on the PATH.
    * `:not_found` — no such container, volume, network, image or build
      context.
    * `{:podman_failed, verb, status, line}` — the CLI exited non-zero; `line`
      is its last line of output, which is where podman puts the reason
      (before a usage error's `See 'podman … --help'`, which is skipped).

  A build answers its own, since its reason is a compiler's output, not
  podman's last line (`build/2`).

  ## Secrets

  Environment goes through a mode-0600 `--env-file`, never `-e`: arguments
  are world-readable in `ps`. The file is created empty at 0600 before the
  values are written, so they are never readable by another user, and it is
  removed as soon as `podman create` has read it.

  ## Users

  Rootless podman runs uid 0 of a container as the host user that runs
  podman, which owns every container, image and volume here, and any other
  uid as one of that user's subordinate uids. A container running someone
  else's code therefore runs as a numeric `:user` of its own, one per owner
  and never given to another while that owner's volumes exist, its volumes
  made for it (`create_volume/3`'s `owner:`) or re-owned as they are mounted
  (`:chown`). A way out of it lands on a uid that owns that owner's files
  and nothing else.

  There is no `--userns=auto`. Rootless, each new mapping copies the image's
  layers chowned to it (6 s and 170 MB for a Gamend image, kept after the
  container is gone), a freed range goes to the next container while files
  written under it keep their owner, and an `idmap` volume is refused
  (podman 5.3).
  """

  require Logger

  @type port_map :: {host_ip :: String.t(), host_port :: pos_integer(), port :: pos_integer()}
  @type mount :: {source :: String.t(), target :: String.t(), :rw | :ro | :chown}

  @typedoc """
  One container.

  `:volumes` sources are podman volume names or absolute host paths, mounted
  `:rw`, `:ro` or `:chown`: read-write once podman has chowned the source,
  recursively and on every start, to the user the container runs as. That
  is how a volume another user wrote passes to the container's own (a
  server's from before it had a uid); never on one another owner's
  container mounts too, which would belong to whichever started last.
  `:tmpfs` entries are `"/path:options"`, as podman's `--tmpfs` takes them.

  `:networks` are the networks it joins (`create_network/2`), in place of
  podman's default. A container that must still reach the internet joins a
  network the host made beside an internal one, never `"podman"`: the
  default has no DNS, so beside an internal network the container would
  resolve only that network's names (podman 5.3). `:network_alias` is a
  name the others on those networks reach it by, besides its own.

  `:user` runs it as that user instead of the image's own: a name, `"uid"`
  or `"uid:gid"`. An image that starts as root to drop to its user (a
  database's entrypoint) runs under the floor's dropped capabilities only
  when it starts as that user. A name is looked up in the image's own
  `/etc/passwd`, which can map it to 0, so an image someone else built gets
  `"uid:gid"` (a uid alone that its passwd lacks runs in group 0). It is the
  host's to choose, never an owner's (see Users above).
  """
  @type spec :: %{
          required(:name) => String.t(),
          required(:image) => String.t(),
          optional(:env) => %{String.t() => String.t()},
          optional(:networks) => [String.t()],
          optional(:network_alias) => String.t(),
          optional(:user) => String.t(),
          optional(:ports) => [port_map()],
          optional(:volumes) => [mount()],
          optional(:tmpfs) => [String.t()],
          optional(:labels) => %{String.t() => String.t()},
          optional(:memory_mb) => pos_integer(),
          optional(:cpus) => number(),
          optional(:pids) => pos_integer(),
          optional(:runtime) => String.t() | nil,
          optional(:read_only) => boolean(),
          optional(:command) => [String.t()]
        }

  @typedoc "What podman says a container is doing."
  @type state :: :created | :running | :paused | :exited | :stopping | :removing | :unknown

  # ── Containers ──────────────────────────────────────────────────────────

  @doc "Create a container from `spec`, not started. Answers its id."
  @spec create(spec()) :: {:ok, String.t()} | {:error, term()}
  def create(%{name: name, image: image} = spec) when is_binary(name) and is_binary(image) do
    env_file = temp_path("gamend-env-")

    with :ok <- write_env_file(env_file, Map.get(spec, :env, %{})) do
      try do
        case podman(create_args(spec, env_file)) do
          {:ok, {out, 0}} -> {:ok, out |> String.trim() |> last_line()}
          other -> failed(:create, other)
        end
      after
        File.rm(env_file)
      end
    end
  end

  @doc "Start a created or stopped container."
  @spec start(String.t()) :: :ok | {:error, term()}
  def start(name), do: run_verb(:start, ["start", name])

  @doc "Stop a container, killing it after `timeout_s` seconds."
  @spec stop(String.t(), non_neg_integer()) :: :ok | {:error, term()}
  def stop(name, timeout_s \\ 10),
    do: run_verb(:stop, ["stop", "--time", Integer.to_string(timeout_s), name])

  @doc """
  Freeze a running container (the cgroup freezer): it keeps its memory and
  uses no CPU. `unpause/1` thaws it in milliseconds.
  """
  @spec pause(String.t()) :: :ok | {:error, term()}
  def pause(name), do: run_verb(:pause, ["pause", name])

  @doc "Thaw a paused container."
  @spec unpause(String.t()) :: :ok | {:error, term()}
  def unpause(name), do: run_verb(:unpause, ["unpause", name])

  @doc "Remove a container, running or not. Its named volumes stay."
  @spec remove(String.t()) :: :ok | {:error, term()}
  def remove(name) do
    case run_verb(:remove, ["rm", "--force", "--time", "10", name]) do
      {:error, :not_found} -> :ok
      other -> other
    end
  end

  @doc """
  Kill a container at once (SIGKILL). One started with `--rm` is removed with
  it, which is how a host stops a job past its time.
  """
  @spec kill(String.t()) :: :ok | {:error, term()}
  def kill(name), do: run_verb(:kill, ["kill", name])

  @doc """
  Change a container's limits while it runs: `cpus:`, `memory_mb:` and
  `pids:`, all three required.

  A host gives a booting container more CPU than its size and takes it back
  once it answers, since a boot is the one time a small server is CPU-bound.

  All three because podman 5 writes the whole resource set on an update: a
  call with only `--cpus` left the container with no memory and no pids
  limit (`memory.max` read `max` afterwards, podman 5.3.1).
  """
  @spec update(String.t(), keyword()) :: :ok | {:error, term()}
  def update(name, limits) do
    cpus = Keyword.fetch!(limits, :cpus)
    mb = Keyword.fetch!(limits, :memory_mb)
    pids = Keyword.fetch!(limits, :pids)

    flags = [
      "--cpus",
      format_cpus(cpus),
      "--memory",
      "#{mb}m",
      "--memory-swap",
      "#{mb}m",
      "--pids-limit",
      Integer.to_string(pids)
    ]

    run_verb(:update, Enum.concat([["update"], flags, [name]]))
  end

  @doc "This machine's memory and CPUs, as podman sees them."
  @spec info() :: {:ok, %{memory_mb: non_neg_integer(), cpus: pos_integer()}} | {:error, term()}
  def info do
    case podman(["info", "--format", "{{.Host.MemTotal}} {{.Host.CPUs}}"]) do
      {:ok, {out, 0}} ->
        [memory, cpus] = out |> String.trim() |> String.split(" ", parts: 2)

        {:ok,
         %{memory_mb: div(String.to_integer(memory), 1_048_576), cpus: String.to_integer(cpus)}}

      other ->
        failed(:info, other)
    end
  end

  @doc """
  Memory in use and CPU of every running container, by name, in one call:
  `%{"name" => %{memory_bytes: n, cpu_percent: f}}`.
  """
  @spec stats() ::
          {:ok, %{String.t() => %{memory_bytes: non_neg_integer(), cpu_percent: float()}}}
          | {:error, term()}
  def stats do
    case podman(["stats", "--no-stream", "--no-reset", "--format", "{{json .}}"]) do
      {:ok, {out, 0}} ->
        {:ok,
         out
         |> String.split("\n", trim: true)
         |> Enum.flat_map(fn line ->
           case Jason.decode(line) do
             {:ok, %{"Name" => name} = row} ->
               [
                 {name,
                  %{
                    memory_bytes: row["MemUsage"] || 0,
                    cpu_percent: (row["CPU"] || 0) * 1.0
                  }}
               ]

             _ ->
               []
           end
         end)
         |> Map.new()}

      other ->
        failed(:stats, other)
    end
  end

  @doc "What a container is doing, or `{:error, :not_found}`."
  @spec state(String.t()) :: {:ok, state()} | {:error, term()}
  def state(name) do
    case podman(["container", "inspect", "--format", "{{.State.Status}}", name]) do
      {:ok, {out, 0}} -> {:ok, parse_state(String.trim(out))}
      other -> failed(:inspect, other)
    end
  end

  @doc "A container's last `tail` lines of output, stdout and stderr together."
  @spec logs(String.t(), pos_integer()) :: {:ok, String.t()} | {:error, term()}
  def logs(name, tail \\ 200) do
    case podman(["logs", "--tail", Integer.to_string(tail), name]) do
      {:ok, {out, 0}} -> {:ok, out}
      other -> failed(:logs, other)
    end
  end

  @doc """
  Run `argv` inside a running container and answer what it printed, stdout
  and stderr together. A non-zero exit is `{:podman_failed, :exec, status, line}`.
  """
  @spec exec(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, term()}
  def exec(name, argv) when is_list(argv) do
    case podman(["exec", name | argv]) do
      {:ok, {out, 0}} -> {:ok, out}
      other -> failed(:exec, other)
    end
  end

  @doc """
  Every container carrying `label` (`key=value`), any state, by name: one
  call for a whole machine, where `state/1` per container would be one each.
  """
  @spec list(String.t()) :: {:ok, %{String.t() => state()}} | {:error, term()}
  def list(label) do
    args = ["ps", "--all", "--filter", "label=#{label}", "--format", "{{.Names}} {{.State}}"]

    case podman(args) do
      {:ok, {out, 0}} ->
        {:ok,
         out
         |> String.split("\n", trim: true)
         |> Map.new(fn line ->
           [name | rest] = String.split(line, " ", parts: 2)
           {name, parse_state(String.trim(Enum.join(rest)))}
         end)}

      other ->
        failed(:list, other)
    end
  end

  # ── Volumes ─────────────────────────────────────────────────────────────

  @doc """
  Create a named volume; one that exists already is fine, as it is.

  `opts`: `owner: {uid, gid}` gives a new volume's root to that user, for a
  container that runs as `user: "uid:gid"`. One that exists keeps its owner;
  a `:chown` mount re-owns it.
  """
  @spec create_volume(String.t(), %{String.t() => String.t()}, keyword()) ::
          :ok | {:error, term()}
  def create_volume(name, labels \\ %{}, opts \\ []),
    do: run_verb(:create_volume, create_volume_args(name, labels, opts))

  @doc false
  # Public so a test can read the flags without podman.
  @spec create_volume_args(String.t(), %{String.t() => String.t()}, keyword()) :: [String.t()]
  def create_volume_args(name, labels, opts) do
    Enum.concat([
      ["volume", "create", "--ignore"],
      label_args(labels),
      case Keyword.get(opts, :owner) do
        {uid, gid} when is_integer(uid) and is_integer(gid) ->
          ["--opt", "o=uid=#{uid},gid=#{gid}"]

        nil ->
          []
      end,
      [name]
    ])
  end

  @doc "Remove a named volume and everything in it."
  @spec remove_volume(String.t()) :: :ok | {:error, term()}
  def remove_volume(name) do
    case run_verb(:remove_volume, ["volume", "rm", "--force", name]) do
      {:error, :not_found} -> :ok
      other -> other
    end
  end

  # ── Networks ────────────────────────────────────────────────────────────

  @doc """
  Create a network; one that exists already is fine, as it is.

  `opts`: `internal: true` for a network with no way out, which only its
  containers reach each other on (a server and its database); `labels:`.
  Containers on a network a host made reach each other by name.
  """
  @spec create_network(String.t(), keyword()) :: :ok | {:error, term()}
  def create_network(name, opts \\ []),
    do: run_verb(:create_network, create_network_args(name, opts))

  # No `--force`: podman's removes every container on the network with it.
  @doc """
  Remove a network no container is on. One that is not there is fine; one
  a container is still on is a `:podman_failed` error.
  """
  @spec remove_network(String.t()) :: :ok | {:error, term()}
  def remove_network(name) do
    case run_verb(:remove_network, ["network", "rm", name]) do
      {:error, :not_found} -> :ok
      other -> other
    end
  end

  @doc false
  # Public so a test can read the flags without podman.
  @spec create_network_args(String.t(), keyword()) :: [String.t()]
  def create_network_args(name, opts) do
    Enum.concat([
      ["network", "create", "--ignore"],
      if(Keyword.get(opts, :internal, false), do: ["--internal"], else: []),
      label_args(Keyword.get(opts, :labels, %{})),
      [name]
    ])
  end

  # ── Builds ──────────────────────────────────────────────────────────────

  # What a build keeps of its output: the end, where a compiler's error is.
  @build_log_bytes 64 * 1024

  # After a build's time is up: how long it has to stop on SIGTERM before
  # SIGKILL.
  @build_kill_grace_ms 10_000

  @doc """
  Build an image from the directory `context` with its Dockerfile, and name
  it `tag:`. Answers the image's id and the end of the build's output:
  `{:ok, %{id: "sha256:…", log: "…"}}`.

  `opts`:

    * `tag:` — the name, required.
    * `dockerfile:` — the file, relative to `context` and inside it
      (podman's own `Containerfile`, then `Dockerfile`, when not given). A
      file outside it, or a symlink, is refused with `{:unsafe_dockerfile,
      path}`: the CLI reads it from this machine, so it could be anything
      here.
    * `target:` — the stage to build; the last one when not given.
    * `args:` — `%{"NAME" => "value"}` for the Dockerfile's `ARG`s. Never a
      secret: they are in the image's history and on the command line.
    * `labels:` — set on the image.
    * `memory_mb:`, `cpus:` — what the build's `RUN` steps may use.
    * `runtime:` — the OCI runtime its `RUN` steps run under (`runsc`).
      A podman CLI talking to a remote service (`CONTAINER_HOST`) does not
      take one, and the build fails on it.
    * `network: false` — no network for `RUN` steps. On by default, since
      a build fetches its dependencies.
    * `timeout_ms:` — the build is stopped past it, SIGTERM then SIGKILL
      #{div(@build_kill_grace_ms, 1000)} s later, and answers `{:build_timeout,
      log}`. Through a remote service (podman 5.3), the build stopped there
      too, with no image and no working container left. No limit by
      default.
    * `on_output:` — a function given each piece of output as it comes,
      for a host showing the build live. Of arity 2, it is given the end
      of the output so far too (the `log` the answer would have now), for
      a host keeping it as it goes, so a page opened mid-build has it.

  No hardening floor, unlike `create/1`: a Dockerfile's `RUN` expects the
  root a build normally has (apt drops to its own user with `setgroups`,
  which a container without capabilities refuses). Rootless podman, and
  `runtime:` for someone else's Dockerfile, are what keep a build in.

  Errors besides the module's: `{:build_failed, status, log}`, the build's
  exit status and the end of its output, and `{:build_timeout, log}`.
  """
  @spec build(Path.t(), keyword()) ::
          {:ok, %{id: String.t(), log: String.t()}} | {:error, term()}
  def build(context, opts) when is_binary(context) and is_list(opts) do
    iidfile = temp_path("gamend-iid-")

    with :ok <- check_context(context),
         :ok <- check_dockerfile(context, Keyword.get(opts, :dockerfile)),
         {:ok, podman} <- executable() do
      try do
        case run_port(podman, build_args(context, opts, iidfile), opts) do
          {:exited, 0, log} -> read_iid(iidfile, log)
          {:exited, status, log} -> {:error, {:build_failed, status, log}}
          {:timeout, log} -> {:error, {:build_timeout, log}}
        end
      after
        File.rm(iidfile)
      end
    end
  end

  @doc false
  # Public so a test can read the flags without podman.
  @spec build_args(Path.t(), keyword(), Path.t()) :: [String.t()]
  def build_args(context, opts, iidfile) do
    Enum.concat([
      ["build", "--tag", Keyword.fetch!(opts, :tag), "--iidfile", iidfile],
      if(file = Keyword.get(opts, :dockerfile),
        do: ["--file", Path.expand(file, context)],
        else: []
      ),
      if(target = Keyword.get(opts, :target), do: ["--target", target], else: []),
      Enum.flat_map(Keyword.get(opts, :args, %{}), fn {k, v} -> ["--build-arg", "#{k}=#{v}"] end),
      label_args(Keyword.get(opts, :labels, %{})),
      memory_args(Keyword.get(opts, :memory_mb)),
      build_cpu_args(Keyword.get(opts, :cpus)),
      runtime_args(Keyword.get(opts, :runtime)),
      if(Keyword.get(opts, :network, true), do: [], else: ["--network=none"]),
      [context]
    ])
  end

  defp check_context(context) do
    if File.dir?(context), do: :ok, else: {:error, :not_found}
  end

  defp check_dockerfile(_context, nil), do: :ok

  # Inside `context` by its path, and by every directory on the way: a
  # symlinked directory in a repository could point anywhere on this machine.
  defp check_dockerfile(context, file) do
    root = Path.expand(context)
    path = Path.expand(file, root)

    if String.starts_with?(path, root <> "/") do
      path
      |> Path.relative_to(root)
      |> Path.split()
      |> Enum.scan(root, &Path.join(&2, &1))
      |> Enum.reduce_while(:ok, fn step, :ok ->
        case File.lstat(step) do
          {:ok, %File.Stat{type: :symlink}} -> {:halt, {:error, {:unsafe_dockerfile, file}}}
          {:ok, _stat} -> {:cont, :ok}
          {:error, _} -> {:halt, {:error, :not_found}}
        end
      end)
      |> regular_file(path, file)
    else
      {:error, {:unsafe_dockerfile, file}}
    end
  end

  defp regular_file(:ok, path, file) do
    if File.regular?(path), do: :ok, else: {:error, {:unsafe_dockerfile, file}}
  end

  defp regular_file(error, _path, _file), do: error

  defp read_iid(iidfile, log) do
    case File.read(iidfile) do
      {:ok, id} -> {:ok, %{id: String.trim(id), log: log}}
      {:error, _} -> {:error, {:build_failed, 0, log}}
    end
  end

  # A build has no `--cpus`: a quota of the default 100 ms period is the
  # same share.
  defp build_cpu_args(nil), do: []

  defp build_cpu_args(cpus),
    do: ["--cpu-period=100000", "--cpu-quota=#{round(cpus * 100_000)}"]

  @doc false
  # Public so a test can time a program out without podman. Runs `path`
  # through a port, gives `on_output:` each piece, keeps the end of what it
  # printed, and past `timeout_ms:` stops it: SIGTERM, then SIGKILL
  # `kill_grace_ms:` later (a test's, shorter than a build's).
  @spec run_port(Path.t(), [String.t()], keyword()) ::
          {:exited, non_neg_integer(), String.t()} | {:timeout, String.t()}
  def run_port(path, args, opts) do
    Logger.debug("#{Path.basename(path)} #{Enum.join(args, " ")}")

    port =
      Port.open({:spawn_executable, path}, [:binary, :exit_status, :stderr_to_stdout, args: args])

    deadline =
      case Keyword.get(opts, :timeout_ms) do
        nil -> :infinity
        ms -> System.monotonic_time(:millisecond) + ms
      end

    grace_ms = Keyword.get(opts, :kill_grace_ms, @build_kill_grace_ms)
    collect(port, deadline, grace_ms, Keyword.get(opts, :on_output), "")
  end

  defp collect(port, deadline, grace_ms, on_output, log) do
    receive do
      {^port, {:data, chunk}} ->
        log = keep_end(log <> chunk)
        give_output(on_output, chunk, log)
        collect(port, deadline, grace_ms, on_output, log)

      {^port, {:exit_status, status}} ->
        {:exited, status, log}
    after
      remaining(deadline) ->
        stop_port(port, grace_ms)
        {:timeout, log}
    end
  end

  defp give_output(nil, _chunk, _log), do: :ok
  defp give_output(on_output, chunk, _log) when is_function(on_output, 1), do: on_output.(chunk)

  defp give_output(on_output, chunk, log) when is_function(on_output, 2),
    do: on_output.(chunk, log)

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  # Waits for the exit after each signal, so no `exit_status` reaches the
  # caller's mailbox later.
  defp stop_port(port, grace_ms) do
    with {:os_pid, pid} <- Port.info(port, :os_pid) do
      signal(pid, "TERM")

      if not exited?(port, grace_ms) do
        signal(pid, "KILL")
        exited?(port, grace_ms)
      end
    end

    flush_port(port)
  end

  defp exited?(port, wait_ms) do
    receive do
      {^port, {:exit_status, _status}} -> true
    after
      wait_ms -> false
    end
  end

  defp signal(pid, name), do: System.cmd("kill", ["-" <> name, Integer.to_string(pid)])

  defp flush_port(port) do
    receive do
      {^port, _message} -> flush_port(port)
    after
      0 -> :ok
    end
  end

  # From the first whole line once cut, so the end holds no half of a
  # character.
  defp keep_end(log) when byte_size(log) <= @build_log_bytes, do: log

  defp keep_end(log) do
    cut = binary_part(log, byte_size(log) - @build_log_bytes, @build_log_bytes)

    case :binary.split(cut, "\n") do
      [_partial, rest] -> rest
      [_no_newline] -> cut
    end
  end

  # ── Images ──────────────────────────────────────────────────────────────

  @doc "Whether the image store has `image`."
  @spec image_exists?(String.t()) :: boolean()
  def image_exists?(image), do: match?({:ok, {_out, 0}}, podman(["image", "exists", image]))

  # `-q` so a gigabyte's progress bars are not what comes back.
  @doc "Pull `image` into the image store."
  @spec pull(String.t()) :: :ok | {:error, term()}
  def pull(image), do: run_verb(:pull, ["pull", "-q", image])

  @doc "Give the image `image` names a second name, `ref`."
  @spec tag(String.t(), String.t()) :: :ok | {:error, term()}
  def tag(image, ref), do: run_verb(:tag, ["tag", image, ref])

  # No `--force`: a container still running on the image is why it is kept.
  @doc """
  Drop the name `ref`. An image goes with its last name, unless a container
  holds it.
  """
  @spec untag(String.t()) :: :ok | {:error, term()}
  def untag(ref), do: run_verb(:untag, ["rmi", ref])

  @doc "Every `repo:tag` name of `repo` in the image store."
  @spec tags(String.t()) :: [String.t()]
  def tags(repo) do
    args = ["images", "--format", "{{.Repository}}:{{.Tag}}", "--filter", "reference=#{repo}"]

    case podman(args) do
      {:ok, {out, 0}} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.starts_with?(&1, repo <> ":"))

      _other ->
        []
    end
  end

  @doc """
  What `argv` prints, run once in `image` and removed: no network, a
  read-only root, no capabilities, and no pull. For asking an image what it
  holds (a version string), or a short chore on a volume, never for running
  a job.

  `opts`: `volumes:` (`{source, target, :ro | :rw | :chown}`), `tmpfs:`,
  `entrypoint:` to run something other than the image's own, `user:` (as
  `create/1` takes them both), `env:` (through
  a 0600 env file, as `create/1`), and `network: true` for a chore that must
  reach the network (a restore from a bucket). A chore running someone
  else's code (a build of a tenant's plugin) takes the limits `create/1`
  does: `memory_mb:`, `cpus:`, `pids:` and `runtime:` (`runsc`).
  """
  @spec output(String.t(), [String.t()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def output(image, argv, opts \\ []) when is_list(argv) do
    case Keyword.get(opts, :env, %{}) do
      env when map_size(env) == 0 ->
        run_output(image, argv, [], opts)

      env ->
        env_file = temp_path("gamend-env-")

        with :ok <- write_env_file(env_file, env) do
          try do
            run_output(image, argv, ["--env-file", env_file], opts)
          after
            File.rm(env_file)
          end
        end
    end
  end

  defp run_output(image, argv, env_args, opts) do
    case podman(output_args(image, argv, env_args, opts)) do
      {:ok, {out, 0}} -> {:ok, out}
      other -> failed(:output, other)
    end
  end

  @doc "Copy `path` out of a container, running or stopped, to `dest` on this machine."
  @spec copy_from(String.t(), String.t(), Path.t()) :: :ok | {:error, term()}
  def copy_from(name, path, dest), do: run_verb(:copy_from, ["cp", "#{name}:#{path}", dest])

  @doc """
  The tree at `path` in a container, running or stopped, as a tar archive in
  the file `dest` on this machine (`podman cp … -`), written as podman
  produces it and never held in memory: a volume's files handed over whole,
  however large. `{:error, :not_found}` for a container or a path that is
  not there.
  """
  @spec copy_tar(String.t(), String.t(), Path.t()) :: :ok | {:error, term()}
  def copy_tar(name, path, dest) do
    errors = temp_path("gamend-cp-")

    # The archive is stdout, so podman's own messages go to a file of their
    # own: mixed in, they would corrupt it.
    script = ~s|"$0" cp "$1" - > "$2" 2> "$3"|

    with {:ok, podman} <- executable() do
      try do
        case System.cmd("sh", ["-c", script, podman, "#{name}:#{path}", dest, errors]) do
          {_out, 0} ->
            :ok

          {_out, status} ->
            line = errors |> File.read() |> elem(1) |> to_string() |> last_line()

            if missing?(line) or String.contains?(String.downcase(line), "no such file"),
              do: {:error, :not_found},
              else: {:error, {:podman_failed, :copy_tar, status, line}}
        end
      after
        File.rm(errors)
      end
    end
  end

  @doc """
  One field of an image, through a Go template: `"{{.Digest}}"`, or
  `"{{range .Config.Env}}{{println .}}{{end}}"`.
  """
  @spec inspect_image(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def inspect_image(image, format) do
    case podman(["image", "inspect", "--format", format, image]) do
      {:ok, {out, 0}} -> {:ok, String.trim(out)}
      other -> failed(:inspect_image, other)
    end
  end

  # ── Flags ───────────────────────────────────────────────────────────────

  @doc false
  # Public so a test can read the flags `output/3` runs with without podman.
  @spec output_args(String.t(), [String.t()], [String.t()], keyword()) :: [String.t()]
  def output_args(image, argv, env_args, opts) do
    network = if Keyword.get(opts, :network, false), do: [], else: ["--network=none"]

    Enum.concat([
      ["run", "--rm", "--pull=never"],
      network,
      ["--read-only", "--cap-drop=ALL", "--security-opt=no-new-privileges"],
      if(user = Keyword.get(opts, :user), do: ["--user", user], else: []),
      runtime_args(Keyword.get(opts, :runtime)),
      memory_args(Keyword.get(opts, :memory_mb)),
      cpu_args(Keyword.get(opts, :cpus)),
      if(pids = Keyword.get(opts, :pids), do: ["--pids-limit=#{pids}"], else: []),
      env_args,
      volume_args(Keyword.get(opts, :volumes, [])),
      Enum.flat_map(Keyword.get(opts, :tmpfs, []), &["--tmpfs", &1]),
      entrypoint_args(Keyword.get(opts, :entrypoint)),
      [image],
      argv
    ])
  end

  @doc false
  # Public so a test can read the flags a spec becomes without podman.
  @spec create_args(spec(), String.t()) :: [String.t()]
  def create_args(spec, env_file) do
    Enum.concat([
      ["create", "--name", spec.name, "--env-file", env_file],
      runtime_args(Map.get(spec, :runtime)),
      if(user = Map.get(spec, :user), do: ["--user", user], else: []),
      [
        "--cap-drop=ALL",
        "--security-opt=no-new-privileges",
        "--pids-limit=#{Map.get(spec, :pids, 1024)}"
      ],
      read_only_args(Map.get(spec, :read_only, false)),
      memory_args(Map.get(spec, :memory_mb)),
      cpu_args(Map.get(spec, :cpus)),
      Enum.flat_map(Map.get(spec, :networks, []), &["--network", &1]),
      if(alias_name = Map.get(spec, :network_alias),
        do: ["--network-alias", alias_name],
        else: []
      ),
      Enum.flat_map(Map.get(spec, :tmpfs, []), &["--tmpfs", &1]),
      Enum.flat_map(Map.get(spec, :ports, []), fn {ip, host, port} ->
        ["--publish", "#{ip}:#{host}:#{port}"]
      end),
      volume_args(Map.get(spec, :volumes, [])),
      label_args(Map.get(spec, :labels, %{})),
      [spec.image],
      Map.get(spec, :command, [])
    ])
  end

  defp volume_args(volumes) do
    Enum.flat_map(volumes, fn {source, target, mode} ->
      ["--volume", "#{source}:#{target}:#{mount_mode(mode)}"]
    end)
  end

  # `U`: podman chowns the source to the container's user before it starts.
  defp mount_mode(:rw), do: "rw"
  defp mount_mode(:ro), do: "ro"
  defp mount_mode(:chown), do: "rw,U"

  defp label_args(labels), do: Enum.flat_map(labels, fn {k, v} -> ["--label", "#{k}=#{v}"] end)

  defp entrypoint_args(nil), do: []
  defp entrypoint_args(entrypoint), do: ["--entrypoint", entrypoint]

  defp runtime_args(nil), do: []
  defp runtime_args(""), do: []
  defp runtime_args(runtime), do: ["--runtime=#{runtime}"]

  defp read_only_args(true), do: ["--read-only"]
  defp read_only_args(_), do: []

  # Swap equal to memory: a server over its limit is killed, rather than
  # paging a whole machine's disk for one tenant.
  defp memory_args(nil), do: []
  defp memory_args(mb), do: ["--memory=#{mb}m", "--memory-swap=#{mb}m"]

  defp cpu_args(nil), do: []
  defp cpu_args(cpus), do: ["--cpus=#{format_cpus(cpus)}"]

  defp format_cpus(cpus) when is_integer(cpus), do: Integer.to_string(cpus)
  defp format_cpus(cpus) when is_float(cpus), do: :erlang.float_to_binary(cpus, decimals: 2)

  # ── The CLI ─────────────────────────────────────────────────────────────

  defp run_verb(verb, args) do
    case podman(args) do
      {:ok, {_out, 0}} -> :ok
      other -> failed(verb, other)
    end
  end

  @doc """
  The `podman` executable, for a host that runs it itself: a job whose output
  it streams through a port as it comes.
  """
  @spec executable() :: {:ok, String.t()} | {:error, :podman_not_found}
  def executable do
    case System.find_executable("podman") do
      nil -> {:error, :podman_not_found}
      path -> {:ok, path}
    end
  end

  defp podman(args) do
    with {:ok, podman} <- executable() do
      Logger.debug("podman #{Enum.join(args, " ")}")
      {:ok, System.cmd(podman, args, stderr_to_stdout: true)}
    end
  end

  defp failed(_verb, {:error, reason}), do: {:error, reason}

  defp failed(verb, {:ok, {out, status}}) do
    line = failure_line(out)

    if missing?(line),
      do: {:error, :not_found},
      else: {:error, {:podman_failed, verb, status, line}}
  end

  # Podman's own words for a name it does not have, across containers,
  # volumes and images.
  defp missing?(line) do
    down = String.downcase(line)

    String.contains?(down, [
      "no such container",
      "no such volume",
      "no such object",
      "no such image",
      "image not known",
      "network not found"
    ])
  end

  defp last_line(out) do
    case String.split(out, "\n", trim: true) do
      [] -> ""
      lines -> lines |> List.last() |> String.slice(0, 500)
    end
  end

  @doc false
  # Public so a test can read it without podman. The reason of a failure:
  # its last line, but for a usage error's closing hint (`See 'podman create
  # --help'`), which follows the line that says what was wrong (`Error:
  # unknown flag: --runtime`).
  @spec failure_line(String.t()) :: String.t()
  def failure_line(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.reject(&Regex.match?(~r/^See '.*--help'\.?$/, String.trim(&1)))
    |> Enum.join("\n")
    |> last_line()
  end

  defp parse_state("created"), do: :created
  defp parse_state("running"), do: :running
  defp parse_state("paused"), do: :paused
  defp parse_state("exited"), do: :exited
  defp parse_state("stopped"), do: :exited
  defp parse_state("stopping"), do: :stopping
  defp parse_state("removing"), do: :removing
  defp parse_state(_other), do: :unknown

  # ── The env file ────────────────────────────────────────────────────────

  @doc """
  Write `env` to `path` as a podman `--env-file`, readable by its owner only.

  The file is created empty at 0600 before the values go in, so they are
  never readable by another user, even for the moment between the two. A key
  or value holding a newline, a carriage return or a NUL is refused with
  `{:unsafe_env, key}`: the file is read a line at a time, so a newline in a
  value is a second `KEY=value` line the caller never set. The caller removes
  the file once podman has read it.
  """
  @spec write_env_file(Path.t(), %{String.t() => String.t()}) :: :ok | {:error, term()}
  def write_env_file(path, env) do
    with :ok <- check_env(env),
         :ok <- File.touch(path),
         :ok <- File.chmod(path, 0o600) do
      File.write(path, Enum.map_join(env, "\n", fn {k, v} -> "#{k}=#{v}" end))
    end
  end

  defp temp_path(prefix) do
    random = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    Path.join(System.tmp_dir!(), prefix <> random)
  end

  defp check_env(env) do
    case Enum.find(env, fn {k, v} -> unsafe?(k) or unsafe?(v) end) do
      nil -> :ok
      {key, _value} -> {:error, {:unsafe_env, key}}
    end
  end

  defp unsafe?(value) when is_binary(value), do: String.contains?(value, ["\n", "\r", "\0"])
  defp unsafe?(_value), do: true
end
