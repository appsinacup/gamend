defmodule Gamend.Groups.Shared do
  @moduledoc false
  # Internal helpers shared by `Gamend.Groups` and its submodules
  # (`Invites`, `JoinRequests`). Not part of the public Groups API.

  import Ecto.Query, warn: false

  alias Gamend.Groups
  alias Gamend.Groups.Group
  alias Gamend.Groups.GroupInvite
  alias Gamend.Groups.GroupMember
  alias Gamend.Lock
  alias Gamend.Repo

  @doc false
  def broadcast_group(group_id, event) do
    Gamend.Broadcast.publish("group:#{group_id}", event)
  end

  # -- Group cache (version-based, keyed by group_id) --

  @doc false
  def group_cache_version(group_id) when is_binary(group_id) do
    Gamend.Cache.get!({:groups, :group_version, group_id}) || 1
  end

  @doc false
  def invalidate_group_cache(group_id) when is_binary(group_id) do
    Gamend.Async.run(fn ->
      _ = Gamend.Cache.bump_version({:groups, :group_version, group_id})
      :ok
    end)

    :ok
  end

  # -- Invite cache (version-based, keyed by user_id) --

  def invite_cache_version(user_id) when is_binary(user_id) do
    Gamend.Cache.get!({:group_invites, :version, user_id}) || 1
  end

  def invalidate_invite_cache(user_id) when is_binary(user_id) do
    Gamend.Async.run(fn ->
      _ = Gamend.Cache.bump_version({:group_invites, :version, user_id})
      :ok
    end)

    :ok
  end

  # Synchronous version — used when the caller needs the cache to be
  # invalidated immediately before returning (e.g. accept_invite where the
  # client polls right away).
  def invalidate_invite_cache_sync(user_id) when is_binary(user_id) do
    _ = Gamend.Cache.bump_version({:group_invites, :version, user_id})
    :ok
  end

  # Mark any pending GroupInvite records for a user+group as "accepted" and
  # notify/invalidate caches for each sender. Called when a user joins a group
  # through a path other than accept_invite (e.g. manual join, admin approval).
  def mark_pending_invites_accepted(user_id, group_id) do
    pending_invites =
      from(i in GroupInvite,
        where:
          i.recipient_id == ^user_id and i.group_id == ^group_id and
            i.status == "pending"
      )
      |> Repo.all()

    if pending_invites != [] do
      from(i in GroupInvite,
        where:
          i.recipient_id == ^user_id and i.group_id == ^group_id and
            i.status == "pending"
      )
      |> Repo.update_all(set: [status: "accepted", updated_at: DateTime.utc_now()])

      invalidate_invite_cache_sync(user_id)

      user = Gamend.Accounts.get_user(user_id)
      user_name = Gamend.Accounts.display_name(user)
      group = Groups.get_group(group_id)
      group_title = (group && group.title) || ""

      sender_ids = pending_invites |> Enum.map(& &1.sender_id) |> Enum.uniq()

      for sender_id <- sender_ids do
        invalidate_invite_cache_sync(sender_id)

        Gamend.Notifications.admin_create_notification(
          user_id,
          sender_id,
          %{
            "title" => "#{user_name} joined #{group_title}",
            "content" => "",
            "metadata" => %{
              "type" => "group_invite_accepted",
              "group_id" => group_id,
              "group_title" => group_title,
              "user_id" => user_id,
              "user_name" => user_name
            }
          }
        )

        Gamend.Broadcast.publish(
          "user:#{sender_id}",
          {:group_invite_accepted, %{group_id: group_id}}
        )
      end
    end

    :ok
  end

  # Collect unique user IDs (senders + recipients) with pending invites for a group.
  # Must be called BEFORE deleting the group (cascade deletes the rows).
  def gather_pending_invite_user_ids(group_id) do
    from(i in GroupInvite,
      where: i.group_id == ^group_id and i.status == "pending",
      select: {i.sender_id, i.recipient_id}
    )
    |> Repo.all()
    |> Enum.flat_map(fn {s, r} -> [s, r] end)
    |> Enum.uniq()
  end

  # Invalidate invite caches for a list of user IDs.
  def invalidate_invite_caches_for_users(user_ids) do
    for uid <- user_ids, do: invalidate_invite_cache_sync(uid)
    :ok
  end

  # Broadcast a group_deleted event to each user who had a pending invite.
  def notify_invite_users_group_deleted(user_ids, group) do
    for uid <- user_ids do
      Gamend.Broadcast.publish(
        "user:#{uid}",
        {:group_invite_cancelled, %{group_id: group.id, group_title: group.title}}
      )
    end

    :ok
  end

  def run_before_group_join_hook(user_id, %Group{} = group, opts)
      when is_binary(user_id) and is_map(opts) do
    case Repo.get(Gamend.Accounts.User, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        actor_user_id = Map.get(opts, "actor_user_id") || Map.get(opts, :actor_user_id) || user_id

        hook_opts =
          Map.merge(opts, %{
            "actor_user_id" => actor_user_id,
            "joining_user_id" => user_id,
            "group_id" => group.id,
            "group_title" => group.title,
            "group_type" => group.type,
            "group_metadata" => group.metadata || %{}
          })

        case Gamend.Hooks.internal_call(:before_group_join, [user, group, hook_opts],
               caller: actor_user_id
             ) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Shared helper: check capacity, run the hook, then lock, re-check and insert.
  #
  # The hook runs before the lock, as join-request approval already does: it
  # may take up to its timeout, and inside the lock it held the group and, on
  # SQLite, the only database connection. The capacity checks run first too,
  # so a full group is refused without calling it, and again under the lock,
  # where a concurrent join could have taken the last place.
  @doc false
  def do_add_group_member(user_id, group_id, group, source) do
    with :ok <- check_room(user_id, group_id, group),
         :ok <- run_before_group_join_hook(user_id, group, %{"source" => source}) do
      Lock.serialize(:group, group_id, fn ->
        case check_room(user_id, group_id, group) do
          :ok -> insert_group_member(group_id, user_id)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  defp check_room(user_id, group_id, group) do
    cond do
      Groups.count_group_members(group_id) >= group.max_members ->
        {:error, :full}

      Groups.count_user_group_memberships(user_id) >= Gamend.Limits.get(:max_groups_per_user) ->
        {:error, :too_many_groups}

      true ->
        :ok
    end
  end

  defp insert_group_member(group_id, user_id) do
    case %GroupMember{}
         |> GroupMember.changeset(%{group_id: group_id, user_id: user_id, role: "member"})
         |> Repo.insert() do
      {:ok, member} ->
        _ = invalidate_group_cache(group_id)
        broadcast_group(group_id, {:member_joined, group_id, user_id})
        member

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end
end
