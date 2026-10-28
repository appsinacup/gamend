defmodule Gamend.Groups.InviteLinks do
  @moduledoc """
  A group's invite link: an admin makes one, shares it anywhere, and whoever
  opens it while signed in joins the group as a member, without an invite of
  their own or a request to approve. It works for every group type, hidden
  ones too, and is a pull, like a class code: the person chooses to join,
  nobody is added to anything.

  One link per group. It lasts `link_days` (`GAMEND_GROUPS_LINK_DAYS`, 7 by
  default, 0 turns links off); making a new one replaces the old, which
  stops working at once, and an admin may turn it off. It also stops working
  when the admin who made it is no longer one, so a demoted or departed
  admin's link does not keep letting people in.

  Joining through it takes the same room checks and `before_group_join`
  hook as any other join (source `"invite_link"`), and tells the admin who
  made the link, as an accepted invite does.

  Public API is re-exported by `Gamend.Groups`.
  """

  import Ecto.Query, warn: false

  alias Gamend.Groups
  alias Gamend.Groups.GroupInviteLink
  alias Gamend.Groups.GroupMember
  alias Gamend.Groups.Shared
  alias Gamend.Repo

  @token_bytes 16

  @doc "How many days a new link lasts (`link_days`); 0 when links are off."
  @spec link_days() :: non_neg_integer()
  def link_days, do: max(Gamend.Settings.get(Groups, :link_days) || 0, 0)

  @doc "Whether groups may have invite links (`link_days` above 0)."
  @spec links?() :: boolean()
  def links?, do: link_days() > 0

  @doc """
  A group's link, while it works: not expired, links on, its maker still an
  admin. Nil otherwise. For the group's admins to show and copy.
  """
  @spec get_invite_link(Ecto.UUID.t()) :: GroupInviteLink.t() | nil
  def get_invite_link(group_id) when is_binary(group_id) do
    GroupInviteLink
    |> where([l], l.group_id == ^group_id)
    |> Repo.one()
    |> working()
  end

  @doc """
  The working link a token opens, its group preloaded, or nil: an unknown
  token, an expired or replaced link, and one whose maker is no longer an
  admin all read the same to whoever holds it.
  """
  @spec get_invite_link_by_token(String.t()) :: GroupInviteLink.t() | nil
  def get_invite_link_by_token(token) when is_binary(token) do
    GroupInviteLink
    |> where([l], l.token == ^token)
    |> preload([:group, :created_by])
    |> Repo.one()
    |> working()
  end

  def get_invite_link_by_token(_token), do: nil

  defp working(nil), do: nil

  defp working(%GroupInviteLink{} = link) do
    if links?() and DateTime.after?(link.expires_at, DateTime.utc_now()) and
         is_binary(link.created_by_id) and
         Groups.can_manage_group?(link.created_by_id, link.group_id),
       do: link
  end

  @doc """
  Make a group's link, replacing the one it had: a new token, lasting
  `link_days` from now. Admins only.
  """
  @spec create_invite_link(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupInviteLink.t()} | {:error, :links_off | :not_found | :not_admin | term()}
  def create_invite_link(admin_id, group_id) when is_binary(admin_id) and is_binary(group_id) do
    with :ok <- check_admin(admin_id, group_id) do
      now = DateTime.utc_now(:second)
      token = new_token()
      expires_at = DateTime.add(now, link_days(), :day)

      %GroupInviteLink{}
      |> GroupInviteLink.changeset(%{
        group_id: group_id,
        created_by_id: admin_id,
        token: token,
        expires_at: expires_at
      })
      |> Repo.insert(
        on_conflict: [
          set: [
            created_by_id: admin_id,
            token: token,
            expires_at: expires_at,
            uses: 0,
            updated_at: now
          ]
        ],
        conflict_target: :group_id,
        returning: true
      )
    end
  end

  @doc "Turn a group's link off. Admins only."
  @spec delete_invite_link(Ecto.UUID.t(), Ecto.UUID.t()) ::
          :ok | {:error, :links_off | :not_found | :not_admin}
  def delete_invite_link(admin_id, group_id) when is_binary(admin_id) and is_binary(group_id) do
    with :ok <- check_admin(admin_id, group_id) do
      GroupInviteLink |> where([l], l.group_id == ^group_id) |> Repo.delete_all()
      :ok
    end
  end

  defp check_admin(admin_id, group_id) do
    cond do
      not links?() -> {:error, :links_off}
      is_nil(Groups.get_group(group_id)) -> {:error, :not_found}
      not Groups.can_manage_group?(admin_id, group_id) -> {:error, :not_admin}
      true -> :ok
    end
  end

  @doc """
  Join the group a link opens, as a member. `{:error, :not_found}` for a
  link that does not work (see `get_invite_link_by_token/1`),
  `{:error, :already_member}` for someone already in it, and the room
  checks' `:full` and `:too_many_groups`.
  """
  @spec join_by_invite_link(Ecto.UUID.t(), String.t()) ::
          {:ok, GroupMember.t()} | {:error, atom()}
  def join_by_invite_link(user_id, token) when is_binary(user_id) do
    case get_invite_link_by_token(token) do
      nil -> {:error, :not_found}
      link -> join(link, user_id)
    end
  end

  defp join(%GroupInviteLink{group: group} = link, user_id) do
    cond do
      Groups.member?(group.id, user_id) ->
        {:error, :already_member}

      Gamend.Friends.blocked?(link.created_by_id, user_id) ->
        {:error, :blocked}

      true ->
        case Shared.do_add_group_member(user_id, group.id, group, "invite_link") do
          {:ok, member} ->
            GroupInviteLink |> where([l], l.id == ^link.id) |> Repo.update_all(inc: [uses: 1])
            Shared.mark_pending_invites_accepted(user_id, group.id)
            tell_maker(link, user_id)

            Gamend.Async.run(fn ->
              Gamend.Hooks.internal_call(:after_group_join, [user_id, group])
            end)

            {:ok, member}

          error ->
            error
        end
    end
  end

  # The admin who made the link hears who joined through it, as the sender
  # of an accepted invite does.
  defp tell_maker(%GroupInviteLink{created_by_id: maker_id, group: group}, user_id)
       when maker_id != user_id do
    user_name = Gamend.Accounts.display_name(Gamend.Accounts.get_user(user_id))

    Gamend.Notifications.admin_create_notification(user_id, maker_id, %{
      "title" => "#{user_name} joined #{group.title}",
      "content" => "",
      "metadata" => %{
        "type" => "group_invite_accepted",
        "group_id" => group.id,
        "group_title" => group.title,
        "user_id" => user_id,
        "user_name" => user_name
      }
    })

    Gamend.Broadcast.publish("user:#{maker_id}", {:group_invite_accepted, %{group_id: group.id}})
  end

  defp tell_maker(_link, _user_id), do: :ok

  defp new_token, do: Base.url_encode64(:crypto.strong_rand_bytes(@token_bytes), padding: false)
end
