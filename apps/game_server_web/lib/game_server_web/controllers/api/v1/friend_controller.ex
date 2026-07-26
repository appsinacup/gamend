defmodule GameServerWeb.Api.V1.FriendController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.Accounts.Scope
  alias GameServer.Accounts.User
  alias GameServer.Friends
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  @ok_schema %Schema{type: :object}
  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @validation_error_schema %Schema{
    type: :object,
    properties: %{error: %Schema{type: :string}, errors: %Schema{type: :object}}
  }

  tags(["Friends"])

  @request_list_schema %Schema{
    type: :array,
    items: %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        requester: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            username: %Schema{type: :string},
            display_name: %Schema{type: :string},
            metadata: %Schema{type: :object, description: "User metadata"},
            is_online: %Schema{type: :boolean},
            last_seen_at: %Schema{type: :string, format: :date_time, nullable: false}
          }
        },
        target: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            username: %Schema{type: :string},
            display_name: %Schema{type: :string},
            metadata: %Schema{type: :object, description: "User metadata"},
            is_online: %Schema{type: :boolean},
            last_seen_at: %Schema{type: :string, format: :date_time, nullable: false}
          }
        },
        status: %Schema{type: :string},
        inserted_at: %Schema{type: :string, format: :date_time}
      }
    }
  }

  @request_meta_schema %Schema{
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

  operation(:create,
    operation_id: "create_friend_request",
    summary: "Send a friend request",
    security: [%{"authorization" => []}],
    request_body: {
      "Friend request",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          target_user_id: %Schema{
            type: :string,
            format: :uuid,
            description: "Target user's id (user_id) to whom the request will be sent"
          }
        },
        required: [:target_user_id]
      }
    },
    responses: [
      created: {"Request created", "application/json", @ok_schema},
      bad_request: {"Bad request", "application/json", @error_schema},
      conflict: {"Already friends or requested", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", @validation_error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  operation(:index,
    operation_id: "list_friends",
    summary: "List current user's friends (returns a paginated set of user objects)",
    security: [%{"authorization" => []}],
    parameters: [
      page: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page number (1-based)",
        required: false
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page size (max results per page)",
        required: false
      ]
    ],
    responses: [
      ok:
        {"List of friends (paginated)", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   friendship_id: %Schema{type: :string, format: :uuid},
                   username: %Schema{type: :string},
                   display_name: %Schema{type: :string},
                   profile_url: %Schema{type: :string},
                   metadata: %Schema{
                     type: :object,
                     description: "User metadata (accessories, hat, color, etc.)"
                   },
                   is_online: %Schema{
                     type: :boolean,
                     description: "Whether the friend is currently connected"
                   },
                   last_seen_at: %Schema{
                     type: :string,
                     format: "date-time",
                     nullable: false,
                     description: "Last time the friend connected or disconnected"
                   }
                 }
               }
             },
             meta: %Schema{
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
           }
         }}
    ]
  )

  operation(:requests,
    operation_id: "list_friend_requests",
    summary: "List pending friend requests (incoming and outgoing)",
    security: [%{"authorization" => []}],
    parameters: [
      page: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page number (1-based, applied to both lists)",
        required: false
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page size (applied to both lists)",
        required: false
      ]
    ],
    responses: [
      ok: {
        "Requests",
        "application/json",
        %Schema{
          type: :object,
          properties: %{
            data: %Schema{
              type: :object,
              properties: %{
                incoming: @request_list_schema,
                outgoing: @request_list_schema
              }
            },
            meta: %Schema{
              type: :object,
              properties: %{
                incoming: @request_meta_schema,
                outgoing: @request_meta_schema
              }
            }
          }
        }
      }
    ]
  )

  operation(:accept,
    operation_id: "accept_friend_request",
    summary: "Accept a friend request",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description:
          "Friendship record id (friendship_id) - the id of the friendship row, not a user id",
        required: true
      ]
    ],
    responses: [
      ok: {"Accepted", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Not authorized", "application/json", @error_schema}
    ]
  )

  operation(:reject,
    operation_id: "reject_friend_request",
    summary: "Reject a friend request",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description:
          "Friendship record id (friendship_id) - the id of the friendship row, not a user id",
        required: true
      ]
    ],
    responses: [
      ok: {"Rejected", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Not authorized", "application/json", @error_schema}
    ]
  )

  operation(:block,
    operation_id: "block_friend_request",
    summary: "Block a friend request / user",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description:
          "Friendship record id (friendship_id) - the id of the friendship row, not a user id",
        required: true
      ]
    ],
    responses: [
      ok: {"Blocked", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Not authorized", "application/json", @error_schema}
    ]
  )

  operation(:blocked,
    operation_id: "list_blocked_friends",
    summary: "List users you've blocked",
    security: [%{"authorization" => []}],
    parameters: [
      page: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page number (1-based)",
        required: false
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page size (max results per page)",
        required: false
      ]
    ],
    responses: [
      ok: {
        "Blocked list",
        "application/json",
        %Schema{
          type: :object,
          properties: %{
            data: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{
                  id: %Schema{type: :string, format: :uuid},
                  requester: %Schema{
                    type: :object,
                    properties: %{
                      id: %Schema{type: :string, format: :uuid},
                      username: %Schema{type: :string},
                      display_name: %Schema{type: :string}
                    }
                  }
                }
              }
            },
            meta: %Schema{
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
          }
        }
      }
    ]
  )

  operation(:unblock,
    operation_id: "unblock_friend",
    summary: "Unblock a previously-blocked friendship",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description:
          "Friendship record id (friendship_id) - the id of the friendship row, not a user id",
        required: true
      ]
    ],
    responses: [
      ok: {"Unblocked", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Not authorized", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  operation(:blacklist,
    operation_id: "list_blacklisted_users",
    summary: "List the users you've blocked",
    description:
      "Returns the blocked users themselves. Use /me/blocked instead when you " <>
        "need the underlying friendship rows.",
    security: [%{"authorization" => []}],
    parameters: [
      page: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page number (1-based)",
        required: false
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page size (max results per page)",
        required: false
      ]
    ],
    responses: [
      ok: {
        "Blacklisted users",
        "application/json",
        %Schema{
          type: :object,
          properties: %{
            data: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{
                  id: %Schema{type: :string, format: :uuid},
                  username: %Schema{type: :string},
                  display_name: %Schema{type: :string}
                }
              }
            },
            meta: %Schema{type: :object}
          }
        }
      },
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  operation(:block_user,
    operation_id: "block_user",
    summary: "Blacklist a user, with or without an existing friendship",
    description:
      "Blocked players are kept apart in matchmaking and cannot join a lobby " <>
        "the other is in, in addition to the existing party, invite and chat blocks.",
    security: [%{"authorization" => []}],
    parameters: [
      user_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "User id to block (a user id, not a friendship id)",
        required: true
      ]
    ],
    responses: [
      ok: {"Blocked", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid id or cannot block self", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  operation(:unblock_user,
    operation_id: "unblock_user",
    summary: "Remove a user from your blacklist",
    security: [%{"authorization" => []}],
    parameters: [
      user_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "User id to unblock (a user id, not a friendship id)",
        required: true
      ]
    ],
    responses: [
      ok: {"Unblocked", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid id", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  operation(:delete,
    operation_id: "remove_friendship",
    summary: "Remove/cancel a friendship or request",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]],
    responses: [
      ok: {"Success", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Not authorized", "application/json", @error_schema}
    ]
  )

  # Clarify: the :id path parameter in accept/reject/block/delete/unblock
  # refers to the friendship record ID (friendship_id), not a user_id.

  def create(conn, %{"target_user_id" => _} = params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        target_id = params["target_user_id"]

        case Friends.create_request(user.id, target_id) do
          {:ok, _f} ->
            conn |> put_status(:created) |> json(%{})

          {:error, :cannot_friend_self} ->
            conn |> put_status(:bad_request) |> json(%{error: "cannot_friend_self"})

          {:error, %Ecto.Changeset{} = cs} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "validation_failed",
              errors: Ecto.Changeset.traverse_errors(cs, & &1)
            })

          {:error, reason} ->
            conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def block(conn, %{"id" => id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          int_id ->
            case Friends.block_friend_request(int_id, user) do
              {:ok, _f} ->
                json(conn, %{})

              {:error, :not_found} ->
                conn |> put_status(:not_found) |> json(%{error: "not_found"})

              {:error, :not_authorized} ->
                conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def blacklist(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        {page, page_size} = Pagination.params(params)

        users = Friends.list_blocked_users(user.id, page: page, page_size: page_size)
        serialized = Enum.map(users, &serialize_user/1)
        total_count = Friends.count_blocked_users(user.id)

        json(conn, %{
          data: serialized,
          meta: GameServerWeb.Pagination.meta(page, page_size, length(serialized), total_count)
        })

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def block_user(conn, %{"user_id" => user_id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(user_id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          target_id ->
            case Friends.block_user(user, target_id) do
              {:ok, _f} ->
                json(conn, %{})

              {:error, :cannot_block_self} ->
                conn |> put_status(:bad_request) |> json(%{error: "cannot_block_self"})

              {:error, _reason} ->
                conn |> put_status(:bad_request) |> json(%{error: "invalid"})
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def unblock_user(conn, %{"user_id" => user_id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(user_id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          target_id ->
            case Friends.unblock_user(user, target_id) do
              {:ok, :unblocked} ->
                json(conn, %{})

              {:error, :not_found} ->
                conn |> put_status(:not_found) |> json(%{error: "not_found"})

              {:error, reason} ->
                conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def index(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        {page, page_size} = Pagination.params(params)

        # include the friendship row id so clients can call delete/accept/reject by id
        friends = Friends.list_friends_with_friendship(user.id, page: page, page_size: page_size)
        serialized = Enum.map(friends, &serialize_friend/1)
        count = length(serialized)
        total_count = Friends.count_friends_for_user(user.id)

        json(conn, %{
          data: serialized,
          meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
        })

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def blocked(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        {page, page_size} = Pagination.params(params)

        blocked = Friends.list_blocked_for_user(user.id, page: page, page_size: page_size)

        serialized =
          Enum.map(blocked, fn f -> %{id: f.id, requester: serialize_user(f.requester)} end)

        count = length(serialized)
        total_count = Friends.count_blocked_for_user(user.id)

        json(conn, %{
          data: serialized,
          meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
        })

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def unblock(conn, %{"id" => id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          int_id ->
            case Friends.unblock_friendship(int_id, user) do
              {:ok, :unblocked} ->
                json(conn, %{})

              {:error, :not_found} ->
                conn |> put_status(:not_found) |> json(%{error: "not_found"})

              {:error, :not_authorized} ->
                conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

              {:error, reason} ->
                conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def requests(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        {page, page_size} = Pagination.params(params)

        incoming = Friends.list_incoming_requests(user.id, page: page, page_size: page_size)
        outgoing = Friends.list_outgoing_requests(user.id, page: page, page_size: page_size)

        inc_serialized = Enum.map(incoming, &serialize_request/1)
        out_serialized = Enum.map(outgoing, &serialize_request/1)

        total_in = Friends.count_incoming_requests(user.id)
        total_out = Friends.count_outgoing_requests(user.id)

        # Two collections share one window, so each gets its own standard meta
        # rather than the response inventing a parallel-map shape of its own.
        json(conn, %{
          data: %{incoming: inc_serialized, outgoing: out_serialized},
          meta: %{
            incoming: Pagination.meta(page, page_size, length(inc_serialized), total_in),
            outgoing: Pagination.meta(page, page_size, length(out_serialized), total_out)
          }
        })

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def accept(conn, %{"id" => id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          int_id ->
            case Friends.accept_friend_request(int_id, user) do
              {:ok, _f} ->
                json(conn, %{})

              {:error, :not_found} ->
                conn |> put_status(:not_found) |> json(%{error: "not_found"})

              {:error, :not_authorized} ->
                conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

              {:error, reason} ->
                conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def reject(conn, %{"id" => id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          int_id ->
            case Friends.reject_friend_request(int_id, user) do
              {:ok, _f} ->
                json(conn, %{})

              {:error, :not_found} ->
                conn |> put_status(:not_found) |> json(%{error: "not_found"})

              {:error, :not_authorized} ->
                conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

              {:error, reason} ->
                conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          int_id ->
            case Friends.get_friendship(int_id) do
              nil ->
                conn |> put_status(:not_found) |> json(%{error: "not_found"})

              f ->
                handle_delete_friendship(conn, user, f)
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  defp handle_delete_friendship(conn, user, f) do
    cond do
      f.status == "pending" and f.requester_id == user.id ->
        case Friends.cancel_request(f.id, user) do
          {:ok, :cancelled} -> json(conn, %{})
          err -> conn |> put_status(:bad_request) |> json(%{error: to_string(err)})
        end

      f.status == "accepted" and (f.requester_id == user.id or f.target_id == user.id) ->
        case Friends.remove_friend(
               user.id,
               if(f.requester_id == user.id, do: f.target_id, else: f.requester_id)
             ) do
          {:ok, _} -> json(conn, %{})
          err -> conn |> put_status(:bad_request) |> json(%{error: to_string(err)})
        end

      true ->
        conn |> put_status(:forbidden) |> json(%{error: "not_authorized"})
    end
  end

  defp serialize_user(user) do
    User.serialize_brief(user)
  end

  defp serialize_friend(%{friendship_id: fid, user: user}) do
    User.serialize_brief(user) |> Map.put(:friendship_id, fid)
  end

  defp serialize_request(%Friends.Friendship{} = f) do
    requester =
      case f.requester do
        %Ecto.Association.NotLoaded{} ->
          %{
            id: f.requester_id,
            username: "",
            display_name: "",
            metadata: %{},
            is_online: false,
            last_seen_at: User.last_seen_at_or_fallback(%User{})
          }

        %User{} = r ->
          User.serialize_brief(r)
      end

    target =
      case f.target do
        %Ecto.Association.NotLoaded{} ->
          %{
            id: f.target_id,
            username: "",
            display_name: "",
            metadata: %{},
            is_online: false,
            last_seen_at: User.last_seen_at_or_fallback(%User{})
          }

        %User{} = t ->
          User.serialize_brief(t)
      end

    %{
      id: f.id,
      requester: requester,
      target: target,
      status: f.status,
      inserted_at: f.inserted_at
    }
  end
end
