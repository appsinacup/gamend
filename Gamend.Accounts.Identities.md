# `Gamend.Accounts.Identities`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/identities.ex#L1)

How a person signs in without a password — Discord, Apple, Google, Facebook,
GitHub, Steam or a device id — and linking those identities to an existing account or
removing them from one.

Split out of `Gamend.Accounts`, which still exposes every function here under
the same name.

# `attach_device_to_user`

```elixir
@spec attach_device_to_user(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Attach a device_id to an existing user record. Returns {:ok, user} or
{:error, changeset} if the device_id is already used.

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

# `find_or_create_from_github`

```elixir
@spec find_or_create_from_github(map()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Finds a user by GitHub ID or creates a new user from OAuth data.

## Examples

    iex> find_or_create_from_github(%{github_id: "123", email: "user@example.com"})
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
  :discord | :apple | :google | :facebook | :github | :steam
) ::
  {:ok, Gamend.Accounts.User.t()}
  | {:error, :last_provider | Ecto.Changeset.t() | term()}
```

Unlink an OAuth provider from a user's account.

provider should be one of :discord, :apple, :google, :facebook, :github, :steam.
This will return {:ok, user} when successful or {:error, reason}.

Guard: we only allow unlinking when the user will still have at least
one other social provider remaining. This prevents users losing all
social logins unexpectedly.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
