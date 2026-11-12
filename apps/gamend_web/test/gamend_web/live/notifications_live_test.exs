defmodule GamendWeb.NotificationsLiveTest do
  @moduledoc """
  `/notifications`: sections by notification group, and one type stacked.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Gamend.AccountsFixtures

  alias Gamend.Notifications
  alias Gamend.Notifications.Notification
  alias Gamend.Notifications.Types
  alias Gamend.Repo
  alias GamendWeb.I18n.NotificationTypesCatalog
  alias GamendWeb.NotificationsLive.Sections

  defp create(recipient, sender, title, type \\ nil) do
    metadata = if type, do: %{"type" => type}, else: %{}

    {:ok, notification} =
      Notifications.admin_create_notification(sender.id, recipient.id, %{
        "title" => title,
        "metadata" => metadata
      })

    notification
  end

  defp row(id, metadata), do: %Notification{id: id, metadata: metadata}

  describe "Sections.build/1" do
    test "keeps the newest section, stack and row first" do
      quest = %{"type" => "quest_completed"}
      invite = %{"type" => "group_invite"}

      assert [
               %{key: "quests", count: 2, stacks: [quests]},
               %{key: "social", count: 1, stacks: [invites]}
             ] =
               Sections.build([row("a", quest), row("b", invite), row("c", quest)])

      assert Enum.map(quests.notifications, & &1.id) == ["a", "c"]
      assert Enum.map(invites.notifications, & &1.id) == ["b"]
      assert quests.description == Types.core()["quest_completed"]
    end

    test "a group the notice names wins over its type's" do
      metadata = %{"type" => "quest_completed", "group" => "payments"}

      assert [%{key: "payments", stacks: [%{key: "payments-quest_completed"}]}] =
               Sections.build([row("a", metadata)])
    end

    test "a notice with no type goes in Other and stacks with nothing" do
      assert [%{key: key, stacks: [_one, _other]}] =
               Sections.build([row("a", %{}), row("b", %{})])

      assert key == Sections.other()
    end

    test "picks out the ids of one section or stack" do
      sections =
        Sections.build([
          row("a", %{"type" => "friend_request"}),
          row("b", %{"type" => "group_invite"}),
          row("c", %{"type" => "friend_request"}),
          row("d", %{"type" => "quest_completed"})
        ])

      assert Sections.stack_ids(sections, "social-friend_request") == ["a", "c"]
      assert Enum.sort(Sections.section_ids(sections, "social")) == ["a", "b", "c"]
      assert Sections.stack_ids(sections, "nope") == []
    end
  end

  test "every core type's description is in the catalogue" do
    msgids = NotificationTypesCatalog.msgids()

    for {type, description} <- Types.core() do
      assert description in msgids, "#{type}: add its description to the catalogue"
    end
  end

  describe "the page" do
    setup :register_and_log_in_user

    setup %{user: user} do
      sender = user_fixture()

      %{
        first_request: create(user, sender, "Friend request one", "friend_request"),
        second_request: create(user, sender, "Friend request two", "friend_request"),
        invite: create(user, sender, "Invited to Chess Club", "group_invite"),
        quest: create(user, sender, "Quest done", "quest_completed"),
        plain: create(user, sender, "A note from a friend")
      }
    end

    test "shows a section per group, a stack for one type and a row for a lone one", %{
      conn: conn,
      invite: invite,
      quest: quest,
      plain: plain
    } do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, "#notif-section-social #notif-stack-social-friend_request")
      assert has_element?(view, "#notif-section-social #notif-#{invite.id}")
      assert has_element?(view, "#notif-section-quests #notif-#{quest.id}")
      assert has_element?(view, "#notif-section-other #notif-#{plain.id}")
      refute has_element?(view, "#notif-stack-social-group_invite")
    end

    test "only a section shows a count, and a stack names no senders", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, "#notif-section-toggle-social .badge", "3")
      refute has_element?(view, "#notif-stack-social-friend_request .badge")
      refute has_element?(view, "#notif-stack-toggle-social-friend_request img")
    end

    test "a notification opens its page, alone or from an open stack", %{
      conn: conn,
      quest: quest,
      user: user
    } do
      other = create(user, user_fixture(), "Another quest done", "quest_completed")
      {:ok, view, _html} = live(conn, ~p"/notifications")

      view |> element("#notif-stack-toggle-quests-quest_completed") |> render_click()

      assert has_element?(view, ~s(#notif-#{quest.id} a[href="/quests"]))
      assert has_element?(view, ~s(#notif-#{other.id} a[href="/quests"]))
    end

    test "a notification with nowhere to go is plain text", %{conn: conn, plain: plain} do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      refute has_element?(view, "#notif-#{plain.id} a")
    end

    test "dates say how long ago", %{conn: conn, plain: plain} do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, ~s(#notif-#{plain.id} time[data-local-time="relative"]))

      assert has_element?(
               view,
               ~s(#notif-stack-toggle-social-friend_request time[data-local-time="relative"])
             )
    end

    test "a stack opens to its notifications and closes again", %{
      conn: conn,
      first_request: first,
      second_request: second
    } do
      {:ok, view, _html} = live(conn, ~p"/notifications")
      toggle = element(view, "#notif-stack-toggle-social-friend_request")

      refute has_element?(view, "#notif-#{first.id}")

      render_click(toggle)
      assert has_element?(view, "#notif-stack-social-friend_request #notif-#{first.id}")
      assert has_element?(view, "#notif-stack-social-friend_request #notif-#{second.id}")

      assert has_element?(
               view,
               ~s(#notif-stack-toggle-social-friend_request[aria-expanded="true"])
             )

      render_click(toggle)
      refute has_element?(view, "#notif-#{first.id}")
    end

    test "a section folds away", %{conn: conn, invite: invite} do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      view |> element("#notif-section-toggle-social") |> render_click()

      assert has_element?(view, "#notif-section-social")
      refute has_element?(view, "#notif-#{invite.id}")
    end

    test "deleting a stack leaves the rest of its section", %{
      conn: conn,
      user: user,
      invite: invite
    } do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      view |> element("#notif-stack-delete-social-friend_request") |> render_click()

      refute has_element?(view, "#notif-stack-social-friend_request")
      assert has_element?(view, "#notif-#{invite.id}")
      assert user.id |> Notifications.list_recent_notifications(10) |> length() == 3
    end

    test "deleting a section leaves the others", %{conn: conn, user: user, quest: quest} do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      view |> element("#notif-section-delete-social") |> render_click()

      refute has_element?(view, "#notif-section-social")
      assert has_element?(view, "#notif-#{quest.id}")
      assert user.id |> Notifications.list_recent_notifications(10) |> length() == 2
    end

    test "deleting one row leaves its section", %{conn: conn, invite: invite} do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      view |> element("#notif-delete-#{invite.id}") |> render_click()

      refute has_element?(view, "#notif-#{invite.id}")
      assert has_element?(view, "#notif-stack-social-friend_request")
    end

    test "an open stack stays open when a notification arrives", %{
      conn: conn,
      user: user,
      first_request: first
    } do
      {:ok, view, _html} = live(conn, ~p"/notifications")
      view |> element("#notif-stack-toggle-social-friend_request") |> render_click()

      late = create(user, user_fixture(), "Friend request three", "friend_request")

      assert has_element?(view, "#notif-#{late.id}")
      assert has_element?(view, "#notif-#{first.id}")
    end
  end

  describe "more notifications than a load" do
    setup :register_and_log_in_user

    test "older ones wait behind Load more", %{conn: conn, user: user} do
      now = DateTime.utc_now(:second)

      rows =
        for i <- 1..51 do
          %{
            id: Gamend.UUIDv7.generate(),
            sender_id: user.id,
            recipient_id: user.id,
            title: "Notice #{i}",
            content: "",
            metadata: %{},
            read: true,
            inserted_at: DateTime.add(now, i, :second),
            updated_at: now
          }
        end

      Repo.insert_all(Notification, rows)
      oldest = hd(rows)

      {:ok, view, _html} = live(conn, ~p"/notifications")
      refute has_element?(view, "#notif-#{oldest.id}")

      view |> element("#notifications-load-more") |> render_click()

      assert has_element?(view, "#notif-#{oldest.id}")
      refute has_element?(view, "#notifications-load-more")
    end
  end
end
