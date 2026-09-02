# `Gamend.Groups`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/groups.ex#L1)

Context module for group management: creating, updating, listing, joining,
leaving, kicking, promoting/demoting members, and handling join requests.

Groups are persistent communities (unlike ephemeral lobbies). They support
three visibility types:

- **public** – anyone can join directly
- **private** – anyone can request to join; an admin must approve
- **hidden** – only invited users can join (via notifications / invite API)

## Usage

    # Create a group (creator becomes admin)
    {:ok, group} = Groups.create_group(user_id, %{"title" => "Cool Group"})

    # List public/private groups (hidden excluded)
    groups = Groups.list_groups(%{}, page: 1, page_size: 25)

    # Join a public group
    {:ok, member} = Groups.join_group(user_id, group.id)

    # Request to join a private group
    {:ok, request} = Groups.request_join(user_id, group.id)

    # Admin approves a join request
    {:ok, member} = Groups.approve_join_request(admin_id, request.id)

## PubSub Events

- `"groups"` topic:
  - `{:group_created, group}`
  - `{:group_updated, group}`
  - `{:group_deleted, group_id}`

- `"group:<group_id>"` topic:
  - `{:member_joined, group_id, user_id}`
  - `{:member_left, group_id, user_id}`
  - `{:member_kicked, group_id, user_id}`
  - `{:member_promoted, group_id, user_id}`
  - `{:member_demoted, group_id, user_id}`
  - `{:group_updated, group}`
  - `{:join_request_created, group_id, user_id}`
  - `{:join_request_approved, group_id, user_id}`
  - `{:join_request_rejected, group_id, user_id}`
  - `{:group_notification, group_id, sender_id}`

# `accept_invite`

```elixir
@spec accept_invite(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
```

Accept a pending group invite by invite id (recipient only).

# `admin_delete_group`

```elixir
@spec admin_delete_group(Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.Group.t()} | {:error, term()}
```

Admin-level delete (no membership check, for server admins).

# `admin_update_group`

```elixir
@spec admin_update_group(Gamend.Groups.Group.t(), map()) ::
  {:ok, Gamend.Groups.Group.t()} | {:error, Ecto.Changeset.t()}
```

Admin-level update, bypasses membership checks.

# `approve_join_request`

```elixir
@spec approve_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
```

Approve a pending join request. Admin only.

# `batch_member_counts`

```elixir
@spec batch_member_counts([Ecto.UUID.t()]) :: %{
  required(Ecto.UUID.t()) =&gt; non_neg_integer()
}
```

Batch count members for a list of group IDs. Returns a map of group_id => count.

# `broadcast_member_presence`

```elixir
@spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
```

Broadcast a presence event (e.g. member_online, member_updated) to a group topic.

# `can_manage_group?`

```elixir
@spec can_manage_group?(
  Gamend.Accounts.User.t() | Ecto.UUID.t() | nil,
  Gamend.Groups.Group.t() | Ecto.UUID.t() | nil
) :: boolean()
```

Whether `user` holds authority over `group` — its admin members, nobody else.

Subject first, resource second, like every other `can_*?` predicate (see
`Gamend.Policy`). Both arguments take a struct or a bare id.

# `cancel_invite`

```elixir
@spec cancel_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
```

Cancel a group invitation the current user sent.

# `cancel_join_request`

```elixir
@spec cancel_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupJoinRequest.t()} | {:error, atom()}
```

Cancel (delete) a pending join request. Only the requesting user can cancel.

# `change_group`

```elixir
@spec change_group(Gamend.Groups.Group.t(), map()) :: Ecto.Changeset.t()
```

Return a changeset for tracking group changes (admin edit forms).

# `count_all_groups`

```elixir
@spec count_all_groups(map()) :: non_neg_integer()
```

Count ALL groups matching filters (admin).

# `count_all_members`

```elixir
@spec count_all_members() :: non_neg_integer()
```

Total member count across all groups.

# `count_group_members`

```elixir
@spec count_group_members(
  Ecto.UUID.t(),
  keyword()
) :: non_neg_integer()
```

Count members in a group. Accepts the same `:search` option as the listing.

# `count_groups_by_type`

```elixir
@spec count_groups_by_type(String.t()) :: non_neg_integer()
```

Count groups by type.

# `count_groups_created_by`

```elixir
@spec count_groups_created_by(Ecto.UUID.t()) :: non_neg_integer()
```

Count how many groups a user has created (is admin of).

# `count_invitations`

```elixir
@spec count_invitations(Ecto.UUID.t()) :: non_neg_integer()
```

Count pending invitations for a user.

# `count_join_requests`

```elixir
@spec count_join_requests(Ecto.UUID.t()) :: non_neg_integer()
```

Count pending join requests for a group.

# `count_list_groups`

```elixir
@spec count_list_groups(map()) :: non_neg_integer()
```

Count groups matching public filters (excludes hidden).

# `count_sent_invitations`

```elixir
@spec count_sent_invitations(Ecto.UUID.t()) :: non_neg_integer()
```

Count group invitations sent by a user.

# `count_user_group_memberships`

```elixir
@spec count_user_group_memberships(Ecto.UUID.t()) :: non_neg_integer()
```

Count how many groups a user is a member of (any role).

# `count_user_groups`

```elixir
@spec count_user_groups(Ecto.UUID.t()) :: non_neg_integer()
```

Count groups the user belongs to.

# `create_group`

```elixir
@spec create_group(Ecto.UUID.t(), map()) ::
  {:ok, Gamend.Groups.Group.t()} | {:error, Ecto.Changeset.t() | term()}
```

Create a new group. The creating user becomes an admin member automatically.

# `decline_invite`

```elixir
@spec decline_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
```

Decline a pending group invite by invite id (recipient only).

# `delete_group`

```elixir
@spec delete_group(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.Group.t()} | {:error, atom()}
```

Delete a group. Admin-only. Refuses if the group still has members — groups
are auto-deleted when the last member leaves.

# `demote_member`

```elixir
@spec demote_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
```

Demote an admin to member. Only admins can demote other admins.

# `get_group`

```elixir
@spec get_group(Ecto.UUID.t()) :: Gamend.Groups.Group.t() | nil
```

Get a group by ID (cached).

# `get_group!`

```elixir
@spec get_group!(Ecto.UUID.t()) :: Gamend.Groups.Group.t()
```

Get a group by ID (raises if not found, cached).

# `get_group_by_title`

```elixir
@spec get_group_by_title(String.t()) :: Gamend.Groups.Group.t() | nil
```

Get a group by its unique title.

# `get_group_members`

```elixir
@spec get_group_members(Ecto.UUID.t()) :: [Gamend.Groups.GroupMember.t()]
```

Get all members of a group.

# `get_group_members_paginated`

```elixir
@spec get_group_members_paginated(
  Ecto.UUID.t(),
  keyword()
) :: [Gamend.Groups.GroupMember.t()]
```

Get paginated members of a group with user info.

Pass `:search` to filter by member name (display name or username).

# `get_membership`

```elixir
@spec get_membership(Ecto.UUID.t(), Ecto.UUID.t()) ::
  Gamend.Groups.GroupMember.t() | nil
```

Get a specific membership.

# `group_member_ids`

```elixir
@spec group_member_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
```

Just the user ids of a group's members, oldest first.

For callers that only need to address members — chat notification fanout is
the hot one — where `get_group_members/1` would preload every member's full
user row only to read `user_id` from it.

# `handle_user_deletion`

```elixir
@spec handle_user_deletion(Ecto.UUID.t()) :: :ok
```

Clean up group memberships before a user is deleted.

For each group the user belongs to:
- If the user is the sole admin and other members exist, promotes the oldest
  member to admin before removing the user's membership row.
- Removes the membership row.
- If the group has no members left after removal, deletes the group.

This must be called *before* `Repo.delete(user)` so that the membership
rows still exist (the DB cascade would silently delete them otherwise
without running the admin-transfer / empty-group logic).

# `invalidate_group_cache_public`

```elixir
@spec invalidate_group_cache_public(Ecto.UUID.t()) :: :ok
```

Public wrapper for cache invalidation (used by admin controller).

# `invite_to_group`

```elixir
@spec invite_to_group(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupInvite.t()}
  | {:ok, :request_approved}
  | {:error, atom()}
```

Invite a user to a group (see `Gamend.Groups.Invites.invite_to_group/3`).

# `join_group`

```elixir
@spec join_group(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
```

Join a public group directly. Returns error for private/hidden groups.

# `kick_member`

```elixir
@spec kick_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
```

Kick a member from the group. Only admins can kick.

# `leave_group`

```elixir
@spec leave_group(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
```

Leave a group.

# `list_all_groups`

```elixir
@spec list_all_groups(
  map(),
  keyword()
) :: [Gamend.Groups.Group.t()]
```

List ALL groups including hidden (admin only).

# `list_groups`

```elixir
@spec list_groups(
  map(),
  keyword()
) :: [Gamend.Groups.Group.t()]
```

List groups visible to the public (excludes hidden).

## Filters

  * `:title` – prefix search on title (case-insensitive)
  * `:type` – exact match on type (`"public"` or `"private"`)
  * `:min_members` – groups with max_members >= value
  * `:max_members` – groups with max_members <= value
  * `:metadata_key` / `:metadata_value` – filter by metadata entry

## Options

  * `:page` – page number (default 1)
  * `:page_size` – results per page (default 25)

# `list_invitations`

```elixir
@spec list_invitations(
  Ecto.UUID.t(),
  keyword()
) :: [map()]
```

List pending group invitations for a user.

# `list_join_requests`

```elixir
@spec list_join_requests(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
  {:ok, [Gamend.Groups.GroupJoinRequest.t()]} | {:error, atom()}
```

List pending join requests for a group (admin only).

# `list_sent_invitations`

```elixir
@spec list_sent_invitations(
  Ecto.UUID.t(),
  keyword()
) :: [map()]
```

List group invitations sent by a user.

# `list_user_groups`

```elixir
@spec list_user_groups(
  Ecto.UUID.t(),
  keyword()
) :: [Gamend.Groups.Group.t()]
```

List groups the user belongs to.

# `list_user_groups_with_role`

```elixir
@spec list_user_groups_with_role(Ecto.UUID.t()) :: [
  {Gamend.Groups.Group.t(), String.t()}
]
```

List groups the user belongs to, together with the membership role.

# `list_user_pending_requests`

```elixir
@spec list_user_pending_requests(Ecto.UUID.t()) :: [
  Gamend.Groups.GroupJoinRequest.t()
]
```

List pending join requests sent by a user.

# `member?`

```elixir
@spec member?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
```

Check if user is a member (any role) of the group.

# `notify_group`

```elixir
@spec notify_group(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), map()) ::
  {:ok, non_neg_integer()} | {:error, atom()}
```

Send a notification to all members of a group (except the sender).

**Server-side only.** There is deliberately no player-facing endpoint for
this: one call writes a row, a cache invalidation and a PubSub push *per
member*, so with `max_group_members` at 10,000 an ordinary member could turn
one request into ~10,000 of each. Members talk to a group through group chat,
which costs one row and one topic broadcast and is throttled per group. This
function is the announcement primitive for plugins and hooks - callers are
trusted, so it skips both the friends-only check and the per-recipient
notification cap that `Notifications.send_notification/2` enforces.

The `group_id` / `group_name` are stored in metadata so the client can
recognise and route it.

## Options

  * `title` – notification title string (default: `"Group Notification"`).
    The title is part of the unique constraint `(sender_id, recipient_id, title)`,
    so different titles create separate notification slots.

Because of the unique constraint on `(sender_id, recipient_id, title)`, a
new notification from the same sender to the same recipient with the same title
replaces the previous one (upsert). This prevents spam while keeping the latest
message.

Returns `{:ok, count}` with the number of notifications sent.

# `promote_member`

```elixir
@spec promote_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
```

Promote a member to admin. Only admins can promote.

# `reject_join_request`

```elixir
@spec reject_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupJoinRequest.t()} | {:error, atom()}
```

Reject a pending join request. Admin only.

# `request_join`

```elixir
@spec request_join(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupJoinRequest.t()} | {:error, atom()}
```

Request to join a private group. Creates a pending join request.

# `set_icon_url`

```elixir
@spec set_icon_url(String.t(), String.t(), String.t()) ::
  {:ok, Gamend.Groups.Group.t()}
  | {:error, :not_admin | Ecto.Changeset.t() | term()}
```

Set a group's icon to an object we have just accepted an upload for.

Separate from `update_group/3` because that one deliberately drops `icon_url`
from caller-supplied attributes. The URL here does not come from the caller:
it is produced by `GamendWeb.Uploads.confirm/5` after the stored object has
been re-read, size-checked and content-sniffed, so this path is the only way
an icon is ever set. Admin rights are still required.

# `shared_group_member?`

```elixir
@spec shared_group_member?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
```

Return true if both users share at least one common group membership.

# `subscribe_group`

```elixir
@spec subscribe_group(Ecto.UUID.t()) :: :ok | {:error, term()}
```

Subscribe to a specific group's events.

# `subscribe_groups`

```elixir
@spec subscribe_groups() :: :ok | {:error, term()}
```

Subscribe to global group events.

# `unsubscribe_group`

```elixir
@spec unsubscribe_group(Ecto.UUID.t()) :: :ok
```

Unsubscribe from a specific group's events.

# `update_group`

```elixir
@spec update_group(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
  {:ok, Gamend.Groups.Group.t()} | {:error, atom() | Ecto.Changeset.t()}
```

Update group settings. Only admins can update.
Cannot lower max_members below current member count.

# `user_group_ids`

```elixir
@spec user_group_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
```

Return the list of group IDs the user belongs to (lightweight, no preloads).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
