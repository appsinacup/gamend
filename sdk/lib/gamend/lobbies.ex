defmodule Gamend.Lobbies do
  @moduledoc ~S"""
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


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    Broadcast a member presence event (online/offline) to a lobby's PubSub topic.
  """
  @spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
  def broadcast_member_presence(_lobby_id, _event) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Lobbies.broadcast_member_presence/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec can_manage_lobby?(Gamend.Accounts.User.t() | nil, Gamend.Lobbies.Lobby.t() | nil) ::
          boolean()
  def can_manage_lobby?(_user, _lobby) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Lobbies.can_manage_lobby?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether `user` may read `lobby`'s details.
    
    Hiding a lobby takes it out of public listings; it does not hide it from the
    people already inside. Those are its members and its signaling host — which
    for a hostless matchmaking lobby is the game server running the room rather
    than any player, so it is never a member. Everyone else sees only lobbies
    that are not hidden.
    
  """
  @spec can_view_lobby?(Gamend.Accounts.User.t() | nil, Gamend.Lobbies.Lobby.t() | nil) ::
          boolean()
  def can_view_lobby?(_user, _lobby) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Lobbies.can_view_lobby?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec change_lobby(Gamend.Lobbies.Lobby.t()) :: Ecto.Changeset.t()
  def change_lobby(_lobby) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Lobbies.change_lobby/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec change_lobby(Gamend.Lobbies.Lobby.t(), map()) :: Ecto.Changeset.t()
  def change_lobby(_lobby, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Lobbies.change_lobby/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns the count of hidden lobbies.
    
  """
  @spec count_hidden_lobbies() :: non_neg_integer()
  def count_hidden_lobbies() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Lobbies.count_hidden_lobbies/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns the count of hostless lobbies.
    
  """
  @spec count_hostless_lobbies() :: non_neg_integer()
  def count_hostless_lobbies() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Lobbies.count_hostless_lobbies/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count ALL lobbies matching filters. For admin pagination.
    
  """
  @spec count_list_all_lobbies() :: non_neg_integer()
  def count_list_all_lobbies() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Lobbies.count_list_all_lobbies/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count ALL lobbies matching filters. For admin pagination.
    
  """
  @spec count_list_all_lobbies(map()) :: non_neg_integer()
  def count_list_all_lobbies(_filters) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Lobbies.count_list_all_lobbies/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count lobbies matching filters (excludes hidden ones unless admin list used). If metadata filters are supplied, they will be applied after fetching.
  """
  @spec count_list_lobbies() :: non_neg_integer()
  def count_list_lobbies() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Lobbies.count_list_lobbies/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count lobbies matching filters (excludes hidden ones unless admin list used). If metadata filters are supplied, they will be applied after fetching.
  """
  @spec count_list_lobbies(map()) :: non_neg_integer()
  def count_list_lobbies(_filters) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Lobbies.count_list_lobbies/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns the count of locked lobbies.
    
  """
  @spec count_locked_lobbies() :: non_neg_integer()
  def count_locked_lobbies() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Lobbies.count_locked_lobbies/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns the count of lobbies with passwords.
    
  """
  @spec count_passworded_lobbies() :: non_neg_integer()
  def count_passworded_lobbies() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Lobbies.count_passworded_lobbies/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Creates a new lobby.
    
    ## Attributes
    
    See `t:Gamend.Types.lobby_create_attrs/0` for available fields.
    
  """
  @spec create_lobby() :: {:ok, Gamend.Lobbies.Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_lobby() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.create_lobby/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Creates a new lobby.
    
    ## Attributes
    
    See `t:Gamend.Types.lobby_create_attrs/0` for available fields.
    
  """
  @spec create_lobby(Gamend.Types.lobby_create_attrs()) ::
          {:ok, Gamend.Lobbies.Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_lobby(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.create_lobby/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec create_membership(%{lobby_id: Ecto.UUID.t(), user_id: Ecto.UUID.t()}) ::
          {:ok, Gamend.Accounts.User.t()}
          | {:error, :not_found | :already_in_lobby | Ecto.Changeset.t() | term()}
  def create_membership(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Lobbies.create_membership/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec delete_lobby(Gamend.Lobbies.Lobby.t()) ::
          {:ok, Gamend.Lobbies.Lobby.t()} | {:error, :not_found | {:hook_rejected, term()}}
  def delete_lobby(_lobby) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.delete_lobby/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec delete_membership(Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, :not_in_lobby}
  def delete_membership(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.delete_membership/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec get_lobby(Ecto.UUID.t()) :: Gamend.Lobbies.Lobby.t() | nil
  def get_lobby(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Lobbies.Lobby{
            id: 0,
            title: "",
            host_id: nil,
            hostless: false,
            max_users: 0,
            is_hidden: false,
            is_locked: false,
            metadata: %{},
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Lobbies.get_lobby/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec get_lobby!(Ecto.UUID.t()) :: Gamend.Lobbies.Lobby.t()
  def get_lobby!(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Lobbies.get_lobby!/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets all users currently in a lobby.
    
    Returns a list of User structs.
    
    ## Examples
    
        iex> get_lobby_members(lobby)
        [%User{}, %User{}]
    
        iex> get_lobby_members(lobby_id)
        [%User{}]
    
    
  """
  @spec get_lobby_members(Gamend.Lobbies.Lobby.t() | Ecto.UUID.t()) :: [Gamend.Accounts.User.t()]
  def get_lobby_members(_lobby_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.get_lobby_members/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec join_lobby(Gamend.Accounts.User.t(), Gamend.Lobbies.Lobby.t() | Ecto.UUID.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, term()}
  def join_lobby(_user, _lobby_arg) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.join_lobby/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec join_lobby(
          Gamend.Accounts.User.t(),
          Gamend.Lobbies.Lobby.t() | Ecto.UUID.t(),
          map() | keyword()
        ) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, term()}
  def join_lobby(_user, _lobby_arg, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.join_lobby/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Kick a user from a lobby. Only the lobby's authority can, per
    `can_manage_lobby?/2`.
    
    Returns {:ok, user} on success, {:error, reason} on failure.
    
  """
  @spec kick_user(Gamend.Accounts.User.t(), Gamend.Lobbies.Lobby.t(), Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, term()}
  def kick_user(_host, _lobby, _target) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.kick_user/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec leave_lobby(Gamend.Accounts.User.t()) :: {:ok, term()} | {:error, term()}
  def leave_lobby(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Lobbies.leave_lobby/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec list_all_lobbies() :: [Gamend.Lobbies.Lobby.t()]
  def list_all_lobbies() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.list_all_lobbies/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec list_all_lobbies(map()) :: [Gamend.Lobbies.Lobby.t()]
  def list_all_lobbies(_filters) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.list_all_lobbies/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec list_all_lobbies(map(), Gamend.Types.pagination_opts()) :: [Gamend.Lobbies.Lobby.t()]
  def list_all_lobbies(_filters, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.list_all_lobbies/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec list_lobbies() :: [Gamend.Lobbies.Lobby.t()]
  def list_lobbies() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.list_lobbies/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec list_lobbies(map()) :: [Gamend.Lobbies.Lobby.t()]
  def list_lobbies(_filters) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.list_lobbies/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec list_lobbies(map(), Gamend.Types.lobby_list_opts()) :: [Gamend.Lobbies.Lobby.t()]
  def list_lobbies(_filters, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.list_lobbies/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List lobbies visible to a specific user.
    Includes the user's own lobby even if it's hidden.
    
  """
  @spec list_lobbies_for_user(Gamend.Accounts.User.t() | nil) :: [Gamend.Lobbies.Lobby.t()]
  def list_lobbies_for_user(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.list_lobbies_for_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List lobbies visible to a specific user.
    Includes the user's own lobby even if it's hidden.
    
  """
  @spec list_lobbies_for_user(Gamend.Accounts.User.t() | nil, map()) :: [Gamend.Lobbies.Lobby.t()]
  def list_lobbies_for_user(_user, _filters) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.list_lobbies_for_user/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List lobbies visible to a specific user.
    Includes the user's own lobby even if it's hidden.
    
  """
  @spec list_lobbies_for_user(
          Gamend.Accounts.User.t() | nil,
          map(),
          Gamend.Types.lobby_list_opts()
        ) :: [
          Gamend.Lobbies.Lobby.t()
        ]
  def list_lobbies_for_user(_user, _filters, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.list_lobbies_for_user/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec list_memberships_for_lobby(Ecto.UUID.t()) :: [Gamend.Accounts.User.t()]
  def list_memberships_for_lobby(_lobby_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.list_memberships_for_lobby/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec merge_metadata(Gamend.Lobbies.Lobby.t(), map()) ::
          {:ok, Gamend.Lobbies.Lobby.t()} | {:error, term()}
  def merge_metadata(_lobby, _patch) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.merge_metadata/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Attempt to find an open lobby matching the given criteria and join it, or
    create a new lobby if none matches.
    
    Signature: quick_join(user, title \ nil, max_users \ nil, metadata \ %{})
    
    - If the user is already in a lobby returns {:error, :already_in_lobby}
    - On successful join or creation returns {:ok, lobby}
    - Propagates errors from join or create flows
    
  """
  @spec quick_join(Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Lobbies.Lobby.t()}
          | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  def quick_join(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.quick_join/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Attempt to find an open lobby matching the given criteria and join it, or
    create a new lobby if none matches.
    
    Signature: quick_join(user, title \ nil, max_users \ nil, metadata \ %{})
    
    - If the user is already in a lobby returns {:error, :already_in_lobby}
    - On successful join or creation returns {:ok, lobby}
    - Propagates errors from join or create flows
    
  """
  @spec quick_join(Gamend.Accounts.User.t(), String.t() | nil) ::
          {:ok, Gamend.Lobbies.Lobby.t()}
          | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  def quick_join(_user, _title) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.quick_join/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Attempt to find an open lobby matching the given criteria and join it, or
    create a new lobby if none matches.
    
    Signature: quick_join(user, title \ nil, max_users \ nil, metadata \ %{})
    
    - If the user is already in a lobby returns {:error, :already_in_lobby}
    - On successful join or creation returns {:ok, lobby}
    - Propagates errors from join or create flows
    
  """
  @spec quick_join(Gamend.Accounts.User.t(), String.t() | nil, integer() | nil) ::
          {:ok, Gamend.Lobbies.Lobby.t()}
          | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  def quick_join(_user, _title, _max_users) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.quick_join/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Attempt to find an open lobby matching the given criteria and join it, or
    create a new lobby if none matches.
    
    Signature: quick_join(user, title \ nil, max_users \ nil, metadata \ %{})
    
    - If the user is already in a lobby returns {:error, :already_in_lobby}
    - On successful join or creation returns {:ok, lobby}
    - Propagates errors from join or create flows
    
  """
  @spec quick_join(Gamend.Accounts.User.t(), String.t() | nil, integer() | nil, map()) ::
          {:ok, Gamend.Lobbies.Lobby.t()}
          | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  def quick_join(_user, _title, _max_users, _metadata) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.quick_join/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Check if a lobby can be spectated (watched by non-members).
    
    A lobby is spectatable if it is not hidden, not locked and not
    password-protected.
    
    The password clause matters because spectating is not a read-only peek: the
    channel subscribes the spectator to lobby chat and hands them an after-join
    payload built with the full member list. The password gated the HTTP join and
    nothing on the channel, so it protected participation while leaving the
    conversation and the roster open to anyone who knew the lobby id.
    
  """
  @spec spectatable?(Gamend.Lobbies.Lobby.t()) :: boolean()
  def spectatable?(_lobby) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Lobbies.spectatable?/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Aggregate lobby counts for the public stats endpoint.
    
    Spectators live in Presence, keyed per lobby topic, and Presence cannot
    enumerate its own topics — so the lobby ids come from the table first. That
    makes the total one query plus an ETS read per lobby, which is why it sits
    inside the cached snapshot rather than being computed per request.
    
  """
  @spec stats() :: %{
          lobbies_total: non_neg_integer(),
          by_state: %{required(String.t()) => non_neg_integer()},
          spectators: non_neg_integer()
        }
  def stats() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Lobbies.stats/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to global lobby events (lobby created, updated, deleted).
    
  """
  @spec subscribe_lobbies() :: :ok | {:error, term()}
  def subscribe_lobbies() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Lobbies.subscribe_lobbies/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to a specific lobby's events (membership changes, updates).
    
  """
  @spec subscribe_lobby(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_lobby(_lobby_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Lobbies.subscribe_lobby/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Move a lobby to `state` (see `Gamend.Lobbies.States`).
    
    The only writer of `state`/`state_changed_at` — the columns are not castable,
    so a generic `update_lobby/2` can never move a lobby's state.
    
    The vocabulary is the game's: core only requires a sane string (non-empty,
    ≤ 64 bytes) and `before_lobby_state_change` enforces
    whatever words and ordering the game cares about. A same-state call is
    a no-op (so at-least-once hook/job retries are safe) and does not re-fire
    hooks. `after_lobby_state_changed` observes post-commit.
    
    Returns `{:ok, lobby}`, `{:error, :invalid_state}`,
    `{:error, {:hook_rejected, reason}}`, `{:error, :state_changed}` when
    another transition moved the lobby first (the hook approved a move out of a
    state it has left), or `{:error, :not_found}` when it was deleted.
    
  """
  @spec transition_state(Gamend.Lobbies.Lobby.t(), String.t(), keyword()) ::
          {:ok, Gamend.Lobbies.Lobby.t()}
          | {:error,
             :invalid_state | :state_changed | :not_found | {:hook_rejected, term()} | term()}
  def transition_state(_lobby, _state, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Lobbies.transition_state/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Client-initiated state change, subject to `can_manage_lobby?/2`.
    
    The lobby's authority already renames, locks, resizes and kicks, so `state`
    is no more powerful than what it holds, and "press Start" is a normal
    party-game action. A hostless matchmaking lobby with no pinned WebRTC host
    has no authority at all: move it with `transition_state/3` from server-side
    hooks instead.
    
  """
  @spec transition_state_by_host(Gamend.Accounts.User.t(), Gamend.Lobbies.Lobby.t(), String.t()) ::
          {:ok, Gamend.Lobbies.Lobby.t()} | {:error, :not_host | :invalid_state | term()}
  def transition_state_by_host(_user, _lobby, _state) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.transition_state_by_host/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unsubscribe from a specific lobby's events.
    
  """
  @spec unsubscribe_lobby(Ecto.UUID.t()) :: :ok
  def unsubscribe_lobby(_lobby_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Lobbies.unsubscribe_lobby/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Updates an existing lobby.
    
    ## Attributes
    
    See `t:Gamend.Types.lobby_update_attrs/0` for available fields.
    
  """
  @spec update_lobby(Gamend.Lobbies.Lobby.t(), Gamend.Types.lobby_update_attrs()) ::
          {:ok, Gamend.Lobbies.Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  def update_lobby(_lobby, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.update_lobby/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Client-initiated lobby update, subject to `can_manage_lobby?/2`.
    
    A hostless matchmaking lobby with no pinned WebRTC host has no authority, so
    none of its members may edit it — one could otherwise rewrite `metadata`,
    `max_users`, `password_hash` and the visibility flags of a ranked match it
    merely happens to be in. Server-side code (hooks, jobs, matchmaking, admin)
    uses `update_lobby/2` instead.
    
  """
  @spec update_lobby_by_host(
          Gamend.Accounts.User.t(),
          Gamend.Lobbies.Lobby.t(),
          Gamend.Types.lobby_update_attrs()
        ) ::
          {:ok, Gamend.Lobbies.Lobby.t()}
          | {:error, :not_host | :too_small | Ecto.Changeset.t() | term()}
  def update_lobby_by_host(_user, _lobby, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.update_lobby_by_host/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Ids of lobbies with WebRTC enabled — the signaling rooms that can exist.
  """
  @spec webrtc_enabled_lobby_ids() :: [Ecto.UUID.t()]
  def webrtc_enabled_lobby_ids() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Lobbies.webrtc_enabled_lobby_ids/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Writes the server-owned `webrtc_*` columns.
    
    Not castable through `update_lobby/2`, so a client `PATCH` cannot reach them.
    Go through `Gamend.Signaling.configure/2` rather than calling this.
    
  """
  @spec write_webrtc_config(Gamend.Lobbies.Lobby.t(), map()) ::
          {:ok, Gamend.Lobbies.Lobby.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def write_webrtc_config(_lobby, _changes) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Lobbies.Lobby{
           id: 0,
           title: "",
           host_id: nil,
           hostless: false,
           max_users: 0,
           is_hidden: false,
           is_locked: false,
           metadata: %{},
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Lobbies.write_webrtc_config/2 is a stub - only available at runtime on Gamend"
    end
  end
end
