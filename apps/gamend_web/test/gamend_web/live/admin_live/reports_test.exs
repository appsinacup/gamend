defmodule GamendWeb.AdminLive.ReportsTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Notifications
  alias Gamend.Repo
  alias Gamend.Reports
  alias Gamend.Reports.Notices

  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
       )

  defp admin_conn(conn) do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    log_in_user(conn, admin)
  end

  defp page_report(context \\ %{}, attrs \\ %{}) do
    {:ok, report} =
      Reports.create(
        Map.merge(
          %{"kind" => "page", "subject" => %{"path" => "/games"}, "description" => "It broke"},
          attrs
        ),
        context
      )

    report
  end

  test "lists open reports with how many share a page", %{conn: conn} do
    page_report()
    page_report()
    page_report(%{}, %{"subject" => %{"path" => "/tests"}, "description" => "Other"})

    {:ok, _lv, html} = live(admin_conn(conn), ~p"/admin/reports")

    assert html =~ "Reports (3)"
    assert html =~ "It broke"
    assert html =~ "×2"
  end

  test "closing as fixed tells a reporter who had an account", %{conn: conn} do
    reporter = AccountsFixtures.user_fixture()
    report = page_report(%{user_id: reporter.id})

    {:ok, lv, _html} = live(admin_conn(conn), ~p"/admin/reports")

    lv
    |> element("#report-#{report.id} button", "Fixed")
    |> render_click()

    lv
    |> form("#report-close-form", %{"note" => "deployed", "message" => "Fixed now, thanks."})
    |> render_submit()

    assert Reports.get(report.id).status == "fixed"

    assert [notice] =
             Notifications.list_notifications_by_title(reporter.id, Notices.reporter_title())

    assert notice.content == "Fixed now, thanks."
  end

  test "an image is served to an admin and to nobody else", %{conn: conn} do
    # The first account is made an admin, so the admin comes first.
    admin = admin_conn(build_conn())
    report = page_report(%{attachments: [@png]})
    path = "/admin/reports/#{report.id}/attachments/1"

    assert conn |> get(path) |> redirected_to()

    user_conn = log_in_user(build_conn(), AccountsFixtures.user_fixture())
    refute user_conn |> get(path) |> Map.get(:status) == 200

    resp = get(admin, path)
    assert resp.status == 200
    assert resp.resp_body == @png
    assert get_resp_header(resp, "content-type") == ["image/png"]
    assert get_resp_header(resp, "cache-control") == ["private, no-store"]
  end
end
