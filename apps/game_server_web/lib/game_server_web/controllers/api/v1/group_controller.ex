defmodule GameServerWeb.Api.V1.GroupController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.Accounts.Scope
  alias GameServer.Accounts.User
  alias GameServer.Groups
  alias GameServerWeb.Serializers
  alias GameServerWeb.Uploads
  alias OpenApiSpex.Schema

  tags(["Groups"])

  # ---------------------------------------------------------------------------
  # Shared schemas
  # ---------------------------------------------------------------------------

  @group_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Group ID"},
      title: %Schema{type: :string, description: "Display title"},
      description: %Schema{type: :string, description: "Description"},
      icon_url: %Schema{type: :string, description: "Icon URL; empty when unset"},
      type: %Schema{
        type: :string,
        enum: ["public", "private", "hidden"],
        description: "Visibility type"
      },
      max_members: %Schema{type: :integer, description: "Maximum number of members"},
      metadata: %Schema{type: :object, description: "Server-managed metadata"},
      creator_id: %Schema{
        type: :string,
        format: :uuid,
        description: "User ID of the creator, or -1 for system groups"
      },
      creator_name: %Schema{
        type: :string,
        description: "Display name of the creator"
      },
      member_count: %Schema{type: :integer, description: "Current member count"},
      slowdown: %Schema{type: :integer, description: "Chat slowdown in seconds (0 = disabled)"},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    example: %{
      id: "0198c0de-0001-7000-8000-000000000001",
      title: "Awesome Guild",
      description: "A group for awesome players",
      type: "public",
      max_members: 100,
      metadata: %{"lang_tag" => "en"},
      creator_id: "0198c0de-0002-7000-8000-000000000002",
      creator_name: "AwesomePlayer",
      member_count: 12,
      slowdown: 0
    }
  }

  @error_schema %Schema{
    type: :object,
    properties: %{error: %Schema{type: :string}}
  }

  @meta_schema %Schema{
    type: :object,
    properties: %{
      page: %Schema{type: :integer},
      page_size: %Schema{type: :integer},
      count: %Schema{type: :integer},
      total_count: %Schema{type: :integer},
      total_pages: %Schema{type: :integer},
      has_more: %Schema{type: :boolean}
    }
  }

  @member_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Membership ID"},
      user_id: %Schema{type: :string, format: :uuid},
      group_id: %Schema{type: :string, format: :uuid},
      role: %Schema{type: :string, enum: ["admin", "member"]},
      username: %Schema{type: :string},
      display_name: %Schema{type: :string},
      profile_url: %Schema{type: :string, description: "Empty when unset"},
      is_online: %Schema{type: :boolean},
      last_seen_at: %Schema{type: :string, format: "date-time"},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  @join_request_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Join request ID"},
      user_id: %Schema{type: :string, format: :uuid},
      group_id: %Schema{type: :string, format: :uuid},
      status: %Schema{type: :string, enum: ["pending", "accepted", "rejected"]},
      username: %Schema{type: :string},
      display_name: %Schema{type: :string},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  @invitation_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Invite ID"},
      group_id: %Schema{type: :string, format: :uuid},
      group_name: %Schema{type: :string},
      sender_id: %Schema{type: :string, format: :uuid},
      sender_name: %Schema{type: :string},
      recipient_id: %Schema{type: :string, format: :uuid},
      recipient_name: %Schema{type: :string},
      status: %Schema{type: :string, description: "pending | accepted | declined | cancelled"},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  }

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
      ok:
        {"List of groups", "application/json",
         %Schema{
           type: :object,
           properties: %{data: %Schema{type: :array, items: @group_schema}, meta: @meta_schema}
         }}
    ]
  )

  operation(:show,
    operation_id: "get_group",
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
      ok: {"Group details", "application/json", @group_schema},
      not_found: {"Group not found", "application/json", @error_schema}
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
      created: {"Group created", "application/json", @group_schema},
      conflict: {"Title taken or validation error", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok: {"Group updated", "application/json", @group_schema},
      forbidden: {"Not an admin", "application/json", @error_schema},
      unprocessable_entity: {"Validation error", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok: {"Joined successfully (public group)", "application/json", @member_schema},
      created: {"Join request created (private group)", "application/json", @join_request_schema},
      forbidden:
        {"Cannot join (full, hidden, already member, already requested)", "application/json",
         @error_schema},
      not_found: {"Group not found", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok: {"Left successfully", "application/json", %Schema{type: :object}},
      bad_request: {"Not a member", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok: {"User kicked", "application/json", %Schema{type: :object}},
      forbidden: {"Not admin or cannot kick", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  operation(:members,
    operation_id: "list_group_members",
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
      ok:
        {"Members list", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @member_schema},
             meta: @meta_schema
           }
         }},
      not_found: {"Group not found", "application/json", @error_schema}
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
      ok: {"Member promoted", "application/json", @member_schema},
      forbidden: {"Not admin", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok: {"Member demoted", "application/json", @member_schema},
      forbidden: {"Not admin", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok:
        {"Join requests", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @join_request_schema},
             meta: @meta_schema
           }
         }},
      forbidden: {"Not admin", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok: {"Request approved", "application/json", @member_schema},
      forbidden: {"Not admin or group full", "application/json", @error_schema},
      not_found: {"Request not found", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok: {"Request rejected", "application/json", @join_request_schema},
      forbidden: {"Not admin", "application/json", @error_schema},
      not_found: {"Request not found", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok: {"Request cancelled", "application/json", @join_request_schema},
      forbidden: {"Not owner or not pending", "application/json", @error_schema},
      not_found: {"Request not found", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
        {"Invitation sent or join request auto-approved", "application/json",
         %Schema{
           type: :object,
           properties: %{
             status: %Schema{
               type: :string,
               description:
                 "\"invited\" if a new invite was created, \"request_approved\" if a pending join request was auto-approved"
             }
           }
         }},
      forbidden: {"Not admin or target already member", "application/json", @error_schema},
      not_found: {"Group not found", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok: {"Joined successfully", "application/json", @member_schema},
      forbidden:
        {"Cannot join (full, already member, no invite)", "application/json", @error_schema},
      not_found: {"Invite not found", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok:
        {"Invite declined", "application/json",
         %Schema{
           type: :object,
           properties: %{status: %Schema{type: :string}}
         }},
      not_found: {"Invite not found", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok:
        {"Invitations list", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @invitation_schema},
             meta: @meta_schema
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok:
        {"My groups", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @group_schema},
             meta: @meta_schema
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok:
        {"Sent invitations list", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   group_id: %Schema{type: :string, format: :uuid},
                   group_name: %Schema{type: :string},
                   sender_id: %Schema{type: :string, format: :uuid},
                   sender_name: %Schema{type: :string},
                   recipient_id: %Schema{type: :string, format: :uuid},
                   recipient_name: %Schema{type: :string},
                   status: %Schema{type: :string},
                   inserted_at: %Schema{type: :string, format: :"date-time"}
                 }
               }
             },
             meta: @meta_schema
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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
      ok:
        {"Invitation cancelled", "application/json",
         %Schema{
           type: :object,
           properties: %{status: %Schema{type: :string}}
         }},
      forbidden: {"Not allowed", "application/json", @error_schema},
      not_found: {"Invitation not found", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  operation(:notify_group,
    operation_id: "notify_group",
    summary: "Send a notification to all group members",
    description:
      "Broadcasts a notification to every member of the group (except the sender). " <>
        "Any group member can send. Sending again from the same user with the same title " <>
        "replaces the previous notification (upsert, prevents spam).",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        type: :string,
        description: "Group ID",
        required: true
      ]
    ],
    request_body:
      {"Notification payload", "application/json",
       %Schema{
         type: :object,
         required: [:content],
         properties: %{
           content: %Schema{type: :string, description: "Notification message text"},
           title: %Schema{
             type: :string,
             description:
               "Notification title (default: \"Group Notification\"). " <>
                 "Different titles create separate notification slots per sender/recipient."
           },
           metadata: %Schema{
             type: :object,
             description:
               "Optional extra metadata (group_id and group_name are added automatically)",
             additionalProperties: true
           }
         }
       }},
    responses: [
      ok:
        {"Notifications sent", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{
                 sent: %Schema{type: :integer, description: "Number of notifications delivered"}
               }
             }
           }
         }},
      forbidden: {"Not a member", "application/json", @error_schema},
      not_found: {"Group not found", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
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

    {page, page_size} = GameServerWeb.Pagination.params(params)
    sort_by = Map.get(params, "sort_by")

    groups =
      Groups.list_groups(filters,
        page: page,
        page_size: page_size,
        sort_by: sort_by
      )

    member_counts = Groups.batch_member_counts(Enum.map(groups, & &1.id))
    serialized = Enum.map(groups, &serialize_group(&1, member_counts))
    count = length(serialized)
    total_count = Groups.count_list_groups(filters)

    json(conn, %{
      data: serialized,
      meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
    })
  end

  def show(conn, %{"id" => id}) do
    case parse_id(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      group_id ->
        case Groups.get_group(group_id) do
          nil -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
          group -> json(conn, serialize_group(group))
        end
    end
  end

  def create(conn, params) do
    with_auth(conn, fn user ->
      case Groups.create_group(user.id, params) do
        {:ok, group} ->
          conn |> put_status(:created) |> json(serialize_group(group))

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)})

        {:error, reason} when is_atom(reason) ->
          conn |> put_status(:conflict) |> json(%{error: to_string(reason)})
      end
    end)
  end

  def update(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      case parse_id(id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        group_id ->
          case Groups.update_group(user.id, group_id, params) do
            {:ok, group} ->
              json(conn, serialize_group(group))

            {:error, :not_admin} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_admin"})

            {:error, :max_members_too_low} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "max_members_too_low"})

            {:error, %Ecto.Changeset{} = changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{
                error: Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
              })

            {:error, reason} when is_atom(reason) ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
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
      ok: {"Upload ticket", "application/json", %Schema{type: :object}},
      bad_request: {"Unsupported content type", "application/json", @error_schema},
      forbidden: {"Not a group admin", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      not_found: {"Group not found", "application/json", @error_schema}
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
      ok: {"Group with the new icon", "application/json", @group_schema},
      bad_request: {"Object not found", "application/json", @error_schema},
      forbidden: {"Not a group admin or key not owned", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      not_found: {"Group not found", "application/json", @error_schema}
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
    case Groups.update_group(user.id, group_id, %{"icon_url" => url}) do
      {:ok, group} ->
        json(conn, serialize_group(group))

      {:error, _reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_data"})
    end
  end

  defp with_group_admin(conn, user, raw_id, fun) do
    case parse_id(raw_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      group_id ->
        cond do
          Groups.get_group(group_id) == nil ->
            conn |> put_status(:not_found) |> json(%{error: "not_found"})

          not Groups.admin?(group_id, user.id) ->
            conn |> put_status(:forbidden) |> json(%{error: "not_admin"})

          true ->
            fun.(group_id)
        end
    end
  end

  def join(conn, %{"id" => id}) do
    with_auth(conn, fn user ->
      case parse_id(id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        group_id ->
          group = Groups.get_group(group_id)
          do_join(conn, user, group, group_id)
      end
    end)
  end

  defp do_join(conn, _user, nil, _group_id) do
    conn |> put_status(:not_found) |> json(%{error: "not_found"})
  end

  defp do_join(conn, user, %{type: "public"} = _group, group_id) do
    case Groups.join_group(user.id, group_id) do
      {:ok, member} ->
        json(conn, serialize_member(member))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, reason} ->
        conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})
    end
  end

  defp do_join(conn, user, %{type: "private"} = _group, group_id) do
    case Groups.request_join(user.id, group_id) do
      {:ok, request} ->
        conn |> put_status(:created) |> json(serialize_join_request(request))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, reason} ->
        conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})
    end
  end

  defp do_join(conn, _user, _group, _group_id) do
    # hidden groups require an invite
    conn |> put_status(:forbidden) |> json(%{error: "not_joinable"})
  end

  def leave(conn, %{"id" => id}) do
    with_auth(conn, fn user ->
      case parse_id(id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        group_id ->
          case Groups.leave_group(user.id, group_id) do
            {:ok, _} ->
              json(conn, %{})

            {:error, :not_member} ->
              conn |> put_status(:bad_request) |> json(%{error: "not_member"})

            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
          end
      end
    end)
  end

  def kick(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      target_user_id = Map.get(params, "target_user_id") || Map.get(params, :target_user_id)

      case {parse_id(id), parse_id(target_user_id)} do
        {nil, _} ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        {_, nil} ->
          conn |> put_status(:bad_request) |> json(%{error: "missing_target_user_id"})

        {group_id, tid} ->
          case Groups.kick_member(user.id, group_id, tid) do
            {:ok, _} ->
              json(conn, %{})

            {:error, :not_admin} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_admin"})

            {:error, :cannot_kick_self} ->
              conn |> put_status(:forbidden) |> json(%{error: "cannot_kick_self"})

            {:error, :not_member} ->
              conn |> put_status(:not_found) |> json(%{error: "not_member"})

            {:error, reason} ->
              conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})
          end
      end
    end)
  end

  def members(conn, %{"id" => id} = params) do
    case parse_id(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      group_id ->
        case Groups.get_group(group_id) do
          nil ->
            conn |> put_status(:not_found) |> json(%{error: "not_found"})

          _group ->
            {page, page_size} = GameServerWeb.Pagination.params(params)

            members =
              Groups.get_group_members_paginated(group_id, page: page, page_size: page_size)

            serialized = Enum.map(members, &serialize_member/1)
            count = length(serialized)
            total_count = Groups.count_group_members(group_id)

            json(conn, %{
              data: serialized,
              meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
            })
        end
    end
  end

  def promote(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      target_user_id = Map.get(params, "target_user_id") || Map.get(params, :target_user_id)

      case {parse_id(id), parse_id(target_user_id)} do
        {nil, _} ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        {_, nil} ->
          conn |> put_status(:bad_request) |> json(%{error: "missing_target_user_id"})

        {group_id, tid} ->
          case Groups.promote_member(user.id, group_id, tid) do
            {:ok, member} ->
              json(conn, serialize_member(member))

            {:error, :not_admin} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_admin"})

            {:error, :cannot_promote_self} ->
              conn |> put_status(:forbidden) |> json(%{error: "cannot_promote_self"})

            {:error, :not_member} ->
              conn |> put_status(:not_found) |> json(%{error: "not_member"})

            {:error, :already_admin} ->
              conn |> put_status(:forbidden) |> json(%{error: "already_admin"})

            {:error, reason} ->
              conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})
          end
      end
    end)
  end

  def demote(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      target_user_id = Map.get(params, "target_user_id") || Map.get(params, :target_user_id)

      case {parse_id(id), parse_id(target_user_id)} do
        {nil, _} ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        {_, nil} ->
          conn |> put_status(:bad_request) |> json(%{error: "missing_target_user_id"})

        {group_id, tid} ->
          case Groups.demote_member(user.id, group_id, tid) do
            {:ok, member} ->
              json(conn, serialize_member(member))

            {:error, :not_admin} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_admin"})

            {:error, :cannot_demote_self} ->
              conn |> put_status(:forbidden) |> json(%{error: "cannot_demote_self"})

            {:error, :not_member} ->
              conn |> put_status(:not_found) |> json(%{error: "not_member"})

            {:error, :already_member} ->
              conn |> put_status(:forbidden) |> json(%{error: "already_member"})

            {:error, reason} ->
              conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})
          end
      end
    end)
  end

  def join_requests(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      case parse_id(id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        group_id ->
          {page, page_size} = GameServerWeb.Pagination.params(params)

          case Groups.list_join_requests(user.id, group_id, page: page, page_size: page_size) do
            {:ok, requests} ->
              serialized = Enum.map(requests, &serialize_join_request/1)
              count = length(serialized)
              total_count = Groups.count_join_requests(group_id)

              json(conn, %{
                data: serialized,
                meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
              })

            {:error, :not_admin} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_admin"})
          end
      end
    end)
  end

  def approve_request(conn, %{"id" => _id, "request_id" => request_id}) do
    with_auth(conn, fn user ->
      case parse_id(request_id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        rid ->
          case Groups.approve_join_request(user.id, rid) do
            {:ok, member} ->
              json(conn, serialize_member(member))

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "not_found"})

            {:error, :not_pending} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_pending"})

            {:error, :not_admin} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_admin"})

            {:error, :full} ->
              conn |> put_status(:forbidden) |> json(%{error: "full"})

            {:error, reason} ->
              conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})
          end
      end
    end)
  end

  def reject_request(conn, %{"id" => _id, "request_id" => request_id}) do
    with_auth(conn, fn user ->
      case parse_id(request_id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        rid ->
          case Groups.reject_join_request(user.id, rid) do
            {:ok, request} ->
              json(conn, serialize_join_request(request))

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "not_found"})

            {:error, :not_pending} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_pending"})

            {:error, :not_admin} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_admin"})

            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
          end
      end
    end)
  end

  def cancel_request(conn, %{"id" => _id, "request_id" => request_id}) do
    with_auth(conn, fn user ->
      case parse_id(request_id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        rid ->
          case Groups.cancel_join_request(user.id, rid) do
            {:ok, request} ->
              json(conn, serialize_join_request(request))

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "not_found"})

            {:error, :not_pending} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_pending"})

            {:error, :not_owner} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_owner"})

            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
          end
      end
    end)
  end

  def invite(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      target_user_id = Map.get(params, "target_user_id") || Map.get(params, :target_user_id)

      case {parse_id(id), parse_id(target_user_id)} do
        {nil, _} ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        {_, nil} ->
          conn |> put_status(:bad_request) |> json(%{error: "missing_target_user_id"})

        {group_id, tid} ->
          case Groups.invite_to_group(user.id, group_id, tid) do
            {:ok, :request_approved} ->
              json(conn, %{status: "request_approved"})

            {:ok, _invite} ->
              json(conn, %{status: "invited"})

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "not_found"})

            {:error, :not_admin} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_admin"})

            {:error, :already_member} ->
              conn |> put_status(:forbidden) |> json(%{error: "already_member"})

            {:error, :blocked} ->
              conn |> put_status(:forbidden) |> json(%{error: "blocked"})

            {:error, reason} ->
              conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})
          end
      end
    end)
  end

  def accept_invite(conn, %{"invite_id" => invite_id_raw}) do
    with_auth(conn, fn user ->
      case parse_id(invite_id_raw) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        invite_id ->
          case Groups.accept_invite(user.id, invite_id) do
            {:ok, member} ->
              json(conn, serialize_member(member))

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "not_found"})

            {:error, :already_member} ->
              json(conn, %{status: "already_member"})

            {:error, :no_invite} ->
              conn |> put_status(:not_found) |> json(%{error: "not_found"})

            {:error, :full} ->
              conn |> put_status(:forbidden) |> json(%{error: "full"})

            {:error, reason} ->
              conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})
          end
      end
    end)
  end

  def decline_invite(conn, %{"invite_id" => invite_id_raw}) do
    with_auth(conn, fn user ->
      case parse_id(invite_id_raw) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        invite_id ->
          case Groups.decline_invite(user.id, invite_id) do
            :ok ->
              json(conn, %{status: "declined"})

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "not_found"})
          end
      end
    end)
  end

  def invitations(conn, params) do
    with_auth(conn, fn user ->
      {page, page_size} = GameServerWeb.Pagination.params(params)
      invites = Groups.list_invitations(user.id, page: page, page_size: page_size)
      count = length(invites)
      total_count = Groups.count_invitations(user.id)

      json(conn, %{
        data: invites,
        meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
      })
    end)
  end

  def my_groups(conn, params) do
    with_auth(conn, fn user ->
      {page, page_size} = GameServerWeb.Pagination.params(params)
      groups = Groups.list_user_groups(user.id, page: page, page_size: page_size)
      member_counts = Groups.batch_member_counts(Enum.map(groups, & &1.id))
      serialized = Enum.map(groups, &serialize_group(&1, member_counts))
      count = length(serialized)
      total_count = Groups.count_user_groups(user.id)

      json(conn, %{
        data: serialized,
        meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
      })
    end)
  end

  def sent_invitations(conn, params) do
    with_auth(conn, fn user ->
      {page, page_size} = GameServerWeb.Pagination.params(params)
      invites = Groups.list_sent_invitations(user.id, page: page, page_size: page_size)
      count = length(invites)
      total_count = Groups.count_sent_invitations(user.id)

      json(conn, %{
        data: invites,
        meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
      })
    end)
  end

  def cancel_invite(conn, %{"invite_id" => invite_id}) do
    with_auth(conn, fn user ->
      case parse_id(invite_id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        iid ->
          case Groups.cancel_invite(user.id, iid) do
            :ok ->
              json(conn, %{status: "cancelled"})

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "not_found"})

            {:error, :not_owner} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_owner"})
          end
      end
    end)
  end

  def notify_group(conn, %{"id" => id} = params) do
    with_auth(conn, fn user ->
      case parse_id(id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        group_id ->
          content = Map.get(params, "content") || Map.get(params, :content) || ""
          title = Map.get(params, "title") || Map.get(params, :title)
          extra_metadata = Map.get(params, "metadata") || Map.get(params, :metadata) || %{}

          # Pass the title through metadata so the domain function can extract it
          metadata =
            if title do
              Map.put(extra_metadata, "title", title)
            else
              extra_metadata
            end

          case Groups.notify_group(user.id, group_id, content, metadata) do
            {:ok, sent} ->
              json(conn, %{data: %{sent: sent}})

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "not_found"})

            {:error, :not_member} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_member"})
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
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  defp serialize_group(group, member_counts \\ %{}) do
    Serializers.serialize_group(group,
      member_counts: member_counts,
      include_slowdown: true,
      include_timestamps: true
    )
  end

  defp serialize_member(member) do
    user_loaded? = Ecto.assoc_loaded?(member.user) and member.user != nil

    username = if user_loaded?, do: member.user.username, else: nil
    display_name = if user_loaded?, do: member.user.display_name, else: nil
    profile_url = if user_loaded?, do: member.user.profile_url, else: nil
    is_online = if user_loaded?, do: member.user.is_online || false, else: false

    last_seen_at =
      if user_loaded?,
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
