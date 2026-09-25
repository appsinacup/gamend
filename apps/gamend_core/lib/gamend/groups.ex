defmodule Gamend.Groups do
  @moduledoc """
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
  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: Gamend.Cache

  alias Gamend.Accounts.User
  alias Gamend.Groups.Group
  alias Gamend.Groups.GroupJoinRequest
  alias Gamend.Groups.GroupMember
  alias Gamend.Groups.Invites
  alias Gamend.Groups.JoinRequests
  alias Gamend.Groups.Shared
  alias Gamend.Lock
  alias Gamend.Repo

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @groups_topic "groups"

  @doc "Subscribe to global group events."
  @spec subscribe_groups() :: :ok | {:error, term()}
  def subscribe_groups do
    Phoenix.PubSub.subscribe(Gamend.PubSub, @groups_topic)
  end

  @doc "Subscribe to a specific group's events."
  @spec subscribe_group(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_group(group_id) do
    Phoenix.PubSub.subscribe(Gamend.PubSub, "group:#{group_id}")
  end

  @doc "Unsubscribe from a specific group's events."
  @spec unsubscribe_group(Ecto.UUID.t()) :: :ok
  def unsubscribe_group(group_id) do
    Phoenix.PubSub.unsubscribe(Gamend.PubSub, "group:#{group_id}")
  end

  defp broadcast_groups(event) do
    Gamend.Broadcast.publish(@groups_topic, event)
  end

  defp broadcast_group(group_id, event) do
    Gamend.Broadcast.publish("group:#{group_id}", event)
  end

  @doc "Broadcast a presence event (e.g. member_online, member_updated) to a group topic."
  @spec broadcast_member_presence(Ecto.UUID.t(), tuple()) :: :ok | {:error, term()}
  def broadcast_member_presence(group_id, event) do
    broadcast_group(group_id, event)
  end

  @doc "Return the list of group IDs the user belongs to (lightweight, no preloads)."
  @spec user_group_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def user_group_ids(user_id) when is_binary(user_id) do
    from(m in GroupMember, where: m.user_id == ^user_id, select: m.group_id)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Cache helpers
  # ---------------------------------------------------------------------------

  defp group_cache_version(group_id), do: Shared.group_cache_version(group_id)
  defp invalidate_group_cache(group_id), do: Shared.invalidate_group_cache(group_id)

  defp cache_match(nil), do: false
  defp cache_match(_), do: true

  @doc "Public wrapper for cache invalidation (used by admin controller)."
  @spec invalidate_group_cache_public(Ecto.UUID.t()) :: :ok
  def invalidate_group_cache_public(group_id) when is_binary(group_id) do
    invalidate_group_cache(group_id)
  end

  # ---------------------------------------------------------------------------
  # Queries – single group
  # ---------------------------------------------------------------------------

  @doc "Get a group by ID (cached)."
  @spec get_group(Ecto.UUID.t()) :: Group.t() | nil
  @decorate cacheable(
              key: {:groups, :get, group_cache_version(id), id},
              match: &cache_match/1,
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_group(id), do: Repo.get_uuid(Group, id)

  @doc "Get a group by ID (raises if not found, cached)."
  @spec get_group!(Ecto.UUID.t()) :: Group.t()
  @decorate cacheable(
              key: {:groups, :get, group_cache_version(id), id},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  def get_group!(id), do: Repo.get_uuid!(Group, id)

  @doc "Get a group by its unique title."
  @spec get_group_by_title(String.t()) :: Group.t() | nil
  def get_group_by_title(title) when is_binary(title) do
    Repo.get_by(Group, title: title)
  end

  # ---------------------------------------------------------------------------
  # Queries – list / count
  # ---------------------------------------------------------------------------

  @doc """
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
  @spec list_groups(map(), keyword()) :: [Group.t()]
  def list_groups(filters \\ %{}, opts \\ []) do
    q =
      from(g in Group)
      |> filter_hidden_false()
      |> apply_filters(filters)
      |> apply_sort(opts)

    results = q |> preload(:creator) |> paginate(opts)
    filter_by_metadata_in_memory(results, filters)
  end

  @doc "Count groups matching public filters (excludes hidden)."
  @spec count_list_groups(map()) :: non_neg_integer()
  def count_list_groups(filters \\ %{}) do
    q =
      from(g in Group)
      |> filter_hidden_false()
      |> apply_filters(filters)

    metadata_key = Map.get(filters, :metadata_key) || Map.get(filters, "metadata_key")

    if is_nil(metadata_key) do
      Repo.one(from g in q, select: count(g.id)) || 0
    else
      # Only fetch metadata column to reduce data transfer
      q
      |> select([g], g.metadata)
      |> Repo.all()
      |> count_matching_metadata(filters)
    end
  end

  defp count_matching_metadata(metadata_list, filters) do
    key = Map.get(filters, :metadata_key) || Map.get(filters, "metadata_key")
    value = Map.get(filters, :metadata_value) || Map.get(filters, "metadata_value")

    Enum.count(metadata_list, fn metadata ->
      case Map.get(metadata || %{}, key) do
        nil -> false
        _ when is_nil(value) -> true
        v -> String.contains?(to_string(v), to_string(value))
      end
    end)
  end

  @doc """
  List ALL groups including hidden (admin only).
  """
  @spec list_all_groups(map(), keyword()) :: [Group.t()]
  def list_all_groups(filters \\ %{}, opts \\ []) do
    q = from(g in Group) |> apply_filters(filters) |> apply_sort(opts)
    paginate(q, opts)
  end

  @doc "Count ALL groups matching filters (admin)."
  @spec count_all_groups(map()) :: non_neg_integer()
  def count_all_groups(filters \\ %{}) do
    q = from(g in Group) |> apply_filters(filters)
    Repo.aggregate(q, :count, :id)
  end

  @doc "Count groups by type."
  @spec count_groups_by_type(String.t()) :: non_neg_integer()
  def count_groups_by_type(type) when type in ["public", "private", "hidden"] do
    Repo.one(from(g in Group, where: g.type == ^type, select: count(g.id))) || 0
  end

  @doc "Total member count across all groups."
  @spec count_all_members() :: non_neg_integer()
  def count_all_members do
    Repo.one(from(m in GroupMember, select: count(m.id))) || 0
  end

  # ---------------------------------------------------------------------------
  # Members
  # ---------------------------------------------------------------------------

  @doc """
  Just the user ids of a group's members, oldest first.

  For callers that only need to address members — chat notification fanout is
  the hot one — where `get_group_members/1` would preload every member's full
  user row only to read `user_id` from it.
  """
  @spec group_member_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def group_member_ids(group_id) when is_binary(group_id) do
    from(m in GroupMember,
      where: m.group_id == ^group_id,
      order_by: [asc: m.inserted_at],
      select: m.user_id
    )
    |> Repo.all()
  end

  @doc "Get all members of a group."
  @spec get_group_members(Ecto.UUID.t()) :: [GroupMember.t()]
  def get_group_members(group_id) when is_binary(group_id) do
    from(m in GroupMember,
      where: m.group_id == ^group_id,
      order_by: [asc: m.inserted_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Get paginated members of a group with user info.

  Pass `:search` to filter by member name (display name or username).
  """
  @spec get_group_members_paginated(Ecto.UUID.t(), keyword()) :: [GroupMember.t()]
  def get_group_members_paginated(group_id, opts \\ []) when is_binary(group_id) do
    group_id
    |> members_query(opts)
    |> order_by([m], asc: m.inserted_at)
    |> paginate(opts)
  end

  @doc "Count members in a group. Accepts the same `:search` option as the listing."
  @spec count_group_members(Ecto.UUID.t()) :: non_neg_integer()
  @spec count_group_members(Ecto.UUID.t(), keyword()) :: non_neg_integer()
  def count_group_members(group_id, opts \\ []) when is_binary(group_id) do
    group_id
    |> members_query(opts)
    |> exclude(:preload)
    |> Repo.aggregate(:count, :id)
  end

  defp members_query(group_id, opts) do
    query =
      from(m in GroupMember,
        join: u in assoc(m, :user),
        as: :user,
        where: m.group_id == ^group_id,
        preload: [user: u]
      )

    case Repo.search_pattern(Keyword.get(opts, :search)) do
      nil ->
        query

      pattern ->
        where(
          query,
          [user: u],
          fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.display_name, ^pattern) or
            fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.username, ^pattern)
        )
    end
  end

  @doc "Batch count members for a list of group IDs. Returns a map of group_id => count."
  @spec batch_member_counts([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => non_neg_integer()}
  def batch_member_counts([]), do: %{}

  def batch_member_counts(group_ids) when is_list(group_ids) do
    from(m in GroupMember,
      where: m.group_id in ^group_ids,
      group_by: m.group_id,
      select: {m.group_id, count(m.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count how many groups a user has created (is admin of)."
  @spec count_groups_created_by(Ecto.UUID.t()) :: non_neg_integer()
  def count_groups_created_by(user_id) when is_binary(user_id) do
    Repo.one(
      from(m in GroupMember,
        where: m.user_id == ^user_id and m.role == "admin",
        select: count(m.id)
      )
    ) || 0
  end

  @doc "Count how many groups a user is a member of (any role)."
  @spec count_user_group_memberships(Ecto.UUID.t()) :: non_neg_integer()
  def count_user_group_memberships(user_id) when is_binary(user_id) do
    Repo.one(
      from(m in GroupMember,
        where: m.user_id == ^user_id,
        select: count(m.id)
      )
    ) || 0
  end

  @doc "Get a specific membership."
  @spec get_membership(Ecto.UUID.t(), Ecto.UUID.t()) :: GroupMember.t() | nil
  def get_membership(group_id, user_id) do
    Repo.get_by(GroupMember, group_id: group_id, user_id: user_id)
  end

  @doc """
  Whether `user` holds authority over `group` — its admin members, nobody else.

  Subject first, resource second, like every other `can_*?` predicate (see
  `Gamend.Policy`). Both arguments take a struct or a bare id.
  """
  @spec can_manage_group?(User.t() | Ecto.UUID.t() | nil, Group.t() | Ecto.UUID.t() | nil) ::
          boolean()
  def can_manage_group?(%User{id: user_id}, group), do: can_manage_group?(user_id, group)
  def can_manage_group?(user_id, %Group{id: group_id}), do: can_manage_group?(user_id, group_id)

  def can_manage_group?(user_id, group_id) when is_binary(user_id) and is_binary(group_id) do
    case get_membership(group_id, user_id) do
      %GroupMember{role: "admin"} -> true
      _ -> false
    end
  end

  def can_manage_group?(_user, _group), do: false

  @doc "Check if user is a member (any role) of the group."
  @spec member?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def member?(group_id, user_id) do
    get_membership(group_id, user_id) != nil
  end

  @doc "Return true if both users share at least one common group membership."
  @spec shared_group_member?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def shared_group_member?(user_a_id, user_b_id)
      when is_binary(user_a_id) and is_binary(user_b_id) do
    Repo.exists?(
      from m1 in GroupMember,
        join: m2 in GroupMember,
        on: m1.group_id == m2.group_id,
        where: m1.user_id == ^user_a_id and m2.user_id == ^user_b_id
    )
  end

  @doc "List groups the user belongs to."
  @spec list_user_groups(Ecto.UUID.t(), keyword()) :: [Group.t()]
  def list_user_groups(user_id, opts \\ []) when is_binary(user_id) do
    from(g in Group,
      join: m in GroupMember,
      on: m.group_id == g.id,
      where: m.user_id == ^user_id,
      order_by: [asc: g.title],
      preload: [:creator]
    )
    |> paginate(opts)
  end

  @doc "List groups the user belongs to, together with the membership role."
  @spec list_user_groups_with_role(Ecto.UUID.t()) :: [{Group.t(), String.t()}]
  def list_user_groups_with_role(user_id) when is_binary(user_id) do
    from(g in Group,
      join: m in GroupMember,
      on: m.group_id == g.id,
      where: m.user_id == ^user_id,
      order_by: [asc: g.title],
      select: {g, m.role}
    )
    |> Repo.all()
  end

  @doc "Count groups the user belongs to."
  @spec count_user_groups(Ecto.UUID.t()) :: non_neg_integer()
  def count_user_groups(user_id) when is_binary(user_id) do
    from(m in GroupMember, where: m.user_id == ^user_id, select: count(m.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  # ---------------------------------------------------------------------------
  # Commands – create
  # ---------------------------------------------------------------------------

  @doc """
  Create a new group. The creating user becomes an admin member automatically.
  """
  @spec create_group(Ecto.UUID.t(), map()) ::
          {:ok, Group.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_group(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
    attrs = normalize_params(attrs)

    case Gamend.Accounts.get_user(user_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        max_created = Gamend.Limits.get(:max_groups_created_per_user)

        if count_groups_created_by(user_id) >= max_created do
          {:error, :too_many_groups_created}
        else
          case Gamend.Hooks.internal_call(:before_group_create, [user, attrs]) do
            {:ok, attrs} -> do_create_group(user_id, attrs)
            {:error, reason} -> {:error, {:hook_rejected, reason}}
          end
        end
    end
  end

  defp do_create_group(user_id, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:group, fn _changes ->
      %Group{}
      |> Group.changeset(attrs)
      |> Ecto.Changeset.put_change(:creator_id, user_id)
    end)
    |> Ecto.Multi.insert(:membership, fn %{group: group} ->
      GroupMember.changeset(%GroupMember{}, %{
        group_id: group.id,
        user_id: user_id,
        role: "admin"
      })
    end)
    |> Gamend.AfterCommit.transaction()
    |> case do
      {:ok, %{group: group}} ->
        _ = invalidate_group_cache(group.id)

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_group_create, [group])
        end)

        broadcast_groups({:group_created, group})
        {:ok, group}

      {:error, :group, changeset, _} ->
        {:error, changeset}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

  # ---------------------------------------------------------------------------
  # Commands – update
  # ---------------------------------------------------------------------------

  @doc """
  Update group settings. Only admins can update.
  Cannot lower max_members below current member count.
  """
  @spec update_group(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, Group.t()} | {:error, atom() | Ecto.Changeset.t()}
  def update_group(user_id, group_id, attrs)
      when is_binary(user_id) and is_binary(group_id) and is_map(attrs) do
    if can_manage_group?(user_id, group_id) do
      group = get_group!(group_id)

      # `icon_url` is dropped: it is set only by `save_icon/3`, after an upload
      # ticket has been confirmed. Leaving it castable here let a group admin
      # point the icon at any external URL, and did so even when the
      # `user_image_uploads` feature gate — whose whole purpose is to close that
      # surface — was switched off.
      attrs = attrs |> normalize_params() |> Map.drop(["icon_url"])

      new_max = Map.get(attrs, "max_members") || Map.get(attrs, :max_members)

      if is_nil(new_max) do
        do_update_group(group, attrs)
      else
        new_max_int = to_int_or_nil(new_max) || 0
        current_count = count_group_members(group_id)

        if new_max_int < current_count do
          {:error, :max_members_too_low}
        else
          do_update_group(group, attrs)
        end
      end
    else
      {:error, :not_admin}
    end
  end

  @doc """
  Set a group's icon to an object we have just accepted an upload for.

  Separate from `update_group/3` because that one deliberately drops `icon_url`
  from caller-supplied attributes. The URL here does not come from the caller:
  it is produced by `GamendWeb.Uploads.confirm/5` after the stored object has
  been re-read, size-checked and content-sniffed, so this path is the only way
  an icon is ever set. Admin rights are still required.
  """
  @spec set_icon_url(String.t(), String.t(), String.t()) ::
          {:ok, Group.t()} | {:error, :not_admin | Ecto.Changeset.t() | term()}
  def set_icon_url(user_id, group_id, url)
      when is_binary(user_id) and is_binary(group_id) and is_binary(url) do
    if can_manage_group?(user_id, group_id) do
      group_id |> get_group!() |> do_update_group(%{"icon_url" => url})
    else
      {:error, :not_admin}
    end
  end

  defp do_update_group(%Group{} = group, attrs) do
    case Gamend.Hooks.internal_call(:before_group_update, [group, attrs]) do
      {:ok, returned} ->
        attrs_to_use =
          if is_map(returned) and not is_struct(returned) do
            returned
          else
            attrs
          end

        group
        |> Group.changeset(attrs_to_use)
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            Gamend.Async.run(fn ->
              Gamend.Hooks.internal_call(:after_group_updated, [updated])
            end)

            _ = invalidate_group_cache(updated.id)
            broadcast_group(updated.id, {:group_updated, updated})
            broadcast_groups({:group_updated, updated})
            {:ok, updated}

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Commands – delete
  # ---------------------------------------------------------------------------

  @doc "Return a changeset for tracking group changes (admin edit forms)."
  @spec change_group(Group.t(), map()) :: Ecto.Changeset.t()
  def change_group(%Group{} = group, attrs \\ %{}) do
    Group.changeset(group, attrs)
  end

  @doc "Admin-level update, bypasses membership checks."
  @spec admin_update_group(Group.t(), map()) :: {:ok, Group.t()} | {:error, Ecto.Changeset.t()}
  def admin_update_group(%Group{} = group, attrs) do
    do_update_group(group, attrs)
  end

  @doc """
  Delete a group. Admin-only. Refuses if the group still has members — groups
  are auto-deleted when the last member leaves.
  """
  @spec delete_group(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, Group.t()} | {:error, atom()}
  def delete_group(user_id, group_id)
      when is_binary(user_id) and is_binary(group_id) do
    cond do
      not can_manage_group?(user_id, group_id) ->
        {:error, :not_admin}

      count_group_members(group_id) > 0 ->
        {:error, :has_members}

      true ->
        group = get_group!(group_id)

        with {:ok, _} <- Gamend.Hooks.internal_call(:before_group_delete, [group]) do
          do_delete_group(group)
        end
    end
  end

  defp do_delete_group(%Group{} = group) do
    # Gather pending invite user IDs before cascade-delete removes them
    pending_invite_user_ids = Shared.gather_pending_invite_user_ids(group.id)

    case Repo.delete(group) do
      {:ok, deleted} ->
        _ = invalidate_group_cache(deleted.id)
        Shared.invalidate_invite_caches_for_users(pending_invite_user_ids)
        Shared.notify_invite_users_group_deleted(pending_invite_user_ids, deleted)
        Gamend.Chat.cleanup_chat("group", deleted.id)
        broadcast_groups({:group_deleted, deleted.id})

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_group_deleted, [deleted])
        end)

        {:ok, deleted}

      error ->
        error
    end
  end

  @doc "Admin-level delete (no membership check, for server admins)."
  @spec admin_delete_group(Ecto.UUID.t()) :: {:ok, Group.t()} | {:error, term()}
  def admin_delete_group(group_id) when is_binary(group_id) do
    group = get_group!(group_id)

    with {:ok, _} <- Gamend.Hooks.internal_call(:before_group_delete, [group]) do
      do_delete_group(group)
    end
  end

  @doc """
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
  def handle_user_deletion(user_id) when is_binary(user_id) do
    memberships =
      from(m in GroupMember, where: m.user_id == ^user_id)
      |> Repo.all()

    Gamend.AfterCommit.transaction(fn ->
      Enum.each(memberships, fn member ->
        group_id = member.group_id

        if member.role == "admin" do
          maybe_transfer_admin_before_leave(member, group_id, user_id)
        else
          do_leave(member, group_id, user_id)
        end
      end)
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Commands – join / leave / kick
  # ---------------------------------------------------------------------------

  @doc """
  Join a public group directly. Returns error for private/hidden groups.
  """
  @spec join_group(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupMember.t()} | {:error, atom()}
  def join_group(user_id, group_id)
      when is_binary(user_id) and is_binary(group_id) do
    group = get_group(group_id)

    cond do
      is_nil(group) ->
        {:error, :not_found}

      group.type != "public" ->
        {:error, :not_public}

      member?(group_id, user_id) ->
        # Idempotent: return existing membership instead of erroring
        {:ok, get_membership(group_id, user_id)}

      true ->
        case Shared.do_add_group_member(user_id, group_id, group, "public_join") do
          {:ok, member} ->
            # Clean up any pending invites for this user + group
            Shared.mark_pending_invites_accepted(user_id, group_id)

            Gamend.Async.run(fn ->
              Gamend.Hooks.internal_call(:after_group_join, [user_id, group])
            end)

            {:ok, member}

          error ->
            error
        end
    end
  end

  @doc "Leave a group."
  @spec leave_group(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, GroupMember.t()} | {:error, atom()}
  def leave_group(user_id, group_id)
      when is_binary(user_id) and is_binary(group_id) do
    # `do_leave/3`'s `member_left`, `maybe_delete_empty_group/1`'s
    # `group_deleted` and the cache-version bump wait for the commit: a
    # subscriber that re-read on the event could otherwise see the pre-commit
    # state, or cache rows about to be rolled back under the new version.
    Lock.serialize(:group, group_id, fn ->
      case get_membership(group_id, user_id) do
        nil ->
          Repo.rollback(:not_member)

        member ->
          # If leaving user is admin, check if they're the last admin
          outcome =
            if member.role == "admin" do
              maybe_transfer_admin_before_leave(member, group_id, user_id)
            else
              do_leave(member, group_id, user_id)
            end

          case outcome do
            {:ok, deleted} -> deleted
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  # Once the enclosing transaction commits (`Gamend.AfterCommit`): leaving a
  # group, and account deletion's sweep of every group, both run in one.
  defp after_leave_commit(fun) when is_function(fun, 0) do
    Gamend.AfterCommit.defer(fun)
  end

  # Whether removing `target_id`'s admin rights would leave the group with none.
  #
  # Only the *leave* path had an admin-count check (and promotes a successor).
  # Demote and kick had none, so two admins demoting or kicking each other at
  # the same time both read the other as an admin and both writes landed — after
  # which nobody could update, invite, kick, promote or approve join requests,
  # because `can_manage_group?/2` is admin-membership only. The group could not
  # be recovered; it could only be emptied until it auto-deleted.
  #
  # A single query, evaluated inside neither a lock nor a transaction: this
  # closes the ordinary case, while the genuinely concurrent one is closed by
  # `Gamend.Lock.serialize/3` around the write (see AUDIT.md, advisory locks).
  defp would_orphan_group?(group_id, target_id) do
    case get_membership(group_id, target_id) do
      %GroupMember{role: "admin"} -> last_admin?(group_id)
      _not_an_admin -> false
    end
  end

  defp last_admin?(group_id) do
    admin_count =
      from(m in GroupMember,
        where: m.group_id == ^group_id and m.role == "admin",
        select: count(m.id)
      )
      |> Repo.one()

    admin_count <= 1
  end

  defp maybe_transfer_admin_before_leave(member, group_id, user_id) do
    admin_count =
      from(m in GroupMember,
        where: m.group_id == ^group_id and m.role == "admin",
        select: count(m.id)
      )
      |> Repo.one()

    if admin_count <= 1 do
      # Last admin — try to promote the longest-standing non-admin member
      next_member =
        from(m in GroupMember,
          where: m.group_id == ^group_id and m.user_id != ^user_id and m.role == "member",
          order_by: [asc: m.inserted_at],
          limit: 1
        )
        |> Repo.one()

      if next_member do
        case next_member |> Ecto.Changeset.change(%{role: "admin"}) |> Repo.update() do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end

        # Transfer creator_id if the leaving user is the group creator
        case Repo.get(Group, group_id) do
          %Group{creator_id: ^user_id} = group ->
            _ =
              group |> Ecto.Changeset.change(%{creator_id: next_member.user_id}) |> Repo.update()

          _ ->
            :ok
        end

        broadcast_group(group_id, {:member_promoted, group_id, next_member.user_id})
      else
        # No other members — transfer creator_id to nil won't help,
        # the group will be deleted by maybe_delete_empty_group below.
        :ok
      end

      # Leave even if no other member remains (group becomes empty)
      do_leave(member, group_id, user_id)
    else
      # Multiple admins — still check if leaving user is the creator
      case Repo.get(Group, group_id) do
        %Group{creator_id: ^user_id} = group ->
          # Pick another admin to become the new creator
          next_admin =
            from(m in GroupMember,
              where: m.group_id == ^group_id and m.user_id != ^user_id and m.role == "admin",
              order_by: [asc: m.inserted_at],
              limit: 1
            )
            |> Repo.one()

          if next_admin do
            _ = group |> Ecto.Changeset.change(%{creator_id: next_admin.user_id}) |> Repo.update()
          end

        _ ->
          :ok
      end

      do_leave(member, group_id, user_id)
    end
  end

  defp do_leave(member, group_id, user_id) do
    case Repo.delete(member) do
      {:ok, deleted} ->
        after_leave_commit(fn ->
          _ = invalidate_group_cache(group_id)
          broadcast_group(group_id, {:member_left, group_id, user_id})

          Gamend.Async.run(fn ->
            Gamend.Hooks.internal_call(:after_group_leave, [user_id, group_id])
          end)
        end)

        maybe_delete_empty_group(group_id)
        {:ok, deleted}

      error ->
        error
    end
  end

  defp maybe_delete_empty_group(group_id) do
    if count_group_members(group_id) == 0 do
      case Repo.get(Group, group_id) do
        nil ->
          :ok

        group ->
          Repo.delete(group)
          after_leave_commit(fn -> announce_group_deleted(group) end)
      end
    end
  end

  defp announce_group_deleted(%Group{id: group_id} = group) do
    _ = invalidate_group_cache(group_id)
    broadcast_groups({:group_deleted, group_id})

    Gamend.Async.run(fn ->
      Gamend.Hooks.internal_call(:after_group_deleted, [group])
    end)
  end

  @doc "Kick a member from the group. Only admins can kick."
  @spec kick_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupMember.t()} | {:error, atom()}
  def kick_member(admin_id, group_id, target_id)
      when is_binary(admin_id) and is_binary(group_id) and is_binary(target_id) do
    cond do
      not can_manage_group?(admin_id, group_id) ->
        {:error, :not_admin}

      admin_id == target_id ->
        {:error, :cannot_kick_self}

      would_orphan_group?(group_id, target_id) ->
        {:error, :last_admin}

      true ->
        case get_membership(group_id, target_id) do
          nil ->
            {:error, :not_member}

          member ->
            with {:ok, _} <-
                   Gamend.Hooks.internal_call(:before_group_kick, [
                     admin_id,
                     target_id,
                     group_id
                   ]) do
              do_kick_member(member, admin_id, target_id, group_id)
            end
        end
    end
  end

  defp do_kick_member(member, admin_id, target_id, group_id) do
    case Repo.delete(member) do
      {:ok, deleted} ->
        _ = invalidate_group_cache(group_id)
        broadcast_group(group_id, {:member_kicked, group_id, target_id})

        # Notify the kicked user
        group = get_group(group_id)
        group_title = (group && group.title) || ""

        Gamend.Notifications.admin_create_notification(
          admin_id,
          target_id,
          %{
            "title" => "Removed from #{group_title}",
            "content" => "",
            "metadata" => %{
              "type" => "group_kicked",
              "group_id" => group_id,
              "group_title" => group_title
            }
          }
        )

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_group_kick, [admin_id, target_id, group_id])
        end)

        {:ok, deleted}

      error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Commands – promote / demote
  # ---------------------------------------------------------------------------

  @doc "Promote a member to admin. Only admins can promote."
  @spec promote_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupMember.t()} | {:error, atom()}
  def promote_member(admin_id, group_id, target_id)
      when is_binary(admin_id) and is_binary(group_id) and is_binary(target_id) do
    cond do
      not can_manage_group?(admin_id, group_id) ->
        {:error, :not_admin}

      admin_id == target_id ->
        {:error, :cannot_promote_self}

      true ->
        case get_membership(group_id, target_id) do
          nil ->
            {:error, :not_member}

          %GroupMember{role: "admin"} ->
            {:error, :already_admin}

          member ->
            member
            |> Ecto.Changeset.change(%{role: "admin"})
            |> Repo.update()
            |> case do
              {:ok, updated} ->
                _ = invalidate_group_cache(group_id)
                broadcast_group(group_id, {:member_promoted, group_id, target_id})

                # Notify the promoted user
                group = get_group(group_id)
                group_title = (group && group.title) || ""

                Gamend.Notifications.admin_create_notification(
                  admin_id,
                  target_id,
                  %{
                    "title" => "Promoted to admin in #{group_title}",
                    "content" => "",
                    "metadata" => %{
                      "type" => "group_promoted",
                      "group_id" => group_id,
                      "group_title" => group_title
                    }
                  }
                )

                {:ok, updated}

              error ->
                error
            end
        end
    end
  end

  @doc "Demote an admin to member. Only admins can demote other admins."
  @spec demote_member(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupMember.t()} | {:error, atom()}
  def demote_member(admin_id, group_id, target_id)
      when is_binary(admin_id) and is_binary(group_id) and is_binary(target_id) do
    cond do
      not can_manage_group?(admin_id, group_id) ->
        {:error, :not_admin}

      admin_id == target_id ->
        {:error, :cannot_demote_self}

      would_orphan_group?(group_id, target_id) ->
        {:error, :last_admin}

      true ->
        case get_membership(group_id, target_id) do
          nil ->
            {:error, :not_member}

          %GroupMember{role: "member"} ->
            {:error, :already_member}

          member ->
            member
            |> Ecto.Changeset.change(%{role: "member"})
            |> Repo.update()
            |> case do
              {:ok, updated} ->
                _ = invalidate_group_cache(group_id)
                broadcast_group(group_id, {:member_demoted, group_id, target_id})

                # Notify the demoted user
                group = get_group(group_id)
                group_title = (group && group.title) || ""

                Gamend.Notifications.admin_create_notification(
                  admin_id,
                  target_id,
                  %{
                    "title" => "Demoted to member in #{group_title}",
                    "content" => "",
                    "metadata" => %{
                      "type" => "group_demoted",
                      "group_id" => group_id,
                      "group_title" => group_title
                    }
                  }
                )

                {:ok, updated}

              error ->
                error
            end
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Group notifications
  # ---------------------------------------------------------------------------

  @doc """
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
  def notify_group(sender_id, group_id, content, metadata \\ %{})
      when is_binary(sender_id) and is_binary(group_id) and is_binary(content) do
    group = get_group(group_id)
    title = Map.get(metadata, "title") || Map.get(metadata, :title) || "Group Notification"
    # Remove the title key from metadata so it doesn't duplicate in the payload
    clean_metadata =
      metadata |> Map.delete("title") |> Map.delete(:title)

    cond do
      is_nil(group) ->
        {:error, :not_found}

      not member?(group_id, sender_id) ->
        {:error, :not_member}

      true ->
        member_ids =
          from(m in GroupMember,
            where: m.group_id == ^group_id and m.user_id != ^sender_id,
            select: m.user_id
          )
          |> Repo.all()

        notification_attrs = %{
          "title" => title,
          "content" => content,
          "metadata" =>
            Map.merge(clean_metadata, %{
              "group_id" => group_id,
              "group_title" => group.title
            })
        }

        sent =
          Enum.reduce(member_ids, 0, fn recipient_id, acc ->
            case upsert_group_notification(sender_id, recipient_id, notification_attrs) do
              {:ok, _} -> acc + 1
              _ -> acc
            end
          end)

        broadcast_group(group_id, {:group_notification, group_id, sender_id})
        {:ok, sent}
    end
  end

  defp upsert_group_notification(sender_id, recipient_id, attrs) do
    alias Gamend.Notifications.Notification

    content = Map.get(attrs, "content") || Map.get(attrs, :content, "")
    metadata = Map.get(attrs, "metadata") || Map.get(attrs, :metadata, %{})

    changeset =
      %Notification{}
      |> Notification.changeset(attrs)
      |> Ecto.Changeset.put_change(:sender_id, sender_id)
      |> Ecto.Changeset.put_change(:recipient_id, recipient_id)

    case Repo.insert(changeset,
           on_conflict: [
             set: [
               content: content,
               metadata: metadata,
               read: false,
               updated_at: DateTime.utc_now(:second)
             ]
           ],
           conflict_target: {:unsafe_fragment, "(sender_id, recipient_id, title)"}
         ) do
      {:ok, notification} ->
        Gamend.Notifications.invalidate_notifications_cache(recipient_id)

        Gamend.Broadcast.publish(
          "notifications:user:#{recipient_id}",
          {:notification_created, notification}
        )

        {:ok, notification}

      error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp filter_hidden_false(q) do
    from g in q, where: g.type != "hidden"
  end

  defp apply_filters(q, filters) do
    q
    |> filter_by_title(filters)
    |> filter_by_type(filters)
    |> filter_by_min_members(filters)
    |> filter_by_max_members(filters)
  end

  defp filter_by_title(q, filters) do
    case Map.get(filters, :title) || Map.get(filters, "title") do
      nil ->
        q

      "" ->
        q

      term ->
        prefix = Repo.escape_like(String.downcase(String.trim(term))) <> "%"
        from g in q, where: fragment("lower(?) LIKE ? ESCAPE '\\'", g.title, ^prefix)
    end
  end

  defp filter_by_type(q, filters) do
    case Map.get(filters, :type) || Map.get(filters, "type") do
      nil -> q
      "" -> q
      t when t in ["public", "private", "hidden"] -> from g in q, where: g.type == ^t
      _ -> q
    end
  end

  defp filter_by_min_members(q, filters) do
    case Map.get(filters, :min_members) || Map.get(filters, "min_members") do
      nil ->
        q

      "" ->
        q

      v when is_binary(v) ->
        case to_int_or_nil(v) do
          nil -> q
          int -> from g in q, where: g.max_members >= ^int
        end

      v when is_integer(v) ->
        from g in q, where: g.max_members >= ^v

      _ ->
        q
    end
  end

  defp filter_by_max_members(q, filters) do
    case Map.get(filters, :max_members) || Map.get(filters, "max_members") do
      nil ->
        q

      "" ->
        q

      v when is_binary(v) ->
        case to_int_or_nil(v) do
          nil -> q
          int -> from g in q, where: g.max_members <= ^int
        end

      v when is_integer(v) ->
        from g in q, where: g.max_members <= ^v

      _ ->
        q
    end
  end

  defp filter_by_metadata_in_memory(results, filters) do
    case Map.get(filters, :metadata_key) || Map.get(filters, "metadata_key") do
      nil ->
        results

      key ->
        value = Map.get(filters, :metadata_value) || Map.get(filters, "metadata_value")

        Enum.filter(results, fn g ->
          case Map.get(g.metadata || %{}, key) do
            nil -> false
            _ when is_nil(value) -> true
            v -> String.contains?(to_string(v), to_string(value))
          end
        end)
    end
  end

  # Unlike the other contexts this one runs the query. The window itself comes
  # from `Gamend.Query`, which clamps to the *configured* `max_page_size` — the
  # hard-coded 1000 here ignored it.
  defp paginate(q, opts), do: q |> Gamend.Query.maybe_page(opts) |> Repo.all()

  defp apply_sort(q, opts) do
    case Keyword.get(opts, :sort_by) do
      "updated_at" -> from g in q, order_by: [desc: g.updated_at]
      "updated_at_asc" -> from g in q, order_by: [asc: g.updated_at]
      "inserted_at" -> from g in q, order_by: [desc: g.inserted_at]
      "inserted_at_asc" -> from g in q, order_by: [asc: g.inserted_at]
      "title" -> from g in q, order_by: [asc: g.title]
      "title_desc" -> from g in q, order_by: [desc: g.title]
      "max_members" -> from g in q, order_by: [desc: g.max_members]
      "max_members_asc" -> from g in q, order_by: [asc: g.max_members]
      _ -> from g in q, order_by: [desc: g.inserted_at]
    end
  end

  defp normalize_params(attrs) when is_map(attrs) do
    keys = Map.keys(attrs)
    has_string = Enum.any?(keys, &is_binary/1)
    has_atom = Enum.any?(keys, &is_atom/1)

    if has_string and has_atom do
      Map.new(attrs, fn {k, v} ->
        if is_atom(k), do: {Atom.to_string(k), v}, else: {k, v}
      end)
    else
      attrs
    end
  end

  # ---------------------------------------------------------------------------
  # Join requests — implemented in Gamend.Groups.JoinRequests
  # ---------------------------------------------------------------------------

  @doc "Request to join a private group. Creates a pending join request."
  @spec request_join(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupJoinRequest.t()} | {:error, atom()}
  defdelegate request_join(user_id, group_id), to: JoinRequests

  @doc "List pending join requests for a group (admin only)."
  @spec list_join_requests(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, [GroupJoinRequest.t()]} | {:error, atom()}
  defdelegate list_join_requests(admin_id, group_id, opts \\ []), to: JoinRequests

  @doc "Count pending join requests for a group."
  @spec count_join_requests(Ecto.UUID.t()) :: non_neg_integer()
  defdelegate count_join_requests(group_id), to: JoinRequests

  @doc "Approve a pending join request. Admin only."
  @spec approve_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupMember.t()} | {:error, atom()}
  defdelegate approve_join_request(admin_id, request_id), to: JoinRequests

  @doc "Reject a pending join request. Admin only."
  @spec reject_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupJoinRequest.t()} | {:error, atom()}
  defdelegate reject_join_request(admin_id, request_id), to: JoinRequests

  @doc "Cancel (delete) a pending join request. Only the requesting user can cancel."
  @spec cancel_join_request(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GroupJoinRequest.t()} | {:error, atom()}
  defdelegate cancel_join_request(user_id, request_id), to: JoinRequests

  @doc "List pending join requests sent by a user."
  @spec list_user_pending_requests(Ecto.UUID.t()) :: [GroupJoinRequest.t()]
  defdelegate list_user_pending_requests(user_id), to: JoinRequests

  # ---------------------------------------------------------------------------
  # Invites — implemented in Gamend.Groups.Invites
  # ---------------------------------------------------------------------------

  @doc "Invite a user to a group (see `Gamend.Groups.Invites.invite_to_group/3`)."
  @spec invite_to_group(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Groups.GroupInvite.t()} | {:ok, :request_approved} | {:error, atom()}
  defdelegate invite_to_group(admin_id, group_id, target_user_id), to: Invites

  @doc "Accept a pending group invite by invite id (recipient only)."
  @spec accept_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, GroupMember.t()} | {:error, atom()}
  defdelegate accept_invite(user_id, invite_id), to: Invites

  @doc "Decline a pending group invite by invite id (recipient only)."
  @spec decline_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  defdelegate decline_invite(user_id, invite_id), to: Invites

  @doc "Cancel a group invitation the current user sent."
  @spec cancel_invite(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  defdelegate cancel_invite(user_id, invite_id), to: Invites

  @doc "List pending group invitations for a user."
  @spec list_invitations(Ecto.UUID.t(), keyword()) :: [map()]
  defdelegate list_invitations(user_id, opts \\ []), to: Invites

  @doc "List group invitations sent by a user."
  @spec list_sent_invitations(Ecto.UUID.t(), keyword()) :: [map()]
  defdelegate list_sent_invitations(user_id, opts \\ []), to: Invites

  @doc "Count pending invitations for a user."
  @spec count_invitations(Ecto.UUID.t()) :: non_neg_integer()
  defdelegate count_invitations(user_id), to: Invites

  @doc "Count group invitations sent by a user."
  @spec count_sent_invitations(Ecto.UUID.t()) :: non_neg_integer()
  defdelegate count_sent_invitations(user_id), to: Invites

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
