# `Gamend.Accounts`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts.ex#L1)

The Accounts context.

## Usage

    # Lookup by id or email
    user = Gamend.Accounts.get_user(123)
    user = Gamend.Accounts.get_user_by_email("me@example.com")

    # Update a user
    {:ok, user} = Gamend.Accounts.update_user(user, %{display_name: "NewName"})

    # Search (paginated) and count
    users = Gamend.Accounts.search_users("bob", page: 1, page_size: 25)
    count = Gamend.Accounts.count_search_users("bob")

# `attach_device_to_user`

# `broadcast_friend_update`

# `broadcast_member_update`

# `broadcast_user_update`

# `cache_user`

```elixir
@spec cache_user(Gamend.Accounts.User.t()) :: Gamend.Accounts.User.t()
```

Stores `user` under the canonical user cache key (with the standard TTL).

Call after writes that update the user row outside this module (e.g. lobby
or party membership) so subsequent `get_user/1` reads stay warm and
consistent instead of serving the pre-write struct until the TTL expires.

# `can_upload_avatar?`

```elixir
@spec can_upload_avatar?(Gamend.Accounts.User.t()) :: boolean()
```

Whether `user` may upload an avatar, per `anonymous_can_upload_avatar`.

# `change_user_display_name`

# `change_user_email`

```elixir
@spec change_user_email(Gamend.Accounts.User.t(), map(), keyword()) ::
  Ecto.Changeset.t()
```

Returns an `%Ecto.Changeset{}` for changing the user email.

See `Gamend.Accounts.User.email_changeset/3` for a list of supported options.

## Examples

    iex> change_user_email(user)
    %Ecto.Changeset{data: %User{}}

# `change_user_password`

```elixir
@spec change_user_password(Gamend.Accounts.User.t(), map(), keyword()) ::
  Ecto.Changeset.t()
```

Returns an `%Ecto.Changeset{}` for changing the user password.

See `Gamend.Accounts.User.password_changeset/3` for a list of supported options.

## Examples

    iex> change_user_password(user)
    %Ecto.Changeset{data: %User{}}

# `change_user_registration`

# `change_user_registration_for_validation`

# `change_username`

# `confirm_user`

# `confirm_user_by_token`

# `count_admins`

# `count_list_all_users`

# `count_search_users`

# `count_unactivated_users`

# `count_user_tokens`

# `count_users`

# `count_users_in_lobbies`

# `count_users_in_parties`

# `count_users_online`

# `count_users_with_password`

# `count_users_with_provider`

# `delete_user`

```elixir
@spec delete_user(Gamend.Accounts.User.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Deletes a user and associated resources.

Returns `{:ok, user}` on success or `{:error, changeset}` on failure.

# `delete_user_session_token`

# `delete_user_storage`

# `deliver_login_instructions`

# `deliver_user_confirmation_instructions`

# `deliver_user_update_email_instructions`

# `device_auth_enabled?`

```elixir
@spec device_auth_enabled?() :: boolean()
```

Whether device-based auth is enabled. Defaults to on.

# `display_label`

```elixir
@spec display_label(Gamend.Accounts.User.t() | Ecto.UUID.t() | nil) :: String.t()
```

How to name a user in text a PLAYER reads: `"Ana (drift-2378)"`, or just the
username when there is no display name. Mirrors the client's
`UserDisplayUtil.name_with_username`, so a notification and the friends list
it sends you to name the same person the same way.

Never falls back to the id. Every account has a server-assigned username, and
`"User #0198f7be-…"` reads like a name while telling the reader nothing.

# `display_name`

```elixir
@spec display_name(Gamend.Accounts.User.t() | Ecto.UUID.t() | nil) :: String.t()
```

The short form of `display_label/1`: the display name, or the username when
there is none. No parenthesised handle.

Use this where the name sits inside a sentence the player reads — "Ana
invited you" — and `display_label/1` where it stands on its own and the
handle disambiguates, such as an admin table or a friends list.

This exists because the fallback was being written inline, differently, in
four places: parties sent `display_name || ""`, so an invite from a player
who had set no display name arrived from nobody; group invites wrote
`display_name || username`; three admin views fell through to the email and
then the raw id, which `display_label/1` documents as the thing not to do.

# `find_or_create_from_apple`

# `find_or_create_from_device`

# `find_or_create_from_discord`

# `find_or_create_from_facebook`

# `find_or_create_from_github`

# `find_or_create_from_google`

# `find_or_create_from_steam`

# `generate_user_session_token`

# `get_linked_providers`

```elixir
@spec get_linked_providers(Gamend.Accounts.User.t()) :: %{
  google: boolean(),
  facebook: boolean(),
  github: boolean(),
  discord: boolean(),
  apple: boolean(),
  steam: boolean(),
  device: boolean()
}
```

Returns a map of linked OAuth providers for the user.

Each provider is a boolean indicating whether that provider is linked.

# `get_user`

```elixir
@spec get_user(Ecto.UUID.t()) :: Gamend.Accounts.User.t() | nil
```

Gets a single user by ID.

Returns `nil` if the User does not exist.

## Examples

    iex> get_user(123)
    %User{}

    iex> get_user(Ecto.UUID.generate())
    nil

# `get_user!`

```elixir
@spec get_user!(Ecto.UUID.t()) :: Gamend.Accounts.User.t()
```

Gets a single user.

Raises `Ecto.NoResultsError` if the User does not exist.

## Examples

    iex> get_user!(123)
    %User{}

    iex> get_user!(456)
    ** (Ecto.NoResultsError)

# `get_user_by_apple_id`

```elixir
@spec get_user_by_apple_id(String.t()) :: Gamend.Accounts.User.t() | nil
```

Get a user by their Apple ID.

Returns `%User{}` or `nil`.

# `get_user_by_discord_id`

```elixir
@spec get_user_by_discord_id(String.t()) :: Gamend.Accounts.User.t() | nil
```

Get a user by their Discord ID.

Returns `%User{}` or `nil`.

# `get_user_by_email`

```elixir
@spec get_user_by_email(String.t()) :: Gamend.Accounts.User.t() | nil
```

Gets a user by email.

## Examples

    iex> get_user_by_email("foo@example.com")
    %User{}

    iex> get_user_by_email("unknown@example.com")
    nil

# `get_user_by_email_and_password`

```elixir
@spec get_user_by_email_and_password(String.t(), String.t()) ::
  Gamend.Accounts.User.t() | nil
```

Gets a user by email and password.

## Examples

    iex> get_user_by_email_and_password("foo@example.com", "correct_password")
    %User{}

    iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
    nil

# `get_user_by_facebook_id`

```elixir
@spec get_user_by_facebook_id(String.t()) :: Gamend.Accounts.User.t() | nil
```

Get a user by their Facebook ID.

Returns `%User{}` or `nil`.

# `get_user_by_github_id`

```elixir
@spec get_user_by_github_id(String.t()) :: Gamend.Accounts.User.t() | nil
```

Get a user by their GitHub ID.

Returns `%User{}` or `nil`.

# `get_user_by_google_id`

```elixir
@spec get_user_by_google_id(String.t()) :: Gamend.Accounts.User.t() | nil
```

Get a user by their Google ID.

Returns `%User{}` or `nil`.

# `get_user_by_magic_link_token`

# `get_user_by_session_token`

# `get_user_by_steam_id`

```elixir
@spec get_user_by_steam_id(String.t()) :: Gamend.Accounts.User.t() | nil
```

Get a user by their Steam ID (steam_id).

Returns `%User{}` or `nil`.

# `get_user_by_username`

```elixir
@spec get_user_by_username(String.t()) :: Gamend.Accounts.User.t() | nil
```

Gets a user by their unique username handle (case-insensitive; usernames
are stored lowercase).

# `has_password?`

```elixir
@spec has_password?(Gamend.Accounts.User.t()) :: boolean()
```

Returns whether the user has a password set.

# `invalidate_user_cache_by_id`

```elixir
@spec invalidate_user_cache_by_id(Ecto.UUID.t()) :: :ok
```

Public cache invalidation for cross-module use (lobbies, parties, groups).
Accepts a user ID and clears both the primary and all index caches.

# `link_account`

# `link_device_id`

# `list_admin_ids`

# `list_all_users`

# `list_user_tokens`

# `login_user_by_magic_link`

# `merge_metadata`

# `player_stats`

# `prune_user_avatars`

# `refresh_account_class`

# `register_user`

# `register_user_and_deliver`

# `register_user_with_password_and_deliver`

# `require_account_activation?`

```elixir
@spec require_account_activation?() :: boolean()
```

Whether new accounts require manual admin activation before they can log in.

# `revoke_all_tokens`

```elixir
@spec revoke_all_tokens(Gamend.Accounts.User.t()) ::
  {:ok, {Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
  | {:error, Ecto.Changeset.t()}
```

Revokes every credential the user holds: all session tokens are deleted and
`token_version` is bumped, which invalidates all previously issued JWT
access and refresh tokens ("log out everywhere").

Returns `{:ok, {user, expired_tokens}}`.

# `revoke_all_user_sessions`

# `search_users`

# `serialize_user_payload`

# `set_user_age`

# `set_user_offline`

# `set_user_online`

# `sudo_mode?`

```elixir
@spec sudo_mode?(Gamend.Accounts.User.t(), integer()) :: boolean()
```

Checks whether the user is in sudo mode.

The user is in sudo mode when the last authentication was done no further
than 20 minutes ago. The limit can be given as second argument in minutes.

# `touch_last_seen`

# `touch_last_seen_by_id`

# `unlink_device_id`

# `unlink_provider`

# `update_user`

```elixir
@spec update_user(Gamend.Accounts.User.t(), Gamend.Types.user_update_attrs()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Updates a user with the given attributes.

This function applies the `User.admin_changeset/2` then updates the user and
broadcasts the update on success. It returns the same tuple shape as
`Repo.update/1` so callers can pattern-match as before.

## Attributes

See `t:Gamend.Types.user_update_attrs/0` for available fields.

## Examples

    iex> update_user(user, %{display_name: "NewName"})
    {:ok, %User{}}

    iex> update_user(user, %{metadata: %{level: 5}})
    {:ok, %User{}}

# `update_user_avatar`

# `update_user_display_name`

# `update_user_email`

```elixir
@spec update_user_email(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, :transaction_aborted}
```

Updates the user email using the given token.

If the token matches, the user email is updated and the token is deleted.

# `update_user_password`

```elixir
@spec update_user_password(Gamend.Accounts.User.t(), map()) ::
  {:ok, {Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
  | {:error, Ecto.Changeset.t()}
```

Updates the user password.

Returns a tuple with the updated user, as well as a list of expired tokens.

## Examples

    iex> update_user_password(user, %{password: ...})
    {:ok, {%User{}, [...]}}

    iex> update_user_password(user, %{password: "too short"})
    {:error, %Ecto.Changeset{}}

# `update_username`

# `user_activated?`

```elixir
@spec user_activated?(Gamend.Accounts.User.t()) :: boolean()
```

Returns true when the given user is activated or when account activation
is not required. Returns false only when activation is required **and**
the user's `is_activated` flag is `false`.

# `user_exists?`

```elixir
@spec user_exists?(term()) :: boolean()
```

Whether an account with this id exists.

For the contexts that write a row pointing at a user, before they write it.
SQLite — the default adapter — does not report *which* constraint an
`INSERT` violated, only that one was violated, so
`Ecto.Changeset.foreign_key_constraint/2` cannot match it and Ecto raises
`Ecto.ConstraintError` instead of returning a changeset. The declarations in
those schemas are therefore decorative on SQLite (the adapter's own docs say
so), and a bad `user_id` reaching the database surfaced as a 500.

Checking first costs one indexed read and gives the caller a real answer.
It is not a substitute for the foreign key: the row can still be deleted
between this and the write. That race ends where it did before, which is why
the constraint stays declared.

Returns `false` for a malformed id rather than raising, since these ids come
from request bodies and hook arguments.

Goes through `get_user/1` rather than a bare `Repo.exists?`, because this sits
on the hot write paths — a currency grant, a score submission — and
`get_user/1` is cached. A player earning currency during a session was
authenticated moments ago, so their row is already in the cache and this costs
nothing; `Repo.exists?` would take a connection from the pool every time.
Correctness is unchanged: `delete_user/1` invalidates that entry, and a
`nil` lookup is never cached (`cache_match/1`), so a missing user is re-checked
against the database each time rather than being remembered as absent.

# `users_by_ids`

```elixir
@spec users_by_ids([Ecto.UUID.t()]) :: %{
  required(Ecto.UUID.t()) =&gt; Gamend.Accounts.User.t()
}
```

Map of `%{id => %User{}}` for the given ids, for batch name lookups (e.g. admin
tables that hold only a `user_id`). Nil/duplicate ids are ignored.

# `valid_password?`

```elixir
@spec valid_password?(Gamend.Accounts.User.t(), term()) :: boolean()
```

Returns true when `password` matches the user's current password.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
