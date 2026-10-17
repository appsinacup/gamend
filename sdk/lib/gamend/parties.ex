defmodule Gamend.Parties do
  @moduledoc ~S"""
  Context module for party management.

  A party is a pre-lobby grouping mechanism. Players form a party before
  creating or joining a lobby together.

  ## Usage

      # Create a party (user becomes leader and first member)
      {:ok, party} = Gamend.Parties.create_party(user, %{max_size: 4})

      # Leader invites a friend or shared-group member by user_id
      {:ok, _notification} = Gamend.Parties.invite_to_party(leader, target_user_id)

      # Target accepts the invite
      {:ok, party} = Gamend.Parties.accept_party_invite(target, party_id)

      # Or declines
      :ok = Gamend.Parties.decline_party_invite(target, party_id)

      # Leave a party (a leader hands it over; the last member out disbands it)
      {:ok, _} = Gamend.Parties.leave_party(user)

      # Party leader creates a lobby — all members join atomically
      {:ok, lobby} = Gamend.Parties.create_lobby_with_party(user, lobby_attrs)

      # Party leader joins an existing lobby — all members join atomically
      {:ok, lobby} = Gamend.Parties.join_lobby_with_party(user, lobby_id, opts)

  ## PubSub Events

  This module broadcasts the following events:

  - `"party:<party_id>"` topic:
    - `{:party_member_joined, party_id, user_id}`
    - `{:party_member_left, party_id, user_id}`
    - `{:party_disbanded, party_id}`
    - `{:party_updated, party}`


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    Accept a party invite. Joins the party and marks the invite as accepted.
    
    If the user is already in another party, they automatically leave it first
    (disbanding if they are the leader).
    
    Returns `{:error, :no_invite}` if no pending invite exists for that party.
    
  """
  @spec accept_party_invite(Gamend.Accounts.User.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Parties.Party.t()} | {:error, atom()}
  def accept_party_invite(_user, _party_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Parties.accept_party_invite/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Admin delete of a party. Clears all members' party_id and deletes the party.
  """
  @spec admin_delete_party(Ecto.UUID.t()) :: {:ok, Gamend.Parties.Party.t()} | {:error, term()}
  def admin_delete_party(_party_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Parties.admin_delete_party/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Admin update of a party (max_size, metadata).
  """
  @spec admin_update_party(Gamend.Parties.Party.t(), map()) ::
          {:ok, Gamend.Parties.Party.t()} | {:error, Ecto.Changeset.t()}
  def admin_update_party(_party, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Parties.admin_update_party/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Broadcast a member presence event (online/offline) to a party's PubSub topic.
  """
  @spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
  def broadcast_member_presence(_party_id, _event) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Parties.broadcast_member_presence/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether `user` holds authority over `party` — its leader, nobody else.
    
    Subject first, resource second, like every other `can_*?` predicate (see
    `Gamend.Policy`). The party takes a struct or a bare id; passing the user's
    own `party_id` is the common case.
    
  """
  @spec can_manage_party?(
          Gamend.Accounts.User.t() | nil,
          Gamend.Parties.Party.t() | Ecto.UUID.t() | nil
        ) ::
          boolean()
  def can_manage_party?(_user, _party_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Parties.can_manage_party?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Cancel a previously sent party invite. Only the original sender (leader) can cancel.
    
  """
  @spec cancel_party_invite(Gamend.Accounts.User.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def cancel_party_invite(_leader, _target_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Parties.cancel_party_invite/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Return a changeset for the given party (for edit forms).
  """
  @spec change_party(Gamend.Parties.Party.t()) :: Ecto.Changeset.t()
  def change_party(_party) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Parties.change_party/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count all parties matching the given filters.
  """
  @spec count_all_parties(map()) :: non_neg_integer()
  def count_all_parties(_filters \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Parties.count_all_parties/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count total members across all parties.
  """
  @spec count_all_party_members() :: non_neg_integer()
  def count_all_party_members() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Parties.count_all_party_members/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    How many pending party invites the user has, for paging.
  """
  @spec count_party_invitations(Gamend.Accounts.User.t()) :: non_neg_integer()
  def count_party_invitations(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Parties.count_party_invitations/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count members in a party.
  """
  @spec count_party_members(Ecto.UUID.t()) :: non_neg_integer()
  def count_party_members(_party_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Parties.count_party_members/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    How many pending party invites the leader has sent, for paging.
  """
  @spec count_sent_party_invitations(Gamend.Accounts.User.t()) :: non_neg_integer()
  def count_sent_party_invitations(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Parties.count_sent_party_invitations/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The party leader creates a new lobby, and all party members join it
    atomically. The party is kept intact.
    
    The lobby's `max_users` must be >= party member count.
    
  """
  @spec create_lobby_with_party(Gamend.Accounts.User.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def create_lobby_with_party(_user, _lobby_attrs \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Parties.create_lobby_with_party/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Create a new party. The user becomes the leader and first member.
    
    Returns `{:error, :already_in_party}` if the user is already in a party.
    
  """
  @spec create_party(Gamend.Accounts.User.t(), map()) ::
          {:ok, Gamend.Parties.Party.t()} | {:error, term()}
  def create_party(_user, _attrs \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Parties.create_party/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Decline a party invite. Marks the invite as declined.
    
  """
  @spec decline_party_invite(Gamend.Accounts.User.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def decline_party_invite(_user, _party_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Parties.decline_party_invite/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Disband a party outright: clears every member's `party_id`, cancels pending
    invites, deletes the row, and broadcasts as a leader-initiated disband would.
    
    For callers acting on the party rather than on behalf of a member — the
    retention sweep for parties everyone has abandoned. Members leaving is
    `leave_party/1`.
    
  """
  @spec disband(Gamend.Parties.Party.t()) :: {:ok, term()} | {:error, term()}
  def disband(_party) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Parties.disband/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a party by ID. Returns nil if not found.
  """
  @spec get_party(Ecto.UUID.t()) :: Gamend.Parties.Party.t() | nil
  def get_party(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Parties.get_party/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a party by ID. Raises if not found.
  """
  @spec get_party!(Ecto.UUID.t()) :: Gamend.Parties.Party.t()
  def get_party!(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Parties.get_party!/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get all members of a party.
  """
  @spec get_party_members(Gamend.Parties.Party.t() | Ecto.UUID.t()) :: [Gamend.Accounts.User.t()]
  def get_party_members(_party_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Parties.get_party_members/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get the party the user is currently in, or nil.
  """
  @spec get_user_party(Gamend.Accounts.User.t()) :: Gamend.Parties.Party.t() | nil
  def get_user_party(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Parties.get_user_party/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Invite a user to join the party. Only the party leader may invite.
    
    The target user must be a friend of the leader, or share at least one group
    with the leader. A `PartyInvite` record is created and an informational
    notification is sent. The invite is independent of the notification —
    deleting notifications does not affect pending invites.
    
    Returns `{:error, :not_in_party}` if the caller is not in a party.
    Returns `{:error, :not_leader}` if the caller is not the party leader.
    Returns `{:error, :not_connected}` if the target is not a friend or shared group member.
    If a pending invite already exists, returns `{:ok, existing_invite}` (no-op).
    
  """
  @spec invite_to_party(Gamend.Accounts.User.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Parties.PartyInvite.t()} | {:error, atom()}
  def invite_to_party(_leader, _target_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Parties.invite_to_party/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The party leader joins an existing lobby, and all party members join it
    atomically. The party is kept intact.
    
    The lobby must have enough free slots for the entire party.
    
  """
  @spec join_lobby_with_party(Gamend.Accounts.User.t(), Ecto.UUID.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def join_lobby_with_party(_user, _lobby_id, _opts \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Parties.join_lobby_with_party/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Kick a member from the party. Only the leader can kick.
    
  """
  @spec kick_member(Gamend.Accounts.User.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, term()}
  def kick_member(_leader, _target_user_id) do
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
        raise "Gamend.Parties.kick_member/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Leave the current party.
    
    A leader leaving HANDS THE PARTY OVER to the longest-present remaining member,
    the way a lobby migrates its host — the party outliving one player is the
    point of it. Regular members are simply removed, and whoever leaves last takes
    the party with them, since there is nobody to hand it to.
    
    To end a party outright rather than leave it, call `disband/1`.
    
  """
  @spec leave_party(Gamend.Accounts.User.t()) :: {:ok, :left | :disbanded} | {:error, term()}
  def leave_party(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Parties.leave_party/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List all parties with optional filters and pagination.
  """
  @spec list_all_parties(
          map(),
          keyword()
        ) :: [Gamend.Parties.Party.t()]
  def list_all_parties(_filters \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Parties.list_all_parties/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List pending party invites for the given user.
    
  """
  @spec list_party_invitations(
          Gamend.Accounts.User.t(),
          keyword()
        ) :: [map()]
  def list_party_invitations(_user, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Parties.list_party_invitations/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List pending party invites sent by the given leader.
    
    Returns invitations the leader has sent that have not yet been accepted or declined.
    
  """
  @spec list_sent_party_invitations(
          Gamend.Accounts.User.t(),
          keyword()
        ) :: [map()]
  def list_sent_party_invitations(_leader, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Parties.list_sent_party_invitations/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The party leader quick-joins a lobby with the entire party.
    
    Searches for an open lobby that matches the given criteria (title,
    max_users, metadata) and has enough space for the whole party. If no
    matching lobby is found, creates a new one and joins all party members
    atomically.
    
    Returns `{:ok, lobby}` on success.
    
  """
  @spec quick_join_with_party(Gamend.Accounts.User.t(), map()) ::
          {:ok, Gamend.Lobbies.Lobby.t()} | {:error, term()}
  def quick_join_with_party(_user, _params \\ %{}) do
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
        raise "Gamend.Parties.quick_join_with_party/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Aggregate party counts for the public stats endpoint.
    
    Membership is a user column (`users.party_id`, indexed), so both numbers are
    derived counts rather than a maintained size.
    
  """
  @spec stats() :: %{parties_active: non_neg_integer(), players_in_parties: non_neg_integer()}
  def stats() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Parties.stats/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to all party events (create/delete).
  """
  @spec subscribe_parties() :: :ok | {:error, term()}
  def subscribe_parties() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Parties.subscribe_parties/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to events for a specific party.
  """
  @spec subscribe_party(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_party(_party_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Parties.subscribe_party/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unsubscribe from a party's events.
  """
  @spec unsubscribe_party(Ecto.UUID.t()) :: :ok
  def unsubscribe_party(_party_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Parties.unsubscribe_party/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Update party settings. Only the leader can update.
    
  """
  @spec update_party(Gamend.Accounts.User.t(), map()) ::
          {:ok, Gamend.Parties.Party.t()} | {:error, term()}
  def update_party(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Parties.update_party/2 is a stub - only available at runtime on Gamend"
    end
  end
end
