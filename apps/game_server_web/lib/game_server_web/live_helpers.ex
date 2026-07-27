defmodule GameServerWeb.LiveHelpers do
  @moduledoc """
  Shared helpers for LiveViews.
  """

  @doc """
  Extract the client IP from a LiveView socket's `connect_info`.

  Falls back to `"unknown"` when the socket has no peer data (e.g. during
  the initial static render or in tests).
  """
  def client_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: addr} -> addr |> :inet.ntoa() |> to_string()
      _ -> "unknown"
    end
  end

  @doc """
  Check a rate limit bucket for the given IP.

  Bucket types:
    - `:auth` — 30 requests per 60 seconds (matches the HTTP auth bucket)
    - `:general` — 1200 requests per 60 seconds

  Returns `:ok` or `{:error, retry_after_ms}`.
  """
  def check_rate_limit(ip, bucket_type \\ :general)

  def check_rate_limit("unknown", _bucket_type), do: :ok

  def check_rate_limit(ip, :auth) do
    {limit, window} = auth_limits()
    do_check("lv_auth:#{ip}", window, limit)
  end

  def check_rate_limit(ip, :general) do
    {limit, window} = general_limits()
    do_check("lv_general:#{ip}", window, limit)
  end

  defp do_check(key, window_ms, limit) do
    case GameServerWeb.RateLimit.hit(key, window_ms, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after} -> {:error, retry_after}
    end
  end

  defp auth_limits do
    {setting(:auth_limit), setting(:auth_window_ms)}
  end

  defp general_limits do
    {setting(:general_limit), setting(:general_window_ms)}
  end

  defp setting(key), do: GameServer.Settings.get(GameServerWeb.Plugs.RateLimiter, key)

  @doc """
  Put a standard success flash on a LiveView socket.
  """
  def put_success(socket, message), do: Phoenix.LiveView.put_flash(socket, :info, message)

  @doc """
  Put a standard error flash on a LiveView socket.
  """
  def put_failure(socket, message), do: Phoenix.LiveView.put_flash(socket, :error, message)

  @doc """
  Format a common `Failed: reason` message for LiveViews.
  """
  def failure_message(prefix, reason), do: prefix <> ": " <> inspect(reason)

  @doc """
  Return a public user label without exposing email addresses.
  """
  def public_user_name(nil), do: ""

  def public_user_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  def public_user_name(%{"display_name" => name}) when is_binary(name) and name != "", do: name
  def public_user_name(%{id: id}) when is_binary(id) and id != "", do: "User #{id}"
  def public_user_name(%{"id" => id}) when is_binary(id) and id != "", do: "User #{id}"
  def public_user_name(%{user_id: id}) when is_binary(id) and id != "", do: "User #{id}"
  def public_user_name(%{"user_id" => id}) when is_binary(id) and id != "", do: "User #{id}"
  def public_user_name(id) when is_binary(id), do: "User #{id}"
  def public_user_name(_), do: "User"
end
