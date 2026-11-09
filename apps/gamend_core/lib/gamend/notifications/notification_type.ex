defmodule Gamend.Notifications.NotificationType do
  @moduledoc """
  The `metadata["type"]` codes core writes on a notification. The registry with their descriptions is `Gamend.Notifications.Types`.
  """

  use Gamend.Names,
      ~w(friend_request friend_accepted group_invite group_invite_accepted group_deleted
         group_join_request_approved group_join_request_rejected party_invite
         party_invite_accepted party_invite_declined lobby_kicked chat_friend chat_group
         chat_lobby chat_party quest_completed report)
end
