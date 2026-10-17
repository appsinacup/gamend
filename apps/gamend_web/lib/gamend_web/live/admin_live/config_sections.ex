defmodule GamendWeb.AdminLive.ConfigSections do
  @moduledoc """
  The sections of the admin configuration page, `GamendWeb.AdminLive.Config`,
  that describe the product: accounts, theme, sign-in providers, access
  control, payments and mail. The system sections — plugins, runtime, database,
  server, hooks and the cards below the table — are in
  `GamendWeb.AdminLive.ConfigSystemSections`.

  The page keeps the lifecycle and passes each section the assigns it reads;
  what the rows report is gathered by `GamendWeb.AdminLive.ConfigDiagnostics`.
  """
  use GamendWeb, :html

  import GamendWeb.AdminLive.ConfigDiagnostics, only: [mask_secret: 1, display_value: 1]

  @doc "Device login, account activation and the password policy."
  attr :config, :any, required: true

  def account_rows(assigns) do
    ~H"""
    <tr>
      <td class="font-semibold">Device auth</td>
      <td>
        <%= if @config.device_auth_enabled do %>
          <span class="badge badge-success">Enabled</span>
        <% else %>
          <span class="badge badge-error">Disabled</span>
        <% end %>
      </td>
      <td class="font-mono text-sm break-all whitespace-normal">
        GAMEND_AUTH_DEVICE_AUTH_ENABLED: {display_value(@config.device_auth_enabled_env)}
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
        GAMEND_AUTH_REQUIRE_ACTIVATION: {display_value(@config.require_account_activation_env)}
      </td>
    </tr>
    <tr>
      <td class="font-semibold">Password policy</td>
      <td>
        <%= if @config.min_password_length_set? do %>
          <span class="badge badge-success">Custom</span>
        <% else %>
          <span class="badge badge-ghost">Default</span>
        <% end %>
      </td>
      <td class="font-mono text-sm break-all whitespace-normal">
        GAMEND_AUTH_MIN_PASSWORD_LENGTH: {display_value(@config.min_password_length_env)}
        <br /> Effective: {@config.min_password_length_effective} characters
      </td>
    </tr>
    """
  end

  @doc "The theme config: branding images, hero, copy, navigation and footer."
  attr :config, :any, required: true

  def theme_row(assigns) do
    ~H"""
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
                <span class="text-xs opacity-70">
                  {Map.get(@config.theme_map, "logo")}
                </span>
              <% else %>
                <span class="text-xs opacity-70">—</span>
              <% end %>
              <%!-- Logo Dark --%>
              <%= if @config.theme_dark.logo_dark_exists? do %>
                <span class="text-xs font-semibold opacity-70 mt-1">
                  Dark
                </span>
                <img
                  src={@config.theme_dark.logo_dark_path}
                  alt="logo dark"
                  class="h-12 w-auto rounded bg-neutral p-1"
                />
                <span class="text-xs opacity-70">
                  {@config.theme_dark.logo_dark_path}
                </span>
              <% else %>
                <%= if Map.get(@config.theme_map, "logo") do %>
                  <span class="text-xs opacity-70 mt-1">
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
                <span class="text-xs opacity-70">
                  {Map.get(@config.theme_map, "favicon")}
                </span>
              <% else %>
                <span class="text-xs opacity-70">—</span>
              <% end %>
              <%!-- Favicon Dark --%>
              <%= if @config.theme_dark.favicon_dark_exists? do %>
                <span class="text-xs font-semibold opacity-70 mt-1">
                  Dark
                </span>
                <img
                  src={@config.theme_dark.favicon_dark_path}
                  alt="favicon dark"
                  class="h-8 w-auto bg-neutral p-0.5 rounded"
                />
                <span class="text-xs opacity-70">
                  {@config.theme_dark.favicon_dark_path}
                </span>
              <% else %>
                <%= if Map.get(@config.theme_map, "favicon") do %>
                  <span class="text-xs opacity-70 mt-1">
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
                <span class="text-xs opacity-70">
                  {Map.get(@config.theme_map, "banner")}
                </span>
              <% else %>
                <span class="text-xs opacity-70">—</span>
              <% end %>
              <%!-- Banner Dark --%>
              <%= if @config.theme_dark.banner_dark_exists? do %>
                <span class="text-xs font-semibold opacity-70 mt-1">
                  Dark
                </span>
                <img
                  src={@config.theme_dark.banner_dark_path}
                  alt="banner dark"
                  class="h-16 w-auto rounded shadow-sm bg-neutral p-1"
                />
                <span class="text-xs opacity-70">
                  {@config.theme_dark.banner_dark_path}
                </span>
              <% else %>
                <%= if Map.get(@config.theme_map, "banner") do %>
                  <span class="text-xs opacity-70 mt-1">
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
                <span class="text-xs font-semibold opacity-70">Light</span>
                <%= if @config.theme_dark.fullscreen_exists? do %>
                  <img
                    src="/images/fullscreen.png"
                    alt="fullscreen hero"
                    class="w-full max-w-[220px] h-auto rounded shadow-sm"
                  />
                  <span class="text-xs opacity-70">
                    /images/fullscreen.png
                  </span>
                <% else %>
                  <span class="text-xs opacity-70">
                    /images/fullscreen.png — not found
                  </span>
                <% end %>
              </div>
              <div class="flex flex-col items-center gap-1">
                <span class="text-xs font-semibold opacity-70">Dark</span>
                <%= if @config.theme_dark.fullscreen_dark_exists? do %>
                  <img
                    src="/images/fullscreen_dark.png"
                    alt="fullscreen hero dark"
                    class="w-full max-w-[220px] h-auto rounded shadow-sm bg-neutral p-1"
                  />
                  <span class="text-xs opacity-70">
                    /images/fullscreen_dark.png
                  </span>
                <% else %>
                  <span class="text-xs opacity-70">
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
                    <span class="text-xs opacity-70">
                      {Map.get(page, "path", "—")}
                    </span>
                    <span class="text-xs opacity-70">
                      ({ngettext("%{count} section", "%{count} sections", length(sections))})
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
                      <span class="text-xs opacity-70">
                        {theme_nav_entry_path(link)}
                      </span>
                      <%= if theme_nav_entry_auth(link) do %>
                        <span class="text-xs opacity-70">
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
                    <span class="text-xs opacity-70">
                      {ngettext(
                        "%{count} link",
                        "%{count} links",
                        length(Map.get(section, "links", []))
                      )}
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
    """
  end

  @doc "The sign-in providers."
  attr :config, :any, required: true

  def sign_in_rows(assigns) do
    ~H"""
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
          GAMEND_OAUTH_DISCORD_CLIENT_ID: {mask_secret(@config.discord_client_id)}<br />
          GAMEND_OAUTH_DISCORD_CLIENT_SECRET: {mask_secret(@config.discord_client_secret)}
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
          GAMEND_OAUTH_APPLE_CLIENT_ID: {mask_secret(@config.apple_web_client_id || "")}<br />
          GAMEND_OAUTH_APPLE_IOS_CLIENT_ID: {mask_secret(@config.apple_ios_client_id || "")}<br />
          GAMEND_OAUTH_APPLE_TEAM_ID: {mask_secret(@config.apple_team_id || "")}<br />
          GAMEND_OAUTH_APPLE_KEY_ID: {mask_secret(@config.apple_key_id || "")}<br />
          GAMEND_OAUTH_APPLE_PRIVATE_KEY: {mask_secret(@config.apple_private_key)}
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
          GAMEND_OAUTH_GOOGLE_CLIENT_ID: {mask_secret(@config.google_client_id)}<br />
          GAMEND_OAUTH_GOOGLE_CLIENT_SECRET: {mask_secret(@config.google_client_secret)}
        <% else %>
          <span class="text-error">Client ID missing</span>
        <% end %>
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
          GAMEND_OAUTH_FACEBOOK_CLIENT_ID: {mask_secret(@config.facebook_client_id)}<br />
          GAMEND_OAUTH_FACEBOOK_CLIENT_SECRET: {mask_secret(@config.facebook_client_secret)}
        <% else %>
          <span class="text-error">Client ID missing</span>
        <% end %>
      </td>
    </tr>
    <tr>
      <td class="font-semibold">GitHub OAuth</td>
      <td>
        <%= if @config.github_client_id && @config.github_client_secret do %>
          <span class="badge badge-success">Configured</span>
        <% else %>
          <span class="badge badge-error">Disabled</span>
        <% end %>
      </td>
      <td class="font-mono text-sm break-all whitespace-normal">
        <%= if @config.github_client_id do %>
          GAMEND_OAUTH_GITHUB_CLIENT_ID: {mask_secret(@config.github_client_id)}<br />
          GAMEND_OAUTH_GITHUB_CLIENT_SECRET: {mask_secret(@config.github_client_secret)}
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
    """
  end

  @doc "Who may reach the server: CORS, rate limiting and IP bans."
  attr :config, :any, required: true
  attr :ip_bans, :any, required: true

  def access_rows(assigns) do
    ~H"""
    <tr>
      <td class="font-semibold">CORS / Allowed Origins</td>
      <td>
        <%= if @config.phx_allowed_origins_set? do %>
          <span class="badge badge-success">Configured</span>
        <% else %>
          <span class="badge badge-ghost">Default</span>
        <% end %>
      </td>
      <td class="font-mono text-sm break-all whitespace-normal">
        GAMEND_HTTP_ALLOWED_ORIGINS: {if @config.phx_allowed_origins_set?,
          do: display_value(@config.phx_allowed_origins_env),
          else: "<unset>"}<br /> Effective CORS origins: {inspect(@config.cors_allowed_origins)}<br />
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
        <span class="text-xs text-muted">
          Set via GAMEND_RATELIMIT_* env vars
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
    """
  end

  @doc "The payment providers."
  attr :config, :any, required: true

  def payments_row(assigns) do
    ~H"""
    <tr>
      <td class="font-semibold">Payment Providers</td>
      <td>
        <span class="badge badge-info">
          {@config.payment_provider_configured_count}/{length(@config.payment_provider_configs)} configured
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
    """
  end

  @doc "Outgoing mail."
  attr :config, :any, required: true

  def email_row(assigns) do
    ~H"""
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
          GAMEND_MAIL_SMTP_USERNAME: {mask_secret(@config.smtp_username)}<br />
          GAMEND_MAIL_SMTP_PASSWORD: {mask_secret(@config.smtp_password)}<br />
          GAMEND_MAIL_SMTP_RELAY: {display_value(@config.smtp_relay)}<br />
          GAMEND_MAIL_SMTP_PORT: {display_value(@config.smtp_port)}<br />
          GAMEND_MAIL_SMTP_SSL: {display_value(@config.smtp_ssl)} GAMEND_MAIL_SMTP_TLS: {display_value(
            @config.smtp_tls
          )}<br /> GAMEND_MAIL_SMTP_SNI: {mask_secret(@config.smtp_sni)}<br />
          GAMEND_MAIL_SMTP_FROM_NAME: {mask_secret(@config.smtp_from_name || "")}<br />
          GAMEND_MAIL_SMTP_FROM_EMAIL: {mask_secret(@config.smtp_from_email || "")}
        </div>

        <div class="mt-2 text-xs text-muted">
          <p class="mb-1">Notes on TLS modes:</p>
          <ul class="list-disc ml-4">
            <li>
              <strong>SMTPS (implicit SSL)</strong>
              — set <code>GAMEND_MAIL_SMTP_SSL=true</code>
              and use an
              implicit SSL port (e.g. <code>2465</code>
              or <code>465</code>). When using implicit SSL
              it's recommended to set <code>GAMEND_MAIL_SMTP_TLS=never</code>
              and provide a <code>GAMEND_MAIL_SMTP_SNI</code>
              (Server Name Indication) when your provider requires it (example: <code>mail.resend.com</code>).
            </li>
            <li>
              <strong>STARTTLS</strong>
              — use <code>GAMEND_MAIL_SMTP_SSL=false</code>
              with <code>GAMEND_MAIL_SMTP_PORT=587</code>
              and <code>GAMEND_MAIL_SMTP_TLS=always</code>
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
              Ensure the <code>GAMEND_MAIL_SMTP_FROM_EMAIL</code> you configure is a
              verified sender/domain in your SMTP provider — many providers
              require verification before relaying mail and may return errors
              like <code>450 domain not verified</code> otherwise.
            </p>
            <p class="mt-2">
              You can set a friendly sender name via <code>GAMEND_MAIL_SMTP_FROM_NAME</code>.
              If you need to test delivery, use the <em>Send test email</em>
              button under Admin Tools below to verify runtime delivery and messages.
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
    """
  end

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
end
