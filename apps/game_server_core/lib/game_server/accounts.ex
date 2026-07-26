defmodule GameServer.Accounts do
  @moduledoc """
  The Accounts context.

  ## Usage

      # Lookup by id or email
      user = GameServer.Accounts.get_user(123)
      user = GameServer.Accounts.get_user_by_email("me@example.com")

      # Update a user
      {:ok, user} = GameServer.Accounts.update_user(user, %{display_name: "NewName"})

      # Search (paginated) and count
      users = GameServer.Accounts.search_users("bob", page: 1, page_size: 25)
      count = GameServer.Accounts.count_search_users("bob")

  """

  import Ecto.Query, warn: false
  require Logger
  use Nebulex.Caching, cache: GameServer.Cache
  alias GameServer.Repo
  alias GameServer.Types

  alias GameServer.Accounts.{AvatarMirror, User, UsernameGenerator, UserNotifier, UserToken}

  @stats_cache_ttl_ms 60_000
  @users_count_cache_ttl_ms 60_000

  # Upper bound on cross-node staleness for cached user structs: explicit
  # invalidations propagate immediately via `GameServer.Cache.invalidate/1`,
  # and this TTL caps staleness if an invalidation broadcast is ever missed.
  @user_cache_ttl_ms 60_000

  defp users_stats_cache_version do
    GameServer.Cache.get!({:accounts, :users_stats_version}) || 1
  end

  defp invalidate_users_stats_cache do
    GameServer.Async.run(fn ->
      _ = GameServer.Cache.bump_version({:accounts, :users_stats_version})
      :ok
    end)

    :ok
  end

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

  @doc """
  Search users by display name (case-insensitive prefix match) or exact numeric id.

  Returns a list of User structs.

  ## Options

  See `t:GameServer.Types.pagination_opts/0` for available options.
  """
  @spec search_users(String.t()) :: [User.t()]
  @spec search_users(String.t(), Types.pagination_opts()) :: [User.t()]
  def search_users(query, opts \\ []) when is_binary(query) do
    q = String.trim(query)
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    if q == "" do
      []
    else
      normalized_q = String.downcase(q)
      text_results = search_users_by_text(normalized_q, page, page_size)

      maybe_prepend_id_match(text_results, q)
    end
  end

  # If `q` looks like a UUID, attempt a direct ID lookup and prepend the result
  # (deduplicated) to `results`.  Returns `results` unchanged otherwise.
  defp maybe_prepend_id_match(results, q) do
    if match?({:ok, _}, Ecto.UUID.cast(q)) do
      id = q

      case get_user(id) do
        nil -> results
        user -> [user | Enum.reject(results, &(&1.id == id))]
      end
    else
      results
    end
  end

  # Whether a user's display_name starts with `q` (case-insensitive), meaning
  # the text search already includes them.
  defp text_search_matches_user?(user, q) do
    nq = String.downcase(q)
    dn = (user.display_name || "") |> String.downcase()
    String.starts_with?(dn, nq)
  end

  defp search_users_by_text(normalized_q, page, page_size) do
    pattern = "#{Repo.escape_like(normalized_q)}%"
    offset = (page - 1) * page_size

    Repo.all(
      from u in User,
        where:
          fragment("lower(?) LIKE ? ESCAPE '\\'", u.display_name, ^pattern) or
            fragment("? LIKE ? ESCAPE '\\'", u.username, ^pattern),
        limit: ^page_size,
        offset: ^offset
    )
  end

  @doc """
  Count users matching a username/display name query or exact id. Returns integer.
  """
  @spec count_search_users(String.t()) :: non_neg_integer()
  def count_search_users(query) when is_binary(query) do
    q = String.trim(query)

    if q == "" do
      0
    else
      normalized_q = String.downcase(q)
      text_count = count_search_users_by_text(normalized_q)

      maybe_add_id_match_count(text_count, q)
    end
  end

  # If `q` looks like a UUID, check for an ID match and add 1 to the count
  # only if the user isn't already included in the text results.
  defp maybe_add_id_match_count(text_count, q) do
    if match?({:ok, _}, Ecto.UUID.cast(q)) do
      id = q

      case get_user(id) do
        nil -> text_count
        user -> if text_search_matches_user?(user, q), do: text_count, else: text_count + 1
      end
    else
      text_count
    end
  end

  defp count_search_users_by_text(normalized_q) do
    pattern = "#{Repo.escape_like(normalized_q)}%"

    Repo.one(
      from u in User,
        where:
          fragment("lower(?) LIKE ? ESCAPE '\\'", u.display_name, ^pattern) or
            fragment("? LIKE ? ESCAPE '\\'", u.username, ^pattern),
        select: count(u.id)
    ) || 0
  end

  # Fields the ADMIN search matches. Deliberately wider than search_users/2
  # (username + display_name only): email, device id and provider ids are
  # sensitive and must never be searchable through the public player search.
  @admin_search_fields ~w(email username display_name device_id google_id apple_id facebook_id steam_id discord_id)a

  @doc """
  Admin user listing: search across identity fields (or an exact id), optional
  facet filters, sorting and pagination — the query behind the admin Users page.

  Distinct from `search_users/2`, the privacy-safe player search: this matches
  sensitive fields a player cannot, so it is admin-only.

  `filters` keys (string or atom): `:search` (term or full id), `:facets` (list
  of `"online"`, `"unactivated"`, and provider names). `opts`: `:page`,
  `:page_size`, `:sort_field`, `:sort_dir`.
  """
  @spec list_all_users(map(), keyword()) :: [User.t()]
  def list_all_users(filters \\ %{}, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    filters
    |> all_users_query()
    |> order_by(^admin_user_sort(opts))
    |> limit(^page_size)
    |> offset(^((page - 1) * page_size))
    |> Repo.all()
  end

  @doc "Row count for `list_all_users/2` under the same filters."
  @spec count_list_all_users(map()) :: non_neg_integer()
  def count_list_all_users(filters \\ %{}) do
    filters |> all_users_query() |> Repo.aggregate(:count, :id)
  end

  defp all_users_query(filters) do
    search = to_string(filter_get(filters, :search) || "")
    facets = filter_get(filters, :facets) || []

    from(u in User)
    |> filter_users_by_admin_search(String.trim(search))
    |> filter_users_by_facets(facets)
  end

  defp filter_get(filters, key), do: Map.get(filters, key) || Map.get(filters, to_string(key))

  defp filter_users_by_admin_search(query, ""), do: query

  defp filter_users_by_admin_search(query, term) do
    case Ecto.UUID.cast(term) do
      # A full id: exact match (mirrors the id lookup in search_users/2).
      {:ok, id} ->
        from u in query, where: u.id == ^id

      _ ->
        like = "%#{Repo.escape_like(term)}%"

        combined =
          Enum.reduce(@admin_search_fields, nil, fn field, acc ->
            clause =
              dynamic(
                [u],
                fragment("LOWER(?) LIKE LOWER(?) ESCAPE '\\'", field(u, ^field), ^like)
              )

            if acc, do: dynamic([u], ^acc or ^clause), else: clause
          end)

        from u in query, where: ^combined
    end
  end

  defp filter_users_by_facets(query, facets) do
    query
    |> then(fn q -> if "online" in facets, do: where(q, [u], u.is_online == true), else: q end)
    |> then(fn q ->
      if "unactivated" in facets, do: where(q, [u], u.is_activated == false), else: q
    end)
    |> apply_provider_presence(facets -- ["online", "unactivated"])
  end

  defp apply_provider_presence(query, providers) do
    combined =
      providers
      |> Enum.map(&provider_presence_clause/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(nil, fn c, acc -> if acc, do: dynamic([u], ^acc or ^c), else: c end)

    if combined, do: from(u in query, where: ^combined), else: query
  end

  defp provider_presence_clause("discord"),
    do: dynamic([u], not is_nil(u.discord_id) and u.discord_id != "")

  defp provider_presence_clause("google"),
    do: dynamic([u], not is_nil(u.google_id) and u.google_id != "")

  defp provider_presence_clause("apple"),
    do: dynamic([u], not is_nil(u.apple_id) and u.apple_id != "")

  defp provider_presence_clause("facebook"),
    do: dynamic([u], not is_nil(u.facebook_id) and u.facebook_id != "")

  defp provider_presence_clause("steam"),
    do: dynamic([u], not is_nil(u.steam_id) and u.steam_id != "")

  defp provider_presence_clause("device"),
    do: dynamic([u], not is_nil(u.device_id) and u.device_id != "")

  defp provider_presence_clause("email"),
    do: dynamic([u], not is_nil(u.hashed_password) and u.hashed_password != "")

  defp provider_presence_clause(_), do: nil

  defp admin_user_sort(opts) do
    dir = if Keyword.get(opts, :sort_dir) == "asc", do: :asc, else: :desc

    field =
      case Keyword.get(opts, :sort_field) do
        "updated_at" -> :updated_at
        "last_seen_at" -> :last_seen_at
        _ -> :inserted_at
      end

    [{dir, field}]
  end

  @doc """
  Returns the total number of users.
  """
  @spec count_users() :: non_neg_integer()
  @decorate cacheable(key: {:accounts, :users_count}, opts: [ttl: @users_count_cache_ttl_ms])
  def count_users, do: Repo.aggregate(User, :count, :id)

  defp invalidate_users_count_cache do
    GameServer.Async.run(fn ->
      _ = GameServer.Cache.invalidate({:accounts, :users_count})
      :ok
    end)

    :ok
  end

  defp first_user? do
    Repo.aggregate(User, :count, :id) == 0
  end

  defp maybe_make_first_user_admin(changeset, true) do
    Ecto.Changeset.put_change(changeset, :is_admin, true)
  end

  defp maybe_make_first_user_admin(changeset, false), do: changeset

  # When account activation is required, new non-admin users start deactivated.
  # The first user (admin) is always activated.
  defp maybe_deactivate_new_user(changeset, true = _is_first_user), do: changeset

  defp maybe_deactivate_new_user(changeset, _is_first_user) do
    if require_account_activation?() do
      Ecto.Changeset.put_change(changeset, :is_activated, false)
    else
      changeset
    end
  end

  @doc """
  Count users with non-empty provider id for a given provider field (e.g. :google_id)
  """
  @spec count_users_with_provider(atom()) :: non_neg_integer()
  def count_users_with_provider(provider_field) when is_atom(provider_field) do
    count_users_with_provider_cached(provider_field)
  end

  @decorate cacheable(
              key:
                {:accounts, :stats, users_stats_cache_version(), :users_with_provider,
                 provider_field},
              opts: [ttl: @stats_cache_ttl_ms]
            )
  defp count_users_with_provider_cached(provider_field) do
    Repo.one(
      from u in User,
        where: not is_nil(field(u, ^provider_field)) and field(u, ^provider_field) != "",
        select: count(u.id)
    ) || 0
  end

  @doc """
  Count users with a password set (hashed_password not nil/empty).
  """
  @spec count_users_with_password() :: non_neg_integer()
  def count_users_with_password do
    count_users_with_password_cached()
  end

  @decorate cacheable(
              key: {:accounts, :stats, users_stats_cache_version(), :users_with_password},
              opts: [ttl: @stats_cache_ttl_ms]
            )
  defp count_users_with_password_cached do
    Repo.one(
      from u in User,
        where: not is_nil(u.hashed_password) and u.hashed_password != "",
        select: count(u.id)
    ) || 0
  end

  @doc """
  Count users registered in the last N days.
  """
  @spec count_users_registered_since(integer()) :: non_neg_integer()
  def count_users_registered_since(days) when is_integer(days) do
    count_users_registered_since_cached(days)
  end

  @decorate cacheable(
              key:
                {:accounts, :stats, users_stats_cache_version(), :users_registered_since, days},
              opts: [ttl: @stats_cache_ttl_ms]
            )
  defp count_users_registered_since_cached(days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)
    Repo.one(from u in User, where: u.inserted_at >= ^cutoff, select: count(u.id)) || 0
  end

  @doc """
  Count users active in the last N days.

  This metric is based on `users.updated_at` (any user record update,
  including registration/creation), so it reflects all users and not just
  session-token based authentication.
  """
  @spec count_users_active_since(integer()) :: non_neg_integer()
  def count_users_active_since(days) when is_integer(days) do
    count_users_active_since_cached(days)
  end

  @doc """
  Count users currently marked as online.
  """
  @spec count_users_online() :: non_neg_integer()
  def count_users_online do
    Repo.one(from u in User, where: u.is_online == true, select: count(u.id)) || 0
  end

  @doc """
  Count users who are not yet activated (is_activated == false).
  """
  @spec count_unactivated_users() :: non_neg_integer()
  def count_unactivated_users do
    Repo.one(from u in User, where: u.is_activated == false, select: count(u.id)) || 0
  end

  @decorate cacheable(
              key: {:accounts, :stats, users_stats_cache_version(), :users_active_since, days},
              opts: [ttl: @stats_cache_ttl_ms]
            )
  defp count_users_active_since_cached(days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)

    Repo.one(
      from u in User,
        where:
          u.updated_at >= ^cutoff or
            (not is_nil(u.last_seen_at) and u.last_seen_at >= ^cutoff),
        select: count(u.id)
    ) || 0
  end

  @doc """
  Updates `last_seen_at` to now for the given user. Fire-and-forget — errors are ignored.
  Call on login (session or JWT) to track activity.
  """
  @spec touch_last_seen(User.t()) :: :ok
  def touch_last_seen(%User{} = user) do
    now = DateTime.utc_now(:second)

    case user |> Ecto.Changeset.change(last_seen_at: now) |> Repo.update() do
      {:ok, updated} -> invalidate_user_cache(updated)
      _ -> :ok
    end

    invalidate_users_stats_cache()
    :ok
  end

  @doc """
  Lightweight version of `touch_last_seen/1` that accepts a user ID directly.
  Performs a single UPDATE without loading the full struct first, setting
  `last_seen_at` to now and `is_online` to true, then invalidates the cache.
  Fire-and-forget — errors are ignored.
  """
  @spec touch_last_seen_by_id(Ecto.UUID.t()) :: :ok
  def touch_last_seen_by_id(user_id) when is_binary(user_id) do
    now = DateTime.utc_now(:second)

    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(set: [last_seen_at: now, is_online: true])

    # Update the cached struct in place rather than busting it: this runs every
    # few minutes per connected socket, and a delete would force cold get_user
    # reads on the lobby/party/group hot paths right after each heartbeat. Other
    # nodes keep last_seen within the TTL, which is fine for presence data.
    case GameServer.Cache.get!({:accounts, :user, user_id}) do
      %User{} = cached ->
        _ =
          GameServer.Cache.put(
            {:accounts, :user, user_id},
            %{cached | last_seen_at: now, is_online: true},
            ttl: @user_cache_ttl_ms
          )

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

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
              opts: [ttl: @user_cache_ttl_ms]
            )
  def get_user(id), do: Repo.get_uuid(User, id)

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

  @decorate cacheable(
              key: {:accounts, :user_by, field, value},
              references: &(&1 && keyref({:accounts, :user, &1.id})),
              match: &cache_match/1,
              opts: [ttl: @user_cache_ttl_ms]
            )
  defp get_user_by_field(field, value) when is_atom(field) do
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
    _ = GameServer.Cache.invalidate({:accounts, :user, user.id})
    _ = GameServer.Cache.put({:accounts, :user, user.id}, user, ttl: @user_cache_ttl_ms)
    user
  end

  @spec cache_match(term()) :: boolean()
  defp cache_match(nil), do: false
  defp cache_match(_), do: true

  @user_cache_fields [
    :email,
    :device_id,
    :steam_id,
    :google_id,
    :apple_id,
    :discord_id,
    :facebook_id
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

  defp invalidate_user_cache(%User{id: id} = user) do
    _ = GameServer.Cache.invalidate({:accounts, :user, id})

    user
    |> user_index_keys()
    |> Enum.each(fn key ->
      _ = GameServer.Cache.invalidate(key)
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
      nil -> _ = GameServer.Cache.invalidate({:accounts, :user, user_id})
    end

    :ok
  end

  # Alias kept for readability at call sites that emphasise synchronous semantics.
  defp invalidate_user_cache_sync(user), do: invalidate_user_cache(user)

  ## User registration

  @doc """
  Registers a user.

  ## Attributes

  See `t:GameServer.Types.user_registration_attrs/0` for available fields.

  ## Examples

      iex> register_user(%{email: "user@example.com", password: "secret123"})
      {:ok, %User{}}

      iex> register_user(%{email: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  @spec register_user(Types.user_registration_attrs()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    # Normalize keys to strings to match form submissions
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    # Check if this is the first user and make them admin
    is_first_user = first_user?()

    changeset_fun = fn attrs ->
      %User{}
      |> User.email_changeset(attrs)
      |> User.username_changeset(attrs)
      |> maybe_attach_device(attrs)
      |> maybe_make_first_user_admin(is_first_user)
      |> maybe_deactivate_new_user(is_first_user)
    end

    with {:ok, attrs} <- run_before_user_register(changeset_fun, attrs),
         {:ok, user} = ok <- insert_user_with_username_retry(changeset_fun, attrs) do
      invalidate_users_count_cache()

      GameServer.Async.run(fn ->
        GameServer.Hooks.internal_call(:after_user_register, [user])
      end)

      ok
    end
  end

  @doc """
  Register a user and send the confirmation email inside a DB transaction.

  The function accepts a `confirmation_url_fun` which must be a function of arity 1
  that receives the encoded token and returns the confirmation URL string.

  If sending the confirmation email fails the transaction is rolled back and
  `{:error, reason}` is returned. On success it returns `{:ok, user}`.
  """
  @spec register_user_and_deliver(Types.user_registration_attrs(), (String.t() -> String.t())) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  @spec register_user_and_deliver(
          Types.user_registration_attrs(),
          (String.t() -> String.t()),
          module()
        ) :: {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def register_user_and_deliver(
        attrs,
        confirmation_url_fun,
        notifier \\ GameServer.Accounts.UserNotifier
      )
      when is_function(confirmation_url_fun, 1) do
    # Normalize keys to strings to match form submissions
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    # Check if this is the first user and make them admin
    is_first_user = first_user?()

    changeset_fun = fn attrs ->
      %User{}
      |> User.email_changeset(attrs)
      |> User.username_changeset(attrs)
      |> maybe_attach_device(attrs)
      |> maybe_make_first_user_admin(is_first_user)
      |> maybe_deactivate_new_user(is_first_user)
    end

    transaction_fun = fn attrs ->
      case Repo.insert(changeset_fun.(attrs)) do
        {:ok, %User{} = user} ->
          case maybe_send_confirmation(user, is_first_user, notifier, confirmation_url_fun) do
            :ok -> user
            {:error, reason} -> Repo.rollback(reason)
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback(changeset)
      end
    end

    with {:ok, attrs} <- run_before_user_register(changeset_fun, attrs),
         {:ok, %User{} = user} <- transact_with_username_retry(transaction_fun, attrs) do
      invalidate_users_count_cache()

      GameServer.Async.run(fn ->
        GameServer.Hooks.internal_call(:after_user_register, [user])
      end)

      {:ok, user}
    end
  end

  defp maybe_send_confirmation(_user, true, _notifier, _fun), do: :ok

  defp maybe_send_confirmation(user, false, notifier, confirmation_url_fun) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
    Repo.insert!(user_token)

    case notifier.deliver_confirmation_instructions(
           user,
           confirmation_url_fun.(encoded_token)
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @username_insert_attempts 4

  defp put_generated_username(attrs) do
    case attrs["username"] do
      u when is_binary(u) and u != "" -> attrs
      _ -> Map.put(attrs, "username", UsernameGenerator.generate(attrs))
    end
  end

  # Runs the before_user_register pipeline with the tentative (not yet
  # inserted) user built from attrs. Returns the possibly hook-modified,
  # string-keyed attrs.
  defp run_before_user_register(changeset_fun, attrs) do
    attrs = put_generated_username(attrs)
    tentative = attrs |> changeset_fun.() |> Ecto.Changeset.apply_changes()

    case GameServer.Hooks.internal_call(:before_user_register, [tentative, attrs]) do
      {:ok, returned} when is_map(returned) and not is_struct(returned) ->
        {:ok, Map.new(returned, fn {k, v} -> {to_string(k), v} end)}

      {:ok, _other} ->
        {:ok, attrs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Registration must never fail on a bad username: a hook-supplied or
  # generated name that is invalid or already taken is replaced with a
  # freshly generated one (wider suffix on later attempts). Other changeset
  # errors pass through untouched.
  defp insert_user_with_username_retry(changeset_fun, attrs, attempt \\ 1) do
    case Repo.insert(changeset_fun.(attrs)) do
      {:ok, _user} = ok ->
        ok

      {:error, %Ecto.Changeset{} = changeset} = err ->
        case regenerate_username_attrs(attrs, changeset, attempt) do
          {:retry, attrs} -> insert_user_with_username_retry(changeset_fun, attrs, attempt + 1)
          :no_retry -> err
        end
    end
  end

  # A unique violation aborts the surrounding Postgres transaction, so the
  # retry must restart the whole transaction rather than re-insert inside
  # the aborted one.
  defp transact_with_username_retry(transaction_fun, attrs, attempt \\ 1) do
    case Repo.transaction(fn -> transaction_fun.(attrs) end) do
      {:error, %Ecto.Changeset{} = changeset} = err ->
        case regenerate_username_attrs(attrs, changeset, attempt) do
          {:retry, attrs} -> transact_with_username_retry(transaction_fun, attrs, attempt + 1)
          :no_retry -> err
        end

      other ->
        other
    end
  end

  defp regenerate_username_attrs(attrs, %Ecto.Changeset{errors: errors}, attempt) do
    if Keyword.has_key?(errors, :username) and attempt < @username_insert_attempts do
      regenerated = UsernameGenerator.generate(attrs, attempt + 1)

      Logger.warning(
        "username #{inspect(attrs["username"])} rejected " <>
          "(#{inspect(Keyword.get_values(errors, :username))}), retrying as #{regenerated}"
      )

      {:retry, Map.put(attrs, "username", regenerated)}
    else
      :no_retry
    end
  end

  defp maybe_attach_device(changeset, %{"device_id" => device_id}) when is_binary(device_id) do
    changeset
    |> Ecto.Changeset.put_change(:device_id, device_id)
  end

  defp maybe_attach_device(changeset, _), do: changeset

  @doc """
  Confirms a user's email by setting confirmed_at timestamp.

  ## Examples

      iex> confirm_user(user)
      {:ok, %User{}}

  """
  @spec confirm_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def confirm_user(user) do
    case user
         |> User.confirm_changeset()
         |> Repo.update() do
      {:ok, %User{} = updated} = ok ->
        invalidate_user_cache(user)
        invalidate_user_cache(updated)
        ok

      other ->
        other
    end
  end

  @doc """
  Confirm a user by an email confirmation token (context: "confirm").

  Returns {:ok, user} when the token is valid and user was confirmed.
  Returns {:error, :not_found} or {:error, :expired} when token is invalid/expired.
  """
  @spec confirm_user_by_token(String.t()) :: {:ok, User.t()} | {:error, :invalid | :not_found}
  def confirm_user_by_token(token) when is_binary(token) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false),
         hashed <- :crypto.hash(:sha256, decoded),
         {:ok, %User{} = user} <- fetch_user_for_confirm_token(hashed),
         {:ok, %User{} = confirmed_user} <- confirm_user_by_token_tx(user) do
      {:ok, get_user(confirmed_user.id)}
    else
      :error ->
        {:error, :invalid}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp fetch_user_for_confirm_token(hashed) do
    query =
      from t in UserToken,
        where: t.token == ^hashed and t.context == "confirm",
        where: t.inserted_at > ago(7, "day"),
        join: u in assoc(t, :user),
        select: {u, t}

    case Repo.one(query) do
      {%User{} = user, _token} -> {:ok, user}
      nil -> {:error, :not_found}
    end
  end

  defp confirm_user_by_token_tx(%User{} = user) do
    Repo.transaction(fn ->
      {:ok, confirmed_user} = confirm_user(user)

      Repo.delete_all(
        from(ut in UserToken, where: ut.user_id == ^confirmed_user.id and ut.context == "confirm")
      )

      confirmed_user
    end)
  end

  @doc """
  Finds a user by Discord ID or creates a new user from OAuth data.

  ## Examples

      iex> find_or_create_from_discord(%{discord_id: "123", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_discord(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_discord(attrs) do
    find_or_create_from_oauth(
      attrs,
      :discord_id,
      &User.discord_oauth_changeset/2
    )
  end

  @doc """
  Finds a user by Apple ID or creates a new user from OAuth data.

  ## Examples

      iex> find_or_create_from_apple(%{apple_id: "123", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_apple(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_apple(attrs) do
    find_or_create_from_oauth(
      attrs,
      :apple_id,
      &User.apple_oauth_changeset/2
    )
  end

  @doc """
  Finds a user by Google ID or creates a new user from OAuth data.

  ## Examples

      iex> find_or_create_from_google(%{google_id: "123", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_google(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_google(attrs) do
    find_or_create_from_oauth(
      attrs,
      :google_id,
      &User.google_oauth_changeset/2
    )
  end

  @doc """
  Finds a user by Facebook ID or creates a new user from OAuth data.

  ## Examples

      iex> find_or_create_from_facebook(%{facebook_id: "123", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_facebook(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_facebook(attrs) do
    find_or_create_from_oauth(
      attrs,
      :facebook_id,
      &User.facebook_oauth_changeset/2
    )
  end

  @doc """
  Finds a user by Steam ID or creates a new user from Steam OpenID data.

  ## Examples

      iex> find_or_create_from_steam(%{steam_id: "12345", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_steam(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_steam(attrs) do
    find_or_create_from_oauth(
      attrs,
      :steam_id,
      &User.steam_oauth_changeset/2
    )
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
  Gets a user by their unique username handle (case-insensitive; usernames
  are stored lowercase).
  """
  @spec get_user_by_username(String.t()) :: User.t() | nil
  def get_user_by_username(username) when is_binary(username) do
    get_user_by_field(:username, String.downcase(username))
  end

  defp get_user_by_device_id(device_id) when is_binary(device_id) do
    get_user_by_field(:device_id, device_id)
  end

  @doc """
  Finds or creates a user associated with the given device_id.

  If a user already exists with the device_id we return it. Otherwise we
  create an anonymous confirmed user and attach the device_id.
  """
  @spec find_or_create_from_device(String.t()) ::
          {:ok, User.t()} | {:error, :disabled | Ecto.Changeset.t() | term()}
  @spec find_or_create_from_device(String.t(), map()) ::
          {:ok, User.t()} | {:error, :disabled | Ecto.Changeset.t() | term()}
  def find_or_create_from_device(device_id, attrs \\ %{}) when is_binary(device_id) do
    if device_auth_enabled?() do
      do_find_or_create_from_device(device_id, attrs)
    else
      {:error, :disabled}
    end
  end

  defp do_find_or_create_from_device(device_id, attrs) do
    case get_user_by_device_id(device_id) do
      %User{} = user ->
        {:ok, user}

      nil ->
        # Create a new anonymous user for the device. Allow callers to
        # specify optional display_name/metadata via attrs.
        attrs =
          attrs
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> Map.put_new("display_name", nil)

        is_first_user = first_user?()

        changeset_fun = fn attrs ->
          %User{}
          |> User.device_changeset(attrs)
          |> User.username_changeset(attrs)
          |> maybe_make_first_user_admin(is_first_user)
          |> maybe_deactivate_new_user(is_first_user)
          |> User.attach_device_changeset(%{device_id: device_id})
        end

        with {:ok, attrs} <- run_before_user_register(changeset_fun, attrs),
             {:ok, user} = ok <- insert_user_with_username_retry(changeset_fun, attrs) do
          invalidate_users_count_cache()

          GameServer.Async.run(fn ->
            GameServer.Hooks.internal_call(:after_user_register, [user])
          end)

          ok
        end
    end
  end

  @doc """
  Attach a device_id to an existing user record. Returns {:ok, user} or
  {:error, changeset} if the device_id is already used.
  """
  @spec attach_device_to_user(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def attach_device_to_user(%User{} = user, device_id) when is_binary(device_id) do
    case user
         |> User.attach_device_changeset(%{device_id: device_id})
         |> Repo.update() do
      {:ok, %User{} = updated} = ok ->
        invalidate_user_cache(user)
        invalidate_user_cache(updated)
        ok

      other ->
        other
    end
  end

  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :auth,
    label: "Authentication"

  setting(:device_auth_enabled, :boolean,
    default: true,
    doc:
      "Allow POST /api/v1/login/device. When on, any unknown device_id creates an anonymous account."
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

  @doc "Whether device-based auth is enabled. Defaults to on."
  @spec device_auth_enabled?() :: boolean()
  def device_auth_enabled?, do: GameServer.Settings.get(__MODULE__, :device_auth_enabled) == true

  @doc """
  Whether new accounts require manual admin activation before they can log in.
  """
  @spec require_account_activation?() :: boolean()
  def require_account_activation?,
    do: GameServer.Settings.get(__MODULE__, :require_activation) == true

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

  # Generic OAuth find or create helper
  defp find_or_create_from_oauth(attrs, provider_id_field, changeset_fn) do
    provider_id = Map.get(attrs, provider_id_field)
    email = Map.get(attrs, :email)

    result =
      cond do
        provider_id != nil ->
          handle_provider_id(provider_id, attrs, provider_id_field, changeset_fn)

        email != nil ->
          handle_by_email(email, attrs, provider_id_field, changeset_fn)

        true ->
          create_user_from_provider(attrs, changeset_fn)
      end

    with {:ok, %User{} = user} <- result do
      {:ok, maybe_mirror_avatar(user)}
    end
  end

  defp handle_provider_id(provider_id, attrs, provider_id_field, changeset_fn) do
    case get_user_by_field(provider_id_field, provider_id) do
      %User{} = user ->
        attrs = scrub_attrs_for_update(user, attrs, provider_id_field)

        case user
             |> changeset_fn.(attrs)
             |> Repo.update() do
          {:ok, %User{} = updated} = ok ->
            invalidate_user_cache(user)
            invalidate_user_cache(updated)
            ok

          other ->
            other
        end

      nil ->
        handle_provider_id_missing(attrs, provider_id_field, changeset_fn)
    end
  end

  defp handle_provider_id_missing(attrs, provider_id_field, changeset_fn) do
    case Map.get(attrs, :email) && get_user_by_email(Map.get(attrs, :email)) do
      %User{} = user -> link_provider_to_user(user, attrs, provider_id_field, changeset_fn)
      _ -> create_user_from_provider(attrs, changeset_fn)
    end
  end

  defp handle_by_email(email, attrs, provider_id_field, changeset_fn) do
    case get_user_by_email(email) do
      nil -> create_user_from_provider(attrs, changeset_fn)
      %User{} = user -> link_provider_to_user(user, attrs, provider_id_field, changeset_fn)
    end
  end

  # Only attach a provider to a pre-existing account when the provider asserts
  # the email is verified — otherwise an attacker with a provider account
  # bearing the victim's email could take over the account. Callers set
  # `:email_verified` from the provider's claim (see oauth_user_params).
  defp link_provider_to_user(user, attrs, provider_id_field, changeset_fn) do
    if Map.get(attrs, :email_verified) == true do
      attrs = scrub_attrs_for_update(user, attrs, provider_id_field)

      case user |> changeset_fn.(attrs) |> Repo.update() do
        {:ok, %User{} = updated} = ok ->
          invalidate_user_cache(user)
          invalidate_user_cache(updated)
          ok

        other ->
          other
      end
    else
      changeset =
        user
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(
          :email,
          "is already registered — sign in with your existing method, then link this provider from account settings"
        )

      {:error, %{changeset | action: :update}}
    end
  end

  # Mirror an external (OAuth provider) avatar into our object storage so avatars
  # render from our storage/CDN rather than hotlinking the provider. Enqueued only
  # when the user's avatar is not already one of our stored objects. Oban's
  # `:infinity` uniqueness keeps it to one job per user, and once mirrored the URL
  # points at our storage so `our_stored_avatar?/1` short-circuits future logins —
  # we never re-mirror. See `GameServer.Accounts.AvatarMirror`.
  defp maybe_mirror_avatar(%User{profile_url: url} = user) when is_binary(url) and url != "" do
    unless our_stored_avatar?(user) do
      _ =
        Oban.insert(
          AvatarMirror.new(
            %{"user_id" => user.id, "source_url" => url},
            unique: [keys: [:user_id], period: :infinity, states: Oban.Job.states()]
          )
        )
    end

    user
  end

  defp maybe_mirror_avatar(user), do: user

  # Our stored avatars live under the `avatars/<user_id>/…` key namespace, so a
  # profile URL containing that segment is one we already host (uploaded or
  # previously mirrored) — anything else is an external provider link.
  defp our_stored_avatar?(%User{id: id, profile_url: url}),
    do: is_binary(url) and String.contains?(url, "avatars/#{id}")

  defp create_user_from_provider(attrs, changeset_fn) do
    is_first_user = first_user?()

    # For new user creation when provider didn't return an email, avoid
    # passing a nil email into the changeset (update_change will crash).
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    attrs = if attrs["email"] in [nil, ""], do: Map.delete(attrs, "email"), else: attrs

    # Admin is granted via put_change (server-side), never cast from provider
    # attrs — the OAuth changesets must not accept :is_admin.
    changeset_fun = fn attrs ->
      %User{}
      |> changeset_fn.(attrs)
      |> User.username_changeset(attrs)
      |> maybe_make_first_user_admin(is_first_user)
      |> maybe_deactivate_new_user(is_first_user)
    end

    with {:ok, attrs} <- run_before_user_register(changeset_fun, attrs),
         {:ok, user} = ok <- insert_user_with_username_retry(changeset_fun, attrs) do
      invalidate_users_count_cache()

      GameServer.Async.run(fn ->
        GameServer.Hooks.internal_call(:after_user_register, [user])
      end)

      ok
    end
  end

  # When updating an existing user from provider data we should avoid
  # destructive changes:
  # - Do not overwrite an existing, non-empty email (email is used for
  #   password-login accounts and should be preserved when present).
  # - Only set provider avatar if the user's avatar field for that provider
  #   is empty - prefer not to clobber user-set values.
  defp scrub_attrs_for_update(user, attrs, _provider_id_field) do
    attrs = Map.new(attrs)

    # Remove email if user already has one
    attrs =
      if user.email && user.email != "" do
        Map.delete(attrs, :email)
      else
        attrs
      end

    # Only set provider avatar if user doesn't already have one
    # Store provider profile images/URLs in the generic `profile_url` field.
    provider_avatar_key = :profile_url

    attrs =
      if Map.get(user, provider_avatar_key) && Map.get(user, provider_avatar_key) != "" do
        Map.delete(attrs, provider_avatar_key)
      else
        attrs
      end

    # Also avoid overwriting an existing explicit display_name set by the user.
    if Map.get(user, :display_name) && Map.get(user, :display_name) != "" do
      Map.delete(attrs, :display_name)
    else
      attrs
    end
  end

  @doc """
  Link an OAuth provider to an existing user account. Updates the user
  via the provider's oauth changeset while being careful not to overwrite
  existing email or avatars.

  Example: link_account(user, %{discord_id: "123", profile_url: "https://..."}, :discord_id, &User.discord_oauth_changeset/2)
  """
  @spec link_account(User.t(), map(), atom(), (User.t(), map() -> Ecto.Changeset.t())) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | {:conflict, User.t()}}
  def link_account(%User{} = user, attrs, provider_id_field, changeset_fn) do
    attrs = scrub_attrs_for_update(user, attrs, provider_id_field)

    changeset = changeset_fn.(user, attrs)

    case Repo.update(changeset) do
      {:ok, %User{} = updated_user} ->
        invalidate_user_cache(user)
        invalidate_user_cache(updated_user)
        invalidate_users_stats_cache()
        # Broadcast user update to user channel
        broadcast_user_update(updated_user)

        {:ok, maybe_mirror_avatar(updated_user)}

      {:error, changeset} ->
        handle_link_error(user, attrs, provider_id_field, changeset)
    end
  end

  defp handle_link_error(user, attrs, provider_id_field, changeset) do
    # If the update failed due to the provider ID being already taken,
    # return a conflict with the existing account so the UI can guide
    # the user (e.g., delete the other account or sign into it).
    provider_value = Map.get(attrs, provider_id_field)

    if provider_value do
      case get_user_by_field(provider_id_field, provider_value) do
        %User{} = other_user when other_user.id != user.id ->
          {:error, {:conflict, other_user}}

        _ ->
          {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  @doc """
  Link a device_id to an existing user account. This allows the user to
  authenticate using the device_id in addition to their OAuth providers.

  Returns {:ok, user} on success or {:error, changeset} if the device_id
  is already used by another account.
  """
  @spec link_device_id(User.t(), String.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def link_device_id(%User{} = user, device_id) when is_binary(device_id) do
    changeset = User.attach_device_changeset(user, %{device_id: device_id})

    case Repo.update(changeset) do
      {:ok, %User{} = updated_user} ->
        invalidate_user_cache(user)
        invalidate_user_cache(updated_user)
        invalidate_users_stats_cache()
        # Broadcast user update to user channel
        broadcast_user_update(updated_user)
        {:ok, updated_user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Unlink the device_id from a user's account.

  Returns {:ok, user} when successful or {:error, reason}.

  Guard: we only allow unlinking when the user will still have at least
  one authentication method remaining (OAuth provider or password).
  This prevents users losing all login methods unexpectedly.
  """
  @spec unlink_device_id(User.t()) ::
          {:ok, User.t()} | {:error, :last_auth_method | Ecto.Changeset.t()}
  def unlink_device_id(%User{} = user) do
    # If device_id is already nil, just return success
    if user.device_id in [nil, ""] do
      {:ok, user}
    else
      # Check if user has at least one OAuth provider or password
      providers = [:discord_id, :apple_id, :google_id, :facebook_id, :steam_id]

      has_provider =
        Enum.any?(providers, fn f ->
          case Map.get(user, f) do
            v when is_binary(v) -> String.trim(v) != ""
            _ -> false
          end
        end)

      has_password = has_password?(user)

      if has_provider or has_password do
        changes = %{device_id: nil}

        case user |> Ecto.Changeset.change(changes) |> Repo.update() do
          {:ok, %User{} = updated_user} ->
            invalidate_user_cache(user)
            invalidate_user_cache(updated_user)
            invalidate_users_stats_cache()
            # Broadcast user update to user channel
            broadcast_user_update(updated_user)
            {:ok, updated_user}

          {:error, changeset} ->
            {:error, changeset}
        end
      else
        {:error, :last_auth_method}
      end
    end
  end

  @doc """
  Unlink an OAuth provider from a user's account.

  provider should be one of :discord, :apple, :google, :facebook.
  This will return {:ok, user} when successful or {:error, reason}.

  Guard: we only allow unlinking when the user will still have at least
  one other social provider remaining. This prevents users losing all
  social logins unexpectedly.
  """
  @spec unlink_provider(User.t(), :discord | :apple | :google | :facebook | :steam) ::
          {:ok, User.t()} | {:error, :last_provider | Ecto.Changeset.t() | term()}
  def unlink_provider(%User{} = user, provider)
      when provider in [:discord, :apple, :google, :facebook, :steam] do
    provider_field = provider_field(provider)

    # Count remaining linked providers (only non-empty, non-nil strings)
    providers = [:discord_id, :apple_id, :google_id, :facebook_id, :steam_id]

    present =
      Enum.count(providers, fn f ->
        case Map.get(user, f) do
          v when is_binary(v) -> String.trim(v) != ""
          _ -> false
        end
      end)

    if present <= 1 do
      {:error, :last_provider}
    else
      changes = %{provider_field => nil}

      # If unlinking discord and profile_url is a discord CDN URL, clear it
      changes =
        if provider == :discord && user.profile_url &&
             String.contains?(user.profile_url, "cdn.discordapp.com/avatars") do
          Map.put(changes, :profile_url, nil)
        else
          changes
        end

      case user
           |> Ecto.Changeset.change(changes)
           |> Repo.update() do
        {:ok, updated_user} ->
          invalidate_user_cache(user)
          invalidate_user_cache(updated_user)
          invalidate_users_stats_cache()
          # Broadcast user update to user channel
          broadcast_user_update(updated_user)
          {:ok, updated_user}

        error ->
          error
      end
    end
  end

  defp provider_field(:discord), do: :discord_id
  defp provider_field(:apple), do: :apple_id
  defp provider_field(:google), do: :google_id
  defp provider_field(:facebook), do: :facebook_id
  defp provider_field(:steam), do: :steam_id

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  @spec sudo_mode?(User.t()) :: boolean()
  @spec sudo_mode?(User.t(), integer()) :: boolean()
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `GameServer.Accounts.User.email_changeset/3` for a list of supported options.

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

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, updated_user} <- Repo.update(User.email_changeset(user, %{email: email})),
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

  See `GameServer.Accounts.User.password_changeset/3` for a list of supported options.

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

  ## Session

  @doc """
  Generates a session token.
  """
  @spec generate_user_session_token(User.t()) :: binary()
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    touch_last_seen(user)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  @spec get_user_by_session_token(binary()) :: {User.t(), DateTime.t()} | nil
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  @spec get_user_by_magic_link_token(String.t()) :: User.t() | nil
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
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
  """
  @spec login_user_by_magic_link(String.t()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, :not_found | Ecto.Changeset.t() | term()}
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when hash != nil ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        handle_unconfirmed_login(user)

      {user, token} ->
        Repo.delete!(token)

        GameServer.Async.run(fn ->
          GameServer.Hooks.internal_call(:after_user_logged_in, [user])
          GameServer.Quests.report_event(user.id, "login")
        end)

        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  defp handle_unconfirmed_login(user) do
    result =
      user
      |> User.confirm_changeset()
      |> update_user_and_delete_all_tokens()

    case result do
      {:ok, {user, _tokens}} = ok ->
        GameServer.Async.run(fn ->
          GameServer.Hooks.internal_call(:after_user_logged_in, [user])
          GameServer.Quests.report_event(user.id, "login")
        end)

        ok

      other ->
        other
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_user_update_email_instructions(
          User.t(),
          String.t(),
          (String.t() -> String.t())
        ) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  @spec deliver_login_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(token) do
    ids =
      Repo.all(
        from(t in UserToken, where: t.token == ^token and t.context == "session", select: t.id)
      )

    Repo.delete_all(from(t in UserToken, where: t.id in ^ids))
    Enum.each(ids, &GameServer.Cache.invalidate({:accounts, :user_token, &1}))
    :ok
  end

  @doc false
  @spec get_user_token(Ecto.UUID.t()) :: UserToken.t() | nil
  @decorate cacheable(
              key: {:accounts, :user_token, id},
              match: &cache_match/1,
              opts: [ttl: 60_000]
            )
  def get_user_token(id) do
    Repo.get_uuid(UserToken, id)
  end

  @doc false
  @spec get_user_token!(Ecto.UUID.t()) :: UserToken.t()
  def get_user_token!(id) do
    case get_user_token(id) do
      %UserToken{} = token -> token
      nil -> raise Ecto.NoResultsError, queryable: UserToken
    end
  end

  @doc false
  @spec delete_user_token(UserToken.t()) :: {:ok, UserToken.t()} | {:error, Ecto.Changeset.t()}
  def delete_user_token(%UserToken{} = token) do
    case Repo.delete(token) do
      {:ok, _} = ok ->
        _ = GameServer.Cache.invalidate({:accounts, :user_token, token.id})
        ok

      other ->
        other
    end
  end

  @doc """
  Lists tokens for a given user, optionally filtered by context.
  """
  @spec list_user_tokens(Ecto.UUID.t(), keyword()) :: [UserToken.t()]
  def list_user_tokens(user_id, opts \\ []) when is_binary(user_id) do
    context = Keyword.get(opts, :context)

    from(t in UserToken, where: t.user_id == ^user_id, order_by: [desc: t.inserted_at])
    |> then(fn q ->
      if context, do: where(q, [t], t.context == ^context), else: q
    end)
    |> Repo.all()
  end

  @doc """
  Counts tokens for a given user.
  """
  @spec count_user_tokens(Ecto.UUID.t()) :: non_neg_integer()
  def count_user_tokens(user_id) when is_binary(user_id) do
    from(t in UserToken, where: t.user_id == ^user_id, select: count())
    |> Repo.one()
  end

  @doc """
  Revokes all session tokens for a user (mass logout).
  """
  @spec revoke_all_user_sessions(Ecto.UUID.t()) :: {non_neg_integer(), nil}
  def revoke_all_user_sessions(user_id) when is_binary(user_id) do
    token_ids =
      from(t in UserToken,
        where: t.user_id == ^user_id and t.context == "session",
        select: t.id
      )
      |> Repo.all()

    result =
      from(t in UserToken, where: t.user_id == ^user_id and t.context == "session")
      |> Repo.delete_all()

    Enum.each(token_ids, fn id ->
      _ = GameServer.Cache.invalidate({:accounts, :user_token, id})
    end)

    result
  end

  @doc """
  Deletes a user and associated resources.

  Returns `{:ok, user}` on success or `{:error, changeset}` on failure.
  """
  alias GameServer.Lobbies

  @spec delete_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def delete_user(%User{} = user) do
    # Best-effort: try to remove the user from any party they may belong to.
    # If they are the leader the party is disbanded (PubSub + cache cleanup).
    try do
      _ = GameServer.Parties.leave_party(user)
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
      _ = GameServer.Groups.handle_user_deletion(user.id)
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
        _ = GameServer.Chat.cleanup_chat("friend", user.id)

        # Deleting cache entries asynchronously can cause a short-lived race where
        # a delete followed immediately by a device login sees a stale cached user
        # for the same device_id/email and skips the "create" code path.
        invalidate_user_cache_sync(user)

        # Notify plugins the user is gone so they can refresh derived state that
        # does not cascade at the DB level (e.g. maintained aggregate counters).
        # Cascaded rows (kv_entries, plugin FK tables) are already removed here.
        _ = GameServer.Hooks.internal_call(:after_user_deleted, [user])

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

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
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

  # Invalidates all previously issued JWTs: `GameServerWeb.Auth.Guardian`
  # embeds `token_version` as a claim and rejects tokens whose claim no longer
  # matches the user's current value.
  defp bump_token_version(changeset) do
    current = Ecto.Changeset.get_field(changeset, :token_version)
    Ecto.Changeset.force_change(changeset, :token_version, current + 1)
  end

  @doc """
  Broadcast that the given user has been updated.

  This helper is intentionally small and only broadcasts a compact payload
  intended for client consumption through the `user:<id>` topic.
  """
  @spec broadcast_user_update(User.t()) :: :ok
  def broadcast_user_update(%User{} = user) do
    payload = serialize_user_payload(user)
    topic = "user:#{user.id}"

    Phoenix.PubSub.broadcast(
      GameServer.PubSub,
      topic,
      %Phoenix.Socket.Broadcast{topic: topic, event: "updated", payload: payload}
    )

    :ok
  end

  @doc """
  Broadcast a `member_updated` event to the user's current lobby and
  party channels so other members see the profile change (display name, avatar,
  metadata, etc.) in real-time.

  This is fire-and-forget and safe to call even when the user is not in a lobby
  or party.
  """
  @spec broadcast_member_update(User.t()) :: :ok
  def broadcast_member_update(%User{} = user) do
    if user.lobby_id do
      GameServer.Lobbies.broadcast_member_presence(
        user.lobby_id,
        {:member_updated, user.id}
      )
    end

    if user.party_id do
      GameServer.Parties.broadcast_member_presence(
        user.party_id,
        {:member_updated, user.id}
      )
    end

    # Broadcast to all groups the user belongs to
    for group_id <- GameServer.Groups.user_group_ids(user.id) do
      GameServer.Groups.broadcast_member_presence(
        group_id,
        {:member_updated, user.id}
      )
    end

    broadcast_friend_update(user)
    :ok
  end

  @doc """
  Broadcast a `friend_updated` event to all accepted friends.

  Used when public user data changes: map presence, display name, avatar,
  player metadata, ship metadata, lobby/party state, etc.
  """
  @spec broadcast_friend_update(User.t()) :: :ok
  def broadcast_friend_update(%User{} = user) do
    payload = User.serialize_brief(user) |> Map.put(:user_id, user.id)

    for friend_id <- GameServer.Friends.friend_ids(user.id) do
      topic = "user:#{friend_id}"

      Phoenix.PubSub.broadcast(
        GameServer.PubSub,
        topic,
        %Phoenix.Socket.Broadcast{topic: topic, event: "friend_updated", payload: payload}
      )
    end

    :ok
  end

  @doc """
  Serialize a user into the compact payload used by realtime updates.
  """
  @spec serialize_user_payload(User.t()) :: map()
  def serialize_user_payload(%User{} = user) do
    %{
      id: user.id,
      email: user.email || "",
      profile_url: user.profile_url || "",
      metadata: user.metadata || %{},
      username: user.username || "",
      display_name: user.display_name || "",
      lobby_id: user.lobby_id || "",
      party_id: user.party_id || "",
      is_online: user.is_online || false,
      last_seen_at: User.last_seen_at_or_fallback(user),
      linked_providers: get_linked_providers(user),
      has_password: has_password?(user)
    }
  end

  @doc """
  Returns a map of linked OAuth providers for the user.

  Each provider is a boolean indicating whether that provider is linked.
  """
  @spec get_linked_providers(User.t()) :: %{
          google: boolean(),
          facebook: boolean(),
          discord: boolean(),
          apple: boolean(),
          steam: boolean(),
          device: boolean()
        }
  def get_linked_providers(%User{} = user) do
    %{
      google: user.google_id != nil,
      facebook: user.facebook_id != nil,
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
  Returns an `%Ecto.Changeset{}` for changing the user display_name.
  """
  @spec change_user_display_name(User.t()) :: Ecto.Changeset.t()
  @spec change_user_display_name(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_display_name(user, attrs \\ %{}) do
    User.display_name_changeset(user, attrs)
  end

  @spec change_username(User.t()) :: Ecto.Changeset.t()
  @spec change_username(User.t(), map()) :: Ecto.Changeset.t()
  def change_username(user, attrs \\ %{}) do
    User.username_changeset(user, attrs)
  end

  @doc """
  Set the user's avatar URL (`profile_url`), typically after an upload confirmed
  by `GameServer.Storage`. Same cache/broadcast/hook path as other profile edits.
  """
  @spec update_user_avatar(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_avatar(%User{} = user, url) when is_binary(url) do
    case User.avatar_changeset(user, %{"profile_url" => url}) |> Repo.update() do
      {:ok, updated} = ok ->
        invalidate_user_cache_sync(user)
        invalidate_user_cache_sync(updated)
        broadcast_user_update(updated)
        broadcast_member_update(updated)

        GameServer.Async.run(fn ->
          GameServer.Hooks.internal_call(:after_user_updated, [updated])
        end)

        ok

      err ->
        err
    end
  end

  @doc """
  Delete a user's stored avatar objects except `keep_key`.

  Each new avatar gets a fresh random key (`avatars/<user_id>/<rand><ext>`), so
  without this the previous upload or mirror copy lingers in storage forever.
  Best-effort: a failed cleanup leaves the old object rather than failing the
  update that already succeeded.
  """
  @spec prune_user_avatars(Ecto.UUID.t(), String.t()) :: :ok
  def prune_user_avatars(user_id, keep_key) when is_binary(user_id) and is_binary(keep_key) do
    [prefix: "avatars/#{user_id}/", limit: 100]
    |> GameServer.Storage.list_objects()
    |> Enum.reject(&(&1.key == keep_key))
    |> Enum.each(fn %{key: key} -> GameServer.Storage.delete(key) end)

    :ok
  rescue
    e ->
      Logger.warning("avatar prune failed user=#{user_id}: #{inspect(e)}")
      :ok
  end

  @doc """
  Updates the user's display name and broadcasts the change.
  """
  @spec update_user_display_name(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_display_name(%User{} = user, attrs) do
    case GameServer.Hooks.internal_call(:before_user_update, [user, attrs]) do
      {:ok, returned} ->
        attrs_to_use =
          if is_map(returned) and not is_struct(returned) do
            returned
          else
            attrs
          end

        case User.display_name_changeset(user, attrs_to_use) |> Repo.update() do
          {:ok, updated} = ok ->
            invalidate_user_cache_sync(user)
            invalidate_user_cache_sync(updated)
            broadcast_user_update(updated)
            broadcast_member_update(updated)

            GameServer.Async.run(fn ->
              GameServer.Hooks.internal_call(:after_user_updated, [updated])
            end)

            ok

          err ->
            err
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates the user's unique username handle and broadcasts the change.

  Strict, unlike registration: an invalid or taken username returns
  `{:error, changeset}` with no generated fallback, so the player can pick
  again. Routed through the `before_user_update` hook pipeline, where games
  can forbid changes entirely or reject names (profanity, reserved words).
  """
  @spec update_username(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def update_username(%User{} = user, attrs) do
    case GameServer.Hooks.internal_call(:before_user_update, [user, attrs]) do
      {:ok, returned} ->
        attrs_to_use =
          if is_map(returned) and not is_struct(returned) do
            returned
          else
            attrs
          end

        case User.username_changeset(user, attrs_to_use) |> Repo.update() do
          {:ok, updated} = ok ->
            invalidate_user_cache_sync(user)
            invalidate_user_cache_sync(updated)
            broadcast_user_update(updated)
            broadcast_member_update(updated)

            GameServer.Async.run(fn ->
              GameServer.Hooks.internal_call(:after_user_updated, [updated])
            end)

            ok

          err ->
            err
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a user with the given attributes.

  This function applies the `User.admin_changeset/2` then updates the user and
  broadcasts the update on success. It returns the same tuple shape as
  `Repo.update/1` so callers can pattern-match as before.

  ## Attributes

  See `t:GameServer.Types.user_update_attrs/0` for available fields.

  ## Examples

      iex> update_user(user, %{display_name: "NewName"})
      {:ok, %User{}}

      iex> update_user(user, %{metadata: %{level: 5}})
      {:ok, %User{}}

  """
  @spec update_user(User.t(), Types.user_update_attrs()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user(%User{} = user, attrs) when is_map(attrs) do
    case GameServer.Hooks.internal_call(:before_user_update, [user, attrs]) do
      {:ok, returned} ->
        attrs_to_use =
          if is_map(returned) and not is_struct(returned) do
            returned
          else
            attrs
          end

        do_update_user(user, attrs_to_use)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_update_user(%User{} = user, attrs) do
    case User.admin_changeset(user, attrs) |> Repo.update() do
      {:ok, updated} = ok ->
        invalidate_user_cache(user)
        invalidate_user_cache(updated)
        invalidate_users_stats_cache()
        broadcast_user_update(updated)
        broadcast_member_update(updated)

        GameServer.Async.run(fn ->
          GameServer.Hooks.internal_call(:after_user_updated, [updated])
        end)

        ok

      other ->
        other
    end
  end

  @spec change_user_registration(User.t()) :: Ecto.Changeset.t()
  @spec change_user_registration(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, [])
  end

  @spec deliver_user_confirmation_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, :already_confirmed | term()}
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      UserNotifier.deliver_confirmation_instructions(
        user,
        confirmation_url_fun.(encoded_token)
      )
    end
  end

  @doc """
  Mark a user as online and update last_seen_at.

  Writes only on a real offline→online transition: reconnects and extra
  tabs/sockets while already online are no-ops, so reconnect storms don't
  hammer the `users` table (and the `after_user_online` hook fires once per
  session, not once per socket).

  Returns {:ok, user} on success.
  """
  @spec set_user_online(Ecto.UUID.t()) :: {:ok, User.t()} | {:error, term()}
  def set_user_online(user_id) when is_binary(user_id) do
    now = DateTime.utc_now(:second)

    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{is_online: true} = user ->
        {:ok, user}

      user ->
        user
        |> Ecto.Changeset.change(is_online: true, last_seen_at: now)
        |> Repo.update()
        |> case do
          {:ok, updated} = ok ->
            invalidate_user_cache(updated)
            broadcast_member_update(updated)

            GameServer.Async.run(fn ->
              GameServer.Hooks.internal_call(:after_user_online, [updated])
            end)

            ok

          err ->
            err
        end
    end
  end

  @doc """
  Mark a user as offline and update last_seen_at.

  Writes only on a real online→offline transition (see `set_user_online/1`).

  Returns {:ok, user} on success.
  """
  @spec set_user_offline(Ecto.UUID.t()) :: {:ok, User.t()} | {:error, term()}
  def set_user_offline(user_id) when is_binary(user_id) do
    now = DateTime.utc_now(:second)

    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{is_online: false} = user ->
        {:ok, user}

      user ->
        user
        |> Ecto.Changeset.change(is_online: false, last_seen_at: now)
        |> Repo.update()
        |> case do
          {:ok, updated} = ok ->
            invalidate_user_cache(updated)
            broadcast_member_update(updated)

            GameServer.Async.run(fn ->
              GameServer.Hooks.internal_call(:after_user_offline, [updated])
            end)

            ok

          err ->
            err
        end
    end
  end
end
