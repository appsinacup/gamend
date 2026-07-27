defmodule GameServer.Groups do
  @moduledoc ~S"""
  Context module for group management: creating, updating, listing, joining,
  leaving, kicking, promoting/demoting members, and handling join requests.
  
  Groups are persistent communities (unlike ephemeral lobbies). They support
  three visibility types:
  
  - **public** – anyone can join directly
  - **private** – anyone can request to join; an admin must approve
  - **hidden** – only invited users can join (via notifications / invite API)
  
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
  The actual implementation runs on the GameServer.
  """



  @doc ~S"""
    Accept a pending group invite by invite id (recipient only).
  """
  @spec accept_invite(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupMember.t()} | {:error, atom()}
  def accept_invite(_user_id, _invite_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.accept_invite/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Check if user is an admin of the group.
  """
  @spec admin?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def admin?(_group_id, _user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "GameServer.Groups.admin?/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Admin-level delete (no membership check, for server admins).
  """
  @spec admin_delete_group(Ecto.UUID.t()) :: {:ok, GameServer.Groups.Group.t()} | {:error, term()}
  def admin_delete_group(_group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.admin_delete_group/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Admin-level update, bypasses membership checks.
  """
  @spec admin_update_group(GameServer.Groups.Group.t(), map()) ::
  {:ok, GameServer.Groups.Group.t()} | {:error, Ecto.Changeset.t()}
  def admin_update_group(_group, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.admin_update_group/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Approve a pending join request. Admin only.
  """
  @spec approve_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupMember.t()} | {:error, atom()}
  def approve_join_request(_admin_id, _request_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.approve_join_request/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Batch count members for a list of group IDs. Returns a map of group_id => count.
  """
  @spec batch_member_counts([Ecto.UUID.t()]) :: %{required(Ecto.UUID.t()) => non_neg_integer()}
  def batch_member_counts(_group_ids) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.batch_member_counts/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Broadcast a presence event (e.g. member_online, member_updated) to a group topic.
  """
  @spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
  def broadcast_member_presence(_group_id, _event) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Groups.broadcast_member_presence/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Cancel a group invitation the current user sent.
  """
  @spec cancel_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def cancel_invite(_user_id, _invite_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Groups.cancel_invite/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Cancel (delete) a pending join request. Only the requesting user can cancel.
  """
  @spec cancel_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupJoinRequest.t()} | {:error, atom()}
  def cancel_join_request(_user_id, _request_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.cancel_join_request/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Return a changeset for tracking group changes (admin edit forms).
  """
  @spec change_group(GameServer.Groups.Group.t(), map()) :: Ecto.Changeset.t()
  def change_group(_group, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Groups.change_group/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count ALL groups matching filters (admin).
  """
  @spec count_all_groups(map()) :: non_neg_integer()
  def count_all_groups(_filters) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_all_groups/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Total member count across all groups.
  """
  @spec count_all_members() :: non_neg_integer()
  def count_all_members() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_all_members/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count members in a group. Accepts the same `:search` option as the listing.
  """
  @spec count_group_members(Ecto.UUID.t()) :: non_neg_integer()
  def count_group_members(_group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_group_members/1 is a stub - only available at runtime on GameServer"
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
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_group_members/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count groups by type.
  """
  @spec count_groups_by_type(String.t()) :: non_neg_integer()
  def count_groups_by_type(_type) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_groups_by_type/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count how many groups a user has created (is admin of).
  """
  @spec count_groups_created_by(Ecto.UUID.t()) :: non_neg_integer()
  def count_groups_created_by(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_groups_created_by/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count pending invitations for a user.
  """
  @spec count_invitations(Ecto.UUID.t()) :: non_neg_integer()
  def count_invitations(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_invitations/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count pending join requests for a group.
  """
  @spec count_join_requests(Ecto.UUID.t()) :: non_neg_integer()
  def count_join_requests(_group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_join_requests/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count groups matching public filters (excludes hidden).
  """
  @spec count_list_groups(map()) :: non_neg_integer()
  def count_list_groups(_filters) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_list_groups/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count group invitations sent by a user.
  """
  @spec count_sent_invitations(Ecto.UUID.t()) :: non_neg_integer()
  def count_sent_invitations(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_sent_invitations/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count how many groups a user is a member of (any role).
  """
  @spec count_user_group_memberships(Ecto.UUID.t()) :: non_neg_integer()
  def count_user_group_memberships(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_user_group_memberships/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count groups the user belongs to.
  """
  @spec count_user_groups(Ecto.UUID.t()) :: non_neg_integer()
  def count_user_groups(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Groups.count_user_groups/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Create a new group. The creating user becomes an admin member automatically.
    
  """
  @spec create_group(Ecto.UUID.t(), map()) ::
  {:ok, GameServer.Groups.Group.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_group(_user_id, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.create_group/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Decline a pending group invite by invite id (recipient only).
  """
  @spec decline_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def decline_invite(_user_id, _invite_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Groups.decline_invite/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Delete a group. Admin-only. Refuses if the group still has members — groups
    are auto-deleted when the last member leaves.
    
  """
  @spec delete_group(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.Group.t()} | {:error, atom()}
  def delete_group(_user_id, _group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.delete_group/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Demote an admin to member. Only admins can demote other admins.
  """
  @spec demote_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupMember.t()} | {:error, atom()}
  def demote_member(_admin_id, _group_id, _target_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.demote_member/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Get a group by ID (cached).
  """
  @spec get_group(Ecto.UUID.t()) :: GameServer.Groups.Group.t() | nil
  def get_group(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Groups.Group{id: "", title: "", description: "", icon_url: nil, type: "public", max_members: 100, metadata: %{}, slowdown: 0, creator_id: nil, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Groups.get_group/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Get a group by ID (raises if not found, cached).
  """
  @spec get_group!(Ecto.UUID.t()) :: GameServer.Groups.Group.t()
  def get_group!(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Groups.get_group!/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Get a group by its unique title.
  """
  @spec get_group_by_title(String.t()) :: GameServer.Groups.Group.t() | nil
  def get_group_by_title(_title) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Groups.Group{id: "", title: "", description: "", icon_url: nil, type: "public", max_members: 100, metadata: %{}, slowdown: 0, creator_id: nil, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Groups.get_group_by_title/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Get all members of a group.
  """
  @spec get_group_members(Ecto.UUID.t()) :: [GameServer.Groups.GroupMember.t()]
  def get_group_members(_group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Groups.get_group_members/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Get paginated members of a group with user info.
    
    Pass `:search` to filter by member name (display name or username).
    
  """
  @spec get_group_members_paginated(
  Ecto.UUID.t(),
  keyword()
) :: [GameServer.Groups.GroupMember.t()]
  def get_group_members_paginated(_group_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Groups.get_group_members_paginated/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Get a specific membership.
  """
  @spec get_membership(Ecto.UUID.t(), Ecto.UUID.t()) :: GameServer.Groups.GroupMember.t() | nil
  def get_membership(_group_id, _user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Groups.get_membership/2 is a stub - only available at runtime on GameServer"
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
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Groups.handle_user_deletion/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Public wrapper for cache invalidation (used by admin controller).
  """
  @spec invalidate_group_cache_public(Ecto.UUID.t()) :: :ok
  def invalidate_group_cache_public(_group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Groups.invalidate_group_cache_public/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Invite a user to a group (see `GameServer.Groups.Invites.invite_to_group/3`).
  """
  @spec invite_to_group(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupInvite.t()} | {:ok, :request_approved} | {:error, atom()}
  def invite_to_group(_admin_id, _group_id, _target_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.invite_to_group/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Join a public group directly. Returns error for private/hidden groups.
    
  """
  @spec join_group(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupMember.t()} | {:error, atom()}
  def join_group(_user_id, _group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.join_group/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Kick a member from the group. Only admins can kick.
  """
  @spec kick_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupMember.t()} | {:error, atom()}
  def kick_member(_admin_id, _group_id, _target_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.kick_member/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Leave a group.
  """
  @spec leave_group(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupMember.t()} | {:error, atom()}
  def leave_group(_user_id, _group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.leave_group/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List ALL groups including hidden (admin only).
    
  """
  @spec list_all_groups(
  map(),
  keyword()
) :: [GameServer.Groups.Group.t()]
  def list_all_groups(_filters, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Groups.list_all_groups/2 is a stub - only available at runtime on GameServer"
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
) :: [GameServer.Groups.Group.t()]
  def list_groups(_filters, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Groups.list_groups/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List pending group invitations for a user.
  """
  @spec list_invitations(
  Ecto.UUID.t(),
  keyword()
) :: [map()]
  def list_invitations(_user_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "GameServer.Groups.list_invitations/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List pending join requests for a group (admin only).
  """
  @spec list_join_requests(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
  {:ok, [GameServer.Groups.GroupJoinRequest.t()]} | {:error, atom()}
  def list_join_requests(_admin_id, _group_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.list_join_requests/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List group invitations sent by a user.
  """
  @spec list_sent_invitations(
  Ecto.UUID.t(),
  keyword()
) :: [map()]
  def list_sent_invitations(_user_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "GameServer.Groups.list_sent_invitations/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List groups the user belongs to.
  """
  @spec list_user_groups(
  Ecto.UUID.t(),
  keyword()
) :: [GameServer.Groups.Group.t()]
  def list_user_groups(_user_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Groups.list_user_groups/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List groups the user belongs to, together with the membership role.
  """
  @spec list_user_groups_with_role(Ecto.UUID.t()) :: [{GameServer.Groups.Group.t(), String.t()}]
  def list_user_groups_with_role(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "GameServer.Groups.list_user_groups_with_role/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List pending join requests sent by a user.
  """
  @spec list_user_pending_requests(Ecto.UUID.t()) :: [GameServer.Groups.GroupJoinRequest.t()]
  def list_user_pending_requests(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Groups.list_user_pending_requests/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Check if user is a member (any role) of the group.
  """
  @spec member?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def member?(_group_id, _user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "GameServer.Groups.member?/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Send a notification to all members of a group (except the sender).
    
    Any group member can send a notification. The notification is created for
    each member using a direct insert (bypassing the friends-only check).
    The `group_id` / `group_name` are stored in metadata so the client can
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
  def notify_group(_sender_id, _group_id, _content, _metadata) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.notify_group/4 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Promote a member to admin. Only admins can promote.
  """
  @spec promote_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupMember.t()} | {:error, atom()}
  def promote_member(_admin_id, _group_id, _target_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.promote_member/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Reject a pending join request. Admin only.
  """
  @spec reject_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupJoinRequest.t()} | {:error, atom()}
  def reject_join_request(_admin_id, _request_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.reject_join_request/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Request to join a private group. Creates a pending join request.
  """
  @spec request_join(Ecto.UUID.t(), Ecto.UUID.t()) ::
  {:ok, GameServer.Groups.GroupJoinRequest.t()} | {:error, atom()}
  def request_join(_user_id, _group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.request_join/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Return true if both users share at least one common group membership.
  """
  @spec shared_group_member?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def shared_group_member?(_user_a_id, _user_b_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "GameServer.Groups.shared_group_member?/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Subscribe to a specific group's events.
  """
  @spec subscribe_group(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_group(_group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Groups.subscribe_group/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Subscribe to global group events.
  """
  @spec subscribe_groups() :: :ok | {:error, term()}
  def subscribe_groups() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Groups.subscribe_groups/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Unsubscribe from a specific group's events.
  """
  @spec unsubscribe_group(Ecto.UUID.t()) :: :ok
  def unsubscribe_group(_group_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Groups.unsubscribe_group/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Update group settings. Only admins can update.
    Cannot lower max_members below current member count.
    
  """
  @spec update_group(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
  {:ok, GameServer.Groups.Group.t()} | {:error, atom() | Ecto.Changeset.t()}
  def update_group(_user_id, _group_id, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "GameServer.Groups.update_group/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Return the list of group IDs the user belongs to (lightweight, no preloads).
  """
  @spec user_group_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def user_group_ids(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Groups.user_group_ids/1 is a stub - only available at runtime on GameServer"
    end
  end

end
