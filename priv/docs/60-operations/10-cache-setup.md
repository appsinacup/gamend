---
icon: hero-archive-box
---

# Cache Setup

## Defaults

By default, production runs a single-level local cache (fastest for a single instance).

```bash
GAMEND_CACHE_ENABLED=true
GAMEND_CACHE_MODE=single
GAMEND_CACHE_L2=partitioned
GAMEND_CACHE_REDIS_POOL_SIZE=10
```

Tip: `GAMEND_CACHE_L2` only matters when `GAMEND_CACHE_MODE=multi`.

## Single Instance (recommended default)

Use a single local cache level:

```bash
GAMEND_CACHE_MODE=single
# optional: GAMEND_CACHE_ENABLED=false (bypass caching)
```

## Multiple Instances (near-cache)

Enable a two-level cache: L1 local + L2 shared/sharded.

```bash
GAMEND_CACHE_MODE=multi
# Choose one L2:
GAMEND_CACHE_L2=redis
GAMEND_CACHE_REDIS_URL="redis://:password@host:6379/0"
# OR
GAMEND_CACHE_L2=partitioned
```

Redis is shared across nodes. Partitioned requires Erlang clustering between nodes.

## Partitioned Cache Setup (Erlang cluster for partitioned L2)

If you use `GAMEND_CACHE_L2=partitioned`, nodes must be able to connect to each other via Erlang distribution.

```bash
RELEASE_DISTRIBUTION=name
RELEASE_NODE="myapp@fully-qualified-ip"
RELEASE_COOKIE="a_shared_secret_cookie"
GAMEND_CLUSTER_DNS_QUERY="a DNS name that resolves to all peer nodes"
```

**Notes:** All nodes must share the same `RELEASE_COOKIE`, and each node must have a unique `RELEASE_NODE`. If you use `GAMEND_CACHE_L2=redis`, you typically do not need Erlang clustering.
