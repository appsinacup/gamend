defmodule GamendWeb.NotificationsEdgeCasesTest do
  @moduledoc """
  Edge-case tests for the notifications system:

  - User deletion cascades to notifications (DB-level `on_delete: :delete_all`)
  - Cache is not stale after create/delete operations
  """
  use Gamend.DataCase

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Friends
  alias Gamend.Notifications

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp make_friends do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()
    {:ok, f} = Friends.create_request(a.id, b.id)
    {:ok, _} = Friends.accept_friend_request(f.id, b)
    purge_notifications()
    {a, b}
  end

  # Friendship setup itself creates friend_request/friend_accepted
  # notifications; clear them so tests assert only on what they create.
  defp purge_notifications do
    Gamend.Repo.delete_all(Gamend.Notifications.Notification)
  end

  # ---------------------------------------------------------------------------
  # User deletion cascade
  # ---------------------------------------------------------------------------
  describe "user deletion cascade" do
    test "deleting a user removes notifications in both directions" do
      {a, b} = make_friends()

      # a -> b
      {:ok, _} =
        Notifications.admin_create_notification(a.id, b.id, %{"title" => "A to B"})

      # b -> a
      {:ok, _} =
        Notifications.admin_create_notification(b.id, a.id, %{"title" => "B to A"})

      assert Notifications.count_notifications(a.id) == 1
      assert Notifications.count_notifications(b.id) == 1

      # Delete user a – notifications where a is sender OR recipient are deleted
      {:ok, _} = Accounts.delete_user(a)

      # b's notification from a should be gone (sender deleted)
      assert Notifications.count_notifications(b.id) == 0
      # a's notification from b should be gone (recipient deleted)
      assert Notifications.count_notifications(a.id) == 0
    end

    test "deleting a user does not affect other users' unrelated notifications" do
      {a, b} = make_friends()
      c = AccountsFixtures.user_fixture()
      d = AccountsFixtures.user_fixture()
      {:ok, f_cd} = Friends.create_request(c.id, d.id)
      {:ok, _} = Friends.accept_friend_request(f_cd.id, d)
      purge_notifications()

      # a -> b notification
      {:ok, _} =
        Notifications.admin_create_notification(a.id, b.id, %{"title" => "A to B"})

      # c -> d notification (completely unrelated)
      {:ok, _} =
        Notifications.admin_create_notification(c.id, d.id, %{"title" => "C to D"})

      assert Notifications.count_notifications(b.id) == 1
      assert Notifications.count_notifications(d.id) == 1

      # Delete user a
      {:ok, _} = Accounts.delete_user(a)

      # b's notification from a is gone (sender cascade)
      assert Notifications.count_notifications(b.id) == 0

      # d's notification from c is untouched
      assert Notifications.count_notifications(d.id) == 1
      [notif] = Notifications.list_notifications(d.id)
      assert notif.title == "C to D"
    end
  end

  # ---------------------------------------------------------------------------
  # Cache freshness
  # ---------------------------------------------------------------------------
  describe "cache freshness" do
    test "list_notifications reflects newly created notifications" do
      {sender, recipient} = make_friends()

      # Initially empty
      assert Notifications.list_notifications(recipient.id) == []
      assert Notifications.count_notifications(recipient.id) == 0

      # Create a notification
      {:ok, n1} =
        Notifications.send_notification(sender.id, %{
          "user_id" => recipient.id,
          "title" => "First"
        })

      # Cache should not be stale – must reflect the new notification
      notifs = Notifications.list_notifications(recipient.id)
      assert length(notifs) == 1
      assert hd(notifs).id == n1.id

      assert Notifications.count_notifications(recipient.id) == 1
    end

    test "admin_create_notification invalidates user cache" do
      sender = AccountsFixtures.user_fixture()
      recipient = AccountsFixtures.user_fixture()

      # Warm the cache
      assert Notifications.list_notifications(recipient.id) == []
      assert Notifications.count_notifications(recipient.id) == 0

      # Admin create (bypasses friendship check)
      {:ok, _} =
        Notifications.admin_create_notification(sender.id, recipient.id, %{
          "title" => "Admin notif"
        })

      # Cache must reflect it
      assert Notifications.count_notifications(recipient.id) == 1
      notifs = Notifications.list_notifications(recipient.id)
      assert length(notifs) == 1
      assert hd(notifs).title == "Admin notif"
    end

    test "admin_delete_notification invalidates user cache" do
      sender = AccountsFixtures.user_fixture()
      recipient = AccountsFixtures.user_fixture()

      {:ok, n} =
        Notifications.admin_create_notification(sender.id, recipient.id, %{
          "title" => "To be admin-deleted"
        })

      # Warm cache
      assert Notifications.count_notifications(recipient.id) == 1

      # Admin delete
      {:ok, _} = Notifications.admin_delete_notification(n.id)

      # Cache must reflect deletion
      assert Notifications.count_notifications(recipient.id) == 0
      assert Notifications.list_notifications(recipient.id) == []
    end

    test "multiple rapid creates and deletes keep cache consistent" do
      {sender, recipient} = make_friends()

      # Create 5 notifications
      notifs =
        for i <- 1..5 do
          {:ok, n} =
            Notifications.send_notification(sender.id, %{
              "user_id" => recipient.id,
              "title" => "Rapid #{i}"
            })

          n
        end

      assert Notifications.count_notifications(recipient.id) == 5

      # Delete first 3
      ids_to_delete = Enum.take(notifs, 3) |> Enum.map(& &1.id)
      Notifications.delete_notifications(recipient.id, ids_to_delete)

      assert Notifications.count_notifications(recipient.id) == 2

      remaining = Notifications.list_notifications(recipient.id)
      assert length(remaining) == 2
      remaining_titles = Enum.map(remaining, & &1.title)
      assert "Rapid 4" in remaining_titles
      assert "Rapid 5" in remaining_titles
    end

    test "cache is per-user and does not leak between users" do
      {a, b} = make_friends()
      c = AccountsFixtures.user_fixture()
      {:ok, f_ac} = Friends.create_request(a.id, c.id)
      {:ok, _} = Friends.accept_friend_request(f_ac.id, c)
      purge_notifications()

      # Warm both caches
      assert Notifications.count_notifications(b.id) == 0
      assert Notifications.count_notifications(c.id) == 0

      # Send to b only
      {:ok, _} =
        Notifications.send_notification(a.id, %{
          "user_id" => b.id,
          "title" => "For B"
        })

      assert Notifications.count_notifications(b.id) == 1
      assert Notifications.count_notifications(c.id) == 0

      # Send to c only
      {:ok, _} =
        Notifications.send_notification(a.id, %{
          "user_id" => c.id,
          "title" => "For C"
        })

      assert Notifications.count_notifications(b.id) == 1
      assert Notifications.count_notifications(c.id) == 1
    end
  end
end
