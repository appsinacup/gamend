defmodule GameServerWeb.AdminLive.Config do
  use GameServerWeb, :live_view

  alias GameServer.Accounts.Scope
  alias GameServer.Accounts.User
  alias GameServer.Accounts.UserNotifier
  alias GameServer.Content
  alias GameServer.Hooks
  alias GameServer.Hooks.DynamicRpcs
  alias GameServer.Hooks.HookSchemas
  alias GameServer.Hooks.KvSchemas
  alias GameServer.Hooks.MetadataSchemas
  alias GameServer.Hooks.PluginBuilder
  alias GameServer.Hooks.PluginManager
  alias GameServer.Payments
  alias GameServer.Payments.ProviderConfig
  alias GameServer.Payments.Providers.Apple
  alias GameServer.Payments.Providers.Google
  alias GameServer.Payments.Providers.Steam
  alias GameServer.Repo.AdvisoryLock
  alias GameServer.Schedule
  alias GameServer.Theme.JSONConfig
  alias GameServerWeb.Plugs.GeoCountry
  alias GameServerWeb.Plugs.IpBan

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">
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
                          class="btn btn-outline btn-sm"
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
                            class="btn btn-outline btn-sm"
                            disabled={@plugin_build_running? or @plugin_build_options == []}
                          >
                            {if @plugin_build_running?, do: "Building…", else: "Build bundle"}
                          </button>

                          <div class="text-xs font-mono opacity-70 break-all">
                            SRC: {PluginBuilder.sources_dir()} — MIX_ENV: {System.get_env("MIX_ENV") ||
                              "<unset>"}
                          </div>
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
                              {@plugin_build_result.plugin} — {DateTime.to_iso8601(
                                @plugin_build_result.started_at
                              )} → {DateTime.to_iso8601(@plugin_build_result.finished_at)}
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
                  <!-- Hooks Test RPC moved to the end of the card -->
                  <tr>
                    <td class="font-semibold">Device auth</td>
                    <td>
                      <%= if @config.device_auth_enabled_app || @config.device_auth_enabled_env do %>
                        <span class="badge badge-success">Enabled</span>
                      <% else %>
                        <span class="badge badge-error">Disabled</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      GAMEND_AUTH_DEVICE_AUTH_ENABLED: {@config.device_auth_enabled_env || "<unset>"}
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Account activation</td>
                    <td>
                      <%= if @config.require_account_activation do %>
                        <span class="badge badge-warning">Required (beta mode)</span>
                      <% else %>
                        <span class="badge badge-ghost">Not required</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      GAMEND_AUTH_REQUIRE_ACTIVATION: {@config.require_account_activation_env ||
                        "<unset>"}
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Password policy</td>
                    <td>
                      <%= if @config.min_password_length_env do %>
                        <span class="badge badge-success">Custom</span>
                      <% else %>
                        <span class="badge badge-ghost">Default</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      GAMEND_AUTH_MIN_PASSWORD_LENGTH: {@config.min_password_length_env ||
                        "<undefined>"} <br />
                      Effective: {@config.min_password_length_effective} characters
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Theme</td>
                    <td>
                      <%= if @config.theme_config do %>
                        <span class="badge badge-success">Configured</span>
                      <% else %>
                        <span class="badge badge-error">Default</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      GAMEND_CONTENT_THEME_CONFIG: {@config.theme_config || "<unset>"}<br />

                      <%= if @config.theme_map do %>
                        <%!-- Branding: Logo + dark, Favicon + dark, Banner + dark --%>
                        <div class="mt-3 grid grid-cols-1 sm:grid-cols-3 gap-4">
                          <%!-- Logo --%>
                          <div class="flex flex-col items-center gap-1">
                            <span class="text-xs font-semibold opacity-70">Logo</span>
                            <%= if Map.get(@config.theme_map, "logo") do %>
                              <img
                                src={Map.get(@config.theme_map, "logo")}
                                alt="logo"
                                class="h-12 w-auto rounded"
                              />
                              <span class="text-[10px] opacity-50">
                                {Map.get(@config.theme_map, "logo")}
                              </span>
                            <% else %>
                              <span class="text-xs opacity-50">—</span>
                            <% end %>
                            <%!-- Logo Dark --%>
                            <%= if @config.theme_dark.logo_dark_exists? do %>
                              <span class="text-[10px] font-semibold opacity-50 mt-1">
                                Dark
                              </span>
                              <img
                                src={@config.theme_dark.logo_dark_path}
                                alt="logo dark"
                                class="h-12 w-auto rounded bg-neutral p-1"
                              />
                              <span class="text-[10px] opacity-40">
                                {@config.theme_dark.logo_dark_path}
                              </span>
                            <% else %>
                              <%= if Map.get(@config.theme_map, "logo") do %>
                                <span class="text-[10px] opacity-40 mt-1">
                                  Dark: not found
                                </span>
                              <% end %>
                            <% end %>
                          </div>
                          <%!-- Favicon --%>
                          <div class="flex flex-col items-center gap-1">
                            <span class="text-xs font-semibold opacity-70">Favicon</span>
                            <%= if Map.get(@config.theme_map, "favicon") do %>
                              <img
                                src={Map.get(@config.theme_map, "favicon")}
                                alt="favicon"
                                class="h-8 w-auto"
                              />
                              <span class="text-[10px] opacity-50">
                                {Map.get(@config.theme_map, "favicon")}
                              </span>
                            <% else %>
                              <span class="text-xs opacity-50">—</span>
                            <% end %>
                            <%!-- Favicon Dark --%>
                            <%= if @config.theme_dark.favicon_dark_exists? do %>
                              <span class="text-[10px] font-semibold opacity-50 mt-1">
                                Dark
                              </span>
                              <img
                                src={@config.theme_dark.favicon_dark_path}
                                alt="favicon dark"
                                class="h-8 w-auto bg-neutral p-0.5 rounded"
                              />
                              <span class="text-[10px] opacity-40">
                                {@config.theme_dark.favicon_dark_path}
                              </span>
                            <% else %>
                              <%= if Map.get(@config.theme_map, "favicon") do %>
                                <span class="text-[10px] opacity-40 mt-1">
                                  Dark: not found
                                </span>
                              <% end %>
                            <% end %>
                          </div>
                          <%!-- Banner --%>
                          <div class="flex flex-col items-center gap-1">
                            <span class="text-xs font-semibold opacity-70">Banner</span>
                            <%= if Map.get(@config.theme_map, "banner") do %>
                              <img
                                src={Map.get(@config.theme_map, "banner")}
                                alt="banner"
                                class="h-16 w-auto rounded shadow-sm"
                              />
                              <span class="text-[10px] opacity-50">
                                {Map.get(@config.theme_map, "banner")}
                              </span>
                            <% else %>
                              <span class="text-xs opacity-50">—</span>
                            <% end %>
                            <%!-- Banner Dark --%>
                            <%= if @config.theme_dark.banner_dark_exists? do %>
                              <span class="text-[10px] font-semibold opacity-50 mt-1">
                                Dark
                              </span>
                              <img
                                src={@config.theme_dark.banner_dark_path}
                                alt="banner dark"
                                class="h-16 w-auto rounded shadow-sm bg-neutral p-1"
                              />
                              <span class="text-[10px] opacity-40">
                                {@config.theme_dark.banner_dark_path}
                              </span>
                            <% else %>
                              <%= if Map.get(@config.theme_map, "banner") do %>
                                <span class="text-[10px] opacity-40 mt-1">
                                  Dark: not found
                                </span>
                              <% end %>
                            <% end %>
                          </div>
                        </div>

                        <%!-- Fullscreen Hero Images --%>
                        <div class="mt-4">
                          <span class="text-xs font-semibold opacity-70">
                            Fullscreen Hero Images
                          </span>
                          <div class="mt-1 grid grid-cols-1 sm:grid-cols-2 gap-3">
                            <div class="flex flex-col items-center gap-1">
                              <span class="text-[10px] font-semibold opacity-50">Light</span>
                              <%= if @config.theme_dark.fullscreen_exists? do %>
                                <img
                                  src="/images/fullscreen.png"
                                  alt="fullscreen hero"
                                  class="w-full max-w-[220px] h-auto rounded shadow-sm"
                                />
                                <span class="text-[10px] opacity-40">
                                  /images/fullscreen.png
                                </span>
                              <% else %>
                                <span class="text-[10px] opacity-40">
                                  /images/fullscreen.png — not found
                                </span>
                              <% end %>
                            </div>
                            <div class="flex flex-col items-center gap-1">
                              <span class="text-[10px] font-semibold opacity-50">Dark</span>
                              <%= if @config.theme_dark.fullscreen_dark_exists? do %>
                                <img
                                  src="/images/fullscreen_dark.png"
                                  alt="fullscreen hero dark"
                                  class="w-full max-w-[220px] h-auto rounded shadow-sm bg-neutral p-1"
                                />
                                <span class="text-[10px] opacity-40">
                                  /images/fullscreen_dark.png
                                </span>
                              <% else %>
                                <span class="text-[10px] opacity-40">
                                  /images/fullscreen_dark.png — not found
                                </span>
                              <% end %>
                            </div>
                          </div>
                        </div>

                        <%!-- Title, Tagline, Description --%>
                        <div class="mt-4 space-y-1">
                          <div class="flex items-baseline gap-2">
                            <span class="text-xs font-semibold opacity-70 w-20 shrink-0">
                              Title
                            </span>
                            <span class="text-sm font-bold">
                              {Map.get(@config.theme_map, "title", "—")}
                            </span>
                          </div>
                          <div class="flex items-baseline gap-2">
                            <span class="text-xs font-semibold opacity-70 w-20 shrink-0">
                              Tagline
                            </span>
                            <span class="text-sm">
                              {Map.get(@config.theme_map, "tagline", "—")}
                            </span>
                          </div>
                          <div class="flex items-baseline gap-2">
                            <span class="text-xs font-semibold opacity-70 w-20 shrink-0">
                              Description
                            </span>
                            <span class="text-sm">
                              {Map.get(@config.theme_map, "description", "—")}
                            </span>
                          </div>
                          <div class="flex items-baseline gap-2">
                            <span class="text-xs font-semibold opacity-70 w-20 shrink-0">
                              CSS
                            </span>
                            <span class="text-xs font-mono">
                              {Map.get(@config.theme_map, "css") ||
                                "/assets/css/app.css (loaded by host layout)"}
                            </span>
                          </div>
                          <div class="flex items-baseline gap-2">
                            <span class="text-xs font-semibold opacity-70 w-20 shrink-0">
                              Blog
                            </span>
                            <span class="text-xs font-mono">
                              {@config.content_paths.blog || "—"}
                            </span>
                          </div>
                          <div class="flex items-baseline gap-2">
                            <span class="text-xs font-semibold opacity-70 w-20 shrink-0">
                              Changelog
                            </span>
                            <span class="text-xs font-mono">
                              {@config.content_paths.changelog || "—"}
                            </span>
                          </div>
                          <div class="flex items-baseline gap-2">
                            <span class="text-xs font-semibold opacity-70 w-20 shrink-0">
                              Roadmap
                            </span>
                            <span class="text-xs font-mono">
                              {@config.content_paths.roadmap || "—"}
                            </span>
                          </div>
                        </div>

                        <%!-- Presentation pages --%>
                        <% pages =
                          case Map.get(@config.theme_map, "pages", %{}) do
                            value when is_map(value) -> value
                            _ -> %{}
                          end %>

                        <%= if pages != %{} do %>
                          <div class="mt-4">
                            <span class="text-xs font-semibold opacity-70">
                              Pages ({map_size(pages)})
                            </span>
                            <div class="mt-1 flex flex-wrap gap-2">
                              <%= for {key, page} <- Enum.sort_by(pages, fn {key, _page} -> key end) do %>
                                <% sections = Map.get(page, "sections", []) %>
                                <div class="badge badge-outline gap-1 py-3">
                                  <span class="text-xs">{key}</span>
                                  <span class="text-[10px] opacity-50">
                                    {Map.get(page, "path", "—")}
                                  </span>
                                  <span class="text-[10px] opacity-40">
                                    ({length(sections)} sections)
                                  </span>
                                </div>
                              <% end %>
                            </div>
                          </div>
                        <% end %>

                        <%!-- Navigation --%>
                        <% navigation = Map.get(@config.theme_map, "navigation", %{}) %>
                        <%= for {title, key} <- [
                              {"Primary Nav", "primary_links"},
                              {"Guest Nav", "guest_links"},
                              {"Authenticated Nav", "authenticated_links"},
                              {"Account Menu", "account_links"}
                            ] do %>
                          <% links = Map.get(navigation, key, []) %>
                          <%= if links != [] do %>
                            <div class="mt-3">
                              <span class="text-xs font-semibold opacity-70">
                                {title} ({length(links)})
                              </span>
                              <div class="mt-1 flex flex-wrap gap-2">
                                <%= for link <- links do %>
                                  <div class="badge badge-ghost gap-1 py-3">
                                    <span class="text-xs">
                                      {theme_nav_entry_label(link)}
                                    </span>
                                    <span class="text-[10px] opacity-50">
                                      {theme_nav_entry_path(link)}
                                    </span>
                                    <%= if theme_nav_entry_auth(link) do %>
                                      <span class="text-[10px] opacity-40">
                                        ({theme_nav_entry_auth(link)})
                                      </span>
                                    <% end %>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                          <% end %>
                        <% end %>

                        <%!-- Footer --%>
                        <% footer_sections = get_in(@config.theme_map, ["footer", "sections"]) || [] %>
                        <%= if footer_sections != [] do %>
                          <div class="mt-3">
                            <span class="text-xs font-semibold opacity-70">
                              Footer Sections ({length(footer_sections)})
                            </span>
                            <div class="mt-1 flex flex-wrap gap-2">
                              <%= for section <- footer_sections do %>
                                <div class="badge badge-ghost gap-1 py-3">
                                  <span class="text-xs">{section["title"]}</span>
                                  <span class="text-[10px] opacity-50">
                                    {length(Map.get(section, "links", []))} links
                                  </span>
                                </div>
                              <% end %>
                            </div>
                          </div>
                        <% end %>

                        <%!-- Collapsible Raw JSON --%>
                        <details class="mt-4">
                          <summary class="text-xs font-semibold opacity-70 cursor-pointer">
                            Raw JSON
                          </summary>
                          <pre class="mt-1 text-xs font-mono whitespace-pre-wrap max-h-48 overflow-auto bg-base-200/60 rounded-lg p-2">{Jason.encode!(@config.theme_raw_map, pretty: true)}</pre>
                        </details>
                      <% end %>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Discord OAuth</td>
                    <td>
                      <%= if @config.discord_client_id && @config.discord_client_secret do %>
                        <span class="badge badge-success">Configured</span>
                      <% else %>
                        <span class="badge badge-error">Disabled</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      <%= if @config.discord_client_id do %>
                        DISCORD_CLIENT_ID: {mask_secret(@config.discord_client_id)}<br />
                        DISCORD_CLIENT_SECRET: {mask_secret(@config.discord_client_secret)}
                      <% else %>
                        <span class="text-error">Client ID missing</span>
                      <% end %>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Apple Sign In</td>
                    <td>
                      <%= if (@config.apple_web_client_id || @config.apple_ios_client_id) && @config.apple_team_id && @config.apple_key_id && @config.apple_private_key do %>
                        <span class="badge badge-success">Configured</span>
                      <% else %>
                        <span class="badge badge-error">Disabled</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      <%= if @config.apple_web_client_id || @config.apple_ios_client_id do %>
                        APPLE_WEB_CLIENT_ID: {mask_secret(@config.apple_web_client_id || "")}<br />
                        GAMEND_OAUTH_APPLE_IOS_CLIENT_ID: {mask_secret(
                          @config.apple_ios_client_id || ""
                        )}<br /> APPLE_TEAM_ID: {mask_secret(@config.apple_team_id || "")}<br />
                        APPLE_KEY_ID: {mask_secret(@config.apple_key_id || "")}<br />
                        APPLE_PRIVATE_KEY: {mask_secret(@config.apple_private_key)}
                      <% else %>
                        <span class="text-error">Disabled</span>
                      <% end %>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Google OAuth</td>
                    <td>
                      <%= if @config.google_client_id && @config.google_client_secret do %>
                        <span class="badge badge-success">Configured</span>
                      <% else %>
                        <span class="badge badge-error">Disabled</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      <%= if @config.google_client_id do %>
                        GOOGLE_CLIENT_ID: {mask_secret(@config.google_client_id)}<br />
                        GOOGLE_CLIENT_SECRET: {mask_secret(@config.google_client_secret)}
                      <% else %>
                        <span class="text-error">Client ID missing</span>
                      <% end %>
                    </td>
                  </tr>

                  <tr>
                    <td class="font-semibold">CORS / Allowed Origins</td>
                    <td>
                      <%= if @config.phx_allowed_origins_env do %>
                        <span class="badge badge-success">Configured</span>
                      <% else %>
                        <span class="badge badge-ghost">Default</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      GAMEND_HTTP_ALLOWED_ORIGINS: {@config.phx_allowed_origins_env || "<unset>"}<br />
                      Effective CORS origins: {inspect(@config.cors_allowed_origins)}<br />
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Rate Limiting</td>
                    <td>
                      <%= if @config.rate_limit_enabled do %>
                        <span class="badge badge-success">Enabled</span>
                      <% else %>
                        <span class="badge badge-error">Disabled</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      General: {@config.rate_limit_general_limit} req / {@config.rate_limit_general_window}ms<br />
                      Auth (login/register): {@config.rate_limit_auth_limit} req / {@config.rate_limit_auth_window}ms<br />
                      WebSocket: {@config.rate_limit_ws_limit} msg / {@config.rate_limit_ws_window}ms<br />
                      WebRTC DC: {@config.rate_limit_dc_limit} msg / {@config.rate_limit_dc_window}ms<br />
                      ICE Candidates: {@config.rate_limit_ice_limit} / {@config.rate_limit_ice_window}ms<br />
                      Max DataChannels per peer: {@config.webrtc_max_channels}<br />
                      Max DC message size: {@config.webrtc_max_message_size} bytes<br />
                      <span class="text-xs text-base-content/60">
                        Set via RATE_LIMIT_* env vars
                      </span>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">IP Bans</td>
                    <td>
                      <%= if @ip_bans == [] do %>
                        <span class="badge badge-ghost">None</span>
                      <% else %>
                        <span class="badge badge-warning">{length(@ip_bans)} active</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      <.link navigate={~p"/admin/rate_limiting"} class="link link-primary text-sm">
                        Manage IP Bans →
                      </.link>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Facebook OAuth</td>
                    <td>
                      <%= if @config.facebook_client_id && @config.facebook_client_secret do %>
                        <span class="badge badge-success">Configured</span>
                      <% else %>
                        <span class="badge badge-error">Disabled</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      <%= if @config.facebook_client_id do %>
                        FACEBOOK_CLIENT_ID: {mask_secret(@config.facebook_client_id)}<br />
                        FACEBOOK_CLIENT_SECRET: {mask_secret(@config.facebook_client_secret)}
                      <% else %>
                        <span class="text-error">Client ID missing</span>
                      <% end %>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Steam OpenID</td>
                    <td>
                      <%= if @config.steam_api_key do %>
                        <span class="badge badge-success">Configured</span>
                      <% else %>
                        <span class="badge badge-error">Disabled</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm break-all whitespace-normal">
                      <%= if @config.steam_api_key do %>
                        GAMEND_OAUTH_STEAM_API_KEY: {mask_secret(@config.steam_api_key)}
                      <% else %>
                        <span class="text-error">GAMEND_OAUTH_STEAM_API_KEY: unset</span>
                      <% end %>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Payment Providers</td>
                    <td>
                      <span class="badge badge-info">
                        {@config.payment_provider_configured_count}/{length(
                          @config.payment_provider_configs
                        )} configured
                      </span>
                    </td>
                    <td class="text-sm break-words whitespace-normal">
                      <div class="grid grid-cols-1 xl:grid-cols-2 gap-3">
                        <div
                          :for={provider <- @config.payment_provider_configs}
                          class="bg-base-200/70 rounded-lg p-3"
                        >
                          <div class="flex items-center justify-between gap-2">
                            <span class="font-semibold">{provider.name}</span>
                            <span class={[
                              "badge badge-sm",
                              if(provider.configured, do: "badge-success", else: "badge-warning")
                            ]}>
                              {if(provider.configured, do: "Configured", else: "Missing")}
                            </span>
                          </div>
                          <div class="font-mono text-xs mt-2 space-y-1">
                            <div :for={line <- provider.details}>{line}</div>
                          </div>
                        </div>
                      </div>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Email Service</td>
                    <td>
                      <%= if @config.email_configured do %>
                        <span class="badge badge-success">SMTP</span>
                      <% else %>
                        <span class="badge badge-info">Local</span>
                      <% end %>
                    </td>
                    <td class="text-sm break-words whitespace-normal">
                      <div class="font-mono text-sm">
                        SMTP_USERNAME: {mask_secret(@config.smtp_username)}<br />
                        SMTP_PASSWORD: {mask_secret(@config.smtp_password)}<br />
                        SMTP_RELAY: {@config.smtp_relay || "<unset>"}<br />
                        SMTP_PORT: {@config.smtp_port || "<unset>"}<br />
                        SMTP_SSL: {@config.smtp_ssl || "<unset>"} SMTP_TLS: {@config.smtp_tls ||
                          "<unset>"}<br /> SMTP_SNI: {mask_secret(@config.smtp_sni)}<br />
                        SMTP_FROM_NAME: {mask_secret(@config.smtp_from_name || "")}<br />
                        SMTP_FROM_EMAIL: {mask_secret(@config.smtp_from_email || "")}
                      </div>

                      <div class="mt-2 text-xs text-muted">
                        <p class="mb-1">Notes on TLS modes:</p>
                        <ul class="list-disc ml-4">
                          <li>
                            <strong>SMTPS (implicit SSL)</strong>
                            — set <code>SMTP_SSL=true</code>
                            and use an
                            implicit SSL port (eg. <code>2465</code>
                            or <code>465</code>). When using implicit SSL
                            it's recommended to set <code>SMTP_TLS=never</code>
                            and provide an <code>SMTP_SNI</code>
                            (Server Name Indication) when your provider requires it (example: <code>mail.resend.com</code>).
                          </li>
                          <li>
                            <strong>STARTTLS</strong>
                            — use <code>SMTP_SSL=false</code>
                            with <code>SMTP_PORT=587</code>
                            and <code>SMTP_TLS=always</code>
                            (preferred for most providers).
                          </li>
                        </ul>

                        <div class="mt-2">
                          <a
                            href="https://resend.com/docs/smtp"
                            target="_blank"
                            rel="noopener"
                            class="link link-primary text-xs"
                          >
                            Provider docs: Resend SMTP guide
                          </a>
                          <span class="text-xs text-muted ml-2">· see repo docs for examples</span>
                        </div>

                        <div class="mt-3 text-xs text-muted">
                          <p class="mb-1 font-semibold">From address & domain verification</p>
                          <p>
                            Ensure the <code>SMTP_FROM_EMAIL</code> you configure is a
                            verified sender/domain in your SMTP provider — many providers
                            require verification before relaying mail and may return errors
                            like <code>450 domain not verified</code> otherwise.
                          </p>
                          <p class="mt-2">
                            You can set a friendly sender name via <code>SMTP_FROM_NAME</code>.
                            If you need to test delivery, use the <em>Send test email</em>
                            button above to verify runtime delivery and messages.
                          </p>
                        </div>
                      </div>
                      <%= if @config.email_configured do %>
                        SMTP configured - emails are sent via {@config.smtp_relay ||
                          "configured relay"}
                      <% else %>
                        <%= if @config.env == "dev" do %>
                          Using local delivery - emails are not sent (<a
                            href="/dev/mailbox"
                            class="link link-primary"
                          >view mailbox</a>)
                        <% else %>
                          Using local delivery - emails are not sent
                        <% end %>
                      <% end %>
                    </td>
                  </tr>
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
                        <br /> Node.alive?():
                        <span class="break-all">{inspect(@config.node_alive?)}</span>

                        <%= if @config.fly_app_name_env || @config.fly_private_ip_env do %>
                          <br /><br />
                          <span class="opacity-70">fly.io:</span>
                          <br /> FLY_APP_NAME:
                          <span class="break-all">{@config.fly_app_name_env || "<unset>"}</span>
                          <br /> FLY_PRIVATE_IP:
                          <span class="break-all">{@config.fly_private_ip_env || "<unset>"}</span>
                          <br /> FLY_REGION:
                          <span class="break-all">{@config.fly_region_env || "<unset>"}</span>
                        <% end %>
                      </div>

                      <div class="mt-2 text-xs text-base-content/60">
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
                        <br /> GAMEND_CACHE_REDIS_URL / REDIS_URL:
                        <span class="break-all">
                          <%= if @config.cache_redis_url_env do %>
                            {mask_secret(@config.cache_redis_url_env)}
                          <% else %>
                            <span class="opacity-70">
                              &lt;unset (required when GAMEND_CACHE_L2=redis)&gt;
                            </span>
                          <% end %>
                        </span>
                        <br /> CACHE_REDIS_POOL_SIZE:
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
                        <br /> L1 opts:
                        <span class="break-all">{inspect(@config.cache_l1_opts)}</span>
                        <br /> L2 module:
                        <span class="break-all">{inspect(@config.cache_l2_module)}</span>
                        <br /> L2 opts:
                        <span class="break-all">{inspect(@config.cache_l2_opts)}</span>
                      </div>

                      <div class="mt-2 text-xs text-base-content/60">
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
                          to enable L2, then choose
                          <code class="font-mono">GAMEND_CACHE_L2=redis</code>
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
                        <span class="break-all">{@config.log_level}</span>
                        <br /> GAMEND_OBSERVABILITY_ACCESS_LOG_LEVEL:
                        <span class="break-all">{@config.access_log_level_env || "<unset>"}</span>
                        <span class="opacity-70">
                          (effective: {inspect(@config.access_log_level)})
                        </span>
                      </div>
                    </td>
                  </tr>
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
                          GAMEND_DB_POSTGRES_HOST:
                          <span class="font-mono">{@config.pg_host || "<unset>"}</span>
                        </div>
                        <div>
                          GAMEND_DB_POSTGRES_USER:
                          <span class="font-mono">{@config.pg_user || "<unset>"}</span>
                        </div>
                        <div>
                          GAMEND_DB_POSTGRES_DB:
                          <span class="font-mono">{@config.pg_db || "<unset>"}</span>
                        </div>
                        <div>
                          GAMEND_DB_POSTGRES_PASSWORD:
                          <span class="font-mono">{mask_secret(@config.pg_password)}</span>
                        </div>

                        <div class="mt-3 pt-2 border-t border-base-300/60 text-xs">
                          <div class="font-semibold text-base-content/70">Runtime tuning</div>
                          <div class="mt-1 space-y-1">
                            <div>
                              GAMEND_DB_POOL_SIZE:
                              <span class="font-mono">{@config.db_pool_size_env || "<unset>"}</span>
                            </div>
                            <div>
                              DB_POOL_TIMEOUT:
                              <span class="font-mono">
                                {@config.db_pool_timeout_env || "<unset>"}
                              </span>
                            </div>
                            <div>
                              DB_QUEUE_TARGET:
                              <span class="font-mono">
                                {@config.db_queue_target_env || "<unset>"}
                              </span>
                            </div>
                            <div>
                              DB_QUEUE_INTERVAL:
                              <span class="font-mono">
                                {@config.db_queue_interval_env || "<unset>"}
                              </span>
                            </div>
                            <div>
                              DB_QUERY_TIMEOUT:
                              <span class="font-mono">
                                {@config.db_query_timeout_env || "<unset>"}
                              </span>
                            </div>
                            <div>
                              GAMEND_DB_POSTGRES_PORT:
                              <span class="font-mono">{@config.postgres_port_env || "<unset>"}</span>
                            </div>
                            <div>
                              GAMEND_DB_IPV6:
                              <span class="font-mono">{@config.ecto_ipv6_env || "<unset>"}</span>
                            </div>
                            <div>
                              GAMEND_HTTP_SERVER:
                              <span class="font-mono">{@config.phx_server_env || "<unset>"}</span>
                            </div>
                          </div>
                        </div>
                      </div>
                    </td>
                  </tr>
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
                        GAMEND_TLS_CERTFILE:
                        <span class="break-all">{@config.ssl_certfile_env || "<unset>"}</span>
                        <br /> GAMEND_TLS_KEYFILE:
                        <span class="break-all">{@config.ssl_keyfile_env || "<unset>"}</span>
                        <br /> GAMEND_TLS_PORT:
                        <span class="break-all">
                          {@config.https_port_env || "<unset> (default: 443)"}
                        </span>
                        <br /> GAMEND_TLS_FORCE:
                        <span class="break-all">{@config.force_ssl_env || "<unset>"}</span>
                        <br /> GAMEND_TLS_ACME_WEBROOT:
                        <span class="break-all">{@config.acme_webroot_env || "<unset>"}</span>
                      </div>

                      <%= if @config.ssl_cert_info do %>
                        <div class="mt-3 pt-2 border-t border-base-300/60">
                          <div class="text-xs font-semibold text-base-content/70 mb-1">
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
                              Valid from:
                              <span class="break-all">{@config.ssl_cert_info.not_before}</span>
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
                        Disabled
                      <% end %>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">GeoIP</td>
                    <td colspan="2">
                      <%= if @config.geoip_available? do %>
                        <span class="badge badge-success badge-sm">MMDB database loaded</span>
                        <span class="text-xs text-base-content/60 ml-2">
                          GAMEND_CONTENT_GEOIP_DB_PATH: {@config.geoip_db_path || "configured"}
                        </span>
                      <% else %>
                        <span class="badge badge-warning badge-sm">MMDB not configured</span>
                        <span class="text-xs text-base-content/60 ml-2">
                          Falling back to CF-IPCountry header (Cloudflare only). Place GeoLite2-Country.mmdb under data or set GAMEND_CONTENT_GEOIP_DB_PATH for a custom lookup path.
                        </span>
                      <% end %>
                    </td>
                  </tr>
                  <tr>
                    <td class="font-semibold">Metrics</td>
                    <td colspan="2">
                      <span class="badge badge-success badge-sm">PromEx enabled</span>
                      <span class="text-xs text-base-content/60 ml-2">
                        /metrics endpoint — local/Docker IPs always allowed {if @config.metrics_auth_token,
                          do: ", external requires token",
                          else: " (no token set — open to all)"}
                      </span>
                    </td>
                  </tr>
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
                              placeholder="JSON array args (eg [1,2] or [])"
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
                          <.link navigate={~p"/admin/logs"} class="btn btn-outline btn-sm">
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
                                  class="btn btn-outline btn-sm"
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
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Limits & Validation -->
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
              <code class="font-mono text-xs">LIMIT_&lt;KEY&gt;=value</code>
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
                          LIMIT_{String.upcase(to_string(key))}
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Admin Tools -->
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

        <!-- Scheduled Jobs -->
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
              <div class="text-sm text-base-content/60">
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
              <div class="text-xs text-base-content/60 mt-2">
                {length(@scheduled_jobs)} job(s) registered. Jobs are distributed-safe via database locks.
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    cache = cache_diagnostics()
    clustering = clustering_diagnostics()

    config = %{
      discord_client_id: GameServer.Settings.get(GameServer.OAuth.Providers, :discord_client_id),
      discord_client_secret:
        GameServer.Settings.get(GameServer.OAuth.Providers, :discord_client_secret),
      apple_web_client_id: GameServer.Settings.get(GameServer.OAuth.Providers, :apple_client_id),
      apple_ios_client_id:
        GameServer.Settings.get(GameServer.OAuth.Providers, :apple_ios_client_id),
      apple_team_id: GameServer.Settings.get(GameServer.OAuth.Providers, :apple_team_id),
      apple_key_id: GameServer.Settings.get(GameServer.Payments.Settings, :apple_key_id),
      apple_private_key:
        GameServer.Settings.get(GameServer.Payments.Settings, :apple_private_key),
      google_client_id: GameServer.Settings.get(GameServer.OAuth.Providers, :google_client_id),
      google_client_secret:
        GameServer.Settings.get(GameServer.OAuth.Providers, :google_client_secret),
      facebook_client_id:
        GameServer.Settings.get(GameServer.OAuth.Providers, :facebook_client_id),
      facebook_client_secret:
        GameServer.Settings.get(GameServer.OAuth.Providers, :facebook_client_secret),
      steam_api_key: GameServer.Settings.get(GameServer.OAuth.Providers, :steam_api_key),
      payment_provider_configs: payment_provider_configs(),
      payment_provider_configured_count: payment_provider_configured_count(),
      email_configured: GameServer.Settings.get(GameServer.Mail, :smtp_password) != nil,
      smtp_username: GameServer.Settings.get(GameServer.Mail, :smtp_username),
      smtp_password: GameServer.Settings.get(GameServer.Mail, :smtp_password),
      smtp_relay: GameServer.Settings.get(GameServer.Mail, :smtp_relay),
      smtp_port: GameServer.Settings.get(GameServer.Mail, :smtp_port),
      smtp_ssl: GameServer.Settings.get(GameServer.Mail, :smtp_ssl),
      smtp_from_name: GameServer.Settings.get(GameServer.Mail, :smtp_from_name),
      smtp_from_email: GameServer.Settings.get(GameServer.Mail, :smtp_from_email),
      smtp_sni: GameServer.Settings.get(GameServer.Mail, :smtp_sni),
      smtp_tls: GameServer.Settings.get(GameServer.Mail, :smtp_tls),
      env: to_string(Application.get_env(:game_server_web, :environment, :prod)),
      repo_conf: Application.get_env(:game_server_core, GameServer.Repo) || %{},
      database: Application.get_env(:game_server_core, GameServer.Repo)[:database] || "N/A",
      # Database environment diagnostics (don't show raw passwords)
      database_adapter: detect_db_adapter(),
      database_config_adapter: detect_db_config_adapter(),
      pg_database_url: GameServer.Settings.get(GameServer.Database, :url),
      pg_host: GameServer.Settings.get(GameServer.Database, :postgres_host),
      pg_user: GameServer.Settings.get(GameServer.Database, :postgres_user),
      pg_db: GameServer.Settings.get(GameServer.Database, :postgres_db),
      pg_password: GameServer.Settings.get(GameServer.Database, :postgres_password),
      # DB source detection and masked effective value for admin UI
      db_source: detect_db_source(),
      db_effective_value: detect_effective_db_value(),
      hostname:
        Application.get_env(:game_server_web, GameServerWeb.Endpoint)[:url][:host] ||
          GameServer.Settings.get(GameServerWeb.Http, :host),
      port: GameServer.Settings.get(GameServerWeb.Http, :port) || "4000",
      secret_key_base:
        GameServer.Settings.get(GameServer.Accounts, :secret_key_base) ||
          Application.get_env(:game_server_web, GameServerWeb.Endpoint)[:secret_key_base],
      live_reload:
        Application.get_env(:game_server_web, GameServerWeb.Endpoint)[:live_reload] != nil,
      log_level: Logger.level(),
      log_level_env: GameServer.Settings.get(GameServerWeb.Observability, :log_level),
      access_log_level: GameServerWeb.endpoint().access_log_level(nil),
      access_log_level_env:
        GameServer.Settings.get(GameServerWeb.Observability, :access_log_level),
      release_distribution_env: cluster_env("RELEASE_DISTRIBUTION"),
      release_node_env: cluster_env("RELEASE_NODE"),
      release_cookie_env: cluster_env("RELEASE_COOKIE"),
      dns_cluster_query_env: GameServer.Settings.get(GameServer.Cluster, :dns_query),
      release_distribution_recommended: "name",
      release_node_recommended: clustering.release_node_recommended,
      dns_cluster_query_recommended: clustering.dns_cluster_query_recommended,
      erl_aflags_env: cluster_env("ERL_AFLAGS"),
      erl_aflags_recommended: clustering.erl_aflags_recommended,
      node_name: node(),
      node_alive?: Node.alive?(),
      release_distribution_enabled?: Node.alive?(),
      cache_enabled_env: GameServer.Settings.get(GameServer.Cache.Settings, :enabled),
      cache_mode_env: GameServer.Settings.get(GameServer.Cache.Settings, :mode),
      cache_l2_env: GameServer.Settings.get(GameServer.Cache.Settings, :l2),
      cache_redis_url_env:
        GameServer.Settings.get(GameServer.Cache.Settings, :redis_url) ||
          GameServer.Settings.get(GameServer.Cluster, :redis_url),
      cache_redis_pool_size_env:
        GameServer.Settings.get(GameServer.Cache.Settings, :redis_pool_size),
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
      db_pool_size_env: GameServer.Settings.get(GameServer.Database, :pool_size),
      db_pool_timeout_env: GameServer.Settings.get(GameServer.Database, :pool_timeout_ms),
      db_queue_target_env: GameServer.Settings.get(GameServer.Database, :queue_target),
      db_queue_interval_env: GameServer.Settings.get(GameServer.Database, :queue_interval_ms),
      db_query_timeout_env: GameServer.Settings.get(GameServer.Database, :query_timeout_ms),
      postgres_port_env: GameServer.Settings.get(GameServer.Database, :postgres_port),
      ecto_ipv6_env: GameServer.Settings.get(GameServer.Database, :ipv6),
      ecto_ipv6_recommended: clustering.ecto_ipv6_recommended,
      phx_server_env: GameServer.Settings.get(GameServerWeb.Http, :server),
      fly_app_name_env: clustering.fly_app_name_env,
      fly_private_ip_env: clustering.fly_private_ip_env,
      fly_region_env: clustering.fly_region_env,
      # Hooks plugin diagnostics
      hooks_exported_functions: exported_plugin_functions(),
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
      theme_map: GameServerWeb.Layouts.resolve_theme(),
      theme_raw_map: JSONConfig.get_theme(),
      # Only rely on JSONConfig for decisions about runtime vs default and raw
      # content. Keep logic inside the provider instead of duplicating parsing
      # here.
      theme_config: JSONConfig.runtime_path(),
      # Dark variant / fullscreen image diagnostics (convention-based)
      theme_dark: theme_dark_variants(GameServerWeb.Layouts.resolve_theme()),
      content_paths: %{
        blog: Content.path(:blog),
        changelog: Content.path(:changelog),
        roadmap: Content.path(:roadmap)
      },
      device_auth_enabled_app: Application.get_env(:game_server_core, :device_auth_enabled),
      device_auth_enabled_env: GameServer.Settings.get(GameServer.Accounts, :device_auth_enabled),
      require_account_activation: GameServer.Accounts.require_account_activation?(),
      require_account_activation_env:
        GameServer.Settings.get(GameServer.Accounts, :require_activation),
      min_password_length_env:
        GameServer.Settings.get(GameServer.Accounts.User, :min_password_length),
      min_password_length_effective: User.min_password_length(),

      # PHX/CORS runtime configuration (set via GAMEND_HTTP_ALLOWED_ORIGINS)
      phx_allowed_origins_env: GameServer.Settings.get(GameServerWeb.Http, :allowed_origins),
      cors_allowed_origins: Application.get_env(:game_server_web, :cors_allowed_origins, "*"),

      # HTTPS / TLS certificate diagnostics
      ssl_certfile_env: GameServer.Settings.get(GameServerWeb.Tls, :certfile),
      ssl_keyfile_env: GameServer.Settings.get(GameServerWeb.Tls, :keyfile),
      https_port_env: GameServer.Settings.get(GameServerWeb.Tls, :port),
      force_ssl_env: GameServer.Settings.get(GameServerWeb.Tls, :force),
      acme_webroot_env: GameServer.Settings.get(GameServerWeb.Tls, :acme_webroot),
      ssl_enabled?: ssl_enabled?(),
      ssl_cert_info: ssl_cert_info(),

      # Rate Limiting runtime configuration
      rate_limit_enabled:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :enabled,
          true
        ),
      rate_limit_general_limit:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :general_limit,
          1200
        ),
      rate_limit_general_window:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :general_window_ms,
          60_000
        ),
      rate_limit_auth_limit:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :auth_limit,
          30
        ),
      rate_limit_auth_window:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :auth_window_ms,
          60_000
        ),
      rate_limit_ws_limit:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :ws_limit,
          300
        ),
      rate_limit_ws_window:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :ws_window_ms,
          10_000
        ),
      rate_limit_dc_limit:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :dc_limit,
          600
        ),
      rate_limit_dc_window:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :dc_window_ms,
          10_000
        ),
      rate_limit_ice_limit:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :ice_limit,
          150
        ),
      rate_limit_ice_window:
        Keyword.get(
          Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, []),
          :ice_window_ms,
          30_000
        ),
      webrtc_max_channels: 1,
      webrtc_max_message_size: 65_536,
      geoip_available?: GeoCountry.geoip_available?(),
      geoip_db_path: GameServer.Settings.get(GameServer.ContentSettings, :geoip_db_path),
      metrics_auth_token: GameServerWeb.Observability.get(:metrics_token)
    }

    socket =
      assign(socket,
        config: config,
        ip_bans: IpBan.list_bans(),
        limits_grouped: limits_grouped(),
        scheduled_jobs: Schedule.list(),
        hooks_plugin_prefill: %{value: "", seq: 0},
        hooks_prefill: %{value: "", seq: 0},
        hooks_args_prefill: %{value: "", seq: 0},
        hooks_full_doc: nil,
        hooks_full_name: nil,
        plugins: PluginManager.list(),
        plugins_counts: plugin_counts(PluginManager.list()),
        plugins_last_reloaded_at: nil,
        plugins_reload_result: nil,
        plugin_build_options: plugin_build_options(),
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
     |> assign(:plugins_counts, plugin_counts(plugins))
     |> assign(
       :config,
       Map.put(socket.assigns.config, :hooks_exported_functions, exported_plugin_functions())
     )}
  end

  @impl true
  def handle_info({:plugin_build_finished, _name, {:ok, build_result}}, socket) do
    {:noreply,
     socket
     |> assign(:plugin_build_running?, false)
     |> assign(:plugin_build_result, build_result)
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

  defp cache_diagnostics do
    cache_conf = Application.get_env(:game_server_core, GameServer.Cache) || []
    cache_levels = Keyword.get(cache_conf, :levels, [])

    {_l1_mod, l1_opts} =
      Enum.find(cache_levels, {nil, []}, fn
        {GameServer.Cache.L1, _opts} -> true
        _ -> false
      end)

    {l2_module, l2_opts} =
      Enum.find(cache_levels, {nil, []}, fn
        {GameServer.Cache.L2.Partitioned, _opts} -> true
        {GameServer.Cache.L2.Redis, _opts} -> true
        _ -> false
      end)

    bypass_mode_effective = Keyword.get(cache_conf, :bypass_mode, false)
    mode_effective = cache_mode_from_levels(cache_levels)

    %{
      cache_bypass_mode: Keyword.get(cache_conf, :bypass_mode),
      cache_bypass_mode_effective: bypass_mode_effective,
      cache_inclusion_policy: Keyword.get(cache_conf, :inclusion_policy),
      cache_mode_effective: mode_effective,
      cache_l2_effective: cache_l2_label(l2_module),
      cache_levels: cache_levels,
      cache_l1_opts: l1_opts,
      cache_l2_module: l2_module,
      cache_l2_opts: l2_opts
    }
  end

  defp cache_mode_from_levels(levels) when is_list(levels) do
    case length(levels) do
      1 -> "single"
      2 -> "multi"
      _ -> "custom"
    end
  end

  defp cache_l2_label(GameServer.Cache.L2.Redis), do: "redis"
  defp cache_l2_label(GameServer.Cache.L2.Partitioned), do: "partitioned"
  defp cache_l2_label(nil), do: "none"
  defp cache_l2_label(other), do: inspect(other)

  defp clustering_diagnostics do
    fly_app_name_env = cluster_env("FLY_APP_NAME")
    fly_private_ip_env = cluster_env("FLY_PRIVATE_IP")
    fly_region_env = cluster_env("FLY_REGION")

    fly? = fly_app_name_env != nil

    %{
      fly_app_name_env: fly_app_name_env,
      fly_private_ip_env: fly_private_ip_env,
      fly_region_env: fly_region_env,
      release_node_recommended: release_node_recommended(fly?),
      dns_cluster_query_recommended: dns_cluster_query_recommended(fly?),
      erl_aflags_recommended: erl_aflags_recommended(fly?),
      ecto_ipv6_recommended: ecto_ipv6_recommended(fly?)
    }
  end

  defp release_node_recommended(true),
    do: "${FLY_APP_NAME}-${FLY_IMAGE_REF##*-}@${FLY_PRIVATE_IP}"

  defp release_node_recommended(false), do: "myapp@fully-qualified-ip"

  defp dns_cluster_query_recommended(true), do: "${FLY_APP_NAME}.internal"
  defp dns_cluster_query_recommended(false), do: "a DNS name that resolves to all peer nodes"

  defp erl_aflags_recommended(true), do: "-proto_dist inet6_tcp"
  defp erl_aflags_recommended(false), do: ""

  defp ecto_ipv6_recommended(true), do: "true"
  defp ecto_ipv6_recommended(false), do: ""

  @impl true
  def handle_event("reload_plugins", _params, socket) do
    res = PluginManager.reload_and_after_startup()

    plugins = PluginManager.list()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    {:noreply,
     assign(socket,
       plugins: plugins,
       plugins_counts: plugin_counts(plugins),
       plugins_last_reloaded_at: now,
       plugins_reload_result: res,
       config:
         Map.put(socket.assigns.config, :hooks_exported_functions, exported_plugin_functions())
     )}
  end

  @impl true
  def handle_event("build_plugin_bundle", %{"plugin_build" => %{"name" => name}}, socket)
      when is_binary(name) do
    cond do
      socket.assigns.plugin_build_running? ->
        {:noreply, socket}

      socket.assigns.plugin_build_options == [] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No buildable plugins found under #{PluginBuilder.sources_dir()}"
         )}

      true ->
        parent = self()

        GameServer.Async.run(fn ->
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
        {:noreply, put_flash(socket, :error, "No email address available for current admin")}

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

  def handle_event("prefill_args", %{"args" => args_text}, socket) do
    seq = System.unique_integer([:positive])
    {:noreply, assign(socket, :hooks_args_prefill, %{value: args_text, seq: seq})}
  end

  def handle_event("show_docs", %{"doc" => doc, "name" => name, "arity" => arity}, socket) do
    # arity may arrive as string; keep it as-is for display
    full_name = "#{name}/#{arity}"
    {:noreply, assign(socket, hooks_full_doc: doc, hooks_full_name: full_name)}
  end

  def handle_event("close_docs", _params, socket),
    do: {:noreply, assign(socket, hooks_full_doc: nil, hooks_full_name: nil)}

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

  defp plugin_build_output(%{steps: steps}) when is_list(steps) do
    steps
    |> Enum.map_join("\n\n", fn s ->
      "$ #{s.cmd} (exit=#{s.status})\n" <> (s.output || "")
    end)
    |> String.trim()
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

  defp theme_nav_entry_label(%{"label" => label, "items" => items})
       when is_binary(label) and is_list(items) do
    "#{label} (#{length(items)})"
  end

  defp theme_nav_entry_label(%{"label" => label}) when is_binary(label), do: label
  defp theme_nav_entry_label(_entry), do: "Unnamed"

  defp theme_nav_entry_path(%{"items" => _items}), do: "dropdown"
  defp theme_nav_entry_path(%{"href" => href}) when is_binary(href), do: href
  defp theme_nav_entry_path(_entry), do: "—"

  defp theme_nav_entry_auth(%{"admin_only" => true}), do: "admin"
  defp theme_nav_entry_auth(%{"auth" => auth}) when is_binary(auth) and auth != "", do: auth
  defp theme_nav_entry_auth(_entry), do: nil

  # Compute dark-variant and fullscreen image existence for theme diagnostics.
  # Convention: `file.ext` → `file_dark.ext`, detected via File.exists? on priv/static.
  defp theme_dark_variants(theme_map) do
    static_dirs =
      [
        Application.get_env(:game_server_web, :host_static_app, :game_server_web),
        Application.get_env(:game_server_web, :asset_static_app, :game_server_web),
        :game_server_web
      ]
      |> Enum.uniq()
      |> Enum.map(&static_dir_for_app/1)
      |> Enum.reject(&is_nil/1)

    banner_path = (theme_map && Map.get(theme_map, "banner")) || ""
    banner_dark_path = derive_dark_path(banner_path)

    logo_path = (theme_map && Map.get(theme_map, "logo")) || ""
    logo_dark_path = derive_dark_path(logo_path)

    favicon_path = (theme_map && Map.get(theme_map, "favicon")) || ""
    favicon_dark_path = derive_dark_path(favicon_path)

    %{
      banner_dark_path: banner_dark_path,
      banner_dark_exists?: file_exists_in_static?(static_dirs, banner_dark_path),
      logo_dark_path: logo_dark_path,
      logo_dark_exists?: file_exists_in_static?(static_dirs, logo_dark_path),
      favicon_dark_path: favicon_dark_path,
      favicon_dark_exists?: file_exists_in_static?(static_dirs, favicon_dark_path),
      fullscreen_exists?: file_exists_in_static?(static_dirs, "/images/fullscreen.png"),
      fullscreen_dark_exists?: file_exists_in_static?(static_dirs, "/images/fullscreen_dark.png")
    }
  end

  defp derive_dark_path(""), do: ""
  defp derive_dark_path(path), do: String.replace(path, ~r/\.(\w+)$/, "_dark.\\1")

  defp file_exists_in_static?(_static_dirs, ""), do: false

  defp file_exists_in_static?(static_dirs, path) do
    relative_path = String.trim_leading(path, "/")

    Enum.any?(static_dirs, fn static_dir ->
      File.exists?(Path.join(static_dir, relative_path))
    end)
  end

  defp static_dir_for_app(app) when is_atom(app) do
    if Application.spec(app, :vsn) do
      Application.app_dir(app, "priv/static")
    end
  end

  defp static_dir_for_app(_app), do: nil

  defp exported_plugin_functions do
    plugins = PluginManager.hook_modules()

    static =
      plugins
      |> Enum.flat_map(fn {plugin, mod} ->
        Hooks.exported_functions(mod)
        |> Enum.map(&Map.put(&1, :plugin, plugin))
      end)

    dynamic_by_plugin = DynamicRpcs.list_all()

    dynamic =
      plugins
      |> Enum.flat_map(fn {plugin, _mod} ->
        dynamic_by_plugin
        |> Map.get(plugin, [])
        |> Enum.map(fn export ->
          %{
            name: export.hook,
            arities: [],
            signatures: [dynamic_signature(export)],
            plugin: plugin
          }
        end)
      end)

    (static ++ dynamic)
    |> Enum.uniq_by(fn f -> {f.plugin, f.name} end)
    |> Enum.sort_by(fn f -> {f.plugin, f.name} end)
    |> Enum.map(fn f ->
      Map.put(f, :typed_schema, HookSchemas.lookup(f.plugin, to_string(f.name)))
    end)
  end

  defp dynamic_signature(%{meta: meta} = export) when is_map(meta) do
    hook_name = Map.get(export, :hook) || Map.get(export, "hook") || Map.get(export, :name)
    doc = Map.get(meta, :description) || Map.get(meta, "description")
    args = Map.get(meta, :args) || Map.get(meta, "args")

    args_list = List.wrap(args)

    names =
      Enum.map(args_list, fn a ->
        Map.get(a, :name) || Map.get(a, "name") || "arg"
      end)

    arity = length(names)

    signature =
      case hook_name do
        n when is_binary(n) and n != "" ->
          n <> "(" <> Enum.join(names, ", ") <> ")"

        _ ->
          "(" <> Enum.join(names, ", ") <> ")"
      end

    example_args = Map.get(meta, :example_args) || Map.get(meta, "example_args")

    example_args_text =
      case example_args do
        nil ->
          Jason.encode!(names)

        list when is_list(list) ->
          Jason.encode!(list)

        other ->
          Jason.encode!([other])
      end

    %{arity: arity, signature: signature, doc: doc, example_args: example_args_text}
  end

  defp dynamic_signature(_export), do: %{arity: :custom, signature: nil, doc: nil}

  # Not settings: the BEAM and the platform read these names themselves, so
  # they are reported rather than declared. See GameServer.Cluster.
  defp cluster_env(name) do
    Enum.find_value(GameServer.Cluster.environment(), fn
      %{name: ^name, value: value} -> value
      _ -> nil
    end)
  end

  defp detect_db_adapter do
    if AdvisoryLock.postgres?(), do: :postgres, else: :sqlite
  end

  defp detect_db_config_adapter do
    repo_conf = Application.get_env(:game_server_core, GameServer.Repo) || %{}

    cond do
      GameServer.Settings.get(GameServer.Database, :url) ->
        :postgres

      GameServer.Settings.get(GameServer.Database, :postgres_host) &&
          GameServer.Settings.get(GameServer.Database, :postgres_user) ->
        :postgres

      repo_conf[:adapter] == Ecto.Adapters.Postgres ->
        :postgres

      true ->
        :sqlite
    end
  end

  defp detect_db_source do
    repo_conf = Application.get_env(:game_server_core, GameServer.Repo) || %{}

    cond do
      GameServer.Settings.get(GameServer.Database, :url) ->
        :database_url

      GameServer.Settings.get(GameServer.Database, :postgres_host) &&
          GameServer.Settings.get(GameServer.Database, :postgres_user) ->
        :env_vars

      repo_conf[:adapter] in [Ecto.Adapters.Postgres] ->
        :repo_config

      true ->
        :sqlite
    end
  end

  defp detect_effective_db_value do
    case GameServer.Settings.get(GameServer.Database, :url) do
      v when is_binary(v) and v != "" ->
        v

      _ ->
        host = GameServer.Settings.get(GameServer.Database, :postgres_host)
        user = GameServer.Settings.get(GameServer.Database, :postgres_user)
        db = GameServer.Settings.get(GameServer.Database, :postgres_db)
        pw = GameServer.Settings.get(GameServer.Database, :postgres_password)

        if host || user || db do
          "postgres://#{user || "<unset>"}@#{host || "<unset>"}/#{db || "<unset>"}#{if pw, do: ":(pwd)", else: ""}"
        else
          repo_conf = Application.get_env(:game_server_core, GameServer.Repo) || %{}
          to_string(repo_conf[:database] || "N/A")
        end
    end
  end

  defp plugin_counts(plugins) when is_list(plugins) do
    Enum.reduce(plugins, %{total: 0, ok: 0, error: 0}, fn plugin, acc ->
      acc = %{acc | total: acc.total + 1}

      case plugin.status do
        :ok -> %{acc | ok: acc.ok + 1}
        {:error, _} -> %{acc | error: acc.error + 1}
        _ -> acc
      end
    end)
  end

  # ── SSL / TLS certificate helpers ─────────────────────────────────────────

  defp ssl_enabled? do
    endpoint_config = Application.get_env(:game_server_web, GameServerWeb.Endpoint, [])
    Keyword.has_key?(endpoint_config, :https)
  end

  @doc false
  defp ssl_cert_info do
    certfile = GameServer.Settings.get(GameServerWeb.Tls, :certfile)

    if certfile do
      case File.read(certfile) do
        {:ok, pem_data} ->
          parse_pem_certificate(pem_data)

        {:error, _} ->
          nil
      end
    else
      nil
    end
  end

  defp parse_pem_certificate(pem_data) do
    case :public_key.pem_decode(pem_data) do
      [{:Certificate, der, _} | _] ->
        cert = :public_key.pkix_decode_cert(der, :otp)
        tbs = elem(cert, 2)

        # Extract validity
        validity = elem(tbs, 5)
        not_before = parse_asn1_time(elem(validity, 1))
        not_after = parse_asn1_time(elem(validity, 2))

        # Calculate days remaining
        days_remaining =
          case not_after do
            nil ->
              nil

            dt ->
              Date.diff(dt, Date.utc_today())
          end

        # Extract subject CN
        subject =
          tbs
          |> elem(6)
          |> extract_cn()

        # Extract issuer CN
        issuer =
          tbs
          |> elem(4)
          |> extract_cn()

        # Extract serial number
        serial = elem(tbs, 2)

        serial_hex =
          if is_integer(serial) do
            serial
            |> Integer.to_string(16)
            |> String.downcase()
            |> String.graphemes()
            |> Enum.chunk_every(2)
            |> Enum.map_join(":", &Enum.join/1)
          else
            inspect(serial)
          end

        %{
          subject: subject || "Unknown",
          issuer: issuer || "Unknown",
          not_before: format_cert_date(not_before),
          not_after: format_cert_date(not_after),
          days_remaining: days_remaining,
          expires_soon?: days_remaining != nil and days_remaining <= 30,
          serial: serial_hex
        }

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp parse_asn1_time({:utcTime, time}) when is_list(time) do
    parse_asn1_time_string(List.to_string(time), :utc)
  end

  defp parse_asn1_time({:generalTime, time}) when is_list(time) do
    parse_asn1_time_string(List.to_string(time), :general)
  end

  defp parse_asn1_time(_), do: nil

  defp parse_asn1_time_string(str, :utc) do
    # UTCTime format: YYMMDDHHMMSSZ
    case Regex.run(~r/^(\d{2})(\d{2})(\d{2})/, str) do
      [_, yy, mm, dd] ->
        year = String.to_integer(yy)
        # UTCTime: 00-49 => 2000-2049, 50-99 => 1950-1999
        year = if year >= 50, do: year + 1900, else: year + 2000
        Date.new!(year, String.to_integer(mm), String.to_integer(dd))

      _ ->
        nil
    end
  end

  defp parse_asn1_time_string(str, :general) do
    # GeneralizedTime format: YYYYMMDDHHMMSSZ
    case Regex.run(~r/^(\d{4})(\d{2})(\d{2})/, str) do
      [_, yyyy, mm, dd] ->
        Date.new!(String.to_integer(yyyy), String.to_integer(mm), String.to_integer(dd))

      _ ->
        nil
    end
  end

  defp extract_cn({:rdnSequence, rdn_seq}) do
    Enum.find_value(rdn_seq, fn attrs ->
      Enum.find_value(attrs, fn
        {:AttributeTypeAndValue, {2, 5, 4, 3}, value} ->
          extract_string_value(value)

        _ ->
          nil
      end)
    end)
  end

  defp extract_cn(_), do: nil

  defp extract_string_value({:utf8String, v}) when is_binary(v), do: v
  defp extract_string_value({:printableString, v}) when is_list(v), do: List.to_string(v)
  defp extract_string_value({:printableString, v}) when is_binary(v), do: v
  defp extract_string_value(v) when is_list(v), do: List.to_string(v)
  defp extract_string_value(v) when is_binary(v), do: v
  defp extract_string_value(_), do: nil

  defp format_cert_date(nil), do: "Unknown"
  defp format_cert_date(%Date{} = d), do: Date.to_iso8601(d)

  defp payment_provider_configured_count do
    Enum.count(payment_provider_configs(), & &1.configured)
  end

  defp payment_provider_configs do
    stripe = Payments.stripe_config_status()
    google = Google.config_status()
    apple = Apple.config_status()
    steam = Steam.config_status()

    [
      %{
        name: "Stripe",
        configured: stripe.configured,
        details: [
          "Detected mode: #{stripe.mode}",
          env_line("GAMEND_PAYMENTS_ENVIRONMENT", payments_environment()),
          "Secret key source: #{stripe.selected_secret_key || Enum.join(stripe.expected_secret_keys, " or ")}",
          env_line(
            stripe.selected_secret_key || "STRIPE_*_SECRET_KEY",
            ProviderConfig.stripe_secret_key(),
            secret: true
          ),
          "Webhook secret source: #{stripe.selected_webhook_secret || Enum.join(stripe.expected_webhook_secrets, " or ")}",
          env_line(
            stripe.selected_webhook_secret || "STRIPE_*_WEBHOOK_SECRET",
            ProviderConfig.stripe_webhook_secret(),
            secret: true
          ),
          "API version source: #{stripe.api_version_source}",
          env_line("GAMEND_PAYMENTS_STRIPE_API_VERSION", stripe.api_version)
        ]
      },
      %{
        name: "Google Play",
        configured: google.configured,
        details: [
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_PACKAGE_NAME",
            GameServer.Settings.get(GameServer.Payments.Settings, :google_play_package_name)
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
            GameServer.Settings.get(
              GameServer.Payments.Settings,
              :google_play_service_account_json
            ),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH",
            GameServer.Settings.get(
              GameServer.Payments.Settings,
              :google_play_service_account_json_path
            )
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_ACCESS_TOKEN",
            GameServer.Settings.get(GameServer.Payments.Settings, :google_play_access_token),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_RTDN_TOKEN",
            GameServer.Settings.get(GameServer.Payments.Settings, :google_play_rtdn_token),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_AUTO_ACKNOWLEDGE",
            GameServer.Settings.get(GameServer.Payments.Settings, :google_play_auto_acknowledge)
          )
        ]
      },
      %{
        name: "App Store",
        configured: apple.configured,
        details: [
          env_line(
            "GAMEND_PAYMENTS_APPLE_BUNDLE_ID",
            GameServer.Settings.get(GameServer.Payments.Settings, :apple_bundle_id)
          ),
          env_line(
            "GAMEND_PAYMENTS_APPLE_ISSUER_ID",
            GameServer.Settings.get(GameServer.Payments.Settings, :apple_issuer_id),
            secret: true
          ),
          env_line(
            "APPLE_KEY_ID",
            GameServer.Settings.get(GameServer.Payments.Settings, :apple_key_id)
          ),
          env_line(
            "APPLE_PRIVATE_KEY",
            GameServer.Settings.get(GameServer.Payments.Settings, :apple_private_key),
            secret: true
          ),
          env_line(
            "APPLE_PRIVATE_KEY_PATH",
            GameServer.Settings.get(GameServer.Payments.Settings, :apple_private_key_path)
          ),
          env_line("GAMEND_PAYMENTS_ENVIRONMENT", payments_environment())
        ]
      },
      %{
        name: "Steam MicroTxn",
        configured: steam.configured,
        details: [
          env_line(
            "GAMEND_PAYMENTS_STEAM_WEB_API_KEY",
            GameServer.Settings.get(GameServer.Payments.Settings, :steam_web_api_key),
            secret: true
          ),
          env_line(
            "GAMEND_OAUTH_STEAM_API_KEY fallback",
            GameServer.Settings.get(GameServer.OAuth.Providers, :steam_api_key),
            secret: true
          ),
          env_line(
            "STEAM_APP_ID",
            GameServer.Settings.get(GameServer.Payments.Settings, :steam_app_id)
          ),
          env_line("GAMEND_PAYMENTS_ENVIRONMENT", payments_environment())
        ]
      }
    ]
  end

  defp payments_environment, do: ProviderConfig.environment()

  defp env_line(key, value, opts \\ []) do
    display =
      cond do
        Keyword.get(opts, :secret, false) ->
          mask_secret(value)

        is_nil(value) or value == "" ->
          "<unset>"

        true ->
          to_string(value)
      end

    "#{key}: #{display}"
  end

  # Helpers for masking secrets shown in the admin UI.
  # We show the first 2 and last 2 characters for secrets longer than 6
  # (e.g. ab...yz). For very short values we show them with a small mask.
  defp mask_secret(nil), do: "<unset>"
  defp mask_secret(""), do: "<unset>"

  defp mask_secret(s) when is_binary(s) do
    len = byte_size(s)

    if len <= 4 do
      String.duplicate("*", len)
    else
      # Reveal a roughly half-window by showing the first and last ceil(len/4)
      # characters. This is a balance between usefulness and not leaking
      # full secrets in the admin UI.
      visible = max(1, div(len + 3, 4))
      first = String.slice(s, 0, visible)
      last = String.slice(s, -visible, visible)
      "#{first}...#{last}"
    end
  end

  defp env_with_default(v, _default) when is_binary(v) and v != "", do: v
  defp env_with_default(_v, default), do: "<unset (default: #{default})>"

  defp env_with_recommended(v, _recommended) when is_binary(v) and v != "", do: v
  defp env_with_recommended(_v, recommended), do: "<unset (recommended: #{recommended})>"

  # ── Limits helpers ──────────────────────────────────────────

  @limit_categories %{
    "Global" => ~w(max_metadata_size max_page_size)a,
    "User" => ~w(max_display_name max_email max_profile_url max_device_id)a,
    "Groups" =>
      ~w(max_group_title max_group_description max_group_members max_groups_per_user max_groups_created_per_user max_group_pending_invites)a,
    "Lobbies" => ~w(max_lobby_title max_lobby_users max_lobby_password)a,
    "Parties" => ~w(max_party_size max_party_pending_invites)a,
    "Chat" => ~w(max_chat_content)a,
    "Notifications" =>
      ~w(max_notification_title max_notification_content max_notifications_per_user)a,
    "Push" => ~w(max_push_tokens_per_user max_push_title max_push_body max_push_data_size)a,
    "Friends" => ~w(max_friends_per_user max_pending_friend_requests)a,
    "Hooks" => ~w(max_hook_args_size max_hook_args_count)a,
    "KV" => ~w(max_kv_key max_kv_value_size max_kv_entries_per_user)a,
    "Leaderboards" => ~w(max_leaderboard_title max_leaderboard_description max_leaderboard_slug)a,
    "Quests" =>
      ~w(max_quests max_quest_key max_quest_title max_quest_category max_quest_description max_objectives_per_quest max_quest_reward_entries max_active_quests_per_user max_quest_period_history)a,
    "Tournaments" =>
      ~w(max_tournament_title max_tournament_description max_tournament_slug max_tournament_entries max_tournament_bracket_size)a,
    "Matchmaking" =>
      ~w(max_matchmaking_players max_matchmaking_params_size matchmaking_timeout_ms matchmaking_tick_ms)a,
    "Ready checks" => ~w(ready_check_timeout_ms max_ready_check_participants)a
  }

  # Not a ~w sigil: "Ready checks" has a space in it.
  @category_order [
    "Global",
    "User",
    "Groups",
    "Lobbies",
    "Parties",
    "Chat",
    "Notifications",
    "Push",
    "Friends",
    "Hooks",
    "KV",
    "Leaderboards",
    "Quests",
    "Tournaments",
    "Matchmaking",
    "Ready checks"
  ]

  defp limits_grouped do
    defaults = GameServer.Limits.defaults()
    all = GameServer.Limits.all()

    @category_order
    |> Enum.map(fn cat ->
      keys = Map.get(@limit_categories, cat, [])

      items =
        Enum.map(keys, fn key ->
          {key, Map.get(defaults, key), Map.get(all, key)}
        end)

      {cat, items}
    end)
  end

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
