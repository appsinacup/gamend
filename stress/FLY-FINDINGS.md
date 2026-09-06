# Fly benchmark — findings, and where to pick up

Run on 2026-08-19 against `gamend-bench` / `gamend-k6` in `ams`, both since
destroyed. Raw data is in `results/` (`hardware.tsv`, the `[A-Z]*-*.json`
summaries, and the socket CSVs). Everything here is measured; nothing is
extrapolated unless it says so.

## What is finished and trustworthy

The per-operation table across seven machine sizes — 42 runs, **100% of
read-your-write checks passed, zero errors, zero OOM, no crash restarts**. The
hardware for every cell was read back off the machine before load was applied
and logged to `results/hardware.tsv`. It is in the [Performance
guide](../priv/docs/60-operations/70-performance.md).

Three things that table says:

- **bcrypt is the only row that scales cleanly with cores** — 0.3, 1.2, 2.1,
  4.0, 7.9, 15.6 against 0.06, 0.25, 0.5, 1, 2, 4 cores. ~3.9 email logins per
  second per core, in a straight line, because it is the one purely CPU-bound
  path. Size on this if your players use passwords.
- **`shared-cpu-8x` at $16 beats `performance-4x` at $129 on cached reads**
  (8,087 vs 6,275) and loses 7x on bcrypt (2.1 vs 15.6). Shared CPUs get 6.25%
  of a core each and burst on credit; that is excellent for short bursty reads
  and useless for sustained CPU. Their numbers depend on how idle the machine
  has been, so they are not a ceiling.
- **More RAM bought nothing.** `performance-1x` at 2 GB and 3 GB are within
  noise on every row. gamend is CPU-bound at this scale.

Against Nakama's published 1 CPU / 3 GB node, on the same shape of box:
registrations 589/s against their 528, RPC calls 1,982/s against their ~800.

## What is not finished: the idle-socket ceiling

The headline Nakama claims (20,277 idle sockets on 1 vCPU / 3 GB) is still
unanswered. What is known:

- **~10,000 sockets held on 1 core / 3 GB**, with the server showing no OOM, no
  errors and no restarts. That was the point at which the *generator* ran out of
  memory, not the server.
- **~57 KB of server memory per idle socket**, measured: 7,000 sockets took the
  BEAM from 29 MB to 383 MB of process memory plus 50 MB of binary memory.
- On that basis 3 GB should hold roughly 20,000 — but that is arithmetic, not a
  measurement, and it is not a number to publish.

Three obstacles, two of them now removed:

1. **One k6 machine holds ~10k VUs** (1-3 MB each). Fixed by scaling the
   generator app to several machines; that works.
2. **The ramp was registration-bound, not socket-bound.** Every socket signed up
   its own device account first, and at ~589 registrations/s on one core the
   generator could not open sockets faster than the server could create
   accounts. Four generators produced *fewer* sockets than one, because they
   were competing for the same write path. Fixed: `ws_idle.js` now takes
   `USERS`, spreading sockets over a small pool of shared accounts, and
   `fly.bench.toml` sets `GAMEND_LIMITS_MAX_SOCKETS_PER_USER=0` (the default of
   20 would otherwise reject the surplus, correctly and confusingly).
3. **Not yet proven.** The reworked `ws_idle.js` was deployed but the run never
   produced output before the session ended. It needs a foreground run to see
   the error before anything else is attempted.

## Harness bugs found, all fixed

These are worth reading because each one produced *plausible* numbers rather
than an obvious failure.

- **`fly scale vm ... --yes` does not exist.** That flag is `fly deploy`'s. It
  exited non-zero with `unknown flag`, and `run()` did not check exit codes, so
  seven cells all ran on the machine's deployed size. The resulting table looked
  like a scaling curve and was one machine's burst credits draining — the reads
  fell 6,262 → 6,150 → 486 → 472 → 227 in *run order* while bcrypt stayed flat
  at ~1.2/s on supposedly 1, 2 and 4 cores. Kept as
  `results/invalid-2026-08-19-unscaled/`. `run()` now checks exit codes, and the
  matrix reads the size back off the machine and refuses the cell on a mismatch.
- **`fly machine restart --select` needs a TTY.** Without one it selects
  nothing and exits 0, so the plugin directory was staged but never loaded and
  every plugin RPC answered `plugin_not_found` — while the non-plugin scenarios
  passed. Now restarts by machine id.
- **`fly ssh sftp get` cannot fetch a directory.** It reported nothing and
  copied nothing, so results stayed on the generator and cells looked empty.
  Now fetches file by file.
- **`fly deploy` resolves `-c` against the build directory, not the shell's
  cwd** — so `-c fly.k6.toml` with a positional path fails *after* the other app
  has been created. Absolute paths now.
- **`fly machine list --json` is pretty-printed**, so `grep '"id":"'` matched
  nothing and every id-driven loop silently did nothing.
- **zsh does not word-split unquoted variables**, so `for id in $IDS` passed all
  four machine ids as one string and only ever launched one generator.
- **An OOM detector matching the bare string `oom`** matched Fly request ids
  like `GM1LY1oOMsx` and reported a false positive.

## Next session

1. Foreground-run the reworked `ws_idle.js` to find out why it produced no
   output, then get a real socket ceiling on 1 core / 3 GB.
2. Repeat the socket run across the other sizes.
3. Render the time-series chart — `results/sockets-*.csv` already has
   elapsed / port count / process count / memory sampled every 2s, which is the
   right shape (time on X). `ladder.mjs` currently plots machine size on X,
   which answers a different question and should stay as a second chart.
4. Rebuild the bench image from the working tree. Every number here came from
   `ghcr.io/appsinacup/gamend:latest`, which predates this session's fixes —
   in particular the partial provider indexes, which take a registration from 13 index
   writes to 7 and should move the registration row.
5. Postgres cells (E-H). Needs the cluster, which is the one manual setup step.
6. Blog post.

## Cost

The whole thing came to well under a dollar: machines bill per second, cells
were ~5 minutes each, and the two apps plus the 10 GB volume were destroyed at
the end. The expensive mistake would have been leaving a `performance-4x`
running — which is why `matrix.sh` now prints what is still up and what it costs
on the way out.
