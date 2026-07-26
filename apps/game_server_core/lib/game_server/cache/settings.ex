defmodule GameServer.Cache.Settings do
  @moduledoc """
  Cache topology. The resolved levels are built from these in the host's
  runtime config; `GameServer.Cache` itself holds the assembled structure.
  """

  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :cache,
    label: "Cache"

  setting(:enabled, :boolean,
    default: true,
    doc: "Set false to bypass caching entirely."
  )

  setting(:mode, :atom,
    default: :single,
    doc: "single (L1 local only) or multi (L1 + a shared L2)."
  )

  setting(:l2, :atom,
    default: :partitioned,
    doc: "redis or partitioned. Only used when mode is multi; partitioned needs clustering."
  )

  setting(:redis_url, :string,
    required: :prod,
    when: [{[:cache, :mode], :multi}, {[:cache, :l2], :redis}],
    doc: "Redis URL for the shared L2."
  )

  setting(:redis_pool_size, :integer, default: 10)
end
