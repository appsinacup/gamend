---
icon: hero-chat-bubble-oval-left-ellipsis
---

# Chat

The chat system supports messaging within lobbies, groups, and between friends (direct messages). Messages can be sent, edited, deleted, and support read cursors for tracking unread counts. The hook pipeline enables moderation and filtering. Notifications are sent automatically for new messages.

## Chat Types

- **lobby** — Messages sent within a lobby. Requires the sender to be a member of the lobby.
- **group** — Messages sent within a group. Requires the sender to be a member of the group.
- **friend** — Direct messages between two friends. Requires an accepted friendship and neither user has blocked the other.

## API

Endpoints live under `/api/v1/chat`; the shapes are in
[/api/docs](/api/docs). Two parameters identify a conversation everywhere:

- **`chat_type`** - `lobby`, `group` or `friend`
- **`chat_ref_id`** - the lobby id, the group id, or *the other user's* id for a
  DM (not a conversation id; there is no such row)

## Read Cursors & Unread Counts

Track which messages a user has read with read cursors. The server stores the last-read message ID per user per chat.

```text
 # Mark as read: POST /api/v1/chat/read { "chat_type": "lobby", "chat_ref_id": "01977f5a-0042-7000-8000-3f6a2d8c0a42", "message_id": "01977f5a-0150-7000-8000-3f6a2d8c0150

# Get unread count: GET /api/v1/chat/unread
?chat_type=lobby&chat_ref_id=01977f5a-0042-7000-8000-3f6a2d8c0a42

# Response
unread_count": 12 }
```

## Architecture & Message Flow

The following diagram shows the flow when a chat message is sent:

```text
 Client Server Recipients ────── ────── ────────── POST /chat/messages ──► 1. Validate access 2. Run before_chat_message hook 3. Insert into DB 4. Invalidate Nebulex cache 5. PubSub broadcast ─────────► WebSocket push 6. Async: after_chat_message "chat_message_created" hook + send notifications ──► "notification" event PATCH /chat/messages/:id ► 1. Verify ownership (sender_id) 2. Update content/metadata 3. Invalidate cache 4. PubSub broadcast ────────► "chat_message_updated" DELETE /chat/messages/:id ► 1. Verify ownership 2. Delete from DB 3. Invalidate cache 4. PubSub broadcast ───────► "chat_message_deleted" (payload: {id})
```

## Real-time Events

Messages are broadcast in real-time via PubSub. WebSocket channels automatically forward these events to connected clients.

```text
 Chat Type PubSub Topic Channel ───────── ──────────── ─────── lobby chat:lobby:{lobby_id} LobbyChannel group chat:group:{group_id} GroupChannel friend chat:friend:{lo}:{hi} UserChannel + user:{recipient_id} Events pushed to clients: ───────────────────────── "chat_message_created" → Full message object (on send) "chat_message_updated" → Full message object (on edit) "chat_message_deleted" → { id: message_id } (on delete)
```

Friend DMs are broadcast to both the sorted-pair topic and each user's personal topic, so the recipient receives the message even without subscribing to the friend chat topic directly.

Clients that cache messages locally can update in-place: on "chat_message_updated\

## Automatic Notifications

When a new chat message is sent, a notification is automatically created for each recipient:

- **Friend DM:** Title: "New message from {sender_name}", content: message preview (100 chars)
- **Group message:** Title: "New message in {group_name}\
- **Lobby message:** Title: "New message in {lobby_name}\

Notifications use upsert semantics — multiple messages from the same sender update the existing notification with the latest content rather than creating duplicates.

## Elixir Context Functions

The Chat context module provides functions for server-side chat operations:

```text
 # Send a message (validates access, runs hook pipeline, broadcasts, notifies) GameServer.Chat.send_message(%{user: user}, %{ "chat_type" => "lobby", "chat_ref_id" => lobby_id, "content" => "Hello!", "metadata" => %{"color" => "blue
})

# List messages (paginated, cached with 60s TTL)
GameServer.Chat.list_messages("lobby", lobby_id, page: 1, page_size: 50)

# List friend messages (bidirectional)
GameServer.Chat.list_friend_messages(user_a_id, user_b_id, page: 1)

# Get a single message
GameServer.Chat.get_message(message_id)

# Update your own message (ownership enforced)
GameServer.Chat.update_message(user_id, message_id, %{"content" => "edited"})

# Delete your own message (ownership enforced)
GameServer.Chat.delete_own_message(user_id, message_id)

# Mark messages as read (upsert cursor)
GameServer.Chat.mark_read(user_id, "lobby", lobby_id, last_message_id)

# Count unread messages
GameServer.Chat.count_unread(user_id, "lobby", lobby_id)

# Count unread friend DMs
GameServer.Chat.count_unread_friend(user_id, friend_id)

# Batch unread counts for all friends/groups
GameServer.Chat.count_unread_friends_batch(user_id, friend_ids)
GameServer.Chat.count_unread_groups_batch(user_id, group_ids)
```

## Hook Pipeline (Moderation)

Chat messages pass through the hook pipeline before being persisted. Use the before_chat_message hook to filter, transform, or reject messages — ideal for profanity filters, rate limiting, or content moderation.

```elixir
# In your hooks module (implements GameServer.Hooks behaviour)
@impl true
def before_chat_message(user, attrs) do
  content = attrs["content"] || ""

  cond do
    String.length(content) > 500 ->
      {:error, :message_too_long}

    contains_profanity?(content) ->
      {:ok, Map.put(attrs, "content", censor(content))}

    true ->
      {:ok, attrs}
  end
end

# After hook fires asynchronously (logging, analytics, etc.)
@impl true
def after_chat_message(message) do
  Logger.info("Chat message #{message.id} sent by #{message.sender_id}")
  :ok
end
```

## Caching

Message listings are cached using Nebulex with version-based invalidation. When a message is sent, edited, or deleted, the cache version for that chat is incremented, automatically invalidating stale cached results. Cache TTL is 60 seconds.

## Access Rules

- **Lobby chat:** User must currently be in the lobby (user.lobby_id matches)
- **Group chat:** User must be a member of the group
- **Friend chat:** Users must have an accepted friendship and neither can have blocked the other
- Edit/Delete: Only the message sender can modify or delete their own messages (returns 403 otherwise)
- Messages have a maximum content length of 4096 characters
- Metadata is optional and stored as a JSON map
- Slow mode: lobbies and groups have a slowdown field (seconds, 0 = off); sending again within the window returns {:error, :slowdown}

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`GameServer.Chat`](https://appsinacup.com/game_server/GameServer.Chat.html) - the functions a plugin calls, with their
  signatures and docs.
