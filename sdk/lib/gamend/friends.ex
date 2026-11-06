defmodule Gamend.Friends do
  @moduledoc ~S"""
  Friends context - handles friend requests and relationships.

  Basic semantics:
  - A single `friendships` row represents a directed request from requester -> target.
  - status: "pending" | "accepted" | "rejected" | "blocked"
  - When a user accepts a pending incoming request, that request becomes `accepted`.
    If a reverse pending request exists, it will be removed to avoid duplicate rows.
  - Listing friends returns the other user from rows with status `accepted` in either
    direction.

  ## Usage

      # Create a friend request (requester -> target)
      {:ok, friendship} = Gamend.Friends.create_request(requester_id, target_id)

      # Accept a pending incoming request (performed by the target)
      {:ok, accepted} = Gamend.Friends.accept_friend_request(friendship.id, %Gamend.Accounts.User{id: target_id})

      # List accepted friends for a user (paginated)
      friends = Gamend.Friends.list_friends_for_user(user_id, page: 1, page_size: 25)

      # Count accepted friends for a user
      count = Gamend.Friends.count_friends_for_user(user_id)

      # Remove a friendship (either direction)
      {:ok, _} = Gamend.Friends.remove_friend(user_id, friend_id)



  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @type accept_error() ::
          :not_found | :not_authorized | :not_pending | :already_friends | :too_many_friends
  @type user_id() :: Ecto.UUID.t()

  @doc ~S"""
    Accept a friend request (only the target may accept). Returns
    `{:ok, friendship}`.
    
    `{:error, :already_friends}` when it was accepted already,
    `{:error, :not_pending}` when it was rejected or blocked first,
    `{:error, :not_found}` when it was cancelled, and
    `{:error, :too_many_friends}` when either side is at the cap.
    
  """
  @spec accept_friend_request(Ecto.UUID.t(), Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Friends.Friendship.t()} | {:error, accept_error()}
  def accept_friend_request(_friendship_id, _user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Friends.Friendship{
           id: 0,
           requester_id: 0,
           target_id: 0,
           requester: nil,
           target: nil,
           status: "pending",
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Friends.accept_friend_request/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns true if `user_id` is on a block with any of `other_ids`, in either
    direction. One query, regardless of how many others are checked.
    
  """
  @spec any_blocked?(user_id(), [user_id()]) :: boolean()
  def any_blocked?(_user_id, _other_ids) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Friends.any_blocked?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Block an incoming request (only the target may block). Returns
    `{:ok, friendship}` with status "blocked", or `{:error, :not_pending}` when
    it was accepted (or blocked) first.
    
  """
  @spec block_friend_request(Ecto.UUID.t(), Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Friends.Friendship.t()}
          | {:error, :not_found | :not_authorized | :not_pending}
  def block_friend_request(_friendship_id, _user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Friends.Friendship{
           id: 0,
           requester_id: 0,
           target_id: 0,
           requester: nil,
           target: nil,
           status: "pending",
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Friends.block_friend_request/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Block an arbitrary user, with or without any prior friendship between them.
    
    Blocked rows are stored in a canonical direction — `target_id` is the
    blocker, `requester_id` is the blocked user — so `list_blocked_for_user/2`
    stays correct. Any existing row between the pair (in either direction) is
    replaced, so blocking supersedes a pending request or an active friendship.
    
    Returns `{:ok, friendship}`, or `{:error, :cannot_block_self}`.
    
  """
  @spec block_user(Gamend.Accounts.User.t(), user_id()) ::
          {:ok, Gamend.Friends.Friendship.t()} | {:error, :cannot_block_self | Ecto.Changeset.t()}
  def block_user(_user, _blocked_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Friends.Friendship{
           id: 0,
           requester_id: 0,
           target_id: 0,
           requester: nil,
           target: nil,
           status: "pending",
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Friends.block_user/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Check if either user has blocked the other.
    
    Returns `true` if a friendship row with status `"blocked"` exists in either
    direction between the two user IDs.
    
  """
  @spec blocked?(user_id(), user_id()) :: boolean()
  def blocked?(_requester_id, _target_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Friends.blocked?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns the set of blocked pairs among `user_ids`, as a `MapSet` of
    `{lower_id, higher_id}` tuples.
    
    Order-independent by construction, so callers can test a pair without
    knowing who blocked whom. Resolves an entire candidate group in one query,
    which is what makes per-pair filtering cheap in matchmaking.
    
  """
  @spec blocked_pairs([user_id()]) :: MapSet.t({user_id(), user_id()})
  def blocked_pairs(_user_ids) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Friends.blocked_pairs/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Cancel an outgoing friend request (only the requester may cancel).
    `{:error, :not_pending}` once it has been answered.
    
  """
  @spec cancel_request(Ecto.UUID.t(), Gamend.Accounts.User.t()) ::
          {:ok, :cancelled} | {:error, :not_found | :not_authorized | :not_pending}
  def cancel_request(_friendship_id, _user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Friends.cancel_request/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count every block across all users, honouring the same filters as `list_all_blocks/1`.
  """
  @spec count_all_blocks(keyword()) :: non_neg_integer()
  def count_all_blocks(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Friends.count_all_blocks/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count every non-block friendship row, honouring the same filters as `list_all_friendships/1`.
  """
  @spec count_all_friendships(keyword()) :: non_neg_integer()
  def count_all_friendships(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Friends.count_all_friendships/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count blocked friendships for a user (number of blocked rows where user is target).
  """
  @spec count_blocked_for_user(user_id()) :: non_neg_integer()
  def count_blocked_for_user(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Friends.count_blocked_for_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count the users `user_id` has blocked.
  """
  @spec count_blocked_users(user_id()) :: non_neg_integer()
  def count_blocked_users(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Friends.count_blocked_users/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count accepted friends for a given user (distinct other user ids).
  """
  @spec count_friends_for_user(user_id()) :: non_neg_integer()
  def count_friends_for_user(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Friends.count_friends_for_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count incoming pending friend requests for a user.
  """
  @spec count_incoming_requests(user_id()) :: non_neg_integer()
  def count_incoming_requests(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Friends.count_incoming_requests/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count outgoing pending friend requests for a user.
  """
  @spec count_outgoing_requests(user_id()) :: non_neg_integer()
  def count_outgoing_requests(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Friends.count_outgoing_requests/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Create a friend request from requester -> target.
      If a reverse pending request exists (target -> requester) it will be accepted instead,
      and fails as `accept_friend_request/2` does.
      A request or a friendship that already stands is returned as `{:ok, friendship}`.
      Fails with `:cannot_friend_self`, `:blocked`, `:too_many_pending_requests` or the
      changeset.
      
  """
  @spec create_request(Gamend.Accounts.User.t() | user_id(), user_id()) ::
          {:ok, Gamend.Friends.Friendship.t()}
          | {:error,
             :cannot_friend_self
             | :blocked
             | :too_many_pending_requests
             | accept_error()
             | Ecto.Changeset.t()}
  def create_request(_requester_id, _target_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Friends.create_request/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Remove a block by its friendship id, regardless of who created it.
    
    For admin use — `unblock_user/2` is the player-facing path and only lets the
    blocker lift their own block.
    
  """
  @spec delete_block(Ecto.UUID.t()) :: {:ok, :unblocked} | {:error, :not_found}
  def delete_block(_friendship_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Friends.delete_block/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Remove a non-block friendship row by its id, regardless of who created it.
    
    For admin use — force-unfriend an accepted pair or cancel a request without
    being either side of it. Blocked rows belong to the Blacklist; remove those
    with `delete_block/1`.
    
  """
  @spec delete_friendship(Ecto.UUID.t()) :: {:ok, :removed} | {:error, :not_found}
  def delete_friendship(_friendship_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Friends.delete_friendship/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Return a list of user IDs that are accepted friends of the given user.
    
    This is used internally (e.g. for broadcasting online-status changes)
    and does *not* paginate – it returns all friend IDs.
    
  """
  @spec friend_ids(user_id()) :: [user_id()]
  def friend_ids(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.friend_ids/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Check whether two users are friends (accepted friendship in either direction).
    
  """
  @spec friends?(user_id(), user_id()) :: boolean()
  def friends?(_user_a_id, _user_b_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Friends.friends?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get friendship between two users (ordered requester->target) if exists
  """
  @spec get_by_pair(user_id(), user_id()) :: Gamend.Friends.Friendship.t() | nil
  def get_by_pair(_requester_id, _target_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Friends.Friendship{
            id: 0,
            requester_id: 0,
            target_id: 0,
            requester: nil,
            target: nil,
            status: "pending",
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Friends.get_by_pair/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get friendship by id (returns nil when not found)
  """
  @spec get_friendship(Ecto.UUID.t()) :: Gamend.Friends.Friendship.t() | nil
  def get_friendship(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Friends.Friendship{
            id: 0,
            requester_id: 0,
            target_id: 0,
            requester: nil,
            target: nil,
            status: "pending",
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Friends.get_friendship/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get friendship by id
  """
  @spec get_friendship!(Ecto.UUID.t()) :: Gamend.Friends.Friendship.t()
  def get_friendship!(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %Gamend.Friends.Friendship{
          id: 0,
          requester_id: 0,
          target_id: 0,
          requester: nil,
          target: nil,
          status: "pending",
          inserted_at: ~U[1970-01-01 00:00:00Z],
          updated_at: ~U[1970-01-01 00:00:00Z]
        }

      _ ->
        raise "Gamend.Friends.get_friendship!/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List every block across all users, newest first, for admin views.
    
    ## Options
    
      * `:user_id` - only blocks where this user is the blocker or the blocked
      * `:page`, `:page_size` - see `t:Gamend.Types.pagination_opts/0`
    
  """
  @spec list_all_blocks(keyword()) :: [Gamend.Friends.Friendship.t()]
  def list_all_blocks(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_all_blocks/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List every friendship row that is not a block, newest first, for admin views.
    
    Covers pending, accepted and rejected rows; blocks belong to the Blacklist
    and are listed with `list_all_blocks/1`.
    
    ## Options
    
      * `:user_id` - only rows where this user is the requester or the target
      * `:status` - only rows with this status ("pending" | "accepted" | "rejected")
      * `:page`, `:page_size` - see `t:Gamend.Types.pagination_opts/0`
    
  """
  @spec list_all_friendships(keyword()) :: [Gamend.Friends.Friendship.t()]
  def list_all_friendships(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_all_friendships/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List blocked friendships for a user (Friendship structs where the user is the blocker / target).
  """
  @spec list_blocked_for_user(user_id()) :: [Gamend.Friends.Friendship.t()]
  def list_blocked_for_user(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_blocked_for_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List blocked friendships for a user (Friendship structs where the user is the blocker / target).
  """
  @spec list_blocked_for_user(user_id(), Gamend.Types.pagination_opts()) :: [
          Gamend.Friends.Friendship.t()
        ]
  def list_blocked_for_user(_user_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_blocked_for_user/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List the users `user_id` has blocked, as `User` structs.
    
    The blacklist proper — unlike `list_blocked_for_user/2`, which returns the
    underlying friendship rows.
    
    See `t:Gamend.Types.pagination_opts/0` for available options.
    
  """
  @spec list_blocked_users(user_id()) :: [Gamend.Accounts.User.t()]
  def list_blocked_users(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_blocked_users/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List the users `user_id` has blocked, as `User` structs.
    
    The blacklist proper — unlike `list_blocked_for_user/2`, which returns the
    underlying friendship rows.
    
    See `t:Gamend.Types.pagination_opts/0` for available options.
    
  """
  @spec list_blocked_users(user_id(), Gamend.Types.pagination_opts()) :: [
          Gamend.Accounts.User.t()
        ]
  def list_blocked_users(_user_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_blocked_users/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List accepted friends for a given user id - returns list of User structs.
    
    ## Options
    
    See `t:Gamend.Types.pagination_opts/0` for available options.
    
  """
  @spec list_friends_for_user(Ecto.UUID.t()) :: [Gamend.Accounts.User.t()]
  def list_friends_for_user(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_friends_for_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List accepted friends for a given user id - returns list of User structs.
    
    ## Options
    
    See `t:Gamend.Types.pagination_opts/0` for available options.
    
  """
  @spec list_friends_for_user(Ecto.UUID.t(), Gamend.Types.pagination_opts()) :: [
          Gamend.Accounts.User.t()
        ]
  def list_friends_for_user(_user_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_friends_for_user/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List accepted friendships for a user along with the other user and friendship id.
    
    Returns a list of maps: %{friendship_id: integer(), user: %User{}}
    
  """
  @spec list_friends_with_friendship(Ecto.UUID.t()) :: [
          %{friendship_id: Ecto.UUID.t(), user: Gamend.Accounts.User.t()}
        ]
  def list_friends_with_friendship(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_friends_with_friendship/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List accepted friendships for a user along with the other user and friendship id.
    
    Returns a list of maps: %{friendship_id: integer(), user: %User{}}
    
  """
  @spec list_friends_with_friendship(Ecto.UUID.t(), Gamend.Types.pagination_opts()) :: [
          %{friendship_id: Ecto.UUID.t(), user: Gamend.Accounts.User.t()}
        ]
  def list_friends_with_friendship(_user_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_friends_with_friendship/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List incoming pending friend requests for a user (Friendship structs).
    
    ## Options
    
    See `t:Gamend.Types.pagination_opts/0` for available options.
    
  """
  @spec list_incoming_requests(Ecto.UUID.t()) :: [Gamend.Friends.Friendship.t()]
  def list_incoming_requests(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_incoming_requests/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List incoming pending friend requests for a user (Friendship structs).
    
    ## Options
    
    See `t:Gamend.Types.pagination_opts/0` for available options.
    
  """
  @spec list_incoming_requests(Ecto.UUID.t(), Gamend.Types.pagination_opts()) :: [
          Gamend.Friends.Friendship.t()
        ]
  def list_incoming_requests(_user_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_incoming_requests/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List outgoing pending friend requests for a user (Friendship structs).
    
    ## Options
    
    See `t:Gamend.Types.pagination_opts/0` for available options.
    
  """
  @spec list_outgoing_requests(Ecto.UUID.t()) :: [Gamend.Friends.Friendship.t()]
  def list_outgoing_requests(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_outgoing_requests/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List outgoing pending friend requests for a user (Friendship structs).
    
    ## Options
    
    See `t:Gamend.Types.pagination_opts/0` for available options.
    
  """
  @spec list_outgoing_requests(Ecto.UUID.t(), Gamend.Types.pagination_opts()) :: [
          Gamend.Friends.Friendship.t()
        ]
  def list_outgoing_requests(_user_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Friends.list_outgoing_requests/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Normalizes a user pair into the order-independent key used by `blocked_pairs/1`.
  """
  @spec pair_key(user_id(), user_id()) :: {user_id(), user_id()}
  def pair_key(_a, _b) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Friends.pair_key/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Reject a friend request (only the target may reject). Returns
    `{:ok, friendship}`, or `{:error, :not_pending}` when it was answered first.
    
  """
  @spec reject_friend_request(Ecto.UUID.t(), Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Friends.Friendship.t()}
          | {:error, :not_found | :not_authorized | :not_pending}
  def reject_friend_request(_friendship_id, _user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Friends.Friendship{
           id: 0,
           requester_id: 0,
           target_id: 0,
           requester: nil,
           target: nil,
           status: "pending",
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Friends.reject_friend_request/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Remove a friendship (either direction) - only participating users may call
    this. Only an accepted friendship: `{:error, :not_found}` when there is none,
    a block placed since included.
    
  """
  @spec remove_friend(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Friends.Friendship.t()} | {:error, :not_found | :not_pending}
  def remove_friend(_user_id, _friend_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Friends.Friendship{
           id: 0,
           requester_id: 0,
           target_id: 0,
           requester: nil,
           target: nil,
           status: "pending",
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Friends.remove_friend/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec subscribe_user(user_id()) :: :ok
  def subscribe_user(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Friends.subscribe_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unblock a previously-blocked friendship (only the user who blocked may unblock). Returns {:ok, :unblocked} on success.
  """
  @spec unblock_friendship(Ecto.UUID.t(), Gamend.Accounts.User.t()) ::
          {:ok, :unblocked} | {:error, :not_found | :not_authorized}
  def unblock_friendship(_friendship_id, _user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Friends.unblock_friendship/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unblock a user previously blocked via `block_user/2`.
    
    Returns `{:ok, :unblocked}`, or `{:error, :not_found}` when no block exists.
    
  """
  @spec unblock_user(Gamend.Accounts.User.t(), user_id()) ::
          {:ok, :unblocked} | {:error, :not_found}
  def unblock_user(_user, _blocked_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Friends.unblock_user/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec unsubscribe_user(user_id()) :: :ok
  def unsubscribe_user(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Friends.unsubscribe_user/1 is a stub - only available at runtime on Gamend"
    end
  end
end
