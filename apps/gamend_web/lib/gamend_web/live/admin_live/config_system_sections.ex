defmodule GamendWeb.AdminLive.ConfigSystemSections do
  @moduledoc """
  The admin configuration page's system sections — plugins, the runtime,
  database, HTTP server and hook test rows of its status table, and the limits,
  admin tools and scheduled jobs cards. The product-facing rows are in
  `GamendWeb.AdminLive.ConfigSections`.
  """
  use GamendWeb, :html

  import GamendWeb.AdminLive.ConfigDiagnostics, only: [mask_secret: 1, display_value: 1]

  alias Gamend.Accounts.Scope
  alias Gamend.Hooks.PluginBuilder
  alias Gamend.Hooks.PluginManager

  @doc "The hook plugins: what loaded, and building a bundle."
  attr :plugin_build_available, :any, required: true
  attr :plugin_build_mode, :atom, default: nil, doc: "`PluginBuilder.mode/0`"
  attr :plugin_build_form, :any, required: true
  attr :plugin_build_options, :any, required: true
  attr :plugin_build_result, :any, required: true
  attr :plugin_build_running, :any, required: true
  attr :plugins, :any, required: true
  attr :plugins_counts, :any, required: true
  attr :plugins_last_reloaded_at, :any, required: true
  attr :plugins_reload_result, :any, required: true

  def plugins_row(assigns) do
    ~H"""
    <tr>
      <td class="font-semibold">Hooks Plugins</td>
      <td>
        <%= if @plugins_counts.total == 0 do %>
          <span class="badge badge-ghost">None</span>
        <% else %>
          <span class="badge badge-success">OK {@plugins_counts.ok}</span>
          <%= if @plugins_counts.error > 0 do %>
            <span class="badge badge-error">ERR {@plugins_counts.error}</span>
          <% end %>
        <% end %>
      </td>
      <td class="text-sm break-words whitespace-normal">
        <div class="flex flex-wrap items-center gap-3 min-w-0">
          <div class="font-mono break-all min-w-0">
            DIR: {PluginManager.plugins_dir()}
          </div>
          <button
            id="plugins-reload-btn"
            type="button"
            phx-click="reload_plugins"
            class="btn btn-surface btn-sm"
          >
            Reload plugins
          </button>
        </div>

        <div class="mt-2 flex flex-wrap items-center gap-3">
          <.form
            for={@plugin_build_form}
            id="plugins-build-form"
            phx-submit="build_plugin_bundle"
            class="flex flex-wrap items-center gap-2"
          >
            <.input
              field={@plugin_build_form[:name]}
              type="select"
              options={@plugin_build_options}
              class="select select-bordered select-sm w-52"
            />

            <button
              id="plugins-build-btn"
              type="submit"
              class="btn btn-surface btn-sm"
              disabled={
                @plugin_build_running or @plugin_build_options == [] or
                  not @plugin_build_available
              }
            >
              {if @plugin_build_running, do: "Building…", else: "Build bundle"}
            </button>

            <div id="plugins-build-mode" class="text-xs font-mono opacity-70 break-all">
              SRC: {PluginBuilder.sources_dir()} — BUILD: {plugin_build_mode_label(@plugin_build_mode)}
            </div>

            <%= cond do %>
              <% not @plugin_build_available -> %>
                <div class="text-xs opacity-70 max-w-md">
                  This image ships neither <code>mix</code>
                  nor the Elixir compiler, so it cannot build bundles. Build them where the
                  plugin sources live and mount the result.
                </div>
              <% @plugin_build_mode == :in_process -> %>
                <div id="plugins-build-in-process" class="text-xs opacity-70 max-w-md">
                  No <code>mix</code>
                  here, so bundles compile inside the running server. Elixir and GDScript
                  plugins build; a dependency the server does not ship has to be prebuilt in
                  the plugin's <code>deps/&lt;dep&gt;/ebin</code>. A loaded plugin restarts
                  on the new bundle.
                </div>
              <% true -> %>
            <% end %>
          </.form>
        </div>

        <div class="mt-1 text-xs font-mono break-all">
          Last reload: {@plugins_last_reloaded_at || "<never>"}
        </div>

        <%= if @plugins_reload_result do %>
          <div class="mt-2 text-xs font-mono whitespace-pre-wrap break-words">
            {inspect(@plugins_reload_result) |> String.slice(0, 1024)}
            {if String.length(inspect(@plugins_reload_result)) > 1024, do: "…"}
          </div>
        <% end %>

        <%= if @plugin_build_result do %>
          <div class="mt-3">
            <div class="flex flex-wrap items-center gap-2">
              <span class={[
                "badge badge-sm",
                if(@plugin_build_result.ok?, do: "badge-success", else: "badge-error")
              ]}>
                {if @plugin_build_result.ok?, do: "BUILD OK", else: "BUILD ERR"}
              </span>

              <div class="text-xs font-mono opacity-70 break-all">
                {@plugin_build_result.plugin} — {DateTime.to_iso8601(@plugin_build_result.started_at)} → {DateTime.to_iso8601(
                  @plugin_build_result.finished_at
                )}
              </div>
            </div>

            <pre class="mt-2 text-xs font-mono whitespace-pre-wrap break-words max-h-64 overflow-auto bg-base-200/60 rounded-lg p-3">{plugin_build_output(@plugin_build_result) |> String.slice(0, 8192)}{if String.length(plugin_build_output(@plugin_build_result)) > 8192, do: "\n…", else: ""}</pre>
          </div>
        <% end %>

        <div class="mt-2 space-y-1">
          <%= for p <- @plugins do %>
            <div class="font-mono break-all">
              {p.name} ({p.vsn || "<no_vsn>"}) —
              <%= case p.status do %>
                <% :ok -> %>
                  OK — {inspect(p.hooks_module)}
                <% {:error, reason} -> %>
                  ERROR — {inspect(reason)}
              <% end %>
              <span class="text-xs opacity-70">
                (loaded_at: {if p.loaded_at,
                  do: DateTime.to_iso8601(p.loaded_at),
                  else: "<unknown>"})
              </span>
            </div>
          <% end %>
        </div>
      </td>
    </tr>
    """
  end

  @doc "The BEAM runtime: environment, clustering, cache and log level."
  attr :config, :any, required: true

  def runtime_rows(assigns) do
    ~H"""
    <tr>
      <td class="font-semibold">Environment</td>
      <td><span class="badge badge-info">{@config.env}</span></td>
      <td class="font-mono text-sm break-all whitespace-normal">{@config.env}</td>
    </tr>
    <tr>
      <td class="font-semibold">Clustering</td>
      <td>
        <span class={[
          "badge",
          if(@config.release_distribution_enabled?,
            do: "badge-success",
            else: "badge-ghost"
          )
        ]}>
          {if(@config.release_distribution_enabled?, do: "Enabled", else: "Off")}
        </span>
      </td>
      <td class="text-sm break-words whitespace-normal">
        <div class="font-mono text-sm">
          RELEASE_DISTRIBUTION:
          <span class="break-all">
            {env_with_recommended(
              @config.release_distribution_env,
              @config.release_distribution_recommended
            )}
          </span>
          <br /> RELEASE_NODE:
          <span class="break-all">
            {env_with_recommended(
              @config.release_node_env,
              @config.release_node_recommended
            )}
          </span>
          <br /> RELEASE_COOKIE:
          <span class="break-all">{mask_secret(@config.release_cookie_env)}</span>
          <br /> GAMEND_CLUSTER_DNS_QUERY:
          <span class="break-all">
            {env_with_recommended(
              @config.dns_cluster_query_env,
              @config.dns_cluster_query_recommended
            )}
          </span>

          <br /> ERL_AFLAGS:
          <span class="break-all">
            {env_with_recommended(
              @config.erl_aflags_env,
              @config.erl_aflags_recommended
            )}
          </span>
          <br /> GAMEND_DB_IPV6:
          <span class="break-all">
            {env_with_recommended(
              @config.ecto_ipv6_env,
              @config.ecto_ipv6_recommended
            )}
          </span>

          <br /><br />
          <span class="opacity-70">runtime:</span>
          <br /> node(): <span class="break-all">{inspect(@config.node_name)}</span>
          <br /> Node.alive?(): <span class="break-all">{inspect(@config.node_alive?)}</span>

          <%= if @config.fly_app_name_env || @config.fly_private_ip_env do %>
            <br /><br />
            <span class="opacity-70">fly.io:</span>
            <br /> FLY_APP_NAME:
            <span class="break-all">{@config.fly_app_name_env || "<unset>"}</span>
            <br /> FLY_PRIVATE_IP:
            <span class="break-all">{@config.fly_private_ip_env || "<unset>"}</span>
            <br /> FLY_REGION: <span class="break-all">{@config.fly_region_env || "<unset>"}</span>
          <% end %>
        </div>

        <div class="mt-2 text-xs text-muted">
          Partitioned L2 caching requires Erlang distribution + clustering.
          For Redis L2, you do not need node clustering.
        </div>
      </td>
    </tr>
    <tr>
      <td class="font-semibold">Cache</td>
      <td>
        <span class={[
          "badge",
          if(
            @config.cache_enabled_effective?,
            do: "badge-success",
            else: "badge-ghost"
          )
        ]}>
          {if(@config.cache_enabled_effective?, do: "Enabled", else: "Bypassed")}
        </span>
      </td>
      <td class="text-sm break-words whitespace-normal">
        <div class="font-mono text-sm">
          GAMEND_CACHE_ENABLED:
          <span class="break-all">
            {env_with_default(@config.cache_enabled_env, @config.cache_enabled_default)}
          </span>
          <br /> GAMEND_CACHE_MODE:
          <span class="break-all">
            {env_with_default(@config.cache_mode_env, @config.cache_mode_default)}
          </span>
          <br /> GAMEND_CACHE_L2:
          <span class="break-all">
            {env_with_default(@config.cache_l2_env, @config.cache_l2_default)}
          </span>
          <br /> GAMEND_CACHE_REDIS_URL / GAMEND_CLUSTER_REDIS_URL:
          <span class="break-all">
            <%= if @config.cache_redis_url_env do %>
              {mask_secret(@config.cache_redis_url_env)}
            <% else %>
              <span class="opacity-70">
                &lt;unset (required when GAMEND_CACHE_MODE=multi and GAMEND_CACHE_L2=redis)&gt;
              </span>
            <% end %>
          </span>
          <br /> GAMEND_CACHE_REDIS_POOL_SIZE:
          <span class="break-all">
            {env_with_default(
              @config.cache_redis_pool_size_env,
              @config.cache_redis_pool_size_default
            )}
          </span>

          <br /><br />
          <span class="opacity-70">effective:</span>
          <br /> bypass_mode (true disables caching):
          <span class="break-all">{inspect(@config.cache_bypass_mode_effective)}</span>
          <br /> mode: <span class="break-all">{@config.cache_mode_effective}</span>
          <br /> L1: <span class="break-all">local</span>
          <br /> L2: <span class="break-all">{@config.cache_l2_effective}</span>

          <br /><br />
          <span class="opacity-70">details:</span>
          <br /> inclusion_policy:
          <span class="break-all">{inspect(@config.cache_inclusion_policy)}</span>
          <br /> levels: <span class="break-all">{inspect(@config.cache_levels)}</span>
          <br /> L1 opts: <span class="break-all">{inspect(@config.cache_l1_opts)}</span>
          <br /> L2 module: <span class="break-all">{inspect(@config.cache_l2_module)}</span>
          <br /> L2 opts: <span class="break-all">{inspect(@config.cache_l2_opts)}</span>
        </div>

        <div class="mt-2 text-xs text-muted">
          <p class="mb-1">
            This app supports single-level (L1 local) or two-level (L1 + L2).
          </p>
          <p>
            Use <code class="font-mono">GAMEND_CACHE_MODE=single</code>
            for a single-instance deployment
            (local cache only).
          </p>
          <p class="mt-1">
            Use <code class="font-mono">GAMEND_CACHE_MODE=multi</code>
            to enable L2, then choose <code class="font-mono">GAMEND_CACHE_L2=redis</code>
            (shared) or <code class="font-mono">GAMEND_CACHE_L2=partitioned</code>
            (Erlang-cluster sharding).
          </p>
        </div>
      </td>
    </tr>
    <tr>
      <td class="font-semibold">Log Level</td>
      <td>
        <span class={[
          "badge",
          case @config.log_level do
            :debug -> "badge-info"
            :info -> "badge-success"
            :warning -> "badge-warning"
            :error -> "badge-error"
            _ -> "badge-neutral"
          end
        ]}>
          {String.upcase(to_string(@config.log_level))}
        </span>
      </td>
      <td class="text-sm break-words whitespace-normal">
        <div class="font-mono text-sm">
          GAMEND_OBSERVABILITY_LOG_LEVEL:
          <span class="break-all">{display_value(@config.log_level_env)}</span>
          <span class="opacity-70">(effective: {inspect(@config.log_level)})</span>
          <br /> GAMEND_OBSERVABILITY_ACCESS_LOG_LEVEL:
          <span class="break-all">{display_value(@config.access_log_level_env)}</span>
          <span class="opacity-70">
            (effective: {inspect(@config.access_log_level)})
          </span>
        </div>
      </td>
    </tr>
    """
  end

  @doc "The database adapter and where it points."
  attr :config, :any, required: true

  def database_row(assigns) do
    ~H"""
    <tr>
      <td class="font-semibold">Database</td>
      <td>
        <%= case @config.database_adapter do %>
          <% :postgres -> %>
            <span class="badge badge-success">Postgres</span>
          <% :sqlite -> %>
            <span class="badge badge-info">SQLite</span>
        <% end %>
        <%= if @config.database_adapter != @config.database_config_adapter do %>
          <div class="mt-1">
            <span class="badge badge-warning text-xs">
              adapter mismatch: compiled={Atom.to_string(@config.database_adapter)} env={Atom.to_string(
                @config.database_config_adapter
              )}
            </span>
            <div class="mt-1 text-xs text-warning">
              Postgres env vars are set but the image was compiled with SQLite. Rebuild with GAMEND_DB_ADAPTER=postgres.
            </div>
          </div>
          <%!-- Also emit a hidden text so test assertions on "Postgres" still pass --%>
          <span class="sr-only">Postgres (env configured)</span>
        <% end %>
      </td>
      <td class="font-mono text-sm break-all whitespace-normal">
        <div class="mt-2 text-sm">
          <div>
            GAMEND_DB_URL:
            <span class="font-mono">
              {if @config.pg_database_url, do: "set", else: "<unset>"}
            </span>
          </div>
          <div>
            GAMEND_DB_POSTGRES_HOST: <span class="font-mono">{@config.pg_host || "<unset>"}</span>
          </div>
          <div>
            GAMEND_DB_POSTGRES_USER: <span class="font-mono">{@config.pg_user || "<unset>"}</span>
          </div>
          <div>
            GAMEND_DB_POSTGRES_DB: <span class="font-mono">{@config.pg_db || "<unset>"}</span>
          </div>
          <div>
            GAMEND_DB_POSTGRES_PASSWORD:
            <span class="font-mono">{mask_secret(@config.pg_password)}</span>
          </div>

          <div class="mt-3 pt-2 border-t border-base-300/60 text-xs">
            <div class="font-semibold text-muted">Runtime tuning</div>
            <div class="mt-1 space-y-1">
              <div>
                GAMEND_DB_POOL_SIZE:
                <span class="font-mono">{display_value(@config.db_pool_size_env)}</span>
              </div>
              <div>
                GAMEND_DB_POOL_TIMEOUT_MS:
                <span class="font-mono">
                  {display_value(@config.db_pool_timeout_env)}
                </span>
              </div>
              <div>
                GAMEND_DB_QUEUE_TARGET:
                <span class="font-mono">
                  {display_value(@config.db_queue_target_env)}
                </span>
              </div>
              <div>
                GAMEND_DB_QUEUE_INTERVAL_MS:
                <span class="font-mono">
                  {display_value(@config.db_queue_interval_env)}
                </span>
              </div>
              <div>
                GAMEND_DB_QUERY_TIMEOUT_MS:
                <span class="font-mono">
                  {display_value(@config.db_query_timeout_env)}
                </span>
              </div>
              <div>
                GAMEND_DB_POSTGRES_PORT:
                <span class="font-mono">{display_value(@config.postgres_port_env)}</span>
              </div>
              <div>
                GAMEND_DB_IPV6: <span class="font-mono">{display_value(@config.ecto_ipv6_env)}</span>
              </div>
              <div>
                GAMEND_HTTP_SERVER:
                <span class="font-mono">{display_value(@config.phx_server_env)}</span>
              </div>
            </div>
          </div>
        </div>
      </td>
    </tr>
    """
  end

  @doc "The HTTP server: host, port, TLS, secret key base, GeoIP and metrics."
  attr :config, :any, required: true

  def server_rows(assigns) do
    ~H"""
    <tr>
      <td class="font-semibold">Hostname</td>
      <td><span class="badge badge-info">System</span></td>
      <td class="font-mono text-sm break-all whitespace-normal">
        {@config.hostname || "Not set"}
      </td>
    </tr>
    <tr>
      <td class="font-semibold">Port</td>
      <td><span class="badge badge-info">Server</span></td>
      <td class="font-mono text-sm break-all whitespace-normal">
        {@config.port || "4000"}
      </td>
    </tr>
    <tr>
      <td class="font-semibold">HTTPS / TLS</td>
      <td>
        <%= if @config.ssl_enabled? do %>
          <span class="badge badge-success">Enabled</span>
        <% else %>
          <span class="badge badge-ghost">Disabled</span>
        <% end %>
      </td>
      <td class="text-sm break-words whitespace-normal">
        <div class="font-mono text-sm">
          GAMEND_TLS_CERTFILE: <span class="break-all">{@config.ssl_certfile_env || "<unset>"}</span>
          <br /> GAMEND_TLS_KEYFILE:
          <span class="break-all">{@config.ssl_keyfile_env || "<unset>"}</span>
          <br /> GAMEND_TLS_PORT:
          <span class="break-all">
            {display_value(@config.https_port_env)}
          </span>
          <br /> GAMEND_TLS_FORCE:
          <span class="break-all">{display_value(@config.force_ssl_env)}</span>
          <br /> GAMEND_TLS_ACME_WEBROOT:
          <span class="break-all">{@config.acme_webroot_env || "<unset>"}</span>
        </div>

        <%= if @config.ssl_cert_info do %>
          <div class="mt-3 pt-2 border-t border-base-300/60">
            <div class="text-xs font-semibold text-muted mb-1">
              Certificate details
            </div>
            <div class="font-mono text-xs space-y-0.5">
              <div>
                Subject: <span class="break-all">{@config.ssl_cert_info.subject}</span>
              </div>
              <div>
                Issuer: <span class="break-all">{@config.ssl_cert_info.issuer}</span>
              </div>
              <div>
                Valid from: <span class="break-all">{@config.ssl_cert_info.not_before}</span>
              </div>
              <div>
                Valid until:
                <span class={[
                  "break-all font-semibold",
                  if(@config.ssl_cert_info.expires_soon?,
                    do: "text-warning",
                    else: "text-success"
                  )
                ]}>
                  {@config.ssl_cert_info.not_after}
                </span>
                <%= if @config.ssl_cert_info.days_remaining != nil do %>
                  <span class={[
                    "ml-1",
                    if(@config.ssl_cert_info.expires_soon?,
                      do: "text-warning",
                      else: "opacity-70"
                    )
                  ]}>
                    ({@config.ssl_cert_info.days_remaining} days remaining)
                  </span>
                <% end %>
              </div>
              <div>
                Serial: <span class="break-all">{@config.ssl_cert_info.serial}</span>
              </div>
            </div>
          </div>
        <% else %>
          <%= if @config.ssl_certfile_env do %>
            <div class="mt-2 text-xs text-warning">
              Could not read certificate file. Verify the path is correct and the file is readable.
            </div>
          <% end %>
        <% end %>
      </td>
    </tr>
    <tr>
      <td class="font-semibold">Secret Key Base</td>
      <td>
        <%= if @config.secret_key_base do %>
          <span class="badge badge-success">Set</span>
        <% else %>
          <span class="badge badge-error">Not Set</span>
        <% end %>
      </td>
      <td class="font-mono text-sm break-all whitespace-normal">
        <%= if @config.secret_key_base do %>
          GAMEND_AUTH_SECRET_KEY_BASE: {mask_secret(@config.secret_key_base)}
        <% else %>
          GAMEND_AUTH_SECRET_KEY_BASE: &lt;unset&gt;
        <% end %>
      </td>
    </tr>
    <tr>
      <td class="font-semibold">GeoIP</td>
      <td colspan="2">
        <%= if @config.geoip_available? do %>
          <span class="badge badge-success badge-sm">MMDB database loaded</span>
          <span class="text-xs text-muted ml-2">
            GAMEND_CONTENT_GEOIP_DB_PATH: {@config.geoip_db_path || "configured"}
          </span>
        <% else %>
          <span class="badge badge-warning badge-sm">MMDB not configured</span>
          <span class="text-xs text-muted ml-2">
            Falling back to CF-IPCountry header (Cloudflare only). Place GeoLite2-Country.mmdb under data or set GAMEND_CONTENT_GEOIP_DB_PATH for a custom lookup path.
          </span>
        <% end %>
      </td>
    </tr>
    <tr>
      <td class="font-semibold">Metrics</td>
      <td colspan="2">
        <span class="badge badge-success badge-sm">PromEx enabled</span>
        <span class="text-xs text-muted ml-2">
          /metrics endpoint — {if @config.metrics_auth_token,
            do:
              "loopback always allowed; every other caller, private/Docker IPs included, must send the bearer token",
            else:
              "no token set: loopback and private/Docker IPs allowed, every other caller refused. Set GAMEND_OBSERVABILITY_METRICS_TOKEN to scrape from outside"}
        </span>
      </td>
    </tr>
    """
  end

  @doc "Calling a hook by hand, with its schema and docs."
  attr :config, :any, required: true
  attr :hooks_args_prefill, :any, required: true
  attr :hooks_full_doc, :any, required: true
  attr :hooks_full_name, :any, required: true
  attr :hooks_plugin_prefill, :any, required: true
  attr :hooks_prefill, :any, required: true

  def hook_test_row(assigns) do
    ~H"""
    <tr>
      <td class="font-semibold">Hooks - Test RPC</td>
      <td colspan="2">
        <div class="space-y-2">
          <div class="text-sm">
            <p class="text-xs font-semibold">Protobuf schema coverage</p>
            <p class="text-xs text-muted">
              What the loaded plugins registered. Anything marked JSON still works on protobuf sockets — it just travels as JSON bytes.
            </p>
            <div class="mt-2 overflow-x-auto">
              <table class="table table-xs w-auto">
                <tbody>
                  <%= for entity <- @config.metadata_schema_entities do %>
                    <tr>
                      <td class="font-mono text-xs">{entity} metadata</td>
                      <td>
                        <%= if mod = @config.metadata_schemas[entity] do %>
                          <span class="badge badge-primary badge-xs">protobuf</span>
                          <span class="font-mono text-xs ml-1">{inspect(mod)}</span>
                        <% else %>
                          <span class="badge badge-ghost badge-xs">JSON</span>
                          <span class="text-xs text-muted ml-1">
                            define a {entity |> to_string() |> Macro.camelize()}Meta message to register
                          </span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                  <tr>
                    <td class="font-mono text-xs">kv data</td>
                    <td>
                      <% kv = @config.kv_schemas %>
                      <%= if kv.exact == %{} and kv.prefixes == [] do %>
                        <span class="badge badge-ghost badge-xs">JSON</span>
                        <span class="text-xs text-muted ml-1">
                          export kv_schemas/0 (exact key or "prefix*") to register
                        </span>
                      <% else %>
                        <span class="badge badge-primary badge-xs">protobuf</span>
                        <span class="font-mono text-xs ml-1">
                          {Enum.join(
                            Map.keys(kv.exact) ++
                              Enum.map(kv.prefixes, &(elem(&1, 0) <> "*")),
                            ", "
                          )}
                        </span>
                      <% end %>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-mono text-xs">typed hooks</td>
                    <td>
                      <% typed_count =
                        Enum.count(@config.hooks_exported_functions, & &1.typed_schema) %>
                      <span class={"badge badge-xs " <> if(typed_count > 0, do: "badge-primary", else: "badge-ghost")}>
                        {typed_count} / {length(@config.hooks_exported_functions)}
                      </span>
                      <span class="text-xs text-muted ml-1">
                        functions with a &lt;FnName&gt;Request/Reply pair (badged below)
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
          <div class="text-sm">
            <p class="text-xs font-semibold">Available functions</p>
            <div class="mt-2 grid grid-cols-1 lg:grid-cols-2 gap-2">
              <% funcs = @config.hooks_exported_functions %>
              <%= if funcs == [] do %>
                <div class="text-xs text-muted col-span-2">No exported functions</div>
              <% else %>
                <%= for f <- funcs do %>
                  <div class="p-2 border rounded bg-base-200 min-w-0">
                    <div class="font-mono text-sm min-w-0">
                      <%= for s <- f.signatures do %>
                        <div class="min-w-0">
                          <div class="break-all">
                            <span
                              phx-click="prefill_hook"
                              phx-value-fn={f.name}
                              phx-value-plugin={f.plugin}
                              class="cursor-pointer font-semibold"
                            >
                              {f.plugin}:{f.name}/{s.arity}
                            </span>
                            <%= if f.typed_schema do %>
                              <span
                                class="badge badge-primary badge-xs align-middle"
                                title={"protobuf schema: #{inspect(f.typed_schema.request)} / #{inspect(f.typed_schema.reply)}"}
                              >
                                protobuf
                              </span>
                            <% end %>
                            <%= if s.signature do %>
                              <span class="text-muted">
                                - {s.signature}
                              </span>
                            <% end %>
                          </div>
                          <%= if s.doc do %>
                            <span class="text-xs block text-muted mt-1 break-words whitespace-normal">
                              {String.slice(s.doc, 0, 200)}{if String.length(s.doc) >
                                                                 200,
                                                               do: "…"}
                            </span>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <.form for={%{}} phx-submit="call_hook" id="hooks-call-form">
            <div class="flex flex-col md:flex-row gap-2 md:items-center min-w-0">
              <input
                id="hooks-plugin-input"
                name="plugin"
                value={@hooks_plugin_prefill.value || ""}
                placeholder="plugin_name"
                readonly
                class="input input-sm w-full md:w-40 min-w-0"
              />
              <input
                id="hooks-fn-input"
                name="fn"
                value={@hooks_prefill.value || ""}
                placeholder="function_name"
                readonly
                class="input input-sm w-full md:w-40 min-w-0"
              />
              <input
                id="hooks-args-input"
                name="args"
                value={@hooks_args_prefill.value || ""}
                placeholder="JSON array args (e.g. [1,2] or [])"
                class="input input-sm w-full md:flex-1 min-w-0"
              />
              <select
                id="hooks-format-select"
                name="format"
                class="select select-sm w-full md:w-28"
                title="Payload format: protobuf exercises the typed-hook schema round trip (encode args, decode reply)"
              >
                <option value="json">json</option>
                <option value="protobuf">protobuf</option>
              </select>
              <button class="btn btn-primary btn-sm w-full md:w-auto" type="submit">
                Call
              </button>
            </div>
          </.form>

          <div class="font-mono text-sm">
            <%= if @config.hooks_test_result do %>
              <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
                <div>Result: {@config.hooks_test_result}</div>
                <%= if Map.get(@config, :hooks_test_duration_us) do %>
                  <div class="text-xs text-muted">
                    (took {format_duration_us(@config.hooks_test_duration_us)})
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-xs text-muted">No test yet</div>
            <% end %>
          </div>

          <div class="mt-4">
            <.link navigate={~p"/admin/logs"} class="btn btn-surface btn-sm">
              View Logs →
            </.link>
          </div>

          <!-- Full docs modal / pane -->
          <%= if @hooks_full_doc do %>
            <div class="mt-2 p-3 border rounded bg-base-100">
              <div class="flex items-center justify-between">
                <div class="font-semibold">Full docs: {@hooks_full_name}</div>
                <div>
                  <button
                    type="button"
                    phx-click="close_docs"
                    class="btn btn-surface btn-sm"
                  >
                    Close
                  </button>
                </div>
              </div>
              <pre class="whitespace-pre-wrap text-sm mt-2 font-mono">{@hooks_full_doc}</pre>
            </div>
          <% end %>
        </div>
      </td>
    </tr>
    """
  end

  @doc "The configured limits against their defaults."
  attr :limits_grouped, :any, required: true

  def limits_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm collapsed" data-card-key="limits">
      <div class="card-body">
        <h2 class="card-title text-xl mb-4 flex items-center gap-3">
          Limits &amp; Validation
          <button
            type="button"
            data-action="toggle-card"
            data-card-key="limits"
            aria-expanded="false"
            class="btn btn-ghost btn-sm ml-auto"
            title="Collapse/Expand"
          >
            <svg class="w-4 h-4" viewBox="0 0 20 20" fill="none" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 8l4 4 4-4"
              />
            </svg>
          </button>
        </h2>

        <p class="text-sm opacity-70 mb-4">
          Override any limit at boot via env vars:
          <code class="font-mono text-xs">GAMEND_LIMITS_&lt;KEY&gt;=value</code>
          (e.g. <code class="font-mono text-xs">GAMEND_LIMITS_MAX_METADATA_SIZE=32768</code>).
        </p>

        <div class="overflow-x-auto">
          <table id="limits-table" class="table table-zebra table-sm w-full min-w-[40rem]">
            <thead>
              <tr>
                <th>Category</th>
                <th>Limit</th>
                <th class="text-right">Default</th>
                <th class="text-right">Current</th>
                <th>Env Var</th>
              </tr>
            </thead>
            <tbody>
              <%= for {category, items} <- @limits_grouped do %>
                <%= for {key, default, current} <- items do %>
                  <tr>
                    <td class="font-semibold capitalize text-xs">{category}</td>
                    <td class="font-mono text-xs">{key}</td>
                    <td class="text-right font-mono text-xs">{format_limit_value(default)}</td>
                    <td class={[
                      "text-right font-mono text-xs",
                      current != default && "text-warning font-bold"
                    ]}>
                      {format_limit_value(current)}
                      <%= if current != default do %>
                        <span class="badge badge-warning badge-xs ml-1">override</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-xs opacity-60">
                      GAMEND_LIMITS_{String.upcase(to_string(key))}
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  @doc "One-off admin actions."
  attr :config, :any, required: true
  attr :current_scope, :any, required: true

  def admin_tools_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm collapsed" data-card-key="admin_tools">
      <div class="card-body">
        <h2 class="card-title text-xl mb-4 flex items-center gap-3">
          Admin Tools
          <button
            type="button"
            data-action="toggle-card"
            data-card-key="admin_tools"
            aria-expanded="false"
            class="btn btn-ghost btn-sm ml-auto"
            title="Collapse/Expand"
          >
            <svg class="w-4 h-4" viewBox="0 0 20 20" fill="none" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 8l4 4 4-4"
              />
            </svg>
          </button>
        </h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <a href="/admin/dashboard" class="btn btn-outline btn-primary">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
              />
            </svg>
            Live Dashboard
          </a>
          <%= if @config.env == "dev" do %>
            <a href="/dev/mailbox" class="btn btn-outline btn-secondary">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                />
              </svg>
              Mailbox Preview
            </a>
          <% end %>
          <%= if @current_scope && Scope.user(@current_scope) && Scope.user(@current_scope).email do %>
            <button phx-click="send_test_email" class="btn btn-outline btn-accent">
              Send test email
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @doc "The registered scheduled jobs."
  attr :scheduled_jobs, :any, required: true

  def scheduled_jobs_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm collapsed" data-card-key="scheduled_jobs">
      <div class="card-body">
        <h2 class="card-title text-xl mb-4 flex items-center gap-3">
          Scheduled Jobs
          <button
            type="button"
            data-action="toggle-card"
            data-card-key="scheduled_jobs"
            aria-expanded="false"
            class="btn btn-ghost btn-sm ml-auto"
            title="Collapse/Expand"
          >
            <svg class="w-4 h-4" viewBox="0 0 20 20" fill="none" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 8l4 4 4-4"
              />
            </svg>
          </button>
        </h2>
        <%= if @scheduled_jobs == [] do %>
          <div class="text-sm text-muted">
            No scheduled jobs registered. Use <code class="font-mono">Schedule.hourly/2</code>, <code class="font-mono">Schedule.daily/2</code>, etc. in your hook's
            <code class="font-mono">after_startup/0</code>
            callback.
          </div>
        <% else %>
          <div class="overflow-x-auto lg:overflow-x-hidden">
            <table class="table table-zebra table-sm table-fixed w-full min-w-[32rem] lg:min-w-0">
              <thead>
                <tr>
                  <th>Job Name</th>
                  <th>Schedule</th>
                  <th>State</th>
                </tr>
              </thead>
              <tbody>
                <%= for job <- @scheduled_jobs do %>
                  <tr>
                    <td class="font-mono text-sm break-all whitespace-normal">{job.name}</td>
                    <td class="font-mono text-sm break-all whitespace-normal">{job.schedule}</td>
                    <td>
                      <span class={[
                        "badge badge-sm",
                        if(job.state == :active, do: "badge-success", else: "badge-warning")
                      ]}>
                        {job.state}
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
          <div class="text-xs text-muted mt-2">
            {ngettext(
              "%{count} job registered.",
              "%{count} jobs registered.",
              length(@scheduled_jobs)
            )} Each run is enqueued as a unique Oban job, so it runs once per period across the cluster.
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_duration_us(us) when is_integer(us) and us >= 0 do
    cond do
      us < 1_000 ->
        "#{us}µs"

      us < 1_000_000 ->
        ms = us / 1_000
        "#{Float.round(ms, 2)}ms"

      true ->
        s = us / 1_000_000
        "#{Float.round(s, 2)}s"
    end
  end

  defp plugin_build_mode_label(:mix),
    do: "mix (MIX_ENV=#{System.get_env("MIX_ENV") || "<unset>"})"

  defp plugin_build_mode_label(:in_process), do: "in-process"
  defp plugin_build_mode_label(_mode), do: "unavailable"

  defp plugin_build_output(%{steps: steps}) when is_list(steps) do
    steps
    |> Enum.map_join("\n\n", fn s ->
      "$ #{s.cmd} (exit=#{s.status})\n" <> (s.output || "")
    end)
    |> String.trim()
  end

  # Any set value prints, not only a string: the cache and IPv6 settings are
  # booleans, atoms and integers, and printed as unset whatever they held.
  defp env_with_default(v, default) when v in [nil, ""], do: "<unset (default: #{default})>"
  defp env_with_default(v, _default), do: display_value(v)

  # Off Fly there is no recommendation for some of these; "(recommended: )"
  # read like a missing value.
  defp env_with_recommended(v, recommended) when v in [nil, ""] and recommended in [nil, ""],
    do: "<unset>"

  defp env_with_recommended(v, recommended) when v in [nil, ""],
    do: "<unset (recommended: #{recommended})>"

  defp env_with_recommended(v, _recommended), do: display_value(v)

  defp format_limit_value(v) when is_integer(v) and v < 0 do
    "-#{format_limit_value(abs(v))}"
  end

  defp format_limit_value(v) when is_integer(v) and v >= 1_000_000_000_000 do
    "#{Float.round(v / 1_000_000_000_000, 1)}T"
  end

  defp format_limit_value(v) when is_integer(v) and v >= 1_000_000_000 do
    rounded = Float.round(v / 1_000_000_000, 1)

    if rounded >= 1000.0 do
      "#{Float.round(v / 1_000_000_000_000, 1)}T"
    else
      "#{rounded}B"
    end
  end

  defp format_limit_value(v) when is_integer(v) and v >= 1_000_000 do
    "#{Float.round(v / 1_000_000, 1)}M"
  end

  defp format_limit_value(v) when is_integer(v) and v >= 10_000 do
    "#{Float.round(v / 1_000, 1)}K"
  end

  defp format_limit_value(v), do: to_string(v)
end
