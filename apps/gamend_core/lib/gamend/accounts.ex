defmodule Gamend.Accounts do
  @moduledoc """
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

  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: Gamend.Cache
  alias Gamend.Repo
  alias Gamend.Types

  alias Gamend.Accounts.{
    Broadcasts,
    Identities,
    LoginLockouts,
    PasswordHash,
    Presence,
    Profile,
    Registration,
    Search,
    Sessions,
    Stats,
    User,
    Username,
    UserToken
  }

  # Upper bound on cross-node staleness for cached user structs: explicit
  # invalidations propagate immediately via `Gamend.Cache.invalidate/1`,
  # and the cache TTL caps staleness if an invalidation broadcast is ever missed.
  @doc false
  def user_cache_ttl_ms, do: Gamend.Cache.ttl()

  @doc false
  def users_stats_cache_version do
    Gamend.Cache.get!({:accounts, :users_stats_version}) || 1
  end

  @doc false
  def invalidate_users_stats_cache do
    Gamend.Async.run(fn ->
      _ = Gamend.Cache.bump_version({:accounts, :users_stats_version})
      :ok
    end)

    :ok
  end

  # The context is split by concern; these keep every function reachable as
  # `Gamend.Accounts.<name>`, which is the public API plugins and hosts call.

  # Finding users — `Gamend.Accounts.Search`.
  @doc delegate_to: {Search, :search_users, 2}
  defdelegate search_users(query, opts \\ []), to: Search

  @doc delegate_to: {Search, :count_search_users, 1}
  defdelegate count_search_users(query), to: Search

  @doc delegate_to: {Search, :list_all_users, 2}
  defdelegate list_all_users(filters \\ %{}, opts \\ []), to: Search

  @doc delegate_to: {Search, :count_list_all_users, 1}
  defdelegate count_list_all_users(filters \\ %{}), to: Search

  # Counts for the dashboards — `Gamend.Accounts.Stats`.
  @doc delegate_to: {Stats, :count_users, 0}
  defdelegate count_users(), to: Stats

  @doc delegate_to: {Stats, :count_admins, 0}
  defdelegate count_admins(), to: Stats

  @doc delegate_to: {Stats, :count_users_with_provider, 1}
  defdelegate count_users_with_provider(provider_field), to: Stats

  @doc delegate_to: {Stats, :count_users_with_password, 0}
  defdelegate count_users_with_password(), to: Stats

  @doc delegate_to: {Stats, :list_admin_ids, 0}
  defdelegate list_admin_ids(), to: Stats

  @doc delegate_to: {Stats, :count_users_online, 0}
  defdelegate count_users_online(), to: Stats

  @doc delegate_to: {Stats, :player_stats, 0}
  defdelegate player_stats(), to: Stats

  @doc delegate_to: {Stats, :count_users_in_lobbies, 0}
  defdelegate count_users_in_lobbies(), to: Stats

  @doc delegate_to: {Stats, :count_users_in_parties, 0}
  defdelegate count_users_in_parties(), to: Stats

  @doc delegate_to: {Stats, :count_unactivated_users, 0}
  defdelegate count_unactivated_users(), to: Stats

  # Creating and confirming an account — `Gamend.Accounts.Registration`.
  @doc delegate_to: {Registration, :register_user, 1}
  defdelegate register_user(attrs), to: Registration

  @doc delegate_to: {Registration, :confirm_user, 1}
  defdelegate confirm_user(user), to: Registration

  @doc delegate_to: {Registration, :confirm_user_by_token, 1}
  defdelegate confirm_user_by_token(token), to: Registration

  @doc delegate_to: {Registration, :change_user_registration, 2}
  defdelegate change_user_registration(user, attrs \\ %{}), to: Registration

  @doc delegate_to: {Registration, :change_user_registration_for_validation, 2}
  defdelegate change_user_registration_for_validation(user, attrs), to: Registration

  @doc delegate_to: {Registration, :deliver_user_confirmation_instructions, 2}
  defdelegate deliver_user_confirmation_instructions(user, confirmation_url_fun), to: Registration

  # Signing in with a provider or a device, and linking identities — `Gamend.Accounts.Identities`.
  @doc delegate_to: {Identities, :find_or_create_from_discord, 1}
  defdelegate find_or_create_from_discord(attrs), to: Identities

  @doc delegate_to: {Identities, :find_or_create_from_apple, 1}
  defdelegate find_or_create_from_apple(attrs), to: Identities

  @doc delegate_to: {Identities, :find_or_create_from_google, 1}
  defdelegate find_or_create_from_google(attrs), to: Identities

  @doc delegate_to: {Identities, :find_or_create_from_facebook, 1}
  defdelegate find_or_create_from_facebook(attrs), to: Identities

  @doc delegate_to: {Identities, :find_or_create_from_github, 1}
  defdelegate find_or_create_from_github(attrs), to: Identities

  @doc delegate_to: {Identities, :find_or_create_from_steam, 1}
  defdelegate find_or_create_from_steam(attrs), to: Identities

  @doc delegate_to: {Identities, :find_or_create_from_device, 2}
  defdelegate find_or_create_from_device(device_id, attrs \\ %{}), to: Identities

  @doc delegate_to: {Identities, :attach_device_to_user, 2}
  defdelegate attach_device_to_user(user, device_id), to: Identities

  @doc delegate_to: {Identities, :link_account, 4}
  defdelegate link_account(user, attrs, provider_id_field, changeset_fn), to: Identities

  @doc delegate_to: {Identities, :link_device_id, 2}
  defdelegate link_device_id(user, device_id), to: Identities

  @doc delegate_to: {Identities, :unlink_device_id, 1}
  defdelegate unlink_device_id(user), to: Identities

  @doc delegate_to: {Identities, :unlink_provider, 2}
  defdelegate unlink_provider(user, provider), to: Identities

  # Session and magic-link tokens — `Gamend.Accounts.Sessions`.
  @doc delegate_to: {Sessions, :generate_user_session_token, 1}
  defdelegate generate_user_session_token(user), to: Sessions

  @doc delegate_to: {Sessions, :get_user_by_session_token, 1}
  defdelegate get_user_by_session_token(token), to: Sessions

  @doc delegate_to: {Sessions, :get_user_by_magic_link_token, 1}
  defdelegate get_user_by_magic_link_token(token), to: Sessions

  @doc delegate_to: {Sessions, :login_user_by_magic_link, 1}
  defdelegate login_user_by_magic_link(token), to: Sessions

  @doc delegate_to: {Sessions, :deliver_user_update_email_instructions, 3}
  defdelegate deliver_user_update_email_instructions(user, current_email, update_email_url_fun),
    to: Sessions

  @doc delegate_to: {Sessions, :deliver_login_instructions, 2}
  defdelegate deliver_login_instructions(user, magic_link_url_fun), to: Sessions

  @doc delegate_to: {Sessions, :delete_user_session_token, 1}
  defdelegate delete_user_session_token(token), to: Sessions

  @doc false
  defdelegate get_user_token(id), to: Sessions

  @doc false
  defdelegate get_user_token!(id), to: Sessions

  @doc false
  defdelegate delete_user_token(token), to: Sessions

  @doc delegate_to: {Sessions, :list_user_tokens, 2}
  defdelegate list_user_tokens(user_id, opts \\ []), to: Sessions

  @doc delegate_to: {Sessions, :count_user_tokens, 1}
  defdelegate count_user_tokens(user_id), to: Sessions

  @doc delegate_to: {Sessions, :revoke_all_user_sessions, 1}
  defdelegate revoke_all_user_sessions(user_id), to: Sessions

  # Display name, username, avatar, age and metadata — `Gamend.Accounts.Profile`.
  @doc delegate_to: {Profile, :change_user_display_name, 2}
  defdelegate change_user_display_name(user, attrs \\ %{}), to: Profile

  @doc delegate_to: {Profile, :change_username, 2}
  defdelegate change_username(user, attrs \\ %{}), to: Profile

  @doc delegate_to: {Profile, :update_user_avatar, 2}
  defdelegate update_user_avatar(user, url), to: Profile

  @doc delegate_to: {Profile, :delete_user_storage, 1}
  defdelegate delete_user_storage(user_id), to: Profile

  @doc delegate_to: {Profile, :prune_user_avatars, 2}
  defdelegate prune_user_avatars(user_id, keep_key), to: Profile

  @doc delegate_to: {Profile, :merge_metadata, 2}
  defdelegate merge_metadata(user, patch), to: Profile

  @doc delegate_to: {Profile, :update_user_display_name, 2}
  defdelegate update_user_display_name(user, attrs), to: Profile

  @doc delegate_to: {Profile, :set_user_age, 2}
  defdelegate set_user_age(user, attrs), to: Profile

  @doc delegate_to: {Profile, :refresh_account_class, 1}
  defdelegate refresh_account_class(user), to: Profile

  @doc delegate_to: {Profile, :update_username, 2}
  defdelegate update_username(user, attrs), to: Profile

  # Online state and last seen — `Gamend.Accounts.Presence`.
  @doc delegate_to: {Presence, :touch_last_seen, 1}
  defdelegate touch_last_seen(user), to: Presence

  @doc delegate_to: {Presence, :touch_last_seen_by_id, 1}
  defdelegate touch_last_seen_by_id(user_id), to: Presence

  @doc delegate_to: {Presence, :set_user_online, 1}
  defdelegate set_user_online(user_id), to: Presence

  @doc delegate_to: {Presence, :set_user_offline, 1}
  defdelegate set_user_offline(user_id), to: Presence

  @doc false
  defdelegate after_presence_write(user), to: Presence

  # Telling clients a user changed — `Gamend.Accounts.Broadcasts`.
  @doc delegate_to: {Broadcasts, :broadcast_user_update, 1}
  defdelegate broadcast_user_update(user), to: Broadcasts

  @doc delegate_to: {Broadcasts, :broadcast_member_update, 1}
  defdelegate broadcast_member_update(user), to: Broadcasts

  @doc delegate_to: {Broadcasts, :broadcast_friend_update, 1}
  defdelegate broadcast_friend_update(user), to: Broadcasts

  @doc delegate_to: {Broadcasts, :serialize_user_payload, 1}
  defdelegate serialize_user_payload(user), to: Broadcasts

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    normalized = email |> String.trim() |> String.downcase()

    if normalized == "" do
      nil
    else
      get_user_by_field(:email, normalized)
    end
  end

  @doc false
  def invalidate_users_count_cache do
    Gamend.Async.run(fn ->
      _ = Gamend.Cache.invalidate({:accounts, :users_count})
      :ok
    end)

    :ok
  end

  @doc delegate_to: {Registration, :register_user_and_deliver, 3}
  defdelegate register_user_and_deliver(
                attrs,
                confirmation_url_fun,
                notifier \\ Gamend.Accounts.UserNotifier
              ),
              to: Registration

  @doc delegate_to: {Registration, :register_user_with_password_and_deliver, 3}
  defdelegate register_user_with_password_and_deliver(
                attrs,
                confirmation_url_fun,
                notifier \\ Gamend.Accounts.UserNotifier
              ),
              to: Registration

  @doc """
  Gets a user by email and password. `nil` for a wrong password, and for an
  address locked by too many failures (`authenticate_by_password/2` says which).

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    case authenticate_by_password(email, password) do
      {:ok, user} -> user
      {:error, _reason} -> nil
    end
  end

  @doc """
  Checks an email and password, counting failures per address
  (`Gamend.Accounts.LoginLockouts`).

  `{:error, {:locked, seconds}}` when the address is locked, before the
  password is looked at, and for the failure that locks it.
  """
  @spec authenticate_by_password(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_credentials | {:locked, pos_integer()}}
  def authenticate_by_password(email, password)
      when is_binary(email) and is_binary(password) do
    case LoginLockouts.check(email) do
      :ok -> check_password(email, password)
      {:locked, seconds} -> {:error, {:locked, seconds}}
    end
  end

  defp check_password(email, password) do
    user = get_user_by_email(email)

    if User.valid_password?(user, password) do
      maybe_upgrade_password_hash(user, password)
      LoginLockouts.clear(email)
      {:ok, user}
    else
      case LoginLockouts.record_failure(email) do
        :ok -> {:error, :invalid_credentials}
        {:locked, seconds} -> {:error, {:locked, seconds}}
      end
    end
  end

  # A correct login is the only moment the plaintext exists on the server, so
  # it is the only chance to move a row off bcrypt. Run off the request: the
  # user who happens to trigger the migration should not be the one who waits
  # for a second hash. Two concurrent logins race to write the same thing,
  # which is harmless — either hash verifies the same password.
  defp maybe_upgrade_password_hash(%User{hashed_password: hash} = user, password)
       when is_binary(hash) do
    if PasswordHash.needs_rehash?(hash) do
      Gamend.Async.run(fn ->
        case user
             |> Ecto.Changeset.change(hashed_password: PasswordHash.hash(password))
             |> Repo.update() do
          {:ok, updated} -> invalidate_user_cache(updated)
          {:error, _} -> :ok
        end
      end)
    end

    :ok
  end

  defp maybe_upgrade_password_hash(_user, _password), do: :ok

  @doc """
  Returns true when `password` matches the user's current password.
  """
  @spec valid_password?(User.t(), term()) :: boolean()
  def valid_password?(%User{} = user, password) when is_binary(password) do
    User.valid_password?(user, password)
  end

  def valid_password?(_user, _password), do: false

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_user!(Ecto.UUID.t()) :: User.t()
  def get_user!(id) do
    case get_user(id) do
      %User{} = user ->
        user

      nil ->
        raise Ecto.NoResultsError, queryable: User
    end
  end

  @doc """
  Gets a single user by ID.

  Returns `nil` if the User does not exist.

  ## Examples

      iex> get_user(123)
      %User{}

      iex> get_user(Ecto.UUID.generate())
      nil

  """
  @spec get_user(Ecto.UUID.t()) :: User.t() | nil
  @decorate cacheable(
              key: {:accounts, :user, id},
              match: &cache_match/1,
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_user(id), do: Repo.get_uuid(User, id)

  @doc """
  How to name a user in text a PLAYER reads: `"Ana (drift-2378)"`, or just the
  username when there is no display name. Mirrors the client's
  `UserDisplayUtil.name_with_username`, so a notification and the friends list
  it sends you to name the same person the same way.

  Never falls back to the id. Every account has a server-assigned username, and
  `"User #0198f7be-…"` reads like a name while telling the reader nothing.
  """
  @spec display_label(User.t() | Ecto.UUID.t() | nil) :: String.t()
  def display_label(nil), do: ""

  def display_label(%User{} = user) do
    name = String.trim(user.display_name || "")
    handle = String.trim(user.username || "")

    cond do
      name == "" -> handle
      handle == "" or String.downcase(name) == String.downcase(handle) -> name
      true -> "#{name} (#{handle})"
    end
  end

  def display_label(user_id) do
    case get_user(user_id) do
      %User{} = user -> display_label(user)
      _ -> ""
    end
  end

  @doc """
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
  """
  @spec user_exists?(term()) :: boolean()
  def user_exists?(id), do: get_user(id) != nil

  @doc """
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
  """
  @spec display_name(User.t() | Ecto.UUID.t() | nil) :: String.t()
  def display_name(nil), do: ""

  def display_name(%User{} = user) do
    case String.trim(user.display_name || "") do
      "" -> String.trim(user.username || "")
      name -> name
    end
  end

  def display_name(user_id) do
    case get_user(user_id) do
      %User{} = user -> display_name(user)
      _ -> ""
    end
  end

  @doc """
  Map of `%{id => %User{}}` for the given ids, for batch name lookups (e.g. admin
  tables that hold only a `user_id`). Nil/duplicate ids are ignored.
  """
  @spec users_by_ids([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => User.t()}
  def users_by_ids(ids) when is_list(ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    from(u in User, where: u.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  @doc false
  @decorate cacheable(
              key: {:accounts, :user_by, field, value},
              references: &(&1 && keyref({:accounts, :user, &1.id})),
              match: &cache_match/1,
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_user_by_field(field, value) when is_atom(field) do
    Repo.get_by(User, [{field, value}])
  end

  @doc """
  Stores `user` under the canonical user cache key (with the standard TTL).

  Call after writes that update the user row outside this module (e.g. lobby
  or party membership) so subsequent `get_user/1` reads stay warm and
  consistent instead of serving the pre-write struct until the TTL expires.
  """
  @spec cache_user(User.t()) :: User.t()
  def cache_user(%User{} = user) do
    # Evict on all other instances first so their L1 refetches the fresh
    # struct; the put re-warms this node and the shared L2.
    _ = Gamend.Cache.invalidate({:accounts, :user, user.id})
    _ = Gamend.Cache.put({:accounts, :user, user.id}, user, ttl: Gamend.Cache.ttl())
    user
  end

  @doc false
  @spec cache_match(term()) :: boolean()
  def cache_match(nil), do: false
  def cache_match(_), do: true

  @user_cache_fields [
    :email,
    :device_id,
    :steam_id,
    :google_id,
    :apple_id,
    :discord_id,
    :facebook_id,
    :github_id
  ]

  defp user_index_keys(%User{} = user) do
    Enum.reduce(@user_cache_fields, [], fn field, acc ->
      value = Map.get(user, field)

      cond do
        is_binary(value) and String.trim(value) != "" and field == :email ->
          [{:accounts, :user_by, :email, String.downcase(value)} | acc]

        is_binary(value) and String.trim(value) != "" ->
          [{:accounts, :user_by, field, value} | acc]

        true ->
          acc
      end
    end)
  end

  @doc false
  def invalidate_user_cache(%User{id: id} = user) do
    _ = Gamend.Cache.invalidate({:accounts, :user, id})

    user
    |> user_index_keys()
    |> Enum.each(fn key ->
      _ = Gamend.Cache.invalidate(key)
    end)

    :ok
  end

  @doc """
  Public cache invalidation for cross-module use (lobbies, parties, groups).
  Accepts a user ID and clears both the primary and all index caches.
  """
  @spec invalidate_user_cache_by_id(Ecto.UUID.t()) :: :ok
  def invalidate_user_cache_by_id(user_id) when is_binary(user_id) do
    case Repo.get(User, user_id) do
      %User{} = user -> invalidate_user_cache(user)
      nil -> _ = Gamend.Cache.invalidate({:accounts, :user, user_id})
    end

    :ok
  end

  @doc """
  Get a user by their Steam ID (steam_id).

  Returns `%User{}` or `nil`.
  """
  @spec get_user_by_steam_id(String.t()) :: User.t() | nil
  def get_user_by_steam_id(steam_id) when is_binary(steam_id) do
    get_user_by_field(:steam_id, steam_id)
  end

  @doc """
  Get a user by their Google ID.

  Returns `%User{}` or `nil`.
  """
  @spec get_user_by_google_id(String.t()) :: User.t() | nil
  def get_user_by_google_id(google_id) when is_binary(google_id) do
    get_user_by_field(:google_id, google_id)
  end

  @doc """
  Get a user by their Apple ID.

  Returns `%User{}` or `nil`.
  """
  @spec get_user_by_apple_id(String.t()) :: User.t() | nil
  def get_user_by_apple_id(apple_id) when is_binary(apple_id) do
    get_user_by_field(:apple_id, apple_id)
  end

  @doc """
  Get a user by their Discord ID.

  Returns `%User{}` or `nil`.
  """
  @spec get_user_by_discord_id(String.t()) :: User.t() | nil
  def get_user_by_discord_id(discord_id) when is_binary(discord_id) do
    get_user_by_field(:discord_id, discord_id)
  end

  @doc """
  Get a user by their Facebook ID.

  Returns `%User{}` or `nil`.
  """
  @spec get_user_by_facebook_id(String.t()) :: User.t() | nil
  def get_user_by_facebook_id(facebook_id) when is_binary(facebook_id) do
    get_user_by_field(:facebook_id, facebook_id)
  end

  @doc """
  Get a user by their GitHub ID.

  Returns `%User{}` or `nil`.
  """
  @spec get_user_by_github_id(String.t()) :: User.t() | nil
  def get_user_by_github_id(github_id) when is_binary(github_id) do
    get_user_by_field(:github_id, github_id)
  end

  @doc """
  Gets a user by their unique username handle (case-insensitive; usernames
  are stored lowercase).
  """
  @spec get_user_by_username(String.t()) :: User.t() | nil
  def get_user_by_username(username) when is_binary(username) do
    get_user_by_field(:username, Username.normalize(username))
  end

  @doc """
  Whether `user` may upload an avatar, per `anonymous_can_upload_avatar`.
  """
  @spec can_upload_avatar?(User.t()) :: boolean()
  def can_upload_avatar?(%User{} = user) do
    not User.anonymous?(user) or
      Gamend.Settings.get(__MODULE__, :anonymous_can_upload_avatar)
  end

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :auth,
    label: "Authentication"

  setting(:device_auth_enabled, :boolean,
    default: true,
    doc:
      "Allow POST /api/v1/login/device. When on, any unknown device_id creates an anonymous account."
  )

  setting(:anonymous_can_upload_avatar, :boolean,
    default: false,
    doc:
      "Allow device-only accounts to upload an avatar. Off by default: an anonymous " <>
        "account costs one request to create, so this is the cheapest way for a bot " <>
        "to burn object storage."
  )

  setting(:require_activation, :boolean,
    default: false,
    doc: "New accounts cannot log in until an admin activates them (beta mode)."
  )

  # Dev and test carry compiled values (config/dev.exs, config/test.exs), so
  # this only ever fires on a real deployment. Generate one with
  # `mix phx.gen.secret`.
  setting(:secret_key_base, :string,
    secret: true,
    required: :prod,
    doc: "Signs and encrypts cookies, tokens and LiveView sessions."
  )

  setting(:guardian_secret_key, :string,
    secret: true,
    doc: "JWT signing key. Defaults to secret_key_base when unset."
  )

  setting(:access_token_ttl_minutes, :integer,
    default: 15,
    doc:
      "Lifetime of API access tokens, in minutes. Login and refresh answer it as expires_in. " <>
        "Applies to tokens issued after the change."
  )

  setting(:refresh_token_ttl_days, :integer,
    default: 30,
    doc:
      "Lifetime of API refresh tokens, in days. A refresh keeps its token, so this is how " <>
        "long a client stays signed in without logging in again."
  )

  setting(:session_days, :integer,
    default: 14,
    doc:
      "Lifetime of a browser session and its remember-me cookie, in days. An active " <>
        "session is renewed once it is half this old."
  )

  setting(:magic_link_minutes, :integer,
    default: 15,
    doc:
      "How long an emailed login link stays valid, in minutes. Capped at 60: anyone who " <>
        "can read the email can sign in while the link lives."
  )

  setting(:confirm_email_days, :integer,
    default: 7,
    doc: "How long an email confirmation link stays valid, in days."
  )

  setting(:change_email_days, :integer,
    default: 7,
    doc: "How long the link confirming a new email address stays valid, in days."
  )

  setting(:sudo_mode_minutes, :integer,
    default: 10,
    doc:
      "How recently a user must have signed in to open the settings that change their " <>
        "password or email. Submitting the form is allowed 10 minutes more."
  )

  setting(:api_token_max_days, :integer,
    default: 0,
    doc:
      "Longest lifetime a personal API token may have, in days. Applies to existing tokens " <>
        "too, counted from creation. 0 allows tokens that never expire."
  )

  setting(:lockout_attempts, :integer,
    default: 10,
    doc:
      "Failed passwords for one email address that lock its password sign-in. Counted per " <>
        "address across every IP. 0 disables the lockout."
  )

  setting(:lockout_window_minutes, :integer,
    default: 15,
    doc: "The failures must fall within this many minutes to lock."
  )

  setting(:lockout_minutes, :integer,
    default: 15,
    doc:
      "How long a lock lasts. Emailed login links and provider sign-in still work " <>
        "meanwhile, so the owner is never shut out."
  )

  setting(:deletion_grace_days, :integer,
    default: 0,
    doc:
      "Days between a player deleting their own account and it being deleted. Signing in " <>
        "on the website within that time keeps the account. 0 deletes at once."
  )

  @doc "Whether device-based auth is enabled. Defaults to on."
  @spec device_auth_enabled?() :: boolean()
  def device_auth_enabled?, do: Gamend.Settings.get(__MODULE__, :device_auth_enabled) == true

  @doc """
  Whether new accounts require manual admin activation before they can log in.
  """
  @spec require_account_activation?() :: boolean()
  def require_account_activation?,
    do: Gamend.Settings.get(__MODULE__, :require_activation) == true

  @doc """
  Returns true when the given user is activated or when account activation
  is not required. Returns false only when activation is required **and**
  the user's `is_activated` flag is `false`.
  """
  @spec user_activated?(User.t()) :: boolean()
  def user_activated?(%User{is_activated: true}), do: true
  def user_activated?(%User{is_admin: true}), do: true

  def user_activated?(%User{is_activated: false}) do
    not require_account_activation?()
  end

  def user_activated?(_), do: true

  ## Settings

  # Opening a sudo page needs a sign-in within `sudo_mode_minutes`; submitting
  # its form gets this much longer, so a user who opened the page just inside
  # the window can still finish typing.
  @sudo_form_grace_minutes 10

  @doc "How recently a user must have signed in to open a sudo page (`auth.sudo_mode_minutes`)."
  @spec sudo_mode_minutes() :: pos_integer()
  def sudo_mode_minutes, do: max(Gamend.Settings.get(__MODULE__, :sudo_mode_minutes), 1)

  @doc """
  Checks whether the user is in sudo mode.

  With one argument, the window is the one a sudo form is submitted in:
  `sudo_mode_minutes/0` plus ten minutes to fill the form in. The limit can be
  given as second argument in minutes (negative, as an offset from now).
  """
  @spec sudo_mode?(User.t()) :: boolean()
  @spec sudo_mode?(User.t(), integer()) :: boolean()
  def sudo_mode?(user), do: sudo_mode?(user, -(sudo_mode_minutes() + @sudo_form_grace_minutes))

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Gamend.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_email(User.t()) :: Ecto.Changeset.t()
  @spec change_user_email(User.t(), map()) :: Ecto.Changeset.t()
  @spec change_user_email(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  @spec update_user_email(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, :transaction_aborted}
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Gamend.AfterCommit.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           # Bump `token_version` with the address change, so JWTs issued to the
           # old identity stop verifying. `GamendWeb.Auth.Guardian` documents
           # this as already happening on email change; it did not.
           {:ok, updated_user} <-
             user
             |> User.email_changeset(%{email: email})
             |> bump_token_version()
             |> Repo.update(),
           {_count, _result} <-
             Repo.delete_all(
               from(UserToken, where: [user_id: ^updated_user.id, context: ^context])
             ) do
        invalidate_user_cache(user)
        invalidate_user_cache(updated_user)
        {:ok, updated_user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Gamend.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_password(User.t()) :: Ecto.Changeset.t()
  @spec change_user_password(User.t(), map()) :: Ecto.Changeset.t()
  @spec change_user_password(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_user_password(User.t(), map()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, Ecto.Changeset.t()}
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc "Days a player's own deletion waits (`auth.deletion_grace_days`); 0 deletes at once."
  @spec deletion_grace_days() :: non_neg_integer()
  def deletion_grace_days, do: max(Gamend.Settings.get(__MODULE__, :deletion_grace_days), 0)

  @doc """
  A player deleting their own account.

  With `auth.deletion_grace_days` at 0 the account is deleted now, by
  `delete_user/1`. Otherwise it is scheduled that many days out and signed out
  everywhere (every session, access, refresh and personal API token), and
  `Gamend.Retention` deletes it on the day unless its owner signs in on the
  website first (`cancel_deletion/1`). An account already scheduled keeps its
  date. The expired session tokens come back so the caller can disconnect
  their LiveViews.

  Admin deletions and the retention sweeps call `delete_user/1` and never wait.
  """
  @spec request_deletion(User.t()) ::
          {:ok, :deleted}
          | {:ok, {:scheduled, User.t(), [UserToken.t()]}}
          | {:error, Ecto.Changeset.t()}
  def request_deletion(%User{} = user) do
    case deletion_grace_days() do
      0 ->
        with {:ok, _user} <- delete_user(user), do: {:ok, :deleted}

      days ->
        at = user.deletion_scheduled_at || DateTime.add(DateTime.utc_now(:second), days, :day)

        with {:ok, {user, tokens}} <-
               user
               |> Ecto.Changeset.change(deletion_scheduled_at: at)
               |> update_user_and_delete_all_tokens() do
          {:ok, {:scheduled, user, tokens}}
        end
    end
  end

  @doc "Whether `user` is waiting out a deletion grace period."
  @spec deletion_scheduled?(User.t() | nil) :: boolean()
  def deletion_scheduled?(%User{deletion_scheduled_at: %DateTime{}}), do: true
  def deletion_scheduled?(_user), do: false

  @doc """
  Keep an account that was scheduled for deletion. A no-op for one that was not.
  """
  @spec cancel_deletion(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def cancel_deletion(%User{deletion_scheduled_at: nil} = user), do: {:ok, user}

  def cancel_deletion(%User{} = user) do
    with {:ok, user} <-
           user |> Ecto.Changeset.change(deletion_scheduled_at: nil) |> Repo.update() do
      invalidate_user_cache(user)
      cache_user(user)
      {:ok, user}
    end
  end

  @doc "Accounts whose deletion date has passed. For `Gamend.Retention`."
  @spec due_deletions_query() :: Ecto.Query.t()
  def due_deletions_query do
    now = DateTime.utc_now(:second)

    from(u in User,
      where: not is_nil(u.deletion_scheduled_at) and u.deletion_scheduled_at <= ^now
    )
  end

  @doc """
  Deletes a user and associated resources.

  Returns `{:ok, user}` on success or `{:error, changeset}` on failure.
  """
  alias Gamend.Lobbies

  @spec delete_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def delete_user(%User{} = user) do
    # Best-effort: try to remove the user from any party they may belong to.
    # If they are the leader the party is disbanded (PubSub + cache cleanup).
    try do
      _ = Gamend.Parties.leave_party(user)
    rescue
      _ -> :ok
    end

    # Best-effort: try to remove the user from any lobby they may belong to,
    # then delete the user regardless of hook checks (hooks for deletion were removed).
    try do
      _ = Lobbies.leave_lobby(user)
    rescue
      _ -> :ok
    end

    # Clean up group memberships (admin transfer + empty-group deletion)
    # before the DB cascade silently removes the membership rows.
    try do
      _ = Gamend.Groups.handle_user_deletion(user.id)
    rescue
      _ -> :ok
    end

    # Mark the user offline and notify friends before deleting the row.
    # Re-fetch to get current is_online state (the passed struct may be stale).
    fresh_user = Repo.get(User, user.id)

    if fresh_user && fresh_user.is_online do
      _ = set_user_offline(fresh_user.id)
    end

    case Repo.delete(user) do
      {:ok, _user} = ok ->
        invalidate_users_count_cache()

        # Friend DMs sent *to* this user (chat_type "friend", chat_ref_id = user)
        # have no FK to cascade — the sender's own messages go via sender_id, so
        # remove the inbound half here to avoid orphaned half-conversations.
        #
        # Isolated like the steps above: the row is already gone, so a failure
        # here must not skip the cleanups below — storage in particular, which
        # nothing else would ever revisit.
        try do
          _ = Gamend.Chat.cleanup_chat("friend", user.id)
        rescue
          _ -> :ok
        end

        # Deleting cache entries asynchronously can cause a short-lived race where
        # a delete followed immediately by a device login sees a stale cached user
        # for the same device_id/email and skips the "create" code path.
        invalidate_user_cache(user)

        # Notify plugins the user is gone so they can refresh derived state that
        # does not cascade at the DB level (e.g. maintained aggregate counters).
        # Cascaded rows (kv_entries, plugin FK tables) are already removed here.
        # Storage does not cascade: without this the user's avatars outlive the
        # account indefinitely, which defeats both retention and erasure requests.
        delete_user_storage(user.id)

        _ = Gamend.Hooks.internal_call(:after_user_deleted, [user])

        ok

      err ->
        err
    end

    # end delete_user
  end

  ## Token helper

  @doc """
  Revokes every credential the user holds: all session tokens are deleted and
  `token_version` is bumped, which invalidates all previously issued JWT
  access and refresh tokens ("log out everywhere").

  Returns `{:ok, {user, expired_tokens}}`.
  """
  @spec revoke_all_tokens(User.t()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, Ecto.Changeset.t()}
  def revoke_all_tokens(%User{} = user) do
    user
    |> Ecto.Changeset.change()
    |> update_user_and_delete_all_tokens()
  end

  @doc false
  def update_user_and_delete_all_tokens(changeset) do
    Gamend.AfterCommit.transact(fn ->
      changeset = bump_token_version(changeset)

      with {:ok, user} <- Repo.update(changeset) do
        # Re-warm with the post-revocation struct rather than only deleting it:
        # a concurrent auth read that loaded the pre-revocation row could otherwise
        # land its put after the delete and keep a revoked JWT valid until the TTL.
        invalidate_user_cache(user)
        cache_user(user)
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  # Invalidates all previously issued JWTs: `GamendWeb.Auth.Guardian`
  # embeds `token_version` as a claim and rejects tokens whose claim no longer
  # matches the user's current value.
  # Turning `is_activated` off revokes the account's tokens in the same write.
  # Verification checks activation as well (see `GamendWeb.Auth.Guardian`), but
  # bumping the version here is what makes the revocation immediate and explicit
  # rather than dependent on every future reader remembering to ask.
  defp revoke_on_deactivation(%Ecto.Changeset{} = changeset) do
    if Ecto.Changeset.get_change(changeset, :is_activated) == false do
      bump_token_version(changeset)
    else
      changeset
    end
  end

  defp bump_token_version(changeset) do
    current = Ecto.Changeset.get_field(changeset, :token_version)
    Ecto.Changeset.force_change(changeset, :token_version, current + 1)
  end

  @doc """
  Returns a map of linked OAuth providers for the user.

  Each provider is a boolean indicating whether that provider is linked.
  """
  @spec get_linked_providers(User.t()) :: %{
          google: boolean(),
          facebook: boolean(),
          github: boolean(),
          discord: boolean(),
          apple: boolean(),
          steam: boolean(),
          device: boolean()
        }
  def get_linked_providers(%User{} = user) do
    %{
      google: user.google_id != nil,
      facebook: user.facebook_id != nil,
      github: user.github_id != nil,
      discord: user.discord_id != nil,
      apple: user.apple_id != nil,
      steam: user.steam_id != nil,
      device: user.device_id != nil
    }
  end

  @doc """
  Returns whether the user has a password set.
  """
  @spec has_password?(User.t()) :: boolean()
  def has_password?(%User{} = user) do
    user.hashed_password != nil
  end

  @doc """
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

  """
  @spec update_user(User.t(), Types.user_update_attrs()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user(%User{} = user, attrs) when is_map(attrs) do
    with {:ok, attrs_to_use} <- run_before_user_update(user, attrs) do
      apply_user_update(user, attrs_to_use)
    end
  end

  # `update_user/2` in two halves, for a read-modify-write that must not hold
  # its lock across the plugin's hook: ask the hook first, then write under the
  # lock (`Gamend.Hooks.Default`'s payment metadata).
  @doc false
  @spec run_before_user_update(User.t(), map()) :: {:ok, map()} | {:error, term()}
  def run_before_user_update(%User{} = user, attrs) when is_map(attrs) do
    case Gamend.Hooks.internal_call(:before_user_update, [user, attrs]) do
      {:ok, returned} when is_map(returned) and not is_struct(returned) -> {:ok, returned}
      {:ok, _other} -> {:ok, attrs}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec apply_user_update(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def apply_user_update(%User{} = user, attrs) do
    case user |> User.admin_changeset(attrs) |> revoke_on_deactivation() |> Repo.update() do
      {:ok, updated} = ok ->
        invalidate_user_cache(user)
        invalidate_user_cache(updated)
        invalidate_users_stats_cache()
        broadcast_user_update(updated)
        broadcast_member_update(updated)

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_user_updated, [updated])
        end)

        ok

      other ->
        other
    end
  end
end
