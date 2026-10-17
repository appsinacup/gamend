defmodule GamendWeb.Api.V1.GroupController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Groups
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    GroupInviteOutcomeResponse,
    GroupInvitePage,
    GroupJoinRequestPage,
    GroupJoinRequestResponse,
    GroupMemberPage,
    GroupMemberResponse,
    GroupPage,
    GroupResponse,
    OkResponse,
    UploadTicketResponse
  }

  alias GamendWeb.Serializers
  alias GamendWeb.Uploads
  alias OpenApiSpex.Schema

  tags(["Groups"])

  # ---------------------------------------------------------------------------
  # Operations
  # ---------------------------------------------------------------------------

  operation(:index,
    operation_id: "list_groups",
    summary: "List groups",
    description:
      "Return all non-hidden groups. Supports filtering by title, type, max_members, and metadata.",
    parameters: [
      title: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Search by title (prefix)"
      ],
      type: [
        in: :query,
        schema: %Schema{type: :string, enum: ["public", "private"]},
        description: "Filter by group type"
      ],
      min_members: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Minimum max_members to include"
      ],
      max_members: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Maximum max_members to include"
      ],
      metadata_key: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Metadata key to filter by"
      ],
      metadata_value: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Metadata value to match (with metadata_key)"
      ],
      page: [in: :query, schema: %Schema{type: :integer}, description: "Page number"],
      page_size: [in: :query, schema: %Schema{type: :integer}, description: "Page size"]
    ],
    responses: [
      ok: {"List of groups", "application/json", GroupPage}
    ]
  )

  operation(:show,
    operation_id: "get_group",
    security: [%{}, %{"authorization" => []}],
    summary: "Get group details",
    description: "Get a single group by ID including member count.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    responses: [
      ok: {"Group details", "application/json", GroupResponse},
      not_found: Schemas.error("Group not found")
    ]
  )

  operation(:create,
    operation_id: "create_group",
    summary: "Create a group",
    description:
      "Create a new group. The authenticated user becomes an admin member automatically.",
    security: [%{"authorization" => []}],
    request_body: {
      "Group creation parameters",
      "application/json",
      %Schema{
        type: :object,
        required: [:title],
        properties: %{
          title: %Schema{type: :string, description: "Display title (unique)"},
          description: %Schema{type: :string, description: "Optional description"},
          icon_url: %Schema{type: :string, description: "Optional icon URL"},
          type: %Schema{
            type: :string,
            enum: ["public", "private", "hidden"],
            default: "public"
          },
          max_members: %Schema{type: :integer, description: "Max members (default: 100)"},
          metadata: %Schema{type: :object, description: "Server metadata"},
          slowdown: %Schema{
            type: :integer,
            description: "Chat slowdown in seconds (0 = disabled, max 3600)"
          }
        },
        example: %{title: "My Guild", type: "public", max_members: 50}
      }
    },
    responses: [
      created: {"Group created", "application/json", GroupResponse},
      conflict: Schemas.error("Title taken or validation error"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:update,
    operation_id: "update_group",
    summary: "Update a group (admin only)",
    description:
      "Update group settings. Only group admins can update. Cannot reduce max_members below current member count.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    request_body: {
      "Group update parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          title: %Schema{type: :string},
          description: %Schema{type: :string},
          icon_url: %Schema{type: :string},
          type: %Schema{type: :string, enum: ["public", "private", "hidden"]},
          max_members: %Schema{type: :integer},
          metadata: %Schema{type: :object},
          slowdown: %Schema{
            type: :integer,
            description: "Chat slowdown in seconds (0 = disabled, max 3600)"
          }
        }
      }
    },
    responses: [
      ok: {"Group updated", "application/json", GroupResponse},
      forbidden: Schemas.error("Not an admin"),
      unprocessable_entity: Schemas.error("Validation error"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:delete,
    operation_id: "delete_group",
    summary: "Delete a group (admin only)",
    description:
      "Delete a group with everyone in it. Only group admins can. Each other member " <>
        "gets a `group_deleted` notification, and the groups channel a `group_deleted` event.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    responses: [
      ok: {"Group deleted", "application/json", OkResponse},
      forbidden: Schemas.error("Not an admin, or a hook refused"),
      not_found: Schemas.error("Group not found"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:join,
    operation_id: "join_group",
    summary: "Join a group",
    description:
      "Join a group. For public groups the user is added immediately. " <>
        "For private groups a join request is created (an admin must approve it). " <>
        "Hidden groups require an invite and cannot be joined directly.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    responses: [
      ok: {"Joined successfully (public group)", "application/json", GroupMemberResponse},
      created:
        {"Join request created (private group)", "application/json", GroupJoinRequestResponse},
      forbidden: Schemas.error("Cannot join (full, hidden, already member, already requested)"),
      not_found: Schemas.error("Group not found"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:leave,
    operation_id: "leave_group",
    summary: "Leave a group",
    description: "Leave a group you are a member of.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    responses: [
      ok: {"Left successfully", "application/json", OkResponse},
      bad_request: Schemas.error("Not a member"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:kick,
    operation_id: "kick_group_member",
    summary: "Kick a member (admin only)",
    description: "Remove a member from the group. Only group admins can kick.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    request_body: {
      "Kick parameters",
      "application/json",
      %Schema{
        type: :object,
        required: [:target_user_id],
        properties: %{
          target_user_id: %Schema{type: :string, format: :uuid, description: "User ID to kick"}
        },
        example: %{target_user_id: "0198c0de-0002-7000-8000-000000000002"}
      }
    },
    responses: [
      ok: {"User kicked", "application/json", OkResponse},
      forbidden: Schemas.error("Not admin or cannot kick"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:members,
    operation_id: "list_group_members",
    security: [%{}, %{"authorization" => []}],
    summary: "List group members",
    description: "Get paginated members of a group with their roles.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ],
      page: [in: :query, schema: %Schema{type: :integer}, description: "Page number (default: 1)"],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Items per page (default: 25)"
      ]
    ],
    responses: [
      ok: {"Members list", "application/json", GroupMemberPage},
      not_found: Schemas.error("Group not found")
    ]
  )

  operation(:promote,
    operation_id: "promote_group_member",
    summary: "Promote member to admin",
    description: "Promote a member to admin role. Only admins can promote.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    request_body: {
      "Promote parameters",
      "application/json",
      %Schema{
        type: :object,
        required: [:target_user_id],
        properties: %{
          target_user_id: %Schema{type: :string, format: :uuid, description: "User ID to promote"}
        }
      }
    },
    responses: [
      ok: {"Member promoted", "application/json", GroupMemberResponse},
      forbidden: Schemas.error("Not admin"),
      conflict: Schemas.error("Already an admin"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:demote,
    operation_id: "demote_group_member",
    summary: "Demote admin to member",
    description: "Demote an admin to regular member. Only admins can demote.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    request_body: {
      "Demote parameters",
      "application/json",
      %Schema{
        type: :object,
        required: [:target_user_id],
        properties: %{
          target_user_id: %Schema{type: :string, format: :uuid, description: "User ID to demote"}
        }
      }
    },
    responses: [
      ok: {"Member demoted", "application/json", GroupMemberResponse},
      forbidden: Schemas.error("Not admin"),
      conflict: Schemas.error("Already a plain member"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:join_requests,
    operation_id: "list_join_requests",
    summary: "List pending join requests (admin only)",
    description: "List pending join requests for a group. Only group admins can view.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ],
      page: [in: :query, schema: %Schema{type: :integer}, description: "Page number"],
      page_size: [in: :query, schema: %Schema{type: :integer}, description: "Page size"]
    ],
    responses: [
      ok: {"Join requests", "application/json", GroupJoinRequestPage},
      forbidden: Schemas.error("Not admin"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:approve_request,
    operation_id: "approve_join_request",
    summary: "Approve a join request (admin only)",
    description: "Approve a pending join request. The user becomes a member.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ],
      request_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Join request ID",
        required: true
      ]
    ],
    responses: [
      ok: {"Request approved", "application/json", GroupMemberResponse},
      forbidden: Schemas.error("Not admin or group full"),
      not_found: Schemas.error("Request not found"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:reject_request,
    operation_id: "reject_join_request",
    summary: "Reject a join request (admin only)",
    description: "Reject a pending join request.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ],
      request_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Join request ID",
        required: true
      ]
    ],
    responses: [
      ok: {"Request rejected", "application/json", GroupJoinRequestResponse},
      forbidden: Schemas.error("Not admin"),
      not_found: Schemas.error("Request not found"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:cancel_request,
    operation_id: "cancel_join_request",
    summary: "Cancel your own pending join request",
    description: "Cancel a join request that the current user previously sent.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ],
      request_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Join request ID",
        required: true
      ]
    ],
    responses: [
      ok: {"Request cancelled", "application/json", GroupJoinRequestResponse},
      forbidden: Schemas.error("Not owner or not pending"),
      not_found: Schemas.error("Request not found"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:invite,
    operation_id: "invite_to_group",
    summary: "Invite a user to a group (admin only)",
    description:
      "Send an invitation to a user for a group. Creates a GroupInvite record " <>
        "and sends an informational notification. The invite is independent of notifications. " <>
        "If the target user already has a pending join request for this group, " <>
        "the request is automatically approved instead of creating an invite " <>
        "(status: \"request_approved\").",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    request_body: {
      "Invite parameters",
      "application/json",
      %Schema{
        type: :object,
        required: [:target_user_id],
        properties: %{
          target_user_id: %Schema{type: :string, format: :uuid, description: "User ID to invite"}
        }
      }
    },
    responses: [
      ok:
        {"`invited` when an invite was created, `request_approved` when a pending join request was approved instead",
         "application/json", GroupInviteOutcomeResponse},
      forbidden: Schemas.error("Not admin, or blocked"),
      conflict: Schemas.error("Target is already a member"),
      not_found: Schemas.error("Group not found"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:accept_invite,
    operation_id: "accept_group_invite",
    summary: "Accept a group invitation",
    description:
      "Accept a pending group invitation by invite ID. The authenticated user must be the recipient of the invite.",
    security: [%{"authorization" => []}],
    parameters: [
      invite_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Invite ID (from the invitations list)",
        required: true
      ]
    ],
    responses: [
      ok: {"Joined successfully", "application/json", GroupMemberResponse},
      forbidden: Schemas.error("Cannot join (full, no invite)"),
      conflict: Schemas.error("Already a member"),
      not_found: Schemas.error("Invite not found"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:decline_invite,
    operation_id: "decline_group_invite",
    summary: "Decline a group invitation",
    description:
      "Decline a pending group invitation by invite ID. Only the recipient can decline. The invite is marked as declined (not deleted).",
    security: [%{"authorization" => []}],
    parameters: [
      invite_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Invite ID (from the invitations list)",
        required: true
      ]
    ],
    responses: [
      ok: {"Invite declined", "application/json", OkResponse},
      not_found: Schemas.error("Invite not found"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:invitations,
    operation_id: "list_group_invitations",
    summary: "List my group invitations",
    description:
      "List pending group invitations (GroupInvite records) for the authenticated user, with pagination.",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer}, description: "Page number (default: 1)"],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Items per page (default: 25)"
      ]
    ],
    responses: [
      ok: {"Invitations list", "application/json", GroupInvitePage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:my_groups,
    operation_id: "list_my_groups",
    summary: "List groups I belong to",
    description: "List groups the authenticated user is a member of, with pagination.",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer}, description: "Page number (default: 1)"],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Items per page (default: 25)"
      ]
    ],
    responses: [
      ok: {"My groups", "application/json", GroupPage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:sent_invitations,
    operation_id: "list_sent_invitations",
    summary: "List group invitations I have sent",
    description:
      "List group invitations (GroupInvite records) sent by the authenticated user, with pagination.",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer}, description: "Page number (default: 1)"],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Items per page (default: 25)"
      ]
    ],
    responses: [
      ok: {"Sent invitations list", "application/json", GroupInvitePage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:cancel_invite,
    operation_id: "cancel_group_invite",
    summary: "Cancel a sent group invitation",
    description: "Cancel (delete) a group invitation that the authenticated user sent.",
    security: [%{"authorization" => []}],
    parameters: [
      invite_id: [
        in: :path,
        type: :string,
        description: "ID of the GroupInvite to cancel",
        required: true
      ]
    ],
    responses: [
      ok: {"Invitation cancelled", "application/json", OkResponse},
      forbidden: Schemas.error("Not allowed"),
      not_found: Schemas.error("Invitation not found"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  def index(conn, params) do
    filters =
      %{}
      |> maybe_put_string_filter(:title, param_value(params, "title", :title))
      |> maybe_put_string_filter(:type, param_value(params, "type", :type))
      |> maybe_put_int_filter(:min_members, param_value(params, "min_members", :min_members))
      |> maybe_put_int_filter(:max_members, param_value(params, "max_members", :max_members))
      |> maybe_put_string_filter(
        :metadata_key,
        param_value(params, "metadata_key", :metadata_key)
      )
      |> maybe_put_string_filter(
        :metadata_value,
        param_value(params, "metadata_value", :metadata_value)
      )

    {page, page_size} = GamendWeb.Pagination.params(params)
    sort_by = Map.get(params, "sort_by")

    groups =
      Groups.list_groups(filters,
        page: page,
        page_size: page_size,
        sort_by: sort_by
      )

    member_counts = Groups.batch_member_counts(Enum.map(groups, & &1.id))
    serialized = Enum.map(groups, &serialize_group(&1, member_counts))
    total_count = Groups.count_list_groups(filters)

    reply_page(conn, serialized, page, page_size, total_count)
  end

  def show(conn, %{"id" => id}) do
    case parse_id(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      group_id ->
        case visible_group(conn, group_id) do
          nil -> reply_error(conn, :not_found, "not_found")
          group -> reply_data(conn, serialize_group(group))
        end
    end
  end

  # A group the caller is allowed to know exists.
  #
  # `list_groups/2` has always excluded hidden groups, but fetching one by id
  # did not check the type at all — so anyone holding an id (they appear in
  # invite notifications and as a chat's `chat_ref_id`) could read a hidden
  # group and its full roster without a token. Hidden groups are invite-only by
  # definition, so non-members get the same 404 as a group that does not exist.
  defp visible_group(conn, group_id) do
    case Groups.get_group(group_id) do
      %{type: "hidden"} = group ->
        case Scope.user(conn.assigns[:current_scope]) do
          %User{id: user_id} -> if Groups.member?(user_id, group_id), do: group
          _ -> nil
        end

      group ->
        group
    end
  end

  def create(conn, params) do
    with_auth(conn, fn user ->
      case Groups.create_group(user.id, params) do
        {:ok, group} ->
          reply_data(conn, :created, serialize_group(group))

        {:error, %Ecto.Changeset{} = changeset} ->
          uniqueness_conflict(conn, changeset)

        {:error, reason} when is_atom(reason) ->
          reply_error(conn, :conflict, reason)
      end
    end)
  end

  def update(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      case parse_id(id) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        group_id ->
          case Groups.update_group(user.id, group_id, params) do
            {:ok, group} ->
              reply_data(conn, serialize_group(group))

            {:error, :not_admin} ->
              reply_error(conn, :forbidden, "not_admin")

            {:error, :not_found} ->
              reply_error(conn, :not_found, "not_found")

            {:error, :max_members_too_low} ->
              reply_error(conn, :unprocessable_entity, "max_members_too_low")

            {:error, %Ecto.Changeset{} = changeset} ->
              unprocessable(conn, changeset)

            {:error, reason} when is_atom(reason) ->
              reply_error(conn, :unprocessable_entity, reason)
          end
      end
    end)
  end

  def delete(conn, %{"id" => id}) do
    with_auth(conn, fn user ->
      case parse_id(id) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        group_id ->
          case Groups.delete_group(user.id, group_id) do
            {:ok, _} -> reply_ok(conn)
            {:error, :not_found} -> reply_error(conn, :not_found, "not_found")
            {:error, :not_admin} -> reply_error(conn, :forbidden, "not_admin")
            {:error, _hook_refused} -> reply_error(conn, :forbidden, "rejected")
          end
      end
    end)
  end

  operation(:icon_upload_url,
    operation_id: "create_group_icon_upload_url",
    summary: "Request a group icon upload ticket (admin only)",
    description:
      "Returns a presigned ticket for uploading the group's icon to storage. " <>
        "Upload the file to `upload_url`, then confirm with `POST /groups/{id}/icon` " <>
        "using the returned `key`.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    request_body: {
      "Upload intent",
      "application/json",
      %Schema{
        type: :object,
        properties: %{content_type: %Schema{type: :string, example: "image/png"}},
        required: [:content_type]
      }
    },
    responses: [
      ok: {"Upload ticket", "application/json", UploadTicketResponse},
      bad_request: Schemas.error("Unsupported content type"),
      forbidden: Schemas.error("Not a group admin"),
      unauthorized: Schemas.error("Not authenticated"),
      not_found: Schemas.error("Group not found")
    ]
  )

  def icon_upload_url(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      with_group_admin(conn, user, id, fn group_id ->
        Uploads.ticket(conn, "icons/groups", group_id, "icon", Uploads.content_type(params))
      end)
    end)
  end

  operation(:set_icon,
    operation_id: "set_group_icon",
    summary: "Confirm an uploaded group icon (admin only)",
    description: "Records a previously uploaded object (`key`) as the group's icon.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID",
        required: true
      ]
    ],
    request_body: {
      "Uploaded object key",
      "application/json",
      %Schema{type: :object, properties: %{key: %Schema{type: :string}}, required: [:key]}
    },
    responses: [
      ok: {"Group with the new icon", "application/json", GroupResponse},
      bad_request: Schemas.error("Object not found"),
      forbidden: Schemas.error("Not a group admin or key not owned"),
      unauthorized: Schemas.error("Not authenticated"),
      not_found: Schemas.error("Group not found")
    ]
  )

  def set_icon(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      with_group_admin(conn, user, id, fn group_id ->
        Uploads.confirm(conn, "icons/groups", group_id, params["key"], fn url ->
          save_icon(conn, user, group_id, url)
        end)
      end)
    end)
  end

  defp save_icon(conn, user, group_id, url) do
    case Groups.set_icon_url(user.id, group_id, url) do
      {:ok, group} ->
        reply_data(conn, serialize_group(group))

      # Deleted since `with_group_admin/4` read it.
      {:error, :not_found} ->
        reply_error(conn, :not_found, "not_found")

      {:error, _reason} ->
        reply_error(conn, :unprocessable_entity, "invalid_data")
    end
  end

  defp with_group_admin(conn, user, raw_id, fun) do
    case parse_id(raw_id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      group_id ->
        cond do
          Groups.get_group(group_id) == nil ->
            reply_error(conn, :not_found, "not_found")

          not Groups.can_manage_group?(user.id, group_id) ->
            reply_error(conn, :forbidden, "not_admin")

          true ->
            fun.(group_id)
        end
    end
  end

  def join(conn, %{"id" => id}) do
    with_auth(conn, fn user ->
      case parse_id(id) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        group_id ->
          group = Groups.get_group(group_id)
          do_join(conn, user, group, group_id)
      end
    end)
  end

  defp do_join(conn, _user, nil, _group_id) do
    reply_error(conn, :not_found, "not_found")
  end

  defp do_join(conn, user, %{type: "public"} = _group, group_id) do
    case Groups.join_group(user.id, group_id) do
      {:ok, member} ->
        reply_data(conn, serialize_member(member))

      {:error, :not_found} ->
        reply_error(conn, :not_found, "not_found")

      {:error, reason} ->
        reply_error(conn, :forbidden, reason)
    end
  end

  defp do_join(conn, user, %{type: "private"} = _group, group_id) do
    case Groups.request_join(user.id, group_id) do
      {:ok, request} ->
        reply_data(conn, :created, serialize_join_request(request))

      {:error, :not_found} ->
        reply_error(conn, :not_found, "not_found")

      {:error, reason} ->
        reply_error(conn, :forbidden, reason)
    end
  end

  defp do_join(conn, _user, _group, _group_id) do
    # hidden groups require an invite
    reply_error(conn, :forbidden, "not_joinable")
  end

  def leave(conn, %{"id" => id}) do
    with_auth(conn, fn user ->
      case parse_id(id) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        group_id ->
          case Groups.leave_group(user.id, group_id) do
            {:ok, _} ->
              reply_ok(conn)

            {:error, :not_member} ->
              reply_error(conn, :bad_request, "not_member")

            {:error, reason} ->
              reply_error(conn, :unprocessable_entity, reason)
          end
      end
    end)
  end

  def kick(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      target_user_id = Map.get(params, "target_user_id") || Map.get(params, :target_user_id)

      case {parse_id(id), parse_id(target_user_id)} do
        {nil, _} ->
          reply_error(conn, :not_found, "not_found")

        {_, nil} ->
          reply_error(conn, :bad_request, "missing_target_user_id")

        {group_id, tid} ->
          case Groups.kick_member(user.id, group_id, tid) do
            {:ok, _} ->
              reply_ok(conn)

            {:error, :not_admin} ->
              reply_error(conn, :forbidden, "not_admin")

            {:error, :cannot_kick_self} ->
              reply_error(conn, :forbidden, "cannot_kick_self")

            {:error, :not_member} ->
              reply_error(conn, :not_found, "not_member")

            {:error, reason} ->
              reply_error(conn, :forbidden, reason)
          end
      end
    end)
  end

  def members(conn, %{"id" => id} = params) do
    case parse_id(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      group_id ->
        case visible_group(conn, group_id) do
          nil ->
            reply_error(conn, :not_found, "not_found")

          _group ->
            {page, page_size} = GamendWeb.Pagination.params(params)
            authenticated? = match?(%User{}, Scope.user(conn.assigns[:current_scope]))

            members =
              Groups.get_group_members_paginated(group_id, page: page, page_size: page_size)

            serialized = Enum.map(members, &serialize_member(&1, authenticated?))
            total_count = Groups.count_group_members(group_id)

            reply_page(conn, serialized, page, page_size, total_count)
        end
    end
  end

  def promote(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      target_user_id = Map.get(params, "target_user_id") || Map.get(params, :target_user_id)

      case {parse_id(id), parse_id(target_user_id)} do
        {nil, _} ->
          reply_error(conn, :not_found, "not_found")

        {_, nil} ->
          reply_error(conn, :bad_request, "missing_target_user_id")

        {group_id, tid} ->
          case Groups.promote_member(user.id, group_id, tid) do
            {:ok, member} ->
              reply_data(conn, serialize_member(member))

            {:error, :not_admin} ->
              reply_error(conn, :forbidden, "not_admin")

            {:error, :cannot_promote_self} ->
              reply_error(conn, :forbidden, "cannot_promote_self")

            {:error, :not_member} ->
              reply_error(conn, :not_found, "not_member")

            {:error, :already_admin} ->
              reply_error(conn, :conflict, "already_admin")

            {:error, reason} ->
              reply_error(conn, :forbidden, reason)
          end
      end
    end)
  end

  def demote(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      target_user_id = Map.get(params, "target_user_id") || Map.get(params, :target_user_id)

      case {parse_id(id), parse_id(target_user_id)} do
        {nil, _} ->
          reply_error(conn, :not_found, "not_found")

        {_, nil} ->
          reply_error(conn, :bad_request, "missing_target_user_id")

        {group_id, tid} ->
          case Groups.demote_member(user.id, group_id, tid) do
            {:ok, member} ->
              reply_data(conn, serialize_member(member))

            {:error, :not_admin} ->
              reply_error(conn, :forbidden, "not_admin")

            {:error, :cannot_demote_self} ->
              reply_error(conn, :forbidden, "cannot_demote_self")

            {:error, :not_member} ->
              reply_error(conn, :not_found, "not_member")

            {:error, :already_member} ->
              reply_error(conn, :conflict, "already_member")

            {:error, reason} ->
              reply_error(conn, :forbidden, reason)
          end
      end
    end)
  end

  def join_requests(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      case parse_id(id) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        group_id ->
          {page, page_size} = GamendWeb.Pagination.params(params)

          case Groups.list_join_requests(user.id, group_id, page: page, page_size: page_size) do
            {:ok, requests} ->
              serialized = Enum.map(requests, &serialize_join_request/1)
              total_count = Groups.count_join_requests(group_id)

              reply_page(conn, serialized, page, page_size, total_count)

            {:error, :not_admin} ->
              reply_error(conn, :forbidden, "not_admin")
          end
      end
    end)
  end

  def approve_request(conn, %{"id" => _id, "request_id" => request_id}) do
    with_auth(conn, fn user ->
      case parse_id(request_id) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        rid ->
          case Groups.approve_join_request(user.id, rid) do
            {:ok, member} ->
              reply_data(conn, serialize_member(member))

            {:error, :not_found} ->
              reply_error(conn, :not_found, "not_found")

            {:error, :not_pending} ->
              reply_error(conn, :forbidden, "not_pending")

            {:error, :not_admin} ->
              reply_error(conn, :forbidden, "not_admin")

            {:error, :full} ->
              reply_error(conn, :forbidden, "full")

            {:error, reason} ->
              reply_error(conn, :forbidden, reason)
          end
      end
    end)
  end

  def reject_request(conn, %{"id" => _id, "request_id" => request_id}) do
    with_auth(conn, fn user ->
      case parse_id(request_id) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        rid ->
          case Groups.reject_join_request(user.id, rid) do
            {:ok, request} ->
              reply_data(conn, serialize_join_request(request))

            {:error, :not_found} ->
              reply_error(conn, :not_found, "not_found")

            {:error, :not_pending} ->
              reply_error(conn, :forbidden, "not_pending")

            {:error, :not_admin} ->
              reply_error(conn, :forbidden, "not_admin")

            {:error, reason} ->
              reply_error(conn, :unprocessable_entity, reason)
          end
      end
    end)
  end

  def cancel_request(conn, %{"id" => _id, "request_id" => request_id}) do
    with_auth(conn, fn user ->
      case parse_id(request_id) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        rid ->
          case Groups.cancel_join_request(user.id, rid) do
            {:ok, request} ->
              reply_data(conn, serialize_join_request(request))

            {:error, :not_found} ->
              reply_error(conn, :not_found, "not_found")

            {:error, :not_pending} ->
              reply_error(conn, :forbidden, "not_pending")

            {:error, :not_owner} ->
              reply_error(conn, :forbidden, "not_owner")

            {:error, reason} ->
              reply_error(conn, :unprocessable_entity, reason)
          end
      end
    end)
  end

  def invite(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      target_user_id = Map.get(params, "target_user_id") || Map.get(params, :target_user_id)

      case {parse_id(id), parse_id(target_user_id)} do
        {nil, _} ->
          reply_error(conn, :not_found, "not_found")

        {_, nil} ->
          reply_error(conn, :bad_request, "missing_target_user_id")

        {group_id, tid} ->
          case Groups.invite_to_group(user.id, group_id, tid) do
            {:ok, :request_approved} ->
              reply_data(conn, %{status: "request_approved"})

            {:ok, _invite} ->
              reply_data(conn, %{status: "invited"})

            {:error, :not_found} ->
              reply_error(conn, :not_found, "not_found")

            {:error, :not_admin} ->
              reply_error(conn, :forbidden, "not_admin")

            {:error, :already_member} ->
              reply_error(conn, :conflict, "already_member")

            {:error, :blocked} ->
              reply_error(conn, :forbidden, "blocked")

            {:error, reason} ->
              reply_error(conn, :forbidden, reason)
          end
      end
    end)
  end

  def accept_invite(conn, %{"invite_id" => invite_id_raw}) do
    with_auth(conn, fn user ->
      case parse_id(invite_id_raw) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        invite_id ->
          case Groups.accept_invite(user.id, invite_id) do
            {:ok, member} ->
              reply_data(conn, serialize_member(member))

            {:error, :not_found} ->
              reply_error(conn, :not_found, "not_found")

            {:error, :already_member} ->
              reply_error(conn, :conflict, "already_member")

            {:error, :no_invite} ->
              reply_error(conn, :not_found, "not_found")

            {:error, :full} ->
              reply_error(conn, :forbidden, "full")

            {:error, reason} ->
              reply_error(conn, :forbidden, reason)
          end
      end
    end)
  end

  def decline_invite(conn, %{"invite_id" => invite_id_raw}) do
    with_auth(conn, fn user ->
      case parse_id(invite_id_raw) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        invite_id ->
          case Groups.decline_invite(user.id, invite_id) do
            :ok ->
              reply_ok(conn)

            {:error, :not_found} ->
              reply_error(conn, :not_found, "not_found")
          end
      end
    end)
  end

  def invitations(conn, params) do
    with_auth(conn, fn user ->
      {page, page_size} = GamendWeb.Pagination.params(params)
      invites = Groups.list_invitations(user.id, page: page, page_size: page_size)
      total_count = Groups.count_invitations(user.id)

      reply_page(conn, invites, page, page_size, total_count)
    end)
  end

  def my_groups(conn, params) do
    with_auth(conn, fn user ->
      {page, page_size} = GamendWeb.Pagination.params(params)
      groups = Groups.list_user_groups(user.id, page: page, page_size: page_size)
      member_counts = Groups.batch_member_counts(Enum.map(groups, & &1.id))
      serialized = Enum.map(groups, &serialize_group(&1, member_counts))
      total_count = Groups.count_user_groups(user.id)

      reply_page(conn, serialized, page, page_size, total_count)
    end)
  end

  def sent_invitations(conn, params) do
    with_auth(conn, fn user ->
      {page, page_size} = GamendWeb.Pagination.params(params)
      invites = Groups.list_sent_invitations(user.id, page: page, page_size: page_size)
      total_count = Groups.count_sent_invitations(user.id)

      reply_page(conn, invites, page, page_size, total_count)
    end)
  end

  def cancel_invite(conn, %{"invite_id" => invite_id}) do
    with_auth(conn, fn user ->
      case parse_id(invite_id) do
        nil ->
          reply_error(conn, :not_found, "not_found")

        iid ->
          case Groups.cancel_invite(user.id, iid) do
            :ok ->
              reply_ok(conn)

            {:error, :not_found} ->
              reply_error(conn, :not_found, "not_found")

            {:error, :not_owner} ->
              reply_error(conn, :forbidden, "not_owner")
          end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp with_auth(conn, fun) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user -> fun.(user)
      _ -> reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  defp serialize_group(group, member_counts \\ %{}) do
    Serializers.serialize_group(group,
      member_counts: member_counts,
      include_slowdown: true,
      include_timestamps: true
    )
  end

  # `authenticated?` controls the presence and avatar fields.
  #
  # `UserController.serialize_user/1` deliberately strips `profile_url` and
  # `last_seen_at` from its unauthenticated responses; this listing returned
  # both for every member of any group, which made it the easier way to collect
  # exactly what that endpoint protects.
  defp serialize_member(member, authenticated? \\ true) do
    user_loaded? = Ecto.assoc_loaded?(member.user) and member.user != nil

    username = if user_loaded?, do: member.user.username, else: nil
    display_name = if user_loaded?, do: member.user.display_name, else: nil

    profile_url =
      if user_loaded? and authenticated?, do: User.public_avatar_url(member.user), else: nil

    is_online =
      if user_loaded? and authenticated?, do: member.user.is_online || false, else: false

    last_seen_at =
      if user_loaded? and authenticated?,
        do: User.last_seen_at_or_fallback(member.user),
        else: ~U[1970-01-01 00:00:00Z]

    %{
      id: member.id,
      user_id: member.user_id,
      group_id: member.group_id,
      role: member.role,
      username: username || "",
      display_name: display_name || "",
      profile_url: profile_url || "",
      is_online: is_online,
      last_seen_at: last_seen_at,
      inserted_at: member.inserted_at
    }
  end

  defp serialize_join_request(request) do
    user_loaded? = Ecto.assoc_loaded?(request.user) and request.user != nil
    username = if user_loaded?, do: request.user.username, else: nil
    display_name = if user_loaded?, do: request.user.display_name, else: nil

    %{
      id: request.id,
      user_id: request.user_id,
      group_id: request.group_id,
      status: request.status,
      username: username || "",
      display_name: display_name || "",
      inserted_at: request.inserted_at
    }
  end
end
