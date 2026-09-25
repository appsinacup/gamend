defmodule GamendWeb.GameSocketTest do
  @moduledoc """
  `/socket/websocket` is served by the endpoint's own plug rather than by
  `socket/3`, so its idle timeout and frame cap can be settings. These go
  through the real endpoint to the upgrade: if Phoenix changes the internals
  that plug calls, this is what fails.
  """
  # Settings are global Application config.
  use GamendWeb.ConnCase, async: false

  import Gamend.AccountsFixtures

  alias Gamend.SettingsHelpers
  alias GamendWeb.Auth.Guardian

  # The upgrade check wants a `host` header, which `put_req_header/3` refuses
  # to set (Plug keeps it in `conn.host`), so it goes in directly.
  defp upgrade(conn, params) do
    %{conn | req_headers: [{"host", "www.example.com"} | conn.req_headers]}
    |> put_req_header("connection", "Upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")
    |> put_req_header("sec-websocket-version", "13")
    |> get("/socket/websocket", params)
  end

  defp token do
    {:ok, token, _claims} = Guardian.encode_and_sign(user_fixture())
    token
  end

  test "upgrades with the default timeout and frame cap", %{conn: conn} do
    conn = upgrade(conn, %{"token" => token(), "vsn" => "2.0.0"})

    assert conn.halted
    assert [{:websocket, {GamendWeb.UserSocket, _state, opts}}] = Plug.Test.sent_upgrades(conn)
    assert opts[:timeout] == 300_000
    assert opts[:max_frame_size] == 131_072
    assert opts[:compress] == true
  end

  test "the timeout and frame cap follow their settings", %{conn: conn} do
    for {key, value} <- [socket_timeout_ms: 45_000, socket_max_frame_bytes: 4_096] do
      SettingsHelpers.put(:gamend_web, GamendWeb.Realtime, key, value)
      on_exit(fn -> SettingsHelpers.delete(:gamend_web, GamendWeb.Realtime, key) end)
    end

    conn = upgrade(conn, %{"token" => token(), "vsn" => "2.0.0"})

    assert [{:websocket, {GamendWeb.UserSocket, _state, opts}}] = Plug.Test.sent_upgrades(conn)
    assert opts[:timeout] == 45_000
    assert opts[:max_frame_size] == 4_096
  end

  test "a bad token is refused before any upgrade", %{conn: conn} do
    conn = upgrade(conn, %{"token" => "not-a-token", "vsn" => "2.0.0"})

    assert conn.status == 403
    assert Plug.Test.sent_upgrades(conn) == []
  end

  test "other paths under /socket are not the game socket", %{conn: conn} do
    conn = get(conn, "/socket/longpoll")
    refute conn.status in [101, 403]
  end
end
