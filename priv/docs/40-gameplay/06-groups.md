---
icon: hero-building-library
---

# Groups

A group is a persistent community - a clan, a guild, a class - that outlives any session, unlike a lobby or a party. Membership is a row carrying a role, `member` or `admin`, and the group's visibility type decides how new members get in: walk in, ask, or be invited.

## Visibility

| Type | Publicly listed | How you get in |
|---|---|---|
| `public` | yes | Join directly. Idempotent: joining a group you are in returns your membership. |
| `private` | yes | Request to join; an admin approves or rejects. |
| `hidden` | no - never in GET /groups or the `groups` feed | Invite only. A direct join answers 403 `not_joinable`. |

Every path in runs through the same guarded insert: the group's `max_members` cap, the per-user membership cap, and the game's before_group_join hook are all checked under the group's lock regardless of how the member arrived.

## Roles

The creator becomes an admin; everyone else starts as `member`. Admins - all of them, not just the creator - update the group, kick, promote, demote, invite, and handle join requests. Nobody promotes, demotes or kicks themselves.

Leaving keeps the group governed: the last admin walking out promotes the longest-standing member before going, and the creator walking out passes `creator_id` to another admin. When the last member leaves, the group deletes itself. An admin can delete it sooner, members and all, with `DELETE /api/v1/groups/:id` (`Gamend.Groups.delete_group/2` in server code); every other member gets a `group_deleted` notification. The admin console and `DELETE /api/v1/admin/groups/:id` delete it the same way.

## Join requests and invites

A request to join a private group is idempotent (asking twice returns the same pending request) and notifies every admin. Admins approve or reject it; the requester can cancel; the outcome lands on the requester's user channel as `group_join_request_approved` or `group_join_request_rejected`.

Invites are the admin's tool, and an admin may only invite **friends** ([/docs/friends](/docs/friends)) - a shared group is not enough, since anyone can join a public group and grant themselves that connection. Blocked pairs are refused. Inviting someone who already has a pending join request approves the request instead of creating an invite. An admin sees the group's pending invites, whoever sent them, and may cancel any of them (`GET /api/v1/groups/:id/invites`, `DELETE /api/v1/groups/sent_invitations/:invite_id`). Like party invites, the invite record is independent of its notification, and each player holds at most GAMEND_LIMITS_MAX_GROUP_PENDING_INVITES pending invites.

An admin may also share an **invite link** from the group's page on the website: anyone signed in who opens it joins as a member, whatever the group's type, hidden included. It is a pull, like a class code - nobody is added to anything. A group has one link at a time: making a new one stops the old at once, an admin may turn it off, and it stops working when it expires (GAMEND_GROUPS_LINK_DAYS, 7 days by default; 0 turns links off) or when the admin who made it is no longer one. Joining through it takes the same room checks and `before_group_join` hook as any join (source `"invite_link"`), and the admin who made it hears who joined. The link opens `<groups page>/join/<token>` - `/users/groups/join/...` on a host that routes its groups page at `/users/groups`, as Forge and Gamend Cloud do. Over HTTP, an admin reads, makes and turns off the link at `/api/v1/groups/:id/invite_link` (GET, POST, DELETE), and anyone signed in looks at the group a token opens (`GET /api/v1/groups/invite_links/:token`) and joins through it (`POST /api/v1/groups/invite_links/:token/join`).

## Icons and chat

A group's icon is an uploaded image: POST /groups/:id/icon/upload_url returns a presigned upload ticket, and POST /groups/:id/icon confirms the uploaded key - the same two-step flow every upload uses, see [/docs/object-storage](/docs/object-storage). Members talk in group chat, with per-group slowdown and admin mutes - see [/docs/chat](/docs/chat).

Groups also feed the social graph: sharing a group with someone makes them invitable to your party ([/docs/parties](/docs/parties)).

## HTTP API

Endpoints live under `/api/v1/groups` - see [/api/docs](/api/docs). What the spec cannot tell you: **POST /groups/:id/join is three endpoints wearing one path.** On a public group it seats you and returns the membership; on a private group it *creates a join request* and returns that (201); on a hidden group it answers 403. Group invites, unlike party invites, are answered by *invite id* (`/groups/invitations/:invite_id/accept`).

## Realtime events

Members listen on `group:{group_id}`: `updated`, `member_joined`, `member_left`, `member_kicked`, `member_promoted`, `member_demoted`, `member_online`, `member_offline`, `member_updated`, `join_request_approved`, `join_request_rejected` and the three `chat_message_*` events. A group browser listens on the `groups` topic: `group_created`, `group_updated`, `group_deleted` - hidden groups never appear there. Invite and request outcomes for a specific user arrive on their `user:{user_id}` channel (`group_invite_accepted`, `group_invite_cancelled`, `group_join_request_approved`, `group_join_request_rejected`).

## Server scripting

```elixir
{:ok, group} = Gamend.Groups.create_group(user_id, %{"title" => "Crimson Order"})
{:ok, member} = Gamend.Groups.join_group(user_id, group.id)
{:ok, request} = Gamend.Groups.request_join(user_id, private_group_id)
{:ok, member} = Gamend.Groups.approve_join_request(admin_id, request.id)

{:ok, _} = Gamend.Groups.promote_member(admin_id, group.id, target_id)
{:ok, _} = Gamend.Groups.kick_member(admin_id, group.id, target_id)

# One membership check the rest of the system leans on
Gamend.Groups.shared_group_member?(user_a_id, user_b_id)

# Announce to every member - server-side only, deliberately not an endpoint:
# one call fans out a notification per member, so it is a plugin primitive,
# not something a player can trigger.
{:ok, sent} = Gamend.Groups.notify_group(sender_id, group.id, "Raid at 8pm")
```

Hooks fire around create, update, join, leave, kick and delete (`before_group_create`, `after_group_join`, `after_group_deleted`, ...).

## Operations

- The Admin → Groups page (/admin/groups) lists and edits every group, hidden ones included. Admin HTTP mirrors: GET/PATCH/DELETE under /api/v1/admin/groups.
- The public site serves group pages at /groups (browse - hidden groups excluded, like the API listing) and /groups/:id (detail). These pages, the listing API and the feed all sit behind the `list_groups` feature flag.
- Private groups only, or teams: GAMEND_GROUPS_TYPES lists the types a group may be made or changed to, the first the default (`hidden` alone makes every group invite-only and unlisted) and GAMEND_GROUPS_INVITES=anyone lets an admin invite any account, found by name or exact email, rather than friends only. GAMEND_GROUPS_MAX_MEMBERS fixes every new group's cap (the forms stop asking it), and GAMEND_GROUPS_UNIQUE_TITLES=false lets two groups share a title, so a taken one tells no one a hidden group exists. `gamend_authenticated_live_routes(on_mount, groups: "/teams")` serves a player's groups on a page of their own.
- Slugs: every group has one, its name in a URL, made from the title unless given (`"Crimson Order"` is `crimson-order`, a creator's second of it `crimson-order-2`) and unique among its creator's groups. The page's URL names a group as `<owner>/<slug>` with the creator's username (`Gamend.Groups.full_slug/1`, `get_group_by_full_slug/1`); an admin may change it.
- Icons: a group's admins pick its icon from GAMEND_ICONS_CHOICES (heroicon names, the same list an account picks its avatar icon from), and over HTTP create and update take one by name (`icon`), which becomes its `icon_url`, `/icons/<name>.svg`. A group given none gets one at random; the website's forms start a new group from a random title (`Swift Otter`) and icon.
- Limits: GAMEND_LIMITS_MAX_GROUP_MEMBERS caps a group's `max_members`, GAMEND_LIMITS_MAX_GROUPS_CREATED_PER_USER caps how many groups one user can found, GAMEND_LIMITS_MAX_GROUPS_PER_USER caps memberships per user, and GAMEND_LIMITS_MAX_GROUP_TITLE / GAMEND_LIMITS_MAX_GROUP_DESCRIPTION cap the strings.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Groups`](https://docs.gamend.org/Gamend.Groups.html) - the functions a plugin calls, with their
  signatures and docs.
