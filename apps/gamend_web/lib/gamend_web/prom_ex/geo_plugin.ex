defmodule GamendWeb.PromEx.GeoPlugin do
  @moduledoc """
  Custom PromEx plugin that exports geo-traffic Prometheus metrics.

  Tracks:

  - `gamend_geo_requests_total` — counter, tagged by `country`
    (ISO 3166-1 alpha-2 code, or "XX" for unknown) and `class` (the client
    kind, `GamendWeb.Crawlers.kinds/0`: `human`, `search`, …).
  - `gamend_crawler_requests_total` — crawler requests, tagged by `class`
    and `bot` (a closed set of names, `GamendWeb.Crawlers`).
  - `gamend_crawler_rate_limited_total` — 429s by `class` and `bot`
    (`"none"` for a person).

  The events are emitted by `GamendWeb.Plugs.GeoCountry` (every HTTP request
  that reaches the router; static files are served before it) and, for the
  429s, `GamendWeb.Plugs.RateLimiter`. Prometheus keeps them across
  restarts; the admin Geo page's ETS counters do not.
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :gamend_geo_request_metrics,
        [
          counter(
            [:gamend, :geo, :requests, :total],
            event_name: [:gamend, :geo, :request],
            measurement: :count,
            description: "Total HTTP requests by country code and client kind.",
            tags: [:country, :class]
          ),
          counter(
            [:gamend, :crawler, :requests, :total],
            event_name: [:gamend, :crawler, :request],
            measurement: :count,
            description: "Crawler requests by kind and crawler name.",
            tags: [:class, :bot]
          ),
          counter(
            [:gamend, :crawler, :rate_limited, :total],
            event_name: [:gamend, :crawler, :rate_limited],
            measurement: :count,
            description: "HTTP 429s by client kind and crawler name.",
            tags: [:class, :bot]
          )
        ]
      )
    ]
  end
end
