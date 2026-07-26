defmodule GameServerWeb.RealtimeEvents do
  @moduledoc """
  Registry of every server→client channel event.

  Event names are bare strings at their `push`/`push_event` call sites, so they
  cannot be enumerated at runtime — this list is the enumerable source of
  truth. A drift test (`realtime_events_drift_test.exs`) greps the channel
  sources and fails when a pushed literal is missing here or an entry here no
  longer exists in the code, which is what keeps the two in sync.

  `pb: true` marks events with a protobuf mapping in `GameServerWeb.EventCodec`
  (sent as binary frames on `?format=protobuf` sockets; JSON otherwise).
  """

  @type entry :: %{
          topic: String.t(),
          event: String.t(),
          pb: boolean(),
          payload: String.t(),
          description: String.t()
        }

  @user "user:*"
  @lobby "lobby:*"
  @lobbies "lobbies"
  @group "group:*"
  @groups "groups"
  @party "party:*"

  @events [
    # ── user:* ──────────────────────────────────────────────────────────
    {@user, "updated", true, "full user", "The user's own profile changed"},
    {@user, "notification_created", true, "notification", "New notification for the user"},
    {@user, "friend_updated", true, "friendship + users",
     "Friend request/accept/block state changed"},
    {@user, "kv_updated", true, "kv entry", "A subscribed KV key was written"},
    {@user, "kv_deleted", true, "kv entry ref", "A subscribed KV key was deleted"},
    {@user, "wallet_updated", true, "currency + balance + delta",
     "The user's wallet balance changed"},
    {@user, "inventory_updated", true, "item + quantity + delta", "The user's inventory changed"},
    {@user, "chat_message_created", true, "chat message", "DM or watched-conversation message"},
    {@user, "chat_message_updated", true, "chat message", "A visible chat message was edited"},
    {@user, "chat_message_deleted", true, "message id", "A visible chat message was deleted"},
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
    {@lobby, "state_changed", false, "lobby id + from + to + state_changed_at",
     "The lobby moved to another lifecycle state"},
    {@lobby, "ready_check_started", true, "ready check", "The host opened a ready check"},
    {@lobby, "ready_check_updated", true, "ready check", "A member answered (debounced)"},
    {@lobby, "ready_check_passed", true, "ready check", "Every participant answered ready"},
    {@lobby, "ready_check_failed", true, "ready check",
     "The check was declined, timed out or cancelled"},
    {@lobby, "chat_message_created", true, "chat message", "Lobby chat message"},
    {@lobby, "chat_message_updated", true, "chat message", "Lobby chat message edited"},
    {@lobby, "chat_message_deleted", true, "message id", "Lobby chat message deleted"},

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
    {@party, "chat_message_created", true, "chat message", "Party chat message"},
    {@party, "chat_message_updated", true, "chat message", "Party chat message edited"},
    {@party, "chat_message_deleted", true, "message id", "Party chat message deleted"}
  ]

  @doc "Every server→client event as a list of maps."
  @spec all() :: [entry()]
  def all do
    Enum.map(@events, fn {topic, event, pb, payload, description} ->
      %{topic: topic, event: event, pb: pb, payload: payload, description: description}
    end)
  end

  @doc "The distinct event names in the registry."
  def names, do: @events |> Enum.map(fn {_, event, _, _, _} -> event end) |> Enum.uniq()
end
