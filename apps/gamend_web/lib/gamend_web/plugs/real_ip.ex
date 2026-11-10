defmodule GamendWeb.Plugs.RealIp do
  @moduledoc """
  Extracts the real client IP from proxy headers and sets `conn.remote_ip`.

  Checks headers in priority order:
  1. `CF-Connecting-IP` (Cloudflare)
  2. `Fly-Client-IP` (Fly.io)
  3. `X-Forwarded-For` (generic reverse proxy — takes the **last** entry
     before the first trusted proxy, which is the most reliable position)

  Only parses headers when the request comes from a known proxy address
  (loopback, Docker bridge, or configured trusted proxies). If the request
  comes directly from the internet (remote_ip is not a proxy), the headers
  are ignored to prevent spoofing.

  The endpoint listens on `::`, so a proxy reaching it over IPv4 arrives as
  `::ffff:a.b.c.d` and is judged as the IPv4 address it carries. From such a
  peer only `X-Forwarded-For` is read: Caddy, nginx and Gamend Cloud's edge
  write their own entry there, and the walk can only end on an untrusted
  address. They pass `CF-Connecting-IP` and `Fly-Client-IP` on as the client
  sent them, and `CF-Connecting-IP: 127.0.0.1` would pass for loopback.

  ## Configuration

      config :gamend_web, GamendWeb.Plugs.RealIp,
        trusted_proxies: ["127.0.0.1", "::1", "172.16.0.0/12", "10.0.0.0/8"]

  By default, loopback and private-range addresses are trusted.
  """

  import Plug.Conn

  @behaviour Plug

  # Common Docker / private / loopback ranges (as tuples for quick matching)
  @default_trusted_cidrs [
    # 127.0.0.0/8
    {{127, 0, 0, 0}, 8},
    # 10.0.0.0/8
    {{10, 0, 0, 0}, 8},
    # 172.16.0.0/12
    {{172, 16, 0, 0}, 12},
    # 192.168.0.0/16
    {{192, 168, 0, 0}, 16},
    # ::1/128
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128},
    # fd00::/8 (private IPv6)
    {{0xFD00, 0, 0, 0, 0, 0, 0, 0}, 8}
  ]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    peer = unmapped(conn.remote_ip)

    if trusted_proxy?(peer) do
      case extract_real_ip(conn, peer == conn.remote_ip) do
        {:ok, ip} -> %{conn | remote_ip: ip}
        :error -> conn
      end
    else
      conn
    end
  end

  defp extract_real_ip(conn, platform_headers?) do
    platform = if platform_headers?, do: platform_ip(conn)

    cond do
      platform ->
        parse_ip(String.trim(platform))

      # X-Forwarded-For: client, proxy1, proxy2
      # The leftmost non-trusted IP is the real client.
      xff = get_req_header(conn, "x-forwarded-for") |> List.first() ->
        xff
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reverse()
        |> find_first_untrusted_ip()

      true ->
        :error
    end
  end

  # Cloudflare and Fly.io each set a single, verified IP.
  defp platform_ip(conn) do
    Enum.find_value(["cf-connecting-ip", "fly-client-ip"], fn header ->
      conn |> get_req_header(header) |> List.first()
    end)
  end

  defp parse_ip(raw) do
    case :inet.parse_address(String.to_charlist(raw)) do
      {:ok, ip} -> {:ok, unmapped(ip)}
      _ -> :error
    end
  end

  defp unmapped({0, 0, 0, 0, 0, 0xFFFF, _hi, _lo} = ip), do: :inet.ipv4_mapped_ipv6_address(ip)
  defp unmapped(ip), do: ip

  # Walk the reversed XFF list (rightmost first) and return the first
  # IP that isn't a trusted proxy. If all are trusted, return :error.
  defp find_first_untrusted_ip(reversed_ips) do
    Enum.reduce_while(reversed_ips, :error, fn raw, _acc ->
      with {:ok, ip} <- parse_ip(raw),
           false <- trusted_proxy?(ip) do
        {:halt, {:ok, ip}}
      else
        _ -> {:cont, :error}
      end
    end)
  end

  defp trusted_proxy?(ip) do
    trusted_cidrs = configured_cidrs()
    Enum.any?(trusted_cidrs, fn {network, mask} -> ip_in_cidr?(ip, network, mask) end)
  end

  defp configured_cidrs do
    case :persistent_term.get({__MODULE__, :cidrs}, :not_set) do
      :not_set ->
        extra =
          Application.get_env(:gamend_web, __MODULE__, [])
          |> Keyword.get(:trusted_proxies, [])
          |> Enum.flat_map(&parse_cidr/1)

        cidrs = @default_trusted_cidrs ++ extra
        :persistent_term.put({__MODULE__, :cidrs}, cidrs)
        cidrs

      cached ->
        cached
    end
  end

  defp parse_cidr(str) do
    case String.split(str, "/") do
      [ip_str, mask_str] ->
        case {:inet.parse_address(String.to_charlist(ip_str)), Integer.parse(mask_str)} do
          {{:ok, ip}, {mask, ""}} -> [{ip, mask}]
          _ -> []
        end

      [ip_str] ->
        case :inet.parse_address(String.to_charlist(ip_str)) do
          {:ok, ip} when tuple_size(ip) == 4 -> [{ip, 32}]
          {:ok, ip} when tuple_size(ip) == 8 -> [{ip, 128}]
          _ -> []
        end
    end
  end

  defp ip_in_cidr?(ip, network, mask) when tuple_size(ip) == tuple_size(network) do
    ip_int = ip_to_integer(ip)
    net_int = ip_to_integer(network)
    bits = tuple_size(ip) * 8
    shift = bits - mask
    Bitwise.bsr(ip_int, shift) == Bitwise.bsr(net_int, shift)
  end

  defp ip_in_cidr?(_ip, _network, _mask), do: false

  defp ip_to_integer(ip) when tuple_size(ip) == 4 do
    <<int::32>> = <<elem(ip, 0)::8, elem(ip, 1)::8, elem(ip, 2)::8, elem(ip, 3)::8>>
    int
  end

  defp ip_to_integer(ip) when tuple_size(ip) == 8 do
    <<int::128>> =
      <<elem(ip, 0)::16, elem(ip, 1)::16, elem(ip, 2)::16, elem(ip, 3)::16, elem(ip, 4)::16,
        elem(ip, 5)::16, elem(ip, 6)::16, elem(ip, 7)::16>>

    int
  end
end
