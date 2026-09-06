---
icon: hero-bolt
---

# Load Testing

Measure what your deployment can actually take, with the k6 harness in
[`stress/`](https://github.com/appsinacup/gamend/tree/main/stress).

Two different questions, answered by two different tools:

- **What does an operation cost?** `stress/scenarios/` — one isolated scenario
  per feature (login, lobby create, chat, matchmaking, quests, hook RPCs …),
  run one at a time by `suite.sh`.
- **Where does it stop scaling?** `stress/sweep.sh` — one scenario up a ladder
  of concurrency levels, so you can see the knee.

## Before you run anything

Three settings, and skipping any of them makes the numbers meaningless.

**1. Run the server in `MIX_ENV=prod`.** Dev mode checks for changed files on
every request, so a dev benchmark measures the code reloader. Same scenario,
same machine: 293 req/s in dev, 18,918 req/s in prod.

```bash
mix assets.deploy
MIX_ENV=prod GAMEND_AUTH_SECRET_KEY_BASE=$(mix phx.gen.secret) \
  GAMEND_DB_SQLITE_PATH=/tmp/bench.db \
  GAMEND_RATELIMIT_ENABLED=false \
  GAMEND_AUTH_DEVICE_AUTH_ENABLED=true \
  GAMEND_FEATURES_LIST_LOBBIES_ENABLED=true \
  GAMEND_FEATURES_LIST_GROUPS_ENABLED=true \
  mix phx.server
```

**2. Turn rate limiting off.** Limits are per IP: 10 auth and 240 general
requests a minute. Every virtual user shares one IP, so a run with limits on
measures the limiter. Confirm with the `rate_limit deny` counter on `/metrics`:
it must stay at zero.

**3. Load only the stress plugin.** The example plugin writes a leaderboard
score on *every login*; left loaded it charges your server for a sample
plugin's writes.

```bash
cd modules/plugins_examples/stress_hook && mix deps.get && mix compile && mix plugin.bundle && cd -
mkdir -p stress/.plugins && cp -R modules/plugins_examples/stress_hook stress/.plugins/
# then add to the server command above:
#   GAMEND_CONTENT_PLUGINS_DIR=stress/.plugins
```

Never point a load test at a production server you care about: the harness
creates users, lobbies and groups, and is designed to push a machine past the
point where it answers correctly.

## Run it

```bash
cd stress
BASE_URL=http://localhost:4000 VUS=30 DURATION=15s ./suite.sh
```

One scenario while you iterate:

```bash
BASE_URL=http://localhost:4000 k6 run --vus 2 --iterations 4 scenarios/chat.js
```

Find where a path stops scaling:

```bash
BASE_URL=http://localhost:4000 ./sweep.sh auth_device 5 15 30 60 120 240
```

Rising req/s with flat p95 means headroom. Flat req/s with rising p95 means
saturation, meaning work is queueing rather than going faster. Falling req/s means contention.

A laptop number is only good for comparing the same laptop before and after a
change: k6 and the server share your cores. For a figure you intend to quote,
run the server on its own machine with the generator in the same region, which
is what the matrix below does. [Performance](performance) has those numbers.

## Running the matrix on Fly

`stress/fly/matrix.sh` walks a list of (database, machine size) cells: for each
one it resizes the bench app, waits for health, runs the suite from a k6 machine
in the same region, and pulls the summaries back.

It is a separate app from production by construction, because it runs with
rate limiting off and gets its state wiped between cells. Two guards enforce
that rather than trusting it: the script refuses to start if any target app is
listed in `PROTECTED_APPS`, and it refuses if `BENCH_APP` disagrees with the app
name in `fly.bench.toml` (which would deploy to one app and resize another).

```bash
PROTECTED_APPS="game-server-uro my-other-app" ./matrix.sh
DRY_RUN=1 ./matrix.sh                    # see what it would do
```

### Setup

```bash
fly auth login
./matrix.sh --setup
```

Idempotent: every step checks for what it creates and skips it, so it is safe
to re-run after it fails halfway. It creates two apps and two machines:
`gamend-bench` (the target, resized per cell) and `gamend-k6` (the generator, no
inbound port, driven over SSH, same region on purpose, since a generator elsewhere
adds internet latency to every measurement). Plus a 10 GB volume and
`GAMEND_AUTH_SECRET_KEY_BASE`, which is `required: :prod` with no gate, so a
bench app missing it never becomes healthy.

The matrix does not start eight machines. It resizes the same one with
`fly scale vm`, one cell at a time, which is why cells run in sequence:

```bash
./matrix.sh A          # one cell, one size, then stop and look
```

Postgres is the one manual step, deliberately: `fly postgres create` prints the
password exactly once, and a script that swallows it leaves you with a database
you cannot connect to.

```bash
fly postgres create --name gamend-bench-pg --region ams --vm-size performance-2x
PG_URL='ecto://postgres:<password>@gamend-bench-pg.flycast:5432/gamend' ./matrix.sh --setup
```

Without it, the SQLite cells run and the Postgres ones do not.

### Choosing cells and a profile

`PROFILE` decides what runs per cell, and it is the difference between an hour
and a day:

| profile | what runs | per cell at `SUITE_DURATION=30s` |
|---|---|---|
| `core` (default) | 6 scenarios, one operation each | ~3.5 min |
| `suite` | all 21 isolated scenarios | ~12 min |
| `full` | suite plus the four journeys | ~32 min |

`core` is the right profile for sweeping hardware, because its six scenarios are
the distinct cost classes and everything else is a combination of them: `me`
(cached read), `hook_noop` (plugin call, no database), `kv_write`,
`kv_write_locked`, `auth_device` (registration) and `auth_email` (bcrypt, the
one purely-CPU path). Subtracting one from the next attributes cost. The flows
tell you nothing new about a machine size, so run them on the size you intend to
ship.

Any size can be walked without editing the script, and cells are validated
against Fly's catalogue up front, so a typo is refused before anything is
created:

```bash
CELLS="I|sqlite|shared-cpu-2x|2048 J|postgres|performance-2x|4096" ./matrix.sh
```

**Use `performance-*` for any number you intend to quote.** A `shared-cpu-Nx` is
not N cores: each shared CPU gets 5ms per 80ms, or 6.25% of a core, and
bursts above it on a credit balance capping at 500 seconds. So a short run
measures the burst, a long run measures the throttle, and which you get depends
on how idle the machine has been. `matrix.sh` warns when a cell uses one. Memory
ceilings follow the CPU type: 2 GB per shared CPU, 8 GB per performance CPU.

Cell `N` is `performance-1x` at 3 GB, one dedicated core, matching the
shape Nakama publishes on, which is why it is not a shared size.

### Watching for OOM

```bash
./matrix.sh --status    # safe from a second terminal mid-cell
```

It reports machine state and size, Fly's health checks, restart and OOM counts,
and the BEAM's own memory breakdown plus RSS. **The restart count is the one to
watch**: Fly restarts a machine the kernel OOM-killed, so a machine that started
more than once when nobody restarted it is the signature, and the run before it
produced perfectly ordinary-looking numbers right up to the point it died.

BEAM memory comes from inside the app rather than the platform, because
`fly machine status` reports the machine's *limit*, and the gap between that and
what the BEAM is holding is the entire question. RSS is in there because RSS is
what the OOM killer reads.

The matrix fires on both cases by itself: a cell that never becomes healthy
prints the full status plus the last 40 log lines, and a cell that OOM-killed
mid-run is flagged `*** OOM: n mentions, treat this cell's numbers as invalid
***`. Worth having, because such a cell still writes a results file whose
numbers look like a machine that got slower rather than one that died.

### What it costs, and stopping the bill

Fly bills per second, so the cost is the wall-clock of the run rather than
the monthly price of the sizes it walks: a five-minute cell is the monthly
price divided by roughly 8,760. **A full eight-cell run at `PROFILE=core` is
well under a dollar.** Only the adapter decides the image, so walking four
SQLite sizes is one deploy and four resizes; the script skips the deploy when
the image has not changed.

Approximate Amsterdam list prices, per month at each size's base memory:

| size | cores | base RAM | per month |
|---|---:|---:|---:|
| `shared-cpu-1x` | 6.25% | 1 GB | ~$6 |
| `shared-cpu-4x` | 25% | 1 GB | ~$8 |
| `performance-1x` | 1 | 2 GB | ~$32 |
| `performance-2x` | 2 | 4 GB | ~$64 |
| `performance-4x` | 4 | 8 GB | ~$129 |
| `performance-8x` | 8 | 16 GB | ~$258 |
| `performance-16x` | 16 | 32 GB | ~$515 |

Extra RAM beyond a size's base is about $5/GB/month; volumes are
$0.15/GB/month, so the 10 GB bench volume is ~$1.50/month and persists
whether or not anything is running.

The expensive mistake is not the run, it is forgetting to stop. Neither machine
auto-stops. The bench app turns it off deliberately, since a machine that stops
between runs measures its own cold start, and **the bench machine keeps
whatever size the last cell set**, so finishing on the largest cell and walking
away rents a `performance-16x` to do nothing.

```bash
./matrix.sh --stop      # stop both machines; apps, volume and secrets survive
./matrix.sh --destroy   # prints the commands to remove everything
```

`--stop` leaves the setup intact, so the next session starts at `./matrix.sh A`
rather than another setup. A stopped machine costs only its rootfs storage; the
volume bills either way.

## Get the results

```bash
node report.mjs results/ --md results/report.md --page results/report.html
```

- **`report.md`** — every table plus unicode bar charts; renders anywhere a
  Markdown file renders, no image assets.
- **`report.html`** — a self-contained page: totals, throughput and latency
  charts, per-scenario and per-operation tables. No network required.

Add saturation curves, or compare two runs, the loop for checking whether a
change helped:

```bash
node report.mjs results/ --page results/report.html \
  --sweep SQLite=results/sweep --sweep Postgres=results/sweep_pg

RESULTS_DIR=results/before ./suite.sh
# …make the change, restart the server…
RESULTS_DIR=results/after ./suite.sh
node report.mjs --diff results/before results/after
```

## Reading a run

```
| scenario     | VUs | rps  | med  | p95  | p99  | errors | checks |
| me           |  30 | 18607|  1.3 |  3.0 |  4.4 |  0.00% | 100.00%|
```

The column that decides whether a run counts is checks, not latency. Every
write scenario reads its own write back, so a cache serving stale data shows up
as a check failure while the timings still look excellent. A run with failed
checks is not a slower run, it is a wrong one.

Then look at your server for the same window: `/metrics` carries CPU, memory,
BEAM run queue, Ecto queue time and cache hit ratio. A good p95 sitting on a
page of database errors is a failed run the client cannot see.

Read flows/s rather than req/s when comparing scenarios: a flow that spends
five requests is not slower than one that spends one. Two numbers are the
scenario rather than the server: `matchmaking` waits on the sweep tick, and
`ws_join_idle` holds a socket and makes almost no requests. Neither is a
throughput measurement.

## Writing your own scenario

The scenarios are short because everything shared lives in `stress/lib/`:
`auth.js` (device and email login), `api.js` (one wrapper per endpoint),
`phx.js` (a Phoenix channel client, so you can time realtime event delivery),
`hooks.js` (plugin RPCs) and `checks.js` (read-your-write assertions). Copy the
closest scenario and change the middle.

Your own game's operations belong in your own plugin: the harness reaches quest
progress, score submission and wallet credits through
`modules/plugins_examples/stress_hook`, because those are server-side operations
with no player-facing endpoint by design.
