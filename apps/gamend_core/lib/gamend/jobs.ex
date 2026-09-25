defmodule Gamend.Jobs do
  @moduledoc """
  Durable background jobs, backed by Oban.

  Use this from your hooks to run work that must survive a restart, retry on
  failure, or happen later — things `Gamend.Async` (best-effort, in-memory)
  cannot guarantee.

  Jobs are persisted in the same database as the rest of your data (Postgres or
  SQLite), executed with retries and backoff, and observable from the admin
  panel.

  ## Enqueue a hook to run in the background

      # Run `on_welcome_email` now, retried on failure
      Gamend.Jobs.enqueue_hook(:on_welcome_email, %{"user_id" => user.id})

      # Run it in 24 hours (delayed job)
      Gamend.Jobs.enqueue_in(24 * 60 * 60, :on_trial_reminder, %{"user_id" => user.id})

  The callback receives the args map you passed. **Args are stored as JSON**, so
  keys come back as strings and values must be JSON-encodable:

      def on_welcome_email(%{"user_id" => user_id}) do
        # ...
        :ok
      end

  Returning `{:error, reason}` from the callback makes the job retry with
  backoff; `:ok`/`{:ok, _}` completes it.

  ## Recurring work

  For cron-like recurring jobs use `Gamend.Schedule` (also durable, built on
  top of this module).

  ## RPC safety

  Any hook enqueued through `enqueue_hook/3` is automatically protected from
  client RPC — a client cannot invoke a job callback directly.
  """

  alias Gamend.Jobs.HookWorker
  alias Gamend.Jobs.ProtectedCallbacks

  @type args :: map()

  # Read by `oban_config/0` when Oban starts, so a change needs a restart.
  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :jobs,
    label: "Background jobs"

  setting(:queue_default, :integer,
    default: 10,
    doc: "Per-node concurrent jobs on the default queue."
  )

  setting(:queue_hooks, :integer,
    default: 20,
    doc: "Per-node concurrent jobs on the hooks queue: enqueued and scheduled plugin hooks."
  )

  setting(:queue_mailers, :integer,
    default: 5,
    doc: "Per-node concurrent email sends."
  )

  setting(:queue_storage, :integer,
    default: 5,
    doc: "Per-node concurrent storage jobs, such as avatar mirroring."
  )

  setting(:queue_webhooks, :integer,
    default: 10,
    doc: "Per-node concurrent outgoing webhook deliveries."
  )

  setting(:prune_after_days, :integer,
    default: 7,
    doc: "Days finished, cancelled and discarded jobs are kept before they are deleted."
  )

  @doc false
  # Internal: enqueue any Oban.Worker module. Plugins use enqueue_hook/enqueue_in.
  @spec enqueue(module(), args(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(worker, args \\ %{}, opts \\ []) when is_atom(worker) and is_map(args) do
    args
    |> worker.new(opts)
    |> Oban.insert()
  end

  @doc """
  Enqueue a hook function to run in the background.

  Returns `{:ok, job_id}` — pass `job_id` to `cancel/1` to cancel it while it is
  still pending. See the module doc for the callback contract.
  """
  @spec enqueue_hook(atom(), args(), keyword()) :: {:ok, integer()} | {:error, term()}
  def enqueue_hook(hook_fn, args \\ %{}, opts \\ []) when is_atom(hook_fn) and is_map(args) do
    ProtectedCallbacks.register(hook_fn)

    case enqueue(HookWorker, hook_job_args(hook_fn, args), opts) do
      {:ok, %Oban.Job{id: id}} -> {:ok, id}
      {:error, _} = err -> err
    end
  end

  @doc """
  Enqueue a hook function to run after `seconds`.

  Returns `{:ok, job_id}`; cancel it with `cancel/1` before it runs.
  """
  @spec enqueue_in(non_neg_integer(), atom(), args(), keyword()) ::
          {:ok, integer()} | {:error, term()}
  def enqueue_in(seconds, hook_fn, args \\ %{}, opts \\ [])
      when is_integer(seconds) and seconds >= 0 do
    enqueue_hook(hook_fn, args, Keyword.put(opts, :schedule_in, seconds))
  end

  @doc """
  Cancel a pending job by its id (from `enqueue_hook/3` or `enqueue_in/4`).
  """
  @spec cancel(integer()) :: :ok
  def cancel(job_id) when is_integer(job_id) do
    _ = Oban.cancel_job(job_id)
    :ok
  end

  @doc false
  # The JSON envelope `HookWorker` unwraps. Kept here so `Schedule` builds the
  # same shape without duplicating the contract.
  @spec hook_job_args(atom(), args()) :: map()
  def hook_job_args(hook_fn, args) when is_atom(hook_fn) and is_map(args) do
    %{"hook" => Atom.to_string(hook_fn), "args" => args}
  end

  @doc false
  # Oban start options with the engine derived from the Repo's *actual* adapter.
  # The compile-time `default_adapter` keys off `DATABASE_ADAPTER`, but dev/test
  # switch the Repo to Postgres off `POSTGRES_HOST` — so deriving the engine from
  # the running adapter is the only value that's always correct.
  @spec oban_config() :: keyword()
  def oban_config do
    # Read the adapter from config (not Repo.__adapter__/0, a compile-time
    # constant the type checker narrows) so the same source drives both the Repo
    # and the Oban engine.
    adapter = Application.get_env(:gamend_core, Gamend.Repo)[:adapter]

    postgres? = adapter == Ecto.Adapters.Postgres
    engine = if postgres?, do: Oban.Engines.Basic, else: Oban.Engines.Lite

    :gamend_core
    |> Application.fetch_env!(Oban)
    |> Keyword.put(:engine, engine)
    |> apply_settings()
    |> then(&if postgres?, do: &1, else: throttle_for_sqlite(&1))
  end

  # The declared queue sizes and pruning window win over the compiled Oban
  # config. A queue a host added to that config keeps its own size.
  defp apply_settings(opts) do
    opts
    |> Keyword.update(:queues, declared_queues(), fn
      queues when is_list(queues) -> Keyword.merge(queues, declared_queues())
      other -> other
    end)
    |> Keyword.update(:plugins, [], fn
      plugins when is_list(plugins) -> Enum.map(plugins, &put_prune_age/1)
      other -> other
    end)
  end

  defp declared_queues do
    [
      default: queue_setting(__MODULE__, :queue_default),
      hooks: queue_setting(__MODULE__, :queue_hooks),
      mailers: queue_setting(__MODULE__, :queue_mailers),
      storage: queue_setting(__MODULE__, :queue_storage),
      webhooks: queue_setting(__MODULE__, :queue_webhooks),
      push: queue_setting(Gamend.Push, :queue_concurrency)
    ]
  end

  defp queue_setting(module, key), do: max(Gamend.Settings.get(module, key), 1)

  defp put_prune_age(Oban.Plugins.Pruner), do: put_prune_age({Oban.Plugins.Pruner, []})

  defp put_prune_age({Oban.Plugins.Pruner, plugin_opts}) do
    days = max(Gamend.Settings.get(__MODULE__, :prune_after_days), 1)
    {Oban.Plugins.Pruner, Keyword.put(plugin_opts, :max_age, days * 86_400)}
  end

  defp put_prune_age(plugin), do: plugin

  # Queue concurrency is sized for Postgres, which runs writers in parallel.
  # SQLite takes a single database-wide write lock, so that same configuration
  # only converts parallelism into lock contention: dozens of concurrent jobs
  # plus the Stager's own per-second transaction can hold the write lock past
  # `busy_timeout`, and the loser dies with "database is locked" (Oban.Stager
  # crashing is the usual symptom). Scale the queues down and stage less often
  # — SQLite hosts get the same throughput, just without the pile-up.
  @sqlite_max_queue_concurrency 2
  @sqlite_stage_interval :timer.seconds(5)

  defp throttle_for_sqlite(opts) do
    opts
    |> Keyword.update(:queues, [], fn
      queues when is_list(queues) ->
        Enum.map(queues, fn
          {name, limit} when is_integer(limit) ->
            {name, min(limit, @sqlite_max_queue_concurrency)}

          other ->
            other
        end)

      other ->
        other
    end)
    |> Keyword.put_new(:stage_interval, @sqlite_stage_interval)
  end
end
