---
icon: hero-chat-bubble-oval-left-ellipsis
---

# Chat

The chat system supports messaging within lobbies, groups, and between friends (direct messages). Messages can be sent, edited, deleted, and support read cursors for tracking unread counts. A word filter, a report queue and mutes ship built in, with the hook pipeline for rules of your own. Notifications are sent automatically for new messages.

## Chat types

- **lobby** — Messages sent within a lobby. Requires the sender to be a member of the lobby.
- **group** — Messages sent within a group. Requires the sender to be a member of the group.
- **friend** — Direct messages between two friends. Requires an accepted friendship and neither user has blocked the other.

## API

Endpoints live under `/api/v1/chat`; the shapes are in
[/api/docs](/api/docs). Two parameters identify a conversation everywhere:

- **`chat_type`** - `lobby`, `group` or `friend`
- **`chat_ref_id`** - the lobby id, the group id, or *the other user's* id for a
  DM (not a conversation id; there is no such row)

## Read cursors and unread counts

Track which messages a user has read with read cursors. The server stores the last-read message ID per user per chat.

```text
 # Mark as read: POST /api/v1/chat/read { "chat_type": "lobby", "chat_ref_id": "01977f5a-0042-7000-8000-3f6a2d8c0a42", "message_id": "01977f5a-0150-7000-8000-3f6a2d8c0150

# Get unread count: GET /api/v1/chat/unread
?chat_type=lobby&chat_ref_id=01977f5a-0042-7000-8000-3f6a2d8c0a42

# Response
unread_count": 12 }
```

## Architecture and message flow

The following diagram shows the flow when a chat message is sent:

```text
 Client Server Recipients ────── ────── ────────── POST /chat/messages ──► 1. Validate access 2. Run before_chat_message hook 3. Insert into DB 4. Invalidate Nebulex cache 5. PubSub broadcast ─────────► WebSocket push 6. Async: after_chat_message "chat_message_created" hook + send notifications ──► "notification" event PATCH /chat/messages/:id ► 1. Verify ownership (sender_id) 2. Update content/metadata 3. Invalidate cache 4. PubSub broadcast ────────► "chat_message_updated" DELETE /chat/messages/:id ► 1. Verify ownership 2. Delete from DB 3. Invalidate cache 4. PubSub broadcast ───────► "chat_message_deleted" (payload: {id})
```

## Real-time events

Messages are broadcast in real time via PubSub. WebSocket channels automatically forward these events to connected clients.

```text
 Chat Type PubSub Topic Channel ───────── ──────────── ─────── lobby chat:lobby:{lobby_id} LobbyChannel group chat:group:{group_id} GroupChannel friend chat:friend:{lo}:{hi} UserChannel + user:{recipient_id} Events pushed to clients: ───────────────────────── "chat_message_created" → Full message object (on send) "chat_message_updated" → Full message object (on edit) "chat_message_deleted" → { id: message_id } (on delete)
```

Friend DMs are broadcast to both the sorted-pair topic and each user's personal topic, so the recipient receives the message even without subscribing to the friend chat topic directly.

Clients that cache messages locally can update in-place: on "chat_message_updated\

## Automatic notifications

When a new chat message is sent, a notification is automatically created for each recipient:

- **Friend DM:** Title: "New message from {sender_name}", content: message preview (100 chars)
- **Group message:** Title: "New message in {group_name}\
- **Lobby message:** Title: "New message in {lobby_name}\

Notifications use upsert semantics: multiple messages from the same sender update the existing notification with the latest content rather than creating duplicates.

## Elixir context functions

The Chat context module provides functions for server-side chat operations:

```text
 # Send a message (validates access, runs hook pipeline, broadcasts, notifies) Gamend.Chat.send_message(%{user: user}, %{ "chat_type" => "lobby", "chat_ref_id" => lobby_id, "content" => "Hello!", "metadata" => %{"color" => "blue
})

# List messages (paginated, cached with 60s TTL)
Gamend.Chat.list_messages("lobby", lobby_id, page: 1, page_size: 50)

# List friend messages (bidirectional)
Gamend.Chat.list_friend_messages(user_a_id, user_b_id, page: 1)

# Get a single message
Gamend.Chat.get_message(message_id)

# Update your own message (ownership enforced)
Gamend.Chat.update_message(user_id, message_id, %{"content" => "edited"})

# Delete your own message (ownership enforced)
Gamend.Chat.delete_own_message(user_id, message_id)

# Mark messages as read (upsert cursor)
Gamend.Chat.mark_read(user_id, "lobby", lobby_id, last_message_id)

# Count unread messages
Gamend.Chat.count_unread(user_id, "lobby", lobby_id)

# Count unread friend DMs
Gamend.Chat.count_unread_friend(user_id, friend_id)

# Batch unread counts for all friends/groups
Gamend.Chat.count_unread_friends_batch(user_id, friend_ids)
Gamend.Chat.count_unread_groups_batch(user_id, group_ids)
```

## Moderation

Three primitives ship with core, all enforced server-side in
`Gamend.Chat.send_message/2` before a message is persisted: a word filter, a
report queue and mutes. A message core rejects never reaches the
database, PubSub or your hooks. Core ships the mechanism, not the policy. The
blocklist starts empty and nobody is muted until a moderator says so.

## Word filter

An admin-managed blocklist, edited on the admin chat filter page. Every entry
carries a severity and a match mode (`substring`, the default, or `exact` for a
whole word):

- **block** — the message is rejected and never stored; the sender is told `blocked_content`.
- **mask** — the offending token is replaced with `***` and the masked message goes through.
- **flag** — the message is stored as written, marked flagged, and a report is filed automatically.

Matching is evasion-resistant. Blocklist entries and incoming messages both go
through one shared normalizer (lower-cased, diacritics dropped, zero-width
characters removed, common leetspeak mapped (`@`→`a`, `3`→`e`, `0`→`o`, …),
repeated characters collapsed), so a word stored as `idiot` still catches
`ïd10T` and `iiiidiot`. The admin "test a phrase" box runs that same normalizer,
so what it reports is exactly what the runtime path does.

The list ships inert: nothing is enabled, and Gamend ships no profanity or
slur list of its own. `priv/chat_filter/en.txt` contains two harmless
placeholders (`badword`, `spamlink`) purely so you can try the feature; which
words are unacceptable is your game's policy, in your languages, and the server
is MIT-licensed and stays out of that decision.

### Bringing your own list

Public multi-language lists you can start from:

| List | Coverage | Licence |
|---|---|---|
| [LDNOOBW](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) | ~30 languages, one word per line | CC-BY-4.0 |
| [Shutterstock](https://github.com/shutterstock/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) | ~25 languages | MIT |

Read one before you ship it, because lists built for filtering search queries are
far more aggressive than you want between players. Check the licence of
anything you vendor into your repo.

There are two ways to load one:

**As a bundled file (needs a rebuild).** Save it as
`apps/gamend_core/priv/chat_filter/<lang>.txt`, one word per line, `#` for
comments. Rebuild, then open **Admin → Chat filter**, pick the language and a
severity, and press **Import bundled list**. The folder is read from the
compiled app's `priv/` via `Application.app_dir/2`, so a file added *after* the
build is not visible to a running server; it ships with the release like any
other asset. Anything you drop there appears in the picker automatically, and a
whole imported list can be removed again in one click (or with
`DELETE /api/v1/admin/chat/filter_words?lang=de`).

**Over the admin API (no rebuild).** POST each word to
`POST /api/v1/admin/chat/filter_words` with `{"word": "...", "severity":
"block", "lang": "de"}`. This is the path to script when the list lives outside
your repo or changes between deploys. Tag the rows with `lang` and you keep the
same one-click bulk removal.

Either way the cap is `max_chat_filter_words`, and every word goes through the
normalizer on the way in, so one entry covers its evasive spellings.

Matching is language-agnostic: every entry is checked against every message,
because a chat line carries no reliable language signal: players code-switch,
and detecting a language from a short string is both slow and wrong. `lang` is
provenance only. It records which bundled list a row came from, powers "remove
the German list" as a bulk delete, and shows as a column in admin; it never
narrows what a message is checked against. Import the locales you actually
serve, since a benign word in one language is a slur in another, so importing
everything mostly buys false positives.

## Working the report queue

A report is a to-do item for a moderator, and **Admin → Chat reports** is where
you work it. A report has four states:

| Status | Meaning |
|---|---|
| `open` | Nobody has looked at it. This is what every new report starts as. |
| `reviewing` | A moderator pressed **Review** to claim it. Still in the queue — it only signals that someone has it. |
| `actioned` | Resolved, and something happened: the message was deleted, or the player was warned or muted. |
| `dismissed` | Resolved, and nothing was wrong. |

Nothing moves a report on its own. Four actions resolve one, and each records
who did it and when:

- **Dismiss** — no action needed.
- **Delete message** — removes the offending message. The report survives with
  its content snapshot, so the record of what was said is not lost.
- **Warn** — sends the player a notification and resolves the report. No mute.
- **Mute** — silences the player for a duration you choose (10 minutes to
  permanent), in one room or globally.

When a report lands, every admin gets a notification ("New chat reports").
It upserts on its title, so it stays a single unread entry whose count keeps
rising rather than one notification per report.

Each of those actions can also reply to the reporter, so someone who takes
the trouble to report abuse hears what came of it. Reports the word filter filed
itself have no reporter, so that option does not appear on them.

Warnings, mute notices and reporter replies are all prefilled with sensible
wording and are editable before sending; core supplies a starting point, not
your community's voice.

## Report queue

Players report a message with `POST /api/v1/chat/messages/:id/report` and an
optional `reason`. One report per player per message (a repeat is rejected as
`already_reported`), you cannot report your own message, and each player is
capped over a rolling 24 hours by `max_chat_reports_per_user_per_day`. Reports
the word filter files for itself on a `flag` hit have no reporter, so the
`reporter_id` is null.

Every report keeps a snapshot of the message content plus the reported user's
id, so the queue still makes sense after the message itself is deleted.
Moderators work it in the admin console, where a report moves from `open`
through `reviewing` to `actioned` or `dismissed`, with an optional resolution
note.

## Mutes

A mute silences a sender without touching their account. The scope decides
where it applies, and who is allowed to apply it:

- **global** — every chat type, friend DMs included. Server-authoritative: the admin console or API, or a plugin calling `Gamend.Chat.mute_user/4`. There is deliberately no public endpoint.
- **lobby**, **group**, **party** — that one room. Authority follows the room, mirroring kick: the lobby host, a group admin, the party leader.

The scoped endpoints take `{ "target_user_id": …, "expires_at": …, "reason": … }`:

| Scope | Mute | Unmute | List active |
|---|---|---|---|
| lobby | `POST /api/v1/lobbies/mute` | `POST /api/v1/lobbies/unmute` | `GET /api/v1/lobbies/mutes` |
| group | `POST /api/v1/groups/:id/mute` | `POST /api/v1/groups/:id/unmute` | `GET /api/v1/groups/:id/mutes` |
| party | `POST /api/v1/parties/mute` | `POST /api/v1/parties/unmute` | `GET /api/v1/parties/mutes` |

Lobby and party calls take no room id; the room is the caller's own. A hostless
(matchmaking-owned) lobby has no in-game moderator, so only an admin or a plugin
can mute there.

A mute is editable after the fact. Open **Admin → Chat mutes** and change its
duration or reason in place to shorten, extend or re-word one, so you do not have
to unmute and start over. The same holds through the API: re-muting a player in a
scope they are already muted in replaces the existing mute rather than failing.

When you mute someone from the console you can notify them, with wording
prefilled from the mute (its scope, expiry and reason) and editable before it
goes out. Separately, a `chat_muted` realtime event reaches the player's socket
immediately so the client can grey out its chat input.

`expires_at` sets the lifetime: a timestamp for a timed mute, omitted for a
permanent one. Expiry is evaluated when a message is sent, so a mute stops
biting the moment it lapses; the periodic sweep only clears dead rows and is
never load-bearing.

The muted player is pushed `chat_muted` (`scope`, `scope_ref_id`, `expires_at`,
`reason`) and `chat_unmuted` (`scope`, `scope_ref_id`) on their user channel, so
a client can grey out the input instead of discovering the mute through a
rejected send.

## Hook pipeline (moderation)

Chat messages pass through the hook pipeline before being persisted. Core's
filter and mute checks run first, so your hook never sees a message core already
blocked. Then before_chat_message is where your own rules go: custom rate
limits, per-lobby etiquette, or a call out to a classifier. It can still reject
or rewrite anything core let through. Two observation hooks watch what core did:
after_chat_message_reported fires for every report (player-filed or
filter-filed) and after_user_muted for every mute, which is where a strike
policy belongs; see the [Server scripting](/docs/server-scripting)
guide.

```elixir
# In your hooks module (implements Gamend.Hooks behaviour)
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

## Access rules

- **Lobby chat:** User must currently be in the lobby (user.lobby_id matches)
- **Group chat:** User must be a member of the group
- **Friend chat:** Users must have an accepted friendship and neither can have blocked the other
- Edit/Delete: Only the message sender can modify or delete their own messages (returns 403 otherwise)
- Messages have a maximum content length of 4096 characters
- Metadata is optional and stored as a JSON map
- Slow mode: lobbies and groups have a slowdown field (seconds, 0 = off); sending again within the window returns {:error, :slowdown}
- Muted senders: a global mute silences every chat type, a scoped mute only that lobby, group or party; sending returns {:error, :muted}, and a blocked word returns {:error, :blocked_content}

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Chat`](https://docs.gamend.org/Gamend.Chat.html) - the functions a plugin calls, with their
  signatures and docs.
