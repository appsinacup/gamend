defmodule Gamend.Groups.JoinRequests do
  @moduledoc """
  Join requests for private groups: requesting, listing, approving,
  rejecting, and cancelling.

  Public API is re-exported by `Gamend.Groups`.
  """

  import Ecto.Query, warn: false

  alias Gamend.Groups
  alias Gamend.Groups.Group
  alias Gamend.Groups.GroupJoinRequest
  alias Gamend.Groups.GroupMember
  alias Gamend.Groups.Shared
  alias Gamend.Repo

  @doc "List pending join requests sent by a user."
  @spec list_user_pending_requests(Ecto.UUID.t()) :: [GroupJoinRequest.t()]
  def list_user_pending_requests(user_id) when is_binary(user_id) do
    from(r in GroupJoinRequest,
      where: r.user_id == ^user_id and r.status == "pending",
      join: g in assoc(r, :group),
      order_by: [desc: r.inserted_at],
      preload: [group: g]
    )
    |> Repo.all()
  end

  @doc """
  Request to join a private group. Creates a pending join request.
  """
  @spec request_join(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupJoinRequest.t()} | {:error, atom() | Ecto.Changeset.t()}
  def request_join(user_id, group_id)
      when is_binary(user_id) and is_binary(group_id) do
    group = Groups.get_group(group_id)

    cond do
      is_nil(group) ->
        {:error, :not_found}

      group.type != "private" ->
        {:error, :not_private}

      Groups.member?(group_id, user_id) ->
        {:error, :already_member}

      true ->
        # Check for existing pending request
        existing =
          Repo.get_by(GroupJoinRequest,
            group_id: group_id,
            user_id: user_id,
            status: "pending"
          )

        if existing do
          # Idempotent: return existing pending request instead of erroring
          {:ok, existing}
        else
          # The group read above may have been deleted since.
          Repo.rescue_foreign_key(:not_found, fn ->
            %GroupJoinRequest{}
            |> GroupJoinRequest.changeset(%{group_id: group_id, user_id: user_id})
            |> Repo.insert(
              on_conflict: {:replace, [:status, :updated_at]},
              conflict_target: [:group_id, :user_id]
            )
          end)
          |> case do
            {:ok, request} ->
              Shared.broadcast_group(group_id, {:join_request_created, group_id, user_id})
              notify_admins_of_join_request(user_id, group_id, group)
              {:ok, request}

            error ->
              error
          end
        end
    end
  end

  defp notify_admins_of_join_request(user_id, group_id, group) do
    user = Gamend.Accounts.get_user(user_id)
    user_name = Gamend.Accounts.display_name(user)

    admins =
      from(m in GroupMember,
        where: m.group_id == ^group_id and m.role == "admin",
        select: m.user_id
      )
      |> Repo.all()

    for admin_id <- admins do
      Gamend.Notifications.admin_create_notification(
        user_id,
        admin_id,
        %{
          "title" => "#{user_name} wants to join #{group.title}",
          "content" => "",
          "metadata" => %{
            "type" => "group_join_request",
            "group_id" => group_id,
            "group_title" => group.title,
            "user_id" => user_id,
            "user_name" => user_name
          }
        }
      )
    end
  end

  @doc "List pending join requests for a group (admin only)."
  @spec list_join_requests(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, [GroupJoinRequest.t()]} | {:error, atom()}
  def list_join_requests(admin_id, group_id, opts \\ [])
      when is_binary(admin_id) and is_binary(group_id) do
    if Groups.can_manage_group?(admin_id, group_id) do
      page = Keyword.get(opts, :page, 1)
      page_size = Keyword.get(opts, :page_size, 25)
      offset = (page - 1) * page_size

      requests =
        from(r in GroupJoinRequest,
          where: r.group_id == ^group_id and r.status == "pending",
          order_by: [asc: r.inserted_at],
          limit: ^page_size,
          offset: ^offset,
          preload: [:user]
        )
        |> Repo.all()

      {:ok, requests}
    else
      {:error, :not_admin}
    end
  end

  @spec count_join_requests(Ecto.UUID.t()) :: non_neg_integer()
  def count_join_requests(group_id) when is_binary(group_id) do
    Repo.one(
      from(r in GroupJoinRequest,
        where: r.group_id == ^group_id and r.status == "pending",
        select: count(r.id)
      )
    ) || 0
  end

  @doc "Approve a pending join request. Admin only."
  @spec approve_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupMember.t()}
          | {:error, atom() | {:hook_rejected, term()} | Ecto.Changeset.t()}
  def approve_join_request(admin_id, request_id)
      when is_binary(admin_id) and is_binary(request_id) do
    case Repo.get(GroupJoinRequest, request_id) do
      nil ->
        {:error, :not_found}

      %GroupJoinRequest{status: status} when status != "pending" ->
        {:error, :not_pending}

      %GroupJoinRequest{group_id: group_id} = request ->
        with true <- Groups.can_manage_group?(admin_id, group_id) || {:error, :not_admin},
             %Group{} = group <- Groups.get_group(group_id) || {:error, :not_found} do
          approve_join_request_with_hook(request, group, admin_id, request_id)
        end
    end
  end

  # The seat is the join's (`Shared.do_add_group_member/5`): the group's room
  # and the player's cap on groups checked under the locks a join takes, and
  # the request moved from pending to accepted inside that transaction. The
  # approve used to write "accepted" over whatever the request was by then, so
  # with a reject landing too the player ended a member with a rejected
  # request and both answers in their notifications.
  defp approve_join_request_with_hook(request, group, admin_id, request_id) do
    group_id = request.group_id
    user_id = request.user_id

    hook_opts = %{
      "source" => "join_request_approval",
      "request_id" => request_id,
      "actor_user_id" => admin_id,
      "admin_id" => admin_id
    }

    claim = fn ->
      with {:ok, _accepted} <- answer_request(request, "accepted"), do: :ok
    end

    case Shared.do_add_group_member(user_id, group_id, group, hook_opts, claim) do
      {:ok, member} ->
        Shared.mark_pending_invites_accepted(user_id, group_id)
        Shared.broadcast_group(group_id, {:join_request_approved, group_id, user_id})

        # Notify the user that their join request was approved
        admin = Gamend.Accounts.get_user(admin_id)
        admin_name = Gamend.Accounts.display_name(admin)

        Gamend.Notifications.admin_create_notification(
          admin_id,
          user_id,
          %{
            "title" => "Approved to join #{group.title}",
            "content" => "",
            "metadata" => %{
              "type" => "group_join_request_approved",
              "group_id" => group_id,
              "group_title" => group.title,
              "admin_id" => admin_id,
              "admin_name" => admin_name
            }
          }
        )

        Gamend.Broadcast.publish(
          "user:#{user_id}",
          {:group_join_request_approved, %{group_id: group_id}}
        )

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_group_join, [user_id, group])
        end)

        {:ok, member}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Pending to `status`, or nothing: of an approve, a reject and a cancel
  # landing together exactly one moves the request, and only that one tells
  # anyone. The losers answer `:not_pending`, or `:not_found` for a request
  # cancelled (or its group deleted) first.
  defp answer_request(%GroupJoinRequest{id: id}, status) do
    from(r in GroupJoinRequest, where: r.id == ^id and r.status == "pending")
    |> Repo.compare_and_set(set: [status: status, updated_at: DateTime.utc_now(:second)])
    |> case do
      {:ok, answered} -> {:ok, answered}
      {:error, :precondition_failed} -> {:error, answered_or_gone(id)}
    end
  end

  defp answered_or_gone(id) do
    if Repo.get(GroupJoinRequest, id), do: :not_pending, else: :not_found
  end

  @doc "Reject a pending join request. Admin only."
  @spec reject_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupJoinRequest.t()} | {:error, atom()}
  def reject_join_request(admin_id, request_id)
      when is_binary(admin_id) and is_binary(request_id) do
    case Repo.get(GroupJoinRequest, request_id) do
      nil ->
        {:error, :not_found}

      %GroupJoinRequest{status: status} when status != "pending" ->
        {:error, :not_pending}

      %GroupJoinRequest{group_id: group_id} = request ->
        if Groups.can_manage_group?(admin_id, group_id) do
          request
          |> answer_request("rejected")
          |> case do
            {:ok, updated} ->
              Shared.broadcast_group(
                group_id,
                {:join_request_rejected, group_id, updated.user_id}
              )

              # Notify the user that their join request was rejected
              group = Groups.get_group(group_id)
              group_title = (group && group.title) || ""

              Gamend.Notifications.admin_create_notification(
                admin_id,
                updated.user_id,
                %{
                  "title" => "Declined from #{group_title}",
                  "content" => "",
                  "metadata" => %{
                    "type" => "group_join_request_rejected",
                    "group_id" => group_id,
                    "group_title" => group_title
                  }
                }
              )

              Gamend.Broadcast.publish(
                "user:#{updated.user_id}",
                {:group_join_request_rejected, %{group_id: group_id}}
              )

              {:ok, updated}

            error ->
              error
          end
        else
          {:error, :not_admin}
        end
    end
  end

  @doc "Cancel (delete) a pending join request. Only the requesting user can cancel."
  @spec cancel_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupJoinRequest.t()} | {:error, atom()}
  def cancel_join_request(user_id, request_id)
      when is_binary(user_id) and is_binary(request_id) do
    case Repo.get(GroupJoinRequest, request_id) do
      nil ->
        {:error, :not_found}

      %GroupJoinRequest{user_id: ^user_id, status: "pending"} = request ->
        # Deleted only while still pending: an approve that claimed it first
        # has seated the player.
        case Repo.delete_all(
               from(r in GroupJoinRequest, where: r.id == ^request.id and r.status == "pending")
             ) do
          {1, _} ->
            Shared.broadcast_group(
              request.group_id,
              {:join_request_cancelled, request.group_id, user_id}
            )

            {:ok, request}

          {0, _} ->
            {:error, answered_or_gone(request.id)}
        end

      %GroupJoinRequest{status: status} when status != "pending" ->
        {:error, :not_pending}

      _other ->
        {:error, :not_owner}
    end
  end
end
