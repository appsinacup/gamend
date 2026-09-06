---
icon: hero-queue-list
---

# Background & Scheduled Jobs

Durable background work rides Oban, persisted in the same database as the rest of your data (Postgres or SQLite), retried with backoff on failure, and observable at [/admin/oban](/admin/oban). Plugins reach it through two small modules: `Gamend.Jobs` for one-off work and `Gamend.Schedule` for recurring cron work. Both run *your hook functions*, so a background job is just a hook that happens later.

## Durable jobs from hooks

`Gamend.Async` and `Task.start` are best-effort and in-memory: work started that way dies with the node. For anything that must survive a restart, retry on failure, or run later (a welcome email, a trial reminder, a cleanup), enqueue a hook as a job instead:

```elixir
# Run now, retried on failure
{:ok, job_id} = Gamend.Jobs.enqueue_hook(:on_welcome_email, %{"user_id" => user.id})

# Run in 24 hours
{:ok, job_id} = Gamend.Jobs.enqueue_in(24 * 60 * 60, :on_trial_reminder, %{"user_id" => user.id})

# Changed your mind while it is still pending
Gamend.Jobs.cancel(job_id)

# The callback, in your hooks module. Args are stored as JSON,
# so keys come back as strings.
def on_welcome_email(%{"user_id" => user_id}) do
  # ...
  :ok
end
```

The contract: `:ok` or `{:ok, _}` completes the job; `{:error, reason}` retries it with backoff, up to 5 attempts. A job whose hook function no longer exists is discarded rather than retried; retrying will not make the plugin implement it.

Enqueuing a callback also protects it: any hook that has ever been the target of `enqueue_hook/3` or a schedule is barred from client RPC, so a player cannot invoke your job callbacks through `/api/v1/hooks/call`.

## Recurring schedules

Register cron-like schedules from your `after_startup/0` hook. Registration is in-memory and re-runs on every boot, which is exactly what you want, since the schedule always matches the code that is running:

```elixir
def after_startup do
  Gamend.Schedule.every_minutes(5, :on_every_5m)
  Gamend.Schedule.hourly(:on_hourly)
  Gamend.Schedule.daily(:on_morning_report, hour: 9)
  Gamend.Schedule.weekly(:on_monday, day: :monday, hour: 10)
  Gamend.Schedule.cron(:sweep, "*/15 * * * *", :on_every_15m)
  :ok
end

# Callbacks run as background jobs, so the context is a string-keyed JSON map
def on_morning_report(context) do
  # %{"triggered_at" => "2026-07-22T09:00:00Z", "job_name" => "on_morning_report",
  #   "schedule" => "0 9 * * *"}
  :ok
end
```

`Gamend.Schedule.cancel(:sweep)` removes a schedule; `Gamend.Schedule.list()` returns what is registered.

Schedules are distributed-safe with no application-level locks: a single per-minute tick (Oban's leader-elected Cron plugin driving `Gamend.Schedule.TickWorker`) enqueues each due callback as a *unique* job with a 90-second uniqueness window, so a callback runs at most once per period across the whole cluster, and a crash mid-run is retried like any other job.

## Queues

Six queues, sized in `config :gamend_core, Oban`:

| Queue | Concurrency | What runs there |
|---|---|---|
| `hooks` | 20 | Everything from `enqueue_hook`/`enqueue_in` |
| `default` | 10 | Scheduled callbacks, ready-check expiry, the schedule tick |
| `push` | 10 | Push notification fan-out and per-device delivery |
| `webhooks` | 10 | Provisioned for hosts; no core worker enqueues to it today |
| `mailers` | 5 | Account email, e.g. inactivity warnings |
| `storage` | 5 | Object-storage work, e.g. avatar mirroring |

The engine is picked at runtime from the Repo's actual adapter: Postgres runs the Basic engine with the numbers above, SQLite runs the Lite engine with every queue capped at concurrency 2 and staging slowed to every 5 seconds. SQLite takes a single database-wide write lock, so Postgres-sized parallelism only converts into lock contention, so SQLite hosts get the same throughput without the pile-up.

## Operations

- [/admin/oban](/admin/oban) is the full Oban Web dashboard — queues, running and retryable jobs, errors — admin-gated like the rest of the console.
- Finished jobs are kept for 7 days (`Oban.Plugins.Pruner`, `max_age` one week), so a job that failed on Friday can still be inspected on Monday.
- Jobs live in your database: there is no extra broker to deploy, and a backup of the database is a backup of the queue.

## Reference

- **Elixir API:** [`Gamend.Jobs`](https://docs.gamend.org/Gamend.Jobs.html) and [`Gamend.Schedule`](https://docs.gamend.org/Gamend.Schedule.html) - the functions a plugin calls, with their signatures and docs.
- **Dashboard:** [/admin/oban](/admin/oban) - live queue state on your server.
- **Hooks:** [Server scripting](/docs/server-scripting) - where the callbacks these jobs invoke are defined.
