---
icon: hero-bell-solid
---

# Notifications

The notification system delivers real-time and persistent notifications for social events (friend requests, group invites, party actions), chat messages, and custom payloads. Every system-generated notification includes a metadata.type tag for client-side routing and filtering.

## API endpoints

Endpoints are under `/api/v1/notifications` - see [/api/docs](/api/docs).

There is deliberately **no** "mark as read" endpoint. Reading is server-side:
the web UI and `Notifications.mark_all_notifications_read/1` set the flag, so a
game client tracks its own seen state or deletes what it has handled.

## The notifications page

`/notifications` shows one section per notification group, the one with the newest notice first, and stacks those of one `metadata.type`. A notice in no group goes under Other. A plugin type's description (`notification_types/0`) is its stack's heading. A section or a stack deletes as a whole. The API answers a flat list, each notification with its `group` (empty for none), so a game client arranges them the same way: sections by `group`, stacks by `metadata.type`.

## Notification schema

```json
{
  "id": "01977f5a-0009-7000-8000-3f6a2d8c0a09",
  "sender_id": "01977f5a-0001-7000-8000-3f6a2d8c0a01",
  "sender_name": "SomePlayer",
  "recipient_id": "01977f5a-0007-7000-8000-3f6a2d8c0a07",
  "title": "New Group Invite",
  "content": "You've been invited to join Cool Guild",
  "icon_url": "",
  "group": "social",
  "metadata": {"type": "group_invite", "group_id": "01977f5a-0005-7000-8000-3f6a2d8c0a05"},
  "inserted_at": "2026-02-22T12:00:00Z"
}
```

## Notification types (metadata.type)

All system-generated notifications include a type string in metadata for client-side routing. The set is closed: core's codes are below, plugins add theirs with `notification_types/0` (see [server scripting](/docs/server-scripting)), and a notification whose `metadata.type` is neither is rejected when it is written. The admin Runtime page lists every registered code. Below is core's list grouped by domain.

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
  ┌─────────────────────────────┬──────────────────────────────────────────────┐
  │ Type                        │ Description                                  │
  ├─────────────────────────────┼──────────────────────────────────────────────┤
  │ group_invite                │ Invited to join a group                      │
  │ group_invite_accepted       │ Your group invite was accepted               │
  │ group_invite_declined       │ Your group invite was declined               │
  │ group_join_request          │ Someone requested to join your group (admin) │
  │ group_join_request_approved │ Your group join request was approved         │
  │ group_join_request_rejected │ Your group join request was declined         │
  │ group_kicked                │ You were removed from a group                │
  │ group_deleted               │ A group you were in was deleted by an admin  │
  │ group_promoted              │ You were promoted to admin                   │
  │ group_demoted               │ You were demoted to member                   │
  └─────────────────────────────┴──────────────────────────────────────────────┘
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

### Chat moderation

```text
  ┌──────────────────────┬──────────────────────────────────────────────┐
  │ Type                 │ Description                                  │
  ├──────────────────────┼──────────────────────────────────────────────┤
  │ chat_report          │ A chat report is waiting (sent to admins)    │
  │ chat_report_resolved │ A report you filed was reviewed              │
  │ chat_warning         │ A moderator sent you a warning               │
  │ chat_mute            │ You were muted in chat                       │
  └──────────────────────┴──────────────────────────────────────────────┘
```

### Quests

```text
  ┌──────────────────────┬──────────────────────────────────────────────┐
  │ Type                 │ Description                                  │
  ├──────────────────────┼──────────────────────────────────────────────┤
  │ quest_completed      │ A quest or achievement was completed         │
  └──────────────────────┴──────────────────────────────────────────────┘
```

`quest_completed` carries `quest_key`, `category` and `quest_title`.

### Reports

```text
  ┌──────────────────────┬──────────────────────────────────────────────┐
  │ Type                 │ Description                                  │
  ├──────────────────────┼──────────────────────────────────────────────┤
  │ report               │ A report is waiting for review (admins)      │
  │ report_resolved      │ A report you filed was reviewed              │
  └──────────────────────┴──────────────────────────────────────────────┘
```

## Behaviour notes

- Notifications upsert on (sender_id, recipient_id, title): sending the same notification again updates the existing one.
- Cancelling a friend request, group invite, or party invite automatically retracts (deletes) the original notification.
- Notifications are delivered in real time via PubSub on the "user:" topic and persisted to the database.
- Custom notifications can be sent between friends via POST /api/v1/notifications with any title, content, and metadata. A `metadata.type`, if present, must be a registered code.

## What each user gets, and where

A user chooses per **group** and per **channel** (`in_app`, `email`, `push`) on the settings page's Notifications tab, and can turn off all email, all push, or everything. `Gamend.Notifications.Preferences` holds the choices in the user's private `preferences` (never in `metadata`, which friends and lobbies see).

| Group | Types | Default | The user may change |
|---|---|---|---|
| `account` | sign-in links, email changes | email | nothing: it is how the account works |
| `social` | `friend_*`, `group_*`, `party_*`, `lobby_kicked` | in-app + push | email, push |
| `chat` | `chat_friend`, `chat_group`, `chat_lobby`, `chat_party` | in-app + push | push |
| `quests` | `quest_completed` | in-app | push |
| `reports` | `report_resolved`, `chat_report_resolved`, `chat_warning`, `chat_mute` | in-app + email + push, email weekly but for a warning or mute | email, push |
| `moderation` | `report`, `chat_report` (admins only, chosen on `/admin/notifications`) | in-app + email + push | email, push |
| `payments` | an entitlement granted with `notify: true` ([payments](../50-monetization/10-payments.md)) | in-app + email | email, push |

A type in no group (a moderator's notice) is always pushed. A host adds its own groups in config:

```elixir
config :gamend_core, :notification_groups, [
  %{key: "streak", label: "Streak about to end",
    defaults: %{"in_app" => true, "email" => false, "push" => false},
    types: []}
]
```

`configurable` (default: all three channels) limits what the user may change.

To send one, the server calls `Gamend.Notifications.notify(user_id, group, attrs)` with `"title"`, `"content"`, an optional `"url"` (a path on the site, shown as the notification's Open button) and optional `"subject"`/`"text"` for the email. Each channel the user left on gets it: the in-app row (sender = recipient, so a repeated title refreshes one row), a push, and an email job (`GamendWeb.Workers.NotificationEmail`, on the `mailers` queue). The email ends with a one-click unsubscribe link and carries `List-Unsubscribe` + `List-Unsubscribe-Post` headers, so a mail client's own Unsubscribe button works.

A group whose notices come in runs batches its email: `email_every: :day`, `:week` or `:month` keeps each notice (`Gamend.Notifications.Digest`, table `notification_digest_items`) until that long after the oldest one, and one email lists them (`GamendWeb.Workers.NotificationDigest`, queued by an hourly sweep). A lone notice keeps its own subject. The in-app row and the push stay instant. `email_now: ["chat_warning"]` lists the types that keep their own email; a `notify/3` call says the same with `"email_now" => true`.

A user's time zone (taken from the browser) and last site language are saved alongside: `Gamend.Accounts.TimeZone` gives "their day" and "their evening" for a reminder, `Gamend.Accounts.Preferences.locale/1` the language to write it in.

## Real-time (WebSocket)

Connect to the UserChannel to receive notifications in real time. Each one arrives as a `notification_created` event on the "user:" topic; on join the channel replays the most recent 50, oldest first.

```javascript
  // JavaScript — join the user channel
  const channel = socket.channel("user:" + userId, {});
  channel.on("notification_created", (payload) => {
    console.log("New notification:", payload.metadata.type, payload);
  });
```

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Notifications`](https://docs.gamend.org/Gamend.Notifications.html) - the functions a plugin calls, with their
  signatures and docs.
