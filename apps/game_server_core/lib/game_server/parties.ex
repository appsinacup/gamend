defmodule GameServer.Parties do
  @moduledoc """
  Context module for party management.

  A party is a pre-lobby grouping mechanism. Players form a party before
  creating or joining a lobby together.

  ## Usage

      # Create a party (user becomes leader and first member)
      {:ok, party} = GameServer.Parties.create_party(user, %{max_size: 4})

      # Leader invites a friend or shared-group member by user_id
      {:ok, _notification} = GameServer.Parties.invite_to_party(leader, target_user_id)

      # Target accepts the invite
      {:ok, party} = GameServer.Parties.accept_party_invite(target, party_id)

      # Or declines
      :ok = GameServer.Parties.decline_party_invite(target, party_id)

      # Leave a party (if leader leaves, party is disbanded)
      {:ok, _} = GameServer.Parties.leave_party(user)

      # Party leader creates a lobby — all members join atomically
      {:ok, lobby} = GameServer.Parties.create_lobby_with_party(user, lobby_attrs)

      # Party leader joins an existing lobby — all members join atomically
      {:ok, lobby} = GameServer.Parties.join_lobby_with_party(user, lobby_id, opts)

  ## PubSub Events

  This module broadcasts the following events:

  - `"party:<party_id>"` topic:
    - `{:party_member_joined, party_id, user_id}`
    - `{:party_member_left, party_id, user_id}`
    - `{:party_disbanded, party_id}`
    - `{:party_updated, party}`
  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: GameServer.Cache

  require Logger

  alias GameServer.Accounts
  alias GameServer.Accounts.User
  alias GameServer.Friends
  alias GameServer.Groups
  alias GameServer.Lobbies
  alias GameServer.Lobbies.Lobby
  alias GameServer.Parties.Party
  alias GameServer.Parties.PartyInvite
  alias GameServer.Repo
  alias GameServer.Repo.AdvisoryLock

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @doc "Subscribe to events for a specific party."
  @spec subscribe_party(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_party(party_id) do
    Phoenix.PubSub.subscribe(GameServer.PubSub, "party:#{party_id}")
  end

  @doc "Unsubscribe from a party's events."
  @spec unsubscribe_party(Ecto.UUID.t()) :: :ok
  def unsubscribe_party(party_id) do
    Phoenix.PubSub.unsubscribe(GameServer.PubSub, "party:#{party_id}")
  end

  # Preload members once so per-socket channel serialization reuses them
  # instead of each subscriber re-querying get_party_members/1.
  defp with_party_members(%Party{} = party) do
    %{party | members: get_party_members(party.id)}
  end

  defp broadcast_party(party_id, event) do
    Phoenix.PubSub.broadcast(GameServer.PubSub, "party:#{party_id}", event)
  end

  @doc "Broadcast a member presence event (online/offline) to a party's PubSub topic."
  @spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
  def broadcast_member_presence(party_id, event) do
    broadcast_party(party_id, event)
  end

  # ---------------------------------------------------------------------------
  # Cache helpers
  # ---------------------------------------------------------------------------

  @party_invite_cache_ttl_ms 60_000

  defp party_invite_cache_version(user_id) when is_binary(user_id) do
    GameServer.Cache.get!({:party_invites, :version, user_id}) || 1
  end

  defp invalidate_party_invite_cache(user_id) when is_binary(user_id) do
    _ = GameServer.Cache.bump_version({:party_invites, :version, user_id})
    :ok
  end

  # Party-row cache: get_party is keyed by a version bumped on every party-row
  # write. Membership/invite changes don't touch the party row, so they don't bump.
  @party_cache_ttl_ms 60_000
  defp party_cache_version, do: GameServer.Cache.get!({:parties, :version}) || 1

  defp tap_bump_party({:ok, _} = result) do
    _ = GameServer.Cache.bump_version({:parties, :version})
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
              opts: [ttl: @party_cache_ttl_ms]
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

  @doc "Returns true if the given user is the leader of their current party."
  @spec leader?(User.t()) :: boolean()
  def leader?(%User{party_id: nil}), do: false

  def leader?(%User{party_id: party_id, id: user_id}) do
    case get_party(party_id) do
      %Party{leader_id: ^user_id} -> true
      _ -> false
    end
  end

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

    case GameServer.Hooks.internal_call(:before_party_create, [user, attrs]) do
      {:ok, attrs} -> do_create_party(user, attrs)
      {:error, reason} -> {:error, {:hook_rejected, reason}}
    end
  end

  defp do_create_party(user, attrs) do
    Repo.transaction(fn ->
      # Lock on the user's id to prevent concurrent party creation
      AdvisoryLock.lock(:party, user.id)

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

        GameServer.Async.run(fn ->
          GameServer.Hooks.internal_call(:after_party_create, [party])
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
          GameServer.Notifications.admin_create_notification(leader.id, target_user_id, %{
            "title" => "Party invite from #{leader.display_name || ""}",
            "content" => "",
            "metadata" => %{
              "type" => "party_invite",
              "party_id" => party.id,
              "sender_name" => leader.display_name || "",
              "recipient_name" => target.display_name || ""
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
        leader_name = leader.display_name || ""

        GameServer.Notifications.delete_notification_by(
          leader.id,
          target_user_id,
          "Party invite from #{leader_name}"
        )

        Phoenix.PubSub.broadcast(
          GameServer.PubSub,
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
           {:ok, _} <- GameServer.Hooks.internal_call(:before_party_join, [user, party]),
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
    user_name = user.display_name || ""

    # Mark the invite as declined so the sender knows it didn't go through
    from(i in PartyInvite,
      where:
        i.recipient_id == ^user.id and i.party_id == ^party_id and
          i.status == "pending"
    )
    |> Repo.update_all(set: [status: "declined", updated_at: DateTime.utc_now()])

    invalidate_party_invite_cache(user.id)
    invalidate_party_invite_cache(invite.sender_id)

    # Retract the original invite notification
    sender = GameServer.Accounts.get_user(invite.sender_id)
    sender_name = (sender && sender.display_name) || ""

    GameServer.Notifications.delete_notification_by(
      invite.sender_id,
      user.id,
      "Party invite from #{sender_name}"
    )

    # Notify the sender that the invite was declined because the party is full
    GameServer.Notifications.admin_create_notification(
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
    Phoenix.PubSub.broadcast(
      GameServer.PubSub,
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

  defp finalize_accept_invite(user, invite, party_id, party) do
    # Mark all pending invites for this user + party as accepted
    from(i in PartyInvite,
      where:
        i.recipient_id == ^user.id and i.party_id == ^party_id and
          i.status == "pending"
    )
    |> Repo.update_all(set: [status: "accepted", updated_at: DateTime.utc_now()])

    invalidate_party_invite_cache(user.id)
    invalidate_party_invite_cache(invite.sender_id)

    # Cancel pending invites to this user from OTHER parties
    cancel_other_pending_invites_for_user(user.id, party_id)

    # Retract the invite notification for the accepting user
    sender = GameServer.Accounts.get_user(invite.sender_id)
    sender_name = (sender && sender.display_name) || ""

    GameServer.Notifications.delete_notification_by(
      invite.sender_id,
      user.id,
      "Party invite from #{sender_name}"
    )

    # Notify the leader that the invite was accepted
    user_name = user.display_name || ""

    GameServer.Notifications.admin_create_notification(
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
    Phoenix.PubSub.broadcast(
      GameServer.PubSub,
      "user:#{invite.sender_id}",
      {:party_invite_accepted, %{party_id: party_id, user_id: user.id}}
    )

    GameServer.Async.run(fn ->
      GameServer.Hooks.internal_call(:after_party_join, [user, party])
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
    user_name = user.display_name || ""

    Enum.each(sender_ids, fn sender_id ->
      # Retract the invite notification
      sender = GameServer.Accounts.get_user(sender_id)
      sender_name = (sender && sender.display_name) || ""

      GameServer.Notifications.delete_notification_by(
        sender_id,
        user.id,
        "Party invite from #{sender_name}"
      )

      # Notify the leader that the invite was declined
      GameServer.Notifications.admin_create_notification(
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

      Phoenix.PubSub.broadcast(
        GameServer.PubSub,
        "user:#{sender_id}",
        {:party_invite_declined, %{party_id: party_id, user_id: user.id}}
      )
    end)

    :ok
  end

  @doc """
  List pending party invites for the given user.
  """
  @spec list_party_invitations(User.t()) :: [map()]
  def list_party_invitations(%User{} = user) do
    do_list_party_invitations(user.id)
  end

  @decorate cacheable(
              key: {:party_invites, :list, party_invite_cache_version(user_id), user_id},
              opts: [ttl: @party_invite_cache_ttl_ms]
            )
  defp do_list_party_invitations(user_id) do
    from(i in PartyInvite,
      where: i.recipient_id == ^user_id and i.status == "pending",
      join: s in assoc(i, :sender),
      join: r in assoc(i, :recipient),
      order_by: [desc: i.inserted_at],
      preload: [sender: s, recipient: r]
    )
    |> Repo.all()
    |> Enum.map(&serialize_party_invite/1)
  end

  @doc """
  List pending party invites sent by the given leader.

  Returns invitations the leader has sent that have not yet been accepted or declined.
  """
  @spec list_sent_party_invitations(User.t()) :: [map()]
  def list_sent_party_invitations(%User{} = leader) do
    do_list_sent_party_invitations(leader.id)
  end

  @decorate cacheable(
              key: {:party_invites, :list_sent, party_invite_cache_version(leader_id), leader_id},
              opts: [ttl: @party_invite_cache_ttl_ms]
            )
  defp do_list_sent_party_invitations(leader_id) do
    from(i in PartyInvite,
      where: i.sender_id == ^leader_id and i.status == "pending",
      join: s in assoc(i, :sender),
      join: r in assoc(i, :recipient),
      order_by: [desc: i.inserted_at],
      preload: [sender: s, recipient: r]
    )
    |> Repo.all()
    |> Enum.map(&serialize_party_invite/1)
  end

  defp serialize_party_invite(invite) do
    %{
      id: invite.id,
      party_id: invite.party_id,
      sender_id: invite.sender_id,
      sender_name: invite.sender.display_name || "",
      recipient_id: invite.recipient_id,
      recipient_name: invite.recipient.display_name || "",
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
    max = GameServer.Limits.get(:max_party_pending_invites)

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
    Repo.transaction(fn ->
      AdvisoryLock.lock(:party, party_id)

      # Re-check space inside the lock
      count = count_party_members(party_id)
      party = get_party(party_id)

      if party && count >= party.max_size do
        Repo.rollback(:party_full)
      else
        case user
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
        _ = GameServer.ReadyChecks.add_party_member(party_id, updated_user.id)

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

  If the user is the party leader, the party is disbanded (all members removed,
  party deleted). Regular members are simply removed.
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
          disband_party(party)
        else
          remove_member(user, party.id)
        end
      end
    end
  end

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
         {:ok, _} <- GameServer.Hooks.internal_call(:before_party_kick, [target, leader, party]) do
      case do_kick_member(target, party) do
        {:ok, _updated} = result ->
          GameServer.Async.run(fn ->
            GameServer.Hooks.internal_call(:after_party_kick, [target, leader, party])
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

  # A member is considered "recently active" if they are online or were last
  # seen within the grace period (default 5 minutes). This avoids false
  # negatives caused by brief disconnects or heartbeat delays.
  @online_grace_seconds 300

  defp check_all_members_online(members) do
    cutoff = DateTime.add(DateTime.utc_now(), -@online_grace_seconds, :second)

    offline =
      Enum.filter(members, fn m ->
        not member_recently_active?(m, cutoff)
      end)

    if offline == [] do
      :ok
    else
      {:error, :members_offline}
    end
  end

  defp member_recently_active?(%User{is_online: true}, _cutoff), do: true

  defp member_recently_active?(%User{last_seen_at: %DateTime{} = last_seen}, cutoff) do
    DateTime.compare(last_seen, cutoff) != :lt
  end

  defp member_recently_active?(_user, _cutoff), do: false

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
        _ = GameServer.ReadyChecks.remove_party_member(party.id, updated.id)

        # Notify the kicked user
        GameServer.Notifications.admin_create_notification(
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

  @doc """
  Update party settings. Only the leader can update.
  """
  @spec update_party(User.t(), map()) :: {:ok, Party.t()} | {:error, term()}
  def update_party(%User{} = user, attrs) do
    user = Accounts.get_user(user.id)

    with :ok <- check_in_party(user),
         {:ok, party} <- fetch_party(user.party_id),
         :ok <- check_is_leader(party, user) do
      attrs = normalize_params(attrs)
      validate_and_update_party(party, attrs)
    end
  end

  defp validate_and_update_party(party, attrs) do
    new_max = Map.get(attrs, "max_size")

    if new_max do
      count = count_party_members(party.id)
      new_max_int = if is_binary(new_max), do: String.to_integer(new_max), else: new_max

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
    case GameServer.Hooks.internal_call(:before_party_update, [party, attrs]) do
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

            GameServer.Async.run(fn ->
              GameServer.Hooks.internal_call(:after_party_updated, [updated])
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
        v when is_binary(v) -> String.to_integer(v)
        v when is_integer(v) -> v
      end

    if lobby_max < member_count, do: {:error, :lobby_too_small_for_party}, else: :ok
  end

  defp do_create_lobby_with_party(user, _party, members, lobby_attrs) do
    lobby_attrs = Map.put(lobby_attrs, "host_id", user.id)

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
    Repo.transaction(fn ->
      AdvisoryLock.lock(:lobby, lobby.id)

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

          Phoenix.PubSub.broadcast(
            GameServer.PubSub,
            "lobby:#{lobby.id}",
            {:user_joined, lobby.id, member.id}
          )
        end)

        # Party seats bypass `Lobbies.join_lobby/2`, so run its side seams here
        # too: games observe every member arriving, and an open ready check
        # gains the seated members. The leader created the lobby, so only the
        # non-leader members "join".
        Enum.each(non_leader_members, fn member ->
          _ = GameServer.ReadyChecks.add_member(lobby.id, member.id)

          GameServer.Async.run(fn ->
            GameServer.Hooks.internal_call(:after_lobby_join, [
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
        if Bcrypt.verify_pass(pwd, hash), do: :ok, else: {:error, :invalid_password}
    end
  end

  defp join_all_members_to_lobby(members, lobby, _party) do
    # Use a transaction with advisory lock so the space check + member joins
    # are atomic. This prevents TOCTOU race conditions on PostgreSQL.
    Repo.transaction(fn ->
      AdvisoryLock.lock(:lobby, lobby.id)

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

          Phoenix.PubSub.broadcast(
            GameServer.PubSub,
            "lobby:#{lobby.id}",
            {:user_joined, lobby.id, member.id}
          )
        end)

        # Party seats bypass `Lobbies.join_lobby/2`, so run its side seams
        # here too — in particular, the lobby's open ready check must gain
        # every seated member or the match could start without them.
        Enum.each(members, fn member ->
          _ = GameServer.ReadyChecks.add_member(lobby.id, member.id)

          GameServer.Async.run(fn ->
            GameServer.Hooks.internal_call(:after_lobby_join, [
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

    Repo.transaction(fn ->
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

        GameServer.Async.run(fn ->
          GameServer.Hooks.internal_call(:after_party_disband, [party])
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
        _ = GameServer.ReadyChecks.remove_party_member(party_id, updated.id)

        GameServer.Async.run(fn ->
          GameServer.Hooks.internal_call(:after_party_leave, [user, party_id])
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
    _ = GameServer.Cache.invalidate({:accounts, :user, user_id})
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
    Phoenix.PubSub.subscribe(GameServer.PubSub, "parties")
  end

  defp broadcast_parties(event) do
    Phoenix.PubSub.broadcast(GameServer.PubSub, "parties", event)
  end

  @doc "List all parties with optional filters and pagination."
  @spec list_all_parties(map(), keyword()) :: [Party.t()]
  def list_all_parties(filters \\ %{}, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    sort_by = Keyword.get(opts, :sort_by, "updated_at")
    offset = (page - 1) * page_size

    from(p in Party)
    |> apply_party_filters(filters)
    |> apply_party_sort(sort_by)
    |> limit(^page_size)
    |> offset(^offset)
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
end
