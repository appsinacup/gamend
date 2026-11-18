defmodule GamendWeb.AdminLive.NotificationsTest do
  use GamendWeb.ConnCase, async: true

  use Oban.Testing, repo: Gamend.Repo

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Notifications
  alias Gamend.Notifications.AnnouncementWorker
  alias Gamend.Notifications.Preferences
  alias Gamend.Repo

  defp admin_fixture do
    user = AccountsFixtures.user_fixture()

    {:ok, admin} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    admin
  end

  test "admin sends a notification with ids typed as text", %{conn: conn} do
    admin = admin_fixture()
    recipient = AccountsFixtures.user_fixture()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/notifications")

    view |> element(~S(button[phx-click="toggle_create"])) |> render_click()

    view
    |> form("#admin-create-notification-form",
      notification: %{
        "sender_id" => admin.id,
        "recipient_id" => recipient.id,
        "title" => "form-notification",
        "content" => "hello from the admin form",
        "metadata" => ""
      }
    )
    |> render_submit()

    assert Notifications.count_notifications(recipient.id) == 1
  end

  test "non-UUID sender/recipient ids are rejected without creating anything", %{conn: conn} do
    admin = admin_fixture()
    recipient = AccountsFixtures.user_fixture()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/notifications")

    view |> element(~S(button[phx-click="toggle_create"])) |> render_click()

    html =
      view
      |> form("#admin-create-notification-form",
        notification: %{
          "sender_id" => "42",
          "recipient_id" => recipient.id,
          "title" => "bad-sender",
          "content" => "",
          "metadata" => ""
        }
      )
      |> render_submit()

    assert html =~ "Sender ID and Recipient ID are required"
    assert Notifications.count_notifications(recipient.id) == 0
  end

  # The admins' queues are the admin's work, chosen here and not on their
  # account settings.
  test "the admins' notification groups are chosen here, not in settings", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/notifications")
    assert has_element?(view, "#admin-notify-settings #notify-group-moderation")

    view |> element("#notify-moderation-email") |> render_click()
    refute Preferences.enabled?(Repo.get!(User, admin.id), "moderation", "email")

    {:ok, settings, _html} = live(conn, ~p"/users/settings?tab=notifications")
    assert has_element?(settings, "#notify-group-social")
    refute has_element?(settings, "#notify-group-moderation")
  end

  test "admin sends one notification to every player", %{conn: conn} do
    admin = admin_fixture()
    player = AccountsFixtures.user_fixture()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/notifications")
    assert has_element?(view, "#admin-announce-submit[data-confirm]")

    view
    |> form("#admin-announce-form",
      announcement: %{"title" => "Season 2", "content" => "Out now", "url" => "/news"}
    )
    |> render_submit()

    assert [job] = all_enqueued(worker: AnnouncementWorker)
    assert job.args["title"] == "Season 2"
    assert job.args["url"] == "/news"

    assert :ok = perform_job(AnnouncementWorker, job.args)
    assert [row] = Notifications.list_notifications(player.id)
    assert row.title == "Season 2"
  end

  test "an announcement with no title or an outside link is refused on the form", %{conn: conn} do
    admin = admin_fixture()
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/notifications")

    view |> form("#admin-announce-form", announcement: %{"title" => ""}) |> render_submit()
    assert has_element?(view, "#admin-announce-form", "can't be blank")

    view
    |> form("#admin-announce-form",
      announcement: %{"title" => "Hi", "url" => "https://example.com"}
    )
    |> render_submit()

    assert has_element?(view, "#admin-announce-form", "must be a path on this site")
    assert all_enqueued(worker: AnnouncementWorker) == []
  end
end
