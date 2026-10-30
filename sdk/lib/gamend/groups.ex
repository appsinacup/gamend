defmodule Gamend.Groups do
  @moduledoc ~S"""
  Context module for group management: creating, updating, listing, joining,
  leaving, kicking, promoting/demoting members, and handling join requests.

  Groups are persistent communities (unlike ephemeral lobbies). They support
  three visibility types:

  - **public** – anyone can join directly
  - **private** – anyone can request to join; an admin must approve
  - **hidden** – only invited users can join (via notifications / invite API)

  A host picks which of them players may use (`types`), whom an admin may
  invite (`invites`), how long an invite link lasts (`link_days`), whether
  every group holds the same number of members (`max_members`) and whether
  two groups may share a title (`unique_titles`). Forge and Gamend Cloud,
  whose groups are teams of colleagues, allow `hidden` alone, invite
  `anyone`, hold 100 and let titles repeat.

  A group's slug is its name in a URL, unique per creator, and reads
  `<owner>/<slug>` with the creator's username (`full_slug/1`,
  `get_group_by_full_slug/1`). One is made from the title when none is
  given.

  A group's icon is its `icon_url`: an uploaded image (`set_icon_url/3`), or
  one of the site's own icons, `/icons/<name>.svg` (`Gamend.Icons`), which
  create and update take as any other value. A new group given none gets one
  of them at random, and forms start a new group from a random title and icon
  (`change_new_group/0`).

  ## Usage

      # Create a group (creator becomes admin)
      {:ok, group} = Groups.create_group(user_id, %{"title" => "Cool Group"})

      # List public/private groups (hidden excluded)
      groups = Groups.list_groups(%{}, page: 1, page_size: 25)

      # Join a public group
      {:ok, member} = Groups.join_group(user_id, group.id)

      # Request to join a private group
      {:ok, request} = Groups.request_join(user_id, group.id)

      # Admin approves a join request
      {:ok, member} = Groups.approve_join_request(admin_id, request.id)

  ## PubSub Events

  - `"groups"` topic:
    - `{:group_created, group}`
    - `{:group_updated, group}`
    - `{:group_deleted, group_id}`

  - `"group:<group_id>"` topic:
    - `{:member_joined, group_id, user_id}`
    - `{:member_left, group_id, user_id}`
    - `{:member_kicked, group_id, user_id}`
    - `{:member_promoted, group_id, user_id}`
    - `{:member_demoted, group_id, user_id}`
    - `{:group_updated, group}`
    - `{:join_request_created, group_id, user_id}`
    - `{:join_request_approved, group_id, user_id}`
    - `{:join_request_rejected, group_id, user_id}`
    - `{:group_notification, group_id, sender_id}`


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    Accept a pending group invite by **invite_id**.
    The user must be the recipient of the invite.
    Works for all group types (public, private, hidden).
    
  """
  @spec accept_invite(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
  def accept_invite(_user_id, _invite_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.accept_invite/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Admin-level delete (no membership check, for server admins).
  """
  @spec admin_delete_group(Ecto.UUID.t()) :: {:ok, Gamend.Groups.Group.t()} | {:error, term()}
  def admin_delete_group(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.admin_delete_group/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Admin-level update, bypasses membership checks.
  """
  @spec admin_update_group(Gamend.Groups.Group.t(), map()) ::
          {:ok, Gamend.Groups.Group.t()} | {:error, Ecto.Changeset.t()}
  def admin_update_group(_group, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.admin_update_group/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Approve a pending join request. Admin only.
  """
  @spec approve_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
  def approve_join_request(_admin_id, _request_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.approve_join_request/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Batch count members for a list of group IDs. Returns a map of group_id => count.
  """
  @spec batch_member_counts([Ecto.UUID.t()]) :: %{required(Ecto.UUID.t()) => non_neg_integer()}
  def batch_member_counts(_group_ids) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Groups.batch_member_counts/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Broadcast a presence event (e.g. member_online, member_updated) to a group topic.
  """
  @spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
  def broadcast_member_presence(_group_id, _event) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Groups.broadcast_member_presence/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether `user` holds authority over `group` — its admin members, nobody else.
    
    Subject first, resource second, like every other `can_*?` predicate (see
    `Gamend.Policy`). Both arguments take a struct or a bare id.
    
  """
  @spec can_manage_group?(
          Gamend.Accounts.User.t() | Ecto.UUID.t() | nil,
          Gamend.Groups.Group.t() | Ecto.UUID.t() | nil
        ) :: boolean()
  def can_manage_group?(_user_id, _group) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Groups.can_manage_group?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Cancel (delete) a pending group invitation: one the current user sent, or
    any of a group they are an admin of, as its page lists them
    (`list_group_invites/3`).
    
  """
  @spec cancel_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def cancel_invite(_user_id, _invite_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Groups.cancel_invite/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Cancel (delete) a pending join request. Only the requesting user can cancel.
  """
  @spec cancel_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupJoinRequest.t()} | {:error, atom()}
  def cancel_join_request(_user_id, _request_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.cancel_join_request/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Return a changeset for tracking group changes (admin edit forms).
  """
  @spec change_group(Gamend.Groups.Group.t(), map()) :: Ecto.Changeset.t()
  def change_group(_group, _attrs \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Groups.change_group/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A new group's form to start from: a random title (`random_title/0`), the
    slug made from it, and a random icon of the site's (`Gamend.Icons.random/0`).
    
  """
  @spec change_new_group() :: Ecto.Changeset.t()
  def change_new_group() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Groups.change_new_group/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count ALL groups matching filters (admin).
  """
  @spec count_all_groups(map()) :: non_neg_integer()
  def count_all_groups(_filters \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_all_groups/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Total member count across all groups.
  """
  @spec count_all_members() :: non_neg_integer()
  def count_all_members() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_all_members/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count a group's pending invitations.
  """
  @spec count_group_invites(Ecto.UUID.t()) :: non_neg_integer()
  def count_group_invites(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_group_invites/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count members in a group. Accepts the same `:search` option as the listing.
  """
  @spec count_group_members(Ecto.UUID.t()) :: non_neg_integer()
  def count_group_members(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_group_members/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count members in a group. Accepts the same `:search` option as the listing.
  """
  @spec count_group_members(
          Ecto.UUID.t(),
          keyword()
        ) :: non_neg_integer()
  def count_group_members(_group_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_group_members/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count groups by type.
  """
  @spec count_groups_by_type(String.t()) :: non_neg_integer()
  def count_groups_by_type(_type) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_groups_by_type/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count how many groups a user has created (is admin of).
  """
  @spec count_groups_created_by(Ecto.UUID.t()) :: non_neg_integer()
  def count_groups_created_by(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_groups_created_by/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count pending invitations for a user.
  """
  @spec count_invitations(Ecto.UUID.t()) :: non_neg_integer()
  def count_invitations(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_invitations/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec count_join_requests(Ecto.UUID.t()) :: non_neg_integer()
  def count_join_requests(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_join_requests/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count groups matching public filters (excludes hidden).
  """
  @spec count_list_groups(map()) :: non_neg_integer()
  def count_list_groups(_filters \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_list_groups/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count group invitations sent by a user.
  """
  @spec count_sent_invitations(Ecto.UUID.t()) :: non_neg_integer()
  def count_sent_invitations(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_sent_invitations/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count how many groups a user is a member of (any role).
  """
  @spec count_user_group_memberships(Ecto.UUID.t()) :: non_neg_integer()
  def count_user_group_memberships(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_user_group_memberships/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count groups the user belongs to.
  """
  @spec count_user_groups(Ecto.UUID.t()) :: non_neg_integer()
  def count_user_groups(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.count_user_groups/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Create a new group. The creating user becomes an admin member automatically.
    
  """
  @spec create_group(Ecto.UUID.t(), map()) ::
          {:ok, Gamend.Groups.Group.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_group(_user_id, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.create_group/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Make a group's link, replacing the one it had: a new token, lasting
    `link_days` from now. Admins only.
    
  """
  @spec create_invite_link(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupInviteLink.t()}
          | {:error, :links_off | :not_found | :not_admin | term()}
  def create_invite_link(_admin_id, _group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.create_invite_link/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Decline a pending group invite by **invite_id**.
    Only the recipient can decline. The invite is marked as `"declined"`
    (not deleted) so the sender can see the outcome.
    
  """
  @spec decline_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def decline_invite(_user_id, _invite_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Groups.decline_invite/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete a group. Any of its admins can, members or not: everyone in it is
    removed with it and told, as a kick tells one member.
    
  """
  @spec delete_group(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.Group.t()} | {:error, term()}
  def delete_group(_user_id, _group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.delete_group/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Turn a group's link off. Admins only.
  """
  @spec delete_invite_link(Ecto.UUID.t(), Ecto.UUID.t()) ::
          :ok | {:error, :links_off | :not_found | :not_admin}
  def delete_invite_link(_admin_id, _group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Groups.delete_invite_link/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Demote an admin to member. Only admins can demote other admins.
  """
  @spec demote_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
  def demote_member(_admin_id, _group_id, _target_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.demote_member/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Every group's member cap when the host fixes it (`max_members`), else nil.
  """
  @spec fixed_max_members() :: pos_integer() | nil
  def fixed_max_members() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Groups.fixed_max_members/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The slug a new group of `user_id`'s titled `title` gets: its nearest free one.
  """
  @spec free_slug(Ecto.UUID.t(), String.t() | nil) :: String.t()
  def free_slug(_user_id, _title) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "Gamend.Groups.free_slug/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A group's name in a URL: `<owner>/<slug>`, the owner its creator's
    username. A group whose creator is gone, or has no username, is its id.
    A username changed moves it, as on GitHub.
    
  """
  @spec full_slug(Gamend.Groups.Group.t()) :: String.t()
  def full_slug(_group) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "Gamend.Groups.full_slug/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a group by ID (cached).
  """
  @spec get_group(Ecto.UUID.t()) :: Gamend.Groups.Group.t() | nil
  def get_group(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Groups.Group{
            id: "",
            title: "",
            slug: "",
            description: "",
            icon_url: nil,
            type: "public",
            max_members: 100,
            metadata: %{},
            slowdown: 0,
            creator_id: nil,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Groups.get_group/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a group by ID (raises if not found, cached).
  """
  @spec get_group!(Ecto.UUID.t()) :: Gamend.Groups.Group.t()
  def get_group!(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Groups.get_group!/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The group a URL names: `<owner>/<slug>` (`full_slug/1`), or its id. Nil
    for neither.
    
  """
  @spec get_group_by_full_slug(String.t()) :: Gamend.Groups.Group.t() | nil
  def get_group_by_full_slug(_ref) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Groups.Group{
            id: "",
            title: "",
            slug: "",
            description: "",
            icon_url: nil,
            type: "public",
            max_members: 100,
            metadata: %{},
            slowdown: 0,
            creator_id: nil,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Groups.get_group_by_full_slug/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a group by its title: the oldest of that title when the host lets
    titles repeat (`unique_titles`).
    
  """
  @spec get_group_by_title(String.t()) :: Gamend.Groups.Group.t() | nil
  def get_group_by_title(_title) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Groups.Group{
            id: "",
            title: "",
            slug: "",
            description: "",
            icon_url: nil,
            type: "public",
            max_members: 100,
            metadata: %{},
            slowdown: 0,
            creator_id: nil,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Groups.get_group_by_title/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get all members of a group.
  """
  @spec get_group_members(Ecto.UUID.t()) :: [Gamend.Groups.GroupMember.t()]
  def get_group_members(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.get_group_members/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get paginated members of a group with user info.
    
    Pass `:search` to filter by member name (display name or username).
    
  """
  @spec get_group_members_paginated(
          Ecto.UUID.t(),
          keyword()
        ) :: [Gamend.Groups.GroupMember.t()]
  def get_group_members_paginated(_group_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.get_group_members_paginated/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A group's link, while it works: not expired, links on, its maker still an
    admin. Nil otherwise. For the group's admins to show and copy.
    
  """
  @spec get_invite_link(Ecto.UUID.t()) :: Gamend.Groups.GroupInviteLink.t() | nil
  def get_invite_link(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Groups.get_invite_link/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The working link a token opens, its group preloaded, or nil: an unknown
    token, an expired or replaced link, and one whose maker is no longer an
    admin all read the same to whoever holds it.
    
  """
  @spec get_invite_link_by_token(String.t()) :: Gamend.Groups.GroupInviteLink.t() | nil
  def get_invite_link_by_token(_token) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Groups.get_invite_link_by_token/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a specific membership.
  """
  @spec get_membership(Ecto.UUID.t(), Ecto.UUID.t()) :: Gamend.Groups.GroupMember.t() | nil
  def get_membership(_group_id, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Groups.get_membership/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Just the user ids of a group's members, oldest first.
    
    For callers that only need to address members — chat notification fanout is
    the hot one — where `get_group_members/1` would preload every member's full
    user row only to read `user_id` from it.
    
  """
  @spec group_member_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def group_member_ids(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.group_member_ids/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Clean up group memberships before a user is deleted.
    
    For each group the user belongs to:
    - If the user is the sole admin and other members exist, promotes the oldest
      member to admin before removing the user's membership row.
    - Removes the membership row.
    - If the group has no members left after removal, deletes the group.
    
    This must be called *before* `Repo.delete(user)` so that the membership
    rows still exist (the DB cascade would silently delete them otherwise
    without running the admin-transfer / empty-group logic).
    
  """
  @spec handle_user_deletion(Ecto.UUID.t()) :: :ok
  def handle_user_deletion(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Groups.handle_user_deletion/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Public wrapper for cache invalidation (used by admin controller).
  """
  @spec invalidate_group_cache_public(Ecto.UUID.t()) :: :ok
  def invalidate_group_cache_public(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Groups.invalidate_group_cache_public/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether an admin may invite any account, not only a friend (`invites`).
  """
  @spec invite_anyone?() :: boolean()
  def invite_anyone?() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Groups.invite_anyone?/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    How many days a new link lasts (`link_days`); 0 when links are off.
  """
  @spec invite_link_days() :: non_neg_integer()
  def invite_link_days() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Groups.invite_link_days/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether groups may have invite links (`link_days` above 0).
  """
  @spec invite_links?() :: boolean()
  def invite_links?() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Groups.invite_links?/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
    Returns `{:error, :not_connected}`. A host that sets `Gamend.Groups`'
    `invites` to `anyone` (teams of colleagues) lets an admin invite any account.
    
  """
  @spec invite_to_group(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupInvite.t()} | {:ok, :request_approved} | {:error, atom()}
  def invite_to_group(_admin_id, _group_id, _target_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.invite_to_group/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Join the group a link opens, as a member. `{:error, :not_found}` for a
    link that does not work (see `get_invite_link_by_token/1`),
    `{:error, :already_member}` for someone already in it, and the room
    checks' `:full` and `:too_many_groups`.
    
  """
  @spec join_by_invite_link(Ecto.UUID.t(), String.t()) ::
          {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
  def join_by_invite_link(_user_id, _token) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.join_by_invite_link/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Join a public group directly. Returns error for private/hidden groups.
    
  """
  @spec join_group(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
  def join_group(_user_id, _group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.join_group/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Kick a member from the group. Only admins can kick.
  """
  @spec kick_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
  def kick_member(_admin_id, _group_id, _target_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.kick_member/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Leave a group.
  """
  @spec leave_group(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
  def leave_group(_user_id, _group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.leave_group/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List ALL groups including hidden (admin only).
    
  """
  @spec list_all_groups(
          map(),
          keyword()
        ) :: [Gamend.Groups.Group.t()]
  def list_all_groups(_filters \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.list_all_groups/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A group's pending invitations, newest first, whoever sent them: what its
    admins see on the group's page, to cancel one that should not stand.
    Admins only.
    
  """
  @spec list_group_invites(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, [map()]} | {:error, :not_admin}
  def list_group_invites(_admin_id, _group_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.list_group_invites/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List groups visible to the public (excludes hidden).
    
    ## Filters
    
      * `:title` – prefix search on title (case-insensitive)
      * `:type` – exact match on type (`"public"` or `"private"`)
      * `:min_members` – groups with max_members >= value
      * `:max_members` – groups with max_members <= value
      * `:metadata_key` / `:metadata_value` – filter by metadata entry
    
    ## Options
    
      * `:page` – page number (default 1)
      * `:page_size` – results per page (default 25)
    
  """
  @spec list_groups(
          map(),
          keyword()
        ) :: [Gamend.Groups.Group.t()]
  def list_groups(_filters \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.list_groups/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List pending group invitations for a user.
    
  """
  @spec list_invitations(
          Ecto.UUID.t(),
          keyword()
        ) :: [map()]
  def list_invitations(_user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.list_invitations/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List pending join requests for a group (admin only).
  """
  @spec list_join_requests(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, [Gamend.Groups.GroupJoinRequest.t()]} | {:error, atom()}
  def list_join_requests(_admin_id, _group_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.list_join_requests/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List group invitations sent by a user.
    
  """
  @spec list_sent_invitations(
          Ecto.UUID.t(),
          keyword()
        ) :: [map()]
  def list_sent_invitations(_user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.list_sent_invitations/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List groups the user belongs to.
  """
  @spec list_user_groups(
          Ecto.UUID.t(),
          keyword()
        ) :: [Gamend.Groups.Group.t()]
  def list_user_groups(_user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.list_user_groups/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List groups the user belongs to, together with the membership role, creators loaded (`full_slug/1`).
  """
  @spec list_user_groups_with_role(Ecto.UUID.t()) :: [{Gamend.Groups.Group.t(), String.t()}]
  def list_user_groups_with_role(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.list_user_groups_with_role/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List pending join requests sent by a user.
  """
  @spec list_user_pending_requests(Ecto.UUID.t()) :: [Gamend.Groups.GroupJoinRequest.t()]
  def list_user_pending_requests(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.list_user_pending_requests/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Check if user is a member (any role) of the group.
  """
  @spec member?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def member?(_group_id, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Groups.member?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Send a notification to all members of a group (except the sender).
    
    **Server-side only.** There is deliberately no player-facing endpoint for
    this: one call writes a row, a cache invalidation and a PubSub push *per
    member*, so with `max_group_members` at 10,000 an ordinary member could turn
    one request into ~10,000 of each. Members talk to a group through group chat,
    which costs one row and one topic broadcast and is throttled per group. This
    function is the announcement primitive for plugins and hooks - callers are
    trusted, so it skips both the friends-only check and the per-recipient
    notification cap that `Notifications.send_notification/2` enforces.
    
    The `group_id` / `group_title` are stored in metadata so the client can
    recognise and route it.
    
    ## Options
    
      * `title` – notification title string (default: `"Group Notification"`).
        The title is part of the unique constraint `(sender_id, recipient_id, title)`,
        so different titles create separate notification slots.
    
    Because of the unique constraint on `(sender_id, recipient_id, title)`, a
    new notification from the same sender to the same recipient with the same title
    replaces the previous one (upsert). This prevents spam while keeping the latest
    message.
    
    Returns `{:ok, count}` with the number of notifications sent.
    
  """
  @spec notify_group(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), map()) ::
          {:ok, non_neg_integer()} | {:error, atom()}
  def notify_group(_sender_id, _group_id, _content, _metadata \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.notify_group/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Promote a member to admin. Only admins can promote.
  """
  @spec promote_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupMember.t()} | {:error, atom()}
  def promote_member(_admin_id, _group_id, _target_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.promote_member/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A title for a new group to start from, `Swift Otter` (`Gamend.Slug.random/0`),
    one no group has when titles are unique (`unique_titles`), most draws.
    
  """
  @spec random_title() :: String.t()
  def random_title() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "Gamend.Groups.random_title/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Reject a pending join request. Admin only.
  """
  @spec reject_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupJoinRequest.t()} | {:error, atom()}
  def reject_join_request(_admin_id, _request_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.reject_join_request/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Request to join a private group. Creates a pending join request.
    
  """
  @spec request_join(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupJoinRequest.t()} | {:error, atom()}
  def request_join(_user_id, _group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.request_join/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Set a group's icon to an object we have just accepted an upload for.
    
    Separate from `update_group/3` because that one deliberately drops an
    `icon_url` from caller-supplied attributes unless it is one of the site's own
    icons. The URL here does not come from the caller: it is produced by
    `GamendWeb.Uploads.confirm/5` after the stored object has been re-read,
    size-checked and content-sniffed, so this path is the only way an uploaded
    icon is ever set. Admin rights are still required.
    
  """
  @spec set_icon_url(String.t(), String.t(), String.t()) ::
          {:ok, Gamend.Groups.Group.t()} | {:error, :not_admin | Ecto.Changeset.t() | term()}
  def set_icon_url(_user_id, _group_id, _url) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.set_icon_url/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Return true if both users share at least one common group membership.
  """
  @spec shared_group_member?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def shared_group_member?(_user_a_id, _user_b_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Groups.shared_group_member?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to a specific group's events.
  """
  @spec subscribe_group(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_group(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Groups.subscribe_group/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to global group events.
  """
  @spec subscribe_groups() :: :ok | {:error, term()}
  def subscribe_groups() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Groups.subscribe_groups/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The types a group may be created as or changed to, the default first: the
    `types` setting, less any name that is not a type. All three when that
    leaves none, so a typo cannot close group creation.
    
  """
  @spec types() :: [String.t()]
  def types() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.types/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether a group's title must be unique (`unique_titles`).
  """
  @spec unique_titles?() :: boolean()
  def unique_titles?() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Groups.unique_titles?/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unsubscribe from a specific group's events.
  """
  @spec unsubscribe_group(Ecto.UUID.t()) :: :ok
  def unsubscribe_group(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Groups.unsubscribe_group/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Update group settings. Only admins can update.
    Cannot lower max_members below current member count.
    
  """
  @spec update_group(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, Gamend.Groups.Group.t()} | {:error, atom() | Ecto.Changeset.t()}
  def update_group(_user_id, _group_id, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Groups.update_group/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Return the list of group IDs the user belongs to (lightweight, no preloads).
  """
  @spec user_group_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def user_group_ids(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Groups.user_group_ids/1 is a stub - only available at runtime on Gamend"
    end
  end
end
