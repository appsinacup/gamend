defmodule GamendWeb.UserChannelNotificationsTest do
  use ExUnit.Case
  import Phoenix.ChannelTest

  alias Gamend.AccountsFixtures
  alias Gamend.Friends
  alias Gamend.Notifications
  alias GamendWeb.Auth.Guardian

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)
    :ok
  end

  @endpoint GamendWeb.Endpoint

  defp make_friends do
    a = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    b = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
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

  test "user channel pushes existing notifications on join" do
    {a, b} = make_friends()

    # Create notifications for b before connecting
    {:ok, _n1} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "First"})
    {:ok, _n2} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Second"})

    {:ok, token, _claims} = Guardian.encode_and_sign(b)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, _socket} = subscribe_and_join(socket, "user:#{b.id}", %{})

    # Should receive the "updated" event first
    assert_push "updated", _user_payload

    # Then should receive both notifications in order
    assert_push "notification_created", n1_payload
    assert n1_payload.title == "First"

    assert_push "notification_created", n2_payload
    assert n2_payload.title == "Second"
  end

  test "user channel pushes new notification in real-time" do
    {a, b} = make_friends()

    {:ok, token, _claims} = Guardian.encode_and_sign(b)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, _socket} = subscribe_and_join(socket, "user:#{b.id}", %{})

    # Drain the initial "updated" push
    assert_push "updated", _user_payload

    # Now send a notification while b is connected
    {:ok, _n} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Live!"})

    assert_push "notification_created", payload
    assert payload.title == "Live!"
    assert payload.sender_id == a.id
    assert Map.has_key?(payload, :sender_name)
    assert payload.group == ""
  end

  test "notifications persist across sessions (reconnect)" do
    {a, b} = make_friends()

    # Send a notification
    {:ok, _} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Persist"})

    # First session - connect and receive
    {:ok, token, _claims} = Guardian.encode_and_sign(b)
    {:ok, socket1} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, socket1} = subscribe_and_join(socket1, "user:#{b.id}", %{})

    assert_push "updated", _
    assert_push "notification_created", %{title: "Persist"}

    # Leave the channel (simulating disconnect)
    Process.unlink(socket1.channel_pid)
    :ok = close(socket1)

    # Reconnect - should still get the notification since it wasn't deleted
    {:ok, socket2} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, _socket2} = subscribe_and_join(socket2, "user:#{b.id}", %{})

    assert_push "updated", _
    assert_push "notification_created", %{title: "Persist"}
  end

  test "deleted notifications are not pushed on reconnect" do
    {a, b} = make_friends()

    {:ok, n} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Gone"})

    # Delete the notification
    {1, _} = Notifications.delete_notifications(b.id, [n.id])

    # Connect - should NOT receive the deleted notification
    {:ok, token, _claims} = Guardian.encode_and_sign(b)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, _socket} = subscribe_and_join(socket, "user:#{b.id}", %{})

    assert_push "updated", _

    # Should not receive any notification
    refute_push "notification_created", _, 200
  end
end
