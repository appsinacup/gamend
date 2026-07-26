defmodule GameServer.Lobbies do
  @moduledoc ~S"""
  Context module for lobby management: creating, updating, listing and searching lobbies.
  
  This module contains the core domain operations; more advanced membership and
  permission logic will be added in follow-up tasks.
  
  ## Usage
  
      # Create a lobby (returns {:ok, lobby} | {:error, changeset})
      {:ok, lobby} = GameServer.Lobbies.create_lobby(%{name: "fun-room", title: "Fun Room", host_id: host_id})
  
      # List public lobbies (paginated/filterable)
      lobbies = GameServer.Lobbies.list_lobbies(%{}, page: 1, page_size: 25)
  
      # Join and leave
      {:ok, user} = GameServer.Lobbies.join_lobby(user, lobby.id)
      {:ok, _} = GameServer.Lobbies.leave_lobby(user)
  
      # Get current lobby members
      members = GameServer.Lobbies.get_lobby_members(lobby)
  
      # Subscribe to global or per-lobby events
      :ok = GameServer.Lobbies.subscribe_lobbies()
      :ok = GameServer.Lobbies.subscribe_lobby(lobby.id)
  
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
  The actual implementation runs on the GameServer.
  """



  @doc ~S"""
    Broadcast a member presence event (online/offline) to a lobby's PubSub topic.
  """
  @spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
  def broadcast_member_presence(_lobby_id, _event) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Lobbies.broadcast_member_presence/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Check if a user can edit a lobby: the host of a host-managed lobby, nobody
    else. Hostless lobbies have no editor — see `update_lobby_by_host/3`.
    
  """
  @spec can_edit_lobby?(GameServer.Accounts.User.t() | nil, GameServer.Lobbies.Lobby.t() | nil) ::
  boolean()
  def can_edit_lobby?(_user, _lobby) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        false

      _ ->
        raise "GameServer.Lobbies.can_edit_lobby?/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Check if a user can view a lobby's details.
    Users can view any lobby they can see in the list.
    
  """
  @spec can_view_lobby?(GameServer.Accounts.User.t() | nil, GameServer.Lobbies.Lobby.t() | nil) ::
  boolean()
  def can_view_lobby?(_user, _lobby) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        false

      _ ->
        raise "GameServer.Lobbies.can_view_lobby?/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec change_lobby(GameServer.Lobbies.Lobby.t()) :: Ecto.Changeset.t()
  def change_lobby(_lobby) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Lobbies.change_lobby/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec change_lobby(GameServer.Lobbies.Lobby.t(), map()) :: Ecto.Changeset.t()
  def change_lobby(_lobby, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Lobbies.change_lobby/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Returns the count of hidden lobbies.
    
  """
  @spec count_hidden_lobbies() :: non_neg_integer()
  def count_hidden_lobbies() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Lobbies.count_hidden_lobbies/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Returns the count of hostless lobbies.
    
  """
  @spec count_hostless_lobbies() :: non_neg_integer()
  def count_hostless_lobbies() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Lobbies.count_hostless_lobbies/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count ALL lobbies matching filters. For admin pagination.
    
  """
  @spec count_list_all_lobbies() :: non_neg_integer()
  def count_list_all_lobbies() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Lobbies.count_list_all_lobbies/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count ALL lobbies matching filters. For admin pagination.
    
  """
  @spec count_list_all_lobbies(map()) :: non_neg_integer()
  def count_list_all_lobbies(_filters) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Lobbies.count_list_all_lobbies/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count lobbies matching filters (excludes hidden ones unless admin list used). If metadata filters are supplied, they will be applied after fetching.
  """
  @spec count_list_lobbies() :: non_neg_integer()
  def count_list_lobbies() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Lobbies.count_list_lobbies/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count lobbies matching filters (excludes hidden ones unless admin list used). If metadata filters are supplied, they will be applied after fetching.
  """
  @spec count_list_lobbies(map()) :: non_neg_integer()
  def count_list_lobbies(_filters) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Lobbies.count_list_lobbies/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Returns the count of locked lobbies.
    
  """
  @spec count_locked_lobbies() :: non_neg_integer()
  def count_locked_lobbies() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Lobbies.count_locked_lobbies/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Returns the count of lobbies with passwords.
    
  """
  @spec count_passworded_lobbies() :: non_neg_integer()
  def count_passworded_lobbies() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Lobbies.count_passworded_lobbies/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Creates a new lobby.
    
    ## Attributes
    
    See `t:GameServer.Types.lobby_create_attrs/0` for available fields.
    
  """
  @spec create_lobby() :: {:ok, GameServer.Lobbies.Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_lobby() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.create_lobby/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Creates a new lobby.
    
    ## Attributes
    
    See `t:GameServer.Types.lobby_create_attrs/0` for available fields.
    
  """
  @spec create_lobby(GameServer.Types.lobby_create_attrs()) ::
  {:ok, GameServer.Lobbies.Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_lobby(_attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.create_lobby/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec create_membership(%{lobby_id: Ecto.UUID.t(), user_id: Ecto.UUID.t()}) ::
  {:ok, GameServer.Accounts.User.t()} | {:error, :not_found | Ecto.Changeset.t() | term()}
  def create_membership(_attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Accounts.User{id: 0, email: "", display_name: nil, metadata: %{}, is_admin: false, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.create_membership/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec delete_lobby(GameServer.Lobbies.Lobby.t()) ::
  {:ok, GameServer.Lobbies.Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_lobby(_lobby) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.delete_lobby/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec delete_membership(GameServer.Accounts.User.t()) ::
  {:ok, GameServer.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def delete_membership(_user) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Accounts.User{id: 0, email: "", display_name: nil, metadata: %{}, is_admin: false, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.delete_membership/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_lobby(Ecto.UUID.t()) :: GameServer.Lobbies.Lobby.t() | nil
  def get_lobby(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Lobbies.get_lobby/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_lobby!(Ecto.UUID.t()) :: GameServer.Lobbies.Lobby.t()
  def get_lobby!(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Lobbies.get_lobby!/1 is a stub - only available at runtime on GameServer"
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
  @spec get_lobby_members(GameServer.Lobbies.Lobby.t() | Ecto.UUID.t()) :: [GameServer.Accounts.User.t()]
  def get_lobby_members(_lobby_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.get_lobby_members/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Join a user to a lobby.
    
    ## Options
    
      * `:password` - password for a password-protected lobby
      * `:bypass_lock` - when `true`, join succeeds even if the lobby is locked.
        Only set this from trusted server-side code; the HTTP and channel
        surfaces never pass it, so players cannot unlock a lobby themselves.
    
    Returns `{:ok, user}` with the updated user, or `{:error, reason}` where
    reason is one of `:already_in_lobby`, `:locked`, `:full`, `:blocked`,
    `:password_required`, `:invalid_password`, `:invalid_lobby`.
    
  """
  @spec join_lobby(GameServer.Accounts.User.t(), GameServer.Lobbies.Lobby.t() | Ecto.UUID.t()) ::
  {:ok, GameServer.Accounts.User.t()} | {:error, term()}
  def join_lobby(_user, _lobby_arg) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Accounts.User{id: 0, email: "", display_name: nil, metadata: %{}, is_admin: false, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.join_lobby/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Join a user to a lobby.
    
    ## Options
    
      * `:password` - password for a password-protected lobby
      * `:bypass_lock` - when `true`, join succeeds even if the lobby is locked.
        Only set this from trusted server-side code; the HTTP and channel
        surfaces never pass it, so players cannot unlock a lobby themselves.
    
    Returns `{:ok, user}` with the updated user, or `{:error, reason}` where
    reason is one of `:already_in_lobby`, `:locked`, `:full`, `:blocked`,
    `:password_required`, `:invalid_password`, `:invalid_lobby`.
    
  """
  @spec join_lobby(
  GameServer.Accounts.User.t(),
  GameServer.Lobbies.Lobby.t() | Ecto.UUID.t(),
  map() | keyword()
) :: {:ok, GameServer.Accounts.User.t()} | {:error, term()}
  def join_lobby(_user, _lobby_arg, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Accounts.User{id: 0, email: "", display_name: nil, metadata: %{}, is_admin: false, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.join_lobby/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Kick a user from a lobby. Only the host can kick users.
    Returns {:ok, user} on success, {:error, reason} on failure.
    
  """
  @spec kick_user(
  GameServer.Accounts.User.t(),
  GameServer.Lobbies.Lobby.t(),
  GameServer.Accounts.User.t()
) :: {:ok, GameServer.Accounts.User.t()} | {:error, term()}
  def kick_user(_host, _lobby, _target) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Accounts.User{id: 0, email: "", display_name: nil, metadata: %{}, is_admin: false, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.kick_user/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec leave_lobby(GameServer.Accounts.User.t()) :: {:ok, term()} | {:error, term()}
  def leave_lobby(_user) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Lobbies.leave_lobby/1 is a stub - only available at runtime on GameServer"
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
  @spec list_all_lobbies() :: [GameServer.Lobbies.Lobby.t()]
  def list_all_lobbies() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.list_all_lobbies/0 is a stub - only available at runtime on GameServer"
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
  @spec list_all_lobbies(map()) :: [GameServer.Lobbies.Lobby.t()]
  def list_all_lobbies(_filters) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.list_all_lobbies/1 is a stub - only available at runtime on GameServer"
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
  @spec list_all_lobbies(map(), GameServer.Types.pagination_opts()) :: [GameServer.Lobbies.Lobby.t()]
  def list_all_lobbies(_filters, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.list_all_lobbies/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List lobbies. Accepts optional search filters.
    
    ## Filters
    
      * `:title` - Filter by title (partial match)
      * `:is_passworded` - boolean or string 'true'/'false' (omit for any)
      * `:is_locked` - boolean or string 'true'/'false' (omit for any)
      * `:state` - lifecycle state (see `GameServer.Lobbies.States`)
      * `:min_users` - Filter lobbies with max_users >= value
      * `:max_users` - Filter lobbies with max_users <= value
      * `:metadata_key` - Filter by metadata key
      * `:metadata_value` - Filter by metadata value (requires metadata_key)
    
    ## Options
    
    See `t:GameServer.Types.lobby_list_opts/0` for available options.
    
  """
  @spec list_lobbies() :: [GameServer.Lobbies.Lobby.t()]
  def list_lobbies() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.list_lobbies/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List lobbies. Accepts optional search filters.
    
    ## Filters
    
      * `:title` - Filter by title (partial match)
      * `:is_passworded` - boolean or string 'true'/'false' (omit for any)
      * `:is_locked` - boolean or string 'true'/'false' (omit for any)
      * `:state` - lifecycle state (see `GameServer.Lobbies.States`)
      * `:min_users` - Filter lobbies with max_users >= value
      * `:max_users` - Filter lobbies with max_users <= value
      * `:metadata_key` - Filter by metadata key
      * `:metadata_value` - Filter by metadata value (requires metadata_key)
    
    ## Options
    
    See `t:GameServer.Types.lobby_list_opts/0` for available options.
    
  """
  @spec list_lobbies(map()) :: [GameServer.Lobbies.Lobby.t()]
  def list_lobbies(_filters) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.list_lobbies/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List lobbies. Accepts optional search filters.
    
    ## Filters
    
      * `:title` - Filter by title (partial match)
      * `:is_passworded` - boolean or string 'true'/'false' (omit for any)
      * `:is_locked` - boolean or string 'true'/'false' (omit for any)
      * `:state` - lifecycle state (see `GameServer.Lobbies.States`)
      * `:min_users` - Filter lobbies with max_users >= value
      * `:max_users` - Filter lobbies with max_users <= value
      * `:metadata_key` - Filter by metadata key
      * `:metadata_value` - Filter by metadata value (requires metadata_key)
    
    ## Options
    
    See `t:GameServer.Types.lobby_list_opts/0` for available options.
    
  """
  @spec list_lobbies(map(), GameServer.Types.lobby_list_opts()) :: [GameServer.Lobbies.Lobby.t()]
  def list_lobbies(_filters, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.list_lobbies/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List lobbies visible to a specific user.
    Includes the user's own lobby even if it's hidden.
    
  """
  @spec list_lobbies_for_user(GameServer.Accounts.User.t() | nil) :: [GameServer.Lobbies.Lobby.t()]
  def list_lobbies_for_user(_user) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.list_lobbies_for_user/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List lobbies visible to a specific user.
    Includes the user's own lobby even if it's hidden.
    
  """
  @spec list_lobbies_for_user(GameServer.Accounts.User.t() | nil, map()) :: [GameServer.Lobbies.Lobby.t()]
  def list_lobbies_for_user(_user, _filters) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.list_lobbies_for_user/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List lobbies visible to a specific user.
    Includes the user's own lobby even if it's hidden.
    
  """
  @spec list_lobbies_for_user(
  GameServer.Accounts.User.t() | nil,
  map(),
  GameServer.Types.lobby_list_opts()
) :: [GameServer.Lobbies.Lobby.t()]
  def list_lobbies_for_user(_user, _filters, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.list_lobbies_for_user/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_memberships_for_lobby(Ecto.UUID.t()) :: [GameServer.Accounts.User.t()]
  def list_memberships_for_lobby(_lobby_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Lobbies.list_memberships_for_lobby/1 is a stub - only available at runtime on GameServer"
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
  @spec quick_join(GameServer.Accounts.User.t()) ::
  {:ok, GameServer.Lobbies.Lobby.t()} | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  def quick_join(_user) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.quick_join/1 is a stub - only available at runtime on GameServer"
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
  @spec quick_join(GameServer.Accounts.User.t(), String.t() | nil) ::
  {:ok, GameServer.Lobbies.Lobby.t()} | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  def quick_join(_user, _title) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.quick_join/2 is a stub - only available at runtime on GameServer"
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
  @spec quick_join(GameServer.Accounts.User.t(), String.t() | nil, integer() | nil) ::
  {:ok, GameServer.Lobbies.Lobby.t()} | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  def quick_join(_user, _title, _max_users) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.quick_join/3 is a stub - only available at runtime on GameServer"
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
  @spec quick_join(GameServer.Accounts.User.t(), String.t() | nil, integer() | nil, map()) ::
  {:ok, GameServer.Lobbies.Lobby.t()} | {:error, :already_in_lobby | Ecto.Changeset.t() | term()}
  def quick_join(_user, _title, _max_users, _metadata) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.quick_join/4 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Check if a lobby can be spectated (watched by non-members).
    
    A lobby is spectatable if it is not hidden and not locked.
    
  """
  @spec spectatable?(GameServer.Lobbies.Lobby.t()) :: boolean()
  def spectatable?(_lobby) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        false

      _ ->
        raise "GameServer.Lobbies.spectatable?/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Subscribe to global lobby events (lobby created, updated, deleted).
    
  """
  @spec subscribe_lobbies() :: :ok | {:error, term()}
  def subscribe_lobbies() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Lobbies.subscribe_lobbies/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Subscribe to a specific lobby's events (membership changes, updates).
    
  """
  @spec subscribe_lobby(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_lobby(_lobby_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Lobbies.subscribe_lobby/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Move a lobby to `state` (see `GameServer.Lobbies.States`).
    
    The only writer of `state`/`state_changed_at` — the columns are not castable,
    so a generic `update_lobby/2` can never move a lobby's state.
    
    The vocabulary is the game's: core only requires a sane string (non-empty,
    ≤ 64 bytes) and `before_lobby_state_change` enforces
    whatever words and ordering the game cares about. A same-state call is
    a no-op (so at-least-once hook/job retries are safe) and does not re-fire
    hooks. `after_lobby_state_changed` observes post-commit.
    
    Returns `{:ok, lobby}`, `{:error, :invalid_state}` or
    `{:error, {:hook_rejected, reason}}`.
    
  """
  @spec transition_state(GameServer.Lobbies.Lobby.t(), String.t(), keyword()) ::
  {:ok, GameServer.Lobbies.Lobby.t()}
  | {:error, :invalid_state | {:hook_rejected, term()} | term()}
  def transition_state(_lobby, _state, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Lobbies.transition_state/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Player-initiated state change, subject to lobby ownership.
    
    Allowed only for the **host of a host-managed lobby** — the host already
    renames, locks, resizes and kicks, so `state` is no more powerful than what
    they hold, and "press Start" is a normal party-game action. **Hostless**
    lobbies (matchmaking's) belong to nobody, so no player may move them: use
    `transition_state/3` from server-side hooks instead.
    
  """
  @spec transition_state_by_host(GameServer.Accounts.User.t(), GameServer.Lobbies.Lobby.t(), String.t()) ::
  {:ok, GameServer.Lobbies.Lobby.t()} | {:error, :not_host | :invalid_state | term()}
  def transition_state_by_host(_user, _lobby, _state) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.transition_state_by_host/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Unsubscribe from a specific lobby's events.
    
  """
  @spec unsubscribe_lobby(Ecto.UUID.t()) :: :ok
  def unsubscribe_lobby(_lobby_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Lobbies.unsubscribe_lobby/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Updates an existing lobby.
    
    ## Attributes
    
    See `t:GameServer.Types.lobby_update_attrs/0` for available fields.
    
  """
  @spec update_lobby(GameServer.Lobbies.Lobby.t(), GameServer.Types.lobby_update_attrs()) ::
  {:ok, GameServer.Lobbies.Lobby.t()} | {:error, Ecto.Changeset.t() | term()}
  def update_lobby(_lobby, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Lobbies.Lobby{id: 0, title: "", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Lobbies.update_lobby/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Player-initiated lobby update, subject to lobby ownership.
    
    Allowed only for the **host of a host-managed lobby**. **Hostless** lobbies
    (matchmaking's) belong to nobody, so no player may edit them — a member
    could otherwise rewrite `metadata`, `max_users`, `password_hash` and the
    visibility flags of a ranked match they merely happen to be in. Server-side
    code (hooks, jobs, matchmaking, admin) uses `update_lobby/2` instead.
    
  """
  @spec update_lobby_by_host(
  GameServer.Accounts.User.t(),
  GameServer.Lobbies.Lobby.t(),
  GameServer.Types.lobby_update_attrs()
) ::
  {:ok, GameServer.Lobbies.Lobby.t()}
  | {:error, :not_host | :too_small | Ecto.Changeset.t() | term()}
  def update_lobby_by_host(_user, _lobby, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Lobbies.update_lobby_by_host/3 is a stub - only available at runtime on GameServer"
    end
  end

end
