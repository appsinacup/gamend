# WebRTC Lobby Hook

Keeps a Phoenix WebRTC signaling room in sync with a game lobby. When a lobby has WebRTC enabled in its metadata, this hook automatically creates, updates and tears down a matching signaling room managed by the SignalingBroker.

## What it does

- Creates a signaling room automatically when a WebRTC-enabled lobby is created.
- Closes the signaling room when the lobby is deleted.
- Syncs the allowed-user list with lobby joins and leaves.
- Notifies the designated star-topology host so a headless server can join the signaling channel automatically.
- Supports late joins and role assignment (host, client, peer).

## Supported topologies

| Topology | Behaviour |
|---|---|
| star | One host and many clients. The host is notified via user:<id> with webrtc:room_ready. Clients send offers to the host. |
| mesh | All participants are peers. No automatic host notification. |

## Lobby metadata configuration

Set metadata.webrtc on the lobby:

```Elixir
%{
  "webrtc" => %{
    "enabled" => true,
    "topology" => "star",
    "host_user_id" => "star-topology-server-user-id",
    "late_join" => true,
    "reconnect_timeout" => 30000
  }
}
```

### Options

- enabled — Set to true to create the signaling room.
- topology — star or mesh.
- host_user_id — Optional. In star mode this user is assigned the :host role. Falls back to lobby.host_id.
- late_join — Allow users who join the lobby later to enter the signaling room. Defaults to true.
- reconnect_timeout — Grace period for disconnected peers in milliseconds. Defaults to 30000.

## Hook callbacks

| Callback | Purpose |
|---|---|
| before_lobby_create/1 | Injects default WebRTC metadata into lobby attributes if missing. |
| after_lobby_create/1 | Creates the signaling room and seeds the allowed-user list from lobby members. |
| after_lobby_updated/1 | Creates or closes the room if WebRTC is toggled. |
| after_lobby_deleted/1 | Closes the signaling room. |
| after_lobby_join/2 | Allows the joining user into the signaling room with the correct role. |
| after_lobby_leave/2 | Removes the user from the signaling room. |
| after_lobby_host_change/2 | Updates the star host and notifies the new host. |

## Star topology specifics

1. The host is resolved in this order: metadata.webrtc.host_user_id -> lobby.host_id.
2. The host is always added to the allowed-user list even if it is not a lobby member (useful for headless servers).
3. When the room is created, the host receives a broadcast on user:<host_user_id>:

```Elixir
%{
  "lobby_id" => lobby_id,
  "topology" => "star",
  "host_user_id" => host_user_id,
  "signaling_topic" => "signaling:#{lobby_id}"
}
```

## Role assignment

Roles are assigned automatically:

- star + matching host ID -> :host
- star + anyone else -> :client
- mesh -> :peer

The SignalingBroker uses these roles to enforce who can send offers and answers.

## Notes

- The hook normalizes all metadata keys to strings so that Phoenix changesets and Ecto interop cleanly.
- The signaling room ID is the same as the lobby ID, so they are always 1-to-1.
- If the signaling room already exists when a lobby is updated, the hook leaves it alone.
