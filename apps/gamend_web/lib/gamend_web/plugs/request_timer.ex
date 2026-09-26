defmodule GamendWeb.Plugs.RequestTimer do
  @moduledoc """
  A plug that logs the total request duration at the end of the request.
  This runs before the Router and captures the entire pipeline duration.

  The `x-request-time` response header is only included in non-production
  environments to avoid leaking server timing information to attackers.
  """
  import Plug.Conn
  require Logger

  @default_slow_request_threshold_ms 200.0
  @max_param_depth 4
  @max_param_items 20
  @max_string_bytes 300
  @redacted "[FILTERED]"

  def init(opts), do: opts

  def call(conn, _opts) do
    start_time = System.monotonic_time()

    register_before_send(conn, fn conn ->
      end_time = System.monotonic_time()
      duration_us = System.convert_time_unit(end_time - start_time, :native, :microsecond)
      duration_ms = duration_us / 1000

      if duration_ms > slow_request_threshold_ms() do
        Logger.warning(
          "Slow Request: #{conn.method} #{conn.request_path}#{request_params(conn)} took #{format_duration_ms(duration_ms)}ms"
        )
      end

      if expose_header?() do
        put_resp_header(conn, "x-request-time", "#{duration_ms}ms")
      else
        conn
      end
    end)
  end

  defp request_params(conn) do
    [
      {"query", fetched_params(conn.query_params)},
      {"body", fetched_params(conn.body_params)}
    ]
    |> Enum.flat_map(fn
      {_label, params} when params in [%{}, nil] ->
        []

      {label, params} ->
        ["#{label}=#{inspect(sanitize_param(params, @max_param_depth))}"]
    end)
    |> case do
      [] -> ""
      parts -> " " <> Enum.join(parts, " ")
    end
  end

  defp fetched_params(%Plug.Conn.Unfetched{}), do: %{}
  defp fetched_params(params) when is_map(params), do: params
  defp fetched_params(_params), do: %{}

  defp sanitize_param(_value, depth) when depth <= 0, do: "..."
  defp sanitize_param(%Plug.Upload{} = upload, _depth), do: %{filename: upload.filename}

  defp sanitize_param(params, depth) when is_map(params) do
    params
    |> Enum.take(@max_param_items)
    |> Map.new(fn {key, value} ->
      key = to_string(key)
      {key, sanitize_param_value(key, value, depth)}
    end)
  end

  defp sanitize_param(list, depth) when is_list(list) do
    list
    |> Enum.take(@max_param_items)
    |> Enum.map(&sanitize_param(&1, depth - 1))
  end

  defp sanitize_param(value, _depth) when is_binary(value), do: truncate_string(value)
  defp sanitize_param(value, _depth) when is_integer(value), do: value
  defp sanitize_param(value, _depth) when is_float(value), do: value
  defp sanitize_param(value, _depth) when is_boolean(value), do: value
  defp sanitize_param(nil, _depth), do: nil
  defp sanitize_param(value, _depth), do: inspect(value)

  defp sanitize_param_value(key, value, depth) do
    cond do
      sensitive_key?(key) -> @redacted
      key == "args" -> summarize_hook_args(value)
      true -> sanitize_param(value, depth - 1)
    end
  end

  defp summarize_hook_args(args) when is_list(args) do
    %{
      "count" => length(args),
      "types" => Enum.map(args, &param_type/1)
    }
  end

  defp summarize_hook_args(value), do: sanitize_param(value, @max_param_depth - 1)

  # `code` and `state` are exact matches, not substrings: an OAuth
  # authorization code is a credential, and these lines are warning-level, so
  # they reach the admin buffer, the rotating file and whatever ships logs off
  # the host. Slow OAuth callbacks cross the threshold routinely — they make an
  # outbound token exchange — so in practice every one of them was logged with
  # its code.
  #
  # Personal data is redacted for the same reason. Sign in with Apple posts its
  # callback with a `user` field — a JSON string holding the player's email and
  # full name, sent on their first sign-in only — so every new Apple player's
  # name and email went into the log. `user` is also the root of every
  # `user[...]` form; a slow-request line needs none of it.
  #
  # Exact matches because `code` appears inside innocent names (`country_code`,
  # `postcode`) and `name` inside most of them, and over-redacting a
  # slow-request log makes it useless.
  @exact_sensitive_keys ~w(code state id_token access_token refresh_token user
                           first_name last_name full_name firstname lastname fullname)
  @sensitive_key_parts ~w(password token secret authorization api_key cookie session
                          email phone)

  defp sensitive_key?(key) when is_binary(key) do
    normalized = String.downcase(key)

    normalized in @exact_sensitive_keys or
      Enum.any?(@sensitive_key_parts, &String.contains?(normalized, &1))
  end

  defp param_type(value) when is_binary(value), do: "string"
  defp param_type(value) when is_integer(value), do: "integer"
  defp param_type(value) when is_float(value), do: "float"
  defp param_type(value) when is_boolean(value), do: "boolean"
  defp param_type(value) when is_list(value), do: "list"
  defp param_type(value) when is_map(value), do: "map"
  defp param_type(nil), do: "nil"
  defp param_type(_value), do: "unknown"

  defp truncate_string(value) do
    if byte_size(value) <= @max_string_bytes do
      value
    else
      String.slice(value, 0, @max_string_bytes) <> "...[truncated]"
    end
  end

  defp format_duration_ms(duration_ms) do
    duration_ms
    |> Kernel.*(1.0)
    |> :erlang.float_to_binary(decimals: 3)
  end

  defp slow_request_threshold_ms do
    Application.get_env(
      :gamend_web,
      :slow_request_threshold_ms,
      @default_slow_request_threshold_ms
    )
  end

  defp expose_header? do
    Application.get_env(:gamend_web, :environment, :prod) != :prod
  end
end
