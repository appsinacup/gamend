defmodule GamendWeb.AdminLive.NotificationsTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Notifications
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
end
