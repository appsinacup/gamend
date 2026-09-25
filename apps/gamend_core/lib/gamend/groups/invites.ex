defmodule Gamend.Groups.Invites do
  @moduledoc """
  Group invitations: creating, accepting, declining, cancelling, and
  listing/counting pending invites.

  Public API is re-exported by `Gamend.Groups`.
  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: Gamend.Cache

  alias Gamend.Friends
  alias Gamend.Groups
  alias Gamend.Groups.GroupInvite
  alias Gamend.Groups.GroupJoinRequest
  alias Gamend.Groups.GroupMember
  alias Gamend.Groups.JoinRequests
  alias Gamend.Groups.Shared
  alias Gamend.Repo

  @doc "Count pending invitations for a user."
  @spec count_invitations(Ecto.UUID.t()) :: non_neg_integer()
  @decorate cacheable(
              key: {:group_invites, :count, Shared.invite_cache_version(user_id), user_id},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def count_invitations(user_id) when is_binary(user_id) do
    import Ecto.Query

    from(i in GroupInvite,
      where: i.recipient_id == ^user_id and i.status == "pending",
      select: count(i.id)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc "Count group invitations sent by a user."
  @spec count_sent_invitations(Ecto.UUID.t()) :: non_neg_integer()
  @decorate cacheable(
              key: {:group_invites, :count_sent, Shared.invite_cache_version(user_id), user_id},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def count_sent_invitations(user_id) when is_binary(user_id) do
    import Ecto.Query

    from(i in GroupInvite,
      where: i.sender_id == ^user_id and i.status == "pending",
      select: count(i.id)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  # Deliberately stricter than the party rule, which also accepts
  # `Groups.shared_group_member?/2`. Accepting a shared group here would be
  # circular on the surface it is meant to protect: anyone can join a public
  # group, so "we are in a group together" is a connection a stranger can grant
  # themselves. A friendship cannot be — it needs the other person to accept.
  #
  # Classes do not lose anything to this: a student joins a class by entering
  # the code their teacher gives out, which is a pull, not an invite.
  defp connected?(admin_id, target_user_id) do
    Friends.friends?(admin_id, target_user_id)
  end

  @doc """
  Invite a user to a group. Creates a `GroupInvite` record and sends
  an informational notification. The invite record is independent of the
  notification — deleting notifications does not affect pending invites.

  If the target user already has a pending join request for this group,
  the request is automatically approved instead of creating an invite.
  In that case, returns `{:ok, :request_approved}`.

  The admin must already be connected to the target — a friendship, or a group
  they are both already in. Without that an admin could put any user id at all
  into a group with them, which made a group invite a weaker control than a
  party invite, where `Parties.check_leader_connected_to_target/2` has always
  required a connection. On a service children can reach, being addable to a
  stranger's group is the contact path that matters, so the two now agree.
  Returns `{:error, :not_connected}`.
  """
  @spec invite_to_group(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupInvite.t()} | {:ok, :request_approved} | {:error, atom()}
  def invite_to_group(admin_id, group_id, target_user_id)
      when is_binary(admin_id) and is_binary(group_id) and is_binary(target_user_id) do
    group = Groups.get_group(group_id)

    cond do
      is_nil(group) ->
        {:error, :not_found}

      not Groups.can_manage_group?(admin_id, group_id) ->
        {:error, :not_admin}

      Groups.member?(group_id, target_user_id) ->
        {:error, :already_member}

      Friends.blocked?(admin_id, target_user_id) ->
        {:error, :blocked}

      not connected?(admin_id, target_user_id) ->
        {:error, :not_connected}

      true ->
        import Ecto.Query

        # If the target user has a pending join request for this group,
        # auto-approve it instead of creating a separate invite.
        pending_request =
          Repo.get_by(GroupJoinRequest,
            group_id: group_id,
            user_id: target_user_id,
            status: "pending"
          )

        if pending_request do
          case JoinRequests.approve_join_request(admin_id, pending_request.id) do
            {:ok, _member} -> {:ok, :request_approved}
            error -> error
          end
        else
          do_create_invite(admin_id, group_id, target_user_id, group)
        end
    end
  end

  defp do_create_invite(admin_id, group_id, target_user_id, group) do
    import Ecto.Query

    max_invites = Gamend.Limits.get(:max_group_pending_invites)

    pending_count =
      Repo.one(
        from(i in GroupInvite,
          where: i.recipient_id == ^target_user_id and i.status == "pending",
          select: count(i.id)
        )
      ) || 0

    if pending_count >= max_invites do
      {:error, :too_many_pending_invites}
    else
      # Delete any existing invite for this recipient + group (regardless of status)
      # to avoid unique constraint violations on re-invites after accept/decline
      from(i in GroupInvite,
        where: i.recipient_id == ^target_user_id and i.group_id == ^group_id
      )
      |> Repo.delete_all()

      sender = Gamend.Accounts.get_user(admin_id)
      target = Gamend.Accounts.get_user(target_user_id)

      case %GroupInvite{}
           |> GroupInvite.changeset(%{
             group_id: group_id,
             sender_id: admin_id,
             recipient_id: target_user_id
           })
           |> Repo.insert() do
        {:ok, invite} ->
          # Send an informational notification (independent of the invite record)
          Gamend.Notifications.admin_create_notification(admin_id, target_user_id, %{
            "title" => "Invited to #{group.title}",
            "content" => "",
            "metadata" => %{
              "type" => "group_invite",
              "group_id" => group_id,
              "group_title" => group.title,
              "sender_name" => Gamend.Accounts.display_name(sender),
              "recipient_name" => Gamend.Accounts.display_name(target)
            }
          })

          Shared.invalidate_invite_cache(admin_id)
          Shared.invalidate_invite_cache(target_user_id)

          {:ok, invite}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Accept a pending group invite by **invite_id**.
  The user must be the recipient of the invite.
  Works for all group types (public, private, hidden).
  """
  @spec accept_invite(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupMember.t()} | {:error, atom()}
  def accept_invite(user_id, invite_id)
      when is_binary(user_id) and is_binary(invite_id) do
    case Repo.get(GroupInvite, invite_id) do
      %GroupInvite{recipient_id: ^user_id, status: "pending"} = invite ->
        do_accept_invite(user_id, invite)

      %GroupInvite{recipient_id: ^user_id} ->
        {:error, :no_invite}

      _other ->
        {:error, :not_found}
    end
  end

  defp do_accept_invite(user_id, invite) do
    group = Groups.get_group(invite.group_id)

    cond do
      is_nil(group) ->
        {:error, :not_found}

      Groups.member?(group.id, user_id) ->
        Shared.invalidate_invite_cache_sync(user_id)
        {:error, :already_member}

      true ->
        group_id = group.id

        case Shared.do_add_group_member(user_id, group_id, group, "invite_accept") do
          {:ok, member} ->
            finalize_invite_accept(user_id, group_id, group, invite)
            {:ok, member}

          {:error, :full} = error ->
            # The group filled up between the invite and acceptance.
            # Mark the invite as declined, notify the sender, and return the error.
            handle_invite_capacity_failure(user_id, invite, group)
            error

          error ->
            error
        end
    end
  end

  defp handle_invite_capacity_failure(user_id, invite, group) do
    user = Gamend.Accounts.get_user(user_id)
    user_name = Gamend.Accounts.display_name(user)
    group_id = group.id

    # Mark the invite as declined so the sender sees it didn't go through
    from(i in GroupInvite,
      where:
        i.recipient_id == ^user_id and i.group_id == ^group_id and
          i.status == "pending"
    )
    |> Repo.update_all(set: [status: "declined", updated_at: DateTime.utc_now()])

    Shared.invalidate_invite_cache_sync(user_id)
    Shared.invalidate_invite_cache_sync(invite.sender_id)

    # Retract the original invite notification
    Gamend.Notifications.delete_notification_by(
      invite.sender_id,
      user_id,
      "Invited to #{group.title}"
    )

    # Notify the sender that the invite was declined because the group is full
    Gamend.Notifications.admin_create_notification(
      user_id,
      invite.sender_id,
      %{
        "title" => "#{user_name} couldn't join #{group.title} — full",
        "content" => "",
        "metadata" => %{
          "type" => "group_invite_declined",
          "group_id" => group_id,
          "group_title" => group.title,
          "user_id" => user_id,
          "user_name" => user_name,
          "reason" => "full"
        }
      }
    )

    # Real-time PubSub so the sender's UI updates immediately
    Gamend.Broadcast.publish(
      "user:#{invite.sender_id}",
      {:group_invite_declined, %{group_id: group_id, user_id: user_id, reason: "full"}}
    )
  end

  defp finalize_invite_accept(user_id, group_id, group, invite) do
    # Mark all pending invites for this user + group as accepted
    from(i in GroupInvite,
      where:
        i.recipient_id == ^user_id and i.group_id == ^group_id and
          i.status == "pending"
    )
    |> Repo.update_all(set: [status: "accepted", updated_at: DateTime.utc_now()])

    Shared.invalidate_invite_cache_sync(user_id)
    Shared.invalidate_invite_cache_sync(invite.sender_id)

    # Notify the sender that the invite was accepted
    user = Gamend.Accounts.get_user(user_id)
    user_name = Gamend.Accounts.display_name(user)

    Gamend.Notifications.admin_create_notification(
      user_id,
      invite.sender_id,
      %{
        "title" => "#{user_name} joined #{group.title}",
        "content" => "",
        "metadata" => %{
          "type" => "group_invite_accepted",
          "group_id" => group_id,
          "group_title" => group.title,
          "user_id" => user_id,
          "user_name" => user_name
        }
      }
    )

    # Broadcast so the sender's LiveView refreshes
    Gamend.Broadcast.publish(
      "user:#{invite.sender_id}",
      {:group_invite_accepted, %{group_id: group_id}}
    )

    Gamend.Async.run(fn ->
      Gamend.Hooks.internal_call(:after_group_join, [user_id, group])
    end)
  end

  # ---------------------------------------------------------------------------
  # Invitations list
  # ---------------------------------------------------------------------------

  @doc """
  List pending group invitations for a user.
  """
  @spec list_invitations(Ecto.UUID.t(), keyword()) :: [map()]
  def list_invitations(user_id, opts \\ []) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    do_list_invitations(user_id, page, page_size)
  end

  @decorate cacheable(
              key:
                {:group_invites, :list, Shared.invite_cache_version(user_id), user_id, page,
                 page_size},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp do_list_invitations(user_id, page, page_size) do
    import Ecto.Query

    from(i in GroupInvite,
      where: i.recipient_id == ^user_id and i.status == "pending",
      join: g in assoc(i, :group),
      join: s in assoc(i, :sender),
      join: r in assoc(i, :recipient),
      order_by: [desc: i.inserted_at],
      offset: ^((page - 1) * page_size),
      limit: ^page_size,
      preload: [group: g, sender: s, recipient: r]
    )
    |> Repo.all()
    |> Enum.map(&serialize_group_invite/1)
  end

  @doc """
  List group invitations sent by a user.
  """
  @spec list_sent_invitations(Ecto.UUID.t(), keyword()) :: [map()]
  def list_sent_invitations(user_id, opts \\ []) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    do_list_sent_invitations(user_id, page, page_size)
  end

  @decorate cacheable(
              key:
                {:group_invites, :list_sent, Shared.invite_cache_version(user_id), user_id, page,
                 page_size},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp do_list_sent_invitations(user_id, page, page_size) do
    import Ecto.Query

    from(i in GroupInvite,
      where: i.sender_id == ^user_id and i.status == "pending",
      join: g in assoc(i, :group),
      join: s in assoc(i, :sender),
      join: r in assoc(i, :recipient),
      order_by: [desc: i.inserted_at],
      offset: ^((page - 1) * page_size),
      limit: ^page_size,
      preload: [group: g, sender: s, recipient: r]
    )
    |> Repo.all()
    |> Enum.map(&serialize_group_invite/1)
  end

  @doc """
  Cancel (delete) a group invitation that the current user sent.
  Only the sender can cancel their own invitation.
  """
  @spec cancel_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def cancel_invite(user_id, invite_id)
      when is_binary(user_id) and is_binary(invite_id) do
    case Repo.get(GroupInvite, invite_id) do
      nil ->
        {:error, :not_found}

      %GroupInvite{sender_id: ^user_id, status: "pending"} = invite ->
        Repo.delete(invite)
        Shared.invalidate_invite_cache(user_id)
        Shared.invalidate_invite_cache(invite.recipient_id)

        # Retract the invite notification
        group = Groups.get_group(invite.group_id)
        group_title = (group && group.title) || ""

        Gamend.Notifications.delete_notification_by(
          user_id,
          invite.recipient_id,
          "Invited to #{group_title}"
        )

        :ok

      %GroupInvite{status: "pending"} ->
        {:error, :not_owner}

      _other ->
        {:error, :not_found}
    end
  end

  @doc """
  Decline a pending group invite by **invite_id**.
  Only the recipient can decline. The invite is marked as `"declined"`
  (not deleted) so the sender can see the outcome.
  """
  @spec decline_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def decline_invite(user_id, invite_id)
      when is_binary(user_id) and is_binary(invite_id) do
    case Repo.get(GroupInvite, invite_id) do
      %GroupInvite{recipient_id: ^user_id, status: "pending"} = invite ->
        from(i in GroupInvite,
          where:
            i.recipient_id == ^user_id and i.group_id == ^invite.group_id and
              i.status == "pending"
        )
        |> Repo.update_all(set: [status: "declined", updated_at: DateTime.utc_now()])

        Shared.invalidate_invite_cache(user_id)
        Shared.invalidate_invite_cache(invite.sender_id)

        # Retract the invite notification for the recipient
        group = Groups.get_group(invite.group_id)
        group_title = (group && group.title) || ""

        Gamend.Notifications.delete_notification_by(
          invite.sender_id,
          user_id,
          "Invited to #{group_title}"
        )

        # Notify the sender that the invite was declined
        user = Gamend.Accounts.get_user(user_id)
        user_name = Gamend.Accounts.display_name(user)

        Gamend.Notifications.admin_create_notification(
          user_id,
          invite.sender_id,
          %{
            "title" => "#{user_name} declined #{group_title} invite",
            "content" => "",
            "metadata" => %{
              "type" => "group_invite_declined",
              "group_id" => invite.group_id,
              "group_title" => group_title,
              "user_id" => user_id,
              "user_name" => user_name
            }
          }
        )

        # Notify the sender via PubSub
        Gamend.Broadcast.publish(
          "user:#{invite.sender_id}",
          {:group_invite_declined, %{group_id: invite.group_id, user_id: user_id}}
        )

        :ok

      _other ->
        {:error, :not_found}
    end
  end

  defp serialize_group_invite(invite) do
    %{
      id: invite.id,
      group_id: invite.group_id,
      group_title: invite.group.title,
      sender_id: invite.sender_id,
      sender_name: Gamend.Accounts.display_name(invite.sender),
      recipient_id: invite.recipient_id,
      recipient_name: Gamend.Accounts.display_name(invite.recipient),
      status: invite.status,
      inserted_at: invite.inserted_at
    }
  end
end
