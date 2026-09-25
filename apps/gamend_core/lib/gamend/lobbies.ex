defmodule Gamend.Lobbies do
  @moduledoc """
  Context module for lobby management: creating, updating, listing and searching lobbies.

  This module contains the core domain operations; more advanced membership and
  permission logic will be added in follow-up tasks.

  ## Usage

      # Create a lobby (returns {:ok, lobby} | {:error, changeset})
      {:ok, lobby} = Gamend.Lobbies.create_lobby(%{name: "fun-room", title: "Fun Room", host_id: host_id})

      # List public lobbies (paginated/filterable)
      lobbies = Gamend.Lobbies.list_lobbies(%{}, page: 1, page_size: 25)

      # Join and leave
      {:ok, user} = Gamend.Lobbies.join_lobby(user, lobby.id)
      {:ok, _} = Gamend.Lobbies.leave_lobby(user)

      # Get current lobby members
      members = Gamend.Lobbies.get_lobby_members(lobby)

      # Subscribe to global or per-lobby events
      :ok = Gamend.Lobbies.subscribe_lobbies()
      :ok = Gamend.Lobbies.subscribe_lobby(lobby.id)

  ## PubSub Events

  This module broadcasts the following events:

  - `"lobbies"` topic (global lobby list changes):
    - `{:lobby_created, lobby}` - a new lobby was created
    - `{:lobby_updated, lobby}` - a lobby was updated
    - `{:lobby_deleted, lobby_id}` - a lobby was deleted

  - `"lobby:<lobby_id>"` topic (per-lobby membership changes):
    - `{:user_joined, lobby_id, user_id}` - a user joined the lobby
    - `{:user_left, lobby_id, user_id}` - a user left the lobby
    - `{:user_kicked, lobby_id, user_id}` - a user was kicked from the lobby
    - `{:lobby_updated, lobby}` - the lobby settings were updated
    - `{:host_changed, lobby_id, new_host_id}` - the host changed (e.g., after host leaves)
  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: Gamend.Cache

  require Logger

  alias Bcrypt
  alias Ecto.Multi
  alias Gamend.Accounts
  alias Gamend.Accounts.PasswordHash
  alias Gamend.Accounts.User
  alias Gamend.Friends
  alias Gamend.KV
  alias Gamend.Lobbies.Lobby
  alias Gamend.Lobbies.SpectatorTracker
  alias Gamend.Lobbies.States
  alias Gamend.Lock
  alias Gamend.Repo
  alias Gamend.Types

  # A state is a game-chosen word (see Gamend.Lobbies.States); core only
  # keeps it a sane string, since a host can set it over the API.
  @max_state_length 64

  defp invalidate_accounts_user_cache(user_id) when is_binary(user_id) do
    # Synchronous invalidation including index keys — the client may join a
    # channel immediately after a lobby operation, so the cached user must
    # already be cleared.
    Gamend.Accounts.invalidate_user_cache_by_id(user_id)
  end

  # PubSub topic names
  @lobbies_topic "lobbies"

  defp lobby_cache_version(lobby_id) when is_binary(lobby_id) do
    Gamend.Cache.get!({:lobbies, :lobby_version, lobby_id}) || 1
  end

  defp invalidate_lobby_cache(lobby_id) when is_binary(lobby_id) do
    Gamend.Async.run(fn ->
      _ = Gamend.Cache.bump_version({:lobbies, :lobby_version, lobby_id})
      :ok
    end)

    :ok
  end

  defp cache_match(nil), do: false
  defp cache_match(_), do: true

  @doc """
  Subscribe to global lobby events (lobby created, updated, deleted).
  """
  @spec subscribe_lobbies() :: :ok | {:error, term()}
  def subscribe_lobbies do
    Phoenix.PubSub.subscribe(Gamend.PubSub, @lobbies_topic)
  end

  @doc """
  Subscribe to a specific lobby's events (membership changes, updates).
  """
  @spec subscribe_lobby(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_lobby(lobby_id) do
    Phoenix.PubSub.subscribe(Gamend.PubSub, "lobby:#{lobby_id}")
  end

  @doc """
  Unsubscribe from a specific lobby's events.
  """
  @spec unsubscribe_lobby(Ecto.UUID.t()) :: :ok
  def unsubscribe_lobby(lobby_id) do
    Phoenix.PubSub.unsubscribe(Gamend.PubSub, "lobby:#{lobby_id}")
  end

  defp broadcast_lobbies(event) do
    Gamend.Broadcast.publish(@lobbies_topic, load_host(event))
  end

  # Every subscriber to the global list serializes the lobby independently, so
  # anything the serializer has to look up is looked up once per subscriber: an
  # unloaded `:host` sends each of them to `Accounts.get_user/1` for the host's
  # display name. One lobby_created with a lobby-browser screen open on 1000
  # clients was 1000 user reads. Resolve it once here, from the same cache
  # those reads would have hit.
  defp load_host({tag, %Lobby{host: %Ecto.Association.NotLoaded{}, host_id: host_id} = lobby})
       when is_binary(host_id) do
    case Accounts.get_user(host_id) do
      %User{} = host -> {tag, %{lobby | host: host}}
      _ -> {tag, lobby}
    end
  end

  defp load_host(event), do: event

  defp broadcast_lobby(lobby_id, event) do
    Gamend.Broadcast.publish("lobby:#{lobby_id}", event)
  end

  @doc "Broadcast a member presence event (online/offline) to a lobby's PubSub topic."
  @spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
  def broadcast_member_presence(lobby_id, event) do
    broadcast_lobby(lobby_id, event)
  end

  @doc """
  List lobbies. Accepts optional search filters.

  ## Filters

    * `:title` - Filter by title (partial match)
    * `:is_passworded` - boolean or string 'true'/'false' (omit for any)
    * `:is_locked` - boolean or string 'true'/'false' (omit for any)
    * `:state` - lifecycle state (see `Gamend.Lobbies.States`)
    * `:min_users` - Filter lobbies with max_users >= value
    * `:max_users` - Filter lobbies with max_users <= value
    * `:metadata_key` - Filter by metadata key
    * `:metadata_value` - Filter by metadata value (requires metadata_key)

  ## Options

  See `t:Gamend.Types.lobby_list_opts/0` for available options.
  """
  @spec list_lobbies() :: [Lobby.t()]
  @spec list_lobbies(map()) :: [Lobby.t()]
  @spec list_lobbies(map(), Types.lobby_list_opts()) :: [Lobby.t()]
  def list_lobbies(filters \\ %{}, opts \\ []) do
    list_lobbies_uncached(filters, opts)
  end

  defp list_lobbies_uncached(filters, opts) do
    q = from(l in Lobby)

    q =
      q
      |> filter_by_title(filters)
      |> filter_by_hidden_false()
      |> filter_by_passworded(filters)
      |> filter_by_locked(filters)
      |> filter_by_state(filters)
      |> filter_by_min_users(filters)
      |> filter_by_max_users(filters)

    results = q |> preload(:host) |> paginate(opts)

    filter_by_metadata_in_memory(results, filters)
  end

  defp filter_by_hidden_false(q) do
    from l in q, where: l.is_hidden == false
  end

  defp filter_by_state(q, filters) do
    case Map.get(filters, :state) || Map.get(filters, "state") do
      nil -> q
      v when is_binary(v) and v != "" -> from l in q, where: l.state == ^v
      _ -> q
    end
  end

  defp filter_by_passworded(q, filters) do
    case Map.get(filters, :is_passworded) || Map.get(filters, "is_passworded") do
      nil -> q
      v when v in [true, "true", "1"] -> from l in q, where: not is_nil(l.password_hash)
      v when v in [false, "false", "0"] -> from l in q, where: is_nil(l.password_hash)
      _ -> q
    end
  end

  defp filter_by_min_users(q, filters) do
    case Map.get(filters, :min_users) || Map.get(filters, "min_users") do
      nil ->
        q

      v ->
        case to_int_or_nil(v) do
          nil -> q
          int -> from l in q, where: l.max_users >= ^int
        end
    end
  end

  defp filter_by_max_users(q, filters) do
    case Map.get(filters, :max_users) || Map.get(filters, "max_users") do
      nil ->
        q

      v ->
        case to_int_or_nil(v) do
          nil -> q
          int -> from l in q, where: l.max_users <= ^int
        end
    end
  end

  defp filter_by_metadata_in_memory(results, filters) do
    case Map.get(filters, :metadata_key) || Map.get(filters, "metadata_key") do
      nil ->
        results

      key ->
        value = Map.get(filters, :metadata_value) || Map.get(filters, "metadata_value")

        Enum.filter(results, fn l ->
          case Map.get(l.metadata || %{}, key) do
            nil -> false
            _ when is_nil(value) -> true
            v -> String.contains?(to_string(v), to_string(value))
          end
        end)
    end
  end

  @doc "Count lobbies matching filters (excludes hidden ones unless admin list used). If metadata filters are supplied, they will be applied after fetching."
  @spec count_list_lobbies() :: non_neg_integer()
  @spec count_list_lobbies(map()) :: non_neg_integer()
  def count_list_lobbies(filters \\ %{}) do
    count_list_lobbies_uncached(filters)
  end

  defp count_list_lobbies_uncached(filters) do
    q =
      from(l in Lobby)
      |> filter_by_title(filters)
      |> filter_by_hidden_false()

    db_count = Repo.one(from l in q, select: count(l.id)) || 0

    metadata_key = Map.get(filters, :metadata_key) || Map.get(filters, "metadata_key")
    metadata_value = Map.get(filters, :metadata_value) || Map.get(filters, "metadata_value")

    if is_nil(metadata_key) do
      db_count
    else
      q
      |> Repo.all()
      |> Enum.count(fn l ->
        case Map.get(l.metadata || %{}, metadata_key) do
          nil -> false
          _ when is_nil(metadata_value) -> true
          v -> String.contains?(to_string(v), to_string(metadata_value))
        end
      end)
    end
  end

  @doc """
  List ALL lobbies including hidden ones. For admin use only.
  Accepts filters: %{
    title: string,
    is_hidden: boolean/string,
    is_locked: boolean/string,
    has_password: boolean/string,
    min_users: integer (filter by max_users >= val),
    max_users: integer (filter by max_users <= val)
  }
  """
  @spec list_all_lobbies() :: [Lobby.t()]
  @spec list_all_lobbies(map()) :: [Lobby.t()]
  @spec list_all_lobbies(map(), Types.pagination_opts()) :: [Lobby.t()]
  def list_all_lobbies(filters \\ %{}, opts \\ []) do
    page = Keyword.get(opts, :page, nil)
    page_size = Keyword.get(opts, :page_size, nil)

    if page && page_size do
      list_all_lobbies_paged_uncached(filters, page, page_size)
    else
      q = from(l in Lobby)
      q = apply_admin_filters(q, filters)
      Repo.all(q)
    end
  end

  defp list_all_lobbies_paged_uncached(filters, page, page_size)
       when is_map(filters) and is_integer(page) and is_integer(page_size) do
    q = from(l in Lobby)
    q = apply_admin_filters(q, filters)
    sort_by = Map.get(filters, "sort_by") || Map.get(filters, :sort_by) || "updated_at"
    q = apply_admin_sort(q, sort_by)

    offset = (page - 1) * page_size
    Repo.all(from l in q, limit: ^page_size, offset: ^offset)
  end

  @doc """
  Count ALL lobbies matching filters. For admin pagination.
  """
  @spec count_list_all_lobbies() :: non_neg_integer()
  @spec count_list_all_lobbies(map()) :: non_neg_integer()
  def count_list_all_lobbies(filters \\ %{}) do
    count_list_all_lobbies_uncached(filters)
  end

  defp count_list_all_lobbies_uncached(filters) when is_map(filters) do
    q = from(l in Lobby)
    q = apply_admin_filters(q, filters)
    Repo.aggregate(q, :count, :id)
  end

  @doc """
  Aggregate lobby counts for the public stats endpoint.

  Spectators live in Presence, keyed per lobby topic, and Presence cannot
  enumerate its own topics — so the lobby ids come from the table first. That
  makes the total one query plus an ETS read per lobby, which is why it sits
  inside the cached snapshot rather than being computed per request.
  """
  @spec stats() :: %{
          lobbies_total: non_neg_integer(),
          by_state: %{String.t() => non_neg_integer()},
          spectators: non_neg_integer()
        }
  def stats do
    Gamend.Cache.cached({:lobbies, :stats}, [ttl: Gamend.Cache.ttl()], fn ->
      lobby_ids = Repo.all(from(l in Lobby, select: l.id))

      spectators =
        lobby_ids
        |> SpectatorTracker.counts()
        |> Map.values()
        |> Enum.sum()

      %{
        lobbies_total: length(lobby_ids),
        by_state: lobby_counts_by_state(),
        spectators: spectators
      }
    end)
  end

  @doc "Ids of lobbies with WebRTC enabled — the signaling rooms that can exist."
  @spec webrtc_enabled_lobby_ids() :: [Ecto.UUID.t()]
  def webrtc_enabled_lobby_ids do
    Repo.all(from(l in Lobby, where: l.webrtc_enabled == true, select: l.id))
  end

  # One grouped query rather than a count per state: states are game-chosen
  # words, so the set is not known here.
  defp lobby_counts_by_state do
    from(l in Lobby, group_by: l.state, select: {l.state, count(l.id)})
    |> Repo.all()
    |> Map.new(fn {state, count} -> {state || "unknown", count} end)
  end

  @doc """
  Returns the count of hostless lobbies.
  """
  @spec count_hostless_lobbies() :: non_neg_integer()
  def count_hostless_lobbies do
    Repo.one(from l in Lobby, where: l.hostless == true, select: count(l.id)) || 0
  end

  @doc """
  Returns the count of hidden lobbies.
  """
  @spec count_hidden_lobbies() :: non_neg_integer()
  def count_hidden_lobbies do
    Repo.one(from l in Lobby, where: l.is_hidden == true, select: count(l.id)) || 0
  end

  @doc """
  Returns the count of locked lobbies.
  """
  @spec count_locked_lobbies() :: non_neg_integer()
  def count_locked_lobbies do
    Repo.one(from l in Lobby, where: l.is_locked == true, select: count(l.id)) || 0
  end

  @doc """
  Returns the count of lobbies with passwords.
  """
  @spec count_passworded_lobbies() :: non_neg_integer()
  def count_passworded_lobbies do
    Repo.one(from l in Lobby, where: not is_nil(l.password_hash), select: count(l.id)) || 0
  end

  defp apply_admin_filters(q, filters) do
    q
    |> filter_by_title(filters)
    |> filter_by_hidden(filters)
    |> filter_by_locked(filters)
    |> filter_by_state(filters)
    |> filter_by_password(filters)
    |> filter_by_min_users_admin(filters)
    |> filter_by_max_users_admin(filters)
  end

  defp filter_by_title(q, filters) do
    case Map.get(filters, :title) || Map.get(filters, "title") do
      nil ->
        q

      "" ->
        q

      term ->
        trimmed = term |> to_string() |> String.trim()

        if trimmed == "" do
          q
        else
          prefix = Repo.escape_like(String.downcase(trimmed)) <> "%"
          from l in q, where: fragment("lower(?) LIKE ? ESCAPE '\\'", l.title, ^prefix)
        end
    end
  end

  defp filter_by_hidden(q, filters) do
    case Map.get(filters, :is_hidden) || Map.get(filters, "is_hidden") do
      nil -> q
      "" -> q
      val when val in [true, "true", "1"] -> from l in q, where: l.is_hidden == true
      val when val in [false, "false", "0"] -> from l in q, where: l.is_hidden == false
      _ -> q
    end
  end

  defp filter_by_locked(q, filters) do
    case Map.get(filters, :is_locked) || Map.get(filters, "is_locked") do
      nil -> q
      "" -> q
      val when val in [true, "true", "1"] -> from l in q, where: l.is_locked == true
      val when val in [false, "false", "0"] -> from l in q, where: l.is_locked == false
      _ -> q
    end
  end

  defp filter_by_password(q, filters) do
    case Map.get(filters, :has_password) || Map.get(filters, "has_password") do
      nil -> q
      "" -> q
      val when val in [true, "true", "1"] -> from l in q, where: not is_nil(l.password_hash)
      val when val in [false, "false", "0"] -> from l in q, where: is_nil(l.password_hash)
      _ -> q
    end
  end

  defp filter_by_min_users_admin(q, filters) do
    case Map.get(filters, :min_users) || Map.get(filters, "min_users") do
      nil ->
        q

      "" ->
        q

      val ->
        val_int = to_int_or_nil(val) || 0
        from l in q, where: l.max_users >= ^val_int
    end
  end

  defp filter_by_max_users_admin(q, filters) do
    case Map.get(filters, :max_users) || Map.get(filters, "max_users") do
      nil ->
        q

      "" ->
        q

      val ->
        val_int = to_int_or_nil(val) || 0
        from l in q, where: l.max_users <= ^val_int
    end
  end

  defp apply_admin_sort(q, "updated_at"), do: order_by(q, [l], desc: l.updated_at)
  defp apply_admin_sort(q, "updated_at_asc"), do: order_by(q, [l], asc: l.updated_at)
  defp apply_admin_sort(q, "inserted_at"), do: order_by(q, [l], desc: l.inserted_at)
  defp apply_admin_sort(q, "inserted_at_asc"), do: order_by(q, [l], asc: l.inserted_at)
  defp apply_admin_sort(q, "max_users"), do: order_by(q, [l], desc: l.max_users)
  defp apply_admin_sort(q, "max_users_asc"), do: order_by(q, [l], asc: l.max_users)
  defp apply_admin_sort(q, _), do: order_by(q, [l], desc: l.updated_at)

  @doc """
  List lobbies visible to a specific user.
  Includes the user's own lobby even if it's hidden.
  """
  @spec list_lobbies_for_user(User.t() | nil) :: [Lobby.t()]
  @spec list_lobbies_for_user(User.t() | nil, map()) :: [Lobby.t()]
  @spec list_lobbies_for_user(User.t() | nil, map(), Types.lobby_list_opts()) :: [Lobby.t()]
  def list_lobbies_for_user(user, filters \\ %{}, opts \\ [])

  def list_lobbies_for_user(%User{id: user_id, lobby_id: user_lobby_id}, filters, opts) do
    public_lobbies = list_lobbies(filters, opts)

    if is_nil(user_lobby_id) do
      public_lobbies
    else
      # Check if user's lobby is hidden and needs to be included
      user_lobby = get_lobby(user_lobby_id)

      if is_nil(user_lobby) do
        _ = invalidate_accounts_user_cache(user_id)
        public_lobbies
      else
        if user_lobby.is_hidden &&
             !Enum.any?(public_lobbies, &(&1.id == user_lobby_id)) do
          [user_lobby | public_lobbies]
        else
          public_lobbies
        end
      end
    end
  end

  def list_lobbies_for_user(nil, filters, opts), do: list_lobbies(filters, opts)

  @doc """
  Join a user to a lobby.

  ## Options

    * `:password` - password for a password-protected lobby
    * `:bypass_lock` - when `true`, join succeeds even if the lobby is locked.
    * `:bypass_hidden` - when `true`, join succeeds even if the lobby is hidden.
      For server-side callers (matchmaking, hooks, admin) that already know the
      lobby is the right one; a client-facing path must never set it.
      Only set this from trusted server-side code; the HTTP and channel
      surfaces never pass it, so players cannot unlock a lobby themselves.

  Returns `{:ok, user}` with the updated user, or `{:error, reason}` where
  reason is one of `:already_in_lobby`, `:locked`, `:full`, `:blocked`,
  `:password_required`, `:invalid_password`, `:invalid_lobby`.
  """
  @spec join_lobby(User.t(), Lobby.t() | Ecto.UUID.t()) ::
          {:ok, User.t()} | {:error, term()}
  @spec join_lobby(User.t(), Lobby.t() | Ecto.UUID.t(), map() | keyword()) ::
          {:ok, User.t()} | {:error, term()}
  def join_lobby(user, lobby_arg, opts \\ %{})

  def join_lobby(%User{id: user_id} = _user, %Lobby{} = lobby, opts) do
    if is_nil(lobby.id) do
      Logger.error(
        "join_lobby called with lobby missing id user_id=#{user_id} title=#{inspect(lobby.title)}"
      )

      {:error, :invalid_lobby}
    else
      do_join(user_id, lobby, opts)
    end
  end

  def join_lobby(%User{} = user, lobby_id, opts) when is_binary(lobby_id) do
    case get_lobby(lobby_id) do
      %Lobby{} = lobby ->
        join_lobby(user, lobby, opts)

      nil ->
        {:error, :invalid_lobby}
    end
  end

  def join_lobby(_user, _lobby, _opts), do: {:error, :invalid}

  defp do_join(user_id, lobby, opts) do
    # Use Repo.get directly instead of cached Accounts.get_user/1.
    # The cached version would store the current lobby_id state which,
    # combined with concurrent requests through the Guardian pipeline,
    # can poison the cache via the non-atomic @decorate cacheable
    # (a concurrent Cache.put of stale data can land after the
    # post-commit Cache.delete inside create_membership).
    user = Repo.get(User, user_id)

    cond do
      user && user.lobby_id ->
        {:error, :already_in_lobby}

      lobby.is_locked and not opt(opts, :bypass_lock, false) ->
        {:error, :locked}

      # A hidden lobby is invite-only by construction: `list_lobbies/2` excludes
      # it and `show/2` 404s it "so a 403 does not confirm it exists" — but join
      # never checked, so an id (which the public user listing hands out via
      # `lobby_id`) was enough to walk into one. Server-side callers pass
      # `bypass_hidden` the way they already pass `bypass_lock`.
      lobby.is_hidden and not opt(opts, :bypass_hidden, false) ->
        {:error, :not_found}

      true ->
        case do_join_with_lock(user, lobby, opts, user_id) do
          {:ok, updated_user} ->
            # Post-commit: write the correct value to cache so stale
            # concurrent @decorate cacheable puts are overwritten.
            Accounts.cache_user(updated_user)
            # Also post-commit: adding a late arrival to an open ready check
            # broadcasts, which must never happen inside the join transaction.
            _ = Gamend.ReadyChecks.add_member(lobby.id, user_id)
            {:ok, updated_user}

          error ->
            error
        end
    end
  end

  # The lock guards the seat count against a concurrent join, and only that.
  # The slow gates run before it: the plugin's hook (up to its timeout) and the
  # password check (bcrypt, ~250ms). Inside the lock they held the lobby and,
  # on SQLite, the only database connection, so repeated wrong passwords from
  # one player stalled every request in the server. The seat check also runs
  # first, unlocked, so a full lobby is refused without calling the hook.
  defp do_join_with_lock(user, lobby, opts, user_id) do
    with :ok <- check_seat(lobby, user_id),
         :ok <- run_before_join(user, lobby, opts),
         :ok <- check_password(lobby, opt(opts, :password)) do
      Lock.serialize(:lobby, lobby.id, fn ->
        with :ok <- check_seat(lobby, user_id),
             {:ok, updated_user} <-
               create_membership(%{lobby_id: lobby.id, user_id: user_id}) do
          updated_user
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  defp check_seat(lobby, user_id) do
    member_ids =
      Repo.all(
        from(u in User,
          where: u.lobby_id == ^lobby.id,
          select: u.id
        )
      )

    cond do
      length(member_ids) >= lobby.max_users -> {:error, :full}
      # A block in either direction keeps the pair apart, so the blocker does
      # not have to be the one already seated.
      Friends.any_blocked?(user_id, member_ids) -> {:error, :blocked}
      true -> :ok
    end
  end

  defp run_before_join(user, lobby, opts) do
    case Gamend.Hooks.internal_call(:before_lobby_join, [user, lobby, opts]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:hook_rejected, reason}}
    end
  end

  # join opts accept either a map or a keyword list
  defp opt(opts, key, default \\ nil)
  defp opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp opt(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)

  defp check_password(%Lobby{password_hash: nil}, _password), do: :ok
  defp check_password(%Lobby{}, nil), do: {:error, :password_required}

  defp check_password(%Lobby{password_hash: hash}, password) do
    if PasswordHash.verify(password, hash), do: :ok, else: {:error, :invalid_password}
  end

  @spec get_lobby!(Ecto.UUID.t()) :: Lobby.t()
  @decorate cacheable(
              key: {:lobbies, :get, lobby_cache_version(id), id},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_lobby!(id), do: Repo.get_uuid!(Lobby, id)

  @spec get_lobby(Ecto.UUID.t()) :: Lobby.t() | nil
  @decorate cacheable(
              key: {:lobbies, :get, lobby_cache_version(id), id},
              match: &cache_match/1,
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_lobby(id), do: Repo.get_uuid(Lobby, id)

  @doc """
  Gets all users currently in a lobby.

  Returns a list of User structs.

  ## Examples

      iex> get_lobby_members(lobby)
      [%User{}, %User{}]

      iex> get_lobby_members(lobby_id)
      [%User{}]

  """
  @spec get_lobby_members(Lobby.t() | Ecto.UUID.t()) :: [User.t()]
  def get_lobby_members(%Lobby{id: lobby_id}), do: get_lobby_members(lobby_id)

  def get_lobby_members(lobby_id) when is_binary(lobby_id) do
    Repo.all(
      from u in Gamend.Accounts.User,
        where: u.lobby_id == ^lobby_id,
        order_by: [asc: u.inserted_at]
    )
  end

  @doc """
  Creates a new lobby.

  ## Attributes

  See `t:Gamend.Types.lobby_create_attrs/0` for available fields.
  """
  @spec create_lobby() :: {:ok, Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  @spec create_lobby(Types.lobby_create_attrs()) ::
          {:ok, Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_lobby(attrs \\ %{}) do
    attrs = normalize_changeset_params(attrs)
    attrs = maybe_hash_password(attrs)
    do_create_lobby(attrs)
  end

  defp do_create_lobby(attrs) do
    # if host_id is provided, prevent a user who is already a member of a lobby
    # from creating an additional lobby
    # ensure title is present and always ensure it is unique in the DB.
    # If the caller provided a title, use it as the base and derive a unique
    # candidate; otherwise fall back to the default base "lobby".
    # Treat keys that are present but blank/nil as "not provided" so we
    # generate a title in those cases.
    title_val = Map.get(attrs, "title") || Map.get(attrs, :title)

    has_title =
      case title_val do
        nil -> false
        v when is_binary(v) -> String.trim(v) != ""
        _ -> true
      end

    attrs =
      if has_title do
        # Caller provided a title — respect it as-is.
        attrs
      else
        # No title provided: generate a unique candidate using default base.
        title_key =
          cond do
            Map.has_key?(attrs, "title") -> "title"
            Map.has_key?(attrs, :title) -> :title
            true -> if(prefer_string_keys?(attrs), do: "title", else: :title)
          end

        Map.put(attrs, title_key, unique_title_candidate("lobby"))
      end

    case Gamend.Hooks.internal_call(:before_lobby_create, [attrs]) do
      {:ok, attrs} ->
        attrs = normalize_changeset_params(attrs)

        Multi.new()
        |> Multi.run(:check_host, fn _repo, _changes ->
          validate_host_not_in_lobby(attrs)
        end)
        |> Multi.insert(:lobby, new_lobby_changeset(attrs))
        |> maybe_add_host_membership(attrs)
        |> Gamend.AfterCommit.transaction()

      {:error, reason} ->
        {:error, {:hook_rejected, reason}}
    end
    |> case do
      {:ok, %{lobby: lobby} = multi_result} ->
        lobby = normalize_hostless_lobby(lobby)

        # Post-commit user cache handling for host membership.
        # The cache invalidation inside maybe_add_host_membership fires before
        # the Multi transaction commits, so a concurrent Accounts.get_user
        # call can re-poison the cache with stale (lobby_id=nil) data.
        # Writing the correct value here closes that race.
        case multi_result do
          %{membership: updated_user} ->
            _ = invalidate_accounts_user_cache(updated_user.id)
            Accounts.cache_user(updated_user)

          _ ->
            :ok
        end

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_lobby_create, [lobby])
        end)

        # Invalidate after normalize_hostless_lobby to avoid race
        # where cache is re-populated with pre-normalization state.
        _ = invalidate_lobby_cache(lobby.id)
        broadcast_lobbies({:lobby_created, lobby})

        {:ok, lobby}

      {:error, _op, changeset, _} ->
        {:error, changeset}

      other ->
        other
    end
  end

  defp normalize_hostless_lobby(%Lobby{hostless: true, host_id: host_id} = lobby)
       when host_id != nil do
    lobby
    |> Ecto.Changeset.change(%{host_id: nil})
    |> Repo.update()
    |> case do
      {:ok, updated} -> updated
      {:error, _} -> lobby
    end
  end

  defp normalize_hostless_lobby(%Lobby{} = lobby), do: lobby

  @spec validate_host_not_in_lobby(map()) :: {:ok, :ok} | {:error, :already_in_lobby}
  defp validate_host_not_in_lobby(attrs) do
    host_id = Map.get(attrs, "host_id") || Map.get(attrs, :host_id)

    if host_id do
      host_user = Accounts.get_user(host_id)

      if host_user && host_user.lobby_id do
        {:error, :already_in_lobby}
      else
        {:ok, :ok}
      end
    else
      {:ok, :ok}
    end
  end

  @spec maybe_add_host_membership(Ecto.Multi.t(), map()) :: Ecto.Multi.t()
  defp maybe_add_host_membership(multi, %{"host_id" => host_id}) when host_id != nil do
    multi
    |> Multi.run(:membership, fn repo, %{lobby: lobby} ->
      user = repo.get(Gamend.Accounts.User, host_id)
      changeset = Ecto.Changeset.change(user, %{lobby_id: lobby.id})

      repo.update(changeset)
      |> case do
        {:ok, updated} = ok ->
          _ = invalidate_accounts_user_cache(updated.id)
          _ = Accounts.broadcast_user_update(updated)
          ok

        other ->
          other
      end
    end)
  end

  defp maybe_add_host_membership(multi, %{host_id: host_id}) when host_id != nil do
    multi
    |> Multi.run(:membership, fn repo, %{lobby: lobby} ->
      user = repo.get(Gamend.Accounts.User, host_id)
      changeset = Ecto.Changeset.change(user, %{lobby_id: lobby.id})

      repo.update(changeset)
      |> case do
        {:ok, updated} = ok ->
          _ = invalidate_accounts_user_cache(updated.id)
          _ = Accounts.broadcast_user_update(updated)
          ok

        other ->
          other
      end
    end)
  end

  defp maybe_add_host_membership(multi, _), do: multi

  defp unique_title_candidate(base) when is_binary(base) do
    suffix = :erlang.unique_integer([:positive]) |> Integer.to_string()
    "#{base}-#{suffix}"
  end

  @doc """
  Writes the server-owned `webrtc_*` columns.

  Not castable through `update_lobby/2`, so a client `PATCH` cannot reach them.
  Go through `Gamend.Signaling.configure/2` rather than calling this.
  """
  @spec write_webrtc_config(Lobby.t(), map()) :: {:ok, Lobby.t()} | {:error, Ecto.Changeset.t()}
  def write_webrtc_config(%Lobby{} = lobby, changes) when is_map(changes) do
    lobby
    |> Ecto.Changeset.change(changes)
    |> Repo.update()
    |> case do
      {:ok, updated} = ok ->
        _ = invalidate_lobby_cache(updated.id)
        broadcast_lobby(updated.id, {:lobby_updated, updated})
        ok

      {:error, changeset} = error ->
        Logger.warning(
          "webrtc config write failed lobby=#{lobby.id}: #{inspect(changeset.errors)}"
        )

        error
    end
  end

  @doc """
  Merges `patch` into the lobby's metadata, leaving untouched every key it does
  not mention.

  `update_lobby/2` replaces `metadata` wholesale, so a caller writing its own
  key silently wipes everyone else's — which is why a plugin's configuration
  must not live there. This merges at the top level, and serializes the
  read-modify-write so two concurrent merges cannot lose each other.

  Top-level only: a nested map is replaced, not merged into. Deep merge has no
  obvious answer for deleting a key or combining a list, and a rule nobody can
  predict is worse than one they can.
  """
  @merge_attempts 3

  @spec merge_metadata(Lobby.t(), map()) :: {:ok, Lobby.t()} | {:error, term()}
  def merge_metadata(%Lobby{} = lobby, patch) when is_map(patch) do
    do_merge_metadata(lobby.id, Gamend.Parse.string_keys(patch), @merge_attempts)
  end

  # Optimistic, so the plugins' `before_lobby_update` hook (up to its timeout)
  # runs outside the lock: merge against a fresh read and ask the hook
  # unlocked, then write under the lock only if the metadata is still what the
  # merge started from. A concurrent merge starts it over. The read skips the
  # cache, which could hand back a version a merge already replaced.

  defp do_merge_metadata(lobby_id, patch, attempts) do
    with %Lobby{} = current <- Repo.get(Lobby, lobby_id) || {:error, :not_found},
         merged = Map.merge(current.metadata || %{}, patch),
         {:ok, attrs} <- run_before_lobby_update(current, %{metadata: merged}) do
      Gamend.Lock.serialize(:lobby, lobby_id, fn ->
        case Repo.get(Lobby, lobby_id) do
          %Lobby{metadata: metadata} = fresh when metadata == current.metadata ->
            apply_lobby_update(fresh, attrs)

          %Lobby{} ->
            :stale

          nil ->
            {:error, :not_found}
        end
      end)
      |> case do
        {:ok, :stale} when attempts > 1 -> do_merge_metadata(lobby_id, patch, attempts - 1)
        {:ok, :stale} -> {:error, :conflict}
        {:ok, result} -> result
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Updates an existing lobby.

  ## Attributes

  See `t:Gamend.Types.lobby_update_attrs/0` for available fields.
  """
  @spec update_lobby(Lobby.t(), Types.lobby_update_attrs()) ::
          {:ok, Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  def update_lobby(%Lobby{} = lobby, attrs) do
    with {:ok, attrs_to_use} <- run_before_lobby_update(lobby, attrs) do
      apply_lobby_update(lobby, attrs_to_use)
    end
  end

  # Prefer hook-returned attrs if it's a plain map; if the hook incorrectly
  # returns something else (eg. a struct) fall back to the original params we
  # received so updates from the form are not lost.
  defp run_before_lobby_update(lobby, attrs) do
    case Gamend.Hooks.internal_call(:before_lobby_update, [lobby, attrs]) do
      {:ok, returned} when is_map(returned) and not is_struct(returned) -> {:ok, returned}
      {:ok, _other} -> {:ok, attrs}
      {:error, reason} -> {:error, {:hook_rejected, reason}}
    end
  end

  defp apply_lobby_update(lobby, attrs) do
    result =
      lobby
      |> Lobby.changeset(normalize_changeset_params(attrs))
      |> Repo.update()

    case result do
      {:ok, updated} ->
        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_lobby_updated, [updated])
        end)

        _ = invalidate_lobby_cache(updated.id)

        # After commit, with the members query: a lock around the update
        # (`merge_metadata/2`) need not wait on either. Members are
        # materialized once here so the per-socket channel fan-out serializes
        # the already-loaded list instead of each subscriber re-querying (was
        # O(N) queries / O(N²) rows per update).
        Gamend.AfterCommit.defer(fn ->
          with_members = %{updated | memberships: get_lobby_members(updated.id)}
          broadcast_lobby(updated.id, {:lobby_updated, with_members})
          broadcast_lobbies({:lobby_updated, updated})
        end)

        {:ok, updated}

      other ->
        other
    end
  end

  # Core owns the lifecycle field: a new lobby always starts in the initial
  # state, stamped, regardless of what the caller passed (state is not
  # castable, so this is the only way it gets set at insert).
  defp new_lobby_changeset(attrs) do
    %Lobby{}
    |> Lobby.changeset(attrs)
    |> Ecto.Changeset.put_change(:state, States.initial())
    |> Ecto.Changeset.put_change(:state_changed_at, DateTime.utc_now(:second))
  end

  @doc """
  Client-initiated state change, subject to `can_manage_lobby?/2`.

  The lobby's authority already renames, locks, resizes and kicks, so `state`
  is no more powerful than what it holds, and "press Start" is a normal
  party-game action. A hostless matchmaking lobby with no pinned WebRTC host
  has no authority at all: move it with `transition_state/3` from server-side
  hooks instead.
  """
  @spec transition_state_by_host(User.t(), Lobby.t(), String.t()) ::
          {:ok, Lobby.t()} | {:error, :not_host | :invalid_state | term()}
  def transition_state_by_host(%User{} = user, %Lobby{} = lobby, state) do
    if can_manage_lobby?(user, lobby) do
      transition_state(lobby, state)
    else
      {:error, :not_host}
    end
  end

  @doc """
  Move a lobby to `state` (see `Gamend.Lobbies.States`).

  The only writer of `state`/`state_changed_at` — the columns are not castable,
  so a generic `update_lobby/2` can never move a lobby's state.

  The vocabulary is the game's: core only requires a sane string (non-empty,
  ≤ #{@max_state_length} bytes) and `before_lobby_state_change` enforces
  whatever words and ordering the game cares about. A same-state call is
  a no-op (so at-least-once hook/job retries are safe) and does not re-fire
  hooks. `after_lobby_state_changed` observes post-commit.

  Returns `{:ok, lobby}`, `{:error, :invalid_state}` or
  `{:error, {:hook_rejected, reason}}`.
  """
  @spec transition_state(Lobby.t(), String.t(), keyword()) ::
          {:ok, Lobby.t()} | {:error, :invalid_state | {:hook_rejected, term()} | term()}
  def transition_state(%Lobby{} = lobby, state, opts \\ []) when is_binary(state) do
    cond do
      state == "" or byte_size(state) > @max_state_length ->
        {:error, :invalid_state}

      lobby.state == state ->
        {:ok, lobby}

      true ->
        do_transition_state(lobby, lobby.state, state, opts)
    end
  end

  defp do_transition_state(lobby, from, to, opts) do
    with :ok <- run_before_state_change(lobby, from, to, opts),
         {:ok, updated} <- write_state(lobby, to) do
      Gamend.Async.run(fn ->
        Gamend.Hooks.internal_call(:after_lobby_state_changed, [updated, from, to])
      end)

      _ = invalidate_lobby_cache(updated.id)

      payload = %{
        lobby_id: updated.id,
        from: from,
        to: to,
        state_changed_at: updated.state_changed_at
      }

      broadcast_lobby(updated.id, {:lobby_state_changed, payload})
      broadcast_lobbies({:lobby_updated, updated})

      {:ok, updated}
    end
  end

  defp run_before_state_change(lobby, from, to, opts) do
    if Keyword.get(opts, :skip_hooks, false) do
      :ok
    else
      case Gamend.Hooks.internal_call(:before_lobby_state_change, [lobby, from, to]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, {:hook_rejected, reason}}
      end
    end
  end

  defp write_state(lobby, to) do
    lobby
    |> Ecto.Changeset.change(%{state: to, state_changed_at: DateTime.utc_now(:second)})
    |> Repo.update()
  end

  @spec delete_lobby(Lobby.t()) :: {:ok, Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_lobby(%Lobby{} = lobby) do
    case Gamend.Hooks.internal_call(:before_lobby_delete, [lobby]) do
      {:ok, _} ->
        case do_delete_lobby(lobby) do
          {:ok, {deleted, members}} ->
            Gamend.Async.run(fn ->
              Gamend.Chat.cleanup_chat("lobby", deleted.id)
              Gamend.Hooks.internal_call(:after_lobby_deleted, [deleted])
            end)

            # Detaching the members is one bulk update, so each of them has to
            # be told separately — the `lobby_deleted` broadcast below goes to
            # the lobby LIST topic, which a seated player has no reason to be
            # listening on. Without this a member whose lobby was deleted around
            # them (the abandoned-lobby sweep, a finished game, matchmaking
            # giving up, an admin) went on believing they were seated: the
            # client kept its cached lobby_id, skipped creating a lobby for the
            # next game, and the server refused the start it had no lobby for.
            # Parties announce a disband to each member the same way.
            Enum.each(members, fn member ->
              invalidate_accounts_user_cache(member.id)
              _ = Accounts.broadcast_user_update(%{member | lobby_id: nil})
            end)

            _ = invalidate_lobby_cache(deleted.id)
            broadcast_lobbies({:lobby_deleted, deleted.id})
            {:ok, deleted}

          other ->
            other
        end

      {:error, reason} ->
        {:error, {:hook_rejected, reason}}
    end
  end

  defp do_delete_lobby(%Lobby{id: lobby_id} = lobby) when is_binary(lobby_id) do
    # Before anything is unwound: members are about to be detached and the
    # lobby's KV deleted, so this is the last moment the run's final state is
    # readable. Gathered before the lock rather than inside it: reading up to
    # the KV cap, encoding and hashing it held the lobby and, on SQLite, the
    # only write lock. The write is buffered, so a rollback still keeps it.
    _ = Gamend.LobbySnapshots.capture_lobby(lobby_id, "lobby:deleted", sync: true)

    Lock.serialize(:lobby, lobby_id, fn ->
      # Whole structs rather than ids: delete_lobby/1 announces the detachment
      # to each of them afterwards, and this is the last moment they are
      # readable as members of this lobby.
      members = Repo.all(from u in User, where: u.lobby_id == ^lobby_id)

      _ =
        Repo.update_all(
          from(u in User, where: u.lobby_id == ^lobby_id),
          set: [lobby_id: nil]
        )

      _ = KV.delete_lobby_entries(lobby_id)

      case Repo.delete(lobby) do
        {:ok, deleted} -> {deleted, members}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  @spec change_lobby(Lobby.t()) :: Ecto.Changeset.t()
  @spec change_lobby(Lobby.t(), map()) :: Ecto.Changeset.t()
  def change_lobby(%Lobby{} = lobby, attrs \\ %{}) do
    Lobby.changeset(lobby, attrs)
  end

  ## Membership helpers (minimal for now)

  @spec create_membership(%{lobby_id: Ecto.UUID.t(), user_id: Ecto.UUID.t()}) ::
          {:ok, User.t()} | {:error, :not_found | Ecto.Changeset.t() | term()}
  def create_membership(%{lobby_id: lobby_id, user_id: user_id} = _attrs) do
    # Use Repo.get directly — this function may be called inside a
    # Repo.transaction (e.g. from do_join_with_lock). Using the cached
    # Accounts.get_user/1 would seed the cache with lobby_id=nil
    # before the transaction commits, enabling a concurrent process's
    # @decorate cacheable put to re-poison the cache after our delete.
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        result =
          user
          |> Ecto.Changeset.change(%{lobby_id: lobby_id})
          |> Repo.update()

        case result do
          {:ok, updated_user} ->
            _ = invalidate_accounts_user_cache(updated_user.id)
            _ = Accounts.broadcast_user_update(updated_user)
            _ = Accounts.broadcast_member_update(updated_user)
            broadcast_lobby(lobby_id, {:user_joined, lobby_id, user_id})
            broadcast_lobbies({:lobby_membership_changed, lobby_id})

            # Fetch the lobby before starting the background task so the task
            # does not need to check out a DB connection from the sandbox.
            # Using Repo.get/2 avoids raising if the lobby disappears (tests
            # shouldn't crash because of a background DB lookup).
            lobby = get_lobby(lobby_id)

            Gamend.Async.run(fn ->
              Gamend.Hooks.internal_call(:after_lobby_join, [updated_user, lobby])
              report_join_quest_event(updated_user.id, lobby)
            end)

            {:ok, updated_user}

          _ ->
            result
        end
    end
  end

  defp report_join_quest_event(_user_id, nil), do: :ok

  defp report_join_quest_event(user_id, lobby) do
    Gamend.Quests.report_event(user_id, "lobby_joined", 1, %{"lobby_id" => lobby.id})
  end

  @spec delete_membership(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def delete_membership(%Gamend.Accounts.User{} = user) do
    previous_lobby_id = user.lobby_id

    user
    |> Ecto.Changeset.change(%{lobby_id: nil})
    |> Repo.update()
    |> case do
      {:ok, updated} = ok ->
        _ = invalidate_accounts_user_cache(updated.id)
        _ = clear_lobby_scoped_kv(updated.id, previous_lobby_id)
        _ = Accounts.broadcast_user_update(updated)
        _ = Accounts.broadcast_member_update(updated)
        ok

      other ->
        other
    end
  end

  @spec leave_lobby(User.t()) :: {:ok, term()} | {:error, term()}
  def leave_lobby(%User{id: user_id}) do
    case Accounts.get_user(user_id) do
      nil ->
        {:error, :not_in_lobby}

      %Gamend.Accounts.User{lobby_id: nil} ->
        {:error, :not_in_lobby}

      %Gamend.Accounts.User{} = membership ->
        case get_lobby(membership.lobby_id) do
          nil ->
            delete_membership(membership)

          lobby ->
            do_leave_lobby(membership, lobby, user_id)
        end
    end
  end

  defp do_leave_lobby(membership, lobby, user_id) do
    lobby_id = lobby.id
    emptied_capture = prepare_emptied_capture(lobby, user_id, membership.id)

    result =
      Gamend.AfterCommit.transaction(fn ->
        Repo.update!(Ecto.Changeset.change(membership, %{lobby_id: nil}))
        handle_host_transfer(lobby, user_id, membership.id)
      end)

    if match?({:ok, :lobby_deleted}, result), do: Gamend.LobbySnapshots.record(emptied_capture)

    # Let plugins react to the state that is about to be wiped (e.g. bank cargo
    # collected in a level the player is abandoning). Runs synchronously, before
    # the KV clear, and only when the leave actually committed.
    if match?({:ok, _}, result), do: run_before_lobby_leave(user_id, lobby)

    _ = clear_lobby_scoped_kv(user_id, lobby_id)
    # The check is about who is present; a leaver stops being part of it, and
    # the remaining members may now all be ready.
    _ = Gamend.ReadyChecks.remove_member(lobby_id, user_id)

    result
    |> broadcast_leave_result(lobby_id, user_id)
    |> maybe_run_after_lobby_leave(user_id, lobby)
  rescue
    Ecto.StaleEntryError ->
      # Race condition: user was concurrently removed (double leave, kicked, etc.)
      {:error, :not_in_lobby}
  end

  defp run_before_lobby_leave(user_id, lobby) do
    case Accounts.get_user(user_id) do
      %User{} = user -> Gamend.Hooks.internal_call(:before_lobby_leave, [user, lobby])
      _ -> :ok
    end
  rescue
    exception ->
      Logger.warning("before_lobby_leave hook failed: #{Exception.message(exception)}")
      :ok
  end

  # Per-member lobby state (ready flags, loadouts, character picks) is stored as
  # KV scoped to (user_id, lobby_id). It belongs to the membership, not the user,
  # so it dies with the membership — otherwise a leave and rejoin would silently
  # restore stale state. Lobby deletion is already covered by the cascade on
  # kv_entries.lobby_id.
  defp clear_lobby_scoped_kv(user_id, lobby_id)
       when is_binary(user_id) and is_binary(lobby_id) do
    Gamend.KV.delete_user_lobby_entries(user_id, lobby_id)
  end

  defp clear_lobby_scoped_kv(_user_id, _lobby_id), do: 0

  # The host's leave deletes the lobby when no one else is seated; its final
  # state is read here, before the transaction, rather than inside it, where
  # reading and hashing it held the only SQLite write lock. It is recorded only
  # if the lobby was then deleted. No one else seated is checked again inside:
  # a player joining in between keeps the lobby, and the capture is dropped.
  defp prepare_emptied_capture(lobby, user_id, membership_id) do
    if lobby.host_id == user_id and not lobby.hostless and
         not Repo.exists?(
           from u in Gamend.Accounts.User,
             where: u.lobby_id == ^lobby.id and u.id != ^membership_id
         ) do
      Gamend.LobbySnapshots.prepare(lobby.id, "lobby:emptied")
    end
  end

  defp handle_host_transfer(lobby, user_id, membership_id) do
    # if user was host, transfer host or delete lobby if empty
    if lobby.host_id == user_id and not lobby.hostless do
      remaining =
        Repo.all(
          from u in Gamend.Accounts.User,
            where: u.lobby_id == ^lobby.id and u.id != ^membership_id,
            order_by: u.inserted_at,
            limit: 1
        )

      case remaining do
        [%Gamend.Accounts.User{id: new_host_id} | _] ->
          _ = Repo.update(Ecto.Changeset.change(lobby, %{host_id: new_host_id}))
          _ = invalidate_lobby_cache(lobby.id)
          {:host_changed, new_host_id}

        [] ->
          # no members left - delete lobby (its snapshot was gathered before
          # the transaction, `prepare_emptied_capture/3`)
          _ = Repo.delete(lobby)
          _ = invalidate_lobby_cache(lobby.id)
          :lobby_deleted
      end
    else
      :ok
    end
  end

  defp broadcast_leave_result(result, lobby_id, user_id) do
    case result do
      {:ok, :lobby_deleted} ->
        _ = invalidate_accounts_user_cache(user_id)
        _ = invalidate_lobby_cache(lobby_id)
        maybe_broadcast_user_updated(user_id)
        maybe_broadcast_member_updated(user_id)
        broadcast_lobbies({:lobby_deleted, lobby_id})
        result

      {:ok, {:host_changed, new_host_id}} ->
        _ = invalidate_accounts_user_cache(user_id)
        _ = invalidate_lobby_cache(lobby_id)
        maybe_broadcast_user_updated(user_id)
        maybe_broadcast_member_updated(user_id)
        broadcast_lobby(lobby_id, {:user_left, lobby_id, user_id})
        broadcast_lobby(lobby_id, {:host_changed, lobby_id, new_host_id})
        broadcast_lobbies({:lobby_membership_changed, lobby_id})
        updated_lobby = get_lobby(lobby_id)

        if updated_lobby do
          Gamend.Async.run(fn ->
            Gamend.Hooks.internal_call(:after_lobby_host_change, [updated_lobby, new_host_id])
          end)
        end

        result

      {:ok, _} ->
        _ = invalidate_accounts_user_cache(user_id)
        _ = invalidate_lobby_cache(lobby_id)
        maybe_broadcast_user_updated(user_id)
        maybe_broadcast_member_updated(user_id)
        broadcast_lobby(lobby_id, {:user_left, lobby_id, user_id})
        broadcast_lobbies({:lobby_membership_changed, lobby_id})
        result

      _ ->
        result
    end
  end

  defp maybe_broadcast_member_updated(user_id) when is_binary(user_id) do
    case Accounts.get_user(user_id) do
      %User{} = user -> Accounts.broadcast_member_update(user)
      nil -> :ok
    end
  end

  defp maybe_broadcast_user_updated(user_id) when is_binary(user_id) do
    # `invalidate_accounts_user_cache/1` above ensures this refetch isn't stale.
    case Accounts.get_user(user_id) do
      %User{} = user ->
        _ = Accounts.broadcast_user_update(user)
        :ok

      _ ->
        :ok
    end
  end

  defp maybe_run_after_lobby_leave(result, user_id, lobby) do
    case result do
      {:ok, _} ->
        updated_user = Accounts.get_user(user_id)

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_lobby_leave, [updated_user, lobby])
        end)

        result

      _ ->
        result
    end
  end

  @doc """
  Kick a user from a lobby. Only the lobby's authority can, per
  `can_manage_lobby?/2`.

  Returns {:ok, user} on success, {:error, reason} on failure.
  """
  @spec kick_user(User.t(), Lobby.t(), User.t()) :: {:ok, User.t()} | {:error, term()}
  def kick_user(%User{id: host_id} = host, %Lobby{id: lobby_id}, %User{id: target_id}) do
    lobby = get_lobby!(lobby_id)

    cond do
      not can_manage_lobby?(host, lobby) ->
        {:error, :not_host}

      target_id == host_id ->
        {:error, :cannot_kick_self}

      true ->
        case Accounts.get_user(target_id) do
          nil ->
            {:error, :not_found}

          %Gamend.Accounts.User{lobby_id: ^lobby_id} = membership ->
            do_kick_membership(membership, host_id, lobby)

          _ ->
            {:error, :not_in_lobby}
        end
    end
  end

  def kick_user(_host, _lobby, _target), do: {:error, :invalid}

  defp do_kick_membership(membership, host_id, lobby) do
    host_user = Accounts.get_user(host_id) || %Gamend.Accounts.User{id: host_id}

    case Gamend.Hooks.internal_call(:before_lobby_kick, [
           host_user,
           membership,
           lobby
         ]) do
      {:ok, _} ->
        result = Repo.update(Ecto.Changeset.change(membership, %{lobby_id: nil}))

        case result do
          {:ok, updated} ->
            _ = invalidate_accounts_user_cache(membership.id)
            _ = clear_lobby_scoped_kv(membership.id, lobby.id)
            _ = Gamend.ReadyChecks.remove_member(lobby.id, membership.id)
            _ = Accounts.broadcast_user_update(updated)
            _ = Accounts.broadcast_member_update(updated)

            Gamend.Async.run(fn ->
              Gamend.Hooks.internal_call(:after_lobby_kick, [
                host_user,
                membership,
                lobby
              ])
            end)

            broadcast_lobby(lobby.id, {:user_kicked, lobby.id, membership.id})
            broadcast_lobbies({:lobby_membership_changed, lobby.id})

            # Notify the kicked user
            lobby_title = lobby.title || ""

            Gamend.Notifications.admin_create_notification(
              host_id,
              membership.id,
              %{
                "title" => "Removed from #{lobby_title}",
                "content" => "",
                "metadata" => %{
                  "type" => "lobby_kicked",
                  "lobby_id" => lobby.id,
                  "lobby_name" => lobby_title
                }
              }
            )

            result

          _ ->
            result
        end

      {:error, reason} ->
        {:error, {:hook_rejected, reason}}
    end
  end

  @doc """
  Whether `user` holds authority over `lobby` — the one rule behind editing it,
  moving its `state`, kicking from it, opening its ready checks and moderating
  its chat. Every one of those gates asks this and nothing else.

  Two users hold it:

    * the **host of a host-managed lobby**. Hostless lobbies (matchmaking's)
      belong to nobody, so their `host_id` is nil and this branch never fires.

    * the **pinned WebRTC host**, seated in the lobby or not. Only
      `Gamend.Signaling.configure/2` writes `webrtc_host_id` and no
      player-facing route reaches it, so this is the game designating a
      server, bot or peer as the lobby's authority — the one way a hostless
      matchmaking lobby gets an owner. It is the pinned host alone: the
      `webrtc_host_id || host_id` fallback `Gamend.Signaling.config/1` applies
      is about who relays packets, not who commands the lobby.
  """
  @spec can_manage_lobby?(User.t() | nil, Lobby.t() | nil) :: boolean()
  def can_manage_lobby?(%User{id: user_id}, %Lobby{} = lobby) do
    user_id == lobby.webrtc_host_id or
      (not lobby.hostless and lobby.host_id == user_id)
  end

  def can_manage_lobby?(nil, _lobby), do: false
  def can_manage_lobby?(_user, nil), do: false

  @doc """
  Whether `user` may read `lobby`'s details.

  Hiding a lobby takes it out of public listings; it does not hide it from the
  people already inside. Those are its members and its signaling host — which
  for a hostless matchmaking lobby is the game server running the room rather
  than any player, so it is never a member. Everyone else sees only lobbies
  that are not hidden.
  """
  @spec can_view_lobby?(User.t() | nil, Lobby.t() | nil) :: boolean()
  def can_view_lobby?(_user, nil), do: false
  def can_view_lobby?(nil, %Lobby{is_hidden: hidden}), do: not hidden

  def can_view_lobby?(%User{} = user, %Lobby{} = lobby) do
    not lobby.is_hidden or user.lobby_id == lobby.id or can_manage_lobby?(user, lobby)
  end

  @doc """
  Check if a lobby can be spectated (watched by non-members).

  A lobby is spectatable if it is not hidden, not locked and not
  password-protected.

  The password clause matters because spectating is not a read-only peek: the
  channel subscribes the spectator to lobby chat and hands them an after-join
  payload built with the full member list. The password gated the HTTP join and
  nothing on the channel, so it protected participation while leaving the
  conversation and the roster open to anyone who knew the lobby id.
  """
  @spec spectatable?(Lobby.t()) :: boolean()
  def spectatable?(%Lobby{is_hidden: true}), do: false
  def spectatable?(%Lobby{is_locked: true}), do: false
  def spectatable?(%Lobby{password_hash: hash}) when is_binary(hash), do: false
  def spectatable?(%Lobby{}), do: true

  @doc """
  Client-initiated lobby update, subject to `can_manage_lobby?/2`.

  A hostless matchmaking lobby with no pinned WebRTC host has no authority, so
  none of its members may edit it — one could otherwise rewrite `metadata`,
  `max_users`, `password_hash` and the visibility flags of a ranked match it
  merely happens to be in. Server-side code (hooks, jobs, matchmaking, admin)
  uses `update_lobby/2` instead.
  """
  @spec update_lobby_by_host(User.t(), Lobby.t(), Types.lobby_update_attrs()) ::
          {:ok, Lobby.t()} | {:error, :not_host | :too_small | Ecto.Changeset.t() | term()}
  def update_lobby_by_host(%User{} = user, %Lobby{} = lobby, attrs) do
    if can_manage_lobby?(user, lobby) do
      attrs = attrs |> take_client_update_fields() |> maybe_hash_password()
      new_max = Map.get(attrs, "max_users") || Map.get(attrs, :max_users)

      if is_nil(new_max) do
        update_lobby(lobby, attrs)
      else
        validate_and_update_max_users(lobby, attrs, new_max)
      end
    else
      {:error, :not_host}
    end
  end

  # The fields a lobby's host may set, and only those.
  #
  # `Lobby.changeset/2` also casts `host_id`, `hostless` and `password_hash`,
  # which are server-owned: the controller forwarded every parameter, so a host
  # could hand ownership to someone else, write the password hash directly
  # (skipping hashing), or set `hostless` — which makes `can_manage_lobby?/2`
  # false for everyone and leaves the lobby permanently unmanageable. `slowdown`
  # is included because hosts do set it; the password is hashed downstream.
  @client_lobby_fields ~w(title max_users is_hidden is_locked password metadata slowdown)

  defp take_client_update_fields(attrs) when is_map(attrs) do
    allowed = @client_lobby_fields ++ Enum.map(@client_lobby_fields, &String.to_existing_atom/1)
    Map.take(attrs, allowed)
  end

  defp validate_and_update_max_users(lobby, attrs, new_max) do
    # ensure new_max is an integer
    new_max = to_int_or_nil(new_max)

    current_count =
      Repo.one(
        from(u in Gamend.Accounts.User,
          where: u.lobby_id == ^lobby.id,
          select: count(u.id)
        )
      ) || 0

    if new_max < current_count do
      {:error, :too_small}
    else
      update_lobby(lobby, attrs)
    end
  end

  # Argon2id, as account passwords are (`PasswordHash`): bcrypt at cost 12
  # spent ~250ms of CPU on every join attempt, ten times Argon2id's here, and a
  # join is something any signed-in player can repeat. Existing bcrypt hashes
  # still verify.
  defp maybe_hash_password(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, "password") and attrs["password"] != nil ->
        Map.put(attrs, "password_hash", PasswordHash.hash(attrs["password"]))
        |> Map.delete("password")

      Map.has_key?(attrs, :password) and attrs[:password] != nil ->
        Map.put(attrs, :password_hash, PasswordHash.hash(attrs[:password]))
        |> Map.delete(:password)

      true ->
        attrs
    end
  end

  defp maybe_hash_password(other), do: other

  defp normalize_changeset_params(attrs) when is_map(attrs) do
    keys = Map.keys(attrs)
    has_string = Enum.any?(keys, &is_binary/1)
    has_atom = Enum.any?(keys, &is_atom/1)

    if has_string and has_atom do
      Map.new(attrs, fn {k, v} ->
        if is_atom(k), do: {Atom.to_string(k), v}, else: {k, v}
      end)
    else
      attrs
    end
  end

  defp normalize_changeset_params(other), do: other

  defp prefer_string_keys?(attrs) when is_map(attrs) do
    Enum.any?(Map.keys(attrs), &is_binary/1)
  end

  @spec list_memberships_for_lobby(Ecto.UUID.t()) :: [User.t()]
  def list_memberships_for_lobby(lobby_id) do
    from(u in Gamend.Accounts.User, where: u.lobby_id == ^lobby_id)
    |> Repo.all()
  end

  @doc """
  Attempt to find an open lobby matching the given criteria and join it, or
  create a new lobby if none matches.

  Signature: quick_join(user, title \\ nil, max_users \\ nil, metadata \\ %{})

  - If the user is already in a lobby returns {:error, :already_in_lobby}
  - On successful join or creation returns {:ok, lobby}
  - Propagates errors from join or create flows
  """
  @spec quick_join(User.t()) ::
          {:ok, Lobby.t()} | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  @spec quick_join(User.t(), String.t() | nil) ::
          {:ok, Lobby.t()} | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  @spec quick_join(User.t(), String.t() | nil, integer() | nil) ::
          {:ok, Lobby.t()} | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  @spec quick_join(User.t(), String.t() | nil, integer() | nil, map()) ::
          {:ok, Lobby.t()} | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  def quick_join(%User{id: _user_id} = user, title \\ nil, max_users \\ nil, metadata \\ %{}) do
    # reload user in case their membership changed since the caller was loaded
    user = Accounts.get_user(user.id)

    if user && user.lobby_id do
      {:error, :already_in_lobby}
    else
      # base query: only consider visible/unlocked and non-passworded lobbies
      # quick_join prioritizes public, passwordless matches to avoid prompting for password
      q =
        from(l in Lobby,
          where: l.is_hidden == false and l.is_locked == false and is_nil(l.password_hash)
        )

      q =
        if is_nil(max_users) do
          q
        else
          from(l in q, where: l.max_users == ^max_users)
        end

      # order candidates deterministically by insertion time and limit how many we try
      max_candidates = 5

      candidates =
        Repo.all(from(l in q, order_by: [asc: l.inserted_at], limit: ^max_candidates))

      # Try candidates in order — if a candidate fails due to full, move to next.
      tried =
        Enum.reduce_while(candidates, {:none, []}, fn lobby, _acc ->
          if lobby_matches_metadata?(lobby, metadata) do
            attempt_quick_join(user, lobby)
          else
            {:cont, {:none, []}}
          end
        end)

      case tried do
        {:ok, %Lobby{} = lobby} ->
          {:ok, lobby}

        {:error, _} = err ->
          err

        {:none, _} ->
          # no match found -> create a new lobby with the provided params
          attrs = %{}
          attrs = if title, do: Map.put(attrs, :title, title), else: attrs
          attrs = if max_users, do: Map.put(attrs, :max_users, max_users), else: attrs

          attrs =
            if metadata && metadata != %{}, do: Map.put(attrs, :metadata, metadata), else: attrs

          attrs = Map.put(attrs, :host_id, user.id)

          case create_lobby(attrs) do
            {:ok, lobby} -> {:ok, lobby}
            other -> other
          end
      end
    end
  end

  # Unlike the other contexts this one runs the query. The window itself comes
  # from `Gamend.Query`, which clamps to the *configured* `max_page_size` — the
  # hard-coded 1000 here ignored it.
  defp paginate(q, opts), do: q |> Gamend.Query.maybe_page(opts) |> Repo.all()

  @doc false
  def lobby_matches_metadata?(lobby, metadata) do
    Enum.all?(Map.to_list(metadata || %{}), fn
      {_k, v} when is_nil(v) ->
        true

      {k, v} ->
        case Map.get(lobby.metadata || %{}, k) do
          nil -> false
          existing -> String.contains?(to_string(existing), to_string(v))
        end
    end)
  end

  # A candidate that will not take this user is simply not a match: try the
  # next one, and fall through to creating a lobby if none of them will.
  #
  # Only `:full` moved on before, so a game rejecting one candidate in
  # `before_lobby_join` — the callback that owns "may this user join THIS
  # lobby", e.g. because that lobby is already mid-match — failed the whole
  # quick join and handed the player an error where a fresh lobby was the
  # obvious answer.
  defp attempt_quick_join(user, lobby) do
    case do_join(user.id, lobby, %{}) do
      {:ok, _} -> {:halt, {:ok, lobby}}
      {:error, :full} -> {:cont, {:none, []}}
      {:error, {:hook_rejected, _reason}} -> {:cont, {:none, []}}
      other -> {:halt, other}
    end
  end

  # `String.to_integer/1` raises on anything non-numeric, and these values come
  # straight from query strings and request bodies — so `?min_users=abc` was a
  # 500 rather than a validation error. Returns nil for unparseable input, which
  # every caller reads as "no filter" / "not supplied".
  defp to_int_or_nil(value) when is_integer(value), do: value

  defp to_int_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_int_or_nil(_value), do: nil
end
