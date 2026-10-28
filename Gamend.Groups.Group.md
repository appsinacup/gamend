# `Gamend.Groups.Group`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/groups/group.ex#L1)

Ecto schema for the `groups` table.

A group is a persistent community that users can join. Unlike lobbies (which
are ephemeral game sessions), groups are long-lived and support admin roles,
join-request workflows, and invitation flows.

## Fields

- `title` – human-readable display title, unique unless the host turns
  `unique_titles` off (`Gamend.Groups`)
- `slug` – its name in a URL, unique per creator: `<owner>/<slug>`
  (`Gamend.Groups.full_slug/1`), made from the title when none is given
- `description` – optional longer description
- `icon_url` – optional icon; `nil` means clients show their default group icon
- `type` – visibility: `"public"`, `"private"`, or `"hidden"`
- `max_members` – maximum number of members (default 100, or the host's
  fixed `max_members`)
- `metadata` – arbitrary server-managed key/value map
- `creator_id` – the user who originally created the group

# `t`

```elixir
@type t() :: %Gamend.Groups.Group{
  __meta__: term(),
  creator: term(),
  creator_id: term(),
  description: term(),
  icon_url: term(),
  id: term(),
  inserted_at: term(),
  max_members: term(),
  members: term(),
  metadata: term(),
  slowdown: term(),
  slug: term(),
  title: term(),
  type: term(),
  updated_at: term()
}
```

# `changeset`

```elixir
@spec changeset(t(), map()) :: Ecto.Changeset.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
