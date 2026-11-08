defmodule GamendWeb.Api.V1.FriendController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Friends
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    BlockedFriendshipPage,
    FriendPage,
    FriendRequestResponse,
    FriendRequestsResponse,
    OkResponse,
    UserBriefPage
  }

  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  require Gamend.Friends.FriendshipStatus, as: FriendshipStatus

  tags(["Friends"])

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
      created: {"Request created", "application/json", FriendRequestResponse},
      bad_request: Schemas.error("A request to yourself (cannot_friend_self)"),
      forbidden:
        Schemas.error(
          "Blocked (blocked), too many requests out (too_many_pending_requests), or, " <>
            "when this accepts their request to you, a full friend list (too_many_friends)"
        ),
      not_found: Schemas.error("Their request to you was cancelled meanwhile (not_found)"),
      conflict: Schemas.error("Already friends (already_friends)"),
      unprocessable_entity: Schemas.error("Validation failed"),
      unauthorized: Schemas.error("Not authenticated")
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
      ok: {"List of friends (paginated)", "application/json", FriendPage}
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
      ok: {"Requests", "application/json", FriendRequestsResponse}
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
      ok: {"Accepted", "application/json", OkResponse},
      bad_request: Schemas.error("Invalid id (invalid_id)"),
      unauthorized: Schemas.error("Not authenticated"),
      forbidden:
        Schemas.error(
          "Not authorized (forbidden), already rejected or blocked (not_pending), " <>
            "or a friend list is full (too_many_friends)"
        ),
      not_found: Schemas.error("No such request, or it was cancelled"),
      conflict: Schemas.error("Already accepted (already_friends)")
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
      ok: {"Rejected", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Not authorized, or already answered (not_pending)"),
      not_found: Schemas.error("No such request, or it was cancelled")
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
      ok: {"Blocked", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Not authorized, or already accepted or blocked (not_pending)"),
      not_found: Schemas.error("No such request, or it was cancelled")
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
      ok: {"Blocked list", "application/json", BlockedFriendshipPage}
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
      ok: {"Unblocked", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Not authorized"),
      not_found: Schemas.error("Not found")
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
      ok: {"Blacklisted users", "application/json", UserBriefPage},
      unauthorized: Schemas.error("Not authenticated")
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
      ok: {"Blocked", "application/json", OkResponse},
      bad_request: Schemas.error("Invalid id or cannot block self"),
      unauthorized: Schemas.error("Not authenticated")
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
      ok: {"Unblocked", "application/json", OkResponse},
      bad_request: Schemas.error("Invalid id"),
      unauthorized: Schemas.error("Not authenticated"),
      not_found: Schemas.error("Not found")
    ]
  )

  operation(:delete,
    operation_id: "remove_friendship",
    summary: "Remove/cancel a friendship or request",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]],
    responses: [
      ok: {"Success", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Not authorized, or the request was answered (not_pending)"),
      not_found: Schemas.error("No such friendship or request")
    ]
  )

  # Clarify: the :id path parameter in accept/reject/block/delete/unblock
  # refers to the friendship record ID (friendship_id), not a user_id.

  def create(conn, %{"target_user_id" => _} = params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        target_id = params["target_user_id"]

        case Friends.create_request(user.id, target_id) do
          {:ok, friendship} ->
            reply_data(conn, :created, serialize_request(friendship))

          {:error, %Ecto.Changeset{} = cs} ->
            unprocessable(conn, cs)

          {:error, reason} ->
            reply_reason(conn, reason)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def block(conn, %{"id" => id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          int_id ->
            case Friends.block_friend_request(int_id, user) do
              {:ok, _f} ->
                reply_ok(conn)

              {:error, :not_found} ->
                reply_error(conn, :not_found, "not_found")

              {:error, :not_authorized} ->
                reply_error(conn, :forbidden, "forbidden")

              {:error, :not_pending} ->
                reply_error(conn, :forbidden, "not_pending")
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def blacklist(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        {page, page_size} = Pagination.params(params)

        users = Friends.list_blocked_users(user.id, page: page, page_size: page_size)
        serialized = Enum.map(users, &serialize_user/1)
        total_count = Friends.count_blocked_users(user.id)

        reply_page(conn, serialized, page, page_size, total_count)

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def block_user(conn, %{"user_id" => user_id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(user_id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          target_id ->
            case Friends.block_user(user, target_id) do
              {:ok, _f} ->
                reply_ok(conn)

              {:error, reason} ->
                reply_reason(conn, reason)
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def unblock_user(conn, %{"user_id" => user_id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(user_id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          target_id ->
            case Friends.unblock_user(user, target_id) do
              {:ok, :unblocked} ->
                reply_ok(conn)

              {:error, :not_found} ->
                reply_error(conn, :not_found, "not_found")
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def index(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        {page, page_size} = Pagination.params(params)

        # include the friendship row id so clients can call delete/accept/reject by id
        friends = Friends.list_friends_with_friendship(user.id, page: page, page_size: page_size)
        serialized = Enum.map(friends, &serialize_friend/1)
        total_count = Friends.count_friends_for_user(user.id)

        reply_page(conn, serialized, page, page_size, total_count)

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def blocked(conn, params) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        {page, page_size} = Pagination.params(params)

        blocked = Friends.list_blocked_for_user(user.id, page: page, page_size: page_size)

        serialized =
          Enum.map(blocked, fn f -> %{id: f.id, requester: serialize_user(f.requester)} end)

        total_count = Friends.count_blocked_for_user(user.id)

        reply_page(conn, serialized, page, page_size, total_count)

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def unblock(conn, %{"id" => id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          int_id ->
            case Friends.unblock_friendship(int_id, user) do
              {:ok, :unblocked} ->
                reply_ok(conn)

              {:error, :not_authorized} ->
                reply_error(conn, :forbidden, "forbidden")

              {:error, reason} ->
                reply_reason(conn, reason)
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
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
        reply_pages(
          conn,
          %{incoming: {inc_serialized, total_in}, outgoing: {out_serialized, total_out}},
          page,
          page_size
        )

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def accept(conn, %{"id" => id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          int_id ->
            case Friends.accept_friend_request(int_id, user) do
              {:ok, _f} ->
                reply_ok(conn)

              {:error, :not_authorized} ->
                reply_error(conn, :forbidden, "forbidden")

              {:error, reason} ->
                reply_reason(conn, reason)
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def reject(conn, %{"id" => id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          int_id ->
            case Friends.reject_friend_request(int_id, user) do
              {:ok, _f} ->
                reply_ok(conn)

              {:error, :not_authorized} ->
                reply_error(conn, :forbidden, "forbidden")

              {:error, reason} ->
                reply_reason(conn, reason)
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def delete(conn, %{"id" => id}) do
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        case parse_id(id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          int_id ->
            case Friends.get_friendship(int_id) do
              nil ->
                reply_error(conn, :not_found, "not_found")

              f ->
                handle_delete_friendship(conn, user, f)
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  defp handle_delete_friendship(conn, user, f) do
    cond do
      f.status == FriendshipStatus.pending() and f.requester_id == user.id ->
        case Friends.cancel_request(f.id, user) do
          {:ok, :cancelled} -> reply_ok(conn)
          {:error, reason} -> reply_reason(conn, reason)
        end

      f.status == FriendshipStatus.accepted() and
          (f.requester_id == user.id or f.target_id == user.id) ->
        case Friends.remove_friend(
               user.id,
               if(f.requester_id == user.id, do: f.target_id, else: f.requester_id)
             ) do
          {:ok, _} -> reply_ok(conn)
          {:error, reason} -> reply_reason(conn, reason)
        end

      true ->
        reply_error(conn, :forbidden, "not_authorized")
    end
  end

  # Someone blocked is no friend: what `serialize_friend/1` sends is for friends.
  defp serialize_user(user), do: Serializers.public_brief(user)

  defp serialize_friend(%{friendship_id: fid, user: user}) do
    User.serialize_brief(user) |> Map.put(:friendship_id, fid)
  end

  defp serialize_request(%Friends.Friendship{} = f) do
    requester = brief(f.requester, f.requester_id, f.status)
    target = brief(f.target, f.target_id, f.status)

    %{
      id: f.id,
      requester: requester,
      target: target,
      status: f.status,
      inserted_at: f.inserted_at
    }
  end

  # A side that was not preloaded is sent as a blank member row with its id,
  # built by the same serializer, so it has every field a loaded one has.
  # Anyone can send a request, so a side's metadata waits for the acceptance.
  defp brief(%User{} = user, _id, FriendshipStatus.accepted()), do: User.serialize_brief(user)
  defp brief(%User{} = user, _id, _status), do: Serializers.public_brief(user)
  defp brief(_not_loaded, id, _status), do: User.serialize_brief(%User{id: id})
end
