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

```elixir
@spec attach_device_to_user(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Attach a device_id to an existing user record. Returns {:ok, user} or
{:error, changeset} if the device_id is already used.

# `broadcast_friend_update`

```elixir
@spec broadcast_friend_update(Gamend.Accounts.User.t()) :: :ok
```

Broadcast a `friend_updated` event to all accepted friends.

Used when public user data changes: map presence, display name, avatar,
player metadata, ship metadata, lobby/party state, etc.

# `broadcast_member_update`

```elixir
@spec broadcast_member_update(Gamend.Accounts.User.t()) :: :ok
```

Broadcast a `member_updated` event to the user's current lobby and
party channels so other members see the profile change (display name, avatar,
metadata, etc.) in real-time.

This is fire-and-forget and safe to call even when the user is not in a lobby
or party.

# `broadcast_user_update`

```elixir
@spec broadcast_user_update(Gamend.Accounts.User.t()) :: :ok
```

Broadcast that the given user has been updated.

This helper is intentionally small and only broadcasts a compact payload
intended for client consumption through the `user:<id>` topic.

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

```elixir
@spec change_user_display_name(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
```

Returns an `%Ecto.Changeset{}` for changing the user display_name.

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

```elixir
@spec change_user_registration(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
```

# `change_user_registration_for_validation`

```elixir
@spec change_user_registration_for_validation(Gamend.Accounts.User.t(), map()) ::
  Ecto.Changeset.t()
```

A registration changeset for live form feedback, with the uniqueness query
skipped.

`change_user_registration/2` runs `unsafe_validate_unique`, which is right on
submit and wrong on every keystroke: the registration form's `validate` event
is neither rate-limited nor captcha'd, so running it there turned the form
into an unauthenticated oracle for "does this address have an account here?",
one query per character typed. Submitting still checks, and the unique index
is what actually enforces it.

Separate function rather than an option, because `mix gen.sdk` cannot generate
a stub for a function carrying two default arguments.

# `change_username`

```elixir
@spec change_username(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
```

# `confirm_user`

```elixir
@spec confirm_user(Gamend.Accounts.User.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Confirms a user's email by setting confirmed_at timestamp.

## Examples

    iex> confirm_user(user)
    {:ok, %User{}}

# `confirm_user_by_token`

```elixir
@spec confirm_user_by_token(String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, :invalid | :not_found}
```

Confirm a user by an email confirmation token (context: "confirm").

Returns {:ok, user} when the token is valid and user was confirmed.
Returns {:error, :not_found} or {:error, :expired} when token is invalid/expired.

# `count_admins`

```elixir
@spec count_admins() :: non_neg_integer()
```

How many accounts hold the admin flag.

Used to refuse the write that would take that number to zero: nothing else can
grant `is_admin`, so an installation that reaches zero admins cannot be
administered again.

# `count_list_all_users`

```elixir
@spec count_list_all_users(map()) :: non_neg_integer()
```

Row count for `list_all_users/2` under the same filters.

# `count_search_users`

```elixir
@spec count_search_users(String.t()) :: non_neg_integer()
```

Count users matching a username/display name query or exact id. Returns integer.

# `count_unactivated_users`

```elixir
@spec count_unactivated_users() :: non_neg_integer()
```

Count users who are not yet activated (is_activated == false).

# `count_user_tokens`

```elixir
@spec count_user_tokens(Ecto.UUID.t()) :: non_neg_integer()
```

Counts tokens for a given user.

# `count_users`

```elixir
@spec count_users() :: non_neg_integer()
```

Returns the total number of users.

# `count_users_in_lobbies`

```elixir
@spec count_users_in_lobbies() :: non_neg_integer()
```

Count users currently seated in a lobby (`users.lobby_id`, indexed).

# `count_users_in_parties`

```elixir
@spec count_users_in_parties() :: non_neg_integer()
```

Count users currently in a party (`users.party_id`, indexed).

# `count_users_online`

```elixir
@spec count_users_online() :: non_neg_integer()
```

Count users currently marked as online.

# `count_users_with_password`

```elixir
@spec count_users_with_password() :: non_neg_integer()
```

Count users with a password set (hashed_password not nil/empty).

# `count_users_with_provider`

```elixir
@spec count_users_with_provider(atom()) :: non_neg_integer()
```

Count users with non-empty provider id for a given provider field (e.g. :google_id)

# `delete_user`

```elixir
@spec delete_user(Gamend.Accounts.User.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Deletes a user and associated resources.

Returns `{:ok, user}` on success or `{:error, changeset}` on failure.

# `delete_user_session_token`

```elixir
@spec delete_user_session_token(binary()) :: :ok
```

Deletes the signed token with the given context.

# `delete_user_storage`

```elixir
@spec delete_user_storage(Ecto.UUID.t()) :: :ok
```

Removes every stored object belonging to `user_id`.

Best-effort, like `prune_user_avatars/2`: a storage backend that is down must
not block an account deletion that has already happened at the database level.

# `deliver_login_instructions`

```elixir
@spec deliver_login_instructions(Gamend.Accounts.User.t(), (String.t() -&gt; String.t())) ::
  {:ok, Swoosh.Email.t()} | {:error, term()}
```

Delivers the magic link login instructions to the given user.

# `deliver_user_confirmation_instructions`

```elixir
@spec deliver_user_confirmation_instructions(Gamend.Accounts.User.t(), (String.t() -&gt;
                                                                    String.t())) ::
  {:ok, Swoosh.Email.t()} | {:error, :already_confirmed | term()}
```

# `deliver_user_update_email_instructions`

```elixir
@spec deliver_user_update_email_instructions(
  Gamend.Accounts.User.t(),
  String.t(),
  (String.t() -&gt; String.t())
) :: {:ok, Swoosh.Email.t()} | {:error, term()}
```

Delivers the update email instructions to the given user.

## Examples

    iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
    {:ok, %{to: ..., body: ...}}

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

# `find_or_create_from_apple`

```elixir
@spec find_or_create_from_apple(map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Finds a user by Apple ID or creates a new user from OAuth data.

## Examples

    iex> find_or_create_from_apple(%{apple_id: "123", email: "user@example.com"})
    {:ok, %User{}}

# `find_or_create_from_device`

```elixir
@spec find_or_create_from_device(String.t(), map()) ::
  {:ok, Gamend.Accounts.User.t()}
  | {:error, :disabled | Ecto.Changeset.t() | term()}
```

Finds or creates a user associated with the given device_id.

If a user already exists with the device_id we return it. Otherwise we
create an anonymous confirmed user and attach the device_id.

# `find_or_create_from_discord`

```elixir
@spec find_or_create_from_discord(map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Finds a user by Discord ID or creates a new user from OAuth data.

## Examples

    iex> find_or_create_from_discord(%{discord_id: "123", email: "user@example.com"})
    {:ok, %User{}}

# `find_or_create_from_facebook`

```elixir
@spec find_or_create_from_facebook(map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Finds a user by Facebook ID or creates a new user from OAuth data.

## Examples

    iex> find_or_create_from_facebook(%{facebook_id: "123", email: "user@example.com"})
    {:ok, %User{}}

# `find_or_create_from_google`

```elixir
@spec find_or_create_from_google(map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Finds a user by Google ID or creates a new user from OAuth data.

## Examples

    iex> find_or_create_from_google(%{google_id: "123", email: "user@example.com"})
    {:ok, %User{}}

# `find_or_create_from_steam`

```elixir
@spec find_or_create_from_steam(map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Finds a user by Steam ID or creates a new user from Steam OpenID data.

## Examples

    iex> find_or_create_from_steam(%{steam_id: "12345", email: "user@example.com"})
    {:ok, %User{}}

# `generate_user_session_token`

```elixir
@spec generate_user_session_token(Gamend.Accounts.User.t()) :: binary()
```

Generates a session token.

# `get_linked_providers`

```elixir
@spec get_linked_providers(Gamend.Accounts.User.t()) :: %{
  google: boolean(),
  facebook: boolean(),
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

# `get_user_by_google_id`

```elixir
@spec get_user_by_google_id(String.t()) :: Gamend.Accounts.User.t() | nil
```

Get a user by their Google ID.

Returns `%User{}` or `nil`.

# `get_user_by_magic_link_token`

```elixir
@spec get_user_by_magic_link_token(String.t()) :: Gamend.Accounts.User.t() | nil
```

Gets the user with the given magic link token.

# `get_user_by_session_token`

```elixir
@spec get_user_by_session_token(binary()) ::
  {Gamend.Accounts.User.t(), DateTime.t()} | nil
```

Gets the user with the given signed token.

If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.

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

```elixir
@spec link_account(Gamend.Accounts.User.t(), map(), atom(), (Gamend.Accounts.User.t(),
                                                       map() -&gt;
                                                         Ecto.Changeset.t())) ::
  {:ok, Gamend.Accounts.User.t()}
  | {:error, Ecto.Changeset.t() | {:conflict, Gamend.Accounts.User.t()}}
```

Link an OAuth provider to an existing user account. Updates the user
via the provider's oauth changeset while being careful not to overwrite
existing email or avatars.

Example: link_account(user, %{discord_id: "123", profile_url: "https://..."}, :discord_id, &User.discord_oauth_changeset/2)

# `link_device_id`

```elixir
@spec link_device_id(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Link a device_id to an existing user account. This allows the user to
authenticate using the device_id in addition to their OAuth providers.

Returns {:ok, user} on success or {:error, changeset} if the device_id
is already used by another account.

# `list_admin_ids`

```elixir
@spec list_admin_ids() :: [Ecto.UUID.t()]
```

Ids of every admin user.

Used to fan a moderation alert out to whoever can act on it. Not cached: the
callers are rare (a chat report arriving), and a stale list would silently
skip a newly promoted moderator.

# `list_all_users`

```elixir
@spec list_all_users(
  map(),
  keyword()
) :: [Gamend.Accounts.User.t()]
```

Admin user listing: search across identity fields (or an exact id), optional
facet filters, sorting and pagination — the query behind the admin Users page.

Distinct from `search_users/2`, the privacy-safe player search: this matches
sensitive fields a player cannot, so it is admin-only.

`filters` keys (string or atom): `:search` (term or full id), `:facets` (list
of `"online"`, `"unactivated"`, and provider names). `opts`: `:page`,
`:page_size`, `:sort_field`, `:sort_dir`.

# `list_user_tokens`

```elixir
@spec list_user_tokens(
  Ecto.UUID.t(),
  keyword()
) :: [Gamend.Accounts.UserToken.t()]
```

Lists tokens for a given user, optionally filtered by context.

# `login_user_by_magic_link`

```elixir
@spec login_user_by_magic_link(String.t()) ::
  {:ok, {Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
  | {:error, :not_found | Ecto.Changeset.t() | term()}
```

Logs the user in by magic link.

There are three cases to consider:

1. The user has already confirmed their email. They are logged in
   and the magic link is expired.

2. The user has not confirmed their email and no password is set.
   In this case, the user gets confirmed, logged in, and all tokens -
   including session ones - are expired. In theory, no other tokens
   exist but we delete all of them for best security practices.

3. The user has not confirmed their email but a password is set.
   This cannot happen in the default implementation but may be the
   source of security pitfalls. See the "Mixing magic link and password registration" section of
   `mix help phx.gen.auth`.

# `merge_metadata`

```elixir
@spec merge_metadata(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Merges `patch` into the user's metadata, leaving untouched every key it does
not mention.

The counterpart to `Gamend.Lobbies.merge_metadata/2`, and for the same
reason: `metadata` is one shared map, so a writer that replaces it wipes keys
belonging to code it has never heard of. Top-level merge, serialized so two
concurrent merges cannot lose each other.

# `player_stats`

```elixir
@spec player_stats() :: %{
  players_online: non_neg_integer(),
  players_total: non_neg_integer(),
  players_offline: non_neg_integer(),
  players_in_lobbies: non_neg_integer(),
  players_in_parties: non_neg_integer()
}
```

Aggregate player counts for the public stats endpoint.

Every field is derived, never a counter: a counter would put a write on the
login path (SQLite has one writer) and would drift from the bulk updates in
`touch_users/1` and `StalePresenceSweeper`. `players_online` rides the
partial index over online rows, so it scans the smallest set; the unfiltered
`players_total` cannot use an index at all, which is what the cache is for.

# `prune_user_avatars`

```elixir
@spec prune_user_avatars(Ecto.UUID.t(), String.t()) :: :ok
```

Delete a user's stored avatar objects except `keep_key`.

Each new avatar gets a fresh random key (`avatars/<user_id>/<rand><ext>`), so
without this the previous upload or mirror copy lingers in storage forever.
Best-effort: a failed cleanup leaves the old object rather than failing the
update that already succeeded.

# `refresh_account_class`

```elixir
@spec refresh_account_class(Gamend.Accounts.User.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Re-derive `account_class` for a user whose stored answer has not changed.

An account graduates on the first of its birth month, and nothing writes to it
on that day — the derivation is a function of the calendar, not of an event.
Call this to bring the denormalised column back in step, from a scheduled
sweep or on login.

# `register_user`

```elixir
@spec register_user(Gamend.Types.user_registration_attrs()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Registers a user.

## Attributes

See `t:Gamend.Types.user_registration_attrs/0` for available fields.

## Examples

    iex> register_user(%{email: "user@example.com", password: "secret123"})
    {:ok, %User{}}

    iex> register_user(%{email: "invalid"})
    {:error, %Ecto.Changeset{}}

# `register_user_and_deliver`

```elixir
@spec register_user_and_deliver(
  Gamend.Types.user_registration_attrs(),
  (String.t() -&gt; String.t()),
  module()
) :: {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Register a user and send the confirmation email inside a DB transaction.

The function accepts a `confirmation_url_fun` which must be a function of arity 1
that receives the encoded token and returns the confirmation URL string.

If sending the confirmation email fails the transaction is rolled back and
`{:error, reason}` is returned. On success it returns `{:ok, user}`.

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

```elixir
@spec revoke_all_user_sessions(Ecto.UUID.t()) :: {non_neg_integer(), nil}
```

Revokes all session tokens for a user (mass logout).

# `search_users`

```elixir
@spec search_users(String.t(), Gamend.Types.pagination_opts()) :: [
  Gamend.Accounts.User.t()
]
```

Search users by display name (case-insensitive prefix match) or exact numeric id.

Returns a list of User structs.

## Options

See `t:Gamend.Types.pagination_opts/0` for available options.

# `serialize_user_payload`

```elixir
@spec serialize_user_payload(Gamend.Accounts.User.t()) :: map()
```

Serialize a user into the compact payload used by realtime updates.

# `set_user_age`

```elixir
@spec set_user_age(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Record a user's age answer and re-derive what it permits.

Three things happen together, and they have to: the answer is stored, the
denormalised `account_class` is recomputed from it, and `grandfathered_at` is
cleared. That last one is the point — an account that predated the age gate
stops being treated as an adult-by-default the moment it tells us what it
actually is, in whichever direction that goes.

Refuses with `{:error, :age_change_not_allowed}` when the answer would raise
the user's age without a stronger signal than the one already recorded. See
`AgePolicy.may_change_age?/4`: lowering is always allowed, because it only
ever increases protection.

`attrs` must carry `birth_year`, `birth_month` and `age_method`, and should
carry `age_country` — without it the highest digital-consent age in the table
applies, which is the safe reading but not always the right one.

# `set_user_offline`

```elixir
@spec set_user_offline(Ecto.UUID.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Mark a user as offline and update last_seen_at.

Writes only on a real online→offline transition (see `set_user_online/1`).

Returns {:ok, user} on success.

# `set_user_online`

```elixir
@spec set_user_online(Ecto.UUID.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Mark a user as online and update last_seen_at.

Writes only on a real offline→online transition: reconnects and extra
tabs/sockets while already online are no-ops, so reconnect storms don't
hammer the `users` table (and the `after_user_online` hook fires once per
session, not once per socket).

Returns {:ok, user} on success.

# `sudo_mode?`

```elixir
@spec sudo_mode?(Gamend.Accounts.User.t(), integer()) :: boolean()
```

Checks whether the user is in sudo mode.

The user is in sudo mode when the last authentication was done no further
than 20 minutes ago. The limit can be given as second argument in minutes.

# `touch_last_seen`

```elixir
@spec touch_last_seen(Gamend.Accounts.User.t()) :: :ok
```

Updates `last_seen_at` to now for the given user. Fire-and-forget — errors are ignored.
Call on login (session or JWT) to track activity. Also records the UTC day
for `Gamend.Analytics` (DAU / retention).

# `touch_last_seen_by_id`

```elixir
@spec touch_last_seen_by_id(Ecto.UUID.t()) :: :ok
```

Lightweight version of `touch_last_seen/1` that accepts a user ID directly.
Performs a single UPDATE without loading the full struct first, setting
`last_seen_at` to now and `is_online` to true, then invalidates the cache.
Fire-and-forget — errors are ignored.

# `unlink_device_id`

```elixir
@spec unlink_device_id(Gamend.Accounts.User.t()) ::
  {:ok, Gamend.Accounts.User.t()}
  | {:error, :last_auth_method | Ecto.Changeset.t()}
```

Unlink the device_id from a user's account.

Returns {:ok, user} when successful or {:error, reason}.

Guard: we only allow unlinking when the user will still have at least
one authentication method remaining (OAuth provider or password).
This prevents users losing all login methods unexpectedly.

# `unlink_provider`

```elixir
@spec unlink_provider(
  Gamend.Accounts.User.t(),
  :discord | :apple | :google | :facebook | :steam
) ::
  {:ok, Gamend.Accounts.User.t()}
  | {:error, :last_provider | Ecto.Changeset.t() | term()}
```

Unlink an OAuth provider from a user's account.

provider should be one of :discord, :apple, :google, :facebook.
This will return {:ok, user} when successful or {:error, reason}.

Guard: we only allow unlinking when the user will still have at least
one other social provider remaining. This prevents users losing all
social logins unexpectedly.

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

```elixir
@spec update_user_avatar(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Set the user's avatar URL (`profile_url`), typically after an upload confirmed
by `Gamend.Storage`. Same cache/broadcast/hook path as other profile edits.

# `update_user_display_name`

```elixir
@spec update_user_display_name(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Updates the user's display name and broadcasts the change.

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

```elixir
@spec update_username(Gamend.Accounts.User.t(), map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Updates the user's unique username handle and broadcasts the change.

Strict, unlike registration: an invalid or taken username returns
`{:error, changeset}` with no generated fallback, so the player can pick
again. Routed through the `before_user_update` hook pipeline, where games
can forbid changes entirely or reject names (profanity, reserved words).

# `user_activated?`

```elixir
@spec user_activated?(Gamend.Accounts.User.t()) :: boolean()
```

Returns true when the given user is activated or when account activation
is not required. Returns false only when activation is required **and**
the user's `is_activated` flag is `false`.

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
