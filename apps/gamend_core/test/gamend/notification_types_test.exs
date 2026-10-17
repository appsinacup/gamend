defmodule Gamend.NotificationTypesTest do
  @moduledoc """
  Notification codes are a closed set. The server never reads the type, so an
  unregistered code would be delivered and silently ignored by every client —
  it is rejected at write time instead.
  """
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Notifications
  alias Gamend.Notifications.Notification
  alias Gamend.Notifications.Types

  defp pair do
    {AccountsFixtures.user_fixture(), AccountsFixtures.user_fixture()}
  end

  test "every code emitted by core is registered" do
    # The codes core actually sends; a new emission without a registry entry
    # fails here before it can reach a client.
    for code <- ~w(friend_request friend_accepted friend_rejected
                   group_invite group_invite_accepted group_invite_declined
                   group_join_request group_join_request_approved group_join_request_rejected
                   group_kicked group_deleted group_promoted group_demoted
                   party_invite party_invite_accepted party_invite_declined party_kicked
                   lobby_kicked
                   chat_friend chat_group chat_lobby chat_party
                   chat_report chat_report_resolved chat_warning chat_mute
                   quest_completed report report_resolved) do
      assert Types.known?(code), "core code #{code} is not registered"
    end
  end

  test "a registered code is accepted" do
    {sender, recipient} = pair()

    assert {:ok, notification} =
             Notifications.admin_create_notification(sender.id, recipient.id, %{
               "title" => "Friend request",
               "metadata" => %{"type" => "friend_request"}
             })

    assert notification.metadata["type"] == "friend_request"
  end

  test "an unregistered code is rejected" do
    {sender, recipient} = pair()

    assert {:error, changeset} =
             Notifications.admin_create_notification(sender.id, recipient.id, %{
               "title" => "Mystery",
               "metadata" => %{"type" => "not_a_real_code"}
             })

    assert "unknown notification type \"not_a_real_code\"" in errors_on(changeset).metadata
  end

  test "a notification without a type is still allowed" do
    {sender, recipient} = pair()

    assert {:ok, _} =
             Notifications.admin_create_notification(sender.id, recipient.id, %{
               "title" => "Plain message",
               "metadata" => %{"other" => "data"}
             })
  end

  test "an atom-keyed type is validated too" do
    {sender, recipient} = pair()

    assert {:error, changeset} =
             Notifications.admin_create_notification(sender.id, recipient.id, %{
               title: "Mystery",
               metadata: %{type: "not_a_real_code"}
             })

    assert "unknown notification type \"not_a_real_code\"" in errors_on(changeset).metadata
  end

  describe "create_chat_notification/3" do
    # Chat sends these from `Gamend.Async.run/1`, where a rejected changeset is
    # dropped without a trace — so each kind is checked here, row and all.
    for kind <- ~w(chat_friend chat_group chat_lobby chat_party) do
      test "stores a #{kind} notification and counts repeats" do
        user = AccountsFixtures.user_fixture()

        attrs = %{
          "title" => "New messages (#{unquote(kind)})",
          "metadata" => %{"type" => unquote(kind)}
        }

        assert {:ok, _} = Notifications.create_chat_notification(user.id, user.id, attrs)
        assert {:ok, _} = Notifications.create_chat_notification(user.id, user.id, attrs)

        assert [row] = Repo.all(from n in Notification, where: n.recipient_id == ^user.id)
        assert row.metadata["type"] == unquote(kind)
        assert row.metadata["message_count"] == 2
      end
    end
  end

  test "known?/1 rejects non-strings" do
    refute Types.known?(nil)
    refute Types.known?(:friend_request)
    refute Types.known?(42)
  end
end
