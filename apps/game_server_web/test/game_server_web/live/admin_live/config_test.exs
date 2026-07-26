defmodule GameServerWeb.AdminLive.ConfigTest do
  # This test modifies global environment (plugins dir) and must not run
  # concurrently with other tests that depend on this state.
  use GameServerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias GameServer.Accounts.User
  alias GameServer.AccountsFixtures
  alias GameServer.Content
  alias GameServer.Hooks.PluginManager
  alias GameServer.Repo
  alias GameServer.Theme.JSONConfig

  test "renders config page with collapsible cards for admin", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    {:ok, user} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin/config")

    assert html =~ "Configuration"
    assert html =~ "data-action=\"toggle-card\""
    assert html =~ "data-card-key=\"config_status\""
    assert html =~ "GAMEND_CACHE_ENABLED"
    assert html =~ "GAMEND_OBSERVABILITY_ACCESS_LOG_LEVEL"
    # default collapsed state
    assert html =~ "collapsed"
    assert html =~ "aria-expanded=\"false\""
    # Database diagnostics should render (show adapter and diagnostic keys)
    assert html =~ "Database"
    assert html =~ "GAMEND_DB_POSTGRES_HOST" or html =~ "SQLite"
  end

  test "secrets are masked and DB adapter shows Postgres when env is set", %{conn: conn} do
    # Arrange - set env vars to predictable values and ensure cleanup after test
    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :discord_client_id,
      "discord12345"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :discord_client_secret,
      "disSecret9876"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :google_client_id,
      "go123456"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :google_client_secret,
      "goSecret987"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Accounts,
      :secret_key_base,
      "myverylongsecret_key_value_here"
    )

    GameServer.SettingsHelpers.put(:game_server_core, GameServer.Mail, :smtp_username, "smtpuser")
    GameServer.SettingsHelpers.put(:game_server_core, GameServer.Mail, :smtp_password, "smtppass")
    GameServer.SettingsHelpers.put(:game_server_core, GameServer.Mail, :smtp_port, 465)
    GameServer.SettingsHelpers.put(:game_server_core, GameServer.Mail, :smtp_ssl, true)
    GameServer.SettingsHelpers.put(:game_server_core, GameServer.Mail, :smtp_tls, true)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Mail,
      :smtp_from_name,
      "Game Server"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Mail,
      :smtp_from_email,
      "no-reply@example.com"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Mail,
      :smtp_sni,
      "mail.resend.com"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Database,
      :postgres_host,
      "localhost"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Database,
      :postgres_user,
      "postgres"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Database,
      :postgres_db,
      "game_server_test"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Database,
      :postgres_password,
      "pg_secret_very_long"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :stripe_sandbox_secret_key,
      "sk_test_config_123456"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :stripe_sandbox_webhook_secret,
      "whsec_config_123456"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :stripe_api_version,
      "2022-11-15"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :environment,
      :sandbox
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :google_play_package_name,
      "com.example.game"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :google_play_access_token,
      "google_play_access_token"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :apple_bundle_id,
      "com.example.game"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :apple_issuer_id,
      "apple_issuer_id"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :apple_key_id,
      "apple_key_id"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :apple_private_key,
      "apple_private_key_value"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.Payments.Settings,
      :steam_web_api_key,
      "steam_payment_key"
    )

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.OAuth.Providers,
      :steam_app_id,
      "480"
    )

    previous_settings =
      Map.new(
        [
          GameServer.Mail,
          GameServer.OAuth.Providers,
          GameServer.Payments.Settings,
          GameServer.Database,
          GameServer.Accounts,
          GameServerWeb.Observability
        ],
        &{&1, Application.get_env(:game_server_core, &1)}
      )

    on_exit(fn ->
      # Restore, not delete: these providers also hold values the rest of the
      # suite depends on (config/test.exs sets auth.secret_key_base, and a
      # missing required setting would fail validate!/1 for every later test).
      Enum.each(previous_settings, fn {module, value} ->
        if value,
          do: Application.put_env(:game_server_core, module, value),
          else: Application.delete_env(:game_server_core, module)
      end)
    end)

    {:ok, user} =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin/config")

    # verify postgres adapter detection
    assert html =~ "Postgres"

    # secrets should be masked according to the UI helper and present in the page
    mask = fn s ->
      if is_nil(s) or s == "" do
        "<unset>"
      else
        len = byte_size(s)

        if len <= 4 do
          String.duplicate("*", len)
        else
          n = max(1, div(len + 3, 4))
          first = String.slice(s, 0, n)
          last = String.slice(s, -n, n)
          "#{first}...#{last}"
        end
      end
    end

    assert html =~ mask.("discord12345")
    assert html =~ mask.("disSecret9876")
    assert html =~ mask.("go123456")
    assert html =~ mask.("goSecret987")
    assert html =~ mask.("myverylongsecret_key_value_here")
    assert html =~ mask.("smtppass")
    assert html =~ mask.("pg_secret_very_long")
    assert html =~ mask.("sk_test_config_123456")
    assert html =~ mask.("whsec_config_123456")
    assert html =~ mask.("google_play_access_token")
    assert html =~ mask.("apple_issuer_id")
    assert html =~ mask.("apple_private_key_value")
    assert html =~ mask.("steam_payment_key")

    # ensure secret env label presence
    assert html =~ "GAMEND_AUTH_SECRET_KEY_BASE"

    # ensure we've rendered env-var style labels for client config and hooks/device env names
    assert html =~ "DISCORD_CLIENT_ID"
    assert html =~ "GOOGLE_CLIENT_ID"
    assert html =~ "GAMEND_AUTH_DEVICE_AUTH_ENABLED"
    assert html =~ "Payment Providers"
    assert html =~ "GAMEND_PAYMENTS_STRIPE_SANDBOX_SECRET_KEY"
    assert html =~ "GAMEND_PAYMENTS_STRIPE_SANDBOX_WEBHOOK_SECRET"
    assert html =~ "STRIPE_API_VERSION"
    assert html =~ "2022-11-15"
    assert html =~ "GAMEND_PAYMENTS_GOOGLE_PLAY_PACKAGE_NAME"
    assert html =~ "GAMEND_PAYMENTS_APPLE_BUNDLE_ID"
    assert html =~ "GAMEND_PAYMENTS_STEAM_WEB_API_KEY"

    # SMTP env var label should be shown
    assert html =~ "SMTP_USERNAME"
    # when SMTP_PASSWORD is present the UI should indicate SMTP is configured
    assert html =~ "<span class=\"badge badge-success\">SMTP</span>"

    # SMTP port and SSL flags should be displayed
    assert html =~ "SMTP_PORT"
    assert html =~ "SMTP_SSL"
    # SMTP SNI (server name indication) should be displayed when present
    assert html =~ "SMTP_SNI"

    # From details should be displayed when configured
    assert html =~ mask.("Game Server")
    assert html =~ mask.("no-reply@example.com")

    # Admin UI should show guidance about verifying the From address/domain
    # The ampersand is escaped in HTML; look for the phrase "domain verification" instead
    assert html =~ "domain verification"

    # if no hooks watch interval set, these should not be visible
    refute html =~ "Watch interval (app): <unset>"
    refute html =~ "GAME_SERVER_HOOKS_WATCH_INTERVAL"
  end

  test "clicking function name pre-fills function and example args", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    {:ok, user} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    # Create a test-only OTP plugin and reload plugins so the Admin UI
    # can list exported functions.
    tmp = Path.join(System.tmp_dir!(), "gs-admin-plugin-#{System.unique_integer([:positive])}")
    plugin_root = Path.join(tmp, "modules/plugins")
    plugin_name = "admin_test_plugin"
    plugin_dir = Path.join(plugin_root, plugin_name)
    ebin_dir = Path.join(plugin_dir, "ebin")

    File.mkdir_p!(ebin_dir)

    hook_mod = Module.concat([GameServer, AdminConfigTestPluginHook])

    src = """
    defmodule #{inspect(hook_mod)} do
      @behaviour GameServer.Hooks

      def after_startup do
        [
          %{hook: "custom_hello"}
        ]
      end
      def before_stop, do: :ok

      def before_user_register(_user, attrs), do: {:ok, attrs}
      def after_user_register(_user), do: :ok
      def after_user_logged_in(_user), do: :ok
      def after_user_updated(_user), do: :ok
      def after_user_online(_user), do: :ok
      def after_user_offline(_user), do: :ok
      def before_user_update(_user, attrs), do: {:ok, attrs}
      def after_user_deleted(_user), do: :ok
      def after_score_submitted(_record), do: :ok
      def before_group_delete(group), do: {:ok, group}
      def before_group_kick(a, t, g), do: {:ok, {a, t, g}}
      def before_party_join(user, party), do: {:ok, {user, party}}
      def before_party_kick(target, leader, party), do: {:ok, {target, leader, party}}

      def before_lobby_create(attrs), do: {:ok, attrs}
      def after_lobby_create(_lobby), do: :ok
      def before_group_create(_user, attrs), do: {:ok, attrs}
      def after_group_create(_group), do: :ok
      def before_group_join(user, group, opts), do: {:ok, {user, group, opts}}
      def before_group_update(_group, attrs), do: {:ok, attrs}
      def after_group_updated(_group), do: :ok
      def before_lobby_join(user, lobby, opts), do: {:ok, {user, lobby, opts}}
      def before_chat_message(_user, attrs), do: {:ok, attrs}
      def after_chat_message(_message), do: :ok
      def after_lobby_join(_user, _lobby), do: :ok
      def before_lobby_leave(user, lobby), do: {:ok, {user, lobby}}
      def after_lobby_leave(_user, _lobby), do: :ok
      def before_lobby_update(_lobby, attrs), do: {:ok, attrs}
      def after_lobby_updated(_lobby), do: :ok
      def before_lobby_delete(lobby), do: {:ok, lobby}
      def after_lobby_deleted(_lobby), do: :ok
      def before_lobby_kick(host, target, lobby), do: {:ok, {host, target, lobby}}
      def after_lobby_kick(_host, _target, _lobby), do: :ok
      def after_lobby_host_change(_lobby, _new_host_id), do: :ok
      def after_group_join(_user_id, _group), do: :ok
      def after_group_leave(_user_id, _group_id), do: :ok
      def after_group_deleted(_group), do: :ok
      def after_group_kick(_admin_id, _target_id, _group_id), do: :ok
      def before_party_create(_user, attrs), do: {:ok, attrs}
      def after_party_create(_party), do: :ok
      def before_party_update(_party, attrs), do: {:ok, attrs}
      def after_party_updated(_party), do: :ok
      def after_party_join(_user, _party), do: :ok
      def after_party_leave(_user, _party_id), do: :ok
      def after_party_kick(_target, _leader, _party), do: :ok
      def after_party_disband(_party), do: :ok


      def before_kv_get(_key, _opts), do: :public

      def on_custom_hook("custom_hello", _args), do: "hello"
      def on_custom_hook(_hook, _args), do: {:error, :not_implemented}

      @doc "Say hi with two names"
      def hello2(name, name2), do: "Hello2, \#{name} \#{name2}!"

      @doc "Say hi to a user"
      def hello(name), do: "Hello, \#{name}!"
    end
    """

    [{^hook_mod, beam}] = Code.compile_string(src)

    File.write!(Path.join(ebin_dir, Atom.to_string(hook_mod) <> ".beam"), beam)

    app_term =
      {:application, String.to_atom(plugin_name),
       [
         {:description, ~c"admin test plugin"},
         {:vsn, ~c"0.1.0"},
         {:modules, [hook_mod]},
         {:registered, []},
         {:applications, [:kernel, :stdlib]},
         {:env, [hooks_module: to_charlist(Atom.to_string(hook_mod))]}
       ]}

    app_text = :io_lib.format(~c"~p.~n", [app_term]) |> IO.iodata_to_binary()
    File.write!(Path.join(ebin_dir, "#{plugin_name}.app"), app_text)

    orig_plugins_dir =
      GameServer.SettingsHelpers.get(:game_server_core, GameServer.ContentSettings, :plugins_dir)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :plugins_dir,
      plugin_root
    )

    _ = PluginManager.reload()

    on_exit(fn ->
      if orig_plugins_dir,
        do:
          GameServer.SettingsHelpers.put(
            :game_server_core,
            GameServer.ContentSettings,
            :plugins_dir,
            orig_plugins_dir
          ),
        else:
          GameServer.SettingsHelpers.delete(
            :game_server_core,
            GameServer.ContentSettings,
            :plugins_dir
          )

      _ = PluginManager.reload()
      File.rm_rf!(tmp)
    end)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin/config")

    # click the function name for hello2 (should auto-prefill args too)
    # trigger the phx-click on the span element and assert the inputs were updated
    # verify the element exists before clicking (avoid transient races)
    assert has_element?(
             lv,
             "span[phx-click='prefill_hook'][phx-value-plugin='#{plugin_name}'][phx-value-fn='hello2']"
           )

    hello2_el =
      element(
        lv,
        "span[phx-click='prefill_hook'][phx-value-plugin='#{plugin_name}'][phx-value-fn='hello2']"
      )

    html_after = render_click(hello2_el)

    # plugin input should contain plugin name
    assert html_after =~ "id=\"hooks-plugin-input\""
    assert html_after =~ "value=\"#{plugin_name}\""

    # function input should contain hello2
    assert html_after =~ "id=\"hooks-fn-input\""
    assert html_after =~ "value=\"hello2\""

    # args input should contain a generated example args JSON containing both parameter examples
    assert html_after =~ "id=\"hooks-args-input\""
    assert html_after =~ "name=\"args\""

    # Full docs may be unavailable depending on compiled BEAM metadata.
  end

  test "send test email button delivers a message and shows flash", %{conn: conn} do
    {:ok, user} =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin/config")

    # ensure the UI shows the test email button
    assert has_element?(lv, "button[phx-click='send_test_email']")

    # click and capture the updated HTML (flash present)
    html_after = render_click(element(lv, "button[phx-click='send_test_email']"))

    assert html_after =~ "Test email sent to #{user.email}"

    # Swoosh.Test adapter sends delivered emails to the current process
    assert_receive {:email, email}

    assert Enum.any?(email.to, fn {_name, addr} -> addr == user.email end)
  end

  test "renders theme diagnostics when GAMEND_CONTENT_THEME_CONFIG is set (env var)", %{
    conn: conn
  } do
    orig =
      GameServer.SettingsHelpers.get(:game_server_core, GameServer.ContentSettings, :theme_config)

    base = Path.join(System.tmp_dir!(), "theme_test_#{System.unique_integer([:positive])}.json")

    json =
      Jason.encode!(%{
        "title" => "Test Theme",
        "logo" => "/theme/test-logo.png",
        "banner" => "/theme/test-banner.png",
        "navigation" => %{
          "primary_links" => [
            %{
              "label" => "Social",
              "items" => [
                %{"label" => "Status", "href" => "/status"}
              ]
            }
          ],
          "account_links" => [
            %{"label" => "Billing", "href" => "/billing"}
          ]
        }
      })

    File.write!(base, json)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config,
      base
    )

    JSONConfig.reload()
    Content.reload()

    on_exit(fn ->
      if orig,
        do:
          GameServer.SettingsHelpers.put(
            :game_server_core,
            GameServer.ContentSettings,
            :theme_config,
            orig
          ),
        else:
          GameServer.SettingsHelpers.delete(
            :game_server_core,
            GameServer.ContentSettings,
            :theme_config
          )

      JSONConfig.reload()
      Content.reload()
      File.rm_rf(base)
    end)

    {:ok, user} =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin/config")

    assert html =~ "Theme"
    assert html =~ "GAMEND_CONTENT_THEME_CONFIG: #{base}"
    # raw JSON content should be present in the page
    assert html =~ "Test Theme"
    assert html =~ "Primary Nav"
    assert html =~ "Social"
    assert html =~ "/theme/test-logo.png"
    assert has_element?(lv, "#main-navbar a[href='/status']")
    assert has_element?(lv, "#main-navbar a[href='/billing']")
  end

  test "renders default theme diagnostics when GAMEND_CONTENT_THEME_CONFIG is unset", %{
    conn: conn
  } do
    # Ensure env var is unset so no theme is loaded
    orig =
      GameServer.SettingsHelpers.get(:game_server_core, GameServer.ContentSettings, :theme_config)

    GameServer.SettingsHelpers.delete(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config
    )

    JSONConfig.reload()
    Content.reload()

    on_exit(fn ->
      if orig,
        do:
          GameServer.SettingsHelpers.put(
            :game_server_core,
            GameServer.ContentSettings,
            :theme_config,
            orig
          ),
        else:
          GameServer.SettingsHelpers.delete(
            :game_server_core,
            GameServer.ContentSettings,
            :theme_config
          )

      JSONConfig.reload()
      Content.reload()
    end)

    {:ok, user} =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin/config")

    # When GAMEND_CONTENT_THEME_CONFIG is not present, the UI should show Disabled badge
    assert html =~ "<span class=\"badge badge-error\">Disabled</span>"
  end

  test "blank GAMEND_CONTENT_THEME_CONFIG is treated as unset and shows disabled badge", %{
    conn: conn
  } do
    orig =
      GameServer.SettingsHelpers.get(:game_server_core, GameServer.ContentSettings, :theme_config)

    GameServer.SettingsHelpers.put(
      :game_server_core,
      GameServer.ContentSettings,
      :theme_config,
      ""
    )

    JSONConfig.reload()
    Content.reload()

    on_exit(fn ->
      if orig,
        do:
          GameServer.SettingsHelpers.put(
            :game_server_core,
            GameServer.ContentSettings,
            :theme_config,
            orig
          ),
        else:
          GameServer.SettingsHelpers.delete(
            :game_server_core,
            GameServer.ContentSettings,
            :theme_config
          )

      JSONConfig.reload()
      Content.reload()
    end)

    {:ok, user} =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin/config")

    assert html =~ "GAMEND_CONTENT_THEME_CONFIG: &lt;unset&gt;"
    assert html =~ "<span class=\"badge badge-error\">Disabled</span>"
  end
end
