defmodule GamendWeb.AdminLive.ServiceDiagnostics do
  @moduledoc """
  What the Services section of `/admin/system` reports, gathered once at mount:
  the state a setting's value cannot show on its own. The adapter this build
  was compiled with, the cache levels in force, whether the node joined a
  cluster and the variables the BEAM reads for that, the TLS certificate on
  disk. The values themselves are on `/admin/settings`.
  """

  alias Gamend.Repo.AdvisoryLock

  @none "none"

  @doc "Everything the section shows."
  @spec services() :: map()
  def services do
    %{
      environment: to_string(Application.get_env(:gamend_web, :environment, :prod)),
      database: %{
        adapter: detect_db_adapter(),
        configured_adapter: detect_db_config_adapter(),
        source: detect_db_source()
      },
      cache: cache_diagnostics(),
      cluster: cluster(),
      tls: %{
        enabled?: ssl_enabled?(),
        certfile: Gamend.Settings.get(GamendWeb.Tls, :certfile),
        certificate: ssl_cert_info()
      },
      mail: %{
        smtp?: Gamend.Settings.get(Gamend.Mail, :smtp_password) != nil,
        relay: Gamend.Settings.get(Gamend.Mail, :smtp_relay)
      }
    }
  end

  # The opts of each level are left out on purpose: Redis's hold its connection
  # options, password included.
  defp cache_diagnostics do
    cache_conf = Application.get_env(:gamend_core, Gamend.Cache) || []
    levels = Keyword.get(cache_conf, :levels, [])

    l2 =
      Enum.find_value(levels, fn
        {Gamend.Cache.L2.Partitioned, _opts} -> Gamend.Cache.L2.Partitioned
        {Gamend.Cache.L2.Redis, _opts} -> Gamend.Cache.L2.Redis
        _level -> nil
      end)

    %{
      enabled?: not Keyword.get(cache_conf, :bypass_mode, false),
      mode: cache_mode_from_levels(levels),
      l2: cache_l2_label(l2),
      inclusion_policy: Keyword.get(cache_conf, :inclusion_policy)
    }
  end

  defp cluster do
    fly_app = cluster_env("FLY_APP_NAME")
    fly? = fly_app != nil

    %{
      enabled?: Node.alive?(),
      node: node(),
      variables: [
        {"RELEASE_DISTRIBUTION", recommended(cluster_env("RELEASE_DISTRIBUTION"), "name")},
        {"RELEASE_NODE",
         recommended(cluster_env("RELEASE_NODE"), release_node_recommended(fly?))},
        {"RELEASE_COOKIE", mask_secret(cluster_env("RELEASE_COOKIE"))},
        {"GAMEND_CLUSTER_DNS_QUERY",
         recommended(
           Gamend.Settings.get(Gamend.Cluster, :dns_query),
           dns_cluster_query_recommended(fly?)
         )},
        {"ERL_AFLAGS", recommended(cluster_env("ERL_AFLAGS"), erl_aflags_recommended(fly?))},
        {"GAMEND_DB_IPV6",
         recommended(setting_if_set(Gamend.Database, :ipv6), ecto_ipv6_recommended(fly?))}
      ],
      fly:
        if fly? do
          [
            {"FLY_APP_NAME", fly_app},
            {"FLY_PRIVATE_IP", cluster_env("FLY_PRIVATE_IP") || "<unset>"},
            {"FLY_REGION", cluster_env("FLY_REGION") || "<unset>"}
          ]
        else
          []
        end
    }
  end

  # Off Fly there is no recommendation for some of these; "(recommended: )"
  # read like a missing value.
  defp recommended(value, recommended) when value in [nil, ""] and recommended in [nil, ""],
    do: "<unset>"

  defp recommended(value, recommended) when value in [nil, ""],
    do: "<unset (recommended: #{recommended})>"

  defp recommended(value, _recommended) when is_binary(value), do: value

  defp recommended(value, _recommended) when is_atom(value) or is_number(value),
    do: to_string(value)

  defp recommended(value, _recommended), do: inspect(value)

  defp cache_mode_from_levels(levels) when is_list(levels) do
    case length(levels) do
      1 -> "single"
      2 -> "multi"
      _ -> "custom"
    end
  end

  defp cache_l2_label(Gamend.Cache.L2.Redis), do: "redis"
  defp cache_l2_label(Gamend.Cache.L2.Partitioned), do: "partitioned"
  defp cache_l2_label(nil), do: @none
  defp cache_l2_label(other), do: inspect(other)

  defp release_node_recommended(true),
    do: "${FLY_APP_NAME}-${FLY_IMAGE_REF##*-}@${FLY_PRIVATE_IP}"

  defp release_node_recommended(false), do: "myapp@fully-qualified-ip"

  defp dns_cluster_query_recommended(true), do: "${FLY_APP_NAME}.internal"
  defp dns_cluster_query_recommended(false), do: "a DNS name that resolves to all peer nodes"

  defp erl_aflags_recommended(true), do: "-proto_dist inet6_tcp"
  defp erl_aflags_recommended(false), do: ""

  defp ecto_ipv6_recommended(true), do: "true"
  defp ecto_ipv6_recommended(false), do: ""

  # Not settings: the BEAM and the platform read these names themselves, so
  # they are reported rather than declared. See Gamend.Cluster.
  defp cluster_env(name) do
    Enum.find_value(Gamend.Cluster.environment(), fn
      %{name: ^name, value: value} -> value
      _ -> nil
    end)
  end

  defp detect_db_adapter do
    if AdvisoryLock.postgres?(), do: :postgres, else: :sqlite
  end

  defp detect_db_config_adapter do
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

  defp detect_db_source do
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

  defp ssl_enabled? do
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

  # A declared setting's value when the host set one, otherwise nil:
  # `Gamend.Settings.get/2` answers the default for an unset key.
  defp setting_if_set(module, key) do
    with %{} = definition <- Enum.find(module.__settings__(), &(&1.key == key)),
         %{source: :config, value: value} <- Gamend.Settings.describe(definition) do
      value
    else
      _unset -> nil
    end
  end
end
