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
  alias Gamend.Types
  @friends_topic "friends"

  @type user_id :: Ecto.UUID.t()

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
        "metadata" => %{"type" => "friend_request", "friendship_id" => f.id}
      })

    :ok
  end

  defp notify_friend_accepted(%Friendship{} = f) do
    target_name = user_display_name(f.target_id)

    _ =
      Gamend.Notifications.admin_create_notification(f.target_id, f.requester_id, %{
        "title" => "#{target_name} accepted your friend request",
        "content" => "",
        "metadata" => %{"type" => "friend_accepted", "friendship_id" => f.id}
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
  If a reverse pending request exists (target -> requester) it will be accepted instead.
  Returns {:ok, friendship} on success or {:error, reason}.
  "
  @spec create_request(User.t() | user_id(), user_id()) ::
          {:ok, Friendship.t()}
          | {:error,
             :cannot_friend_self | :blocked | :already_friends | :already_requested | term()}
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
        # clean up any rejected same-direction rows to allow fresh request creation
        remove_rejected_same_direction(requester_id, target_id)

        cond do
          blocked?(requester_id, target_id) ->
            Repo.rollback(:blocked)

          already_friends?(requester_id, target_id) ->
            Repo.rollback(:already_friends)

          same_direction_pending?(requester_id, target_id) ->
            Repo.rollback(:already_requested)

          pending_reverse = find_pending_reverse(requester_id, target_id) ->
            # Roll back so accept_friend_request can use its own transaction
            Repo.rollback({:accept_reverse, pending_reverse.id})

          true ->
            insert_friend_request(requester_id, target_id)
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

        {:error, :already_requested} ->
          # Idempotent: return existing pending request instead of erroring
          case get_by_pair(requester_id, target_id) do
            %Friendship{status: "pending"} = f -> {:ok, f}
            _ -> {:error, :already_requested}
          end

        {:error, :already_friends} ->
          # Idempotent: return existing accepted friendship instead of erroring
          case already_friends?(requester_id, target_id) do
            %Friendship{} = f -> {:ok, f}
            _ -> {:error, :already_friends}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Direction-independent key so both A→B and B→A hash to the same lock.
  defp canonical_pair_id(a, b), do: [a, b] |> Enum.sort() |> Enum.join(":")

  defp remove_rejected_same_direction(requester_id, target_id) do
    case get_by_pair(requester_id, target_id) do
      %Friendship{status: "rejected"} = f ->
        _ = Repo.delete(f)
        _ = invalidate_friends_cache_pair(requester_id, target_id)
        :ok

      _ ->
        :ok
    end
  end

  # Extracted to reduce nesting depth in create_request/2 transaction.
  # Must be called inside a Repo.transaction.
  defp insert_friend_request(requester_id, target_id) do
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

  @doc """
  Check if either user has blocked the other.

  Returns `true` if a friendship row with status `"blocked"` exists in either
  direction between the two user IDs.
  """
  @spec blocked?(user_id(), user_id()) :: boolean()
  def blocked?(requester_id, target_id) do
    existing_same = get_by_pair(requester_id, target_id)
    existing_reverse = get_by_pair(target_id, requester_id)

    (existing_same && existing_same.status == "blocked") ||
      (existing_reverse && existing_reverse.status == "blocked")
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
      %Friendship{status: "accepted"} = f ->
        f

      _ ->
        case get_by_pair(target_id, requester_id) do
          %Friendship{status: "accepted"} = f -> f
          _ -> nil
        end
    end
  end

  defp same_direction_pending?(requester_id, target_id) do
    match?(%Friendship{status: "pending"}, get_by_pair(requester_id, target_id))
  end

  defp find_pending_reverse(requester_id, target_id) do
    case get_by_pair(target_id, requester_id) do
      %Friendship{status: "pending"} = f -> f
      _ -> nil
    end
  end

  @doc "Accept a friend request (only the target may accept). Returns {:ok, friendship}."
  @spec accept_friend_request(Ecto.UUID.t(), User.t()) :: {:ok, Friendship.t()} | {:error, term()}
  def accept_friend_request(friendship_id, %User{id: user_id}) when is_binary(friendship_id) do
    Gamend.AfterCommit.transaction(fn ->
      with %Friendship{} = f <- get_friendship(friendship_id),
           true <- f.target_id == user_id,
           true <- f.status == "pending",
           :ok <- check_friends_limit(f.requester_id),
           :ok <- check_friends_limit(f.target_id),
           {:ok, accepted} <- f |> Ecto.Changeset.change(status: "accepted") |> Repo.update() do
        # remove any reverse pending request if present
        Repo.delete_all(
          from ff in Friendship,
            where:
              ff.requester_id == ^f.target_id and ff.target_id == ^f.requester_id and
                ff.status == "pending"
        )

        _ = invalidate_friendship_cache(accepted.id)
        _ = invalidate_friends_cache_pair(accepted.requester_id, accepted.target_id)

        # broadcast accepted to both users
        broadcast_user(accepted.requester_id, {:friend_accepted, accepted})
        broadcast_user(accepted.target_id, {:friend_accepted, accepted})
        broadcast_all({:friend_accepted, accepted})
        # Its insert, push fan-out and `before_push_send` hook are not the
        # acceptance: they wait for the commit (`Gamend.AfterCommit`).
        Gamend.AfterCommit.defer(fn -> notify_friend_accepted(accepted) end)

        accepted
      else
        nil -> Repo.rollback(:not_found)
        false -> Repo.rollback(:not_authorized)
        {:error, :too_many_friends} -> Repo.rollback(:too_many_friends)
      end
    end)
  end

  @doc "Reject a friend request (only the target may reject). Returns {:ok, friendship}."
  @spec reject_friend_request(Ecto.UUID.t(), User.t()) :: {:ok, Friendship.t()} | {:error, term()}
  def reject_friend_request(friendship_id, %User{id: user_id}) when is_binary(friendship_id) do
    with %Friendship{} = f <- get_friendship(friendship_id),
         true <- f.target_id == user_id,
         true <- f.status == "pending",
         {:ok, rejected} <- f |> Ecto.Changeset.change(status: "rejected") |> Repo.update() do
      _ = invalidate_friendship_cache(rejected.id)
      _ = invalidate_friends_cache_pair(rejected.requester_id, rejected.target_id)

      # broadcast rejection
      broadcast_user(rejected.requester_id, {:friend_rejected, rejected})
      broadcast_user(rejected.target_id, {:friend_rejected, rejected})
      broadcast_all({:friend_rejected, rejected})
      notify_friend_rejected(rejected)

      {:ok, rejected}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_authorized}
      err -> err
    end
  end

  @doc "Cancel an outgoing friend request (only the requester may cancel)."
  @spec cancel_request(Ecto.UUID.t(), User.t()) ::
          {:ok, :cancelled} | {:error, :not_found | :not_authorized | term()}
  def cancel_request(friendship_id, %User{id: user_id}) when is_binary(friendship_id) do
    with %Friendship{} = f <- get_friendship(friendship_id),
         true <- f.requester_id == user_id,
         {:ok, _} <- Repo.delete(f) do
      _ = invalidate_friendship_cache(f.id)
      _ = invalidate_friends_cache_pair(f.requester_id, f.target_id)

      # broadcast cancellation
      broadcast_user(f.requester_id, {:request_cancelled, f})
      broadcast_user(f.target_id, {:request_cancelled, f})
      broadcast_all({:request_cancelled, f})
      retract_friend_request_notification(f)

      {:ok, :cancelled}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_authorized}
      err -> err
    end
  end

  @doc "Remove a friendship (either direction) - only participating users may call this."
  @spec remove_friend(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, Friendship.t()} | {:error, term()}
  def remove_friend(user_id, friend_id) when is_binary(user_id) and is_binary(friend_id) do
    case Repo.one(
           from f in Friendship,
             where:
               (f.requester_id == ^user_id and f.target_id == ^friend_id) or
                 (f.requester_id == ^friend_id and f.target_id == ^user_id),
             limit: 1
         ) do
      %Friendship{} = f ->
        result = Repo.delete(f)

        case result do
          {:ok, _} ->
            _ = invalidate_friendship_cache(f.id)
            _ = invalidate_friends_cache_pair(user_id, friend_id)

            # clean up friend chat messages and read cursors
            Gamend.Chat.cleanup_friend_chat(user_id, friend_id)

            # broadcast removal
            broadcast_user(user_id, {:friend_removed, f})
            broadcast_user(friend_id, {:friend_removed, f})
            broadcast_all({:friend_removed, f})
            result

          err ->
            err
        end

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Block an incoming request (only the target may block). Returns {:ok, friendship} with status \"blocked\"."
  @spec block_friend_request(Ecto.UUID.t(), User.t()) :: {:ok, Friendship.t()} | {:error, term()}
  def block_friend_request(friendship_id, %User{id: user_id}) when is_binary(friendship_id) do
    with %Friendship{} = f <- get_friendship(friendship_id),
         true <- f.target_id == user_id,
         true <- f.status in ["pending", "rejected"],
         {:ok, blocked} <- f |> Ecto.Changeset.change(status: "blocked") |> Repo.update() do
      _ = invalidate_friendship_cache(blocked.id)
      _ = invalidate_friends_cache_pair(blocked.requester_id, blocked.target_id)

      # broadcast blocked
      broadcast_user(blocked.requester_id, {:friend_blocked, blocked})
      broadcast_user(blocked.target_id, {:friend_blocked, blocked})
      broadcast_all({:friend_blocked, blocked})

      {:ok, blocked}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_authorized}
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
  @spec block_user(User.t(), user_id()) :: {:ok, Friendship.t()} | {:error, term()}
  def block_user(%User{id: blocker_id}, blocked_id) when is_binary(blocked_id) do
    if blocker_id == blocked_id do
      {:error, :cannot_block_self}
    else
      do_block_user(blocker_id, blocked_id)
    end
  end

  defp do_block_user(blocker_id, blocked_id) do
    Gamend.AfterCommit.transaction(fn ->
      # Drop the reverse row first: the pair is unique per direction, so a
      # reverse row would otherwise survive alongside the canonical block.
      Repo.delete_all(
        from f in Friendship,
          where: f.requester_id == ^blocker_id and f.target_id == ^blocked_id
      )

      result =
        case get_by_pair(blocked_id, blocker_id) do
          %Friendship{} = f ->
            f |> Ecto.Changeset.change(status: "blocked") |> Repo.update()

          nil ->
            %Friendship{}
            |> Friendship.changeset(%{
              requester_id: blocked_id,
              target_id: blocker_id,
              status: "blocked"
            })
            |> Repo.insert()
        end

      case result do
        {:ok, blocked} ->
          _ = invalidate_friendship_cache(blocked.id)
          _ = invalidate_friends_cache_pair(blocker_id, blocked_id)

          broadcast_user(blocker_id, {:friend_blocked, blocked})
          broadcast_user(blocked_id, {:friend_blocked, blocked})
          broadcast_all({:friend_blocked, blocked})

          blocked

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Unblock a user previously blocked via `block_user/2`.

  Returns `{:ok, :unblocked}`, or `{:error, :not_found}` when no block exists.
  """
  @spec unblock_user(User.t(), user_id()) :: {:ok, :unblocked} | {:error, term()}
  def unblock_user(%User{id: blocker_id}, blocked_id) when is_binary(blocked_id) do
    case get_by_pair(blocked_id, blocker_id) do
      %Friendship{status: "blocked"} = f ->
        with {:ok, _} <- Repo.delete(f) do
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
        f.status == "blocked" and f.requester_id in ^ids and
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
        where: f.target_id == ^user_id and f.status == "blocked",
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
    query = from f in Friendship, where: f.status == "blocked"

    case Keyword.get(opts, :user_id) do
      nil ->
        query

      "" ->
        query

      user_id ->
        from f in query,
          where: f.requester_id == ^user_id or f.target_id == ^user_id
    end
  end

  @doc """
  Remove a block by its friendship id, regardless of who created it.

  For admin use — `unblock_user/2` is the player-facing path and only lets the
  blocker lift their own block.
  """
  @spec delete_block(Ecto.UUID.t()) :: {:ok, :unblocked} | {:error, :not_found}
  def delete_block(friendship_id) when is_binary(friendship_id) do
    case get_friendship(friendship_id) do
      %Friendship{status: "blocked"} = f ->
        {:ok, _} = Repo.delete(f)

        _ = invalidate_friendship_cache(f.id)
        _ = invalidate_friends_cache_pair(f.requester_id, f.target_id)

        broadcast_user(f.requester_id, {:friend_unblocked, f})
        broadcast_user(f.target_id, {:friend_unblocked, f})
        broadcast_all({:friend_unblocked, f})

        {:ok, :unblocked}

      _ ->
        {:error, :not_found}
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
    query = from f in Friendship, where: f.status != "blocked"

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
        from f in query,
          where: f.requester_id == ^user_id or f.target_id == ^user_id
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
    case get_friendship(friendship_id) do
      %Friendship{status: "blocked"} ->
        {:error, :not_found}

      %Friendship{} = f ->
        {:ok, _} = Repo.delete(f)

        _ = invalidate_friendship_cache(f.id)
        _ = invalidate_friends_cache_pair(f.requester_id, f.target_id)

        # An accepted pair leaves a DM history behind, same as remove_friend/2.
        if f.status == "accepted" do
          Gamend.Chat.cleanup_friend_chat(f.requester_id, f.target_id)
        end

        # A cancelled request and a removed friendship are different events to
        # a connected client, so broadcast whichever the row actually was.
        event = if f.status == "pending", do: :request_cancelled, else: :friend_removed
        broadcast_user(f.requester_id, {event, f})
        broadcast_user(f.target_id, {event, f})
        broadcast_all({event, f})
        if f.status == "pending", do: retract_friend_request_notification(f)

        {:ok, :removed}

      nil ->
        {:error, :not_found}
    end
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
            f.status == "blocked" and
              ((f.requester_id == ^user_id and f.target_id in ^others) or
                 (f.target_id == ^user_id and f.requester_id in ^others))
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
        where: f.target_id == ^user_id and f.status == "blocked",
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
        where: f.target_id == ^user_id and f.status == "blocked",
        select: count(f.id)
    ) || 0
  end

  @doc "Unblock a previously-blocked friendship (only the user who blocked may unblock). Returns {:ok, :unblocked} on success."
  @spec unblock_friendship(Ecto.UUID.t(), User.t()) :: {:ok, :unblocked} | {:error, term()}
  def unblock_friendship(friendship_id, %User{id: user_id}) when is_binary(friendship_id) do
    with %Friendship{} = f <- get_friendship(friendship_id),
         true <- f.target_id == user_id,
         true <- f.status == "blocked",
         {:ok, _} <- Repo.delete(f) do
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
        where: f.status == "accepted" and f.requester_id == ^user_id,
        select: %{id: f.target_id}

    q2 =
      from f in Friendship,
        where: f.status == "accepted" and f.target_id == ^user_id,
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
            f.status == "accepted" and
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
        where: f.status == "accepted" and f.requester_id == ^user_id,
        select: %{id: f.target_id}

    q2 =
      from f in Friendship,
        where: f.status == "accepted" and f.target_id == ^user_id,
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
        where: f.target_id == ^user_id and f.status == "pending",
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
        where: f.target_id == ^user_id and f.status == "pending",
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
        where: f.requester_id == ^user_id and f.status == "pending",
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
        where: f.requester_id == ^user_id and f.status == "pending",
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
        where: f.status == "accepted" and f.requester_id == ^user_id,
        select: f.target_id

    q2 =
      from f in Friendship,
        where: f.status == "accepted" and f.target_id == ^user_id,
        select: f.requester_id

    union_all(q1, ^q2) |> Repo.all()
  end

  defp check_friends_limit(user_id) do
    max_friends = Gamend.Limits.get(:max_friends_per_user)
    current = count_friends_for_user(user_id)

    if current >= max_friends do
      {:error, :too_many_friends}
    else
      :ok
    end
  end
end
