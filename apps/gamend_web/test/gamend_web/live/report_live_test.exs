defmodule GamendWeb.ReportLiveTest do
  @moduledoc """
  `/report`: anyone files a report, signed in or not, and it lands in the
  queue with what they typed and nothing else about them.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Reports
  alias Gamend.Reports.Report
  alias Gamend.SettingsHelpers

  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
       )

  setup do
    on_exit(fn -> Application.delete_env(:gamend_core, Reports) end)
    :ok
  end

  defp form(lv), do: element(lv, "form[phx-hook=ReportForm]")

  test "the page offers the kinds and no form until one is picked", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/report")

    assert html =~ "Report a problem"
    assert html =~ "A page"
    refute has_element?(lv, "form[phx-hook=ReportForm]")

    lv |> element("a", "A page") |> render_click()
    assert_patch(lv, "/report?kind=page")
    assert has_element?(lv, "form[phx-hook=ReportForm]")
  end

  test "a visitor reports a page; the link's page is filled in", %{conn: conn} do
    url = GamendWeb.Endpoint.url() <> "/games/ro"
    {:ok, lv, html} = live(conn, ~p"/report?kind=page&page=/games/ro")
    assert html =~ ~s(value="#{url}")

    html = lv |> form() |> render_submit(%{"description" => "The keyboard covers the answers"})

    assert html =~ "Thanks. We read every report."
    assert [%Report{} = report] = Reports.list()
    assert report.kind == "page"
    assert report.subject == %{"path" => url}
    assert report.subject_ref == "/games/ro"
    assert report.description == "The keyboard covers the answers"
    assert report.user_id == nil
  end

  test "the page field reports what the reader typed", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/report?kind=page")

    lv |> element("form[phx-target]") |> render_change(%{"path" => "/tests/fr"})
    lv |> form() |> render_submit(%{"description" => "Broken"})

    assert [%Report{subject: %{"path" => "/tests/fr"}}] = Reports.list()
  end

  test "a page report needs a description", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/report?kind=page")

    html = lv |> form() |> render_submit(%{"description" => ""})
    assert html =~ "Say what happened."
    assert Reports.list() == []
  end

  test "a bot filling the hidden field is thanked and nothing is stored", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/report?kind=page")

    html =
      lv |> form() |> render_submit(%{"description" => "Buy now", "website" => "spam.example"})

    assert html =~ "Thanks. We read every report."
    assert Reports.list() == []
  end

  test "a screenshot travels with the report", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/report?kind=page")

    shot =
      file_input(lv, "form[phx-hook=ReportForm]", :attachments, [
        %{name: "screenshot.png", content: @png, type: "image/png"}
      ])

    render_upload(shot, "screenshot.png")

    lv |> form() |> render_submit(%{"description" => "See the picture"})

    assert [%Report{} = report] = Reports.list()
    assert [%{"type" => "image/png"}] = Report.files(report)
  end

  test "a signed-in reader's report is theirs, with no email", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    {:ok, lv, _html} = live(conn, ~p"/report?kind=page")

    html = lv |> form() |> render_submit(%{"description" => "Broken"})
    assert html =~ "notifications"

    assert [%Report{user_id: user_id, email: nil}] = Reports.list()
    assert user_id == user.id
  end

  test "an address over its hourly cap is told to wait", %{conn: conn} do
    SettingsHelpers.put(:gamend_core, Reports, :ip_hourly_limit, 1)
    {:ok, lv, _html} = live(conn, ~p"/report?kind=page")

    lv |> form() |> render_submit(%{"description" => "One"})
    lv |> element("button", "Report something else") |> render_click()
    html = lv |> form() |> render_submit(%{"description" => "Two"})

    assert html =~ "You have sent a lot of reports."
    assert length(Reports.list()) == 1
  end
end
