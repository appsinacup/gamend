# `Gamend.Groups.Invites`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/groups/invites.ex#L1)

Group invitations: creating, accepting, declining, cancelling, and
listing/counting pending invites.

Public API is re-exported by `Gamend.Groups`.

# `accept_invite`

```elixir
@spec accept_invite(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
```

Accept a pending group invite by **invite_id**.
The user must be the recipient of the invite.
Works for all group types (public, private, hidden).

# `cancel_invite`

```elixir
@spec cancel_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
```

Cancel (delete) a pending group invitation: one the current user sent, or
any of a group they are an admin of, as its page lists them
(`list_group_invites/3`).

# `count_group_invites`

```elixir
@spec count_group_invites(Ecto.UUID.t()) :: non_neg_integer()
```

Count a group's pending invitations.

# `count_invitations`

```elixir
@spec count_invitations(Ecto.UUID.t()) :: non_neg_integer()
```

Count pending invitations for a user.

# `count_sent_invitations`

```elixir
@spec count_sent_invitations(Ecto.UUID.t()) :: non_neg_integer()
```

Count group invitations sent by a user.

# `decline_invite`

```elixir
@spec decline_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
```

Decline a pending group invite by **invite_id**.
Only the recipient can decline. The invite is marked as `"declined"`
(not deleted) so the sender can see the outcome.

# `invite_to_group`

```elixir
@spec invite_to_group(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupInvite.t()}
  | {:ok, :request_approved}
  | {:error, atom()}
```

Invite a user to a group. Creates a `GroupInvite` record and sends
an informational notification. The invite record is independent of the
notification — deleting notifications does not affect pending invites.

If the target user already has a pending join request for this group,
the request is automatically approved instead of creating an invite.
In that case, returns `{:ok, :request_approved}`.

The admin must already be connected to the target — a friendship, or a group
they are both already in. Without that an admin could put any user id at all
into a group with them, which made a group invite a weaker control than a
party invite, where `Parties.check_leader_connected_to_target/2` has always
required a connection. On a service children can reach, being addable to a
stranger's group is the contact path that matters, so the two now agree.
Returns `{:error, :not_connected}`. A host that sets `Gamend.Groups`'
`invites` to `anyone` (teams of colleagues) lets an admin invite any account.

# `list_group_invites`

```elixir
@spec list_group_invites(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
  {:ok, [map()]} | {:error, :not_admin}
```

A group's pending invitations, newest first, whoever sent them: what its
admins see on the group's page, to cancel one that should not stand.
Admins only.

# `list_invitations`

```elixir
@spec list_invitations(Ecto.UUID.t(), keyword()) :: [map()]
```

List pending group invitations for a user.

# `list_sent_invitations`

```elixir
@spec list_sent_invitations(Ecto.UUID.t(), keyword()) :: [map()]
```

List group invitations sent by a user.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
