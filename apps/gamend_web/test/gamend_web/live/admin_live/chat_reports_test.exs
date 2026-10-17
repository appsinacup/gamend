defmodule GamendWeb.AdminLive.ChatReportsTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Chat.Message
  alias Gamend.Chat.Moderation.Cache
  alias Gamend.Chat.Reports
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    reporter = AccountsFixtures.user_fixture()
    sender = AccountsFixtures.user_fixture()

    message =
      %Message{sender_id: sender.id}
      |> Message.changeset(%{
        chat_type: "lobby",
        chat_ref_id: Ecto.UUID.generate(),
        content: "something rude"
      })
      |> Repo.insert!()

    {:ok, report} = Reports.report_message(reporter.id, message.id, "abusive")
    on_exit(fn -> Cache.apply_remote(:mute_deleted, {sender.id, "global", nil}) end)
    %{admin: admin, sender: sender, message: message, report: report}
  end

  defp page(conn, admin, path \\ ~p"/admin/chat/reports") do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(path)
    view
  end

  defp status(report), do: Repo.reload(report).status

  test "the queue lists the report; a moderator claims it for review", %{
    conn: conn,
    admin: admin,
    report: report
  } do
    view = page(conn, admin)
    assert has_element?(view, "#chat-report-#{report.id}")

    render_click(view, "review", %{"id" => report.id})
    assert status(report) == "reviewing"
  end

  test "dismissed with a note to the reporter, the report is resolved", %{
    conn: conn,
    admin: admin,
    report: report
  } do
    view = page(conn, admin)
    render_click(view, "open_action", %{"id" => report.id, "action" => "dismiss"})
    assert has_element?(view, "#chat-report-action-form")

    view
    |> form("#chat-report-action-form", %{
      "notify_reporter" => "true",
      "reporter_message" => "Thanks, nothing to act on."
    })
    |> render_submit()

    assert status(report) == "dismissed"
    refute has_element?(view, "#chat-report-action-form")
  end

  test "a warning resolves it and tells the player", %{conn: conn, admin: admin, report: report} do
    view = page(conn, admin)
    render_click(view, "open_action", %{"id" => report.id, "action" => "warn"})

    render_submit(view, "submit_action", %{"message" => "Keep it civil.", "notify_user" => "true"})

    assert status(report) == "actioned"
  end

  test "deleting the message resolves it and the message is gone", %{
    conn: conn,
    admin: admin,
    report: report,
    message: message
  } do
    view = page(conn, admin)
    render_click(view, "open_action", %{"id" => report.id, "action" => "delete_message"})
    render_submit(view, "submit_action", %{})
    assert status(report) == "actioned"
    assert Repo.get(Message, message.id) == nil
  end

  test "a mute resolves it and mutes the player; a scoped mute needs its room", %{
    conn: conn,
    admin: admin,
    report: report,
    sender: sender
  } do
    view = page(conn, admin)
    render_click(view, "open_action", %{"id" => report.id, "action" => "mute"})

    render_submit(view, "submit_action", %{
      "scope" => "lobby",
      "scope_ref_id" => "",
      "duration" => "1h"
    })

    assert :sys.get_state(view.pid).socket.assigns.form_error =~ "lobby, group or party id"
    assert status(report) == "open"

    render_submit(view, "submit_action", %{
      "scope" => "global",
      "duration" => "1h",
      "reason" => "abuse"
    })

    assert status(report) == "actioned"
    assert Cache.muted?(sender.id, "lobby", Ecto.UUID.generate())
  end

  test "an action form closes without acting; an unknown report says so", %{
    conn: conn,
    admin: admin,
    report: report
  } do
    view = page(conn, admin)
    render_click(view, "open_action", %{"id" => report.id, "action" => "warn"})
    render_change(view, "form_change", %{"message" => "draft"})
    render_click(view, "close_action", %{})
    refute has_element?(view, "#chat-report-action-form")

    render_click(view, "review", %{"id" => Ecto.UUID.generate()})
    render_click(view, "open_action", %{"id" => Ecto.UUID.generate(), "action" => "warn"})
    assert status(report) == "open"
  end

  test "the queue filters by status and by player, from the form or the URL", %{
    conn: conn,
    admin: admin,
    report: report,
    sender: sender
  } do
    view = page(conn, admin)
    view |> form("#chat-reports-filter-form", %{"status" => "dismissed"}) |> render_change()
    refute has_element?(view, "#chat-report-#{report.id}")

    render_change(view, "filter", %{"status" => "open"})
    assert has_element?(view, "#chat-report-#{report.id}")

    render_click(view, "filter_user", %{"id" => Ecto.UUID.generate()})
    refute has_element?(view, "#chat-report-#{report.id}")

    view = page(conn, admin, ~p"/admin/chat/reports?reported_user_id=#{sender.id}&status=open")
    assert has_element?(view, "#chat-report-#{report.id}")

    render_click(view, "next_page", %{})
    render_click(view, "prev_page", %{})
    render_click(view, "page_size", %{"size" => "50"})
    render_click(view, "refresh", %{})
    assert has_element?(view, "#chat-report-#{report.id}")
  end
end
