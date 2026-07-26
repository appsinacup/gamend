---
icon: hero-bolt
---

# WebSocket Channels

Real-time features use Phoenix PubSub to broadcast events. Domain modules publish to named topics; WebSocket channels and LiveViews subscribe to receive instant updates.

## WebSocket channels

Clients connect via WebSocket and join channels to receive real-time events. Six channel types are available:

- **UserChannel** (`user:{user_id}`) — personal channel: friend updates/presence, notifications, KV subscriptions, user profile updates
- **LobbyChannel** (`lobby:{lobby_id}`) — per-lobby: member join/leave/kick, lobby settings, host changes
- **LobbiesChannel** (`lobbies`) — global lobby list: lobby created/updated/deleted/membership changed
- **GroupChannel** (`group:{group_id}`) — per-group: member join/leave/kick, promote/demote, join request decisions
- **GroupsChannel** (`groups`) — global group list: group created/updated/deleted (excludes hidden)
- **PartyChannel** (`party:{party_id}`) — per-party: member join/leave, party settings, disbanded

## Payload format: JSON (default) or Protobuf

Server-to-client event payloads are JSON by default. Sockets can opt into protobuf: mapped events then arrive as binary frames encoded per the shared wire contract in proto/gamend_realtime.proto, and the official clients decode them transparently. Client-to-server pushes remain JSON in both modes.

Raw connection URL (requires the V2 channel protocol):

```text
wss://your-server/socket/websocket?vsn=2.0.0&format=protobuf&token=...
```

```javascript
const realtime = new GameRealtime(serverUrl, token, { format: 'protobuf' })
```

```gdscript
var realtime = GamendRealtime.new(token_provider, endpoint, "protobuf")
```

- Decoded protobuf payloads keep the JSON field names, with two documented differences: timestamps are unix-millisecond integers (last_seen_at_ms, inserted_at_ms, ...) instead of ISO 8601 strings, and metadata/data values arrive already parsed.
- Every event pushed by the server is protobuf-mapped, except the webrtc:* signaling events and phx_reply payloads (join/push replies), which remain JSON. Any future unmapped event is delivered as JSON on the same socket, so coverage can grow without breaking clients.
- The format is negotiated per connection, so JSON and protobuf clients coexist freely on the same server.

**Which to choose:** keep JSON unless you have a reason not to — it is human-readable on the wire, and because WebSocket traffic is permessage-deflate compressed the real bandwidth difference on this transport is small. Choose protobuf when you want schema-enforced payload shapes, cheaper client-side decoding, or numeric timestamps; raw payloads measure 35–84% smaller (see the encoding benchmark in protobuf_bench_test.exs), which matters mainly for clients without compression support.

### Game-defined schemas: what to implement

Free-form values (metadata, KV data, hook payloads) are JSON in the database and REST API, so on protobuf sockets they normally travel as JSON bytes. To make them compact binary, your plugin's proto file implements the following messages — everything below is optional and independent, and anything you skip simply stays JSON. The admin Config page shows this coverage at a glance (Hooks section, "Protobuf schema coverage").

| You want binary… | Implement / register | Registration |
|---|---|---|
| user metadata | message UserMeta | by name, at plugin load |
| lobby metadata | message LobbyMeta | by name, at plugin load |
| group metadata | message GroupMeta | by name, at plugin load |
| party metadata | message PartyMeta | by name, at plugin load |
| a hook's request/reply | message <FnName>Request + <FnName>Reply | by name, at plugin load |
| KV data for a key | any message + kv_schemas/0 mapping | explicit: exact key or "prefix*" pattern |

KV keys are open-ended, so unlike the fixed names above there is no naming convention — the hooks module exports the mapping itself (exact keys win over prefixes, longest prefix wins). KV entry metadata always stays JSON. Overrides: metadata_schemas/0 remaps or disables the Meta conventions. Scoping: hook schemas are namespaced per plugin; metadata entities and the KV keyspace are global — explicit registrations beat conventions, and on a conflict the first plugin in name order wins (losers are logged, and an explicit nil disables an entity for the whole deployment).

```elixir
# In the plugin's hooks module — KV data schemas are explicit
def kv_schemas do
  %{"loadout" => MyGame.V1.Loadout, "match:*" => MyGame.V1.MatchState}
end

# Generate all bindings from the plugin's proto/ (one schema source):
mix plugin.gen.proto --godot-out ../../godot/addons/my_game/my_game_pb.gd \
                     --js-out ../../assets/js/my_game_pb.js
```

```proto
// my_game.proto - compiled into your plugin AND your client
message UserMeta { uint32 rank = 1; string clan = 2; }
```

Mirror the registration client-side:

```javascript
realtime.registerMetaSchema('user', UserMeta)
```

```gdscript
GamendProto.register_meta_schema("user", MyGamePb.UserMeta)
```

- Safety: if a stored metadata map does not match the registered schema (extra keys, wrong types), that push falls back to JSON — mismatches cost bytes, never data.
- Clients without a registered schema receive the raw bytes as metadata_pb and can decode them however they like.

## Event payload reference

Detailed payload shapes for every event pushed from the server to the client, grouped by channel.

### UserChannel `user:{user_id}`

| Event | When | Payload |
|---|---|---|
| updated | Profile changes, on join | {id, email, profile_url, metadata, username, display_name, lobby_id, party_id, is_online, last_seen_at, linked_providers, has_password} |
| notification_created | New notification / all on join | {id, sender_id, sender_name, recipient_id, title, content, metadata, inserted_at} |
| friend_updated | Friend presence/profile changes; full list on join | {friends: {"<user_id>": {user_id, friendship_id, id, username, display_name, profile_url, metadata, is_online, is_activated, last_seen_at}}} |
| kv_updated / kv_deleted | Subscribed KV entry changed (see kv:subscribe) | {key, user_id, lobby_id, data, metadata} / {key, user_id, lobby_id} |
| match_found | The user's matchmaking ticket matched into a lobby | {lobby_id, match_params} |
| wallet_updated | A currency balance changed | {currency, balance, delta} |
| inventory_updated | An item count changed | {item, quantity, delta} |
| tournament_updated / tournament_finished | A tournament the user entered changed state | {tournament_id, slug, state} |
| tournament_match_ready / tournament_match_resolved | The user's tournament match became playable / got a verdict | {tournament_id, slug, match_id, round, deadline, winner_entry_id} |
| chat_message_created | Friend DM received | {id, content, metadata, sender_id, sender_name, chat_type, chat_ref_id, inserted_at} |
| chat_message_updated | Friend DM edited | {id, content, metadata, sender_id, sender_name, chat_type, chat_ref_id, inserted_at} |
| chat_message_deleted | Friend DM deleted | {id} |
| quest_progress / quest_completed / quest_claimed | A quest objective advanced / completed / rewards claimed | {id, user_id, quest_key, period_key, objective_progress, status, completed_at, claimed_at, metadata, inserted_at, updated_at} |
| group_invite_accepted | Someone accepted your group invite | {group_id} |
| group_invite_cancelled | Group deleted — pending invites cancelled | {group_id, group_name} |
| group_join_request_approved | Your group join request was approved | {group_id} |
| group_join_request_rejected | Your group join request was declined | {group_id} |
| party_invite_accepted | Someone accepted your party invite | {party_id, user_id} |
| party_invite_declined | Someone declined your party invite | {party_id, user_id} |
| party_invite_cancelled | Party leader cancelled your invite | {party_id, user_id} |

Friend requests, acceptances, blocks and removals **do not** each get their own
channel event — every one of them arrives as a single `friend_updated` carrying
the refreshed friend list, plus a `notification_created` whose `metadata.type`
names what happened (`incoming_request`, `friend_accepted`, `friend_blocked`,
and so on). Handle those two events; a listener bound to `friend_accepted` on
the socket will never fire.

The UserChannel also accepts a "call_hook" push from the client to invoke server-side plugin hooks with a reply.

### LobbyChannel `lobby:{lobby_id}`

| Event | When | Payload |
|---|---|---|
| updated | Lobby settings changed, on join | {id, title, host_id, host_name, hostless, max_users, is_hidden, is_locked, metadata, members (+ spectator on join)} |
| user_joined | A user joined the lobby | {user_id, id, username, display_name, profile_url, metadata, is_online, is_activated, last_seen_at} |
| user_left | A user left the lobby | {user_id, display_name} |
| user_kicked | A user was kicked | {user_id, display_name} |
| host_changed | Lobby host changed | {new_host_id, display_name} |
| user_online | A lobby member came online | {user_id, id, username, display_name, profile_url, metadata, is_online, is_activated, last_seen_at} |
| user_offline | A lobby member went offline | {user_id, id, username, display_name, profile_url, metadata, is_online, is_activated, last_seen_at} |
| user_updated | A lobby member was updated | {user_id, id, username, display_name, profile_url, metadata, is_online, is_activated, last_seen_at} |
| chat_message_created | New lobby chat message | {id, content, metadata, sender_id, sender_name, chat_type, chat_ref_id, inserted_at} |
| chat_message_updated | Lobby chat message edited | {id, content, metadata, sender_id, sender_name, chat_type, chat_ref_id, inserted_at} |
| chat_message_deleted | Lobby chat message deleted | {id} |
| state_changed | The lobby moved to another lifecycle state | {lobby_id, from, to, state_changed_at} |
| ready_check_started / ready_check_updated / ready_check_passed / ready_check_failed | A ready check opened, someone answered, or it resolved | The ready check with its participants |

### LobbiesChannel `lobbies`

| Event | When | Payload |
|---|---|---|
| lobby_created | New lobby created | {id, title, host_id, host_name, hostless, max_users, is_hidden, is_locked, metadata, is_passworded} |
| lobby_updated | Lobby settings changed | {id, title, host_id, host_name, hostless, max_users, is_hidden, is_locked, metadata, is_passworded} |
| lobby_deleted | Lobby deleted | {id} |
| lobby_membership_changed | Member count changed | {id} |

### GroupChannel `group:{group_id}`

| Event | When | Payload |
|---|---|---|
| updated | Group settings changed, on join | {id, title, description, type, max_members, creator_id, creator_name, metadata} |
| member_joined | New member joined | {group_id, user_id, display_name} |
| member_left | Member left | {group_id, user_id, display_name} |
| member_kicked | Member kicked | {group_id, user_id, display_name} |
| member_promoted | Member promoted to admin | {group_id, user_id, display_name} |
| member_demoted | Admin demoted to member | {group_id, user_id, display_name} |
| member_online | A group member came online | {user_id, is_online: true} |
| member_offline | A group member went offline | {user_id, is_online: false} |
| join_request_approved | Join request approved by admin | {group_id, user_id, display_name} |
| join_request_rejected | Join request rejected by admin | {group_id, user_id, display_name} |
| member_updated | A group member was updated | {user_id, id, username, display_name, profile_url, metadata, is_online, is_activated, last_seen_at} |
| chat_message_created | New group chat message | {id, content, metadata, sender_id, sender_name, chat_type, chat_ref_id, inserted_at} |
| chat_message_updated | Group chat message edited | {id, content, metadata, sender_id, sender_name, chat_type, chat_ref_id, inserted_at} |
| chat_message_deleted | Group chat message deleted | {id} |

### GroupsChannel `groups`

| Event | When | Payload |
|---|---|---|
| group_created | New group created (excludes hidden) | {id, title, description, type, max_members, creator_id, creator_name, metadata} |
| group_updated | Group settings changed (excludes hidden) | {id, title, description, type, max_members, creator_id, creator_name, metadata} |
| group_deleted | Group deleted | {id} |

### PartyChannel `party:{party_id}`

| Event | When | Payload |
|---|---|---|
| updated | Party settings changed, on join | {id, leader_id, leader_name, max_size, metadata, members} |
| member_joined | User joined the party | {user_id, id, username, display_name, profile_url, metadata, is_online, is_activated, last_seen_at} |
| member_left | User left the party | {user_id, display_name} |
| disbanded | Party was disbanded | {party_id} |
| member_online | A party member came online | {user_id, id, username, display_name, profile_url, metadata, is_online, is_activated, last_seen_at} |
| member_offline | A party member went offline | {user_id, id, username, display_name, profile_url, metadata, is_online, is_activated, last_seen_at} |
| member_updated | A party member was updated | {user_id, id, username, display_name, profile_url, metadata, is_online, is_activated, last_seen_at} |
| chat_message_created | New party chat message | {id, content, metadata, sender_id, sender_name, chat_type, chat_ref_id, inserted_at} |
| chat_message_updated | Party chat message edited | {id, content, metadata, sender_id, sender_name, chat_type, chat_ref_id, inserted_at} |
| chat_message_deleted | Party chat message deleted | {id} |

## How it works

```text
  Domain module (e.g. Lobbies)
       │
       ├── performs DB operation
       │
       └── Phoenix.PubSub.broadcast("lobby:42", {:lobby_user_joined, user})
                │
                ▼
         ┌──────────────────┐
         │  Phoenix PubSub  │  (in-memory, distributed in cluster)
         └──────┬───────────┘
                │
           ┌────┴────┐
           ▼         ▼
      LobbyChannel   Admin LiveView
      (sends JSON    (updates UI
       to client)     via stream)
```

## Notes

- All broadcasts are fire-and-forget — subscribers don't acknowledge receipt
- In a cluster, PubSub automatically distributes messages across nodes via pg2/Phoenix.PubSub.PG2
- WebSocket connections are authenticated via JWT token on join
- Friend DMs are broadcast to both the sorted-pair topic and each user's personal topic, so the recipient receives the message even without subscribing to the friend chat topic directly.
- Clients that cache messages locally can update in place: `chat_message_updated`
  carries the full message, and `chat_message_deleted` carries only its `id`.

## Chat Notifications

When a new chat message is sent, a notification is automatically created for recipients:

- **Friend DM:** One consolidated notification per user: "New messages from friends"
- **Group message:** One notification per group: "New messages from {group_name}". Sent to all group members except sender.
- **Lobby message:** One notification per lobby: "New messages from {lobby_name}". Sent to all lobby members except sender.

Notifications use upsert semantics — multiple messages update the existing notification with the latest content rather than creating duplicates.

## Quest Completion Notifications

When a user completes a quest, a notification is automatically created:

- **Title:** "Quest completed: " ("Achievement unlocked: " for quests categorised `achievement`)
- **Metadata:** `{type: "quest_completed", quest_key, category, quest_title}`

Progress increments do not generate notifications — only completion does. The notification is a self-notification (sender = recipient) since it is system-generated.
