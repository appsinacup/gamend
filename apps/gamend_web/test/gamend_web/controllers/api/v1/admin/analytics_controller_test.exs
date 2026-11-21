defmodule GamendWeb.Api.V1.Admin.AnalyticsControllerTest do
  use GamendWeb.ConnCase, async: true

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Analytics
  alias Gamend.Repo
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    {:ok, token, _} = Guardian.encode_and_sign(admin)
    %{conn: put_req_header(conn, "authorization", "Bearer " <> token)}
  end

  test "requires admin" do
    user = AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)
    conn = build_conn() |> put_req_header("authorization", "Bearer " <> token)

    assert json_response(get(conn, "/api/v1/admin/analytics"), 403)
    assert json_response(get(conn, "/api/v1/admin/analytics/daily"), 403)
  end

  test "summary carries the dashboard numbers", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    :ok = Analytics.record_activity(user.id, DateTime.utc_now())

    body = json_response(get(conn, "/api/v1/admin/analytics"), 200)["data"]

    assert body["day"] == Date.to_iso8601(Date.utc_today())
    assert body["dau"] >= 1
    assert body["mau"] >= body["dau"]
    assert Map.has_key?(body, "d7")
    assert Map.has_key?(body, "conversion_30d")
  end

  test "snapshot, economy and counts endpoints answer", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, _} = Gamend.Economy.grant(user.id, "coins", 42, reason: "test_grant")
    :ok = Analytics.count("level.finished", 3)

    body = json_response(get(conn, "/api/v1/admin/analytics/snapshot"), 200)["data"]
    assert is_map(body["players"]) and is_map(body["activity"])

    body =
      json_response(get(conn, "/api/v1/admin/analytics/economy?days=3&currency=coins"), 200)[
        "data"
      ]

    assert body["days"] == 3
    assert Enum.any?(body["totals"], &(&1["reason"] == "test_grant" and &1["granted"] == 42))
    assert Enum.all?(body["flow"], &(&1["currency"] == "coins"))

    body =
      json_response(get(conn, "/api/v1/admin/analytics/counts?key=level.*&days=2"), 200)["data"]

    assert body["key"] == "level.*"
    assert Enum.any?(body["totals"], &(&1["key"] == "level.finished" and &1["total"] >= 3))
    assert body["series"]["level.finished"][Date.to_iso8601(Date.utc_today())] >= 3
  end

  test "daily series honours ?days and refuses one past its maximum", %{conn: conn} do
    body = json_response(get(conn, "/api/v1/admin/analytics/daily?days=7"), 200)["data"]
    assert body["days"] == 7
    assert length(body["series"]) == 7
    assert List.last(body["series"])["day"] == Date.to_iso8601(Date.utc_today())

    # Past the documented maximum: refused by the request check (`RequestContract`).
    assert %{"error" => "validation_failed", "errors" => %{"days" => [_]}} =
             json_response(get(conn, "/api/v1/admin/analytics/daily?days=9999"), 422)
  end
end
