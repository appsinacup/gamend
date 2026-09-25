defmodule Gamend.Cache.Settings do
  @moduledoc """
  Cache topology. The resolved levels are built from these in the host's
  runtime config; `Gamend.Cache` itself holds the assembled structure.
  """

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :cache,
    label: "Cache"

  setting(:enabled, :boolean,
    default: true,
    doc: "Set false to bypass caching entirely."
  )

  setting(:mode, :atom,
    values: [:single, :multi],
    default: :single,
    doc: "single (L1 local only) or multi (L1 + a shared L2)."
  )

  setting(:l2, :atom,
    values: [:redis, :partitioned],
    default: :partitioned,
    doc: "redis or partitioned. Only used when mode is multi; partitioned needs clustering."
  )

  setting(:redis_url, :string,
    required: :prod,
    when: [{[:cache, :mode], :multi}, {[:cache, :l2], :redis}],
    doc: "Redis URL for the shared L2."
  )

  setting(:redis_pool_size, :integer, default: 10)

  # Both bound each node's local cache (L1, and a partitioned L2's local
  # primary). Whichever is reached first evicts the oldest generation.
  setting(:max_entries, :integer,
    default: 1_000_000,
    doc: "Most entries each node's local cache holds."
  )

  setting(:max_memory_mb, :integer,
    default: 500,
    doc:
      "Most memory each node's local cache may use, in MB. Lower it on a small machine: " <>
        "the default alone is most of a 512 MB instance."
  )

  setting(:ttl_ms, :integer,
    default: 60_000,
    doc:
      "How long a cached entity (user, lobby, party, group, KV entry...) is kept, in ms. " <>
        "On a cluster it bounds how stale a node can be when an invalidation is missed."
  )
end
