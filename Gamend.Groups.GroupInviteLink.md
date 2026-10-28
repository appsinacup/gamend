# `Gamend.Groups.GroupInviteLink`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/groups/group_invite_link.ex#L1)

Ecto schema for the `group_invite_links` table: a group's invite link
(`Gamend.Groups.InviteLinks`).

- `token` – the link's secret part, random and URL-safe
- `expires_at` – when the link stops working
- `uses` – how many people joined through it
- `created_by` – the admin who made it; the link works while they are one

# `t`

```elixir
@type t() :: %Gamend.Groups.GroupInviteLink{
  __meta__: term(),
  created_by: term(),
  created_by_id: term(),
  expires_at: term(),
  group: term(),
  group_id: term(),
  id: term(),
  inserted_at: term(),
  token: term(),
  updated_at: term(),
  uses: term()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
