defmodule GameServerWeb.EventCodec do
  @moduledoc """
  Encodes realtime channel event payloads as protobuf for sockets connected
  with `?format=protobuf` (see `proto/gamend_realtime.proto`, the wire
  contract shared with all clients).

  `encode/3` is the single source of truth for the event → message mapping.
  Events without a mapping return `:json` and are delivered as regular JSON,
  so protobuf coverage can grow event by event without breaking clients.

  Transforms relative to the JSON payloads (documented in the proto file):
  timestamps become unix milliseconds, arbitrary JSON values (metadata, KV
  data) become JSON-encoded bytes.
  """

  require Logger

  alias Gamend.Realtime.V1, as: PB
  alias GameServer.Hooks.KvSchemas
  alias GameServer.Hooks.MetadataSchemas

  @doc """
  Encodes `payload` for `event` pushed on `topic`.

  Returns `{:ok, iodata}` or `:json` when the event has no protobuf mapping.
  """
  @spec encode(String.t(), String.t(), map()) :: {:ok, iodata()} | :json
  def encode(topic, event, payload) do
    case message_for(topic_kind(topic), event, payload) do
      nil -> :json
      msg -> {:ok, Protobuf.encode_to_iodata(msg)}
    end
  rescue
    # Never let a malformed payload kill the channel; JSON is always valid.
    error ->
      Logger.warning("EventCodec failed to encode #{event}: #{Exception.message(error)}")
      :json
  end

  defp topic_kind(topic) do
    case String.split(topic, ":", parts: 2) do
      [kind, _] -> kind
      [kind] -> kind
    end
  end

  # ── Event → message mapping ────────────────────────────────────────────

  defp message_for("user", "updated", p), do: user(p)
  defp message_for("user", "friend_updated", p), do: friend_update(p)
  defp message_for(_, "kv_updated", p), do: kv_entry(p)
  defp message_for(_, "kv_deleted", p), do: kv_entry(p)
  defp message_for(_, "notification_created", p), do: notification(p)
  defp message_for(_, "chat_message_created", p), do: chat_message(p)
  defp message_for(_, "chat_message_updated", p), do: chat_message(p)
  defp message_for(_, "chat_message_deleted", p), do: %PB.EntityId{id: get(p, :id)}
  defp message_for(_, "quest_progress", p), do: quest_progress(p)
  defp message_for(_, "quest_completed", p), do: quest_progress(p)
  defp message_for(_, "quest_claimed", p), do: quest_progress(p)

  defp message_for("lobby", "updated", p), do: lobby(p)

  defp message_for("lobby", event, p)
       when event in ~w(user_joined user_left user_kicked user_online user_offline),
       do: member_event(p)

  defp message_for("lobby", "host_changed", p),
    do: %PB.HostChanged{
      new_host_id: get(p, :new_host_id),
      display_name: get(p, :display_name) || ""
    }

  defp message_for("lobby", "user_updated", p), do: user_brief(p)

  defp message_for(kind, "member_updated", p) when kind in ~w(group party),
    do: user_brief(p)

  defp message_for("lobbies", event, p) when event in ~w(lobby_created lobby_updated),
    do: lobby(p)

  defp message_for("lobbies", event, p) when event in ~w(lobby_deleted lobby_membership_changed),
    do: %PB.EntityId{id: get(p, :id)}

  defp message_for("group", "updated", p), do: group(p)

  defp message_for("group", event, p)
       when event in ~w(member_joined member_left member_kicked member_promoted member_demoted
                        join_request_approved join_request_rejected member_online member_offline),
       do: member_event(p)

  defp message_for("groups", event, p) when event in ~w(group_created group_updated),
    do: group(p)

  defp message_for("groups", "group_deleted", p), do: %PB.EntityId{id: get(p, :id)}

  defp message_for("party", "updated", p), do: party(p)

  defp message_for("party", event, p)
       when event in ~w(member_joined member_left member_online member_offline),
       do: member_event(p)

  defp message_for("party", "disbanded", p), do: %PB.PartyRef{party_id: get(p, :party_id)}

  defp message_for("user", event, p)
       when event in ~w(group_invite_accepted group_invite_cancelled group_join_request_approved group_join_request_rejected),
       do: %PB.GroupInviteEvent{group_id: get(p, :group_id)}

  defp message_for("user", event, p)
       when event in ~w(party_invite_accepted party_invite_declined party_invite_cancelled),
       do: %PB.PartyInviteEvent{party_id: get(p, :party_id), user_id: get(p, :user_id) || ""}

  defp message_for("user", event, p)
       when event in ~w(tournament_updated tournament_finished),
       do: %PB.TournamentEvent{
         tournament_id: get(p, :tournament_id),
         slug: get(p, :slug) || "",
         state: get(p, :state) || ""
       }

  defp message_for("user", event, p)
       when event in ~w(tournament_match_ready tournament_match_resolved),
       do: %PB.TournamentMatchEvent{
         tournament_id: get(p, :tournament_id),
         slug: get(p, :slug) || "",
         match_id: get(p, :match_id),
         round: get(p, :round),
         deadline_ms: ms(p, :deadline_at),
         winner_entry_id: get(p, :winner_entry_id) || ""
       }

  defp message_for(_kind, event, p)
       when event in ~w(ready_check_started ready_check_updated ready_check_passed ready_check_failed),
       do: ready_check(p)

  defp message_for("user", "match_found", p),
    do: %PB.MatchmakingFound{
      lobby_id: get(p, :lobby_id),
      match_params: stringify_map(get(p, :match_params) || %{})
    }

  defp message_for(_kind, _event, _payload), do: nil

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  # ── Message builders (absent map keys stay unset) ──────────────────────

  defp user(p) do
    {meta_json, meta_pb} = metadata(p, :user)

    %PB.User{
      id: get(p, :id),
      email: get(p, :email),
      profile_url: get(p, :profile_url),
      metadata_json: meta_json,
      metadata_pb: meta_pb,
      display_name: get(p, :display_name),
      lobby_id: get(p, :lobby_id),
      party_id: get(p, :party_id),
      is_online: get(p, :is_online),
      last_seen_at_ms: ms(p, :last_seen_at),
      linked_providers: linked_providers(get(p, :linked_providers)),
      has_password: get(p, :has_password),
      username: get(p, :username)
    }
  end

  defp friend_update(p) do
    friends = get(p, :friends) || %{}

    %PB.FriendUpdate{
      friends: Map.new(friends, fn {id, friend} -> {to_string(id), user(friend)} end)
    }
  end

  defp user_brief(p) do
    {meta_json, meta_pb} = metadata(p, :user)

    %PB.UserBrief{
      id: get(p, :id),
      display_name: get(p, :display_name),
      profile_url: get(p, :profile_url),
      metadata_json: meta_json,
      metadata_pb: meta_pb,
      is_online: get(p, :is_online),
      is_activated: get(p, :is_activated),
      last_seen_at_ms: ms(p, :last_seen_at),
      username: get(p, :username)
    }
  end

  defp member_event(p) do
    {meta_json, meta_pb} = metadata(p, :user)

    %PB.MemberEvent{
      user_id: get(p, :user_id),
      display_name: get(p, :display_name),
      id: get(p, :id),
      profile_url: get(p, :profile_url),
      metadata_json: meta_json,
      metadata_pb: meta_pb,
      is_online: get(p, :is_online),
      is_activated: get(p, :is_activated),
      last_seen_at_ms: ms(p, :last_seen_at),
      group_id: get(p, :group_id),
      username: get(p, :username)
    }
  end

  defp notification(p) do
    %PB.Notification{
      id: get(p, :id),
      sender_id: get(p, :sender_id) || "",
      sender_name: get(p, :sender_name) || "",
      recipient_id: get(p, :recipient_id),
      title: get(p, :title),
      content: get(p, :content) || "",
      metadata_json: json_bytes(p, :metadata) || "",
      inserted_at_ms: ms(p, :inserted_at) || 0
    }
  end

  defp chat_message(p) do
    %PB.ChatMessage{
      id: get(p, :id),
      content: get(p, :content),
      metadata_json: json_bytes(p, :metadata) || "",
      sender_id: get(p, :sender_id) || "",
      sender_name: get(p, :sender_name) || "",
      chat_type: get(p, :chat_type),
      chat_ref_id: get(p, :chat_ref_id),
      inserted_at_ms: ms(p, :inserted_at) || 0,
      updated_at_ms: ms(p, :updated_at),
      sender_email: get(p, :sender_email)
    }
  end

  # `participants` is absent on an accept check by design — the serializer only
  # includes it for kind "ready", so a pending match keeps its roster private.
  defp ready_check(p) do
    %PB.ReadyCheckState{
      id: get(p, :id),
      kind: get(p, :kind),
      status: get(p, :status),
      lobby_id: get(p, :lobby_id) || "",
      party_id: get(p, :party_id) || "",
      deadline_ms: ms(p, :deadline_at) || 0,
      total: get(p, :total) || 0,
      ready_count: get(p, :ready_count) || 0,
      your_state: get(p, :your_state) || "",
      reason: get(p, :reason) || "",
      participants: Enum.map(get(p, :participants) || [], &ready_check_participant/1)
    }
  end

  defp ready_check_participant(p) do
    %PB.ReadyCheckParticipant{
      user_id: get(p, :user_id),
      display_name: get(p, :display_name) || "",
      state: get(p, :state)
    }
  end

  defp quest_progress(p) do
    %PB.QuestProgress{
      id: get(p, :id),
      user_id: get(p, :user_id),
      quest_key: get(p, :quest_key),
      period_key: get(p, :period_key),
      objective_progress: get(p, :objective_progress) || %{},
      status: get(p, :status),
      completed_at_ms: ms(p, :completed_at),
      claimed_at_ms: ms(p, :claimed_at),
      metadata_json: json_bytes(p, :metadata) || "",
      inserted_at_ms: ms(p, :inserted_at) || 0,
      updated_at_ms: ms(p, :updated_at) || 0
    }
  end

  defp lobby(p) do
    {members, has_members} = members(p)
    {meta_json, meta_pb} = metadata(p, :lobby)

    %PB.Lobby{
      id: get(p, :id),
      title: get(p, :title),
      host_id: get(p, :host_id),
      host_name: get(p, :host_name),
      hostless: get(p, :hostless),
      max_users: get(p, :max_users),
      is_hidden: get(p, :is_hidden),
      is_locked: get(p, :is_locked),
      metadata_json: meta_json,
      metadata_pb: meta_pb,
      is_passworded: get(p, :is_passworded),
      slowdown: get(p, :slowdown),
      spectator_count: get(p, :spectator_count),
      members: members,
      has_members: has_members
    }
  end

  defp group(p) do
    {meta_json, meta_pb} = metadata(p, :group)

    %PB.Group{
      id: get(p, :id),
      title: get(p, :title),
      description: get(p, :description),
      type: get(p, :type),
      max_members: get(p, :max_members),
      creator_id: creator_id(get(p, :creator_id)),
      creator_name: get(p, :creator_name),
      metadata_json: meta_json,
      metadata_pb: meta_pb,
      member_count: get(p, :member_count),
      slowdown: get(p, :slowdown),
      inserted_at_ms: ms(p, :inserted_at),
      updated_at_ms: ms(p, :updated_at)
    }
  end

  defp party(p) do
    {members, has_members} = members(p)
    {meta_json, meta_pb} = metadata(p, :party)

    %PB.Party{
      id: get(p, :id),
      leader_id: get(p, :leader_id),
      leader_name: get(p, :leader_name),
      max_size: get(p, :max_size),
      metadata_json: meta_json,
      metadata_pb: meta_pb,
      members: members,
      has_members: has_members,
      inserted_at_ms: ms(p, :inserted_at),
      updated_at_ms: ms(p, :updated_at)
    }
  end

  defp kv_entry(p) do
    key = get(p, :key)
    {data_json, data_pb} = kv_data(p, key)

    %PB.KvEntry{
      key: key,
      user_id: get(p, :user_id),
      lobby_id: get(p, :lobby_id),
      data_json: data_json,
      data_pb: data_pb,
      metadata_json: json_bytes(p, :metadata)
    }
  end

  # KV data encodes through the plugin-registered schema for the key when it
  # fits (same never-drop-data rule as entity metadata), otherwise JSON.
  defp kv_data(p, key) do
    if Map.has_key?(p, :data) or Map.has_key?(p, "data") do
      value = get(p, :data)

      case KvSchemas.module_for(key) do
        nil ->
          {Jason.encode!(value), nil}

        mod ->
          with true <- keys_known?(value, mod),
               {:ok, struct} <- Protobuf.JSON.from_decoded(value, mod) do
            {nil, Protobuf.encode(struct)}
          else
            _ -> {Jason.encode!(value), nil}
          end
      end
    else
      {nil, nil}
    end
  rescue
    _ -> {Jason.encode!(get(p, :data)), nil}
  end

  defp linked_providers(nil), do: nil

  defp linked_providers(lp) do
    %PB.LinkedProviders{
      google: get(lp, :google) || false,
      facebook: get(lp, :facebook) || false,
      discord: get(lp, :discord) || false,
      apple: get(lp, :apple) || false,
      steam: get(lp, :steam) || false,
      device: get(lp, :device) || false
    }
  end

  defp members(p) do
    case get(p, :members) do
      nil -> {[], nil}
      members -> {Enum.map(members, &user_brief/1), true}
    end
  end

  # Group creator_id serializes as -1 when nil (see Serializers.response_id/1).
  defp creator_id(-1), do: ""
  defp creator_id(id), do: id

  # ── Value helpers ──────────────────────────────────────────────────────

  # Payload maps use atom keys in-process but may arrive with string keys
  # after crossing PubSub in serialized form.
  defp get(p, key) do
    case Map.fetch(p, key) do
      {:ok, v} -> v
      :error -> Map.get(p, Atom.to_string(key))
    end
  end

  # Encodes an entity metadata field, preserving key presence. Returns
  # {metadata_json, metadata_pb}; when the game plugin registered a schema
  # for the entity and the stored map matches it, the compact protobuf form
  # is used, otherwise JSON (mismatches must never drop data).
  defp metadata(p, entity) do
    if Map.has_key?(p, :metadata) or Map.has_key?(p, "metadata") do
      map = get(p, :metadata)

      case MetadataSchemas.module_for(entity) do
        nil ->
          {Jason.encode!(map), nil}

        mod ->
          # Protobuf.JSON silently drops unknown JSON keys, so top-level keys
          # are checked explicitly: metadata that doesn't fit the schema must
          # fall back to JSON rather than lose data.
          with true <- keys_known?(map, mod),
               {:ok, struct} <- Protobuf.JSON.from_decoded(map, mod) do
            {nil, Protobuf.encode(struct)}
          else
            _ -> {Jason.encode!(map), nil}
          end
      end
    else
      {nil, nil}
    end
  rescue
    _ -> {Jason.encode!(get(p, :metadata)), nil}
  end

  defp keys_known?(map, mod) when is_map(map) do
    known =
      mod.__message_props__().field_props
      |> Map.values()
      |> Enum.flat_map(&[&1.name, &1.json_name])
      |> MapSet.new()

    Enum.all?(Map.keys(map), &MapSet.member?(known, to_string(&1)))
  end

  defp keys_known?(_map, _mod), do: false

  # JSON-encodes an arbitrary value field, preserving key presence.
  defp json_bytes(p, key) do
    if Map.has_key?(p, key) or Map.has_key?(p, Atom.to_string(key)) do
      Jason.encode!(get(p, key))
    else
      nil
    end
  end

  # Converts a timestamp field to unix milliseconds, preserving presence.
  defp ms(p, key), do: to_ms(get(p, key))

  defp to_ms(nil), do: nil
  defp to_ms(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)

  defp to_ms(%NaiveDateTime{} = dt),
    do: dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)

  defp to_ms(bin) when is_binary(bin) do
    case DateTime.from_iso8601(bin) do
      {:ok, dt, _offset} -> DateTime.to_unix(dt, :millisecond)
      _ -> nil
    end
  end

  defp to_ms(int) when is_integer(int), do: int
end
