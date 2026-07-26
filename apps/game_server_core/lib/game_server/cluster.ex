defmodule GameServer.Cluster do
  @moduledoc """
  Erlang distribution, needed for multi-node deployments and the partitioned
  L2 cache.

  Only `dns_query` and `redis_url` are settings — values this server reads.
  The rest of a clustered deployment is configured through variables *other
  software* reads before any of our code runs: `RELEASE_DISTRIBUTION`,
  `RELEASE_NODE` and `RELEASE_COOKIE` are consumed by the release boot script,
  `ERL_AFLAGS` by `erl` itself, and the `FLY_*` values are injected by the
  platform.

  Declaring those as settings would be a lie: renaming them onto our convention
  would not rename what the BEAM and the platform read, it would leave the
  settings permanently empty. `environment/0` reports them for the admin page
  as observations rather than settings.
  """

  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :cluster,
    label: "Clustering"

  setting(:dns_query, :string,
    doc: "DNS name whose A/AAAA records list the other nodes, polled at boot."
  )

  setting(:redis_url, :string,
    doc: "Shared fallback URL used by the cache and rate limiter when neither sets its own."
  )

  @external ~w(RELEASE_DISTRIBUTION RELEASE_NODE RELEASE_COOKIE ERL_AFLAGS
               FLY_APP_NAME FLY_PRIVATE_IP FLY_REGION)

  @secret ~w(RELEASE_COOKIE)

  @doc """
  The clustering variables other software reads, with their current values,
  for display only.

  These are not settings and cannot be renamed onto our convention — the BEAM
  and the platform read these exact names.
  """
  @spec environment() :: [%{name: String.t(), value: String.t() | nil, secret: boolean()}]
  def environment do
    for name <- @external do
      %{name: name, value: System.get_env(name), secret: name in @secret}
    end
  end
end
