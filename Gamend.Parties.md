# `Gamend.Parties`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/parties.ex#L1)

Context module for party management.

A party is a pre-lobby grouping mechanism. Players form a party before
creating or joining a lobby together.

## Usage

    # Create a party (user becomes leader and first member)
    {:ok, party} = Gamend.Parties.create_party(user, %{max_size: 4})

    # Leader invites a friend or shared-group member by user_id
    {:ok, _notification} = Gamend.Parties.invite_to_party(leader, target_user_id)

    # Target accepts the invite
    {:ok, party} = Gamend.Parties.accept_party_invite(target, party_id)

    # Or declines
    :ok = Gamend.Parties.decline_party_invite(target, party_id)

    # Leave a party (a leader hands it over; the last member out disbands it)
    {:ok, _} = Gamend.Parties.leave_party(user)

    # Party leader creates a lobby — all members join atomically
    {:ok, lobby} = Gamend.Parties.create_lobby_with_party(user, lobby_attrs)

    # Party leader joins an existing lobby — all members join atomically
    {:ok, lobby} = Gamend.Parties.join_lobby_with_party(user, lobby_id, opts)

## PubSub Events

This module broadcasts the following events:

- `"party:<party_id>"` topic:
  - `{:party_member_joined, party_id, user_id}`
  - `{:party_member_left, party_id, user_id}`
  - `{:party_disbanded, party_id}`
  - `{:party_updated, party}`

# `accept_party_invite`

```elixir
@spec accept_party_invite(Gamend.Accounts.User.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Parties.Party.t()}
  | {:error, atom() | Ecto.Changeset.t() | {:hook_rejected, term()}}
```

Accept a party invite. Joins the party and marks the invite as accepted.

If the user is already in another party, they automatically leave it first
(disbanding if they are the leader).

Returns `{:error, :no_invite}` if no pending invite exists for that party,
and `{:error, {:hook_rejected, reason}}` when `before_party_join` refuses.

# `admin_add_member`

```elixir
@spec admin_add_member(Gamend.Parties.Party.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Accounts.User.t()}
  | {:error, :not_found | :party_full | :already_in_party | term()}
```

Admin: seats `user_id` in `party` the way an accepted invite does. The
party's capacity and one party per player hold (`:party_full`,
`:already_in_party`); no hook is consulted.

# `admin_delete_party`

```elixir
@spec admin_delete_party(Ecto.UUID.t()) ::
  {:ok, Gamend.Parties.Party.t()} | {:error, term()}
```

Admin delete of a party. Clears all members' party_id and deletes the party.

# `admin_update_party`

```elixir
@spec admin_update_party(Gamend.Parties.Party.t(), map()) ::
  {:ok, Gamend.Parties.Party.t()} | {:error, Ecto.Changeset.t()}
```

Admin update of a party (max_size, metadata).

# `broadcast_member_presence`

```elixir
@spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
```

Broadcast a member presence event (online/offline) to a party's PubSub topic.

# `can_manage_party?`

```elixir
@spec can_manage_party?(
  Gamend.Accounts.User.t() | nil,
  Gamend.Parties.Party.t() | Ecto.UUID.t() | nil
) ::
  boolean()
```

Whether `user` holds authority over `party` — its leader, nobody else.

Subject first, resource second, like every other `can_*?` predicate (see
`Gamend.Policy`). The party takes a struct or a bare id; passing the user's
own `party_id` is the common case.

# `cancel_party_invite`

```elixir
@spec cancel_party_invite(Gamend.Accounts.User.t(), Ecto.UUID.t()) ::
  :ok | {:error, atom()}
```

Cancel a previously sent party invite. Only the original sender (leader) can cancel.

# `change_party`

```elixir
@spec change_party(Gamend.Parties.Party.t()) :: Ecto.Changeset.t()
```

Return a changeset for the given party (for edit forms).

# `count_all_parties`

```elixir
@spec count_all_parties(map()) :: non_neg_integer()
```

Count all parties matching the given filters.

# `count_all_party_members`

```elixir
@spec count_all_party_members() :: non_neg_integer()
```

Count total members across all parties.

# `count_party_invitations`

```elixir
@spec count_party_invitations(Gamend.Accounts.User.t()) :: non_neg_integer()
```

How many pending party invites the user has, for paging.

# `count_party_members`

```elixir
@spec count_party_members(Ecto.UUID.t()) :: non_neg_integer()
```

Count members in a party.

# `count_sent_party_invitations`

```elixir
@spec count_sent_party_invitations(Gamend.Accounts.User.t()) :: non_neg_integer()
```

How many pending party invites the leader has sent, for paging.

# `create_lobby_with_party`

```elixir
@spec create_lobby_with_party(Gamend.Accounts.User.t(), map()) ::
  {:ok, map()} | {:error, term()}
```

The party leader creates a new lobby, and all party members join it
atomically. The party is kept intact.

The lobby's `max_users` must be >= party member count.

# `create_party`

```elixir
@spec create_party(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Parties.Party.t()} | {:error, term()}
```

Create a new party. The user becomes the leader and first member.

Returns `{:error, :already_in_party}` if the user is already in a party.

# `decline_party_invite`

```elixir
@spec decline_party_invite(Gamend.Accounts.User.t(), Ecto.UUID.t()) ::
  :ok | {:error, atom()}
```

Decline a party invite. Marks the invite as declined.

# `disband`

```elixir
@spec disband(Gamend.Parties.Party.t()) :: {:ok, term()} | {:error, term()}
```

Disband a party outright: clears every member's `party_id`, cancels pending
invites, deletes the row, and broadcasts as a leader-initiated disband would.

For callers acting on the party rather than on behalf of a member — the
retention sweep for parties everyone has abandoned. Members leaving is
`leave_party/1`.

# `disband`

```elixir
@spec disband(Gamend.Parties.Party.t(), Gamend.Accounts.User.t()) ::
  {:ok, :disbanded} | {:error, :not_leader | term()}
```

Disband `party` as its leader: the end of the party a leader asks for, as
opposed to leaving it, which hands it over.

`{:error, :not_leader}` unless `leader` still leads it once its lock is
taken: a leader who handed the party over while this was on its way no
longer ends it for the new leader.

# `get_party`

```elixir
@spec get_party(Ecto.UUID.t()) :: Gamend.Parties.Party.t() | nil
```

Get a party by ID. Returns nil if not found.

# `get_party!`

```elixir
@spec get_party!(Ecto.UUID.t()) :: Gamend.Parties.Party.t()
```

Get a party by ID. Raises if not found.

# `get_party_members`

```elixir
@spec get_party_members(Gamend.Parties.Party.t() | Ecto.UUID.t()) :: [
  Gamend.Accounts.User.t()
]
```

Get all members of a party.

# `get_user_party`

```elixir
@spec get_user_party(Gamend.Accounts.User.t()) :: Gamend.Parties.Party.t() | nil
```

Get the party the user is currently in, or nil.

# `invite_to_party`

```elixir
@spec invite_to_party(Gamend.Accounts.User.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Parties.PartyInvite.t()} | {:error, atom()}
```

Invite a user to join the party. Only the party leader may invite.

The target user must be a friend of the leader, or share at least one group
with the leader. A `PartyInvite` record is created and an informational
notification is sent. The invite is independent of the notification —
deleting notifications does not affect pending invites.

Returns `{:error, :not_in_party}` if the caller is not in a party.
Returns `{:error, :not_leader}` if the caller is not the party leader.
Returns `{:error, :not_connected}` if the target is not a friend or shared group member.
If a pending invite already exists, returns `{:ok, existing_invite}` (no-op).

# `join_lobby_with_party`

```elixir
@spec join_lobby_with_party(Gamend.Accounts.User.t(), Ecto.UUID.t(), map()) ::
  {:ok, map()} | {:error, term()}
```

The party leader joins an existing lobby, and all party members join it
atomically. The party is kept intact.

The lobby must have enough free slots for the entire party, and the party
gets in only where each member could alone: a hidden lobby answers
`{:error, :not_found}` (unless a server-side caller passes
`bypass_hidden: true`, as for `Lobbies.join_lobby/3`, or `bypass_lock: true`
for a locked one, which answers `{:error, :locked}`), a block between
any member and anyone already seated answers `{:error, :blocked}`, and the
game's `before_lobby_join` is asked for every member (`"party_id"` in its
opts), the first refusal answering `{:error, {:hook_rejected, reason}}`.
A member who joined or left the party meanwhile answers
`{:error, :state_changed}`, with nobody seated.

# `kick_member`

```elixir
@spec kick_member(Gamend.Accounts.User.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, atom() | {:hook_rejected, term()}}
```

Kick a member from the party. Only the leader can kick.

`{:error, {:hook_rejected, reason}}` when `before_party_kick` refuses.

# `leave_party`

```elixir
@spec leave_party(Gamend.Accounts.User.t()) ::
  {:ok, :left | :disbanded} | {:error, term()}
```

Leave the current party.

A leader leaving HANDS THE PARTY OVER to the longest-present remaining member,
the way a lobby migrates its host — the party outliving one player is the
point of it. Regular members are simply removed, and whoever leaves last takes
the party with them, since there is nobody to hand it to.

To end a party outright rather than leave it, call `disband/1`.

# `list_all_parties`

```elixir
@spec list_all_parties(map(), keyword()) :: [Gamend.Parties.Party.t()]
```

List all parties with optional filters and pagination.

# `list_party_invitations`

```elixir
@spec list_party_invitations(Gamend.Accounts.User.t(), keyword()) :: [map()]
```

List pending party invites for the given user.

# `list_sent_party_invitations`

```elixir
@spec list_sent_party_invitations(Gamend.Accounts.User.t(), keyword()) :: [map()]
```

List pending party invites sent by the given leader.

Returns invitations the leader has sent that have not yet been accepted or declined.

# `quick_join_with_party`

```elixir
@spec quick_join_with_party(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Lobbies.Lobby.t()} | {:error, term()}
```

The party leader quick-joins a lobby with the entire party.

Searches for an open lobby that matches the given criteria (title,
max_users, metadata) and has enough space for the whole party. If no
matching lobby is found, creates a new one and joins all party members
atomically.

Returns `{:ok, lobby}` on success.

# `stats`

```elixir
@spec stats() :: %{
  parties_active: non_neg_integer(),
  players_in_parties: non_neg_integer()
}
```

Aggregate party counts for the public stats endpoint.

Membership is a user column (`users.party_id`, indexed), so both numbers are
derived counts rather than a maintained size.

# `subscribe_parties`

```elixir
@spec subscribe_parties() :: :ok | {:error, term()}
```

Subscribe to all party events (create/delete).

# `subscribe_party`

```elixir
@spec subscribe_party(Ecto.UUID.t()) :: :ok | {:error, term()}
```

Subscribe to events for a specific party.

# `unsubscribe_party`

```elixir
@spec unsubscribe_party(Ecto.UUID.t()) :: :ok
```

Unsubscribe from a party's events.

# `update_party`

```elixir
@spec update_party(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Parties.Party.t()}
  | {:error, atom() | Ecto.Changeset.t() | {:hook_rejected, term()}}
```

Update party settings. Only the leader can update.

`{:error, {:hook_rejected, reason}}` when `before_party_update` refuses.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
