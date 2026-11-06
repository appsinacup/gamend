# `Gamend.Groups.JoinRequests`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/groups/join_requests.ex#L1)

Join requests for private groups: requesting, listing, approving,
rejecting, and cancelling.

Public API is re-exported by `Gamend.Groups`.

# `approve_join_request`

```elixir
@spec approve_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupMember.t()}
  | {:error, atom() | {:hook_rejected, term()} | Ecto.Changeset.t()}
```

Approve a pending join request. Admin only.

# `cancel_join_request`

```elixir
@spec cancel_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupJoinRequest.t()} | {:error, atom()}
```

Cancel (delete) a pending join request. Only the requesting user can cancel.

# `count_join_requests`

```elixir
@spec count_join_requests(Ecto.UUID.t()) :: non_neg_integer()
```

# `list_join_requests`

```elixir
@spec list_join_requests(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
  {:ok, [Gamend.Groups.GroupJoinRequest.t()]} | {:error, atom()}
```

List pending join requests for a group (admin only).

# `list_user_pending_requests`

```elixir
@spec list_user_pending_requests(Ecto.UUID.t()) :: [
  Gamend.Groups.GroupJoinRequest.t()
]
```

List pending join requests sent by a user.

# `reject_join_request`

```elixir
@spec reject_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupJoinRequest.t()} | {:error, atom()}
```

Reject a pending join request. Admin only.

# `request_join`

```elixir
@spec request_join(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupJoinRequest.t()}
  | {:error, atom() | Ecto.Changeset.t()}
```

Request to join a private group. Creates a pending join request.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
