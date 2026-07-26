defmodule GameServerWeb.Plugs.MetricsAuth do
  @moduledoc """
  Authentication for the `/metrics` endpoint.

  Access rules (checked in order):

  1. **Loopback** (127.x, ::1) — always allowed without auth.

  2. **Bearer token** — if `METRICS_AUTH_TOKEN` is set, every non-loopback
     request must include `Authorization: Bearer <token>`, including
     private/Docker-internal IPs. (Trusting a private source IP is unsafe behind
     a proxy that can be made to leave `remote_ip` as its own private address.)

  3. **No token configured** — private/Docker-internal IPs are allowed without
     auth (dev/compose convenience); all requests are allowed.

  ## Configuration

      # In production — set this to restrict external access
      METRICS_AUTH_TOKEN=my-secret-prometheus-token

  Prometheus scrape config with token:

      scrape_configs:
        - job_name: "gamend"
          bearer_token: "my-secret-prometheus-token"
          static_configs:
            - targets: ["app:4000"]
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      loopback?(conn.remote_ip) -> conn
      required_token() == nil and private_ip?(conn.remote_ip) -> conn
      true -> check_token(conn)
    end
  end

  defp check_token(conn) do
    case required_token() do
      nil ->
        # No token configured — allow unrestricted access
        conn

      expected ->
        case get_req_header(conn, "authorization") do
          ["Bearer " <> token] ->
            if Plug.Crypto.secure_compare(token, expected) do
              conn
            else
              deny(conn)
            end

          _ ->
            deny(conn)
        end
    end
  end

  defp deny(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(401, "Unauthorized")
    |> halt()
  end

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_), do: false

  # Check if the IP is in a private/local range
  defp private_ip?({10, _, _, _}), do: true
  defp private_ip?({172, b, _, _}) when b >= 16 and b <= 31, do: true
  defp private_ip?({192, 168, _, _}), do: true
  defp private_ip?(ip), do: loopback?(ip)

  defp required_token do
    case GameServerWeb.Observability.get(:metrics_token) do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end
end
