# `Gamend.Containers`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/containers.ex#L1)

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
    is its last line of output, which is where podman puts the reason.

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

# `mount`

```elixir
@type mount() :: {source :: String.t(), target :: String.t(), :rw | :ro | :chown}
```

# `port_map`

```elixir
@type port_map() ::
  {host_ip :: String.t(), host_port :: pos_integer(), port :: pos_integer()}
```

# `spec`

```elixir
@type spec() :: %{
  :name =&gt; String.t(),
  :image =&gt; String.t(),
  optional(:env) =&gt; %{required(String.t()) =&gt; String.t()},
  optional(:networks) =&gt; [String.t()],
  optional(:network_alias) =&gt; String.t(),
  optional(:user) =&gt; String.t(),
  optional(:ports) =&gt; [port_map()],
  optional(:volumes) =&gt; [mount()],
  optional(:tmpfs) =&gt; [String.t()],
  optional(:labels) =&gt; %{required(String.t()) =&gt; String.t()},
  optional(:memory_mb) =&gt; pos_integer(),
  optional(:cpus) =&gt; number(),
  optional(:pids) =&gt; pos_integer(),
  optional(:runtime) =&gt; String.t() | nil,
  optional(:read_only) =&gt; boolean(),
  optional(:command) =&gt; [String.t()]
}
```

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

# `state`

```elixir
@type state() ::
  :created | :running | :paused | :exited | :stopping | :removing | :unknown
```

What podman says a container is doing.

# `build`

```elixir
@spec build(Path.t(), keyword()) ::
  {:ok, %{id: String.t(), log: String.t()}} | {:error, term()}
```

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
    10 s later, and answers `{:build_timeout,
    log}`. Through a remote service (podman 5.3), the build stopped there
    too, with no image and no working container left. No limit by
    default.
  * `on_output:` — a function given each piece of output as it comes,
    for a host showing the build live.

No hardening floor, unlike `create/1`: a Dockerfile's `RUN` expects the
root a build normally has (apt drops to its own user with `setgroups`,
which a container without capabilities refuses). Rootless podman, and
`runtime:` for someone else's Dockerfile, are what keep a build in.

Errors besides the module's: `{:build_failed, status, log}`, the build's
exit status and the end of its output, and `{:build_timeout, log}`.

# `copy_from`

```elixir
@spec copy_from(String.t(), String.t(), Path.t()) :: :ok | {:error, term()}
```

Copy `path` out of a container, running or stopped, to `dest` on this machine.

# `copy_tar`

```elixir
@spec copy_tar(String.t(), String.t(), Path.t()) :: :ok | {:error, term()}
```

The tree at `path` in a container, running or stopped, as a tar archive in
the file `dest` on this machine (`podman cp … -`), written as podman
produces it and never held in memory: a volume's files handed over whole,
however large. `{:error, :not_found}` for a container or a path that is
not there.

# `create`

```elixir
@spec create(spec()) :: {:ok, String.t()} | {:error, term()}
```

Create a container from `spec`, not started. Answers its id.

# `create_network`

```elixir
@spec create_network(String.t(), keyword()) :: :ok | {:error, term()}
```

Create a network; one that exists already is fine, as it is.

`opts`: `internal: true` for a network with no way out, which only its
containers reach each other on (a server and its database); `labels:`.
Containers on a network a host made reach each other by name.

# `create_volume`

```elixir
@spec create_volume(String.t(), %{required(String.t()) =&gt; String.t()}, keyword()) ::
  :ok | {:error, term()}
```

Create a named volume; one that exists already is fine, as it is.

`opts`: `owner: {uid, gid}` gives a new volume's root to that user, for a
container that runs as `user: "uid:gid"`. One that exists keeps its owner;
a `:chown` mount re-owns it.

# `exec`

```elixir
@spec exec(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, term()}
```

Run `argv` inside a running container and answer what it printed, stdout
and stderr together. A non-zero exit is `{:podman_failed, :exec, status, line}`.

# `executable`

```elixir
@spec executable() :: {:ok, String.t()} | {:error, :podman_not_found}
```

The `podman` executable, for a host that runs it itself: a job whose output
it streams through a port as it comes.

# `image_exists?`

```elixir
@spec image_exists?(String.t()) :: boolean()
```

Whether the image store has `image`.

# `info`

```elixir
@spec info() ::
  {:ok, %{memory_mb: non_neg_integer(), cpus: pos_integer()}} | {:error, term()}
```

This machine's memory and CPUs, as podman sees them.

# `inspect_image`

```elixir
@spec inspect_image(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
```

One field of an image, through a Go template: `"{{.Digest}}"`, or
`"{{range .Config.Env}}{{println .}}{{end}}"`.

# `kill`

```elixir
@spec kill(String.t()) :: :ok | {:error, term()}
```

Kill a container at once (SIGKILL). One started with `--rm` is removed with
it, which is how a host stops a job past its time.

# `list`

```elixir
@spec list(String.t()) :: {:ok, %{required(String.t()) =&gt; state()}} | {:error, term()}
```

Every container carrying `label` (`key=value`), any state, by name: one
call for a whole machine, where `state/1` per container would be one each.

# `logs`

```elixir
@spec logs(String.t(), pos_integer()) :: {:ok, String.t()} | {:error, term()}
```

A container's last `tail` lines of output, stdout and stderr together.

# `output`

```elixir
@spec output(String.t(), [String.t()], keyword()) ::
  {:ok, String.t()} | {:error, term()}
```

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

# `pause`

```elixir
@spec pause(String.t()) :: :ok | {:error, term()}
```

Freeze a running container (the cgroup freezer): it keeps its memory and
uses no CPU. `unpause/1` thaws it in milliseconds.

# `pull`

```elixir
@spec pull(String.t()) :: :ok | {:error, term()}
```

Pull `image` into the image store.

# `remove`

```elixir
@spec remove(String.t()) :: :ok | {:error, term()}
```

Remove a container, running or not. Its named volumes stay.

# `remove_network`

```elixir
@spec remove_network(String.t()) :: :ok | {:error, term()}
```

Remove a network no container is on. One that is not there is fine; one
a container is still on is a `:podman_failed` error.

# `remove_volume`

```elixir
@spec remove_volume(String.t()) :: :ok | {:error, term()}
```

Remove a named volume and everything in it.

# `start`

```elixir
@spec start(String.t()) :: :ok | {:error, term()}
```

Start a created or stopped container.

# `state`

```elixir
@spec state(String.t()) :: {:ok, state()} | {:error, term()}
```

What a container is doing, or `{:error, :not_found}`.

# `stats`

```elixir
@spec stats() ::
  {:ok,
   %{
     required(String.t()) =&gt; %{
       memory_bytes: non_neg_integer(),
       cpu_percent: float()
     }
   }}
  | {:error, term()}
```

Memory in use and CPU of every running container, by name, in one call:
`%{"name" => %{memory_bytes: n, cpu_percent: f}}`.

# `stop`

```elixir
@spec stop(String.t(), non_neg_integer()) :: :ok | {:error, term()}
```

Stop a container, killing it after `timeout_s` seconds.

# `tag`

```elixir
@spec tag(String.t(), String.t()) :: :ok | {:error, term()}
```

Give the image `image` names a second name, `ref`.

# `tags`

```elixir
@spec tags(String.t()) :: [String.t()]
```

Every `repo:tag` name of `repo` in the image store.

# `unpause`

```elixir
@spec unpause(String.t()) :: :ok | {:error, term()}
```

Thaw a paused container.

# `untag`

```elixir
@spec untag(String.t()) :: :ok | {:error, term()}
```

Drop the name `ref`. An image goes with its last name, unless a container
holds it.

# `update`

```elixir
@spec update(String.t(), keyword()) :: :ok | {:error, term()}
```

Change a container's limits while it runs: `cpus:`, `memory_mb:` and
`pids:`, all three required.

A host gives a booting container more CPU than its size and takes it back
once it answers, since a boot is the one time a small server is CPU-bound.

All three because podman 5 writes the whole resource set on an update: a
call with only `--cpus` left the container with no memory and no pids
limit (`memory.max` read `max` afterwards, podman 5.3.1).

# `write_env_file`

```elixir
@spec write_env_file(Path.t(), %{required(String.t()) =&gt; String.t()}) ::
  :ok | {:error, term()}
```

Write `env` to `path` as a podman `--env-file`, readable by its owner only.

The file is created empty at 0600 before the values go in, so they are
never readable by another user, even for the moment between the two. A key
or value holding a newline, a carriage return or a NUL is refused with
`{:unsafe_env, key}`: the file is read a line at a time, so a newline in a
value is a second `KEY=value` line the caller never set. The caller removes
the file once podman has read it.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
