defmodule Gamend.Realtime.V1.LinkedProviders do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.LinkedProviders",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :google, 1, type: :bool
  field :facebook, 2, type: :bool
  field :discord, 3, type: :bool
  field :apple, 4, type: :bool
  field :steam, 5, type: :bool
  field :device, 6, type: :bool
end

defmodule Gamend.Realtime.V1.User do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.User",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, proto3_optional: true, type: :string
  field :email, 2, proto3_optional: true, type: :string
  field :profile_url, 3, proto3_optional: true, type: :string, json_name: "profileUrl"
  field :metadata_json, 4, proto3_optional: true, type: :bytes, json_name: "metadataJson"
  field :display_name, 5, proto3_optional: true, type: :string, json_name: "displayName"
  field :lobby_id, 6, proto3_optional: true, type: :string, json_name: "lobbyId"
  field :party_id, 7, proto3_optional: true, type: :string, json_name: "partyId"
  field :is_online, 8, proto3_optional: true, type: :bool, json_name: "isOnline"
  field :last_seen_at_ms, 9, proto3_optional: true, type: :int64, json_name: "lastSeenAtMs"

  field :linked_providers, 10,
    proto3_optional: true,
    type: Gamend.Realtime.V1.LinkedProviders,
    json_name: "linkedProviders"

  field :has_password, 11, proto3_optional: true, type: :bool, json_name: "hasPassword"
  field :metadata_pb, 12, proto3_optional: true, type: :bytes, json_name: "metadataPb"
  field :username, 13, proto3_optional: true, type: :string
end

defmodule Gamend.Realtime.V1.FriendUpdate.FriendsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.FriendUpdate.FriendsEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Gamend.Realtime.V1.User
end

defmodule Gamend.Realtime.V1.FriendUpdate do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.FriendUpdate",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :friends, 1, repeated: true, type: Gamend.Realtime.V1.FriendUpdate.FriendsEntry, map: true
end

defmodule Gamend.Realtime.V1.UserBrief do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.UserBrief",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, proto3_optional: true, type: :string
  field :display_name, 2, proto3_optional: true, type: :string, json_name: "displayName"
  field :profile_url, 3, proto3_optional: true, type: :string, json_name: "profileUrl"
  field :metadata_json, 4, proto3_optional: true, type: :bytes, json_name: "metadataJson"
  field :is_online, 5, proto3_optional: true, type: :bool, json_name: "isOnline"
  field :is_activated, 6, proto3_optional: true, type: :bool, json_name: "isActivated"
  field :last_seen_at_ms, 7, proto3_optional: true, type: :int64, json_name: "lastSeenAtMs"
  field :metadata_pb, 8, proto3_optional: true, type: :bytes, json_name: "metadataPb"
  field :username, 9, proto3_optional: true, type: :string
end

defmodule Gamend.Realtime.V1.Notification do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.Notification",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, type: :string
  field :sender_id, 2, type: :string, json_name: "senderId"
  field :sender_name, 3, type: :string, json_name: "senderName"
  field :recipient_id, 4, type: :string, json_name: "recipientId"
  field :title, 5, type: :string
  field :content, 6, type: :string
  field :metadata_json, 7, type: :bytes, json_name: "metadataJson"
  field :inserted_at_ms, 8, type: :int64, json_name: "insertedAtMs"
end

defmodule Gamend.Realtime.V1.ChatMessage do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.ChatMessage",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, type: :string
  field :content, 2, type: :string
  field :metadata_json, 3, type: :bytes, json_name: "metadataJson"
  field :sender_id, 4, type: :string, json_name: "senderId"
  field :sender_name, 5, type: :string, json_name: "senderName"
  field :chat_type, 6, type: :string, json_name: "chatType"
  field :chat_ref_id, 7, type: :string, json_name: "chatRefId"
  field :inserted_at_ms, 8, type: :int64, json_name: "insertedAtMs"
  field :updated_at_ms, 9, proto3_optional: true, type: :int64, json_name: "updatedAtMs"
  field :sender_email, 10, proto3_optional: true, type: :string, json_name: "senderEmail"
end

defmodule Gamend.Realtime.V1.QuestProgress.ObjectiveProgressEntry do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.QuestProgress.ObjectiveProgressEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :int64
end

defmodule Gamend.Realtime.V1.QuestProgress do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.QuestProgress",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, type: :string
  field :user_id, 2, type: :string, json_name: "userId"
  field :quest_key, 3, type: :string, json_name: "questKey"
  field :period_key, 4, type: :string, json_name: "periodKey"

  field :objective_progress, 5,
    repeated: true,
    type: Gamend.Realtime.V1.QuestProgress.ObjectiveProgressEntry,
    json_name: "objectiveProgress",
    map: true

  field :status, 6, type: :string
  field :completed_at_ms, 7, proto3_optional: true, type: :int64, json_name: "completedAtMs"
  field :claimed_at_ms, 8, proto3_optional: true, type: :int64, json_name: "claimedAtMs"
  field :metadata_json, 9, type: :bytes, json_name: "metadataJson"
  field :inserted_at_ms, 10, type: :int64, json_name: "insertedAtMs"
  field :updated_at_ms, 11, type: :int64, json_name: "updatedAtMs"
end

defmodule Gamend.Realtime.V1.Lobby do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.Lobby",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, proto3_optional: true, type: :string
  field :title, 2, proto3_optional: true, type: :string
  field :host_id, 3, proto3_optional: true, type: :string, json_name: "hostId"
  field :host_name, 4, proto3_optional: true, type: :string, json_name: "hostName"
  field :hostless, 5, proto3_optional: true, type: :bool
  field :max_users, 6, proto3_optional: true, type: :int32, json_name: "maxUsers"
  field :is_hidden, 7, proto3_optional: true, type: :bool, json_name: "isHidden"
  field :is_locked, 8, proto3_optional: true, type: :bool, json_name: "isLocked"
  field :metadata_json, 9, proto3_optional: true, type: :bytes, json_name: "metadataJson"
  field :is_passworded, 10, proto3_optional: true, type: :bool, json_name: "isPassworded"
  field :slowdown, 11, proto3_optional: true, type: :int32
  field :spectator_count, 12, proto3_optional: true, type: :int32, json_name: "spectatorCount"
  field :members, 13, repeated: true, type: Gamend.Realtime.V1.UserBrief
  field :has_members, 14, proto3_optional: true, type: :bool, json_name: "hasMembers"
  field :metadata_pb, 15, proto3_optional: true, type: :bytes, json_name: "metadataPb"
end

defmodule Gamend.Realtime.V1.Group do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.Group",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, proto3_optional: true, type: :string
  field :title, 2, proto3_optional: true, type: :string
  field :description, 3, proto3_optional: true, type: :string
  field :type, 4, proto3_optional: true, type: :string
  field :max_members, 5, proto3_optional: true, type: :int32, json_name: "maxMembers"
  field :creator_id, 6, proto3_optional: true, type: :string, json_name: "creatorId"
  field :creator_name, 7, proto3_optional: true, type: :string, json_name: "creatorName"
  field :metadata_json, 8, proto3_optional: true, type: :bytes, json_name: "metadataJson"
  field :member_count, 9, proto3_optional: true, type: :int32, json_name: "memberCount"
  field :slowdown, 10, proto3_optional: true, type: :int32
  field :inserted_at_ms, 11, proto3_optional: true, type: :int64, json_name: "insertedAtMs"
  field :updated_at_ms, 12, proto3_optional: true, type: :int64, json_name: "updatedAtMs"
  field :metadata_pb, 13, proto3_optional: true, type: :bytes, json_name: "metadataPb"
end

defmodule Gamend.Realtime.V1.Party do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.Party",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, proto3_optional: true, type: :string
  field :leader_id, 2, proto3_optional: true, type: :string, json_name: "leaderId"
  field :leader_name, 3, proto3_optional: true, type: :string, json_name: "leaderName"
  field :max_size, 4, proto3_optional: true, type: :int32, json_name: "maxSize"
  field :metadata_json, 5, proto3_optional: true, type: :bytes, json_name: "metadataJson"
  field :members, 6, repeated: true, type: Gamend.Realtime.V1.UserBrief
  field :has_members, 7, proto3_optional: true, type: :bool, json_name: "hasMembers"
  field :inserted_at_ms, 8, proto3_optional: true, type: :int64, json_name: "insertedAtMs"
  field :updated_at_ms, 9, proto3_optional: true, type: :int64, json_name: "updatedAtMs"
  field :metadata_pb, 10, proto3_optional: true, type: :bytes, json_name: "metadataPb"
end

defmodule Gamend.Realtime.V1.MemberEvent do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.MemberEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :display_name, 2, proto3_optional: true, type: :string, json_name: "displayName"
  field :id, 3, proto3_optional: true, type: :string
  field :profile_url, 4, proto3_optional: true, type: :string, json_name: "profileUrl"
  field :metadata_json, 5, proto3_optional: true, type: :bytes, json_name: "metadataJson"
  field :is_online, 6, proto3_optional: true, type: :bool, json_name: "isOnline"
  field :is_activated, 7, proto3_optional: true, type: :bool, json_name: "isActivated"
  field :last_seen_at_ms, 8, proto3_optional: true, type: :int64, json_name: "lastSeenAtMs"
  field :group_id, 9, proto3_optional: true, type: :string, json_name: "groupId"
  field :metadata_pb, 10, proto3_optional: true, type: :bytes, json_name: "metadataPb"
  field :username, 11, proto3_optional: true, type: :string
end

defmodule Gamend.Realtime.V1.EntityId do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.EntityId",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, type: :string
end

defmodule Gamend.Realtime.V1.PartyRef do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.PartyRef",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :party_id, 1, type: :string, json_name: "partyId"
end

defmodule Gamend.Realtime.V1.HostChanged do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.HostChanged",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :new_host_id, 1, type: :string, json_name: "newHostId"
  field :display_name, 2, type: :string, json_name: "displayName"
end

defmodule Gamend.Realtime.V1.GroupInviteEvent do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.GroupInviteEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :group_id, 1, type: :string, json_name: "groupId"
end

defmodule Gamend.Realtime.V1.PartyInviteEvent do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.PartyInviteEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :party_id, 1, type: :string, json_name: "partyId"
  field :user_id, 2, type: :string, json_name: "userId"
end

defmodule Gamend.Realtime.V1.TournamentEvent do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.TournamentEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :tournament_id, 1, type: :string, json_name: "tournamentId"
  field :slug, 2, type: :string
  field :state, 3, type: :string
end

defmodule Gamend.Realtime.V1.TournamentMatchEvent do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.TournamentMatchEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :tournament_id, 1, type: :string, json_name: "tournamentId"
  field :slug, 2, type: :string
  field :match_id, 3, type: :string, json_name: "matchId"
  field :round, 4, type: :int32
  field :deadline_ms, 5, type: :int64, json_name: "deadlineMs"
  field :winner_entry_id, 6, type: :string, json_name: "winnerEntryId"
end

defmodule Gamend.Realtime.V1.MatchmakingFound.MatchParamsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.MatchmakingFound.MatchParamsEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Gamend.Realtime.V1.MatchmakingFound do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.MatchmakingFound",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :lobby_id, 1, type: :string, json_name: "lobbyId"

  field :match_params, 2,
    repeated: true,
    type: Gamend.Realtime.V1.MatchmakingFound.MatchParamsEntry,
    json_name: "matchParams",
    map: true
end

defmodule Gamend.Realtime.V1.ReadyCheckParticipant do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.ReadyCheckParticipant",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :display_name, 2, type: :string, json_name: "displayName"
  field :state, 3, type: :string
end

defmodule Gamend.Realtime.V1.ReadyCheckState do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.ReadyCheckState",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, type: :string
  field :kind, 2, type: :string
  field :status, 3, type: :string
  field :lobby_id, 4, type: :string, json_name: "lobbyId"
  field :deadline_ms, 5, type: :int64, json_name: "deadlineMs"
  field :total, 6, type: :int32
  field :ready_count, 7, type: :int32, json_name: "readyCount"
  field :your_state, 8, type: :string, json_name: "yourState"
  field :reason, 9, type: :string
  field :participants, 10, repeated: true, type: Gamend.Realtime.V1.ReadyCheckParticipant
  field :party_id, 11, type: :string, json_name: "partyId"
end

defmodule Gamend.Realtime.V1.KvEntry do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.KvEntry",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :user_id, 2, proto3_optional: true, type: :string, json_name: "userId"
  field :lobby_id, 3, proto3_optional: true, type: :string, json_name: "lobbyId"
  field :data_json, 4, proto3_optional: true, type: :bytes, json_name: "dataJson"
  field :metadata_json, 5, proto3_optional: true, type: :bytes, json_name: "metadataJson"
  field :data_pb, 6, proto3_optional: true, type: :bytes, json_name: "dataPb"
end

defmodule Gamend.Realtime.V1.RpcCall do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.RpcCall",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof(:args, 0)

  field :id, 1, type: :uint32
  field :plugin, 2, type: :string
  field :fn, 3, type: :string
  field :args_json, 4, type: :bytes, json_name: "argsJson", oneof: 0
  field :args_raw, 5, type: :bytes, json_name: "argsRaw", oneof: 0
end

defmodule Gamend.Realtime.V1.RpcReply do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.RpcReply",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof(:data, 0)

  field :id, 1, type: :uint32
  field :data_json, 2, type: :bytes, json_name: "dataJson", oneof: 0
  field :data_raw, 3, type: :bytes, json_name: "dataRaw", oneof: 0
end

defmodule Gamend.Realtime.V1.RpcError do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.RpcError",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :id, 1, type: :uint32
  field :error, 2, type: :string
end

defmodule Gamend.Realtime.V1.RtcEnvelope do
  @moduledoc false

  use Protobuf,
    full_name: "gamend.realtime.v1.RtcEnvelope",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof(:msg, 0)

  field :call_hook, 1, type: Gamend.Realtime.V1.RpcCall, json_name: "callHook", oneof: 0
  field :hook_reply, 2, type: Gamend.Realtime.V1.RpcReply, json_name: "hookReply", oneof: 0
  field :hook_error, 3, type: Gamend.Realtime.V1.RpcError, json_name: "hookError", oneof: 0
end
