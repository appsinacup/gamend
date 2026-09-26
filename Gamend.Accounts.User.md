# `Gamend.Accounts.User`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/user.ex#L1)

The User schema and associated changeset functions used across the
application (registration, OAuth, and admin changes).

This module keeps Ecto changesets for common user interactions and
validations so other domains can reuse them safely.

# `t`

```elixir
@type t() :: %Gamend.Accounts.User{
  __meta__: term(),
  account_class: String.t() | nil,
  age_country: String.t() | nil,
  age_locked_at: DateTime.t() | nil,
  age_method: String.t() | nil,
  apple_id: term(),
  authenticated_at: term(),
  birth_month: integer() | nil,
  birth_year: integer() | nil,
  confirmed_at: DateTime.t() | nil,
  deletion_scheduled_at: DateTime.t() | nil,
  device_id: term(),
  discord_id: term(),
  display_name: String.t() | nil,
  email: String.t() | nil,
  facebook_id: term(),
  github_id: term(),
  google_id: term(),
  grandfathered_at: DateTime.t() | nil,
  hashed_password: String.t() | nil,
  id: Ecto.UUID.t() | nil,
  inserted_at: term(),
  is_activated: term(),
  is_admin: term(),
  is_online: boolean(),
  last_seen_at: DateTime.t() | nil,
  lobby: term(),
  lobby_id: Ecto.UUID.t() | nil,
  metadata: map() | nil,
  party: term(),
  party_id: Ecto.UUID.t() | nil,
  password: term(),
  profile_url: term(),
  steam_id: term(),
  token_version: term(),
  updated_at: term(),
  username: String.t() | nil
}
```

The public user struct used across the application.

# `admin_changeset`

A user changeset for admin updates.

# `age_changeset`

Record an age answer.

Takes a year and a month and nothing finer — a caller that collected a full
date discards the day before it gets here, so the day is never written and
never stored. See the migration for why.

Validation only: whether the answer is *allowed* to replace an existing one is
`AgePolicy.may_change_age?/4`, and `Accounts.set_age/2` is what asks. A
changeset that enforced it too would make the rule two things to keep in step.

# `anonymous?`

```elixir
@spec anonymous?(t()) :: boolean()
```

True when nothing but a device id backs this account.

Such an account is created by `POST /api/v1/login/device` with no proof of
anything, costs an attacker one request, and cannot be emailed - which is why
it is the tier that gets the tighter quotas and the shorter retention window.

# `apple_oauth_changeset`

A user changeset for Apple OAuth registration.

It accepts email and Apple ID.

# `attach_device_changeset`

Changeset used when a device_id is present (linking device_id to user).
Ensures device_id is stored on user record and enforces uniqueness by DB
constraint.

# `avatar_changeset`

Changeset for setting the avatar URL (`profile_url`) from an upload.

# `confirm_changeset`

Confirms the account by setting `confirmed_at`.

# `device_changeset`

A user changeset used for device-based logins where there is no email.

Device users are created with optional display_name and metadata and are
immediately confirmed so the SDK can receive tokens without email confirmation.

# `discord_oauth_changeset`

A user changeset for Discord OAuth registration.

It accepts email and Discord fields.

# `display_name_changeset`

A simple changeset for updating a user's display name.

Allows empty string so users can set an empty display name if desired.

# `email_changeset`

A user changeset for registering or changing the email.

It requires the email to change otherwise an error is added.

## Options

  * `:validate_unique` - Set to false if you don't want to validate the
    uniqueness of the email, useful when displaying live validations.
    Defaults to `true`.

# `facebook_oauth_changeset`

A user changeset for Facebook OAuth registration.

It accepts email and Facebook ID.

# `github_oauth_changeset`

A user changeset for GitHub OAuth registration.

It accepts email and GitHub ID. The email may be absent: a GitHub App
without the email permission only sees the public profile.

# `google_oauth_changeset`

A user changeset for Google OAuth registration.

It accepts email and Google ID.

# `last_seen_at_or_fallback`

```elixir
@spec last_seen_at_or_fallback(t()) :: DateTime.t()
```

Returns `last_seen_at` when present, otherwise a stable fallback timestamp.

# `min_password_length`

```elixir
@spec min_password_length() :: pos_integer()
```

The minimum password length enforced at registration and change.

# `password_changeset`

A user changeset for changing the password.

It is important to validate the length of the password, as long passwords may
be very expensive to hash for certain algorithms.

## Options

  * `:hash_password` - Hashes the password so it can be stored securely
    in the database and ensures the password field is cleared to prevent
    leaks in the logs. If password hashing is not needed and clearing the
    password field is not desired (like when using this changeset for
    validations on a LiveView form), this option can be set to `false`.
    Defaults to `true`.

# `registration_changeset`

A user changeset for registering a new user.

# `serialize_brief`

```elixir
@spec serialize_brief(t()) :: map()
```

Serialize a user into a compact public map suitable for member lists in parties,
lobbies, and friends. Includes metadata for rendering player appearance.

# `steam_oauth_changeset`

A user changeset for Steam OpenID registration.

Expects steam_id and optional profile fields.

# `username_changeset`

A changeset for the unique username handle.

Input is NFKC-normalized and lowercased on cast. Valid usernames are 3–32
characters (`Gamend.Limits` `:min_username`/`:max_username`) of letters and
digits in one script, or Latin mixed with Chinese, Japanese or Korean,
joined by non-consecutive `.` `_` `-` separators and starting and ending on
a letter or digit — `Gamend.Accounts.Username` has the rules and why, and a
plugin replaces them with the `validate_username/1` hook. Length and the DB
unique index stay.

# `valid_password?`

Verifies the password.

If there is no user or the user doesn't have a password, we burn the same
time a real verification would to avoid timing attacks.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
