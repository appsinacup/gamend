defmodule Gamend.TestSupport.Runtime do
  @moduledoc """
  Starts what the core contexts need under test, without an application
  callback: `gamend_core` has none, because the host owns the supervision tree.

  `gamend_web`'s suite starts the same tree with its own processes added, so
  both suites boot the core the same way. `start_suite/1` is the whole of a
  `test_helper.exs`.
  """

  alias Ecto.Adapters.SQL.Sandbox
  alias Gamend.Chat.Moderation.Cache, as: ModerationCache
  alias Gamend.OAuth.Providers, as: OAuthProviders
  alias Gamend.SettingsHelpers

  @supervisor __MODULE__.Supervisor

  @doc """
  Configures ExUnit, starts the runtime and puts the repo in manual sandbox
  mode.

  ## Options

    * `:setup` — a zero-arity function run before any process starts, for
      ETS tables and code paths the extra children expect.
    * `:services` — children started after the core services and before the
      plugin manager, which may call into them from a hook.
    * `:endpoints` — children started last.
  """
  @spec start_suite(keyword()) :: :ok
  def start_suite(opts \\ []) do
    repo_config = Application.get_env(:gamend_core, Gamend.Repo, [])

    if repo_config[:adapter] == Ecto.Adapters.SQLite3 do
      ExUnit.configure(max_cases: 1)
    else
      # Tests pinning SQLite-only repo options (e.g. IMMEDIATE transactions) are
      # meaningless against Postgres.
      ExUnit.configure(exclude: [:sqlite_only])
    end

    ensure_started(opts)

    # capture_log: many tests deliberately exercise failure paths (OAuth CSRF
    # rejection, payment decline, SMTP failure, plugin hook raising, log rotation
    # probes). Their logs are captured per test and only printed when that test
    # fails, so a green run stays readable without losing diagnostics.
    ExUnit.start(capture_log: true)
    Sandbox.mode(Gamend.Repo, :manual)

    # Some auth flows need Apple's audiences configured. Set once here and kept
    # stable across async tests to avoid cross-test races.
    for {key, value} <- [
          apple_client_id: "com.example.web",
          apple_ios_client_id: "com.example.ios"
        ] do
      SettingsHelpers.put(
        :gamend_core,
        OAuthProviders,
        key,
        SettingsHelpers.get(:gamend_core, OAuthProviders, key) || value
      )
    end

    :ok
  end

  @doc "Starts the runtime once; see `start_suite/1` for the options."
  @spec ensure_started(keyword()) :: :ok
  def ensure_started(opts \\ []) do
    # Idempotent: creates the Schedule registry + protected-callback tables if
    # they don't exist yet.
    Gamend.Schedule.start_link()
    # Tables only. Moderation.Sync is deliberately absent: its boot load would
    # run outside the sandbox. Tests that need remote-event application drive
    # Cache.apply_remote/2 directly.
    ModerationCache.init_table()

    if setup = opts[:setup], do: setup.()

    children =
      core_services() ++
        Keyword.get(opts, :services, []) ++
        [Gamend.Hooks.PluginManager, {Oban, Gamend.Jobs.oban_config()}] ++
        Keyword.get(opts, :endpoints, [])

    case Supervisor.start_link(children, strategy: :one_for_one, name: @supervisor) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp core_services do
    [
      Gamend.Repo,
      Gamend.Lock.Queue,
      {Gamend.Cache, []},
      Gamend.Cache.Stats,
      {Task.Supervisor, name: Gamend.TaskSupervisor, max_children: 200},
      {Phoenix.PubSub, name: Gamend.PubSub},
      Gamend.Presence,
      Gamend.Cache.Sync,
      Gamend.Accounts.PresenceWriter
    ]
  end
end
