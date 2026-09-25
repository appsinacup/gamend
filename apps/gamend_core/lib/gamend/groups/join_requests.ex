defmodule Gamend.Groups.JoinRequests do
  @moduledoc """
  Join requests for private groups: requesting, listing, approving,
  rejecting, and cancelling.

  Public API is re-exported by `Gamend.Groups`.
  """

  import Ecto.Query, warn: false

  alias Gamend.Groups
  alias Gamend.Groups.GroupJoinRequest
  alias Gamend.Groups.GroupMember
  alias Gamend.Groups.Shared
  alias Gamend.Repo
  alias Gamend.Repo.AdvisoryLock

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
          {:ok, GroupJoinRequest.t()} | {:error, atom()}
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
          %GroupJoinRequest{}
          |> GroupJoinRequest.changeset(%{group_id: group_id, user_id: user_id})
          |> Repo.insert(
            on_conflict: {:replace, [:status, :updated_at]},
            conflict_target: [:group_id, :user_id]
          )
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
          {:ok, GroupMember.t()} | {:error, atom()}
  def approve_join_request(admin_id, request_id)
      when is_binary(admin_id) and is_binary(request_id) do
    case Repo.get(GroupJoinRequest, request_id) do
      nil ->
        {:error, :not_found}

      %GroupJoinRequest{status: status} when status != "pending" ->
        {:error, :not_pending}

      %GroupJoinRequest{group_id: group_id} = request ->
        group = Groups.get_group!(group_id)

        if Groups.can_manage_group?(admin_id, group_id) do
          approve_join_request_with_hook(request, group, admin_id, request_id)
        else
          {:error, :not_admin}
        end
    end
  end

  defp approve_join_request_with_hook(request, group, admin_id, request_id) do
    group_id = request.group_id
    user_id = request.user_id

    case Shared.run_before_group_join_hook(user_id, group, %{
           "source" => "join_request_approval",
           "request_id" => request_id,
           "actor_user_id" => admin_id,
           "admin_id" => admin_id
         }) do
      :ok ->
        Ecto.Multi.new()
        |> Ecto.Multi.run(:lock_and_check, fn _repo, _changes ->
          AdvisoryLock.lock(:group, group_id)

          if Groups.count_group_members(group_id) >= group.max_members do
            {:error, :full}
          else
            {:ok, :space_available}
          end
        end)
        |> Ecto.Multi.update(:request, Ecto.Changeset.change(request, %{status: "accepted"}))
        |> Ecto.Multi.insert(:membership, fn _changes ->
          GroupMember.changeset(%GroupMember{}, %{
            group_id: group_id,
            user_id: user_id,
            role: "member"
          })
        end)
        |> Gamend.AfterCommit.transaction()
        |> case do
          {:ok, %{membership: member}} ->
            _ = Shared.invalidate_group_cache(group_id)
            Shared.mark_pending_invites_accepted(user_id, group_id)
            Shared.broadcast_group(group_id, {:join_request_approved, group_id, user_id})
            Shared.broadcast_group(group_id, {:member_joined, group_id, user_id})

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

          {:error, _op, changeset, _} ->
            {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
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
          |> Ecto.Changeset.change(%{status: "rejected"})
          |> Repo.update()
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
        case Repo.delete(request) do
          {:ok, deleted} ->
            Shared.broadcast_group(
              request.group_id,
              {:join_request_cancelled, request.group_id, user_id}
            )

            {:ok, deleted}

          error ->
            error
        end

      %GroupJoinRequest{status: status} when status != "pending" ->
        {:error, :not_pending}

      _other ->
        {:error, :not_owner}
    end
  end
end
