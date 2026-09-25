defmodule GamendWeb.AdminLive.ConfigDiagnostics do
  @moduledoc """
  What the admin configuration page reports, gathered once at mount: cache and
  clustering state, the database, TLS certificate, payment providers, plugins,
  theme assets and limits.

  Kept apart from `GamendWeb.AdminLive.Config`, which owns the page's lifecycle,
  and `GamendWeb.AdminLive.ConfigSections`, which renders it.
  """

  alias Gamend.Hooks
  alias Gamend.Hooks.DynamicRpcs
  alias Gamend.Hooks.HookSchemas
  alias Gamend.Hooks.PluginManager
  alias Gamend.Payments
  alias Gamend.Payments.ProviderConfig
  alias Gamend.Payments.Providers.Apple
  alias Gamend.Payments.Providers.Google
  alias Gamend.Payments.Providers.Steam
  alias Gamend.Repo.AdvisoryLock

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
      ~w(max_matchmaking_players matchmaking_default_min_players matchmaking_default_max_players max_matchmaking_params_size matchmaking_timeout_ms matchmaking_tick_ms)a,
    "Ready checks" => ~w(ready_check_timeout_ms max_ready_check_participants)a
  }

  # Not a ~w sigil: "Ready checks" has a space in it.

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

  def cache_diagnostics do
    cache_conf = Application.get_env(:gamend_core, Gamend.Cache) || []
    cache_levels = Keyword.get(cache_conf, :levels, [])

    {_l1_mod, l1_opts} =
      Enum.find(cache_levels, {nil, []}, fn
        {Gamend.Cache.L1, _opts} -> true
        _ -> false
      end)

    {l2_module, l2_opts} =
      Enum.find(cache_levels, {nil, []}, fn
        {Gamend.Cache.L2.Partitioned, _opts} -> true
        {Gamend.Cache.L2.Redis, _opts} -> true
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

  defp cache_l2_label(Gamend.Cache.L2.Redis), do: "redis"
  defp cache_l2_label(Gamend.Cache.L2.Partitioned), do: "partitioned"
  defp cache_l2_label(nil), do: "none"
  defp cache_l2_label(other), do: inspect(other)

  def clustering_diagnostics do
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

  # Compute dark-variant and fullscreen image existence for theme diagnostics.
  # Convention: `file.ext` → `file_dark.ext`, detected via File.exists? on priv/static.
  def theme_dark_variants(theme_map) do
    static_dirs =
      [
        Application.get_env(:gamend_web, :host_static_app, :gamend_web),
        Application.get_env(:gamend_web, :asset_static_app, :gamend_web),
        :gamend_web
      ]
      |> Enum.uniq()
      |> Enum.map(&static_dir_for_app/1)
      |> Enum.reject(&is_nil/1)

    banner_path = (theme_map && Map.get(theme_map, "banner")) || ""
    banner_dark_path = derive_dark_path(banner_path)

    logo_path = (theme_map && Map.get(theme_map, "logo")) || ""
    # The theme names its dark mark when the light one's name does not
    # follow the `_dark` convention; the derived path is the fallback.
    logo_dark_path = (theme_map && Map.get(theme_map, "logo_dark")) || derive_dark_path(logo_path)

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

  def exported_plugin_functions do
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
  # they are reported rather than declared. See Gamend.Cluster.
  def cluster_env(name) do
    Enum.find_value(Gamend.Cluster.environment(), fn
      %{name: ^name, value: value} -> value
      _ -> nil
    end)
  end

  def detect_db_adapter do
    if AdvisoryLock.postgres?(), do: :postgres, else: :sqlite
  end

  def detect_db_config_adapter do
    repo_conf = Application.get_env(:gamend_core, Gamend.Repo) || %{}

    cond do
      Gamend.Settings.get(Gamend.Database, :url) ->
        :postgres

      Gamend.Settings.get(Gamend.Database, :postgres_host) &&
          Gamend.Settings.get(Gamend.Database, :postgres_user) ->
        :postgres

      repo_conf[:adapter] == Ecto.Adapters.Postgres ->
        :postgres

      true ->
        :sqlite
    end
  end

  def detect_db_source do
    repo_conf = Application.get_env(:gamend_core, Gamend.Repo) || %{}

    cond do
      Gamend.Settings.get(Gamend.Database, :url) ->
        :database_url

      Gamend.Settings.get(Gamend.Database, :postgres_host) &&
          Gamend.Settings.get(Gamend.Database, :postgres_user) ->
        :env_vars

      repo_conf[:adapter] in [Ecto.Adapters.Postgres] ->
        :repo_config

      true ->
        :sqlite
    end
  end

  def detect_effective_db_value do
    case Gamend.Settings.get(Gamend.Database, :url) do
      v when is_binary(v) and v != "" ->
        v

      _ ->
        host = Gamend.Settings.get(Gamend.Database, :postgres_host)
        user = Gamend.Settings.get(Gamend.Database, :postgres_user)
        db = Gamend.Settings.get(Gamend.Database, :postgres_db)
        pw = Gamend.Settings.get(Gamend.Database, :postgres_password)

        if host || user || db do
          "postgres://#{user || "<unset>"}@#{host || "<unset>"}/#{db || "<unset>"}#{if pw, do: ":(pwd)", else: ""}"
        else
          repo_conf = Application.get_env(:gamend_core, Gamend.Repo) || %{}
          to_string(repo_conf[:database] || "N/A")
        end
    end
  end

  def plugin_counts(plugins) when is_list(plugins) do
    Enum.reduce(plugins, %{total: 0, ok: 0, error: 0}, fn plugin, acc ->
      acc = %{acc | total: acc.total + 1}

      case plugin.status do
        :ok -> %{acc | ok: acc.ok + 1}
        {:error, _} -> %{acc | error: acc.error + 1}
        _ -> acc
      end
    end)
  end

  def ssl_enabled? do
    endpoint_config = Application.get_env(:gamend_web, GamendWeb.Endpoint, [])
    Keyword.has_key?(endpoint_config, :https)
  end

  @doc false
  def ssl_cert_info do
    certfile = Gamend.Settings.get(GamendWeb.Tls, :certfile)

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
        # `{:OTPCertificate, tbs, signature_algorithm, signature}`. This read
        # `elem(cert, 2)` -- the signature algorithm -- so every field below
        # raised, the rescue answered nil, and the page never showed a
        # certificate.
        {:OTPCertificate, tbs, _signature_algorithm, _signature} =
          :public_key.pkix_decode_cert(der, :otp)

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
            hex = serial |> Integer.to_string(16) |> String.downcase()
            # An odd digit count paired the bytes wrong: 0x3ff read "3f:f".
            hex = if rem(byte_size(hex), 2) == 1, do: "0" <> hex, else: hex

            hex
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

  # UTCTime is YYMMDDHHMMSSZ, where 50-99 means 1950-1999 and 00-49 means
  # 2000-2049; GeneralizedTime is YYYYMMDDHHMMSSZ. Only the date is kept.
  defp parse_asn1_time_string(<<yy::binary-size(2), rest::binary>>, :utc) do
    case Gamend.Parse.integer(yy) do
      year when is_integer(year) and year >= 50 -> asn1_date(1900 + year, rest)
      year when is_integer(year) -> asn1_date(2000 + year, rest)
      nil -> nil
    end
  end

  defp parse_asn1_time_string(<<yyyy::binary-size(4), rest::binary>>, :general) do
    case Gamend.Parse.integer(yyyy) do
      year when is_integer(year) -> asn1_date(year, rest)
      nil -> nil
    end
  end

  defp parse_asn1_time_string(_str, _kind), do: nil

  defp asn1_date(year, <<mm::binary-size(2), dd::binary-size(2), _time::binary>>) do
    with month when is_integer(month) <- Gamend.Parse.integer(mm),
         day when is_integer(day) <- Gamend.Parse.integer(dd),
         {:ok, date} <- Date.new(year, month, day) do
      date
    else
      _ -> nil
    end
  end

  defp asn1_date(_year, _rest), do: nil

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

  def payment_provider_configured_count do
    Enum.count(payment_provider_configs(), & &1.configured)
  end

  def payment_provider_configs do
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
            stripe.selected_secret_key || "GAMEND_PAYMENTS_STRIPE_*_SECRET_KEY",
            ProviderConfig.stripe_secret_key(),
            secret: true
          ),
          "Webhook secret source: #{stripe.selected_webhook_secret || Enum.join(stripe.expected_webhook_secrets, " or ")}",
          env_line(
            stripe.selected_webhook_secret || "GAMEND_PAYMENTS_STRIPE_*_WEBHOOK_SECRET",
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
            Gamend.Settings.get(Gamend.Payments.Settings, :google_play_package_name)
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
            Gamend.Settings.get(
              Gamend.Payments.Settings,
              :google_play_service_account_json
            ),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH",
            Gamend.Settings.get(
              Gamend.Payments.Settings,
              :google_play_service_account_json_path
            )
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_ACCESS_TOKEN",
            Gamend.Settings.get(Gamend.Payments.Settings, :google_play_access_token),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_RTDN_TOKEN",
            Gamend.Settings.get(Gamend.Payments.Settings, :google_play_rtdn_token),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_GOOGLE_PLAY_AUTO_ACKNOWLEDGE",
            Gamend.Settings.get(Gamend.Payments.Settings, :google_play_auto_acknowledge)
          )
        ]
      },
      %{
        name: "App Store",
        configured: apple.configured,
        details: [
          env_line(
            "GAMEND_PAYMENTS_APPLE_BUNDLE_ID",
            Gamend.Settings.get(Gamend.Payments.Settings, :apple_bundle_id)
          ),
          env_line(
            "GAMEND_PAYMENTS_APPLE_ISSUER_ID",
            Gamend.Settings.get(Gamend.Payments.Settings, :apple_issuer_id),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_APPLE_KEY_ID",
            Gamend.Settings.get(Gamend.Payments.Settings, :apple_key_id)
          ),
          env_line(
            "GAMEND_PAYMENTS_APPLE_PRIVATE_KEY",
            Gamend.Settings.get(Gamend.Payments.Settings, :apple_private_key),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_APPLE_PRIVATE_KEY_PATH",
            Gamend.Settings.get(Gamend.Payments.Settings, :apple_private_key_path)
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
            Gamend.Settings.get(Gamend.Payments.Settings, :steam_web_api_key),
            secret: true
          ),
          env_line(
            "GAMEND_OAUTH_STEAM_API_KEY fallback",
            Gamend.Settings.get(Gamend.OAuth.Providers, :steam_api_key),
            secret: true
          ),
          env_line(
            "GAMEND_PAYMENTS_STEAM_APP_ID",
            Gamend.Settings.get(Gamend.Payments.Settings, :steam_app_id)
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
  # A fixed-width mask, plus the last four characters once the value is long
  # enough for four to be a small fraction of it.
  #
  # This used to show the first and last `ceil(len/4)` characters — about half
  # of the value, contiguous at both ends. For a 64-character `secret_key_base`
  # that is 32 characters; for a 16-character SMTP password it left 8 to guess;
  # and it masked `RELEASE_COOKIE`, the BEAM distribution credential, the same
  # way. Recognising a value needs a handful of characters, not half of it.
  # Matches `GamendWeb.AdminLive.Settings`, which already did this.
  def mask_secret(nil), do: "<unset>"
  def mask_secret(""), do: "<unset>"

  def mask_secret(s) when is_binary(s) do
    if byte_size(s) <= 12 do
      "••••••••"
    else
      "••••••••" <> String.slice(s, -4, 4)
    end
  end

  @doc """
  Whether the host set a declared setting — in its config or through the env
  var — rather than leaving the default.

  `Gamend.Settings.get/2` answers the default for an unset key, so a badge that
  tests its result for truthiness says "configured" for every setting that has
  a default.
  """
  def setting_set?(module, key) do
    case Enum.find(module.__settings__(), &(&1.key == key)) do
      nil -> false
      definition -> Gamend.Settings.describe(definition).source == :config
    end
  end

  @doc "A declared setting's value when the host set one, otherwise nil."
  def setting_if_set(module, key) do
    if setting_set?(module, key), do: Gamend.Settings.get(module, key)
  end

  @doc """
  A setting value as the config page prints it. Only nil and "" are unset:
  `value || "<unset>"` printed `false` as unset, and HEEx cannot render an atom
  or integer the way it renders a string.
  """
  def display_value(nil), do: "<unset>"
  def display_value(""), do: "<unset>"
  def display_value(value) when is_binary(value), do: value
  def display_value(value) when is_atom(value) or is_number(value), do: to_string(value)
  def display_value(value), do: inspect(value)

  def limits_grouped do
    defaults = Gamend.Limits.defaults()
    all = Gamend.Limits.all()

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
end
