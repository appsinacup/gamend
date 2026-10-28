defmodule Gamend.Notifications.PreferencesTest do
  @moduledoc """
  Notification choices (`Gamend.Notifications.Preferences`), the server's
  own notifications (`Gamend.Notifications.notify/3`) honouring them, the
  existing pushes following a type's group, and the time zone.
  """
  use Gamend.DataCase, async: false
  use Oban.Testing, repo: Gamend.Repo

  alias Gamend.Accounts.TimeZone
  alias Gamend.AccountsFixtures
  alias Gamend.Notifications
  alias Gamend.Notifications.Preferences
  alias Gamend.Push
  alias Gamend.Push.DeliveryWorker

  @streak %{
    key: "streak",
    label: "Streak about to end",
    defaults: %{"in_app" => true, "email" => false, "push" => false},
    types: ["streak_ending"],
    signup: true
  }

  setup do
    old = Application.get_env(:gamend_core, :notification_groups)
    Application.put_env(:gamend_core, :notification_groups, [@streak])

    on_exit(fn ->
      if old,
        do: Application.put_env(:gamend_core, :notification_groups, old),
        else: Application.delete_env(:gamend_core, :notification_groups)
    end)

    %{user: AccountsFixtures.user_fixture()}
  end

  defp register_device!(user) do
    {:ok, _token} =
      Push.register_token(user.id, %{
        "token" => "tok-#{System.unique_integer([:positive])}",
        "platform" => "android"
      })
  end

  describe "choices" do
    test "defaults apply until the user chooses", %{user: user} do
      assert Preferences.enabled?(user, "social", "push")
      refute Preferences.enabled?(user, "social", "email")
      assert Preferences.enabled?(user, "streak", "in_app")
      refute Preferences.enabled?(user, "streak", "email")
      refute Preferences.enabled?(user, "nope", "email")
    end

    test "a choice sticks, and a switch wins over it", %{user: user} do
      {:ok, user} = Preferences.put(user, "streak", "email", true)
      assert Preferences.enabled?(user, "streak", "email")

      {:ok, user} = Preferences.turn_off(user, :email)
      refute Preferences.enabled?(user, "streak", "email")
      assert Preferences.enabled?(user, "streak", "in_app")

      {:ok, user} = Preferences.turn_off(user, :all)
      refute Preferences.enabled?(user, "streak", "in_app")

      {:ok, user} = Preferences.turn_on(user, :all)
      {:ok, user} = Preferences.turn_on(user, :email)
      assert Preferences.enabled?(user, "streak", "email")
    end

    test "account email cannot be turned off", %{user: user} do
      assert {:error, :not_configurable} = Preferences.put(user, "account", "email", false)
      {:ok, user} = Preferences.turn_off(user, :all)
      assert Preferences.enabled?(user, "account", "email")
    end

    test "a type belongs to its group" do
      assert Preferences.group_for_type("chat_friend") == "chat"
      assert Preferences.group_for_type("friend_request") == "social"
      assert Preferences.group_for_type("quest_completed") == "quests"
      assert Preferences.group_for_type("streak_ending") == "streak"
      assert Preferences.group_for_type("chat_warning") == "reports"
      assert Preferences.group_for_type("report") == "moderation"
      assert Preferences.group_for_type(nil) == nil
    end

    test "only opted-in host groups are offered at sign-up" do
      assert Enum.map(Preferences.signup_groups(), & &1.key) == ["streak"]
    end

    test "the choices stay private: not in metadata", %{user: user} do
      {:ok, user} = Preferences.put(user, "streak", "email", true)
      refute Map.has_key?(user.metadata || %{}, "notifications")
    end
  end

  describe "notify/3" do
    test "writes the row and skips what is off", %{user: user} do
      assert {:ok, ["in_app"]} =
               Notifications.notify(user.id, "streak", %{
                 "title" => "Your streak ends tonight",
                 "url" => "/tests/daily"
               })

      assert [row] = Notifications.list_notifications(user.id)
      assert row.metadata["url"] == "/tests/daily"
      assert row.metadata["group"] == "streak"
      assert all_enqueued(queue: :mailers) == []
    end

    test "queues the email once the user turned it on", %{user: user} do
      {:ok, _user} = Preferences.put(user, "streak", "email", true)

      assert {:ok, channels} =
               Notifications.notify(user.id, "streak", %{"title" => "Hi", "content" => "Body"})

      assert "email" in channels
      assert [job] = all_enqueued(queue: :mailers)
      assert job.worker == "GamendWeb.Workers.NotificationEmail"
      assert job.args["group"] == "streak"
      assert job.args["subject"] == "Hi"
      assert job.args["text"] == "Body"
    end

    test "pushes only when the group's push is on", %{user: user} do
      register_device!(user)

      assert {:ok, ["in_app"]} = Notifications.notify(user.id, "streak", %{"title" => "Hi"})
      assert all_enqueued(worker: DeliveryWorker) == []

      {:ok, _user} = Preferences.put(user, "streak", "push", true)

      assert {:ok, ["in_app", "push"]} =
               Notifications.notify(user.id, "streak", %{"title" => "Hi"})

      assert [_job] = all_enqueued(worker: DeliveryWorker)
    end

    test "an unknown user is an error" do
      assert {:error, :not_found} = Notifications.notify(Ecto.UUID.generate(), "streak", %{})
    end
  end

  describe "existing notifications follow their group" do
    test "a chat push is skipped once chat push is off", %{user: user} do
      sender = AccountsFixtures.user_fixture()
      register_device!(user)

      {:ok, _} =
        Notifications.admin_create_notification(sender.id, user.id, %{
          "title" => "Friend request",
          "metadata" => %{"type" => "friend_request"}
        })

      assert [_job] = all_enqueued(worker: DeliveryWorker)

      {:ok, _user} = Preferences.put(user, "social", "push", false)

      {:ok, _} =
        Notifications.admin_create_notification(sender.id, user.id, %{
          "title" => "Friend request 2",
          "metadata" => %{"type" => "friend_request"}
        })

      assert [_job] = all_enqueued(worker: DeliveryWorker)
    end
  end

  describe "time zone" do
    test "a known zone is saved; an unknown one refused", %{user: user} do
      assert TimeZone.of(user) == nil
      assert {:error, :invalid_time_zone} = TimeZone.put(user, "Mars/Olympus")
      {:ok, user} = TimeZone.put(user, "Europe/Bucharest")
      assert TimeZone.of(user) == "Europe/Bucharest"
    end

    test "local date follows the zone" do
      utc = ~U[2026-09-30 22:30:00Z]
      assert TimeZone.local_date("Europe/Bucharest", utc) == ~D[2026-10-01]
      assert TimeZone.local_date(nil, utc) == ~D[2026-09-30]
      assert TimeZone.local_hour("America/New_York", utc) == 18
    end

    test "a zone picked by hand is kept until the user goes back to automatic", %{user: user} do
      assert "Europe/Bucharest" in TimeZone.names()
      assert "UTC" in TimeZone.names()
      assert {:error, :invalid_time_zone} = TimeZone.choose(user, "Mars/Olympus")

      {:ok, user} = TimeZone.choose(user, "Asia/Tokyo")
      assert TimeZone.of(user) == "Asia/Tokyo"
      assert TimeZone.manual?(user)

      {:ok, user} = TimeZone.choose(user, nil)
      refute TimeZone.manual?(user)
      assert TimeZone.of(user) == "Asia/Tokyo"
    end

    test "a day starts at the zone's midnight" do
      assert TimeZone.day_start("Europe/Bucharest", ~D[2026-10-01]) == ~U[2026-09-30 21:00:00Z]
      assert TimeZone.day_start(nil, ~D[2026-10-01]) == ~U[2026-10-01 00:00:00Z]
    end
  end
end
