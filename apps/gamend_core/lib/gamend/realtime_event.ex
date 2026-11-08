defmodule Gamend.RealtimeEvent do
  @moduledoc """
  The names of the server-to-client channel events core and the channels both spell. The registry that lists them with their payloads is `GamendWeb.RealtimeEvents`.
  """

  @all ~w(updated notification_created friend_updated kv_updated kv_deleted wallet_updated
         inventory_updated result_started result_event result_ended chat_message_created
         chat_message_updated chat_message_deleted chat_muted chat_unmuted quest_progress
         quest_completed quest_claimed account_banned group_invite_accepted
         group_invite_cancelled group_join_request_approved group_join_request_rejected
         party_invite_accepted party_invite_cancelled party_invite_declined user_joined user_left
         user_kicked user_online user_offline user_updated state_changed host_changed
         ready_check_started ready_check_updated ready_check_passed ready_check_failed
         group_created group_updated group_deleted lobby_created lobby_updated lobby_deleted
         lobby_membership_changed member_joined member_left member_kicked member_promoted
         member_demoted member_online member_offline member_updated join_request_approved
         join_request_rejected tournament_updated tournament_finished tournament_match_ready
         tournament_match_resolved disbanded)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
