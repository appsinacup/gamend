defmodule GamendWeb.RealtimeEvents do
  @moduledoc """
  Registry of every server→client channel event.

  Event names are bare strings at their `push`/`push_event` call sites, so they
  cannot be enumerated at runtime — this list is the enumerable source of
  truth. A drift test (`realtime_events_drift_test.exs`) greps the channel
  sources and fails when a pushed literal is missing here or an entry here no
  longer exists in the code, which is what keeps the two in sync.

  `pb: true` marks events with a protobuf mapping in `GamendWeb.EventCodec`
  (sent as binary frames on `?format=protobuf` sockets; JSON otherwise).
  """

  @type entry :: %{
          topic: String.t(),
          event: String.t(),
          pb: boolean(),
          payload: String.t(),
          description: String.t(),
          signal: String.t()
        }

  @user "user:*"
  @lobby "lobby:*"
  @lobbies "lobbies"
  @group "group:*"
  @groups "groups"
  @party "party:*"
  @signaling "signaling:*"

  @events [
    # ── user:* ──────────────────────────────────────────────────────────
    {@user, "updated", true, "full user", "The user's own profile changed"},
    {@user, "notification_created", true, "notification", "New notification for the user"},
    {@user, "friend_updated", true, "friends: id => brief user",
     "A friend's profile or presence changed"},
    {@user, "kv_updated", true, "kv entry", "A subscribed KV key was written"},
    {@user, "kv_deleted", true, "kv entry ref", "A subscribed KV key was deleted"},
    {@user, "wallet_updated", true, "currency + balance + delta",
     "The user's wallet balance changed"},
    {@user, "inventory_updated", true, "item + quantity + delta", "The user's inventory changed"},
    {@user, "result_started", false, "result", "A play of the user's began (Gamend.Results)"},
    {@user, "result_event", false, "result id + event",
     "Something happened in a play of the user's"},
    {@user, "result_ended", false, "result", "A play of the user's ended"},
    {@user, "chat_message_created", true, "chat message", "DM or watched-conversation message"},
    {@user, "chat_message_updated", true, "chat message", "A visible chat message was edited"},
    {@user, "chat_message_deleted", true, "message id", "A visible chat message was deleted"},
    {@user, "chat_muted", true, "scope + scope_ref_id + expires_at + reason",
     "The user was muted; the client greys out its chat input"},
    {@user, "chat_unmuted", true, "scope + scope_ref_id", "The user's mute was lifted"},
    {@user, "account_banned", false, "expires_at + reason",
     "The account was banned: every other channel and API call now refuses it"},
    {@user, "account_unbanned", false, "empty", "The account's ban was lifted"},
    {@user, "quest_progress", true, "quest progress", "A quest objective advanced"},
    {@user, "quest_completed", true, "quest progress",
     "Every objective met — claim or auto-claim next"},
    {@user, "quest_claimed", true, "quest progress", "The quest's rewards were granted"},
    {@user, "group_invite_accepted", true, "group id",
     "Someone accepted the user's group invite"},
    {@user, "group_invite_cancelled", true, "group id",
     "A group invite to the user was cancelled"},
    {@user, "group_join_request_approved", true, "group id",
     "The user's join request was approved"},
    {@user, "group_join_request_rejected", true, "group id",
     "The user's join request was rejected"},
    {@user, "party_invite_accepted", true, "party id + user id",
     "Someone accepted the user's party invite"},
    {@user, "party_invite_cancelled", true, "party id + user id",
     "A party invite to the user was cancelled"},
    {@user, "party_invite_declined", true, "party id + user id",
     "Someone declined the user's party invite"},
    {@user, "match_found", true, "lobby id + match params",
     "A match formed; the user is seated in the lobby"},
    {@user, "ticket_queued", true, "ticket id + match params + queued_at_ms + requeued",
     "The user's matchmaking ticket is in the queue: joined, or put back after a failed accept"},
    {@user, "ticket_cancelled", true, "ticket id + reason",
     "The user's matchmaking ticket left the queue with no match"},
    # A matchmaking accept has no lobby or party yet: its check fans out per user.
    {@user, "ready_check_started", true, "ready check",
     "A formed match asks the user to accept (kind accept)"},
    {@user, "ready_check_updated", true, "ready check", "A player answered the accept"},
    {@user, "ready_check_passed", true, "ready check", "Everyone accepted: the match is seated"},
    {@user, "ready_check_failed", true, "ready check",
     "The accept was declined, timed out or cancelled"},
    # Pushed by `Gamend.Friends` straight to the socket (its `broadcast_user/2`).
    {@user, "outgoing_request", false, "friendship", "The user sent a friend request"},
    {@user, "incoming_request", false, "friendship", "Someone sent the user a friend request"},
    {@user, "request_cancelled", false, "friendship", "A pending friend request was cancelled"},
    {@user, "friend_accepted", false, "friendship", "A friend request was accepted"},
    {@user, "friend_rejected", false, "friendship", "A friend request was rejected"},
    {@user, "friend_removed", false, "friendship", "A friendship was removed"},
    {@user, "friend_blocked", false, "friendship", "The user blocked someone, or was blocked"},
    {@user, "friend_unblocked", false, "friendship", "A block was lifted"},
    {@user, "tournament_updated", true, "tournament ref",
     "A registered tournament changed state"},
    {@user, "tournament_finished", true, "tournament ref", "A registered tournament finished"},
    {@user, "tournament_match_ready", true, "match ref",
     "The user's tournament match is ready to play"},
    {@user, "tournament_match_resolved", true, "match ref",
     "The user's tournament match was resolved"},
    {@user, "webrtc:answer", false, "sdp",
     "WebRTC signalling: server answer to the client offer"},
    {@user, "webrtc:ice", false, "ice candidate", "WebRTC signalling: server ICE candidate"},
    {@user, "webrtc:channel_open", false, "channel label", "A WebRTC DataChannel opened"},
    {@user, "webrtc:channel_closed", false, "empty", "The WebRTC DataChannel closed"},
    {@user, "webrtc:state", false, "state string", "WebRTC connection state changed"},

    # ── lobby:* ─────────────────────────────────────────────────────────
    {@lobby, "updated", true, "full lobby", "Lobby fields changed (title, lock, metadata, ...)"},
    {@lobby, "user_joined", true, "member event", "A player joined the lobby"},
    {@lobby, "user_left", true, "member event", "A player left the lobby"},
    {@lobby, "user_kicked", true, "member event", "A player was kicked from the lobby"},
    {@lobby, "user_online", true, "member event", "A lobby user's socket came online"},
    {@lobby, "user_offline", true, "member event", "A lobby user's socket went offline"},
    {@lobby, "user_updated", true, "user brief", "A lobby user's profile changed"},
    {@lobby, "host_changed", true, "new host", "Lobby host transferred"},
    {@lobby, "state_changed", true, "lobby id + from + to + state_changed_at",
     "The lobby moved to another lifecycle state"},
    {@lobby, "ready_check_started", true, "ready check", "The host opened a ready check"},
    {@lobby, "ready_check_updated", true, "ready check", "A member answered (debounced)"},
    {@lobby, "ready_check_passed", true, "ready check", "Every participant answered ready"},
    {@lobby, "ready_check_failed", true, "ready check",
     "The check was declined, timed out or cancelled"},
    {@lobby, "chat_message_created", true, "chat message", "Lobby chat message"},
    {@lobby, "chat_message_updated", true, "chat message", "Lobby chat message edited"},
    {@lobby, "chat_message_deleted", true, "message id", "Lobby chat message deleted"},
    {@lobby, "result_started", false, "result", "A play its members may read began"},
    {@lobby, "result_event", false, "result id + event", "Something happened in that play"},
    {@lobby, "result_ended", false, "result", "That play ended"},

    # ── lobbies ─────────────────────────────────────────────────────────
    {@lobbies, "lobby_created", true, "full lobby", "A public lobby was created"},
    {@lobbies, "lobby_updated", true, "full lobby", "A public lobby changed"},
    {@lobbies, "lobby_deleted", true, "lobby id", "A public lobby was deleted"},
    {@lobbies, "lobby_membership_changed", true, "lobby id",
     "A public lobby's member count changed"},

    # ── group:* ─────────────────────────────────────────────────────────
    {@group, "updated", true, "full group", "Group fields changed"},
    {@group, "member_joined", true, "member event", "A member joined the group"},
    {@group, "member_left", true, "member event", "A member left the group"},
    {@group, "member_kicked", true, "member event", "A member was kicked"},
    {@group, "member_promoted", true, "member event", "A member was promoted"},
    {@group, "member_demoted", true, "member event", "A member was demoted"},
    {@group, "member_online", true, "member event", "A member came online"},
    {@group, "member_offline", true, "member event", "A member went offline"},
    {@group, "member_updated", true, "user brief", "A member's profile changed"},
    {@group, "join_request_approved", true, "member event", "A join request was approved"},
    {@group, "join_request_rejected", true, "member event", "A join request was rejected"},
    {@group, "chat_message_created", true, "chat message", "Group chat message"},
    {@group, "chat_message_updated", true, "chat message", "Group chat message edited"},
    {@group, "chat_message_deleted", true, "message id", "Group chat message deleted"},

    # ── groups ──────────────────────────────────────────────────────────
    {@groups, "group_created", true, "full group", "A public group was created"},
    {@groups, "group_updated", true, "full group", "A public group changed"},
    {@groups, "group_deleted", true, "group id", "A public group was deleted"},

    # ── party:* ─────────────────────────────────────────────────────────
    {@party, "updated", true, "full party", "Party fields changed"},
    {@party, "member_joined", true, "member event", "A member joined the party"},
    {@party, "member_left", true, "member event", "A member left the party"},
    {@party, "member_online", true, "member event", "A member came online"},
    {@party, "member_offline", true, "member event", "A member went offline"},
    {@party, "member_updated", true, "user brief", "A member's profile changed"},
    {@party, "disbanded", true, "party ref", "The party was disbanded"},
    {@party, "ready_check_started", true, "ready check", "The leader opened a ready check"},
    {@party, "ready_check_updated", true, "ready check", "A member answered (debounced)"},
    {@party, "ready_check_passed", true, "ready check", "Every member answered ready"},
    {@party, "ready_check_failed", true, "ready check",
     "The check was declined, timed out or cancelled"},
    {@party, "chat_message_created", true, "chat message", "Party chat message"},
    {@party, "chat_message_updated", true, "chat message", "Party chat message edited"},
    {@party, "chat_message_deleted", true, "message id", "Party chat message deleted"},

    # ── signaling:* ─────────────────────────────────────────────────────
    {@signaling, "user_joined", false, "user id + role", "A user joined the signaling room"},
    {@signaling, "user_rejoined", false, "user id + role",
     "A user rejoined the signaling room after a transient disconnect"},
    {@signaling, "user_left", false, "user id", "A user left the signaling room"},
    {@signaling, "offer", false, "sdp + from user id", "WebRTC offer relayed to this peer"},
    {@signaling, "answer", false, "sdp + from user id", "WebRTC answer relayed to this peer"},
    {@signaling, "ice", false, "candidate + from user id",
     "WebRTC ICE candidate relayed to this peer"},
    {@signaling, "room_closed", false, "empty", "The signaling room was closed"}
  ]

  # The name an SDK's signal or callback has for an event, where it is not the
  # event's own (`signal/2`). The C++, C#, Rust and Balaur SDKs' come from the
  # table generated from this registry (`mix gamend.gen.events`, `clients/events.json`); a new
  # event's signal is its name unless named here.
  @signals %{
    {"group", "chat_message_created"} => "group_chat_message",
    {"group", "chat_message_deleted"} => "group_chat_message_deleted",
    {"group", "chat_message_updated"} => "group_chat_message_updated",
    {"group", "join_request_approved"} => "group_join_request_approved",
    {"group", "join_request_rejected"} => "group_join_request_rejected",
    {"group", "member_demoted"} => "group_member_demoted",
    {"group", "member_joined"} => "group_member_joined",
    {"group", "member_kicked"} => "group_member_kicked",
    {"group", "member_left"} => "group_member_left",
    {"group", "member_offline"} => "group_member_offline",
    {"group", "member_online"} => "group_member_online",
    {"group", "member_promoted"} => "group_member_promoted",
    {"group", "member_updated"} => "group_member_updated",
    {"group", "updated"} => "group_updated",
    {"groups", "group_updated"} => "group_list_updated",
    {"lobbies", "lobby_updated"} => "lobby_list_updated",
    {"lobby", "chat_message_created"} => "lobby_chat_message",
    {"lobby", "chat_message_deleted"} => "lobby_chat_message_deleted",
    {"lobby", "chat_message_updated"} => "lobby_chat_message_updated",
    {"lobby", "host_changed"} => "lobby_host_changed",
    {"lobby", "result_ended"} => "lobby_result_ended",
    {"lobby", "result_event"} => "lobby_result_event",
    {"lobby", "result_started"} => "lobby_result_started",
    {"lobby", "state_changed"} => "lobby_state_changed",
    {"lobby", "updated"} => "lobby_updated",
    {"lobby", "user_joined"} => "lobby_member_joined",
    {"lobby", "user_kicked"} => "lobby_member_kicked",
    {"lobby", "user_left"} => "lobby_member_left",
    {"lobby", "user_offline"} => "lobby_member_offline",
    {"lobby", "user_online"} => "lobby_member_online",
    {"lobby", "user_updated"} => "lobby_member_updated",
    {"party", "chat_message_created"} => "party_chat_message",
    {"party", "chat_message_deleted"} => "party_chat_message_deleted",
    {"party", "chat_message_updated"} => "party_chat_message_updated",
    {"party", "disbanded"} => "party_disbanded",
    {"party", "member_joined"} => "party_member_joined",
    {"party", "member_left"} => "party_member_left",
    {"party", "member_offline"} => "party_member_offline",
    {"party", "member_online"} => "party_member_online",
    {"party", "member_updated"} => "party_member_updated",
    {"party", "updated"} => "party_updated",
    {"signaling", "answer"} => "signaling_answer",
    {"signaling", "ice"} => "signaling_ice",
    {"signaling", "offer"} => "signaling_offer",
    {"signaling", "room_closed"} => "signaling_room_closed",
    {"signaling", "user_joined"} => "signaling_user_joined",
    {"signaling", "user_left"} => "signaling_user_left",
    {"signaling", "user_rejoined"} => "signaling_user_rejoined",
    {"user", "chat_message_created"} => "friend_chat_message",
    {"user", "chat_message_deleted"} => "friend_chat_message_deleted",
    {"user", "chat_message_updated"} => "friend_chat_message_updated",
    {"user", "friend_accepted"} => "friend_added",
    {"user", "incoming_request"} => "friend_added",
    {"user", "notification_created"} => "notification_emitted",
    {"user", "outgoing_request"} => "friend_added",
    {"user", "request_cancelled"} => "friend_request_cancelled",
    {"user", "updated"} => "user_updated",
    {"user", "webrtc:answer"} => "webrtc_answer",
    {"user", "webrtc:channel_closed"} => "webrtc_channel_closed",
    {"user", "webrtc:channel_open"} => "webrtc_channel_open",
    {"user", "webrtc:ice"} => "webrtc_ice",
    {"user", "webrtc:state"} => "webrtc_state"
  }

  @doc "Every server→client event as a list of maps."
  @spec all() :: [entry()]
  def all do
    Enum.map(@events, fn {topic, event, pb, payload, description} ->
      %{
        topic: topic,
        event: event,
        pb: pb,
        payload: payload,
        description: description,
        signal: signal(topic, event)
      }
    end)
  end

  @doc """
  The SDK signal name for `event` on `topic` (`"user:*"` or `"user"`): the
  event's own name unless `@signals` names another.
  """
  @spec signal(String.t(), String.t()) :: String.t()
  def signal(topic, event) do
    channel = topic |> String.split(":") |> hd()
    Map.get(@signals, {channel, event}, event)
  end

  @doc "The distinct event names in the registry."
  def names, do: @events |> Enum.map(fn {_, event, _, _, _} -> event end) |> Enum.uniq()
end
