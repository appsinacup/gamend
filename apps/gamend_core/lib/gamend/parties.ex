defmodule Gamend.Parties do
  @moduledoc """
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
  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: Gamend.Cache

  require Logger

  alias Gamend.Accounts
  alias Gamend.Accounts.PasswordHash
  alias Gamend.Accounts.PresenceStatus
  alias Gamend.Accounts.User
  alias Gamend.Friends
  alias Gamend.Groups
  alias Gamend.Lobbies
  alias Gamend.Lobbies.Lobby
  alias Gamend.Lock
  alias Gamend.Parties.Party
  alias Gamend.Parties.PartyInvite
  alias Gamend.Repo

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @doc "Subscribe to events for a specific party."
  @spec subscribe_party(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_party(party_id) do
    Phoenix.PubSub.subscribe(Gamend.PubSub, "party:#{party_id}")
  end

  @doc "Unsubscribe from a party's events."
  @spec unsubscribe_party(Ecto.UUID.t()) :: :ok
  def unsubscribe_party(party_id) do
    Phoenix.PubSub.unsubscribe(Gamend.PubSub, "party:#{party_id}")
  end

  # Preload members once so per-socket channel serialization reuses them
  # instead of each subscriber re-querying get_party_members/1.
  defp with_party_members(%Party{} = party) do
    %{party | members: get_party_members(party.id)}
  end

  defp broadcast_party(party_id, event) do
    Gamend.Broadcast.publish("party:#{party_id}", event)
  end

  @doc "Broadcast a member presence event (online/offline) to a party's PubSub topic."
  @spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
  def broadcast_member_presence(party_id, event) do
    broadcast_party(party_id, event)
  end

  # ---------------------------------------------------------------------------
  # Cache helpers
  # ---------------------------------------------------------------------------

  defp party_invite_cache_version(user_id) when is_binary(user_id) do
    Gamend.Cache.get!({:party_invites, :version, user_id}) || 1
  end

  defp invalidate_party_invite_cache(user_id) when is_binary(user_id) do
    _ = Gamend.Cache.bump_version({:party_invites, :version, user_id})
    :ok
  end

  # Party-row cache: get_party is keyed by a version bumped on every party-row
  # write. Membership/invite changes don't touch the party row, so they don't bump.
  defp party_cache_version, do: Gamend.Cache.get!({:parties, :version}) || 1

  @doc """
  Aggregate party counts for the public stats endpoint.

  Membership is a user column (`users.party_id`, indexed), so both numbers are
  derived counts rather than a maintained size.
  """
  @spec stats() :: %{parties_active: non_neg_integer(), players_in_parties: non_neg_integer()}
  def stats do
    Gamend.Cache.cached({:parties, :stats}, [ttl: Gamend.Cache.ttl()], fn ->
      %{
        parties_active: Repo.aggregate(Party, :count, :id),
        players_in_parties: Accounts.count_users_in_parties()
      }
    end)
  end

  defp tap_bump_party({:ok, _} = result) do
    _ = Gamend.Cache.bump_version({:parties, :version})
    result
  end

  defp tap_bump_party(other), do: other

  # Cancel all pending invites for a party (used when party is disbanded/deleted).
  # Invalidates invite caches for all affected senders and recipients.
  defp cancel_pending_invites_for_party(party_id) do
    pending =
      from(i in PartyInvite,
        where: i.party_id == ^party_id and i.status == "pending",
        select: {i.sender_id, i.recipient_id}
      )
      |> Repo.all()

    if pending != [] do
      from(i in PartyInvite,
        where: i.party_id == ^party_id and i.status == "pending"
      )
      |> Repo.update_all(set: [status: "cancelled", updated_at: DateTime.utc_now()])

      user_ids = pending |> Enum.flat_map(fn {s, r} -> [s, r] end) |> Enum.uniq()

      for uid <- user_ids do
        invalidate_party_invite_cache(uid)
      end
    end

    :ok
  end

  # Cancel pending invites involving a user in a specific party.
  # Called when a member leaves or is kicked, so their pending invites are cleaned up.
  defp cancel_pending_invites_for_user_in_party(user_id, party_id) do
    pending =
      from(i in PartyInvite,
        where:
          i.party_id == ^party_id and i.status == "pending" and
            (i.sender_id == ^user_id or i.recipient_id == ^user_id),
        select: {i.sender_id, i.recipient_id}
      )
      |> Repo.all()

    if pending != [] do
      from(i in PartyInvite,
        where:
          i.party_id == ^party_id and i.status == "pending" and
            (i.sender_id == ^user_id or i.recipient_id == ^user_id)
      )
      |> Repo.update_all(set: [status: "cancelled", updated_at: DateTime.utc_now()])

      user_ids = pending |> Enum.flat_map(fn {s, r} -> [s, r] end) |> Enum.uniq()

      for uid <- user_ids do
        invalidate_party_invite_cache(uid)
      end
    end

    :ok
  end

  # Cancel pending invites to a user from parties OTHER than the one they just joined.
  # Called after accept_party_invite so stale invites from other parties are cleaned up.
  defp cancel_other_pending_invites_for_user(user_id, joined_party_id) do
    pending =
      from(i in PartyInvite,
        where:
          i.recipient_id == ^user_id and i.party_id != ^joined_party_id and
            i.status == "pending",
        select: {i.sender_id, i.party_id}
      )
      |> Repo.all()

    if pending != [] do
      from(i in PartyInvite,
        where:
          i.recipient_id == ^user_id and i.party_id != ^joined_party_id and
            i.status == "pending"
      )
      |> Repo.update_all(set: [status: "cancelled", updated_at: DateTime.utc_now()])

      sender_ids = pending |> Enum.map(fn {s, _} -> s end) |> Enum.uniq()

      for sender_id <- sender_ids do
        invalidate_party_invite_cache(sender_id)
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  @doc "Get a party by ID. Returns nil if not found."
  @spec get_party(Ecto.UUID.t()) :: Party.t() | nil
  @decorate cacheable(
              key: {:parties, :get, party_cache_version(), id},
              match: &(&1 != nil),
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_party(id), do: Repo.get_uuid(Party, id)

  @doc "Get a party by ID. Raises if not found."
  @spec get_party!(Ecto.UUID.t()) :: Party.t()
  def get_party!(id) do
    case get_party(id) do
      %Party{} = party -> party
      nil -> raise Ecto.NoResultsError, queryable: Party
    end
  end

  @doc """
  Whether `user` holds authority over `party` — its leader, nobody else.

  Subject first, resource second, like every other `can_*?` predicate (see
  `Gamend.Policy`). The party takes a struct or a bare id; passing the user's
  own `party_id` is the common case.
  """
  @spec can_manage_party?(User.t() | nil, Party.t() | Ecto.UUID.t() | nil) :: boolean()
  def can_manage_party?(%User{id: user_id}, %Party{leader_id: leader_id}),
    do: user_id == leader_id

  def can_manage_party?(%User{} = user, party_id) when is_binary(party_id) do
    case get_party(party_id) do
      %Party{} = party -> can_manage_party?(user, party)
      _ -> false
    end
  end

  def can_manage_party?(_user, _party), do: false

  @doc "Get all members of a party."
  @spec get_party_members(Party.t() | Ecto.UUID.t()) :: [User.t()]
  def get_party_members(%Party{id: party_id}), do: get_party_members(party_id)

  def get_party_members(party_id) when is_binary(party_id) do
    Repo.all(
      from u in User,
        where: u.party_id == ^party_id,
        order_by: [asc: u.inserted_at]
    )
  end

  @doc "Count members in a party."
  @spec count_party_members(Ecto.UUID.t()) :: non_neg_integer()
  def count_party_members(party_id) when is_binary(party_id) do
    Repo.one(from u in User, where: u.party_id == ^party_id, select: count(u.id)) || 0
  end

  @doc "Count total members across all parties."
  @spec count_all_party_members() :: non_neg_integer()
  def count_all_party_members do
    Repo.one(from u in User, where: not is_nil(u.party_id), select: count(u.id)) || 0
  end

  @doc "Get the party the user is currently in, or nil."
  @spec get_user_party(User.t()) :: Party.t() | nil
  def get_user_party(%User{party_id: nil}), do: nil

  def get_user_party(%User{party_id: party_id}) when is_binary(party_id) do
    get_party(party_id)
  end

  # ---------------------------------------------------------------------------
  # Create
  # ---------------------------------------------------------------------------

  @doc """
  Create a new party. The user becomes the leader and first member.

  Returns `{:error, :already_in_party}` if the user is already in a party.
  """
  @spec create_party(User.t(), map()) :: {:ok, Party.t()} | {:error, term()}
  def create_party(%User{} = user, attrs \\ %{}) do
    attrs =
      attrs
      |> normalize_params()
      |> Map.put("leader_id", user.id)

    case Gamend.Hooks.internal_call(:before_party_create, [user, attrs]) do
      {:ok, attrs} -> do_create_party(user, attrs)
      {:error, reason} -> {:error, {:hook_rejected, reason}}
    end
  end

  defp do_create_party(user, attrs) do
    Lock.serialize(:party, user.id, fn ->
      # Lock on the user's id to prevent concurrent party creation

      # Use Repo.get directly instead of cached Accounts.get_user/1.
      # The cached version would seed the cache with party_id=nil inside
      # the transaction, enabling a concurrent @decorate cacheable put
      # of stale data to land after our post-commit cache invalidation.
      fresh_user = Repo.get(User, user.id)

      if fresh_user.party_id != nil do
        Repo.rollback(:already_in_party)
      end

      case %Party{} |> Party.changeset(attrs) |> Repo.insert() |> tap_bump_party() do
        {:ok, party} ->
          case fresh_user |> Ecto.Changeset.change(%{party_id: party.id}) |> Repo.update() do
            {:ok, updated_user} ->
              {party, updated_user}

            {:error, reason} ->
              Repo.rollback(reason)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, {party, updated_user}} ->
        # Write the correct value to cache to prevent stale concurrent puts.
        Accounts.cache_user(updated_user)
        broadcast_parties({:party_created, party.id})

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_party_create, [party])
        end)

        {:ok, party}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Invitations
  # ---------------------------------------------------------------------------

  @doc """
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
  @spec invite_to_party(User.t(), Ecto.UUID.t()) :: {:ok, PartyInvite.t()} | {:error, atom()}
  def invite_to_party(%User{} = leader, target_user_id) when is_binary(target_user_id) do
    leader = Accounts.get_user(leader.id)

    with :ok <- check_in_party(leader),
         {:ok, party} <- fetch_party(leader.party_id),
         :ok <- check_is_leader(party, leader),
         {:ok, target} <- fetch_invite_target(target_user_id),
         :ok <- check_not_blocked_by_party(party.id, target_user_id),
         :ok <- check_leader_connected_to_target(leader.id, target_user_id),
         :ok <- check_no_pending_invite(leader.id, target_user_id),
         :ok <- check_max_pending_invites(target_user_id),
         :ok <- delete_stale_invites(leader.id, target_user_id) do
      case %PartyInvite{}
           |> PartyInvite.changeset(%{
             party_id: party.id,
             sender_id: leader.id,
             recipient_id: target_user_id
           })
           |> Repo.insert() do
        {:ok, invite} ->
          # Send an informational notification (independent of the invite record)
          Gamend.Notifications.admin_create_notification(leader.id, target_user_id, %{
            "title" => "Party invite from #{Gamend.Accounts.display_name(leader)}",
            "content" => "",
            "metadata" => %{
              "type" => "party_invite",
              "party_id" => party.id,
              "sender_name" => Gamend.Accounts.display_name(leader),
              "recipient_name" => Gamend.Accounts.display_name(target)
            }
          })

          invalidate_party_invite_cache(leader.id)
          invalidate_party_invite_cache(target_user_id)

          {:ok, invite}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :already_invited} ->
        # No-op: return the existing pending invite instead of erroring
        existing =
          Repo.one(
            from(i in PartyInvite,
              where:
                i.sender_id == ^leader.id and i.recipient_id == ^target_user_id and
                  i.status == "pending"
            )
          )

        {:ok, existing}

      other ->
        other
    end
  end

  defp delete_stale_invites(sender_id, recipient_id) do
    from(i in PartyInvite,
      where:
        i.sender_id == ^sender_id and i.recipient_id == ^recipient_id and
          i.status != "pending"
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Cancel a previously sent party invite. Only the original sender (leader) can cancel.
  """
  @spec cancel_party_invite(User.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def cancel_party_invite(%User{} = leader, target_user_id) when is_binary(target_user_id) do
    leader = Accounts.get_user(leader.id)

    with :ok <- check_in_party(leader),
         {:ok, party} <- fetch_party(leader.party_id),
         :ok <- check_is_leader(party, leader) do
      {deleted_count, _} =
        from(i in PartyInvite,
          where:
            i.sender_id == ^leader.id and i.recipient_id == ^target_user_id and
              i.status == "pending"
        )
        |> Repo.delete_all()

      invalidate_party_invite_cache(leader.id)
      invalidate_party_invite_cache(target_user_id)

      # Only retract notification and broadcast if invites were actually deleted.
      # Without this guard, a cancel-then-invite "refresh" pattern would send
      # a spurious party_invite_cancelled event to the recipient even when no
      # prior invite existed.
      if deleted_count > 0 do
        leader_name = Gamend.Accounts.display_name(leader)

        Gamend.Notifications.delete_notification_by(
          leader.id,
          target_user_id,
          "Party invite from #{leader_name}"
        )

        Gamend.Broadcast.publish(
          "user:#{target_user_id}",
          {:party_invite_cancelled, %{party_id: party.id, user_id: leader.id}}
        )
      end

      :ok
    end
  end

  @doc """
  Accept a party invite. Joins the party and marks the invite as accepted.

  If the user is already in another party, they automatically leave it first
  (disbanding if they are the leader).

  Returns `{:error, :no_invite}` if no pending invite exists for that party.
  """
  @spec accept_party_invite(User.t(), Ecto.UUID.t()) :: {:ok, Party.t()} | {:error, atom()}
  def accept_party_invite(%User{} = user, party_id) when is_binary(party_id) do
    user = Accounts.get_user(user.id)

    invite =
      Repo.one(
        from i in PartyInvite,
          where:
            i.recipient_id == ^user.id and i.party_id == ^party_id and
              i.status == "pending",
          limit: 1
      )

    if is_nil(invite) do
      {:error, :no_invite}
    else
      with {:ok, user} <- ensure_left_current_party(user),
           {:ok, party} <- fetch_party(party_id),
           :ok <- check_not_blocked_by_party(party_id, user.id),
           {:ok, _} <- Gamend.Hooks.internal_call(:before_party_join, [user, party]),
           # Claim the invite before joining, not after.
           #
           # The invite was read at the top, then several steps ran — including
           # the `before_party_join` hook, which may take up to the hook timeout
           # — and the join never looked at it again. A leader cancelling in
           # that window *deleted* the row, the join proceeded regardless, and
           # `finalize_accept_invite/4`'s `update_all` matched zero rows and
           # said nothing: the leader was told someone joined their party who no
           # longer had an invite to it. Claiming first makes the state
           # transition the thing that authorises the join.
           :ok <- claim_party_invite(user.id, party_id),
           {:ok, updated_user} <- do_join_party(user, party_id) do
        result = finalize_accept_invite(user, invite, party_id, party)

        # Final cache invalidation to clear any stale writes from concurrent
        # processes (e.g. Guardian pipeline calls to Accounts.get_user/1) whose
        # DB read happened before do_join_party committed but whose Cache.put
        # landed after do_join_party's cache delete.
        invalidate_user_cache(updated_user.id)

        result
      else
        {:error, :party_full} = error ->
          # The party filled up between the invite and acceptance.
          # Mark the invite as declined, notify both parties, and return the error.
          handle_accept_capacity_failure(user, invite, party_id, "party_full")
          error

        other ->
          other
      end
    end
  end

  defp handle_accept_capacity_failure(user, invite, party_id, reason_str) do
    user_name = Gamend.Accounts.display_name(user)

    # Mark the invite as declined so the sender knows it didn't go through.
    #
    # Matches `pending` *or* `accepted`: `accept_party_invite/2` claims the
    # invite before attempting the join (so a cancelled invite cannot be
    # consumed), which means a join that then fails on capacity has to release
    # the claim it took.
    from(i in PartyInvite,
      where:
        i.recipient_id == ^user.id and i.party_id == ^party_id and
          i.status in ["pending", "accepted"]
    )
    |> Repo.update_all(set: [status: "declined", updated_at: DateTime.utc_now()])

    invalidate_party_invite_cache(user.id)
    invalidate_party_invite_cache(invite.sender_id)

    # Retract the original invite notification
    sender = Gamend.Accounts.get_user(invite.sender_id)
    sender_name = Gamend.Accounts.display_name(sender)

    Gamend.Notifications.delete_notification_by(
      invite.sender_id,
      user.id,
      "Party invite from #{sender_name}"
    )

    # Notify the sender that the invite was declined because the party is full
    Gamend.Notifications.admin_create_notification(
      user.id,
      invite.sender_id,
      %{
        "title" => "#{user_name} couldn't join — party full",
        "content" => "",
        "metadata" => %{
          "type" => "party_invite_declined",
          "party_id" => party_id,
          "user_id" => user.id,
          "user_name" => user_name,
          "reason" => reason_str
        }
      }
    )

    # Real-time PubSub so the sender's UI updates immediately
    Gamend.Broadcast.publish(
      "user:#{invite.sender_id}",
      {:party_invite_declined, %{party_id: party_id, user_id: user.id, reason: reason_str}}
    )
  end

  defp ensure_left_current_party(%User{party_id: nil} = user), do: {:ok, user}

  defp ensure_left_current_party(%User{} = user) do
    case leave_party(user) do
      # Use Repo.get directly instead of cached Accounts.get_user/1.
      # The cached version would store the intermediate party_id=nil state,
      # which combined with concurrent requests can poison the cache
      # (a concurrent @decorate cacheable put of the nil value can land after
      # do_join_party's cache delete, leaving stale data behind).
      {:ok, _} -> {:ok, Repo.get(User, user.id)}
      {:error, reason} -> {:error, {:leave_failed, reason}}
    end
  end

  # Compare-and-set on the invite: pending → accepted, or nothing.
  #
  # Returns `{:error, :no_invite}` when it matched no rows, which is what makes
  # a cancelled (or already-consumed) invite stop the join instead of being
  # discovered afterwards.
  defp claim_party_invite(user_id, party_id) do
    {count, _} =
      from(i in PartyInvite,
        where:
          i.recipient_id == ^user_id and i.party_id == ^party_id and
            i.status == "pending"
      )
      |> Repo.update_all(set: [status: "accepted", updated_at: DateTime.utc_now()])

    if count > 0, do: :ok, else: {:error, :no_invite}
  end

  defp finalize_accept_invite(user, invite, party_id, party) do
    # The invite was already claimed by `claim_party_invite/2` above.
    invalidate_party_invite_cache(user.id)
    invalidate_party_invite_cache(invite.sender_id)

    # Cancel pending invites to this user from OTHER parties
    cancel_other_pending_invites_for_user(user.id, party_id)

    # Retract the invite notification for the accepting user
    sender = Gamend.Accounts.get_user(invite.sender_id)
    sender_name = Gamend.Accounts.display_name(sender)

    Gamend.Notifications.delete_notification_by(
      invite.sender_id,
      user.id,
      "Party invite from #{sender_name}"
    )

    # Notify the leader that the invite was accepted
    user_name = Gamend.Accounts.display_name(user)

    Gamend.Notifications.admin_create_notification(
      user.id,
      invite.sender_id,
      %{
        "title" => "#{user_name} joined your party",
        "content" => "",
        "metadata" => %{
          "type" => "party_invite_accepted",
          "party_id" => party_id,
          "user_id" => user.id,
          "user_name" => user_name
        }
      }
    )

    # Notify the sender that the invite was accepted via PubSub
    Gamend.Broadcast.publish(
      "user:#{invite.sender_id}",
      {:party_invite_accepted, %{party_id: party_id, user_id: user.id}}
    )

    Gamend.Async.run(fn ->
      Gamend.Hooks.internal_call(:after_party_join, [user, party])
    end)

    {:ok, party}
  end

  @doc """
  Decline a party invite. Marks the invite as declined.
  """
  @spec decline_party_invite(User.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def decline_party_invite(%User{} = user, party_id) when is_binary(party_id) do
    user = Accounts.get_user(user.id)

    # Fetch sender_ids before updating so we can invalidate their caches
    sender_ids =
      from(i in PartyInvite,
        where:
          i.recipient_id == ^user.id and i.party_id == ^party_id and
            i.status == "pending",
        select: i.sender_id
      )
      |> Repo.all()

    from(i in PartyInvite,
      where:
        i.recipient_id == ^user.id and i.party_id == ^party_id and
          i.status == "pending"
    )
    |> Repo.update_all(set: [status: "declined", updated_at: DateTime.utc_now()])

    invalidate_party_invite_cache(user.id)
    Enum.each(sender_ids, &invalidate_party_invite_cache/1)

    # Notify each sender that the invite was declined
    user_name = Gamend.Accounts.display_name(user)

    Enum.each(sender_ids, fn sender_id ->
      # Retract the invite notification
      sender = Gamend.Accounts.get_user(sender_id)
      sender_name = Gamend.Accounts.display_name(sender)

      Gamend.Notifications.delete_notification_by(
        sender_id,
        user.id,
        "Party invite from #{sender_name}"
      )

      # Notify the leader that the invite was declined
      Gamend.Notifications.admin_create_notification(
        user.id,
        sender_id,
        %{
          "title" => "#{user_name} declined your party invite",
          "content" => "",
          "metadata" => %{
            "type" => "party_invite_declined",
            "party_id" => party_id,
            "user_id" => user.id,
            "user_name" => user_name
          }
        }
      )

      Gamend.Broadcast.publish(
        "user:#{sender_id}",
        {:party_invite_declined, %{party_id: party_id, user_id: user.id}}
      )
    end)

    :ok
  end

  @doc """
  List pending party invites for the given user.
  """
  @spec list_party_invitations(User.t(), keyword()) :: [map()]
  def list_party_invitations(%User{} = user, opts \\ []) do
    do_list_party_invitations(user.id, Keyword.get(opts, :page), Keyword.get(opts, :page_size))
  end

  @doc "How many pending party invites the user has, for paging."
  @spec count_party_invitations(User.t()) :: non_neg_integer()
  def count_party_invitations(%User{id: user_id}) do
    Repo.aggregate(
      from(i in PartyInvite, where: i.recipient_id == ^user_id and i.status == "pending"),
      :count
    )
  end

  @decorate cacheable(
              key:
                {:party_invites, :list, party_invite_cache_version(user_id), user_id, page,
                 page_size},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp do_list_party_invitations(user_id, page, page_size) do
    from(i in PartyInvite,
      where: i.recipient_id == ^user_id and i.status == "pending",
      join: s in assoc(i, :sender),
      join: r in assoc(i, :recipient),
      order_by: [desc: i.inserted_at],
      preload: [sender: s, recipient: r]
    )
    |> Gamend.Query.page(page: page, page_size: page_size)
    |> Repo.all()
    |> Enum.map(&serialize_party_invite/1)
  end

  @doc """
  List pending party invites sent by the given leader.

  Returns invitations the leader has sent that have not yet been accepted or declined.
  """
  @spec list_sent_party_invitations(User.t(), keyword()) :: [map()]
  def list_sent_party_invitations(%User{} = leader, opts \\ []) do
    do_list_sent_party_invitations(
      leader.id,
      Keyword.get(opts, :page),
      Keyword.get(opts, :page_size)
    )
  end

  @doc "How many pending party invites the leader has sent, for paging."
  @spec count_sent_party_invitations(User.t()) :: non_neg_integer()
  def count_sent_party_invitations(%User{id: leader_id}) do
    Repo.aggregate(
      from(i in PartyInvite, where: i.sender_id == ^leader_id and i.status == "pending"),
      :count
    )
  end

  @decorate cacheable(
              key:
                {:party_invites, :list_sent, party_invite_cache_version(leader_id), leader_id,
                 page, page_size},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp do_list_sent_party_invitations(leader_id, page, page_size) do
    from(i in PartyInvite,
      where: i.sender_id == ^leader_id and i.status == "pending",
      join: s in assoc(i, :sender),
      join: r in assoc(i, :recipient),
      order_by: [desc: i.inserted_at],
      preload: [sender: s, recipient: r]
    )
    |> Gamend.Query.page(page: page, page_size: page_size)
    |> Repo.all()
    |> Enum.map(&serialize_party_invite/1)
  end

  defp serialize_party_invite(invite) do
    %{
      id: invite.id,
      party_id: invite.party_id,
      sender_id: invite.sender_id,
      sender_name: Gamend.Accounts.display_name(invite.sender),
      recipient_id: invite.recipient_id,
      recipient_name: Gamend.Accounts.display_name(invite.recipient),
      status: invite.status,
      inserted_at: invite.inserted_at
    }
  end

  defp fetch_invite_target(target_user_id) do
    case Accounts.get_user(target_user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  # A block in either direction keeps the pair apart, so every current member is
  # checked, not just the leader — mirroring `Lobbies.join_lobby/2`. Checked on
  # both invite and accept because membership can change in between.
  defp check_not_blocked_by_party(party_id, user_id) do
    member_ids = party_id |> get_party_members() |> Enum.map(& &1.id)

    if Friends.any_blocked?(user_id, member_ids), do: {:error, :blocked}, else: :ok
  end

  defp check_leader_connected_to_target(leader_id, target_user_id) do
    if Friends.friends?(leader_id, target_user_id) ||
         Groups.shared_group_member?(leader_id, target_user_id) do
      :ok
    else
      {:error, :not_connected}
    end
  end

  defp check_no_pending_invite(leader_id, target_user_id) do
    exists =
      Repo.exists?(
        from i in PartyInvite,
          where:
            i.sender_id == ^leader_id and i.recipient_id == ^target_user_id and
              i.status == "pending"
      )

    if exists, do: {:error, :already_invited}, else: :ok
  end

  defp check_max_pending_invites(target_user_id) do
    max = Gamend.Limits.get(:max_party_pending_invites)

    count =
      Repo.one(
        from(i in PartyInvite,
          where: i.recipient_id == ^target_user_id and i.status == "pending",
          select: count(i.id)
        )
      ) || 0

    if count >= max, do: {:error, :too_many_pending_invites}, else: :ok
  end

  # ---------------------------------------------------------------------------
  # Join (internal — used by accept_party_invite)
  # ---------------------------------------------------------------------------

  defp fetch_party(party_id) do
    case get_party(party_id) do
      nil -> {:error, :party_not_found}
      %Party{} = party -> {:ok, party}
    end
  end

  defp do_join_party(user, party_id) do
    # Wrap in a transaction with advisory lock to prevent TOCTOU race
    # conditions on PostgreSQL (two concurrent joins both passing the
    # count check before either updates).
    #
    # IMPORTANT: Cache invalidation and PubSub broadcasts MUST happen
    # after the transaction commits. If they fire inside the transaction,
    # other processes may read the DB (different connection, READ COMMITTED)
    # before the commit and re-populate the cache with stale data (e.g.
    # party_id still nil), causing "not_a_member" errors on subsequent
    # channel joins or API calls.
    Lock.serialize(:party, party_id, fn ->
      # Re-check space inside the lock
      count = count_party_members(party_id)
      party = get_party(party_id)

      # Re-read the joiner too, and refuse if they are already in a party.
      #
      # `do_create_party/2` locks `(:party, user.id)` while this locks
      # `(:party, party_id)` — disjoint critical sections, so a client firing
      # `POST /parties` and an invite accept together could have both commit:
      # the create wrote `users.party_id = new_party`, then this overwrote it
      # with the other party, leaving a zero-member party whose `leader_id`
      # still pointed at them. Because that column is uniquely indexed, they
      # then could not create a party again until retention swept the orphan.
      fresh_user = Repo.get(User, user.id)

      cond do
        is_nil(fresh_user) ->
          Repo.rollback(:not_found)

        is_binary(fresh_user.party_id) and fresh_user.party_id != party_id ->
          Repo.rollback(:already_in_party)

        party && count >= party.max_size ->
          Repo.rollback(:party_full)

        true ->
          case fresh_user
               |> Ecto.Changeset.change(%{party_id: party_id})
               |> Repo.update() do
            {:ok, updated_user} ->
              updated_user

            {:error, reason} ->
              Repo.rollback(reason)
          end
      end
    end)
    |> case do
      {:ok, updated_user} ->
        # Post-commit: now safe to invalidate cache and broadcast because
        # the party_id change is visible to all DB connections.
        invalidate_user_cache(updated_user.id)

        # Also write the correct value into cache.  This narrows the window
        # for a stale concurrent @decorate cacheable put (which read
        # party_id=nil from DB before this commit) from overwriting our
        # delete.  A final invalidation in accept_party_invite closes the
        # remaining gap.
        Accounts.cache_user(updated_user)

        _ = Accounts.broadcast_user_update(updated_user)
        _ = Accounts.broadcast_member_update(updated_user)
        broadcast_party(party_id, {:party_member_joined, party_id, updated_user.id})

        # The party's open ready board, if any, must cover the new member.
        _ = Gamend.ReadyChecks.add_party_member(party_id, updated_user.id)

        {:ok, updated_user}

      {:error, _reason} = error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Leave
  # ---------------------------------------------------------------------------

  @doc """
  Leave the current party.

  A leader leaving HANDS THE PARTY OVER to the longest-present remaining member,
  the way a lobby migrates its host — the party outliving one player is the
  point of it. Regular members are simply removed, and whoever leaves last takes
  the party with them, since there is nobody to hand it to.

  To end a party outright rather than leave it, call `disband/1`.
  """
  @spec leave_party(User.t()) :: {:ok, :left | :disbanded} | {:error, term()}
  def leave_party(%User{} = user) do
    user = Accounts.get_user(user.id)

    if is_nil(user.party_id) do
      {:error, :not_in_party}
    else
      party = get_party(user.party_id)

      if is_nil(party) do
        # Stale reference, just clear it
        clear_party_id(user)
        {:ok, :left}
      else
        if party.leader_id == user.id do
          hand_over_or_disband(user, party)
        else
          remove_member(user, party.id)
        end
      end
    end
  end

  @doc """
  Disband a party outright: clears every member's `party_id`, cancels pending
  invites, deletes the row, and broadcasts as a leader-initiated disband would.

  For callers acting on the party rather than on behalf of a member — the
  retention sweep for parties everyone has abandoned. Members leaving is
  `leave_party/1`.
  """
  @spec disband(Party.t()) :: {:ok, term()} | {:error, term()}
  def disband(%Party{} = party), do: disband_party(party)

  @doc """
  Kick a member from the party. Only the leader can kick.
  """
  @spec kick_member(User.t(), Ecto.UUID.t()) :: {:ok, User.t()} | {:error, term()}
  def kick_member(%User{} = leader, target_user_id) when is_binary(target_user_id) do
    leader = Accounts.get_user(leader.id)

    with :ok <- check_in_party(leader),
         {:ok, party} <- fetch_party(leader.party_id),
         :ok <- check_is_leader(party, leader),
         :ok <- check_not_self_kick(leader, target_user_id),
         {:ok, target} <- fetch_kick_target(target_user_id, party),
         {:ok, _} <- Gamend.Hooks.internal_call(:before_party_kick, [target, leader, party]) do
      case do_kick_member(target, party) do
        {:ok, _updated} = result ->
          Gamend.Async.run(fn ->
            Gamend.Hooks.internal_call(:after_party_kick, [target, leader, party])
          end)

          result

        error ->
          error
      end
    end
  end

  defp check_in_party(%User{party_id: nil}), do: {:error, :not_in_party}
  defp check_in_party(%User{}), do: :ok

  defp check_is_leader(%Party{leader_id: leader_id}, %User{id: user_id})
       when leader_id != user_id,
       do: {:error, :not_leader}

  defp check_is_leader(%Party{}, %User{}), do: :ok

  defp check_no_members_in_lobby(members) do
    if Enum.any?(members, fn m -> m.lobby_id != nil end) do
      {:error, :member_in_lobby}
    else
      :ok
    end
  end

  # "Recently active" means online, or last seen inside the grace window — this
  # avoids false negatives from brief disconnects and heartbeat delays. The
  # window and the rule live in Accounts.PresenceStatus so this check and the
  # three-state one the UI draws cannot drift apart; they used to be separate
  # copies that merely happened to agree on 300 seconds.
  defp check_all_members_online(members) do
    if Enum.all?(members, &PresenceStatus.active?/1) do
      :ok
    else
      {:error, :members_offline}
    end
  end

  defp check_not_self_kick(%User{id: id}, id), do: {:error, :cannot_kick_self}
  defp check_not_self_kick(%User{}, _target_id), do: :ok

  defp fetch_kick_target(target_user_id, party) do
    case Accounts.get_user(target_user_id) do
      nil -> {:error, :user_not_found}
      %User{party_id: party_id} when party_id != party.id -> {:error, :not_in_party}
      %User{} = target -> {:ok, target}
    end
  end

  defp do_kick_member(target, party) do
    result =
      target
      |> Ecto.Changeset.change(%{party_id: nil})
      |> Repo.update()

    case result do
      {:ok, updated} ->
        invalidate_user_cache(updated.id)
        cancel_pending_invites_for_user_in_party(updated.id, party.id)
        _ = Accounts.broadcast_user_update(updated)
        _ = Accounts.broadcast_member_update(updated)
        broadcast_party(party.id, {:party_member_left, party.id, updated.id})
        _ = Gamend.ReadyChecks.remove_party_member(party.id, updated.id)

        # Notify the kicked user
        Gamend.Notifications.admin_create_notification(
          party.leader_id,
          target.id,
          %{
            "title" => "Removed from party",
            "content" => "",
            "metadata" => %{
              "type" => "party_kicked",
              "party_id" => party.id
            }
          }
        )

        {:ok, updated}

      error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Update party
  # ---------------------------------------------------------------------------

  # `Party.changeset/2` casts `leader_id`, which is server-owned: the controller
  # forwarded every parameter, so a leader could name anyone as leader. Every
  # leader-only operation resolves the party from `user.party_id`, so pointing
  # `leader_id` at a non-member left the party with nobody able to kick,
  # disband, invite or run a ready check — and the unique index on the column
  # then blocked that person from ever creating a party of their own.
  @client_party_fields ~w(max_size metadata)

  @doc """
  Update party settings. Only the leader can update.
  """
  @spec update_party(User.t(), map()) :: {:ok, Party.t()} | {:error, term()}
  def update_party(%User{} = user, attrs) do
    user = Accounts.get_user(user.id)

    with :ok <- check_in_party(user),
         {:ok, party} <- fetch_party(user.party_id),
         :ok <- check_is_leader(party, user) do
      attrs = attrs |> normalize_params() |> Map.take(@client_party_fields)
      validate_and_update_party(party, attrs)
    end
  end

  defp validate_and_update_party(party, attrs) do
    new_max = Map.get(attrs, "max_size")

    if new_max do
      count = count_party_members(party.id)
      new_max_int = to_int_or_nil(new_max) || 0

      if new_max_int < count do
        {:error, :too_small}
      else
        do_update_party(party, attrs)
      end
    else
      do_update_party(party, attrs)
    end
  end

  defp do_update_party(party, attrs) do
    case Gamend.Hooks.internal_call(:before_party_update, [party, attrs]) do
      {:ok, returned} ->
        attrs_to_use =
          if is_map(returned) and not is_struct(returned) do
            returned
          else
            attrs
          end

        party
        |> Party.changeset(attrs_to_use)
        |> Repo.update()
        |> tap_bump_party()
        |> case do
          {:ok, updated} ->
            broadcast_party(updated.id, {:party_updated, with_party_members(updated)})

            Gamend.Async.run(fn ->
              Gamend.Hooks.internal_call(:after_party_updated, [updated])
            end)

            {:ok, updated}

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Lobby integration: quick join with party
  # ---------------------------------------------------------------------------

  @doc """
  The party leader quick-joins a lobby with the entire party.

  Searches for an open lobby that matches the given criteria (title,
  max_users, metadata) and has enough space for the whole party. If no
  matching lobby is found, creates a new one and joins all party members
  atomically.

  Returns `{:ok, lobby}` on success.
  """
  @spec quick_join_with_party(User.t(), map()) :: {:ok, Lobby.t()} | {:error, term()}
  def quick_join_with_party(%User{} = user, params \\ %{}) do
    user = Accounts.get_user(user.id)

    with :ok <- check_in_party(user),
         {:ok, party} <- fetch_party(user.party_id),
         :ok <- check_is_leader(party, user) do
      members = get_party_members(party.id)

      with :ok <- check_no_members_in_lobby(members),
           :ok <- check_all_members_online(members) do
        do_quick_join_with_party(user, party, members, params)
      end
    end
  end

  defp do_quick_join_with_party(user, party, members, params) do
    title = Map.get(params, "title") || Map.get(params, :title)
    max_users = Map.get(params, "max_users") || Map.get(params, :max_users)

    metadata_raw = Map.get(params, "metadata") || Map.get(params, :metadata)

    metadata =
      case metadata_raw do
        nil ->
          %{}

        "" ->
          %{}

        s when is_binary(s) ->
          case Jason.decode(s) do
            {:ok, m} when is_map(m) -> m
            _ -> %{}
          end

        m when is_map(m) ->
          m

        _ ->
          %{}
      end

    party_size = length(members)

    # Find candidate lobbies: visible, unlocked, no password, matching max_users
    q =
      from(l in Lobbies.Lobby,
        where: l.is_hidden == false and l.is_locked == false and is_nil(l.password_hash)
      )

    q =
      if is_nil(max_users) do
        q
      else
        from(l in q, where: l.max_users == ^max_users)
      end

    # Only consider lobbies that have at least party_size free slots
    q =
      from(l in q,
        left_join: u in User,
        on: u.lobby_id == l.id,
        group_by: l.id,
        having: l.max_users - count(u.id) >= ^party_size,
        order_by: [asc: l.inserted_at],
        limit: 5
      )

    candidates = Repo.all(q)

    # Try candidates in order
    tried =
      Enum.reduce_while(candidates, :none, fn lobby, _acc ->
        if Lobbies.lobby_matches_metadata?(lobby, metadata) do
          case join_all_members_to_lobby(members, lobby, party) do
            {:ok, _} -> {:halt, {:ok, lobby}}
            {:error, :not_enough_space} -> {:cont, :none}
            {:error, _} = err -> {:halt, err}
          end
        else
          {:cont, :none}
        end
      end)

    case tried do
      {:ok, lobby} when is_map(lobby) ->
        {:ok, lobby}

      {:error, _} = err ->
        err

      :none ->
        # No match found -> create a new lobby with the whole party
        lobby_attrs = %{}
        lobby_attrs = if title, do: Map.put(lobby_attrs, "title", title), else: lobby_attrs

        lobby_attrs =
          if max_users,
            do: Map.put(lobby_attrs, "max_users", max_users),
            else:
              Map.put(
                lobby_attrs,
                "max_users",
                max(party_size, 8)
              )

        lobby_attrs =
          if metadata != %{},
            do: Map.put(lobby_attrs, "metadata", metadata),
            else: lobby_attrs

        do_create_lobby_with_party(user, party, members, lobby_attrs)
    end
  end

  # ---------------------------------------------------------------------------
  # Lobby integration: create lobby with party
  # ---------------------------------------------------------------------------

  @doc """
  The party leader creates a new lobby, and all party members join it
  atomically. The party is kept intact.

  The lobby's `max_users` must be >= party member count.
  """
  @spec create_lobby_with_party(User.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_lobby_with_party(%User{} = user, lobby_attrs \\ %{}) do
    user = Accounts.get_user(user.id)

    with :ok <- check_in_party(user),
         {:ok, party} <- fetch_party(user.party_id),
         :ok <- check_is_leader(party, user) do
      members = get_party_members(party.id)
      lobby_attrs = normalize_params(lobby_attrs)

      with :ok <- check_no_members_in_lobby(members),
           :ok <- check_all_members_online(members),
           :ok <- check_lobby_fits_party(lobby_attrs, length(members)) do
        do_create_lobby_with_party(user, party, members, lobby_attrs)
      end
    end
  end

  defp check_lobby_fits_party(lobby_attrs, member_count) do
    lobby_max =
      case Map.get(lobby_attrs, "max_users") do
        nil -> 8
        v when is_binary(v) -> to_int_or_nil(v) || 0
        v when is_integer(v) -> v
      end

    if lobby_max < member_count, do: {:error, :lobby_too_small_for_party}, else: :ok
  end

  defp do_create_lobby_with_party(user, _party, members, lobby_attrs) do
    # Drop the server-owned fields before stamping the real host. This path took
    # client attributes straight through, so `hostless` from the request body
    # would have survived into the changeset and produced an unmanageable lobby.
    lobby_attrs =
      lobby_attrs
      |> Map.drop(~w(hostless host_id)a ++ ~w(hostless host_id))
      |> Map.put("host_id", user.id)

    case Lobbies.create_lobby(lobby_attrs) do
      {:ok, lobby} ->
        finalize_party_lobby_creation(user, members, lobby)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finalize_party_lobby_creation(user, members, lobby) do
    non_leader_members = Enum.reject(members, &(&1.id == user.id))

    # Use a transaction with advisory lock so either ALL members join or NONE do
    Lock.serialize(:lobby, lobby.id, fn ->
      Enum.map(non_leader_members, fn member ->
        # Use Repo.get directly — Accounts.get_user would seed the cache
        # with lobby_id=nil inside the un-committed transaction.
        member = Repo.get(User, member.id)

        case Ecto.Changeset.change(member, %{lobby_id: lobby.id}) |> Repo.update() do
          {:ok, updated} ->
            updated

          {:error, reason} ->
            Repo.rollback({:member_join_failed, member.id, reason})
        end
      end)
    end)
    |> case do
      {:ok, updated_members} ->
        # Post-commit: invalidate and write correct values to cache.
        all_members = [user | non_leader_members]

        Enum.each(updated_members, fn updated ->
          Accounts.cache_user(updated)
        end)

        Enum.each(all_members, fn member ->
          updated = Accounts.get_user(member.id)
          _ = Accounts.broadcast_user_update(updated)

          Gamend.Broadcast.publish(
            "lobby:#{lobby.id}",
            {:user_joined, lobby.id, member.id}
          )
        end)

        # Party seats bypass `Lobbies.join_lobby/2`, so run its side seams here
        # too: games observe every member arriving, and an open ready check
        # gains the seated members. The leader created the lobby, so only the
        # non-leader members "join".
        Enum.each(non_leader_members, fn member ->
          _ = Gamend.ReadyChecks.add_member(lobby.id, member.id)

          Gamend.Async.run(fn ->
            Gamend.Hooks.internal_call(:after_lobby_join, [
              Accounts.get_user(member.id),
              lobby
            ])
          end)
        end)

        {:ok, lobby}

      {:error, reason} ->
        # Roll back lobby creation since not all party members could join
        Logger.warning(
          "Party lobby creation rolled back: #{inspect(reason)}, deleting lobby #{lobby.id}"
        )

        Lobbies.leave_lobby(user)
        Lobbies.delete_lobby(lobby)
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Lobby integration: join lobby with party
  # ---------------------------------------------------------------------------

  @doc """
  The party leader joins an existing lobby, and all party members join it
  atomically. The party is kept intact.

  The lobby must have enough free slots for the entire party.
  """
  @spec join_lobby_with_party(User.t(), Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  def join_lobby_with_party(%User{} = user, lobby_id, opts \\ %{}) when is_binary(lobby_id) do
    user = Accounts.get_user(user.id)

    with :ok <- check_in_party(user),
         {:ok, party} <- fetch_party(user.party_id),
         :ok <- check_is_leader(party, user),
         {:ok, lobby} <- fetch_joinable_lobby(lobby_id) do
      members = get_party_members(party.id)

      with :ok <- check_no_members_in_lobby(members),
           :ok <- check_all_members_online(members) do
        password = Map.get(opts, :password) || Map.get(opts, "password")

        case validate_lobby_password(lobby, password) do
          :ok -> join_all_members_to_lobby(members, lobby, party)
          {:error, _} = err -> err
        end
      end
    end
  end

  defp fetch_joinable_lobby(lobby_id) do
    case Lobbies.get_lobby(lobby_id) do
      nil -> {:error, :invalid_lobby}
      %{is_locked: true} -> {:error, :locked}
      lobby -> {:ok, lobby}
    end
  end

  defp validate_lobby_password(lobby, password) do
    case {lobby.password_hash, password} do
      {nil, _} ->
        :ok

      {_hash, nil} ->
        {:error, :password_required}

      {hash, pwd} ->
        if PasswordHash.verify(pwd, hash), do: :ok, else: {:error, :invalid_password}
    end
  end

  defp join_all_members_to_lobby(members, lobby, _party) do
    # Use a transaction with advisory lock so the space check + member joins
    # are atomic. This prevents TOCTOU race conditions on PostgreSQL.
    Lock.serialize(:lobby, lobby.id, fn ->
      # Re-check space inside the lock
      current_lobby_count =
        Repo.one(
          from(u in User,
            where: u.lobby_id == ^lobby.id,
            select: count(u.id)
          )
        ) || 0

      available = lobby.max_users - current_lobby_count

      if available < length(members) do
        Repo.rollback(:not_enough_space)
      end

      Enum.map(members, fn member ->
        # Use Repo.get directly — Accounts.get_user would seed the cache
        # with lobby_id=nil inside the un-committed transaction.
        member = Repo.get(User, member.id)

        case member
             |> Ecto.Changeset.change(%{lobby_id: lobby.id})
             |> Repo.update() do
          {:ok, updated} ->
            updated

          {:error, reason} ->
            Repo.rollback({:member_join_failed, member.id, reason})
        end
      end)
    end)
    |> case do
      {:ok, updated_members} ->
        # Post-commit: invalidate and write correct values to cache.
        Enum.each(updated_members, fn updated ->
          Accounts.cache_user(updated)
        end)

        # Broadcast events only after successful commit
        Enum.each(members, fn member ->
          updated = Accounts.get_user(member.id)
          _ = Accounts.broadcast_user_update(updated)

          Gamend.Broadcast.publish(
            "lobby:#{lobby.id}",
            {:user_joined, lobby.id, member.id}
          )
        end)

        # Party seats bypass `Lobbies.join_lobby/2`, so run its side seams
        # here too — in particular, the lobby's open ready check must gain
        # every seated member or the match could start without them.
        Enum.each(members, fn member ->
          _ = Gamend.ReadyChecks.add_member(lobby.id, member.id)

          Gamend.Async.run(fn ->
            Gamend.Hooks.internal_call(:after_lobby_join, [
              Accounts.get_user(member.id),
              lobby
            ])
          end)
        end)

        {:ok, lobby}

      {:error, reason} ->
        Logger.warning("Party lobby join rolled back: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp disband_party(%Party{} = party) do
    # Collect member IDs before bulk update for cache invalidation + broadcasts
    members = get_party_members(party.id)
    member_ids = Enum.map(members, & &1.id)

    Gamend.AfterCommit.transaction(fn ->
      # Bulk-clear party_id for all members in a single query
      from(u in User, where: u.party_id == ^party.id)
      |> Repo.update_all(set: [party_id: nil])

      # Cancel all pending invites for this party
      cancel_pending_invites_for_party(party.id)

      # Delete the party
      Repo.delete!(party)
    end)
    |> tap_bump_party()
    |> case do
      {:ok, _} ->
        # Invalidate caches and broadcast outside the transaction
        Enum.each(member_ids, fn id ->
          invalidate_user_cache(id)
        end)

        Enum.each(members, fn member ->
          _ = Accounts.broadcast_user_update(%{member | party_id: nil})
          _ = Accounts.broadcast_member_update(%{member | party_id: nil})
        end)

        broadcast_party(party.id, {:party_disbanded, party.id})
        broadcast_parties({:party_deleted, party.id})

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_party_disband, [party])
        end)

        {:ok, :disbanded}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    Ecto.StaleEntryError ->
      # Race condition: party was concurrently disbanded by another operation
      {:ok, :disbanded}
  end

  # The leader leaving hands the party to whoever else is in it, the way a lobby
  # hands over its host — losing the whole party because one player left (or
  # dropped, once retention releases their seat) punished everyone else for it.
  # Longest-present member first, the same order lobby migration uses.
  #
  # With nobody left there is nothing to hand over, and an empty party is just a
  # row: disband as before.
  # Serialized, and the member list is re-read inside the lock.
  #
  # This was three independent statements — read the members, promote a
  # successor, remove the leaver — with no transaction and no lock. When the
  # leader and the chosen successor left at the same time, the party ended up
  # with zero members but `leader_id` pointing at someone no longer in it; and
  # because that column is uniquely indexed, the successor's next
  # `create_party/2` then failed on a constraint instead of returning a clean
  # error, until retention swept the orphan. A failure between the two writes
  # left the party with a new leader *and* the old one still in it.
  defp hand_over_or_disband(%User{} = user, %Party{} = party) do
    outcome =
      Lock.serialize(:party, party.id, fn ->
        case Enum.reject(get_party_members(party.id), &(&1.id == user.id)) do
          [] ->
            :disband

          [%User{id: successor_id} | _] ->
            with {:ok, promoted} <- promote_party_leader(party, successor_id),
                 {:ok, :left} <- remove_member(user, party.id) do
              {:handed_over, promoted}
            else
              {:error, reason} -> Repo.rollback(reason)
            end
        end
      end)

    case outcome do
      # Disbanding runs its own transaction and broadcasts, so it happens after
      # this one has committed rather than nested inside it.
      {:ok, :disband} ->
        disband_party(party)

      {:ok, {:handed_over, promoted}} ->
        broadcast_party(promoted.id, {:party_updated, with_party_members(promoted)})
        broadcast_parties({:party_updated, promoted.id})
        {:ok, :left}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp promote_party_leader(%Party{} = party, successor_id) when is_binary(successor_id) do
    party
    |> Ecto.Changeset.change(%{leader_id: successor_id})
    |> Repo.update()
    |> tap_bump_party()
  end

  defp remove_member(%User{} = user, party_id) do
    result =
      user
      |> Ecto.Changeset.change(%{party_id: nil})
      |> Repo.update()

    case result do
      {:ok, updated} ->
        invalidate_user_cache(updated.id)
        cancel_pending_invites_for_user_in_party(updated.id, party_id)
        _ = Accounts.broadcast_user_update(updated)
        _ = Accounts.broadcast_member_update(updated)
        broadcast_party(party_id, {:party_member_left, party_id, updated.id})
        _ = Gamend.ReadyChecks.remove_party_member(party_id, updated.id)

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_party_leave, [user, party_id])
        end)

        {:ok, :left}

      error ->
        error
    end
  end

  defp clear_party_id(%User{} = user) do
    user
    |> Ecto.Changeset.change(%{party_id: nil})
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        invalidate_user_cache(updated.id)
        _ = Accounts.broadcast_user_update(updated)
        _ = Accounts.broadcast_member_update(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  defp invalidate_user_cache(user_id) when is_binary(user_id) do
    # Synchronous invalidation — the client may join the party channel
    # immediately after a party operation (possibly via another app
    # instance), so the cached user must already be cleared everywhere.
    _ = Gamend.Cache.invalidate({:accounts, :user, user_id})
    :ok
  end

  defp normalize_params(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} ->
      if is_atom(k), do: {Atom.to_string(k), v}, else: {k, v}
    end)
  end

  defp normalize_params(other), do: other

  # ---------------------------------------------------------------------------
  # Admin helpers
  # ---------------------------------------------------------------------------

  @doc "Subscribe to all party events (create/delete)."
  @spec subscribe_parties() :: :ok | {:error, term()}
  def subscribe_parties do
    Phoenix.PubSub.subscribe(Gamend.PubSub, "parties")
  end

  defp broadcast_parties(event) do
    Gamend.Broadcast.publish("parties", event)
  end

  @doc "List all parties with optional filters and pagination."
  @spec list_all_parties(map(), keyword()) :: [Party.t()]
  def list_all_parties(filters \\ %{}, opts \\ []) do
    sort_by = Keyword.get(opts, :sort_by, "updated_at")

    from(p in Party)
    |> apply_party_filters(filters)
    |> apply_party_sort(sort_by)
    |> Gamend.Query.page(opts)
    |> Repo.all()
    |> Repo.preload(:leader)
  end

  @doc "Count all parties matching the given filters."
  @spec count_all_parties(map()) :: non_neg_integer()
  def count_all_parties(filters \\ %{}) do
    from(p in Party, select: count(p.id))
    |> apply_party_filters(filters)
    |> Repo.one() || 0
  end

  @doc "Return a changeset for the given party (for edit forms)."
  @spec change_party(Party.t()) :: Ecto.Changeset.t()
  def change_party(%Party{} = party) do
    Party.changeset(party, %{})
  end

  @doc "Admin update of a party (max_size, metadata)."
  @spec admin_update_party(Party.t(), map()) :: {:ok, Party.t()} | {:error, Ecto.Changeset.t()}
  def admin_update_party(%Party{} = party, attrs) do
    result =
      party
      |> Party.changeset(attrs)
      |> Repo.update()
      |> tap_bump_party()

    case result do
      {:ok, updated} ->
        broadcast_party(updated.id, {:party_updated, with_party_members(updated)})
        broadcast_parties({:party_updated, updated.id})
        result

      _ ->
        result
    end
  end

  @doc "Admin delete of a party. Clears all members' party_id and deletes the party."
  @spec admin_delete_party(Ecto.UUID.t()) :: {:ok, Party.t()} | {:error, term()}
  def admin_delete_party(party_id) when is_binary(party_id) do
    case get_party(party_id) do
      nil ->
        {:error, :not_found}

      party ->
        # Collect member IDs before clearing, to invalidate caches after
        member_ids =
          from(u in User, where: u.party_id == ^party_id, select: u.id)
          |> Repo.all()

        # Clear all members' party_id
        from(u in User, where: u.party_id == ^party_id)
        |> Repo.update_all(set: [party_id: nil])

        # Cancel all pending invites for this party
        cancel_pending_invites_for_party(party_id)

        case Repo.delete(party) |> tap_bump_party() do
          {:ok, deleted} ->
            Enum.each(member_ids, &invalidate_user_cache/1)
            broadcast_party(party_id, {:party_disbanded, party_id})
            broadcast_parties({:party_deleted, party_id})
            {:ok, deleted}

          error ->
            error
        end
    end
  end

  defp apply_party_filters(query, filters) when is_map(filters) do
    query
    |> maybe_filter_leader_id(filters)
    |> maybe_filter_min_size(filters)
    |> maybe_filter_max_size(filters)
  end

  defp maybe_filter_leader_id(query, %{"leader_id" => id}) when id not in ["", nil] do
    case Ecto.UUID.cast(to_string(id)) do
      {:ok, lid} -> where(query, [p], p.leader_id == ^lid)
      :error -> query
    end
  end

  defp maybe_filter_leader_id(query, _), do: query

  defp maybe_filter_min_size(query, %{"min_size" => v}) when v not in ["", nil] do
    case Integer.parse(to_string(v)) do
      {n, ""} -> where(query, [p], p.max_size >= ^n)
      _ -> query
    end
  end

  defp maybe_filter_min_size(query, _), do: query

  defp maybe_filter_max_size(query, %{"max_size" => v}) when v not in ["", nil] do
    case Integer.parse(to_string(v)) do
      {n, ""} -> where(query, [p], p.max_size <= ^n)
      _ -> query
    end
  end

  defp maybe_filter_max_size(query, _), do: query

  defp apply_party_sort(query, "updated_at"), do: order_by(query, [p], desc: p.updated_at)
  defp apply_party_sort(query, "updated_at_asc"), do: order_by(query, [p], asc: p.updated_at)
  defp apply_party_sort(query, "inserted_at"), do: order_by(query, [p], desc: p.inserted_at)
  defp apply_party_sort(query, "inserted_at_asc"), do: order_by(query, [p], asc: p.inserted_at)
  defp apply_party_sort(query, "max_size"), do: order_by(query, [p], desc: p.max_size)
  defp apply_party_sort(query, "max_size_asc"), do: order_by(query, [p], asc: p.max_size)
  defp apply_party_sort(query, _), do: order_by(query, [p], desc: p.updated_at)

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
