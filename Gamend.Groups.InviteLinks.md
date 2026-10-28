# `Gamend.Groups.InviteLinks`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/groups/invite_links.ex#L1)

A group's invite link: an admin makes one, shares it anywhere, and whoever
opens it while signed in joins the group as a member, without an invite of
their own or a request to approve. It works for every group type, hidden
ones too, and is a pull, like a class code: the person chooses to join,
nobody is added to anything.

One link per group. It lasts `link_days` (`GAMEND_GROUPS_LINK_DAYS`, 7 by
default, 0 turns links off); making a new one replaces the old, which
stops working at once, and an admin may turn it off. It also stops working
when the admin who made it is no longer one, so a demoted or departed
admin's link does not keep letting people in.

Joining through it takes the same room checks and `before_group_join`
hook as any other join (source `"invite_link"`), and tells the admin who
made the link, as an accepted invite does.

Public API is re-exported by `Gamend.Groups`.

# `create_invite_link`

```elixir
@spec create_invite_link(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, Gamend.Groups.GroupInviteLink.t()}
  | {:error, :links_off | :not_found | :not_admin | term()}
```

Make a group's link, replacing the one it had: a new token, lasting
`link_days` from now. Admins only.

# `delete_invite_link`

```elixir
@spec delete_invite_link(Ecto.UUID.t(), Ecto.UUID.t()) ::
  :ok | {:error, :links_off | :not_found | :not_admin}
```

Turn a group's link off. Admins only.

# `get_invite_link`

```elixir
@spec get_invite_link(Ecto.UUID.t()) :: Gamend.Groups.GroupInviteLink.t() | nil
```

A group's link, while it works: not expired, links on, its maker still an
admin. Nil otherwise. For the group's admins to show and copy.

# `get_invite_link_by_token`

```elixir
@spec get_invite_link_by_token(String.t()) :: Gamend.Groups.GroupInviteLink.t() | nil
```

The working link a token opens, its group preloaded, or nil: an unknown
token, an expired or replaced link, and one whose maker is no longer an
admin all read the same to whoever holds it.

# `join_by_invite_link`

```elixir
@spec join_by_invite_link(Ecto.UUID.t(), String.t()) ::
  {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
```

Join the group a link opens, as a member. `{:error, :not_found}` for a
link that does not work (see `get_invite_link_by_token/1`),
`{:error, :already_member}` for someone already in it, and the room
checks' `:full` and `:too_many_groups`.

# `link_days`

```elixir
@spec link_days() :: non_neg_integer()
```

How many days a new link lasts (`link_days`); 0 when links are off.

# `links?`

```elixir
@spec links?() :: boolean()
```

Whether groups may have invite links (`link_days` above 0).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
