---
icon: hero-chart-bar-solid
---

# Performance

We compared **Gamend** and **Nakama** on various machine sizes. On the same 1-core / 3 GB shape, **Gamend** holds about 1.9x the idle connections, answers a plugin call about 2.6-3x faster, and registers a device about 1.3x faster.

| operation | `shared-1x` | `shared-4x` | `shared-8x` | `perf-1x` | `perf-1x` | Nakama | `perf-2x` |
|---|---:|---:|---:|---:|---:|---:|---:|
| cores | 0.06 | 0.25 | 0.5 | 1 | 1 | 1 | 2 |
| memory | 1 GB | 1 GB | 2 GB | 2 GB | 3 GB | 3 GB | 4 GB |
| idle sockets | 6,867 | 9,055 | 22,333 | 22,359 | **37,854** | 20,277 | 51,225 |
| cached read (`GET /me`) | 1,999 | 6,228 | 6,296 | 2,218 | 2,189 | — | 4,255 |
| plugin call, no database | 155 | 6,005 | 6,911 | 2,200 | **2,184** | 700–825 | 3,854 |
| write | 41 | 209 | 1,950 | 836 | 839 | — | 1,071 |
| write inside a lock | 32 | 73 | 152 | 584 | 575 | — | 653 |
| registration (device) | 42 | 92 | 167 | 539 | **680** | 528 | 843 |
| email login (Argon2id) | 1.0 | 5.8 | 10.9 | 23.7 | 24.0 | — | 46.5 |
| page loads | 10 | 47 | 97 | 244 | 249 | — | 425 |
| cost / month | $6 | $8 | $16 | $32 | $37 | — | $64 |

The Nakama column is their own
[published benchmarks](https://heroiclabs.com/docs/nakama/getting-started/benchmarks/),
for a single node at 1 vCPU / 3 GB with its database on a separate 8-vCPU
instance. It sits next to the perf-1x / 3 GB column because that is the same
configuration.

### It scales linearly

![Concurrent connections](images/sockets-by-memory.svg)

Per connection the cost is **68–75 KB**, and it barely moves across a 4x range
of memory and a 16x range of CPU.

## Measuring your own

The numbers above are reproducible in about ten minutes on your own hardware,
and your game's mix of reads and writes matters more than any table here. See
[Load Testing](load-testing) for the harness, and read its check column before
its latency column: a server that answers quickly with stale data is failing,
not performing.
