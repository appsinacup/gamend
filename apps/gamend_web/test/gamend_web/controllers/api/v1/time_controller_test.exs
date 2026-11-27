defmodule GamendWeb.Api.V1.TimeControllerTest do
  use GamendWeb.ConnCase, async: true

  alias Gamend.Accounts.TimeZone

  test "GET /api/v1/time answers the server clock in ms", %{conn: conn} do
    before = System.system_time(:millisecond)
    now = conn |> get("/api/v1/time") |> json_response(200) |> get_in(["data", "server_now"])

    assert is_integer(now)
    assert now >= before - 1_000
  end

  test "GET /api/v1/time_zones answers the settings picker's zones, signed in or not", %{
    conn: conn
  } do
    zones = conn |> get("/api/v1/time_zones") |> json_response(200) |> get_in(["data", "zones"])

    assert zones == TimeZone.names()
    assert "UTC" in zones
    assert "Europe/Bucharest" in zones
    assert zones == Enum.sort(zones)
  end
end
