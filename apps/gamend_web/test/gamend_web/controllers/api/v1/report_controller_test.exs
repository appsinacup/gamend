defmodule GamendWeb.Api.V1.ReportControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Reports
  alias Gamend.Reports.Report
  alias GamendWeb.Auth.Guardian

  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
       )

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp report(attrs \\ %{}) do
    Map.merge(
      %{"kind" => "page", "subject" => %{"path" => "/play"}, "description" => "Crashed"},
      attrs
    )
  end

  test "lists the kinds a client may file", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    kinds = conn |> auth_conn(user) |> get("/api/v1/reports/kinds") |> json_response(200)

    assert %{"key" => "page", "topics" => [], "max_attachments" => 3} =
             Enum.find(kinds["data"]["kinds"], &(&1["key"] == "page"))
  end

  test "a signed-in client files a report, image included", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    body =
      conn
      |> auth_conn(user)
      |> post(
        "/api/v1/reports",
        report(%{
          "attachments" => [Base.encode64(@png)],
          "client" => %{"platform" => "android"}
        })
      )
      |> json_response(201)

    assert %{"id" => id, "kind" => "page", "status" => "open"} = body["data"]
    report = Reports.get(id)
    assert report.user_id == user.id
    assert report.source == "api"
    assert report.client == %{"platform" => "android"}
    assert [%{"type" => "image/png"}] = Report.files(report)
  end

  test "needs a token", %{conn: conn} do
    assert conn |> post("/api/v1/reports", report()) |> json_response(401)
  end

  test "an unknown kind and a duplicate are answered with their codes", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    conn = auth_conn(conn, user)

    assert %{"error" => "invalid_report"} =
             conn |> post("/api/v1/reports", %{"kind" => "nope"}) |> json_response(400)

    assert conn |> post("/api/v1/reports", report()) |> json_response(201)

    assert %{"error" => "already_reported"} =
             conn |> post("/api/v1/reports", report()) |> json_response(409)
  end
end
