# `Gamend.Notifications`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/notifications.ex#L1)

Notifications context – create, list, and delete persisted user-to-user
notifications.

Notifications can only be sent to accepted friends. They are stored in the
database so that recipients receive them even when offline. On WebSocket
connect the client gets all undeleted notifications (ordered by timestamp).
New notifications are also pushed in real-time via PubSub.

## PubSub Events

This module broadcasts to the `"notifications:user:<user_id>"` topic:

- `{:notification_created, notification}` – a new notification was created

## Usage

    # Send a notification to a friend
    {:ok, notification} = Notifications.send_notification(sender_id, %{
      "user_id" => recipient_id,
      "title" => "Game invite",
      "content" => "Join my lobby!",
      "metadata" => %{"lobby_id" => "0198c0de-7f2a-7e3b-9c4d-1a2b3c4d5e6f"}
    })

    # List all notifications for a user (ordered oldest-first)
    notifications = Notifications.list_notifications(user_id)

    # Delete notifications by IDs (only owner can delete)
    {deleted_count, nil} = Notifications.delete_notifications(user_id, [1, 2, 3])

    # Count notifications for a user
    count = Notifications.count_notifications(user_id)

# `user_id`

```elixir
@type user_id() :: Ecto.UUID.t()
```

# `admin_create_notification`

```elixir
@spec admin_create_notification(user_id(), user_id(), map()) ::
  {:ok, Gamend.Notifications.Notification.t()} | {:error, Ecto.Changeset.t()}
```

Admin: create a notification from any sender to any recipient (no friendship check).

# `admin_delete_notification`

```elixir
@spec admin_delete_notification(Ecto.UUID.t()) ::
  {:ok, Gamend.Notifications.Notification.t()}
  | {:error, :not_found | Ecto.Changeset.t()}
```

Admin: delete a single notification by ID (no ownership check).

# `count_all_notifications`

```elixir
@spec count_all_notifications(map()) :: non_neg_integer()
```

Count all notifications matching the given filters (admin).

# `count_notifications`

```elixir
@spec count_notifications(user_id()) :: non_neg_integer()
```

Count total notifications for a user.

# `count_unread_notifications`

```elixir
@spec count_unread_notifications(user_id()) :: non_neg_integer()
```

Count unread notifications for a user.

# `create_chat_notification`

```elixir
@spec create_chat_notification(user_id(), user_id(), map()) ::
  {:ok, Gamend.Notifications.Notification.t()} | {:error, term()}
```

Create a chat notification for a recipient.

Unlike `send_notification/2`, this does not require friendship — it is
intended for system-generated notifications triggered by new chat messages.

Uses upsert semantics: if a notification with the same
`(sender_id, recipient_id, title)` already exists, its content and metadata
are updated (so the user sees the latest message preview).

# `delete_all_notifications`

```elixir
@spec delete_all_notifications(user_id()) :: {non_neg_integer(), nil}
```

Delete every notification `user_id` received, in one statement. Returns `{deleted_count, nil}`.

# `delete_notification_by`

```elixir
@spec delete_notification_by(user_id(), user_id(), String.t()) ::
  {non_neg_integer(), nil}
```

Delete all notifications from `sender_id` to `recipient_id` with the given `title`.
Used internally to retract system-generated notifications (e.g. friend request cancelled).

# `delete_notifications`

```elixir
@spec delete_notifications(user_id(), [Ecto.UUID.t()]) :: {non_neg_integer(), nil}
```

Delete notifications by IDs, scoped to the recipient (owner).

Only notifications belonging to `user_id` will be deleted.
Returns `{deleted_count, nil}`.

# `get_notification`

```elixir
@spec get_notification(Ecto.UUID.t()) :: Gamend.Notifications.Notification.t() | nil
```

Get a single notification by ID.

# `get_notification!`

```elixir
@spec get_notification!(Ecto.UUID.t()) :: Gamend.Notifications.Notification.t()
```

Get a single notification by ID (raises if not found).

# `group_of`

```elixir
@spec group_of(Gamend.Notifications.Notification.t()) :: String.t() | nil
```

The notification group (`Gamend.Notifications.Preferences`) a notification
belongs to: the one `notify/3` named, else its type's. nil for one in no group.

# `list_all_notifications`

```elixir
@spec list_all_notifications(map(), keyword()) :: [
  Gamend.Notifications.Notification.t()
]
```

List all notifications (admin), with optional filters.

## Filters (map with string keys)

- `"recipient_id"` / `"user_id"` – filter by recipient user ID
- `"sender_id"` – filter by sender user ID
- `"title"` – partial (LIKE) match on title

## Options

- `:page` – page number (default 1)
- `:page_size` – results per page (default 25)

# `list_notifications`

```elixir
@spec list_notifications(user_id(), keyword()) :: [
  Gamend.Notifications.Notification.t()
]
```

List all notifications for a user, ordered oldest-first so the client
receives them in chronological order.

Supports pagination via `:page` and `:page_size` options.

# `list_notifications_by_title`

```elixir
@spec list_notifications_by_title(user_id(), String.t()) :: [
  Gamend.Notifications.Notification.t()
]
```

List notifications for a user filtered by title (e.g. `"party_invite"`, `"group_invite"`).

Results are ordered newest-first and cached with the same version-based TTL
as `list_notifications/2`.

# `list_recent_notifications`

```elixir
@spec list_recent_notifications(Ecto.UUID.t(), pos_integer()) :: [
  Gamend.Notifications.Notification.t()
]
```

Returns the `limit` most recent notifications, ordered oldest-first (so they
can be replayed in chronological order on connect without loading the user's
entire history).

# `list_sent_notifications_by_title`

```elixir
@spec list_sent_notifications_by_title(user_id(), String.t()) :: [
  Gamend.Notifications.Notification.t()
]
```

List notifications sent by a user filtered by title.

Useful for a leader to see which invites they have sent that are still pending.
Results are ordered newest-first and cached with the same version-based TTL.

# `mark_all_notifications_read`

```elixir
@spec mark_all_notifications_read(user_id()) :: {non_neg_integer(), nil}
```

Mark all notifications as read for a user.

# `mark_notification_read`

```elixir
@spec mark_notification_read(user_id(), Ecto.UUID.t()) ::
  {:ok, Gamend.Notifications.Notification.t()} | {:error, atom()}
```

Mark a single notification as read. Only the recipient can mark it.

# `mark_notifications_read`

```elixir
@spec mark_notifications_read(user_id(), [Ecto.UUID.t()]) :: {non_neg_integer(), nil}
```

Mark the user's notifications `ids` read, in one statement: what the
notifications page does with those that arrive while it is open. Others'
ids are skipped.

# `notify`

```elixir
@spec notify(user_id(), String.t(), map()) ::
  {:ok, [String.t()]} | {:error, :not_found}
```

Tell a user something the SERVER has to say (a streak about to end, a class
result), through the channels they chose for `group`
(`Gamend.Notifications.Preferences`): the in-app row, a push to their
devices, an email. A channel they turned off is skipped.

`attrs`: `"title"` (required), `"content"`, `"type"` (a declared code,
`Gamend.Notifications.Types`), `"url"` (a path on this site the
notification leads to), and for the email `"subject"` and `"text"`
(default: the title and the content). `"email_now" => true` sends the email
at once in a group that sends digests (`Gamend.Notifications.Digest`).
`"site_only" => true` writes the row and sends nothing else: no push and no
email, for what the reader only likes to know (a build done).

The in-app row is the user's own (sender = recipient), so repeating a title
refreshes the one row rather than stacking. Returns the channels it went
out on.

# `send_notification`

```elixir
@spec send_notification(user_id(), map()) ::
  {:ok, Gamend.Notifications.Notification.t()}
  | {:error,
     :missing_recipient
     | :cannot_notify_self
     | :not_friends
     | :too_many_notifications
     | Ecto.Changeset.t()}
```

Send a notification to a friend.

`sender_id` is the authenticated user. `attrs` must include:
- `"user_id"` or `"recipient_id"` – the target friend's user ID
- `"title"` – required
- `"content"` – optional
- `"metadata"` – optional map

Returns `{:error, :not_friends}` when the target is not an accepted friend,
`:missing_recipient` without a target, `:cannot_notify_self` for the sender
themselves, `:too_many_notifications` when the recipient's inbox is at
`max_notifications_per_user`, or the changeset.

# `subscribe`

```elixir
@spec subscribe(user_id()) :: :ok | {:error, term()}
```

Subscribe to notification events for a specific user.

# `unsubscribe`

```elixir
@spec unsubscribe(user_id()) :: :ok
```

Unsubscribe from notification events for a specific user.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
