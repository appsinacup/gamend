# `Gamend.Notifications.Preferences`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/notifications/preferences.ex#L1)

Which notifications a user wants, and how: per GROUP (a row on the
settings page: "Friends and groups", a host's "Streak about to end") and
per CHANNEL (`in_app`, `email`, `push`), plus three switches that win over
everything: all email off, all push off, everything off.

## Groups

Core declares its own; a host adds its own in config:

    config :gamend_core, :notification_groups, [
      %{key: "streak", label: "Streak about to end",
        defaults: %{"in_app" => true, "email" => false, "push" => false},
        types: ["streak_ending"], signup: true}
    ]

A group's `defaults` apply until the user chooses. `configurable` is the
channels the user may change (default: all three); a channel they may not
change always uses its default. `types` are the notification types
(`Gamend.Notifications.Types`) that belong to the group. `signup: true`
offers its email on the registration form, unticked: an email nobody asked
for is spam, so the user opts in. The "account" group — sign-in links, email
changes — is email that cannot be turned off: it is how the account works.
`admin: true` is a group for the site's admins only (a queue to work
through): nobody else sees its row (`groups_for/1`) or gets it
(`enabled?/3`).

Which channel a group defaults to follows one rule (2026-10-28):

  * **email on**: what the person asked for and waits on, a queue an admin
    must work through, or what they lose if they miss it: "Your reports"
    (a report's answer, a moderator's warning), "Reports to review";
  * **email off, theirs to turn on**: news and nudges ("Friends and
    groups", a host's streak reminder);
  * **on the site only**: what comes often and matters in the moment
    ("Chat messages", "Quests and rewards").

Stored in the user's private preferences (`Gamend.Accounts.Preferences`)
under `"notifications"`:

    %{"off_all" => bool, "off_email" => bool, "off_push" => bool,
      "groups" => %{group => %{channel => bool}}}

# `channels`

```elixir
@spec channels() :: [String.t()]
```

The channels, in the order the settings page shows them.

# `enabled?`

```elixir
@spec enabled?(Gamend.Accounts.User.t() | nil, String.t(), String.t()) :: boolean()
```

Whether `user` gets `group` through `channel`. A channel the group does not
let the user change is its default; otherwise the switches win (everything
off, then all email / all push off), then the user's own choice, then the
default. An unknown group is off, and so is an admins' group for anyone
else.

# `group`

```elixir
@spec group(String.t()) :: map() | nil
```

One group, or nil.

# `group_for_type`

```elixir
@spec group_for_type(term()) :: String.t() | nil
```

The group a notification TYPE (`Gamend.Notifications.Types`) belongs to, so
a friend request or a chat message follows the user's choices for its row.
nil for a type in no group (a moderator's notice), which is always sent.

# `groups`

```elixir
@spec groups() :: [map()]
```

Every group, core's first then the host's: `%{key, label, defaults,
configurable, types, signup, admin}`, `configurable` a list of channels.

# `groups_for`

```elixir
@spec groups_for(Gamend.Accounts.User.t() | nil) :: [map()]
```

The groups `user` may get: every one but the admins' (`admin: true`) for anyone else.

# `off?`

```elixir
@spec off?(Gamend.Accounts.User.t() | nil, String.t()) :: boolean()
```

Whether a switch is on: `"off_all"`, `"off_email"`, `"off_push"`.

# `put`

```elixir
@spec put(Gamend.Accounts.User.t(), String.t(), String.t(), boolean()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Set one group's channel. A channel the group does not let users change is refused.

# `signup_groups`

```elixir
@spec signup_groups() :: [map()]
```

The groups whose email the registration form offers (`signup: true`).

# `stored`

```elixir
@spec stored(Gamend.Accounts.User.t() | nil) :: map()
```

A user's stored choices (see the moduledoc's shape).

# `turn_off`

```elixir
@spec turn_off(Gamend.Accounts.User.t(), :email | :push | :all) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Turn off all email, all push, or everything (`:email | :push | :all`).

# `turn_on`

```elixir
@spec turn_on(Gamend.Accounts.User.t(), :email | :push | :all) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Undo `turn_off/2`: each group's own choices apply again.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
