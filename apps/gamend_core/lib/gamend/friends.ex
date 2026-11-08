defmodule Gamend.Friends do
  @moduledoc """
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

  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: Gamend.Cache
  alias Gamend.Accounts.User
  alias Gamend.Friends.Friendship
  alias Gamend.Lock
  alias Gamend.Repo
  alias Gamend.Repo.AdvisoryLock
  alias Gamend.Types

  require Gamend.Friends.FriendshipStatus, as: FriendshipStatus
  require Gamend.Notifications.NotificationType, as: NotificationType

  @friends_topic "friends"

  @type user_id :: Ecto.UUID.t()

  @typedoc """
  Why `accept_friend_request/2` did not accept: no such request (or it was
  cancelled), not the caller's to answer, answered another way, accepted
  already, or a friend list at its cap.
  """
  @type accept_error ::
          :not_found | :not_authorized | :not_pending | :already_friends | :too_many_friends

  defp friends_cache_version(user_id) when is_binary(user_id) do
    Gamend.Cache.get!({:friends, :version, user_id}) || 1
  end

  defp invalidate_friends_cache(user_id) when is_binary(user_id) do
    _ = Gamend.Cache.bump_version({:friends, :version, user_id})
    :ok
  end

  defp invalidate_friends_cache_pair(a, b) when is_binary(a) and is_binary(b) do
    _ = invalidate_friends_cache(a)
    _ = invalidate_friends_cache(b)
    :ok
  end

  defp friendship_cache_version(friendship_id) when is_binary(friendship_id) do
    Gamend.Cache.get!({:friends, :friendship_version, friendship_id}) || 1
  end

  defp invalidate_friendship_cache(friendship_id) when is_binary(friendship_id) do
    # Synchronous — get_friendship may be called immediately after mutation.
    _ = Gamend.Cache.bump_version({:friends, :friendship_version, friendship_id})
    :ok
  end

  defp cache_match(nil), do: false
  defp cache_match(_), do: true

  @decorate cacheable(
              key:
                {:friends, :pair, friends_cache_version(requester_id),
                 friends_cache_version(target_id), requester_id, target_id},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp get_by_pair_cached(requester_id, target_id)
       when is_binary(requester_id) and is_binary(target_id) do
    Repo.get_by(Friendship, requester_id: requester_id, target_id: target_id)
  end

  @spec subscribe_user(user_id()) :: :ok
  def subscribe_user(user_id) when is_binary(user_id) do
    Phoenix.PubSub.subscribe(Gamend.PubSub, "friends:user:#{user_id}")
  end

  @spec unsubscribe_user(user_id()) :: :ok
  def unsubscribe_user(user_id) when is_binary(user_id) do
    Phoenix.PubSub.unsubscribe(Gamend.PubSub, "friends:user:#{user_id}")
  end

  defp broadcast_user(user_id, event) when is_binary(user_id) do
    # keep existing PubSub behavior (server-side consumers)
    Gamend.Broadcast.publish("friends:user:#{user_id}", event)

    # also push a channel-friendly version to the per-user Phoenix channel
    # so clients joined to "user:<id>" receive realtime updates via sockets.
    case event do
      {name, %Friendship{} = f} when is_atom(name) ->
        payload = %{
          id: f.id,
          requester_id: f.requester_id,
          target_id: f.target_id,
          status: f.status
        }

        # Broadcast to the user channel without depending on the web app.
        topic = "user:#{user_id}"

        Gamend.Broadcast.publish(
          topic,
          %Phoenix.Socket.Broadcast{topic: topic, event: Atom.to_string(name), payload: payload}
        )

      _ ->
        :ok
    end
  end

  defp broadcast_all(event) do
    Gamend.Broadcast.publish(@friends_topic, event)
  end

  # ── Friend notifications ────────────────────────────────────────────────
  #
  # Created synchronously at the event source (not via a PubSub-subscribing
  # GenServer), matching how groups and parties create invite notifications:
  # each event is written exactly once regardless of how many app instances
  # run, and never queues behind a single process.

  defp notify_friend_request(%Friendship{} = f) do
    requester_name = user_display_name(f.requester_id)

    _ =
      Gamend.Notifications.admin_create_notification(f.requester_id, f.target_id, %{
        "title" => "#{requester_name} sent you a friend request",
        "content" => "",
        "metadata" => %{"type" => NotificationType.friend_request(), "friendship_id" => f.id}
      })

    :ok
  end

  defp notify_friend_accepted(%Friendship{} = f) do
    target_name = user_display_name(f.target_id)

    _ =
      Gamend.Notifications.admin_create_notification(f.target_id, f.requester_id, %{
        "title" => "#{target_name} accepted your friend request",
        "content" => "",
        "metadata" => %{"type" => NotificationType.friend_accepted(), "friendship_id" => f.id}
      })

    :ok
  end

  defp notify_friend_rejected(%Friendship{} = f) do
    requester_name = user_display_name(f.requester_id)
    target_name = user_display_name(f.target_id)

    _ =
      Gamend.Notifications.delete_notification_by(
        f.requester_id,
        f.target_id,
        "#{requester_name} sent you a friend request"
      )

    _ =
      Gamend.Notifications.admin_create_notification(f.target_id, f.requester_id, %{
        "title" => "#{target_name} declined your friend request",
        "content" => "",
        "metadata" => %{"type" => "friend_rejected", "friendship_id" => f.id}
      })

    :ok
  end

  # Retracts the original friend-request notification when the request is
  # cancelled by the requester.
  defp retract_friend_request_notification(%Friendship{} = f) do
    requester_name = user_display_name(f.requester_id)

    _ =
      Gamend.Notifications.delete_notification_by(
        f.requester_id,
        f.target_id,
        "#{requester_name} sent you a friend request"
      )

    :ok
  end

  # "Ana (drift-2378)", or the bare username — never "User #<uuid>", which reads
  # like a name and identifies nobody. Accounts owns the rule so this and the
  # friends list the notification sends you to agree.
  defp user_display_name(user_id), do: Gamend.Accounts.display_label(user_id)

  @doc "Create a friend request from requester -> target.
  If a reverse pending request exists (target -> requester) it will be accepted instead,
  and fails as `accept_friend_request/2` does.
  A request or a friendship that already stands is returned as `{:ok, friendship}`.
  Fails with `:cannot_friend_self`, `:blocked`, `:too_many_pending_requests` or the
  changeset.
  "
  @spec create_request(User.t() | user_id(), user_id()) ::
          {:ok, Friendship.t()}
          | {:error,
             :cannot_friend_self
             | :blocked
             | :too_many_pending_requests
             | accept_error()
             | Ecto.Changeset.t()}
  def create_request(%User{id: requester_id}, target_id),
    do: create_request(requester_id, target_id)

  def create_request(requester_id, target_id)
      when is_binary(requester_id) and is_binary(target_id) do
    if requester_id == target_id do
      {:error, :cannot_friend_self}
    else
      # Lock on the canonical (direction-independent) pair so concurrent
      # A→B and B→A requests serialize — the unique index only covers one
      # direction, so without this both could insert reciprocal pending rows.
      Lock.serialize(:friendship, canonical_pair_id(requester_id, target_id), fn ->
        # Both directions are read from the database, not the cache: under the
        # lock these reads are the gate, and a block or an accept commits
        # before its writer evicts the cached row.
        same = Repo.get_by(Friendship, requester_id: requester_id, target_id: target_id)
        reverse = Repo.get_by(Friendship, requester_id: target_id, target_id: requester_id)

        cond do
          status?(same, FriendshipStatus.blocked()) or
              status?(reverse, FriendshipStatus.blocked()) ->
            Repo.rollback(:blocked)

          status?(same, FriendshipStatus.accepted()) ->
            Repo.rollback({:already_friends, same})

          status?(reverse, FriendshipStatus.accepted()) ->
            Repo.rollback({:already_friends, reverse})

          status?(same, FriendshipStatus.pending()) ->
            Repo.rollback({:already_requested, same})

          status?(reverse, FriendshipStatus.pending()) ->
            # Roll back so accept_friend_request can use its own transaction
            Repo.rollback({:accept_reverse, reverse.id})

          true ->
            insert_friend_request(same, requester_id, target_id)
        end
      end)
      |> case do
        {:ok, f} ->
          _ = invalidate_friendship_cache(f.id)
          _ = invalidate_friends_cache_pair(requester_id, target_id)
          broadcast_user(target_id, {:incoming_request, f})
          broadcast_user(requester_id, {:outgoing_request, f})
          broadcast_all({:friend_created, f})
          notify_friend_request(f)
          {:ok, f}

        {:error, {:accept_reverse, friendship_id}} ->
          accept_friend_request(friendship_id, %User{id: requester_id})

        # Idempotent: the request or the friendship that already stands.
        {:error, {:already_requested, %Friendship{} = f}} ->
          {:ok, f}

        {:error, {:already_friends, %Friendship{} = f}} ->
          {:ok, f}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Direction-independent key so both A→B and B→A hash to the same lock.
  defp canonical_pair_id(a, b), do: [a, b] |> Enum.sort() |> Enum.join(":")

  defp status?(%Friendship{status: status}, status), do: true
  defp status?(_friendship, _status), do: false

  # Every write of a pair's rows holds the pair's lock, so what
  # `create_request/2` decides from the rows it reads under it stays true until
  # it commits. `fun` answers `{:ok, value}` or `{:error, reason}`, which rolls
  # back.
  defp with_pair_lock(a, b, fun) do
    Lock.serialize(:friendship, canonical_pair_id(a, b), fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # A cap on friends or on pending requests is each player's, not the pair's:
  # one player accepting two requests at once, or sending two, takes two pair
  # locks that never wait on each other. So the players are locked too, inside
  # the pair's lock and in id order, so two writes sharing both players cannot
  # each hold one and wait for the other.
  defp lock_players(user_ids) do
    user_ids
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(&AdvisoryLock.lock("friends_player", &1))
  end

  # Inside the pair's lock, with the requester locked: the pending count is
  # the one the insert is checked against. `rejected` is the same-direction
  # row a rejection left, or nil; it makes way for the fresh request.
  defp insert_friend_request(rejected, requester_id, target_id) do
    lock_players([requester_id])

    if rejected, do: Repo.delete_all(from f in Friendship, where: f.id == ^rejected.id)

    max_pending = Gamend.Limits.get(:max_pending_friend_requests)
    pending_count = count_outgoing_requests(requester_id)

    if pending_count >= max_pending do
      Repo.rollback(:too_many_pending_requests)
    end

    case %Friendship{}
         |> Friendship.changeset(%{requester_id: requester_id, target_id: target_id})
         |> Repo.insert() do
      {:ok, f} ->
        f

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  # The cached row names the pair and who may act on it, which never change
  # for a row id. Its status may have changed since, and only the write that
  # follows decides on that.
  defp fetch_request(friendship_id, side, user_id) do
    case get_friendship(friendship_id) do
      nil ->
        {:error, :not_found}

      %Friendship{} = f ->
        if Map.fetch!(f, side) == user_id, do: {:ok, f}, else: {:error, :not_authorized}
    end
  end

  # The one write of a request's status. The row moves to `to` only while it
  # is still in one of `from`: of an accept, a reject, a block and a cancel
  # landing together exactly one wins, and the others answer what the row
  # became instead of writing over it (an accept over a block) or raising on a
  # row deleted under them (an accept after a cancel).
  defp transition(%Friendship{id: id}, from, to) do
    from(f in Friendship, where: f.id == ^id and f.status in ^from)
    |> Repo.compare_and_set(set: [status: to, updated_at: DateTime.utc_now(:second)])
    |> case do
      {:ok, row} -> {:ok, row}
      {:error, :precondition_failed} -> {:error, moved_on(id, to)}
    end
  end

  # Deletes the row only while it is still in `status`.
  defp delete_in_status(%Friendship{id: id}, status) do
    case Repo.delete_all(from f in Friendship, where: f.id == ^id and f.status == ^status) do
      {1, _} -> {:ok, :deleted}
      {0, _} -> {:error, moved_on(id, :deleted)}
    end
  end

  # What a write that found its row moved on answers: gone (cancelled, or
  # deleted by a block from the requester), friends already when that is what
  # it wanted, and otherwise answered some other way.
  defp moved_on(id, wanted) do
    case {Repo.get(Friendship, id), wanted} do
      {nil, _} ->
        :not_found

      {%Friendship{status: FriendshipStatus.accepted()}, FriendshipStatus.accepted()} ->
        :already_friends

      {%Friendship{}, _} ->
        :not_pending
    end
  end

  @doc """
  Check if either user has blocked the other.

  Returns `true` if a friendship row with status `"blocked"` exists in either
  direction between the two user IDs.
  """
  @spec blocked?(user_id(), user_id()) :: boolean()
  def blocked?(requester_id, target_id) do
    existing_same = get_by_pair(requester_id, target_id)
    existing_reverse = get_by_pair(target_id, requester_id)

    (existing_same && existing_same.status == FriendshipStatus.blocked()) ||
      (existing_reverse && existing_reverse.status == FriendshipStatus.blocked())
  end

  @doc """
  Check whether two users are friends (accepted friendship in either direction).
  """
  @spec friends?(user_id(), user_id()) :: boolean()
  def friends?(user_a_id, user_b_id) do
    already_friends?(user_a_id, user_b_id) != nil
  end

  defp already_friends?(requester_id, target_id) do
    case get_by_pair(requester_id, target_id) do
      %Friendship{status: FriendshipStatus.accepted()} = f ->
        f

      _ ->
        case get_by_pair(target_id, requester_id) do
          %Friendship{status: FriendshipStatus.accepted()} = f -> f
          _ -> nil
        end
    end
  end

  @doc """
  Accept a friend request (only the target may accept). Returns
  `{:ok, friendship}`.

  `{:error, :already_friends}` when it was accepted already,
  `{:error, :not_pending}` when it was rejected or blocked first,
  `{:error, :not_found}` when it was cancelled, and
  `{:error, :too_many_friends}` when either side is at the cap.
  """
  @spec accept_friend_request(Ecto.UUID.t(), User.t()) ::
          {:ok, Friendship.t()} | {:error, accept_error()}
  def accept_friend_request(friendship_id, %User{id: user_id}) when is_binary(friendship_id) do
    with {:ok, f} <- fetch_request(friendship_id, :target_id, user_id),
         {:ok, accepted} <-
           with_pair_lock(f.requester_id, f.target_id, fn -> accept_locked(f) end) do
      _ = invalidate_friendship_cache(accepted.id)
      _ = invalidate_friends_cache_pair(accepted.requester_id, accepted.target_id)

      # Only the accept whose write won gets here, and only once it committed.
      broadcast_user(accepted.requester_id, {:friend_accepted, accepted})
      broadcast_user(accepted.target_id, {:friend_accepted, accepted})
      broadcast_all({:friend_accepted, accepted})
      notify_friend_accepted(accepted)

      {:ok, accepted}
    end
  end

  # The friend cap is counted after the write, with both players locked: the
  # accept stands only while neither of them is over it.
  defp accept_locked(%Friendship{} = f) do
    lock_players([f.requester_id, f.target_id])

    with {:ok, accepted} <-
           transition(f, [FriendshipStatus.pending()], FriendshipStatus.accepted()),
         :ok <- within_friends_limit(accepted.requester_id),
         :ok <- within_friends_limit(accepted.target_id) do
      # remove any reverse pending request if present
      Repo.delete_all(
        from ff in Friendship,
          where:
            ff.requester_id == ^f.target_id and ff.target_id == ^f.requester_id and
              ff.status == ^FriendshipStatus.pending()
      )

      {:ok, accepted}
    end
  end

  @doc """
  Reject a friend request (only the target may reject). Returns
  `{:ok, friendship}`, or `{:error, :not_pending}` when it was answered first.
  """
  @spec reject_friend_request(Ecto.UUID.t(), User.t()) ::
          {:ok, Friendship.t()} | {:error, :not_found | :not_authorized | :not_pending}
  def reject_friend_request(friendship_id, %User{id: user_id}) when is_binary(friendship_id) do
    with {:ok, f} <- fetch_request(friendship_id, :target_id, user_id),
         {:ok, rejected} <-
           with_pair_lock(f.requester_id, f.target_id, fn ->
             transition(f, [FriendshipStatus.pending()], FriendshipStatus.rejected())
           end) do
      _ = invalidate_friendship_cache(rejected.id)
      _ = invalidate_friends_cache_pair(rejected.requester_id, rejected.target_id)

      # broadcast rejection
      broadcast_user(rejected.requester_id, {:friend_rejected, rejected})
      broadcast_user(rejected.target_id, {:friend_rejected, rejected})
      broadcast_all({:friend_rejected, rejected})
      notify_friend_rejected(rejected)

      {:ok, rejected}
    end
  end

  @doc """
  Cancel an outgoing friend request (only the requester may cancel).
  `{:error, :not_pending}` once it has been answered.
  """
  @spec cancel_request(Ecto.UUID.t(), User.t()) ::
          {:ok, :cancelled} | {:error, :not_found | :not_authorized | :not_pending}
  def cancel_request(friendship_id, %User{id: user_id}) when is_binary(friendship_id) do
    with {:ok, f} <- fetch_request(friendship_id, :requester_id, user_id),
         {:ok, :deleted} <-
           with_pair_lock(f.requester_id, f.target_id, fn ->
             delete_in_status(f, FriendshipStatus.pending())
           end) do
      _ = invalidate_friendship_cache(f.id)
      _ = invalidate_friends_cache_pair(f.requester_id, f.target_id)

      # broadcast cancellation
      broadcast_user(f.requester_id, {:request_cancelled, f})
      broadcast_user(f.target_id, {:request_cancelled, f})
      broadcast_all({:request_cancelled, f})
      retract_friend_request_notification(f)

      {:ok, :cancelled}
    end
  end

  @doc """
  Remove a friendship (either direction) - only participating users may call
  this. Only an accepted friendship: `{:error, :not_found}` when there is none,
  a block placed since included.
  """
  @spec remove_friend(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Friendship.t()} | {:error, :not_found | :not_pending}
  def remove_friend(user_id, friend_id) when is_binary(user_id) and is_binary(friend_id) do
    with_pair_lock(user_id, friend_id, fn ->
      # A block the other player placed since this one listed their friends is
      # theirs: it replaced the friendship, and removing it is not this call's.
      case Repo.one(
             from f in Friendship,
               where:
                 f.status == ^FriendshipStatus.accepted() and
                   ((f.requester_id == ^user_id and f.target_id == ^friend_id) or
                      (f.requester_id == ^friend_id and f.target_id == ^user_id)),
               limit: 1
           ) do
        %Friendship{} = f ->
          with {:ok, :deleted} <- delete_in_status(f, FriendshipStatus.accepted()), do: {:ok, f}

        nil ->
          {:error, :not_found}
      end
    end)
    |> case do
      {:ok, f} ->
        _ = invalidate_friendship_cache(f.id)
        _ = invalidate_friends_cache_pair(user_id, friend_id)

        # clean up friend chat messages and read cursors
        Gamend.Chat.cleanup_friend_chat(user_id, friend_id)

        # broadcast removal
        broadcast_user(user_id, {:friend_removed, f})
        broadcast_user(friend_id, {:friend_removed, f})
        broadcast_all({:friend_removed, f})
        {:ok, f}

      error ->
        error
    end
  end

  @doc """
  Block an incoming request (only the target may block). Returns
  `{:ok, friendship}` with status "blocked", or `{:error, :not_pending}` when
  it was accepted (or blocked) first.
  """
  @spec block_friend_request(Ecto.UUID.t(), User.t()) ::
          {:ok, Friendship.t()} | {:error, :not_found | :not_authorized | :not_pending}
  def block_friend_request(friendship_id, %User{id: user_id}) when is_binary(friendship_id) do
    with {:ok, f} <- fetch_request(friendship_id, :target_id, user_id),
         {:ok, blocked} <-
           with_pair_lock(f.requester_id, f.target_id, fn ->
             transition(
               f,
               [FriendshipStatus.pending(), FriendshipStatus.rejected()],
               FriendshipStatus.blocked()
             )
           end) do
      _ = invalidate_friendship_cache(blocked.id)
      _ = invalidate_friends_cache_pair(blocked.requester_id, blocked.target_id)

      # broadcast blocked
      broadcast_user(blocked.requester_id, {:friend_blocked, blocked})
      broadcast_user(blocked.target_id, {:friend_blocked, blocked})
      broadcast_all({:friend_blocked, blocked})

      {:ok, blocked}
    end
  end

  @doc """
  Block an arbitrary user, with or without any prior friendship between them.

  Blocked rows are stored in a canonical direction — `target_id` is the
  blocker, `requester_id` is the blocked user — so `list_blocked_for_user/2`
  stays correct. Any existing row between the pair (in either direction) is
  replaced, so blocking supersedes a pending request or an active friendship.

  Returns `{:ok, friendship}`, or `{:error, :cannot_block_self}`.
  """
  @spec block_user(User.t(), user_id()) ::
          {:ok, Friendship.t()} | {:error, :cannot_block_self | Ecto.Changeset.t()}
  def block_user(%User{id: blocker_id}, blocked_id) when is_binary(blocked_id) do
    if blocker_id == blocked_id do
      {:error, :cannot_block_self}
    else
      do_block_user(blocker_id, blocked_id)
    end
  end

  # Under the pair's lock, with the row it turns into the block read from the
  # database: the cached one may be a request cancelled since, whose update
  # found no row and raised.
  defp do_block_user(blocker_id, blocked_id) do
    with_pair_lock(blocker_id, blocked_id, fn ->
      # Drop the reverse row first: the pair is unique per direction, so a
      # reverse row would otherwise survive alongside the canonical block.
      Repo.delete_all(
        from f in Friendship,
          where: f.requester_id == ^blocker_id and f.target_id == ^blocked_id
      )

      case Repo.get_by(Friendship, requester_id: blocked_id, target_id: blocker_id) do
        %Friendship{} = f ->
          f |> Ecto.Changeset.change(status: FriendshipStatus.blocked()) |> Repo.update()

        nil ->
          %Friendship{}
          |> Friendship.changeset(%{
            requester_id: blocked_id,
            target_id: blocker_id,
            status: FriendshipStatus.blocked()
          })
          |> Repo.insert()
      end
    end)
    |> case do
      {:ok, blocked} ->
        _ = invalidate_friendship_cache(blocked.id)
        _ = invalidate_friends_cache_pair(blocker_id, blocked_id)

        broadcast_user(blocker_id, {:friend_blocked, blocked})
        broadcast_user(blocked_id, {:friend_blocked, blocked})
        broadcast_all({:friend_blocked, blocked})

        {:ok, blocked}

      error ->
        error
    end
  end

  @doc """
  Unblock a user previously blocked via `block_user/2`.

  Returns `{:ok, :unblocked}`, or `{:error, :not_found}` when no block exists.
  """
  @spec unblock_user(User.t(), user_id()) :: {:ok, :unblocked} | {:error, :not_found}
  def unblock_user(%User{id: blocker_id}, blocked_id) when is_binary(blocked_id) do
    case get_by_pair(blocked_id, blocker_id) do
      %Friendship{status: FriendshipStatus.blocked()} = f ->
        with {:ok, :deleted} <- delete_block_row(f) do
          _ = invalidate_friendship_cache(f.id)
          _ = invalidate_friends_cache_pair(blocker_id, blocked_id)

          broadcast_user(blocker_id, {:friend_unblocked, f})
          broadcast_user(blocked_id, {:friend_unblocked, f})
          broadcast_all({:friend_unblocked, f})

          {:ok, :unblocked}
        end

      _ ->
        {:error, :not_found}
    end
  end

  # A block lifted twice at once (or by its owner and an admin) is lifted
  # once: the second finds no row and answers `:not_found`.
  defp delete_block_row(%Friendship{} = f) do
    with {:error, _} <-
           with_pair_lock(f.requester_id, f.target_id, fn ->
             delete_in_status(f, FriendshipStatus.blocked())
           end),
         do: {:error, :not_found}
  end

  @doc """
  Returns the set of blocked pairs among `user_ids`, as a `MapSet` of
  `{lower_id, higher_id}` tuples.

  Order-independent by construction, so callers can test a pair without
  knowing who blocked whom. Resolves an entire candidate group in one query,
  which is what makes per-pair filtering cheap in matchmaking.
  """
  @spec blocked_pairs([user_id()]) :: MapSet.t({user_id(), user_id()})
  def blocked_pairs(user_ids) when is_list(user_ids) do
    ids = Enum.uniq(user_ids)

    from(f in Friendship,
      where:
        f.status == ^FriendshipStatus.blocked() and f.requester_id in ^ids and
          f.target_id in ^ids,
      select: {f.requester_id, f.target_id}
    )
    |> Repo.all()
    |> MapSet.new(fn {a, b} -> pair_key(a, b) end)
  end

  @doc """
  List the users `user_id` has blocked, as `User` structs.

  The blacklist proper — unlike `list_blocked_for_user/2`, which returns the
  underlying friendship rows.

  See `t:Gamend.Types.pagination_opts/0` for available options.
  """
  @spec list_blocked_users(user_id()) :: [User.t()]
  @spec list_blocked_users(user_id(), Types.pagination_opts()) :: [User.t()]
  def list_blocked_users(user_id, opts \\ []) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    offset = (page - 1) * page_size

    Repo.all(
      from u in User,
        join: f in Friendship,
        on: f.requester_id == u.id,
        where: f.target_id == ^user_id and f.status == ^FriendshipStatus.blocked(),
        order_by: [desc: f.inserted_at],
        limit: ^page_size,
        offset: ^offset
    )
  end

  @doc "Count the users `user_id` has blocked."
  @spec count_blocked_users(user_id()) :: non_neg_integer()
  def count_blocked_users(user_id) when is_binary(user_id) do
    count_blocked_for_user(user_id)
  end

  @doc """
  List every block across all users, newest first, for admin views.

  ## Options

    * `:user_id` - only blocks where this user is the blocker or the blocked
    * `:page`, `:page_size` - see `t:Gamend.Types.pagination_opts/0`
  """
  @spec list_all_blocks(keyword()) :: [Friendship.t()]
  def list_all_blocks(opts \\ []) do
    opts
    |> all_blocks_query()
    |> order_by([f], desc: f.inserted_at)
    |> Gamend.Query.page(opts)
    |> preload([:requester, :target])
    |> Repo.all()
  end

  @doc "Count every block across all users, honouring the same filters as `list_all_blocks/1`."
  @spec count_all_blocks(keyword()) :: non_neg_integer()
  def count_all_blocks(opts \\ []) do
    Repo.one(from f in all_blocks_query(opts), select: count(f.id)) || 0
  end

  defp all_blocks_query(opts) do
    query = from f in Friendship, where: f.status == ^FriendshipStatus.blocked()

    case Keyword.get(opts, :user_id) do
      nil ->
        query

      "" ->
        query

      user_id ->
        # An admin filter typed by hand: an id that is not one matches nothing.
        case Gamend.UUIDv7.cast_or_nil(user_id) do
          nil -> from(f in query, where: false)
          id -> from(f in query, where: f.requester_id == ^id or f.target_id == ^id)
        end
    end
  end

  @doc """
  Remove a block by its friendship id, regardless of who created it.

  For admin use — `unblock_user/2` is the player-facing path and only lets the
  blocker lift their own block.
  """
  @spec delete_block(Ecto.UUID.t()) :: {:ok, :unblocked} | {:error, :not_found}
  def delete_block(friendship_id) when is_binary(friendship_id) do
    with %Friendship{status: FriendshipStatus.blocked()} = f <- get_friendship(friendship_id),
         {:ok, :deleted} <- delete_block_row(f) do
      _ = invalidate_friendship_cache(f.id)
      _ = invalidate_friends_cache_pair(f.requester_id, f.target_id)

      broadcast_user(f.requester_id, {:friend_unblocked, f})
      broadcast_user(f.target_id, {:friend_unblocked, f})
      broadcast_all({:friend_unblocked, f})

      {:ok, :unblocked}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  List every friendship row that is not a block, newest first, for admin views.

  Covers pending, accepted and rejected rows; blocks belong to the Blacklist
  and are listed with `list_all_blocks/1`.

  ## Options

    * `:user_id` - only rows where this user is the requester or the target
    * `:status` - only rows with this status ("pending" | "accepted" | "rejected")
    * `:page`, `:page_size` - see `t:Gamend.Types.pagination_opts/0`
  """
  @spec list_all_friendships(keyword()) :: [Friendship.t()]
  def list_all_friendships(opts \\ []) do
    opts
    |> all_friendships_query()
    |> order_by([f], desc: f.inserted_at)
    |> Gamend.Query.page(opts)
    |> preload([:requester, :target])
    |> Repo.all()
  end

  @doc "Count every non-block friendship row, honouring the same filters as `list_all_friendships/1`."
  @spec count_all_friendships(keyword()) :: non_neg_integer()
  def count_all_friendships(opts \\ []) do
    Repo.one(from f in all_friendships_query(opts), select: count(f.id)) || 0
  end

  defp all_friendships_query(opts) do
    query = from f in Friendship, where: f.status != ^FriendshipStatus.blocked()

    query =
      case Keyword.get(opts, :status) do
        nil ->
          query

        "" ->
          query

        status ->
          from f in query, where: f.status == ^status
      end

    case Keyword.get(opts, :user_id) do
      nil ->
        query

      "" ->
        query

      user_id ->
        # An admin filter typed by hand: an id that is not one matches nothing.
        case Gamend.UUIDv7.cast_or_nil(user_id) do
          nil -> from(f in query, where: false)
          id -> from(f in query, where: f.requester_id == ^id or f.target_id == ^id)
        end
    end
  end

  @doc """
  Remove a non-block friendship row by its id, regardless of who created it.

  For admin use — force-unfriend an accepted pair or cancel a request without
  being either side of it. Blocked rows belong to the Blacklist; remove those
  with `delete_block/1`.
  """
  @spec delete_friendship(Ecto.UUID.t()) :: {:ok, :removed} | {:error, :not_found}
  def delete_friendship(friendship_id) when is_binary(friendship_id) do
    with %Friendship{status: status} = f when status != FriendshipStatus.blocked() <-
           get_friendship(friendship_id),
         # Deleted only while it is still what was read, so the event below
         # names what the row was: a request accepted or blocked meanwhile is
         # left for another look.
         {:ok, :deleted} <-
           with_pair_lock(f.requester_id, f.target_id, fn -> delete_in_status(f, status) end) do
      remove_friendship_row(f)
    else
      _ -> {:error, :not_found}
    end
  end

  defp remove_friendship_row(%Friendship{} = f) do
    _ = invalidate_friendship_cache(f.id)
    _ = invalidate_friends_cache_pair(f.requester_id, f.target_id)

    # An accepted pair leaves a DM history behind, same as remove_friend/2.
    if f.status == FriendshipStatus.accepted() do
      Gamend.Chat.cleanup_friend_chat(f.requester_id, f.target_id)
    end

    # A cancelled request and a removed friendship are different events to
    # a connected client, so broadcast whichever the row actually was.
    event =
      if f.status == FriendshipStatus.pending(), do: :request_cancelled, else: :friend_removed

    broadcast_user(f.requester_id, {event, f})
    broadcast_user(f.target_id, {event, f})
    broadcast_all({event, f})
    if f.status == FriendshipStatus.pending(), do: retract_friend_request_notification(f)

    {:ok, :removed}
  end

  @doc """
  Returns true if `user_id` is on a block with any of `other_ids`, in either
  direction. One query, regardless of how many others are checked.
  """
  @spec any_blocked?(user_id(), [user_id()]) :: boolean()
  def any_blocked?(user_id, other_ids) when is_binary(user_id) and is_list(other_ids) do
    others = other_ids |> Enum.uniq() |> Enum.reject(&(&1 == user_id))

    others != [] and
      Repo.exists?(
        from f in Friendship,
          where:
            f.status == ^FriendshipStatus.blocked() and
              ((f.requester_id == ^user_id and f.target_id in ^others) or
                 (f.target_id == ^user_id and f.requester_id in ^others))
      )
  end

  @doc """
  Returns true if anyone in `ids` is on a block with anyone in `other_ids`, in
  either direction: a party and the players already seated in a lobby. One
  query.
  """
  @spec any_blocked_between?([user_id()], [user_id()]) :: boolean()
  def any_blocked_between?(ids, other_ids) when is_list(ids) and is_list(other_ids) do
    ids = Enum.uniq(ids)
    others = other_ids |> Enum.uniq() |> Enum.reject(&(&1 in ids))

    ids != [] and others != [] and
      Repo.exists?(
        from f in Friendship,
          where:
            f.status == ^FriendshipStatus.blocked() and
              ((f.requester_id in ^ids and f.target_id in ^others) or
                 (f.target_id in ^ids and f.requester_id in ^others))
      )
  end

  @doc "Normalizes a user pair into the order-independent key used by `blocked_pairs/1`."
  @spec pair_key(user_id(), user_id()) :: {user_id(), user_id()}
  def pair_key(a, b) when a <= b, do: {a, b}
  def pair_key(a, b), do: {b, a}

  @doc "List blocked friendships for a user (Friendship structs where the user is the blocker / target)."
  @spec list_blocked_for_user(user_id()) :: [Friendship.t()]
  @spec list_blocked_for_user(user_id(), Types.pagination_opts()) :: [Friendship.t()]
  def list_blocked_for_user(user_id, opts \\ [])

  def list_blocked_for_user(user_id, opts) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    list_blocked_for_user_uncached(user_id, page, page_size)
  end

  defp list_blocked_for_user_uncached(user_id, page, page_size) do
    offset = (page - 1) * page_size

    Repo.all(
      from f in Friendship,
        where: f.target_id == ^user_id and f.status == ^FriendshipStatus.blocked(),
        preload: [:requester],
        limit: ^page_size,
        offset: ^offset
    )
  end

  @doc "Count blocked friendships for a user (number of blocked rows where user is target)."
  @spec count_blocked_for_user(user_id()) :: non_neg_integer()

  def count_blocked_for_user(user_id) when is_binary(user_id) do
    count_blocked_for_user_uncached(user_id)
  end

  defp count_blocked_for_user_uncached(user_id) do
    Repo.one(
      from f in Friendship,
        where: f.target_id == ^user_id and f.status == ^FriendshipStatus.blocked(),
        select: count(f.id)
    ) || 0
  end

  @doc "Unblock a previously-blocked friendship (only the user who blocked may unblock). Returns {:ok, :unblocked} on success."
  @spec unblock_friendship(Ecto.UUID.t(), User.t()) ::
          {:ok, :unblocked} | {:error, :not_found | :not_authorized}
  def unblock_friendship(friendship_id, %User{id: user_id}) when is_binary(friendship_id) do
    with %Friendship{} = f <- get_friendship(friendship_id),
         true <- f.target_id == user_id,
         true <- f.status == FriendshipStatus.blocked(),
         {:ok, :deleted} <- delete_block_row(f) do
      _ = invalidate_friendship_cache(f.id)
      _ = invalidate_friends_cache_pair(f.requester_id, f.target_id)

      # broadcast unblocked so UI/SDK can refresh
      broadcast_user(f.requester_id, {:friend_unblocked, f})
      broadcast_user(f.target_id, {:friend_unblocked, f})
      broadcast_all({:friend_unblocked, f})

      {:ok, :unblocked}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_authorized}
      err -> err
    end
  end

  @doc """
  List accepted friends for a given user id - returns list of User structs.

  ## Options

  See `t:Gamend.Types.pagination_opts/0` for available options.
  """
  @spec list_friends_for_user(Ecto.UUID.t()) :: [User.t()]
  @spec list_friends_for_user(Ecto.UUID.t(), Types.pagination_opts()) :: [User.t()]
  def list_friends_for_user(user_id, opts \\ [])

  def list_friends_for_user(user_id, opts) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    list_friends_for_user_uncached(user_id, page, page_size)
  end

  defp list_friends_for_user_uncached(user_id, page, page_size) do
    offset = (page - 1) * page_size

    q1 =
      from f in Friendship,
        where: f.status == ^FriendshipStatus.accepted() and f.requester_id == ^user_id,
        select: %{id: f.target_id}

    q2 =
      from f in Friendship,
        where: f.status == ^FriendshipStatus.accepted() and f.target_id == ^user_id,
        select: %{id: f.requester_id}

    union_q = union_all(q1, ^q2)

    # union the two sets and paginate
    ids =
      Repo.all(
        from id_row in subquery(union_q),
          select: id_row.id,
          distinct: true,
          limit: ^page_size,
          offset: ^offset
      )

    Repo.all(from u in User, where: u.id in ^ids)
  end

  @doc """
  List accepted friendships for a user along with the other user and friendship id.

  Returns a list of maps: %{friendship_id: integer(), user: %User{}}
  """
  @spec list_friends_with_friendship(Ecto.UUID.t()) :: [
          %{friendship_id: Ecto.UUID.t(), user: User.t()}
        ]
  @spec list_friends_with_friendship(Ecto.UUID.t(), Types.pagination_opts()) :: [
          %{friendship_id: Ecto.UUID.t(), user: User.t()}
        ]
  def list_friends_with_friendship(user_id, opts \\ [])

  def list_friends_with_friendship(user_id, opts) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    list_friends_with_friendship_uncached(user_id, page, page_size)
  end

  defp list_friends_with_friendship_uncached(user_id, page, page_size) do
    offset = (page - 1) * page_size

    friendships =
      Repo.all(
        from f in Friendship,
          where:
            f.status == ^FriendshipStatus.accepted() and
              (f.requester_id == ^user_id or f.target_id == ^user_id),
          preload: [:requester, :target],
          limit: ^page_size,
          offset: ^offset
      )

    Enum.map(friendships, fn f ->
      other = if f.requester_id == user_id, do: f.target, else: f.requester
      %{friendship_id: f.id, user: other}
    end)
  end

  @doc "Count accepted friends for a given user (distinct other user ids)."
  @spec count_friends_for_user(user_id()) :: non_neg_integer()

  def count_friends_for_user(user_id) when is_binary(user_id) do
    count_friends_for_user_uncached(user_id)
  end

  defp count_friends_for_user_uncached(user_id) do
    q1 =
      from f in Friendship,
        where: f.status == ^FriendshipStatus.accepted() and f.requester_id == ^user_id,
        select: %{id: f.target_id}

    q2 =
      from f in Friendship,
        where: f.status == ^FriendshipStatus.accepted() and f.target_id == ^user_id,
        select: %{id: f.requester_id}

    union_q = union_all(q1, ^q2)

    Repo.one(from id_row in subquery(union_q), select: count(id_row.id, :distinct)) || 0
  end

  @doc """
  List incoming pending friend requests for a user (Friendship structs).

  ## Options

  See `t:Gamend.Types.pagination_opts/0` for available options.
  """
  @spec list_incoming_requests(Ecto.UUID.t()) :: [Friendship.t()]
  @spec list_incoming_requests(Ecto.UUID.t(), Types.pagination_opts()) :: [Friendship.t()]
  def list_incoming_requests(user_id, opts \\ [])

  def list_incoming_requests(user_id, opts) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    list_incoming_requests_uncached(user_id, page, page_size)
  end

  defp list_incoming_requests_uncached(user_id, page, page_size) do
    offset = (page - 1) * page_size

    Repo.all(
      from f in Friendship,
        where: f.target_id == ^user_id and f.status == ^FriendshipStatus.pending(),
        preload: [:requester],
        limit: ^page_size,
        offset: ^offset
    )
  end

  @doc "Count incoming pending friend requests for a user."
  @spec count_incoming_requests(user_id()) :: non_neg_integer()

  def count_incoming_requests(user_id) when is_binary(user_id) do
    count_incoming_requests_uncached(user_id)
  end

  defp count_incoming_requests_uncached(user_id) do
    Repo.one(
      from f in Friendship,
        where: f.target_id == ^user_id and f.status == ^FriendshipStatus.pending(),
        select: count(f.id)
    ) || 0
  end

  @doc """
  List outgoing pending friend requests for a user (Friendship structs).

  ## Options

  See `t:Gamend.Types.pagination_opts/0` for available options.
  """
  @spec list_outgoing_requests(Ecto.UUID.t()) :: [Friendship.t()]
  @spec list_outgoing_requests(Ecto.UUID.t(), Types.pagination_opts()) :: [Friendship.t()]
  def list_outgoing_requests(user_id, opts \\ [])

  def list_outgoing_requests(user_id, opts) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    list_outgoing_requests_uncached(user_id, page, page_size)
  end

  defp list_outgoing_requests_uncached(user_id, page, page_size) do
    offset = (page - 1) * page_size

    Repo.all(
      from f in Friendship,
        where: f.requester_id == ^user_id and f.status == ^FriendshipStatus.pending(),
        preload: [:target],
        limit: ^page_size,
        offset: ^offset
    )
  end

  @doc "Count outgoing pending friend requests for a user."
  @spec count_outgoing_requests(user_id()) :: non_neg_integer()

  def count_outgoing_requests(user_id) when is_binary(user_id) do
    count_outgoing_requests_uncached(user_id)
  end

  defp count_outgoing_requests_uncached(user_id) do
    Repo.one(
      from f in Friendship,
        where: f.requester_id == ^user_id and f.status == ^FriendshipStatus.pending(),
        select: count(f.id)
    ) || 0
  end

  @doc "Get friendship by id"
  @spec get_friendship!(Ecto.UUID.t()) :: Friendship.t()
  @decorate cacheable(
              key: {:friends, :friendship, friendship_cache_version(id), id},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_friendship!(id), do: Repo.get_uuid!(Friendship, id)

  @doc "Get friendship by id (returns nil when not found)"
  @spec get_friendship(Ecto.UUID.t()) :: Friendship.t() | nil
  @decorate cacheable(
              key: {:friends, :friendship, friendship_cache_version(id), id},
              match: &cache_match/1,
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_friendship(id), do: Repo.get_uuid(Friendship, id)

  @doc "Get friendship between two users (ordered requester->target) if exists"
  @spec get_by_pair(user_id(), user_id()) :: Friendship.t() | nil
  def get_by_pair(requester_id, target_id) do
    get_by_pair_cached(requester_id, target_id)
  end

  @doc """
  Return a list of user IDs that are accepted friends of the given user.

  This is used internally (e.g. for broadcasting online-status changes)
  and does *not* paginate – it returns all friend IDs.
  """
  @spec friend_ids(user_id()) :: [user_id()]
  def friend_ids(user_id) when is_binary(user_id) do
    q1 =
      from f in Friendship,
        where: f.status == ^FriendshipStatus.accepted() and f.requester_id == ^user_id,
        select: f.target_id

    q2 =
      from f in Friendship,
        where: f.status == ^FriendshipStatus.accepted() and f.target_id == ^user_id,
        select: f.requester_id

    union_all(q1, ^q2) |> Repo.all()
  end

  # Asked after the accept's write, so the count includes the friendship it
  # made: over the cap means this one is one too many.
  defp within_friends_limit(user_id) do
    if count_friends_for_user(user_id) > Gamend.Limits.get(:max_friends_per_user) do
      {:error, :too_many_friends}
    else
      :ok
    end
  end
end
