defmodule GamendWeb.AdminLive.Config do
  use GamendWeb, :live_view

  import GamendWeb.AdminLive.ConfigSections
  import GamendWeb.AdminLive.ConfigSystemSections

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Accounts.UserNotifier
  alias Gamend.Content
  alias Gamend.Hooks.HookSchemas
  alias Gamend.Hooks.KvSchemas
  alias Gamend.Hooks.MetadataSchemas
  alias Gamend.Hooks.PluginBuilder
  alias Gamend.Hooks.PluginManager
  alias Gamend.Schedule
  alias Gamend.Theme.JSONConfig
  alias GamendWeb.AdminLive.ConfigDiagnostics
  alias GamendWeb.Plugs.GeoCountry
  alias GamendWeb.Plugs.IpBan

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-surface mb-4">
          ← Back to Admin
        </.link>

        <!-- Current Configuration Status -->
        <div class="card bg-base-100 shadow-sm" data-card-key="config_status">
          <div class="card-body">
            <h2 class="card-title text-xl mb-4 flex items-center gap-3">
              Current Configuration Status
              <button
                type="button"
                data-action="toggle-card"
                data-card-key="config_status"
                aria-expanded="false"
                class="btn btn-ghost btn-sm ml-auto"
                title="Collapse/Expand"
              >
                ▸
              </button>
            </h2>
            <div class="overflow-x-auto lg:overflow-x-hidden">
              <table class="table table-zebra table-fixed w-full min-w-[48rem] lg:min-w-0">
                <colgroup>
                  <col class="w-44" />
                  <col class="w-32" />
                  <col class="w-auto" />
                </colgroup>
                <thead>
                  <tr>
                    <th>Service</th>
                    <th>Status</th>
                    <th>Details</th>
                  </tr>
                </thead>
                <tbody>
                  <.plugins_row
                    plugin_build_available={@plugin_build_available?}
                    plugin_build_mode={@plugin_build_mode}
                    plugin_build_form={@plugin_build_form}
                    plugin_build_options={@plugin_build_options}
                    plugin_build_result={@plugin_build_result}
                    plugin_build_running={@plugin_build_running?}
                    plugins={@plugins}
                    plugins_counts={@plugins_counts}
                    plugins_last_reloaded_at={@plugins_last_reloaded_at}
                    plugins_reload_result={@plugins_reload_result}
                  />
                  <.account_rows config={@config} />
                  <.theme_row config={@config} />
                  <.sign_in_rows config={@config} />
                  <.access_rows config={@config} ip_bans={@ip_bans} />
                  <.payments_row config={@config} />
                  <.email_row config={@config} />
                  <.runtime_rows config={@config} />
                  <.database_row config={@config} />
                  <.server_rows config={@config} />
                  <.hook_test_row
                    config={@config}
                    hooks_args_prefill={@hooks_args_prefill}
                    hooks_full_doc={@hooks_full_doc}
                    hooks_full_name={@hooks_full_name}
                    hooks_plugin_prefill={@hooks_plugin_prefill}
                    hooks_prefill={@hooks_prefill}
                  />
                </tbody>
              </table>
            </div>
          </div>
        </div>
        <.limits_card limits_grouped={@limits_grouped} />
        <.admin_tools_card config={@config} current_scope={@current_scope} />
        <.scheduled_jobs_card scheduled_jobs={@scheduled_jobs} />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    cache = ConfigDiagnostics.cache_diagnostics()
    clustering = ConfigDiagnostics.clustering_diagnostics()

    config = %{
      discord_client_id: Gamend.Settings.get(Gamend.OAuth.Providers, :discord_client_id),
      discord_client_secret: Gamend.Settings.get(Gamend.OAuth.Providers, :discord_client_secret),
      apple_web_client_id: Gamend.Settings.get(Gamend.OAuth.Providers, :apple_client_id),
      apple_ios_client_id: Gamend.Settings.get(Gamend.OAuth.Providers, :apple_ios_client_id),
      apple_team_id: Gamend.Settings.get(Gamend.OAuth.Providers, :apple_team_id),
      # Sign in with Apple's own key, not the App Store payments key of the same
      # name in Gamend.Payments.Settings.
      apple_key_id: Gamend.Settings.get(Gamend.OAuth.Providers, :apple_key_id),
      apple_private_key: Gamend.Settings.get(Gamend.OAuth.Providers, :apple_private_key),
      google_client_id: Gamend.Settings.get(Gamend.OAuth.Providers, :google_client_id),
      google_client_secret: Gamend.Settings.get(Gamend.OAuth.Providers, :google_client_secret),
      facebook_client_id: Gamend.Settings.get(Gamend.OAuth.Providers, :facebook_client_id),
      facebook_client_secret:
        Gamend.Settings.get(Gamend.OAuth.Providers, :facebook_client_secret),
      github_client_id: Gamend.Settings.get(Gamend.OAuth.Providers, :github_client_id),
      github_client_secret: Gamend.Settings.get(Gamend.OAuth.Providers, :github_client_secret),
      steam_api_key: Gamend.Settings.get(Gamend.OAuth.Providers, :steam_api_key),
      payment_provider_configs: ConfigDiagnostics.payment_provider_configs(),
      payment_provider_configured_count: ConfigDiagnostics.payment_provider_configured_count(),
      email_configured: Gamend.Settings.get(Gamend.Mail, :smtp_password) != nil,
      smtp_username: Gamend.Settings.get(Gamend.Mail, :smtp_username),
      smtp_password: Gamend.Settings.get(Gamend.Mail, :smtp_password),
      smtp_relay: Gamend.Settings.get(Gamend.Mail, :smtp_relay),
      smtp_port: Gamend.Settings.get(Gamend.Mail, :smtp_port),
      smtp_ssl: Gamend.Settings.get(Gamend.Mail, :smtp_ssl),
      smtp_from_name: Gamend.Settings.get(Gamend.Mail, :smtp_from_name),
      smtp_from_email: Gamend.Settings.get(Gamend.Mail, :smtp_from_email),
      smtp_sni: Gamend.Settings.get(Gamend.Mail, :smtp_sni),
      smtp_tls: Gamend.Settings.get(Gamend.Mail, :smtp_tls),
      env: to_string(Application.get_env(:gamend_web, :environment, :prod)),
      repo_conf: Application.get_env(:gamend_core, Gamend.Repo) || %{},
      database: Application.get_env(:gamend_core, Gamend.Repo)[:database] || "N/A",
      # Database environment diagnostics (don't show raw passwords)
      database_adapter: ConfigDiagnostics.detect_db_adapter(),
      database_config_adapter: ConfigDiagnostics.detect_db_config_adapter(),
      pg_database_url: Gamend.Settings.get(Gamend.Database, :url),
      pg_host: Gamend.Settings.get(Gamend.Database, :postgres_host),
      pg_user: Gamend.Settings.get(Gamend.Database, :postgres_user),
      pg_db: Gamend.Settings.get(Gamend.Database, :postgres_db),
      pg_password: Gamend.Settings.get(Gamend.Database, :postgres_password),
      # DB source detection and masked effective value for admin UI
      db_source: ConfigDiagnostics.detect_db_source(),
      db_effective_value: ConfigDiagnostics.detect_effective_db_value(),
      hostname:
        Application.get_env(:gamend_web, GamendWeb.Endpoint)[:url][:host] ||
          Gamend.Settings.get(GamendWeb.Http, :host),
      port: Gamend.Settings.get(GamendWeb.Http, :port) || "4000",
      secret_key_base:
        Gamend.Settings.get(Gamend.Accounts, :secret_key_base) ||
          Application.get_env(:gamend_web, GamendWeb.Endpoint)[:secret_key_base],
      live_reload: Application.get_env(:gamend_web, GamendWeb.Endpoint)[:live_reload] != nil,
      log_level: Logger.level(),
      log_level_env: Gamend.Settings.get(GamendWeb.Observability, :log_level),
      access_log_level: GamendWeb.endpoint().access_log_level(nil),
      access_log_level_env: Gamend.Settings.get(GamendWeb.Observability, :access_log_level),
      release_distribution_env: ConfigDiagnostics.cluster_env("RELEASE_DISTRIBUTION"),
      release_node_env: ConfigDiagnostics.cluster_env("RELEASE_NODE"),
      release_cookie_env: ConfigDiagnostics.cluster_env("RELEASE_COOKIE"),
      dns_cluster_query_env: Gamend.Settings.get(Gamend.Cluster, :dns_query),
      release_distribution_recommended: "name",
      release_node_recommended: clustering.release_node_recommended,
      dns_cluster_query_recommended: clustering.dns_cluster_query_recommended,
      erl_aflags_env: ConfigDiagnostics.cluster_env("ERL_AFLAGS"),
      erl_aflags_recommended: clustering.erl_aflags_recommended,
      node_name: node(),
      node_alive?: Node.alive?(),
      release_distribution_enabled?: Node.alive?(),
      # Only what the host set: the rows print "<unset (default: …)>" otherwise,
      # which `Gamend.Settings.get/2` would never let them do.
      cache_enabled_env: ConfigDiagnostics.setting_if_set(Gamend.Cache.Settings, :enabled),
      cache_mode_env: ConfigDiagnostics.setting_if_set(Gamend.Cache.Settings, :mode),
      cache_l2_env: ConfigDiagnostics.setting_if_set(Gamend.Cache.Settings, :l2),
      cache_redis_url_env:
        Gamend.Settings.get(Gamend.Cache.Settings, :redis_url) ||
          Gamend.Settings.get(Gamend.Cluster, :redis_url),
      cache_redis_pool_size_env:
        ConfigDiagnostics.setting_if_set(Gamend.Cache.Settings, :redis_pool_size),
      cache_enabled_default: "true",
      cache_mode_default: "single",
      cache_l2_default: "partitioned",
      cache_redis_pool_size_default: "10",
      cache_enabled_effective?: not cache.cache_bypass_mode_effective,
      cache_bypass_mode: cache.cache_bypass_mode,
      cache_bypass_mode_effective: cache.cache_bypass_mode_effective,
      cache_inclusion_policy: cache.cache_inclusion_policy,
      cache_mode_effective: cache.cache_mode_effective,
      cache_l2_effective: cache.cache_l2_effective,
      cache_levels: cache.cache_levels,
      cache_l1_opts: cache.cache_l1_opts,
      cache_l2_module: cache.cache_l2_module,
      cache_l2_opts: cache.cache_l2_opts,
      db_pool_size_env: Gamend.Settings.get(Gamend.Database, :pool_size),
      db_pool_timeout_env: Gamend.Settings.get(Gamend.Database, :pool_timeout_ms),
      db_queue_target_env: Gamend.Settings.get(Gamend.Database, :queue_target),
      db_queue_interval_env: Gamend.Settings.get(Gamend.Database, :queue_interval_ms),
      db_query_timeout_env: Gamend.Settings.get(Gamend.Database, :query_timeout_ms),
      postgres_port_env: Gamend.Settings.get(Gamend.Database, :postgres_port),
      ecto_ipv6_env: ConfigDiagnostics.setting_if_set(Gamend.Database, :ipv6),
      ecto_ipv6_recommended: clustering.ecto_ipv6_recommended,
      phx_server_env: Gamend.Settings.get(GamendWeb.Http, :server),
      fly_app_name_env: clustering.fly_app_name_env,
      fly_private_ip_env: clustering.fly_private_ip_env,
      fly_region_env: clustering.fly_region_env,
      # Hooks plugin diagnostics
      hooks_exported_functions: ConfigDiagnostics.exported_plugin_functions(),
      metadata_schema_entities: MetadataSchemas.entities(),
      metadata_schemas: MetadataSchemas.all(),
      kv_schemas: KvSchemas.all(),
      hooks_test_result: nil,
      hooks_test_duration_us: nil,
      # Theme configuration diagnostics: reuse the existing Theme provider
      # implementation so behavior is consistent across the app. We expose three
      # keys used by the template:
      #  - :theme_config -> the runtime GAMEND_CONTENT_THEME_CONFIG env value (path) or nil
      #  - :theme_map -> resolved theme map with host-owned branding assets
      #  - :theme_raw_map -> raw runtime JSON theme values (locale-specific)
      theme_map: GamendWeb.Layouts.resolve_theme(),
      theme_raw_map: JSONConfig.get_theme(),
      # Only rely on JSONConfig for decisions about runtime vs default and raw
      # content. Keep logic inside the provider instead of duplicating parsing
      # here.
      theme_config: JSONConfig.runtime_path(),
      # Dark variant / fullscreen image diagnostics (convention-based)
      theme_dark: ConfigDiagnostics.theme_dark_variants(GamendWeb.Layouts.resolve_theme()),
      content_paths: %{
        blog: Content.path(:blog),
        changelog: Content.path(:changelog),
        roadmap: Content.path(:roadmap)
      },
      device_auth_enabled: Gamend.Accounts.device_auth_enabled?(),
      device_auth_enabled_env: Gamend.Settings.get(Gamend.Accounts, :device_auth_enabled),
      require_account_activation: Gamend.Accounts.require_account_activation?(),
      require_account_activation_env: Gamend.Settings.get(Gamend.Accounts, :require_activation),
      min_password_length_env: Gamend.Settings.get(Gamend.Accounts.User, :min_password_length),
      min_password_length_set?:
        ConfigDiagnostics.setting_set?(Gamend.Accounts.User, :min_password_length),
      min_password_length_effective: User.min_password_length(),

      # PHX/CORS runtime configuration (set via GAMEND_HTTP_ALLOWED_ORIGINS)
      phx_allowed_origins_env: Gamend.Settings.get(GamendWeb.Http, :allowed_origins),
      phx_allowed_origins_set?: ConfigDiagnostics.setting_set?(GamendWeb.Http, :allowed_origins),
      cors_allowed_origins: Application.get_env(:gamend_web, :cors_allowed_origins, "*"),

      # HTTPS / TLS certificate diagnostics
      ssl_certfile_env: Gamend.Settings.get(GamendWeb.Tls, :certfile),
      ssl_keyfile_env: Gamend.Settings.get(GamendWeb.Tls, :keyfile),
      https_port_env: Gamend.Settings.get(GamendWeb.Tls, :port),
      force_ssl_env: Gamend.Settings.get(GamendWeb.Tls, :force),
      acme_webroot_env: Gamend.Settings.get(GamendWeb.Tls, :acme_webroot),
      ssl_enabled?: ConfigDiagnostics.ssl_enabled?(),
      ssl_cert_info: ConfigDiagnostics.ssl_cert_info(),

      # Rate limiting: the values the plug and channels enforce. These used to
      # be `Keyword.get` reads with their own fallbacks (1200/30/300/600),
      # which the page showed instead of the declared defaults (240/10/60/300).
      rate_limit_enabled: rate_limit(:enabled),
      rate_limit_general_limit: rate_limit(:general_limit),
      rate_limit_general_window: rate_limit(:general_window_ms),
      rate_limit_auth_limit: rate_limit(:auth_limit),
      rate_limit_auth_window: rate_limit(:auth_window_ms),
      rate_limit_ws_limit: rate_limit(:ws_limit),
      rate_limit_ws_window: rate_limit(:ws_window_ms),
      rate_limit_dc_limit: rate_limit(:dc_limit),
      rate_limit_dc_window: rate_limit(:dc_window_ms),
      rate_limit_ice_limit: rate_limit(:ice_limit),
      rate_limit_ice_window: rate_limit(:ice_window_ms),
      webrtc_max_channels: 1,
      webrtc_max_message_size: 65_536,
      geoip_available?: GeoCountry.geoip_available?(),
      geoip_db_path: Gamend.Settings.get(Gamend.ContentSettings, :geoip_db_path),
      metrics_auth_token: GamendWeb.Observability.get(:metrics_token)
    }

    socket =
      assign(socket,
        config: config,
        ip_bans: IpBan.list_bans(),
        limits_grouped: ConfigDiagnostics.limits_grouped(),
        scheduled_jobs: Schedule.list(),
        hooks_plugin_prefill: %{value: "", seq: 0},
        hooks_prefill: %{value: "", seq: 0},
        hooks_args_prefill: %{value: "", seq: 0},
        hooks_full_doc: nil,
        hooks_full_name: nil,
        plugins: PluginManager.list(),
        plugins_counts: ConfigDiagnostics.plugin_counts(PluginManager.list()),
        plugins_last_reloaded_at: nil,
        plugins_reload_result: nil,
        plugin_build_options: plugin_build_options(),
        plugin_build_available?: PluginBuilder.available?(),
        plugin_build_mode: PluginBuilder.mode(),
        plugin_build_running?: false,
        plugin_build_result: nil,
        plugin_build_form:
          to_form(%{"name" => default_plugin_build_selection()}, as: :plugin_build)
      )

    socket =
      if connected?(socket) do
        # The LiveView is rendered once over HTTP (disconnected) and then
        # mounts again after the websocket connects. In production, it is
        # also possible for the endpoint to accept traffic briefly before
        # hook plugins finish initializing (e.g. after a node restart).
        #
        # Refresh once shortly after connect so the Hooks Plugins section and
        # exported hooks list are consistent without manual page refreshes.
        Process.send_after(self(), :refresh_hooks_plugins, 250)
        socket
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_hooks_plugins, socket) do
    plugins = PluginManager.list()

    {:noreply,
     socket
     |> assign(:plugins, plugins)
     |> assign(:plugins_counts, ConfigDiagnostics.plugin_counts(plugins))
     |> assign(
       :config,
       Map.put(
         socket.assigns.config,
         :hooks_exported_functions,
         ConfigDiagnostics.exported_plugin_functions()
       )
     )}
  end

  @impl true
  def handle_info({:plugin_build_finished, _name, {:ok, build_result}}, socket) do
    # An in-process build restarts a plugin that was loaded, so the list may
    # have changed under us.
    plugins = PluginManager.list()

    {:noreply,
     socket
     |> assign(:plugin_build_running?, false)
     |> assign(:plugin_build_result, build_result)
     |> assign(:plugins, plugins)
     |> assign(:plugins_counts, ConfigDiagnostics.plugin_counts(plugins))
     |> put_flash(:info, "Plugin build finished")}
  end

  @impl true
  def handle_info({:plugin_build_finished, _name, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:plugin_build_running?, false)
     |> put_flash(:error, "Plugin build failed: #{inspect(reason)}")}
  end

  # Catch-all to avoid crashes from async messages (e.g. test email delivery)
  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("reload_plugins", _params, socket) do
    res = PluginManager.reload_and_after_startup()

    plugins = PluginManager.list()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    {:noreply,
     assign(socket,
       plugins: plugins,
       plugins_counts: ConfigDiagnostics.plugin_counts(plugins),
       plugins_last_reloaded_at: now,
       plugins_reload_result: res,
       config:
         Map.put(
           socket.assigns.config,
           :hooks_exported_functions,
           ConfigDiagnostics.exported_plugin_functions()
         )
     )}
  end

  @impl true
  def handle_event("build_plugin_bundle", %{"plugin_build" => %{"name" => name}}, socket)
      when is_binary(name) do
    cond do
      socket.assigns.plugin_build_running? ->
        {:noreply, socket}

      not socket.assigns.plugin_build_available? ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This image cannot build plugin bundles: it has neither mix nor the Elixir compiler."
         )}

      socket.assigns.plugin_build_options == [] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No buildable plugins found under #{PluginBuilder.sources_dir()}"
         )}

      true ->
        parent = self()

        Gamend.Async.run(fn ->
          result = PluginBuilder.build(name)
          send(parent, {:plugin_build_finished, name, result})
        end)

        {:noreply,
         socket
         |> assign(:plugin_build_running?, true)
         |> assign(:plugin_build_result, nil)
         |> put_flash(:info, "Building plugin bundle for #{name}…")}
    end
  end

  @impl true
  def handle_event(
        "call_hook",
        %{"plugin" => plugin, "fn" => fn_name, "args" => args_text} = params,
        socket
      )
      when is_binary(plugin) and is_binary(fn_name) do
    args = parse_hook_args(args_text)
    format = if params["format"] == "protobuf", do: :protobuf, else: :json

    caller = socket.assigns.current_scope && Scope.user(socket.assigns.current_scope)

    {duration_us, result} =
      :timer.tc(fn -> run_hook_test(plugin, fn_name, args, format, caller) end)

    config =
      socket.assigns.config
      |> Map.put(:hooks_test_result, result)
      |> Map.put(:hooks_test_duration_us, duration_us)

    {:noreply, assign(socket, :config, config)}
  end

  def handle_event("send_test_email", _params, socket) do
    user = socket.assigns.current_scope && Scope.user(socket.assigns.current_scope)

    case user && user.email do
      nil ->
        {:noreply, put_flash(socket, :error, "Your admin account has no email address.")}

      email when is_binary(email) ->
        case UserNotifier.deliver_test_email(email) do
          {:ok, _} ->
            {:noreply, put_flash(socket, :info, "Test email sent to #{email}")}

          other ->
            # Log full details for diagnostic purposes
            require Logger
            Logger.error("send_test_email failed: #{inspect(other)}")

            # Surface useful error detail in development so admins can debug
            debug_msg =
              if socket.assigns.config && socket.assigns.config.env == "dev" do
                " (details: #{inspect(other) |> to_string() |> String.slice(0, 512)})"
              else
                ""
              end

            {:noreply,
             put_flash(
               socket,
               :error,
               "Failed to send test email — check mailer logs and configuration" <> debug_msg
             )}
        end
    end
  end

  def handle_event("call_hook", _params, socket), do: {:noreply, socket}
  @impl true
  def handle_event("prefill_hook", %{"plugin" => plugin, "fn" => fn_name}, socket)
      when is_binary(plugin) and is_binary(fn_name) do
    seq = System.unique_integer([:positive])

    # Try to find example args for the selected function from the mounted
    # hooks_exported_functions (rendered into socket.assigns.config earlier)
    example =
      socket.assigns.config.hooks_exported_functions
      |> Enum.find_value(nil, fn f ->
        if to_string(f.name) == fn_name and to_string(f.plugin) == plugin do
          case f.signatures do
            [first | _] -> Map.get(first, :example_args) || ""
            _ -> nil
          end
        else
          nil
        end
      end)

    # Also set full docs panel when doc text is available
    doc_text =
      socket.assigns.config.hooks_exported_functions
      |> Enum.find_value(nil, fn f ->
        if to_string(f.name) == fn_name and to_string(f.plugin) == plugin do
          case f.signatures do
            [first | _] -> Map.get(first, :doc)
            _ -> nil
          end
        else
          nil
        end
      end)

    full_name =
      socket.assigns.config.hooks_exported_functions
      |> Enum.find_value(nil, fn f ->
        if to_string(f.name) == fn_name and to_string(f.plugin) == plugin do
          case f.signatures do
            [first | _] -> "#{fn_name}/#{first.arity}"
            _ -> nil
          end
        else
          nil
        end
      end)

    {:noreply,
     assign(socket,
       hooks_plugin_prefill: %{value: plugin, seq: seq},
       hooks_prefill: %{value: fn_name, seq: seq},
       hooks_args_prefill: %{value: example || "", seq: seq},
       hooks_full_doc: doc_text,
       hooks_full_name: if(full_name, do: "#{plugin}:#{full_name}", else: nil)
     )}
  end

  def handle_event("prefill_hook", _params, socket), do: {:noreply, socket}

  def handle_event("close_docs", _params, socket),
    do: {:noreply, assign(socket, hooks_full_doc: nil, hooks_full_name: nil)}

  defp rate_limit(key), do: Gamend.Settings.get(GamendWeb.Plugs.RateLimiter, key)

  defp plugin_build_options do
    PluginBuilder.list_buildable_plugins()
    |> Enum.map(fn name -> {name, name} end)
  end

  defp default_plugin_build_selection do
    plugin_build_options()
    |> Enum.at(0)
    |> case do
      {name, _} -> name
      _ -> ""
    end
  end

  # Runs the hook through the same conversion pipeline the realtime
  # transports use. In protobuf mode a typed hook additionally exercises the
  # full binary round trip (args encoded to request bytes, reply decoded
  # from reply bytes) and reports the wire sizes.
  defp run_hook_test(plugin, fn_name, args, :json, caller) do
    case HookSchemas.call(plugin, fn_name, {:list, args}, :map, caller: caller) do
      {:ok, res} -> inspect(res)
      {:error, reason} -> "error: #{inspect(reason)}"
    end
  end

  defp run_hook_test(plugin, fn_name, args, :protobuf, caller) do
    case HookSchemas.lookup(plugin, fn_name) do
      nil ->
        case HookSchemas.call(plugin, fn_name, {:list, args}, :map, caller: caller) do
          {:ok, res} ->
            inspect(res) <> " (no typed schema — dynamic args, protobuf envelope only)"

          {:error, reason} ->
            "error: #{inspect(reason)}"
        end

      %{request: req_mod, reply: reply_mod} ->
        with {:ok, req_struct} <- typed_request_from_args(req_mod, args),
             req_bytes = Protobuf.encode(req_struct),
             {:ok, {:raw, reply_bytes}} <-
               HookSchemas.call(plugin, fn_name, {:raw, req_bytes}, :binary, caller: caller) do
          decoded = reply_mod.decode(reply_bytes)

          "#{inspect(decoded)} (wire: #{byte_size(req_bytes)}B request, #{byte_size(reply_bytes)}B reply)"
        else
          {:error, reason} -> "error: #{inspect(reason)}"
        end
    end
  end

  defp typed_request_from_args(req_mod, []), do: {:ok, struct(req_mod)}

  defp typed_request_from_args(req_mod, [map]) when is_map(map) do
    Protobuf.JSON.from_decoded(map, req_mod)
  end

  defp typed_request_from_args(_req_mod, _args),
    do: {:error, :typed_hook_expects_single_object_arg}

  defp parse_hook_args(v) when is_binary(v) and v != "" do
    case Jason.decode(v) do
      {:ok, parsed} when is_list(parsed) -> parsed
      {:ok, parsed} -> [parsed]
      _ -> []
    end
  end

  defp parse_hook_args(_), do: []
end
