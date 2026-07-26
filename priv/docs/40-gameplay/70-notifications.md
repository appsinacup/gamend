---
icon: hero-bell
---

# Notifications

The notification system delivers real-time and persistent notifications for social events (friend requests, group invites, party actions), chat messages, and custom payloads. Every system-generated notification includes a metadata.type tag for client-side routing and filtering.

## API Endpoints

Endpoints are under `/api/v1/notifications` - see [/api/docs](/api/docs).

There is deliberately **no** "mark as read" endpoint. Reading is server-side:
the web UI and `Notifications.mark_all_notifications_read/1` set the flag, so a
game client tracks its own seen state or deletes what it has handled.

## Notification Schema

```text
  id": 1, "sender_id": 42, "sender_name": "SomePlayer", "recipient_id": "01977f5a-0007-7000-8000-3f6a2d8c0a07", "title": "New Group Invite", "content": "You've been invited to join Cool Guild", "metadata": { "type": "group_invite", "group_id": "01977f5a-0005-7000-8000-3f6a2d8c0a05,
    "inserted_at":  "2026-02-22T12:00:00Z"
  }
```

## Notification Types (metadata.type)

All system-generated notifications include a type string in metadata for client-side routing. Below is the full list grouped by domain.

### Friends

```text
  ┌──────────────────────┬──────────────────────────────────────────────┐
  │ Type                 │ Description                                  │
  ├──────────────────────┼──────────────────────────────────────────────┤
  │ friend_request       │ New incoming friend request                  │
  │ friend_accepted      │ Your friend request was accepted             │
  │ friend_rejected      │ Your friend request was declined             │
  └──────────────────────┴──────────────────────────────────────────────┘
```

### Groups

```text
  ┌──────────────────────┬──────────────────────────────────────────────┐
  │ Type                 │ Description                                  │
  ├──────────────────────┼──────────────────────────────────────────────┤
  │ group_invite         │ Invited to join a group                      │
  │ group_invite_accepted│ Your group invite was accepted               │
  │ group_invite_declined│ Your group invite was declined               │
  │ group_join_request   │ Someone requested to join your group (admin) │
  │ group_join_request_approved  │ Your group join request was approved          │
  │ group_join_request_rejected  │ Your group join request was declined          │
  │ group_kicked         │ You were removed from a group                │
  │ group_promoted       │ You were promoted to admin                   │
  │ group_demoted        │ You were demoted to member                   │
  └──────────────────────┴──────────────────────────────────────────────┘
```

### Parties

```text
  ┌──────────────────────┬──────────────────────────────────────────────┐
  │ Type                 │ Description                                  │
  ├──────────────────────┼──────────────────────────────────────────────┤
  │ party_invite         │ Invited to join a party                      │
  │ party_invite_accepted│ Your party invite was accepted               │
  │ party_invite_declined│ Your party invite was declined               │
  │ party_kicked         │ You were removed from a party                │
  └──────────────────────┴──────────────────────────────────────────────┘
```

### Lobbies

```text
  ┌──────────────────────┬──────────────────────────────────────────────┐
  │ Type                 │ Description                                  │
  ├──────────────────────┼──────────────────────────────────────────────┤
  │ lobby_kicked         │ You were removed from a lobby                │
  └──────────────────────┴──────────────────────────────────────────────┘
```

### Chat

Chat notifications include a message_count field in metadata indicating how many unread messages triggered the notification.

```text
  ┌──────────────────────┬──────────────────────────────────────────────┐
  │ Type                 │ Description                                  │
  ├──────────────────────┼──────────────────────────────────────────────┤
  │ chat_friend          │ New friend DM messages                       │
  │ chat_group           │ New group chat messages                      │
  │ chat_lobby           │ New lobby chat messages                      │
  │ chat_party           │ New party chat messages                      │
  └──────────────────────┴──────────────────────────────────────────────┘
```

## Behaviour Notes

- Notifications upsert on (sender_id, recipient_id, title) — sending the same notification again updates the existing one.
- Cancelling a friend request, group invite, or party invite automatically retracts (deletes) the original notification.
- Notifications are delivered in real-time via PubSub on the "user:" topic and persisted to the database.
- Custom notifications can be sent between friends via POST /api/v1/notifications with any title, content, and metadata.

## Real-time (WebSocket)

Connect to the UserChannel to receive notifications in real-time. Notifications are broadcast on the "user:" topic.

```javascript
  // JavaScript — join the user channel
  const channel = socket.channel("user:" + userId, {});
  channel.on("notification", (payload) => {
    console.log("New notification:", payload.type, payload);
  });
```

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`GameServer.Notifications`](https://appsinacup.com/game_server/GameServer.Notifications.html) - the functions a plugin calls, with their
  signatures and docs.
