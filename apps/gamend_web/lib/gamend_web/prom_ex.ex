defmodule GamendWeb.PromEx do
  @moduledoc """
  Prometheus metrics exporter using PromEx.

  Auto-instruments Phoenix, Ecto, BEAM VM, and Application metrics.
  Exposes a `/metrics` endpoint for Prometheus scraping (or Grafana Agent).

  ## Plugins enabled

  | Plugin | What it tracks |
  |--------|----------------|
  | `PromEx.Plugins.Beam` | VM memory, schedulers, atoms, processes, ports, ETS |
  | `PromEx.Plugins.Phoenix` | HTTP request count, duration, status by route |
  | `PromEx.Plugins.Ecto` | Query count, duration, queue time per source |
  | `PromEx.Plugins.Application` | App info (version, git SHA), uptime |

  ## Configuration

  Set `METRICS_ENABLED=false` to disable (default: enabled).

  A host adds its own plugins (`use PromEx.Plugin`) with
  `config :gamend_web, :host_prom_ex_plugins, [MyHost.PromEx.SomePlugin]`;
  they are appended to the list above when PromEx starts.

  The `/metrics` endpoint is public by design (Prometheus scrapes it).
  In production, restrict access at the network/firewall level or via
  the `GAMEND_OBSERVABILITY_METRICS_TOKEN` setting (Bearer token check;
  accepts inline contents or a path to a secret file).
  """

  use PromEx, otp_app: :gamend_web

  @impl true
  def plugins do
    [
      # BEAM VM metrics (memory, schedulers, processes, etc.)
      PromEx.Plugins.Beam,

      # Phoenix HTTP request metrics (count, duration, status by route)
      {PromEx.Plugins.Phoenix, router: GamendWeb.Router, endpoint: GamendWeb.Endpoint},

      # Ecto database metrics (query count, duration, queue time)
      {PromEx.Plugins.Ecto, repos: [Gamend.Repo]},

      # Application info & uptime
      {PromEx.Plugins.Application, otp_app: :gamend_web},

      # Geo traffic metrics (request count by country)
      GamendWeb.PromEx.GeoPlugin,
      GamendWeb.PromEx.CachePlugin
    ] ++ host_plugins()
  end

  # A host's own PromEx plugins, appended to core's:
  # `config :gamend_web, :host_prom_ex_plugins, [MyHost.PromEx.BootPlugin]`.
  # Read at PromEx's start, like `:host_plugs` is at the endpoint's.
  defp host_plugins, do: Application.get_env(:gamend_web, :host_prom_ex_plugins, [])

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"}
    ]
  end
end
